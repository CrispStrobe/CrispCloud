// lib/services/automation_engine.dart
//
// Automation engine — orchestrates rule execution.
//
// Responsibilities:
//   - Watch directories for FilePatternTrigger rules (desktop only)
//   - Run a per-minute timer for ScheduleTrigger rules
//   - Receive external events for EventTrigger rules via onEvent()
//   - Execute actions: transfer stubs, webhooks, move, delete, runCommand
//   - Maintain an in-memory ring buffer of the last 100 executions

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:watcher/watcher.dart';

import 'automation_rule_service.dart';
import 'log_service.dart';

// ---------------------------------------------------------------------------
// TriggerContext — what fired a rule
// ---------------------------------------------------------------------------

class TriggerContext {
  /// Human-readable label for history.
  final String description;

  /// File that triggered a FilePatternTrigger (may be null).
  final String? filePath;

  /// Event type that triggered an EventTrigger (may be null).
  final AutomationEventType? eventType;

  /// Metadata passed from the caller (e.g. file size, remote path).
  final Map<String, dynamic> metadata;

  const TriggerContext({
    required this.description,
    this.filePath,
    this.eventType,
    this.metadata = const {},
  });
}

// ---------------------------------------------------------------------------
// WebhookExecutor
// ---------------------------------------------------------------------------

class WebhookExecutor {
  static const _log = Log('WebhookExecutor');

  /// Build the JSON payload sent to the webhook endpoint.
  static Map<String, dynamic> buildPayload(
    AutomationRule rule,
    TriggerContext ctx,
  ) {
    return {
      'ruleId': rule.id,
      'ruleName': rule.name,
      'trigger': ctx.description,
      'timestamp': DateTime.now().toIso8601String(),
      if (ctx.filePath != null) 'filePath': ctx.filePath,
      if (ctx.eventType != null) 'eventType': ctx.eventType!.toJson(),
      'metadata': ctx.metadata,
    };
  }

  /// Send the webhook. Returns null on success, error message on failure.
  static Future<String?> send(
    WebhookAction action,
    AutomationRule rule,
    TriggerContext ctx,
  ) async {
    final payload = buildPayload(rule, ctx);
    final body = jsonEncode(payload);

    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...action.headers,
    };

    try {
      final uri = Uri.parse(action.url);
      http.Response response;

      switch (action.method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: body);
          break;
        case 'PATCH':
          response = await http.patch(uri, headers: headers, body: body);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
          break;
        case 'POST':
        default:
          response = await http.post(uri, headers: headers, body: body);
          break;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _log.info(
            'Webhook ${action.method} ${action.url} → ${response.statusCode}');
        return null; // success
      } else {
        final msg =
            'Webhook ${action.method} ${action.url} returned ${response.statusCode}';
        _log.warn(msg);
        return msg;
      }
    } catch (e) {
      final msg = 'Webhook ${action.method} ${action.url} failed: $e';
      _log.error(msg);
      return msg;
    }
  }
}

// ---------------------------------------------------------------------------
// AutomationEngine
// ---------------------------------------------------------------------------

/// Executes automation rules.
///
/// Call [start] once rules are loaded and [stop] on app teardown.
class AutomationEngine {
  static const _log = Log('AutomationEngine');
  static const _historyMax = 100;

  final AutomationRuleService _ruleService;

  // File watchers: directory path → subscription
  final Map<String, StreamSubscription<WatchEvent>> _watchSubs = {};
  final Map<String, DirectoryWatcher> _watchers = {};

  // Schedule timer — fires every minute
  Timer? _scheduleTimer;

  // In-memory execution history (ring buffer)
  final List<AutomationExecution> _history = [];

  // Exposed stream for UI consumers
  final _historyController =
      StreamController<List<AutomationExecution>>.broadcast();

  bool _running = false;

  AutomationEngine(this._ruleService);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start the engine: set up file watchers and the schedule timer.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _log.info('AutomationEngine starting');

    await _refreshWatchers();

    // Schedule runner fires every minute
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _runScheduledRules();
    });

    _log.info('AutomationEngine started');
  }

  /// Stop all watchers and timers.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    _scheduleTimer?.cancel();
    _scheduleTimer = null;

    for (final sub in _watchSubs.values) {
      await sub.cancel();
    }
    _watchSubs.clear();
    _watchers.clear();

    _log.info('AutomationEngine stopped');
  }

  bool get isRunning => _running;

  // ---------------------------------------------------------------------------
  // External event hook
  // ---------------------------------------------------------------------------

  /// Call this from other services (SyncEngine, TransferQueue, etc.) to notify
  /// the automation engine that an event occurred.
  Future<void> onEvent(
    AutomationEventType eventType, {
    String? filePath,
    Map<String, dynamic> metadata = const {},
  }) async {
    if (!_running) return;

    final ctx = TriggerContext(
      description: 'event:${eventType.toJson()}',
      filePath: filePath,
      eventType: eventType,
      metadata: metadata,
    );

    final rules = await _ruleService.getEnabledRules();
    for (final rule in rules) {
      final trigger = rule.trigger;
      if (trigger is EventTrigger && trigger.eventType == eventType) {
        await executeRule(rule, ctx);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Rule refresh / watcher management
  // ---------------------------------------------------------------------------

  /// Re-read rules and update directory watchers accordingly.
  Future<void> _refreshWatchers() async {
    if (kIsWeb) return; // No filesystem watching on web

    final rules = await _ruleService.getEnabledRules();

    // Collect directories that need watching
    final needed = <String>{};
    for (final rule in rules) {
      if (rule.trigger is FilePatternTrigger) {
        needed.add((rule.trigger as FilePatternTrigger).directory);
      }
    }

    // Cancel watchers for directories no longer needed
    for (final dir in _watchSubs.keys.toList()) {
      if (!needed.contains(dir)) {
        await _watchSubs[dir]?.cancel();
        _watchSubs.remove(dir);
        _watchers.remove(dir);
        _log.debug('Removed watcher for $dir');
      }
    }

    // Add new watchers
    for (final dir in needed) {
      if (_watchSubs.containsKey(dir)) continue;
      _startDirectoryWatcher(dir, rules);
    }
  }

  void _startDirectoryWatcher(String directory, List<AutomationRule> rules) {
    try {
      final watcher = DirectoryWatcher(directory);
      _watchers[directory] = watcher;
      _watchSubs[directory] = watcher.events.listen((event) {
        if (event.type == ChangeType.ADD || event.type == ChangeType.MODIFY) {
          _onFileEvent(event.path, rules);
        }
      });
      _log.info('Watching directory: $directory');
    } catch (e) {
      _log.error('Failed to watch directory $directory', e);
    }
  }

  void _onFileEvent(String filePath, List<AutomationRule> rules) {
    for (final rule in rules) {
      if (!rule.enabled) continue;
      final trigger = rule.trigger;
      if (trigger is! FilePatternTrigger) continue;

      // Check that the file lives in the watched directory
      final dir = trigger.directory;
      if (!filePath.startsWith(dir)) continue;

      // Match the glob
      if (!matchesPattern(filePath, trigger.glob)) continue;

      final ctx = TriggerContext(
        description: 'filePattern:${trigger.glob} in $dir',
        filePath: filePath,
        metadata: {'watchedDir': dir, 'glob': trigger.glob},
      );

      // Fire-and-forget (we're in a sync callback)
      unawaited(executeRule(rule, ctx));
    }
  }

  // ---------------------------------------------------------------------------
  // Schedule runner
  // ---------------------------------------------------------------------------

  Future<void> _runScheduledRules() async {
    final rules = await _ruleService.getEnabledRules();
    final now = DateTime.now();

    for (final rule in rules) {
      final trigger = rule.trigger;
      if (trigger is! ScheduleTrigger) continue;

      try {
        final cron = CronParser(trigger.cronExpression);
        if (cron.matches(now)) {
          final ctx = TriggerContext(
            description: 'schedule:${trigger.cronExpression}',
            metadata: {'scheduledAt': now.toIso8601String()},
          );
          unawaited(executeRule(rule, ctx));
        }
      } catch (e) {
        _log.error('Invalid cron in rule ${rule.id}: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Rule execution
  // ---------------------------------------------------------------------------

  /// Execute a single rule with the given [ctx].
  Future<AutomationExecution> executeRule(
    AutomationRule rule,
    TriggerContext ctx,
  ) async {
    final start = DateTime.now();
    _log.info('Executing rule "${rule.name}" (${rule.id}) — ${ctx.description}');

    String? error;
    AutomationStatus status;

    try {
      await _dispatch(rule, ctx);
      status = AutomationStatus.success;
    } catch (e, st) {
      error = e.toString();
      status = AutomationStatus.failure;
      _log.error('Rule "${rule.name}" failed', e, st);
    }

    final exec = AutomationExecution(
      ruleId: rule.id,
      timestamp: start,
      trigger: ctx.description,
      status: status,
      error: error,
      duration: DateTime.now().difference(start),
    );

    _recordExecution(exec);
    return exec;
  }

  Future<void> _dispatch(AutomationRule rule, TriggerContext ctx) async {
    final action = rule.action;

    if (action is WebhookAction) {
      final err = await WebhookExecutor.send(action, rule, ctx);
      if (err != null) throw Exception(err);
      return;
    }

    if (action is TransferAction) {
      await _handleTransfer(rule, action, ctx);
      return;
    }

    if (action is MoveAction) {
      await _handleMove(ctx.filePath, action.destination);
      return;
    }

    if (action is DeleteAction) {
      await _handleDelete(ctx.filePath);
      return;
    }

    if (action is RunCommandAction) {
      await _handleRunCommand(action.command, ctx);
      return;
    }

    throw UnimplementedError('Unknown action type: ${action.runtimeType}');
  }

  /// Transfer handler — in a full implementation this would enqueue a
  /// TransferTask via TransferQueue. Here we log the intent and resolve
  /// conflict policy. Callers can override by wrapping AutomationEngine.
  Future<void> _handleTransfer(
    AutomationRule rule,
    TransferAction action,
    TriggerContext ctx,
  ) async {
    _log.info(
      'Transfer: "${ctx.filePath}" → ${action.destination} '
      'on provider=${action.provider} '
      'conflict=${rule.conflictPolicy.name}',
    );
    // Integration point: real code would call transferQueue.enqueue(...)
    // For now this is a documented hook. Tests can subclass to override.
    await onTransferRequested(rule, action, ctx);
  }

  /// Move handler — local filesystem move (desktop only).
  Future<void> _handleMove(String? sourcePath, String destination) async {
    if (sourcePath == null) {
      throw ArgumentError('MoveAction requires a filePath in TriggerContext');
    }
    if (kIsWeb) {
      _log.warn('MoveAction not supported on web');
      return;
    }
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw FileSystemException('Source file not found', sourcePath);
    }
    final dst = File(destination);
    await dst.parent.create(recursive: true);
    await src.rename(dst.path);
    _log.info('Moved $sourcePath → $destination');
  }

  /// Delete handler — local filesystem delete (desktop only).
  Future<void> _handleDelete(String? filePath) async {
    if (filePath == null) {
      throw ArgumentError('DeleteAction requires a filePath in TriggerContext');
    }
    if (kIsWeb) {
      _log.warn('DeleteAction not supported on web');
      return;
    }
    final f = File(filePath);
    if (await f.exists()) {
      await f.delete();
      _log.info('Deleted $filePath');
    }
  }

  /// RunCommandAction handler — desktop only.
  Future<void> _handleRunCommand(String command, TriggerContext ctx) async {
    if (kIsWeb) {
      _log.warn('RunCommandAction not supported on web');
      return;
    }
    final args = command.split(RegExp(r'\s+'));
    final executable = args.first;
    final rest = args.skip(1).toList();
    if (ctx.filePath != null) rest.add(ctx.filePath!);

    _log.info('RunCommand: $executable ${rest.join(' ')}');
    final result = await Process.run(executable, rest);
    if (result.exitCode != 0) {
      throw Exception(
          'Command "$command" exited with ${result.exitCode}: ${result.stderr}');
    }
  }

  // ---------------------------------------------------------------------------
  // Override hook for transfer integration
  // ---------------------------------------------------------------------------

  /// Override in subclasses (or via composition) to hook into the actual
  /// TransferQueue when a TransferAction fires.
  Future<void> onTransferRequested(
    AutomationRule rule,
    TransferAction action,
    TriggerContext ctx,
  ) async {
    // Default: no-op. Subclasses or wrappers provide real implementation.
  }

  // ---------------------------------------------------------------------------
  // Execution history
  // ---------------------------------------------------------------------------

  void _recordExecution(AutomationExecution exec) {
    if (_history.length >= _historyMax) {
      _history.removeAt(0);
    }
    _history.add(exec);
    _historyController.add(List.unmodifiable(_history));
  }

  /// Snapshot of the last [_historyMax] executions (most recent last).
  List<AutomationExecution> get executionHistory =>
      List.unmodifiable(_history);

  /// Stream of history snapshots — emits after every execution.
  Stream<List<AutomationExecution>> get historyStream =>
      _historyController.stream;

  /// Executions for a specific rule id.
  List<AutomationExecution> historyForRule(String ruleId) =>
      _history.where((e) => e.ruleId == ruleId).toList();

  /// Clear the in-memory history.
  void clearHistory() {
    _history.clear();
    _historyController.add(const []);
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await stop();
    await _historyController.close();
  }
}
