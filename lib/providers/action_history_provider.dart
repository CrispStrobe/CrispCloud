// lib/providers/action_history_provider.dart
//
// Riverpod provider wrapping ActionHistoryService.
//
// Usage:
//   final history = ref.watch(actionHistoryProvider).history;
//   await ref.read(actionHistoryProvider.notifier).undo(id, panel);

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/action_history_service.dart';
import '../services/log_service.dart';

export '../services/action_history_service.dart'
    show ActionRecord, ActionType, UndoContext, UndoResult;

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class ActionHistoryNotifier extends ChangeNotifier {
  static final _log = Log('ActionHistoryNotifier');

  final _service = ActionHistoryService();

  /// Most-recent actions first.
  List<ActionRecord> get history => _service.history;

  /// Most recent action, or null if history is empty.
  ActionRecord? get lastAction => history.isEmpty ? null : history.first;

  /// Return true if [action] is reversible in the current environment.
  bool canUndo(ActionRecord action) => _service.canUndo(action);

  /// Record a new action and notify listeners.
  ///
  /// Returns the action id.
  String record({
    required ActionType type,
    required String originalPath,
    String? newPath,
    required String provider,
    Map<String, dynamic> metadata = const {},
  }) {
    final id = _service.recordNew(
      type: type,
      originalPath: originalPath,
      newPath: newPath,
      provider: provider,
      metadata: metadata,
    );
    notifyListeners();
    return id;
  }

  /// Undo the action identified by [actionId].
  ///
  /// The caller provides an [UndoContext] with the appropriate remote-operation
  /// callbacks for the active panel.
  ///
  /// Returns the [UndoResult] so the caller can show appropriate feedback.
  Future<UndoResult> undo(String actionId, UndoContext context) async {
    _log.info('Undo requested', {'id': actionId});
    final result = await _service.undo(actionId, context);
    notifyListeners();
    return result;
  }

  /// Undo the most recent action in history.
  Future<UndoResult?> undoLast(UndoContext context) async {
    final last = lastAction;
    if (last == null) return null;
    return undo(last.id, context);
  }

  /// Clear all action history.
  void clear() {
    _service.clear();
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final actionHistoryProvider =
    ChangeNotifierProvider<ActionHistoryNotifier>((ref) {
  return ActionHistoryNotifier();
});
