// lib/services/keyboard_shortcut_service.dart
//
// Rebindable keyboard shortcut service.
// Stores custom bindings in SharedPreferences as JSON.

import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
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
  commandEntry,
  insertCommandFilename,
  insertCommandPath,
  connect,
  goToFolder,
  filter,
  selectAll,
  restoreSelection,
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
  copyWithOptions,
  moveWithOptions,
  copyDirect,
  moveDirect,
  back,
  forward,
  up,
  reopenClosedTab,
  togglePreview,
  toggleHidden,
  sortByName,
  sortByExtension,
  sortByDate,
  sortBySize,
  bookmark,
  pathFavorites,
  multiRename,
  terminal,
  // Total Commander / Double Commander parity (2026-11). Appended so saved
  // bindings, which are keyed by action name, keep their meaning.
  newTextFile,
  chooseEditor,
  copySameFolder,
  flatView,
  flatViewSelected,
  openUnderCursor,
  directoryHistory,
  viewBrief,
  viewFull,
  viewTree,
  mirrorToOtherPanel,
  packFiles,
  unpackFiles,
  testArchives,
  deletePermanently,
  leftSourcePicker,
  rightSourcePicker,
  goToRoot,
  goHome,
  openInNewTab,
  openInOtherNewTab,
  closeAllTabs,
  tabList,
  activateTab1,
  activateTab2,
  activateTab3,
  activateTab4,
  activateTab5,
  activateTab6,
  activateTab7,
  activateTab8,
  activateTab9,
  activateLastTab,
  deselectAll,
  selectSameExtension,
  deselectSameExtension,
  compareDirectories,
  linkToOtherPanel,
  calculateFolderSizes,
  openSettings,
  insertCommandDirectory,
}

/// Alt+1…Alt+9 activate tab N (Total Commander); Alt+0 the last tab.
const activateTabShortcutActions = [
  ShortcutAction.activateTab1,
  ShortcutAction.activateTab2,
  ShortcutAction.activateTab3,
  ShortcutAction.activateTab4,
  ShortcutAction.activateTab5,
  ShortcutAction.activateTab6,
  ShortcutAction.activateTab7,
  ShortcutAction.activateTab8,
  ShortcutAction.activateTab9,
];

/// Redo is owned by individual editors. File operations only advertise actions
/// for which the browser has an actual implementation.
const commandEntryShortcutActions = [
  ShortcutAction.insertCommandFilename,
  ShortcutAction.insertCommandPath,
  ShortcutAction.insertCommandDirectory,
];

final browserShortcutActions = ShortcutAction.values
    .where(
      (action) =>
          action != ShortcutAction.redo &&
          !commandEntryShortcutActions.contains(action),
    )
    .toList(growable: false);

final shortcutSettingsActions = [
  ...browserShortcutActions,
  ...commandEntryShortcutActions,
];

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
  bool get isValid => key == ' ' || key.trim().isNotEmpty;

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

    final isMacLike =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;

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
      case 'arrow up':
        return '↑';
      case 'arrow down':
        return '↓';
      case 'arrow left':
        return '←';
      case 'arrow right':
        return '→';
      case 'page up':
        return 'PgUp';
      case 'page down':
        return 'PgDn';
      case 'numpad add':
        return 'Num +';
      case 'numpad subtract':
        return 'Num -';
      case 'numpad multiply':
        return 'Num *';
      case 'numpad divide':
        return 'Num /';
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
      _normaliseForMatch(key) == _normaliseForMatch(other.key) &&
      ctrl == other.ctrl &&
      shift == other.shift &&
      alt == other.alt &&
      meta == other.meta;

  @override
  int get hashCode =>
      Object.hash(_normaliseForMatch(key), ctrl, shift, alt, meta);

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
    ShortcutAction.prevTab: const ShortcutBinding(
      key: 'Tab',
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.commandPalette: const ShortcutBinding(
      key: 'P',
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.commandEntry: const ShortcutBinding(
      key: 'O',
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.insertCommandFilename: const ShortcutBinding(
      key: 'Enter',
      ctrl: true,
    ),
    ShortcutAction.insertCommandPath: const ShortcutBinding(
      key: 'Enter',
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.connect: const ShortcutBinding(key: 'K', ctrl: true),
    ShortcutAction.goToFolder: const ShortcutBinding(key: 'G', ctrl: true),
    ShortcutAction.filter: const ShortcutBinding(key: 'F', ctrl: true),
    ShortcutAction.selectAll: const ShortcutBinding(key: 'A', ctrl: true),
    ShortcutAction.restoreSelection: ShortcutBinding(
      key: LogicalKeyboardKey.numpadDivide.keyLabel,
    ),
    ShortcutAction.delete: const ShortcutBinding(key: 'F8'),
    ShortcutAction.terminal: const ShortcutBinding(key: 'F9'),
    ShortcutAction.rename: const ShortcutBinding(key: 'F2'),
    ShortcutAction.newFolder: const ShortcutBinding(key: 'F7'),
    ShortcutAction.refresh: const ShortcutBinding(key: 'R', ctrl: true),
    ShortcutAction.preview: const ShortcutBinding(key: 'F3'),
    ShortcutAction.edit: const ShortcutBinding(key: 'F4'),
    ShortcutAction.undo: const ShortcutBinding(key: 'Z', ctrl: true),
    ShortcutAction.redo: const ShortcutBinding(
      key: 'Z',
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.switchPanel: const ShortcutBinding(key: 'Tab'),
    ShortcutAction.copy: const ShortcutBinding(key: 'C', ctrl: true),
    ShortcutAction.paste: const ShortcutBinding(key: 'V', ctrl: true),
    ShortcutAction.cut: const ShortcutBinding(key: 'X', ctrl: true),
    ShortcutAction.toggleTreeView: const ShortcutBinding(
      key: '3',
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.cycleLayout: const ShortcutBinding(
      key: '2',
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.search: const ShortcutBinding(key: 'F7', alt: true),
    ShortcutAction.findPattern: ShortcutBinding(
      key: LogicalKeyboardKey.numpadAdd.keyLabel,
    ),
    ShortcutAction.copyWithOptions: const ShortcutBinding(key: 'F5'),
    ShortcutAction.moveWithOptions: const ShortcutBinding(key: 'F6'),
    // No-confirm F5/F6 (Cmd on macOS): copy/move to the other panel now.
    ShortcutAction.copyDirect: const ShortcutBinding(
      key: 'V',
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.moveDirect: const ShortcutBinding(
      key: 'V',
      ctrl: true,
      alt: true,
    ),
    ShortcutAction.back: ShortcutBinding(
      key: LogicalKeyboardKey.arrowLeft.keyLabel,
      alt: true,
    ),
    ShortcutAction.forward: ShortcutBinding(
      key: LogicalKeyboardKey.arrowRight.keyLabel,
      alt: true,
    ),
    ShortcutAction.up: const ShortcutBinding(key: 'Backspace'),
    ShortcutAction.reopenClosedTab: const ShortcutBinding(
      key: 'T',
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.togglePreview: const ShortcutBinding(
      key: 'P',
      ctrl: true,
      alt: true,
    ),
    ShortcutAction.toggleHidden: const ShortcutBinding(key: '.', ctrl: true),
    ShortcutAction.sortByName: const ShortcutBinding(key: 'F3', ctrl: true),
    ShortcutAction.sortByExtension: const ShortcutBinding(
      key: 'F4',
      ctrl: true,
    ),
    ShortcutAction.sortByDate: const ShortcutBinding(key: 'F5', ctrl: true),
    ShortcutAction.sortBySize: const ShortcutBinding(key: 'F6', ctrl: true),
    // Changed for TC/DC parity: bookmark was Ctrl+B (now flat view) and the
    // directory hotlist was Ctrl+Shift+B. Saved custom bindings still win.
    ShortcutAction.bookmark: const ShortcutBinding(
      key: 'D',
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.pathFavorites: const ShortcutBinding(key: 'D', ctrl: true),
    // Control-only: Cmd+M is the macOS Minimize command (see _macDefaults).
    ShortcutAction.multiRename: const ShortcutBinding(key: 'M', ctrl: true),
    // Shift+F4 used to choose an editor; it now creates a file as in TC/DC.
    ShortcutAction.newTextFile: const ShortcutBinding(key: 'F4', shift: true),
    ShortcutAction.chooseEditor: const ShortcutBinding(
      key: 'F4',
      ctrl: true,
      shift: true,
    ),
    // Shift+F5 used to be an alias of F5; it now copies in the same folder.
    ShortcutAction.copySameFolder: const ShortcutBinding(
      key: 'F5',
      shift: true,
    ),
    ShortcutAction.flatView: const ShortcutBinding(key: 'B', ctrl: true),
    ShortcutAction.flatViewSelected: const ShortcutBinding(
      key: 'B',
      ctrl: true,
      shift: true,
    ),
    // Ctrl+PgUp / Ctrl+PgDn used to switch tabs; tabs keep Ctrl+(Shift+)Tab.
    ShortcutAction.openUnderCursor: ShortcutBinding(
      key: LogicalKeyboardKey.pageDown.keyLabel,
      ctrl: true,
    ),
    // Control-only on every platform: Cmd+H hides the app on macOS. Ctrl+H
    // used to toggle hidden files, which keep Ctrl+. and Ctrl+Shift+.
    ShortcutAction.directoryHistory: const ShortcutBinding(
      key: 'H',
      ctrl: true,
    ),
    ShortcutAction.viewBrief: const ShortcutBinding(key: '1', ctrl: true),
    ShortcutAction.viewFull: const ShortcutBinding(key: '2', ctrl: true),
    ShortcutAction.viewTree: const ShortcutBinding(key: '3', ctrl: true),
    ShortcutAction.mirrorToOtherPanel: const ShortcutBinding(
      key: '=',
      ctrl: true,
    ),
    ShortcutAction.packFiles: const ShortcutBinding(key: 'F5', alt: true),
    ShortcutAction.unpackFiles: const ShortcutBinding(key: 'F9', alt: true),
    ShortcutAction.testArchives: const ShortcutBinding(
      key: 'F9',
      alt: true,
      shift: true,
    ),
    ShortcutAction.deletePermanently: const ShortcutBinding(
      key: 'F8',
      shift: true,
    ),
    ShortcutAction.leftSourcePicker: const ShortcutBinding(
      key: 'F1',
      alt: true,
    ),
    ShortcutAction.rightSourcePicker: const ShortcutBinding(
      key: 'F2',
      alt: true,
    ),
    ShortcutAction.goToRoot: ShortcutBinding(
      key: LogicalKeyboardKey.backslash.keyLabel,
      ctrl: true,
    ),
    ShortcutAction.goHome: ShortcutBinding(
      key: LogicalKeyboardKey.home.keyLabel,
      ctrl: true,
      shift: true,
    ),
    // Control-only: Cmd+Up is "enclosing folder" on macOS.
    ShortcutAction.openInNewTab: ShortcutBinding(
      key: LogicalKeyboardKey.arrowUp.keyLabel,
      ctrl: true,
    ),
    ShortcutAction.openInOtherNewTab: ShortcutBinding(
      key: LogicalKeyboardKey.arrowUp.keyLabel,
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.closeAllTabs: const ShortcutBinding(
      key: 'W',
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.tabList: const ShortcutBinding(
      key: 'A',
      ctrl: true,
      shift: true,
    ),
    for (var i = 0; i < activateTabShortcutActions.length; i++)
      activateTabShortcutActions[i]: ShortcutBinding(
        key: '${i + 1}',
        alt: true,
      ),
    ShortcutAction.activateLastTab: const ShortcutBinding(key: '0', alt: true),
    ShortcutAction.deselectAll: ShortcutBinding(
      key: LogicalKeyboardKey.numpadSubtract.keyLabel,
      ctrl: true,
    ),
    ShortcutAction.selectSameExtension: ShortcutBinding(
      key: LogicalKeyboardKey.numpadAdd.keyLabel,
      alt: true,
    ),
    ShortcutAction.deselectSameExtension: ShortcutBinding(
      key: LogicalKeyboardKey.numpadSubtract.keyLabel,
      alt: true,
    ),
    ShortcutAction.compareDirectories: const ShortcutBinding(
      key: 'F2',
      shift: true,
    ),
    ShortcutAction.linkToOtherPanel: const ShortcutBinding(
      key: 'F5',
      ctrl: true,
      shift: true,
    ),
    ShortcutAction.calculateFolderSizes: const ShortcutBinding(
      key: 'Enter',
      alt: true,
      shift: true,
    ),
    ShortcutAction.openSettings: const ShortcutBinding(key: ',', ctrl: true),
    // Command-entry scope (like Ctrl+Enter): literal Control on every system.
    ShortcutAction.insertCommandDirectory: const ShortcutBinding(
      key: 'P',
      ctrl: true,
    ),
  };

  static bool get _isMac =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// macOS replacements for defaults whose Command form belongs to the system.
  static final Map<ShortcutAction, ShortcutBinding> _macDefaults = {
    // Cmd+M minimizes; Cmd+Shift+M is the working default, Ctrl+M an alias.
    ShortcutAction.multiRename: const ShortcutBinding(
      key: 'M',
      meta: true,
      shift: true,
    ),
  };

  /// Default Control bindings that never also accept Command. Cmd+H, Cmd+M and
  /// Cmd+Q stay with macOS; Ctrl+Up must not shadow Finder's Cmd+Up.
  static final Set<ShortcutBinding> _controlOnly = {
    const ShortcutBinding(key: 'H', ctrl: true),
    const ShortcutBinding(key: 'M', ctrl: true),
    const ShortcutBinding(key: 'Q', ctrl: true),
    ShortcutBinding(key: LogicalKeyboardKey.arrowUp.keyLabel, ctrl: true),
    ShortcutBinding(
      key: LogicalKeyboardKey.arrowUp.keyLabel,
      ctrl: true,
      shift: true,
    ),
  };

  /// Whether a default Control binding also accepts Command (and displays as
  /// Command on macOS).
  static bool acceptsCommand(ShortcutBinding binding) =>
      binding.ctrl && !binding.meta && !_controlOnly.contains(binding);

  static ShortcutBinding _default(ShortcutAction action) =>
      (_isMac ? _macDefaults[action] : null) ?? _defaults[action]!;

  /// Alternate bindings for the same command share conflict detection and
  /// customization rules. A custom binding replaces all defaults for its action.
  ///
  /// Removed defaults (2026-11, TC/DC parity): Ctrl+PgDn/PgUp for next/previous
  /// tab, Ctrl+H for hidden files and Shift+F5 for copy. Bindings that users
  /// recorded themselves are persisted separately and are unaffected.
  static Map<ShortcutAction, List<ShortcutBinding>> get _browserAliases => {
    ShortcutAction.newFolder: [
      const ShortcutBinding(key: 'N', ctrl: true),
      if (_isMac) const ShortcutBinding(key: 'N', meta: true, shift: true),
    ],
    ShortcutAction.goToFolder: [
      const ShortcutBinding(key: 'L', ctrl: true),
      if (_isMac) const ShortcutBinding(key: 'G', meta: true, shift: true),
    ],
    // Cmd+Shift+. is Finder's own toggle for hidden files.
    ShortcutAction.toggleHidden: [
      const ShortcutBinding(key: '.', ctrl: true, shift: true),
    ],
    ShortcutAction.delete: [
      const ShortcutBinding(key: 'Delete'),
      if (_isMac) const ShortcutBinding(key: 'Backspace', meta: true),
    ],
    ShortcutAction.deletePermanently: [
      const ShortcutBinding(key: 'Delete', shift: true),
    ],
    ShortcutAction.up: [
      ShortcutBinding(key: LogicalKeyboardKey.pageUp.keyLabel, ctrl: true),
      if (_isMac)
        ShortcutBinding(key: LogicalKeyboardKey.arrowUp.keyLabel, meta: true),
    ],
    ShortcutAction.openUnderCursor: [
      if (_isMac)
        ShortcutBinding(key: LogicalKeyboardKey.arrowDown.keyLabel, meta: true),
    ],
    ShortcutAction.back: [
      if (_isMac) const ShortcutBinding(key: '[', meta: true),
    ],
    ShortcutAction.forward: [
      if (_isMac) const ShortcutBinding(key: ']', meta: true),
    ],
    ShortcutAction.directoryHistory: [
      ShortcutBinding(key: LogicalKeyboardKey.arrowDown.keyLabel, alt: true),
    ],
    ShortcutAction.viewBrief: [const ShortcutBinding(key: 'F1', ctrl: true)],
    ShortcutAction.viewFull: [const ShortcutBinding(key: 'F2', ctrl: true)],
    ShortcutAction.viewTree: [const ShortcutBinding(key: 'F8', ctrl: true)],
    ShortcutAction.mirrorToOtherPanel: [
      const ShortcutBinding(key: 'Z', alt: true),
    ],
    ShortcutAction.selectAll: [
      ShortcutBinding(key: LogicalKeyboardKey.numpadAdd.keyLabel, ctrl: true),
    ],
    // Cmd+Q quits on macOS; Ctrl+Q quick view is a Windows/Linux habit.
    ShortcutAction.togglePreview: [
      if (!_isMac) const ShortcutBinding(key: 'Q', ctrl: true),
    ],
    ShortcutAction.filter: [const ShortcutBinding(key: 'S', ctrl: true)],
    ShortcutAction.multiRename: [
      if (_isMac) const ShortcutBinding(key: 'M', ctrl: true),
    ],
  };

  /// Every default binding of [action] (primary first), ignoring custom ones.
  List<ShortcutBinding> defaultBindings(ShortcutAction action) => [
    _default(action),
    ...?_browserAliases[action],
  ];

  /// Custom bindings loaded from / persisted to SharedPreferences.
  final Map<ShortcutAction, ShortcutBinding> _custom = {};
  Future<void>? _loading;
  Future<void> _saving = Future<void>.value();

  // -------------------------------------------------------------------------
  // Initialisation
  // -------------------------------------------------------------------------

  /// Load persisted custom bindings.  Call once during app startup.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final parsed = _parseBindings(raw);
      if (parsed != null) _custom.addAll(parsed);
    } catch (_) {
      // Corrupt prefs — silently ignore and use defaults.
    }
  }

  Future<void> _persist() {
    final encoded = json.encode({
      for (final entry in _custom.entries) entry.key.name: entry.value.toJson(),
    });
    // Persist snapshots in mutation order. A slow earlier settings write must
    // never finish after, and overwrite, a newer recorded binding or reset.
    _saving = _saving.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, encoded);
      } catch (_) {}
    });
    return _saving;
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Returns all current bindings (custom overrides merged over defaults).
  Map<ShortcutAction, ShortcutBinding> getBindings() {
    return {..._defaults, if (_isMac) ..._macDefaults, ..._custom};
  }

  /// Returns the current binding for [action].
  ShortcutBinding getBinding(ShortcutAction action) =>
      _custom[action] ?? _default(action);

  /// Persists [binding] for [action].
  /// Throws [ArgumentError] when [binding] is invalid (empty key).
  Future<void> setBinding(
    ShortcutAction action,
    ShortcutBinding binding,
  ) async {
    if (!binding.isValid) {
      throw ArgumentError('Binding key must not be empty.');
    }
    await load();
    _custom[action] = binding;
    await _persist();
  }

  /// Removes any custom override for [action], reverting to the default.
  Future<void> resetBinding(ShortcutAction action) async {
    await load();
    _custom.remove(action);
    await _persist();
  }

  /// Removes all custom overrides, reverting every action to its default.
  Future<void> resetAll() async {
    await load();
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
    final parsed = _parseBindings(jsonStr);
    if (parsed == null) return;
    await load();
    _custom
      ..clear()
      ..addAll(parsed);
    await _persist();
  }

  static Map<ShortcutAction, ShortcutBinding>? _parseBindings(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final parsed = <ShortcutAction, ShortcutBinding>{};
      for (final entry in decoded.entries) {
        final action = _actionFromName(entry.key);
        if (action == null || entry.value is! Map<String, dynamic>) continue;
        try {
          final binding = ShortcutBinding.fromJson(
            entry.value as Map<String, dynamic>,
          );
          if (binding.isValid) parsed[action] = binding;
        } catch (_) {
          // A malformed entry must not discard the other saved shortcuts.
        }
      }
      return parsed;
    } catch (_) {
      return null;
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

  bool isCustomized(ShortcutAction action) => _custom.containsKey(action);

  Iterable<ShortcutBinding> _browserBindings(ShortcutAction action) sync* {
    yield getBinding(action);
    if (!isCustomized(action)) {
      yield* _browserAliases[action] ?? const <ShortcutBinding>[];
    }
  }

  List<ShortcutAction> browserConflicts(
    ShortcutAction action,
    ShortcutBinding binding,
  ) {
    return browserShortcutActions
        .where((other) {
          if (other == action) return false;
          return _browserBindings(other).any((existing) {
            if (existing == binding) return true;
            // Default Control accelerators also accept Command.
            return !isCustomized(other) &&
                acceptsCommand(existing) &&
                binding ==
                    ShortcutBinding(
                      key: existing.key,
                      meta: true,
                      shift: existing.shift,
                      alt: existing.alt,
                    );
          });
        })
        .toList(growable: false);
  }

  /// Command-entry keys have their own focus scope. They may reuse browser
  /// bindings without stealing events from a file list, editor or terminal.
  List<ShortcutAction> shortcutConflicts(
    ShortcutAction action,
    ShortcutBinding binding,
  ) => commandEntryShortcutActions.contains(action)
      ? commandEntryShortcutActions
            .where((other) => other != action && getBinding(other) == binding)
            .toList(growable: false)
      : browserConflicts(action, binding);

  ShortcutAction? resolveCommandEntry(
    KeyEvent event, {
    required bool isCtrl,
    required bool isShift,
    required bool isAlt,
    required bool isMeta,
  }) {
    for (final action in [..._custom.keys, ...commandEntryShortcutActions]) {
      if (!commandEntryShortcutActions.contains(action)) continue;
      if (_browserMatches(
        action,
        getBinding(action),
        event,
        isCtrl: isCtrl,
        isShift: isShift,
        isAlt: isAlt,
        isMeta: isMeta,
      )) {
        return action;
      }
    }
    return null;
  }

  bool suppressesCommandEntryDefault(
    KeyEvent event, {
    required bool isCtrl,
    required bool isShift,
    required bool isAlt,
    required bool isMeta,
  }) => commandEntryShortcutActions
      .where(isCustomized)
      .any(
        (action) => _browserMatches(
          action,
          _default(action),
          event,
          isCtrl: isCtrl,
          isShift: isShift,
          isAlt: isAlt,
          isMeta: isMeta,
        ),
      );

  /// Default primary-modifier shortcuts work with Control and Command.
  /// Explicit custom bindings retain the exact modifiers the user recorded.
  bool _browserMatches(
    ShortcutAction action,
    ShortcutBinding binding,
    KeyEvent event, {
    required bool isCtrl,
    required bool isShift,
    required bool isAlt,
    required bool isMeta,
    bool defaultBinding = false,
  }) {
    final primary = defaultBinding && acceptsCommand(binding);
    if (primary && isCtrl == isMeta) return false;
    // Recognize a held binding so child views can forward it and the command
    // host can suppress repeats instead of turning it into quick search.
    final press = event is KeyRepeatEvent
        ? KeyDownEvent(
            physicalKey: event.physicalKey,
            logicalKey: event.logicalKey,
            timeStamp: event.timeStamp,
            character: event.character,
          )
        : event;
    return binding.matches(
      press,
      isCtrl: primary ? isCtrl || isMeta : isCtrl,
      isShift: isShift,
      isAlt: isAlt,
      isMeta: primary ? false : isMeta,
    );
  }

  ShortcutAction? resolveBrowser(
    KeyEvent event, {
    required bool isCtrl,
    required bool isShift,
    required bool isAlt,
    required bool isMeta,
  }) {
    // An explicit binding takes priority over a default it replaced. The UI
    // reports these conflicts before saving; older imports remain deterministic.
    for (final action in [..._custom.keys, ...browserShortcutActions]) {
      if (!browserShortcutActions.contains(action)) continue;
      for (final binding in _browserBindings(action)) {
        if (_browserMatches(
          action,
          binding,
          event,
          isCtrl: isCtrl,
          isShift: isShift,
          isAlt: isAlt,
          isMeta: isMeta,
          defaultBinding: !_custom.containsKey(action),
        ))
          return action;
      }
    }
    return null;
  }

  /// Prevent the old hardcoded accelerator from firing after it was rebound.
  bool suppressesDefault(
    KeyEvent event, {
    required bool isCtrl,
    required bool isShift,
    required bool isAlt,
    required bool isMeta,
  }) {
    return _custom.keys
        .where(browserShortcutActions.contains)
        .any(
          (action) => defaultBindings(action).any(
            (binding) => _browserMatches(
              action,
              binding,
              event,
              isCtrl: isCtrl,
              isShift: isShift,
              isAlt: isAlt,
              isMeta: isMeta,
              defaultBinding: true,
            ),
          ),
        );
  }

  String browserDisplay(ShortcutAction action) =>
      _display(action, getBinding(action));

  /// The primary binding followed by its default aliases, e.g. "F8 / Del".
  String browserDisplayAll(ShortcutAction action) => {
    for (final binding in _browserBindings(action)) _display(action, binding),
  }.join(' / ');

  String _display(ShortcutAction action, ShortcutBinding binding) {
    if (_isMac &&
        !commandEntryShortcutActions.contains(action) &&
        !isCustomized(action) &&
        acceptsCommand(binding)) {
      binding = ShortcutBinding(
        key: binding.key,
        meta: true,
        shift: binding.shift,
        alt: binding.alt,
      );
    }
    return binding.toDisplayString();
  }
}
