// lib/services/keyboard_shortcut_service.dart
//
// Rebindable keyboard shortcut service.
// Stores custom bindings in SharedPreferences as JSON.

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// ShortcutAction
// ---------------------------------------------------------------------------

/// All bindable shortcut actions in CrispCloud.
enum ShortcutAction {
  newTab,
  closeTab,
  nextTab,
  prevTab,
  commandPalette,
  goToFolder,
  filter,
  selectAll,
  delete,
  rename,
  newFolder,
  refresh,
  preview,
  edit,
  undo,
  redo,
  switchPanel,
  copy,
  paste,
  cut,
  toggleTreeView,
  cycleLayout,
  search,
  findPattern,
}

// ---------------------------------------------------------------------------
// ShortcutBinding
// ---------------------------------------------------------------------------

/// A key combination bound to a [ShortcutAction].
class ShortcutBinding {
  /// The logical key label as returned by [LogicalKeyboardKey.keyLabel].
  /// Must be non-empty.
  final String key;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  const ShortcutBinding({
    required this.key,
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  /// Returns false when the key label is empty (modifier-only bindings are
  /// considered invalid).
  bool get isValid => key.trim().isNotEmpty;

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'key': key,
        'ctrl': ctrl,
        'shift': shift,
        'alt': alt,
        'meta': meta,
      };

  factory ShortcutBinding.fromJson(Map<String, dynamic> json) =>
      ShortcutBinding(
        key: (json['key'] as String?) ?? '',
        ctrl: (json['ctrl'] as bool?) ?? false,
        shift: (json['shift'] as bool?) ?? false,
        alt: (json['alt'] as bool?) ?? false,
        meta: (json['meta'] as bool?) ?? false,
      );

  // -------------------------------------------------------------------------
  // Matching
  // -------------------------------------------------------------------------

  /// Returns true when [event] together with the live modifier state matches
  /// this binding.
  bool matches(
    KeyEvent event, {
    required bool isCtrl,
    required bool isShift,
    required bool isAlt,
    required bool isMeta,
  }) {
    if (event is! KeyDownEvent) return false;
    if (ctrl != isCtrl) return false;
    if (shift != isShift) return false;
    if (alt != isAlt) return false;
    if (meta != isMeta) return false;
    // Normalise both sides so that stored 'Space' matches keyLabel ' ', etc.
    return _normaliseForMatch(event.logicalKey.keyLabel) ==
        _normaliseForMatch(key);
  }

  /// Canonicalises a key label for comparison purposes (case-insensitive,
  /// space-character ↔ "space" equivalence, etc.).
  static String _normaliseForMatch(String raw) {
    // Check for space before trimming (trim would eat it).
    if (raw == ' ' || raw.toLowerCase().trim() == 'space') return 'space';
    return raw.toLowerCase().trim();
  }

  // -------------------------------------------------------------------------
  // Display
  // -------------------------------------------------------------------------

  /// Platform-aware human-readable string, e.g. "Ctrl+Shift+P" or "⌘T".
  String toDisplayString() {
    final parts = <String>[];

    final isMacLike = !kIsWeb &&
        (Platform.isMacOS || Platform.isIOS);

    if (ctrl) parts.add(isMacLike ? '⌃' : 'Ctrl');
    if (alt) parts.add(isMacLike ? '⌥' : 'Alt');
    if (shift) parts.add(isMacLike ? '⇧' : 'Shift');
    if (meta) parts.add(isMacLike ? '⌘' : 'Meta');

    // Normalise well-known key labels.
    final label = _normaliseKeyLabel(key);
    parts.add(label);

    return parts.join(isMacLike ? '' : '+');
  }

  static String _normaliseKeyLabel(String raw) {
    switch (raw.toLowerCase()) {
      case ' ':
      case 'space':
        return 'Space';
      case 'escape':
        return 'Esc';
      case 'delete':
        return 'Del';
      case 'backspace':
        return '⌫';
      case 'tab':
        return 'Tab';
      case 'enter':
        return '↵';
      default:
        // F-keys and single letters: capitalise first letter only.
        return raw.length == 1 ? raw.toUpperCase() : raw;
    }
  }

  // -------------------------------------------------------------------------
  // Equality / hashCode
  // -------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      other is ShortcutBinding &&
      key.toLowerCase() == other.key.toLowerCase() &&
      ctrl == other.ctrl &&
      shift == other.shift &&
      alt == other.alt &&
      meta == other.meta;

  @override
  int get hashCode => Object.hash(key.toLowerCase(), ctrl, shift, alt, meta);

  @override
  String toString() => toDisplayString();
}

// ---------------------------------------------------------------------------
// KeyboardShortcutService
// ---------------------------------------------------------------------------

/// Manages rebindable keyboard shortcuts.
///
/// Custom bindings override defaults and are persisted in [SharedPreferences]
/// under the key [_prefsKey].
class KeyboardShortcutService {
  static const _prefsKey = 'keyboard_shortcuts';

  // -------------------------------------------------------------------------
  // Default bindings (matching the hardcoded values in keyboard_shortcuts.dart)
  // -------------------------------------------------------------------------

  static final Map<ShortcutAction, ShortcutBinding> _defaults = {
    ShortcutAction.newTab: const ShortcutBinding(key: 'T', ctrl: true),
    ShortcutAction.closeTab: const ShortcutBinding(key: 'W', ctrl: true),
    ShortcutAction.nextTab: const ShortcutBinding(key: 'Tab', ctrl: true),
    ShortcutAction.prevTab:
        const ShortcutBinding(key: 'Tab', ctrl: true, shift: true),
    ShortcutAction.commandPalette:
        const ShortcutBinding(key: 'P', ctrl: true, shift: true),
    ShortcutAction.goToFolder: const ShortcutBinding(key: 'G', ctrl: true),
    ShortcutAction.filter: const ShortcutBinding(key: 'F', ctrl: true),
    ShortcutAction.selectAll: const ShortcutBinding(key: 'A', ctrl: true),
    ShortcutAction.delete: const ShortcutBinding(key: 'Delete'),
    ShortcutAction.rename: const ShortcutBinding(key: 'F2'),
    ShortcutAction.newFolder: const ShortcutBinding(key: 'N', ctrl: true),
    ShortcutAction.refresh: const ShortcutBinding(key: 'F5'),
    ShortcutAction.preview: const ShortcutBinding(key: 'Space'),
    ShortcutAction.edit:
        const ShortcutBinding(key: 'E', ctrl: true),
    ShortcutAction.undo: const ShortcutBinding(key: 'Z', ctrl: true),
    ShortcutAction.redo:
        const ShortcutBinding(key: 'Z', ctrl: true, shift: true),
    ShortcutAction.switchPanel: const ShortcutBinding(key: 'Tab'),
    ShortcutAction.copy: const ShortcutBinding(key: 'C', ctrl: true),
    ShortcutAction.paste: const ShortcutBinding(key: 'V', ctrl: true),
    ShortcutAction.cut: const ShortcutBinding(key: 'X', ctrl: true),
    ShortcutAction.toggleTreeView:
        const ShortcutBinding(key: 'B', ctrl: true),
    ShortcutAction.cycleLayout:
        const ShortcutBinding(key: 'L', ctrl: true, shift: true),
    ShortcutAction.search: const ShortcutBinding(key: 'K', ctrl: true),
    ShortcutAction.findPattern:
        const ShortcutBinding(key: 'H', ctrl: true, shift: true),
  };

  /// Custom bindings loaded from / persisted to SharedPreferences.
  final Map<ShortcutAction, ShortcutBinding> _custom = {};

  // -------------------------------------------------------------------------
  // Initialisation
  // -------------------------------------------------------------------------

  /// Load persisted custom bindings.  Call once during app startup.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final map = json.decode(raw) as Map<String, dynamic>;
      _custom.clear();
      for (final entry in map.entries) {
        final action = _actionFromName(entry.key);
        if (action == null) continue;
        final binding =
            ShortcutBinding.fromJson(entry.value as Map<String, dynamic>);
        if (binding.isValid) {
          _custom[action] = binding;
        }
      }
    } catch (_) {
      // Corrupt prefs — silently ignore and use defaults.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{
        for (final e in _custom.entries) e.key.name: e.value.toJson(),
      };
      await prefs.setString(_prefsKey, json.encode(map));
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Returns all current bindings (custom overrides merged over defaults).
  Map<ShortcutAction, ShortcutBinding> getBindings() {
    return {
      ..._defaults,
      ..._custom,
    };
  }

  /// Returns the current binding for [action].
  ShortcutBinding getBinding(ShortcutAction action) =>
      _custom[action] ?? _defaults[action]!;

  /// Persists [binding] for [action].
  /// Throws [ArgumentError] when [binding] is invalid (empty key).
  Future<void> setBinding(ShortcutAction action, ShortcutBinding binding) async {
    if (!binding.isValid) {
      throw ArgumentError('Binding key must not be empty.');
    }
    _custom[action] = binding;
    await _persist();
  }

  /// Removes any custom override for [action], reverting to the default.
  Future<void> resetBinding(ShortcutAction action) async {
    _custom.remove(action);
    await _persist();
  }

  /// Removes all custom overrides, reverting every action to its default.
  Future<void> resetAll() async {
    _custom.clear();
    await _persist();
  }

  // -------------------------------------------------------------------------
  // Conflict detection
  // -------------------------------------------------------------------------

  /// Returns true when [binding] is already assigned to *any* action.
  bool isConflict(ShortcutBinding binding) {
    return getBindings().values.any((b) => b == binding);
  }

  /// Returns all [ShortcutAction]s that share [binding].
  List<ShortcutAction> getConflicts(ShortcutBinding binding) {
    return [
      for (final entry in getBindings().entries)
        if (entry.value == binding) entry.key,
    ];
  }

  // -------------------------------------------------------------------------
  // Import / Export
  // -------------------------------------------------------------------------

  /// Serialises all *custom* overrides to a JSON string.
  String exportBindings() {
    final map = <String, dynamic>{
      for (final e in _custom.entries) e.key.name: e.value.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Loads custom bindings from a JSON string produced by [exportBindings].
  ///
  /// Invalid JSON or malformed entries are silently ignored.
  Future<void> importBindings(String jsonStr) async {
    try {
      final dynamic decoded = json.decode(jsonStr);
      if (decoded is! Map<String, dynamic>) return;
      _custom.clear();
      for (final entry in decoded.entries) {
        final action = _actionFromName(entry.key);
        if (action == null) continue;
        if (entry.value is! Map<String, dynamic>) continue;
        final binding =
            ShortcutBinding.fromJson(entry.value as Map<String, dynamic>);
        if (binding.isValid) {
          _custom[action] = binding;
        }
      }
      await _persist();
    } catch (_) {
      // Gracefully handle invalid JSON.
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static ShortcutAction? _actionFromName(String name) {
    try {
      return ShortcutAction.values.firstWhere((a) => a.name == name);
    } catch (_) {
      return null;
    }
  }

  /// Returns the [ShortcutAction] whose current binding matches [event], or
  /// null if no action matches.
  ShortcutAction? resolve(
    KeyEvent event, {
    required bool isCtrl,
    required bool isShift,
    required bool isAlt,
    required bool isMeta,
  }) {
    for (final entry in getBindings().entries) {
      if (entry.value.matches(
        event,
        isCtrl: isCtrl,
        isShift: isShift,
        isAlt: isAlt,
        isMeta: isMeta,
      )) {
        return entry.key;
      }
    }
    return null;
  }
}
