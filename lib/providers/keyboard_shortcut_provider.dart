// lib/providers/keyboard_shortcut_provider.dart
//
// Riverpod providers for the rebindable keyboard shortcut system.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/keyboard_shortcut_service.dart';

// ---------------------------------------------------------------------------
// Service singleton
// ---------------------------------------------------------------------------

/// Singleton [KeyboardShortcutService].
///
/// The service is created immediately; call [KeyboardShortcutService.load]
/// during app startup (or after this provider is first read) to hydrate
/// custom bindings from SharedPreferences.
final keyboardShortcutServiceProvider =
    Provider<KeyboardShortcutService>((ref) {
  final svc = KeyboardShortcutService();
  // Kick off async load; the service updates in place and
  // ShortcutBindingsNotifier re-reads on next access.
  svc.load();
  return svc;
});

// ---------------------------------------------------------------------------
// StateNotifier
// ---------------------------------------------------------------------------

/// Notifier that holds the full map of current bindings and exposes mutation
/// operations that keep the map in sync with the persisted service state.
class ShortcutBindingsNotifier
    extends StateNotifier<Map<ShortcutAction, ShortcutBinding>> {
  ShortcutBindingsNotifier(this._service)
      : super(_service.getBindings());

  final KeyboardShortcutService _service;

  void _refresh() => state = _service.getBindings();

  Future<void> setBinding(ShortcutAction action, ShortcutBinding binding) async {
    await _service.setBinding(action, binding);
    _refresh();
  }

  Future<void> resetBinding(ShortcutAction action) async {
    await _service.resetBinding(action);
    _refresh();
  }

  Future<void> resetAll() async {
    await _service.resetAll();
    _refresh();
  }

  Future<void> importBindings(String jsonStr) async {
    await _service.importBindings(jsonStr);
    _refresh();
  }

  /// Export current custom bindings as a JSON string.
  String exportBindings() => _service.exportBindings();

  /// Whether [binding] conflicts with an existing action.
  bool isConflict(ShortcutBinding binding) => _service.isConflict(binding);

  /// All actions that share [binding].
  List<ShortcutAction> getConflicts(ShortcutBinding binding) =>
      _service.getConflicts(binding);
}

/// StateNotifier provider for the complete bindings map.
final shortcutBindingsProvider = StateNotifierProvider<ShortcutBindingsNotifier,
    Map<ShortcutAction, ShortcutBinding>>(
  (ref) {
    final svc = ref.watch(keyboardShortcutServiceProvider);
    return ShortcutBindingsNotifier(svc);
  },
);

// ---------------------------------------------------------------------------
// Family provider — display string per action
// ---------------------------------------------------------------------------

/// Returns the human-readable display string for [action]'s current binding,
/// e.g. "Ctrl+Shift+P".
final shortcutDisplayProvider =
    Provider.family<String, ShortcutAction>((ref, action) {
  final bindings = ref.watch(shortcutBindingsProvider);
  final binding = bindings[action];
  return binding?.toDisplayString() ?? '';
});
