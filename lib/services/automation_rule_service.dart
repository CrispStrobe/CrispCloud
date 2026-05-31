// lib/services/automation_rule_service.dart
//
// Automation & Rules engine data layer.
//
// Provides:
//   - AutomationRule model with sealed trigger/action types
//   - CronParser for simple 5-field cron expressions
//   - AutomationRuleService for CRUD + SharedPreferences persistence
//   - matchesPattern() glob helper

import 'dart:convert';

import 'package:glob/glob.dart' as globpkg;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum ConflictPolicy {
  skip,
  overwrite,
  rename,
  newestWins,
  askUser,
}

enum AutomationStatus {
  success,
  failure,
  skipped,
}

enum AutomationEventType {
  uploadComplete,
  downloadComplete,
  syncComplete,
  error,
}

extension AutomationEventTypeJson on AutomationEventType {
  String toJson() {
    switch (this) {
      case AutomationEventType.uploadComplete:
        return 'upload_complete';
      case AutomationEventType.downloadComplete:
        return 'download_complete';
      case AutomationEventType.syncComplete:
        return 'sync_complete';
      case AutomationEventType.error:
        return 'error';
    }
  }

  static AutomationEventType fromJson(String s) {
    switch (s) {
      case 'upload_complete':
        return AutomationEventType.uploadComplete;
      case 'download_complete':
        return AutomationEventType.downloadComplete;
      case 'sync_complete':
        return AutomationEventType.syncComplete;
      case 'error':
        return AutomationEventType.error;
      default:
        throw ArgumentError('Unknown AutomationEventType: $s');
    }
  }
}

// ---------------------------------------------------------------------------
// Sealed trigger hierarchy
// ---------------------------------------------------------------------------

sealed class AutomationTrigger {
  const AutomationTrigger();

  Map<String, dynamic> toJson();

  static AutomationTrigger fromJson(Map<String, dynamic> map) {
    final type = map['type'] as String;
    switch (type) {
      case 'filePattern':
        return FilePatternTrigger(
          directory: map['directory'] as String,
          glob: map['glob'] as String,
        );
      case 'schedule':
        return ScheduleTrigger(
          cronExpression: map['cronExpression'] as String,
        );
      case 'event':
        return EventTrigger(
          eventType: AutomationEventTypeJson.fromJson(map['eventType'] as String),
        );
      default:
        throw ArgumentError('Unknown trigger type: $type');
    }
  }
}

/// Triggers when a file matching [glob] appears in [directory].
class FilePatternTrigger extends AutomationTrigger {
  final String directory;
  final String glob;

  const FilePatternTrigger({required this.directory, required this.glob});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'filePattern',
        'directory': directory,
        'glob': glob,
      };

  @override
  String toString() => 'FilePatternTrigger(dir=$directory, glob=$glob)';
}

/// Triggers on a cron schedule.
class ScheduleTrigger extends AutomationTrigger {
  final String cronExpression;

  const ScheduleTrigger({required this.cronExpression});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'schedule',
        'cronExpression': cronExpression,
      };

  @override
  String toString() => 'ScheduleTrigger($cronExpression)';
}

/// Triggers when an [eventType] is emitted by the engine.
class EventTrigger extends AutomationTrigger {
  final AutomationEventType eventType;

  const EventTrigger({required this.eventType});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'event',
        'eventType': eventType.toJson(),
      };

  @override
  String toString() => 'EventTrigger(${eventType.toJson()})';
}

// ---------------------------------------------------------------------------
// Sealed action hierarchy
// ---------------------------------------------------------------------------

sealed class AutomationAction {
  const AutomationAction();

  Map<String, dynamic> toJson();

  static AutomationAction fromJson(Map<String, dynamic> map) {
    final type = map['type'] as String;
    switch (type) {
      case 'transfer':
        return TransferAction(
          destination: map['destination'] as String,
          provider: map['provider'] as String,
        );
      case 'webhook':
        return WebhookAction(
          url: map['url'] as String,
          method: map['method'] as String? ?? 'POST',
          headers: (map['headers'] as Map<String, dynamic>?)
                  ?.map((k, v) => MapEntry(k, v as String)) ??
              {},
        );
      case 'move':
        return MoveAction(destination: map['destination'] as String);
      case 'delete':
        return const DeleteAction();
      case 'runCommand':
        return RunCommandAction(command: map['command'] as String);
      default:
        throw ArgumentError('Unknown action type: $type');
    }
  }
}

/// Upload/download to a remote [provider] at [destination].
class TransferAction extends AutomationAction {
  final String destination;
  final String provider;

  const TransferAction({required this.destination, required this.provider});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'transfer',
        'destination': destination,
        'provider': provider,
      };

  @override
  String toString() => 'TransferAction(dest=$destination, provider=$provider)';
}

/// Send an HTTP request to [url].
class WebhookAction extends AutomationAction {
  final String url;
  final String method; // 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'
  final Map<String, String> headers;

  const WebhookAction({
    required this.url,
    this.method = 'POST',
    this.headers = const {},
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'webhook',
        'url': url,
        'method': method,
        'headers': headers,
      };

  @override
  String toString() => 'WebhookAction($method $url)';
}

/// Move matched file to [destination].
class MoveAction extends AutomationAction {
  final String destination;

  const MoveAction({required this.destination});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'move',
        'destination': destination,
      };

  @override
  String toString() => 'MoveAction(dest=$destination)';
}

/// Delete matched file.
class DeleteAction extends AutomationAction {
  const DeleteAction();

  @override
  Map<String, dynamic> toJson() => {'type': 'delete'};

  @override
  String toString() => 'DeleteAction()';
}

/// Run a shell command on desktop (filename is passed as first argument).
class RunCommandAction extends AutomationAction {
  final String command;

  const RunCommandAction({required this.command});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'runCommand',
        'command': command,
      };

  @override
  String toString() => 'RunCommandAction($command)';
}

// ---------------------------------------------------------------------------
// AutomationRule model
// ---------------------------------------------------------------------------

class AutomationRule {
  final String id;
  final String name;
  final bool enabled;
  final AutomationTrigger trigger;
  final AutomationAction action;

  /// Optional source path hint (for UI display / documentation).
  final String source;

  /// Destination path string (may overlap with action.destination).
  final String destination;

  /// Target provider name.
  final String provider;

  /// Glob pattern for file matching (on top of trigger glob, if any).
  final String filePattern;

  final ConflictPolicy conflictPolicy;
  final DateTime createdAt;

  const AutomationRule({
    required this.id,
    required this.name,
    this.enabled = true,
    required this.trigger,
    required this.action,
    this.source = '',
    this.destination = '',
    this.provider = '',
    this.filePattern = '*',
    this.conflictPolicy = ConflictPolicy.skip,
    required this.createdAt,
  });

  AutomationRule copyWith({
    String? id,
    String? name,
    bool? enabled,
    AutomationTrigger? trigger,
    AutomationAction? action,
    String? source,
    String? destination,
    String? provider,
    String? filePattern,
    ConflictPolicy? conflictPolicy,
    DateTime? createdAt,
  }) {
    return AutomationRule(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      trigger: trigger ?? this.trigger,
      action: action ?? this.action,
      source: source ?? this.source,
      destination: destination ?? this.destination,
      provider: provider ?? this.provider,
      filePattern: filePattern ?? this.filePattern,
      conflictPolicy: conflictPolicy ?? this.conflictPolicy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'trigger': trigger.toJson(),
        'action': action.toJson(),
        'source': source,
        'destination': destination,
        'provider': provider,
        'filePattern': filePattern,
        'conflictPolicy': conflictPolicy.name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AutomationRule.fromJson(Map<String, dynamic> map) {
    return AutomationRule(
      id: map['id'] as String,
      name: map['name'] as String,
      enabled: map['enabled'] as bool? ?? true,
      trigger: AutomationTrigger.fromJson(
          Map<String, dynamic>.from(map['trigger'] as Map)),
      action: AutomationAction.fromJson(
          Map<String, dynamic>.from(map['action'] as Map)),
      source: map['source'] as String? ?? '',
      destination: map['destination'] as String? ?? '',
      provider: map['provider'] as String? ?? '',
      filePattern: map['filePattern'] as String? ?? '*',
      conflictPolicy: ConflictPolicy.values.firstWhere(
        (e) => e.name == (map['conflictPolicy'] as String? ?? 'skip'),
        orElse: () => ConflictPolicy.skip,
      ),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  @override
  String toString() => 'AutomationRule(id=$id, name=$name, enabled=$enabled)';

  @override
  bool operator ==(Object other) =>
      other is AutomationRule && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// ---------------------------------------------------------------------------
// AutomationExecution — execution history record
// ---------------------------------------------------------------------------

class AutomationExecution {
  final String ruleId;
  final DateTime timestamp;
  final String trigger;  // human-readable description of what fired
  final AutomationStatus status;
  final String? error;
  final Duration duration;

  const AutomationExecution({
    required this.ruleId,
    required this.timestamp,
    required this.trigger,
    required this.status,
    this.error,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'timestamp': timestamp.toIso8601String(),
        'trigger': trigger,
        'status': status.name,
        'error': error,
        'durationMs': duration.inMilliseconds,
      };

  factory AutomationExecution.fromJson(Map<String, dynamic> map) {
    return AutomationExecution(
      ruleId: map['ruleId'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      trigger: map['trigger'] as String,
      status: AutomationStatus.values.firstWhere(
        (e) => e.name == (map['status'] as String),
        orElse: () => AutomationStatus.failure,
      ),
      error: map['error'] as String?,
      duration: Duration(milliseconds: (map['durationMs'] as int?) ?? 0),
    );
  }
}

// ---------------------------------------------------------------------------
// CronParser — parse 5-field cron expressions
// ---------------------------------------------------------------------------

/// Simple cron parser supporting the standard 5-field format:
///   minute  hour  dayOfMonth  month  dayOfWeek
///
/// Supported syntax per field:
///   *           = every value
///   N           = exact value
///   */N         = every N steps (starting from the field minimum)
///   N,M,...     = list of values
///   N-M         = range (inclusive)
class CronParser {
  final String expression;
  late final List<int> _minutes;
  late final List<int> _hours;
  late final List<int> _daysOfMonth;
  late final List<int> _months;
  late final List<int> _daysOfWeek;

  CronParser(this.expression) {
    final parts = expression.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) {
      throw ArgumentError(
          'Cron expression must have exactly 5 fields: "$expression"');
    }
    _minutes = _parseField(parts[0], 0, 59);
    _hours = _parseField(parts[1], 0, 23);
    _daysOfMonth = _parseField(parts[2], 1, 31);
    _months = _parseField(parts[3], 1, 12);
    _daysOfWeek = _parseField(parts[4], 0, 6);
  }

  static List<int> _parseField(String field, int min, int max) {
    if (field == '*') {
      return List<int>.generate(max - min + 1, (i) => min + i);
    }

    // */N — step
    if (field.startsWith('*/')) {
      final step = int.parse(field.substring(2));
      if (step <= 0) throw ArgumentError('Step must be > 0: $field');
      return [for (int v = min; v <= max; v += step) v];
    }

    // comma-separated list (may contain ranges)
    if (field.contains(',')) {
      final result = <int>{};
      for (final part in field.split(',')) {
        result.addAll(_parseSimple(part, min, max));
      }
      return result.toList()..sort();
    }

    return _parseSimple(field, min, max);
  }

  static List<int> _parseSimple(String field, int min, int max) {
    // N-M range
    if (field.contains('-')) {
      final parts = field.split('-');
      final from = int.parse(parts[0]);
      final to = int.parse(parts[1]);
      _assertRange(from, min, max, field);
      _assertRange(to, min, max, field);
      return List<int>.generate(to - from + 1, (i) => from + i);
    }
    // exact value
    final v = int.parse(field);
    _assertRange(v, min, max, field);
    return [v];
  }

  static void _assertRange(int value, int min, int max, String field) {
    if (value < min || value > max) {
      throw ArgumentError('Value $value out of range [$min,$max] in "$field"');
    }
  }

  /// Whether [dt] matches this cron expression.
  bool matches(DateTime dt) {
    return _minutes.contains(dt.minute) &&
        _hours.contains(dt.hour) &&
        _daysOfMonth.contains(dt.day) &&
        _months.contains(dt.month) &&
        _daysOfWeek.contains(dt.weekday % 7); // Dart weekday: Mon=1..Sun=7 → Sun=0..Sat=6
  }

  /// Compute the next run time at or after [from], scanning minute by minute
  /// up to [maxSearchDays] days ahead.
  DateTime? nextRunAfter(DateTime from, {int maxSearchDays = 366}) {
    // Round up to the next minute boundary
    var candidate = DateTime(
        from.year, from.month, from.day, from.hour, from.minute)
        .add(const Duration(minutes: 1));

    final limit = from.add(Duration(days: maxSearchDays));

    while (candidate.isBefore(limit)) {
      if (matches(candidate)) return candidate;
      candidate = candidate.add(const Duration(minutes: 1));
    }
    return null;
  }

  /// List of valid minute values.
  List<int> get minutes => List.unmodifiable(_minutes);

  /// List of valid hour values.
  List<int> get hours => List.unmodifiable(_hours);

  /// List of valid day-of-month values.
  List<int> get daysOfMonth => List.unmodifiable(_daysOfMonth);

  /// List of valid month values.
  List<int> get months => List.unmodifiable(_months);

  /// List of valid day-of-week values (0=Sunday … 6=Saturday).
  List<int> get daysOfWeek => List.unmodifiable(_daysOfWeek);
}

// ---------------------------------------------------------------------------
// matchesPattern — glob helper
// ---------------------------------------------------------------------------

/// Returns true if [filename] (or path) matches the [globPattern].
///
/// Uses package:glob for full glob support (*, **, ?, character classes).
/// The match is performed on just the basename unless the pattern contains
/// a path separator.
bool matchesPattern(String filename, String globPattern) {
  try {
    final g = globpkg.Glob(globPattern);
    // If the pattern has no path components, match against just the basename
    if (!globPattern.contains('/') && !globPattern.contains('\\')) {
      return g.matches(p.basename(filename));
    }
    return g.matches(filename);
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// AutomationRuleService — CRUD + persistence
// ---------------------------------------------------------------------------

class AutomationRuleService {
  static const _log = Log('AutomationRuleService');
  static const _prefsKey = 'automation_rules_v1';

  List<AutomationRule> _rules = [];
  bool _loaded = false;

  // --- Lifecycle ---

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    await _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        _rules = list
            .map((e) => AutomationRule.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
        _log.info('Loaded ${_rules.length} automation rules');
      }
    } catch (e, st) {
      _log.error('Failed to load automation rules', e, st);
      _rules = [];
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_rules.map((r) => r.toJson()).toList());
      await prefs.setString(_prefsKey, encoded);
    } catch (e, st) {
      _log.error('Failed to persist automation rules', e, st);
    }
  }

  // --- Validation ---

  /// Returns an error string if the rule is invalid, or null if valid.
  String? validate(AutomationRule rule) {
    if (rule.id.isEmpty) return 'Rule id must not be empty';
    if (rule.name.isEmpty) return 'Rule name must not be empty';

    // Validate trigger
    final trigger = rule.trigger;
    if (trigger is FilePatternTrigger) {
      if (trigger.directory.isEmpty) return 'FilePatternTrigger.directory must not be empty';
      if (trigger.glob.isEmpty) return 'FilePatternTrigger.glob must not be empty';
    } else if (trigger is ScheduleTrigger) {
      try {
        CronParser(trigger.cronExpression);
      } catch (e) {
        return 'Invalid cron expression: $e';
      }
    }

    // Validate action
    final action = rule.action;
    if (action is TransferAction) {
      if (action.destination.isEmpty) return 'TransferAction.destination must not be empty';
      if (action.provider.isEmpty) return 'TransferAction.provider must not be empty';
    } else if (action is WebhookAction) {
      if (action.url.isEmpty) return 'WebhookAction.url must not be empty';
      if (!action.url.startsWith('http')) return 'WebhookAction.url must start with http';
    } else if (action is MoveAction) {
      if (action.destination.isEmpty) return 'MoveAction.destination must not be empty';
    } else if (action is RunCommandAction) {
      if (action.command.isEmpty) return 'RunCommandAction.command must not be empty';
    }

    return null; // valid
  }

  // --- CRUD ---

  Future<List<AutomationRule>> getRules() async {
    await _ensureLoaded();
    return List.unmodifiable(_rules);
  }

  Future<AutomationRule?> getRule(String id) async {
    await _ensureLoaded();
    try {
      return _rules.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Add a new rule. Throws [ArgumentError] if validation fails or id already exists.
  Future<void> addRule(AutomationRule rule) async {
    await _ensureLoaded();

    final error = validate(rule);
    if (error != null) throw ArgumentError(error);

    if (_rules.any((r) => r.id == rule.id)) {
      throw ArgumentError('Rule with id "${rule.id}" already exists');
    }

    _rules.add(rule);
    await _persist();
    _log.info('Added automation rule "${rule.name}" (${rule.id})');
  }

  /// Remove rule by id. No-op if not found.
  Future<void> removeRule(String id) async {
    await _ensureLoaded();
    final before = _rules.length;
    _rules.removeWhere((r) => r.id == id);
    if (_rules.length < before) {
      await _persist();
      _log.info('Removed automation rule $id');
    }
  }

  /// Update an existing rule. Throws [ArgumentError] if not found or validation fails.
  Future<void> updateRule(AutomationRule updated) async {
    await _ensureLoaded();

    final error = validate(updated);
    if (error != null) throw ArgumentError(error);

    final idx = _rules.indexWhere((r) => r.id == updated.id);
    if (idx < 0) {
      throw ArgumentError('Rule "${updated.id}" not found');
    }

    _rules[idx] = updated;
    await _persist();
    _log.info('Updated automation rule "${updated.name}" (${updated.id})');
  }

  /// Enable or disable a rule by id.
  Future<void> setEnabled(String id, {required bool enabled}) async {
    await _ensureLoaded();
    final idx = _rules.indexWhere((r) => r.id == id);
    if (idx < 0) throw ArgumentError('Rule "$id" not found');
    _rules[idx] = _rules[idx].copyWith(enabled: enabled);
    await _persist();
  }

  /// Return all enabled rules.
  Future<List<AutomationRule>> getEnabledRules() async {
    await _ensureLoaded();
    return _rules.where((r) => r.enabled).toList();
  }

  /// Clear all rules (used in tests / reset).
  Future<void> clearAll() async {
    _rules = [];
    _loaded = true;
    await _persist();
  }
}
