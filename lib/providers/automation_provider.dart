// lib/providers/automation_provider.dart
//
// Riverpod providers for the Automation & Rules engine.
//
//   automationRulesProvider  — StateNotifier wrapping AutomationRuleService
//   automationEngineProvider — manages engine lifecycle (ChangeNotifier)
//   automationHistoryProvider — most recent 100 executions

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/automation_engine.dart';
import '../services/automation_rule_service.dart';
import '../services/log_service.dart';

// ---------------------------------------------------------------------------
// automationRulesProvider
// ---------------------------------------------------------------------------

class AutomationRulesNotifier extends StateNotifier<List<AutomationRule>> {
  static const _log = Log('AutomationRulesNotifier');

  final AutomationRuleService _service;

  AutomationRulesNotifier(this._service) : super(const []) {
    _load();
  }

  Future<void> _load() async {
    try {
      final rules = await _service.getRules();
      state = rules.toList();
    } catch (e) {
      _log.error('Failed to load rules', e);
    }
  }

  /// Add a new rule.
  Future<void> addRule(AutomationRule rule) async {
    await _service.addRule(rule);
    await _load();
  }

  /// Remove rule by id.
  Future<void> removeRule(String id) async {
    await _service.removeRule(id);
    await _load();
  }

  /// Update an existing rule.
  Future<void> updateRule(AutomationRule rule) async {
    await _service.updateRule(rule);
    await _load();
  }

  /// Enable or disable a rule.
  Future<void> setEnabled(String id, {required bool enabled}) async {
    await _service.setEnabled(id, enabled: enabled);
    await _load();
  }

  /// Reload rules from persistent storage.
  Future<void> refresh() async => _load();

  /// Validate a rule before saving.
  String? validate(AutomationRule rule) => _service.validate(rule);
}

final automationRulesProvider =
    StateNotifierProvider<AutomationRulesNotifier, List<AutomationRule>>((ref) {
  return AutomationRulesNotifier(AutomationRuleService());
});

// ---------------------------------------------------------------------------
// automationEngineProvider
// ---------------------------------------------------------------------------

class AutomationEngineNotifier extends ChangeNotifier {
  static const _log = Log('AutomationEngineNotifier');

  late final AutomationEngine _engine;
  bool _initialized = false;

  AutomationEngineNotifier() {
    _engine = AutomationEngine(AutomationRuleService());
  }

  AutomationEngine get engine => _engine;
  bool get isRunning => _engine.isRunning;

  /// Start the engine (idempotent).
  Future<void> start() async {
    await _engine.start();
    _initialized = true;
    notifyListeners();
    _log.info('AutomationEngine started via provider');
  }

  /// Stop the engine.
  Future<void> stop() async {
    await _engine.stop();
    notifyListeners();
    _log.info('AutomationEngine stopped via provider');
  }

  /// Notify the engine that an event occurred.
  Future<void> onEvent(
    AutomationEventType eventType, {
    String? filePath,
    Map<String, dynamic> metadata = const {},
  }) async {
    if (!_initialized) return;
    await _engine.onEvent(eventType, filePath: filePath, metadata: metadata);
    notifyListeners();
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }
}

final automationEngineProvider =
    ChangeNotifierProvider<AutomationEngineNotifier>((ref) {
  return AutomationEngineNotifier();
});

// ---------------------------------------------------------------------------
// automationHistoryProvider
// ---------------------------------------------------------------------------

/// Exposes the live execution history stream as an [AsyncValue].
///
/// Rebuilds the widget tree whenever a new execution is recorded.
final automationHistoryProvider =
    StreamProvider<List<AutomationExecution>>((ref) {
  final engine = ref.watch(automationEngineProvider).engine;
  return engine.historyStream;
});

/// Synchronous snapshot of the history (does not rebuild on updates).
final automationHistorySnapshotProvider =
    Provider<List<AutomationExecution>>((ref) {
  final engine = ref.watch(automationEngineProvider).engine;
  return engine.executionHistory;
});
