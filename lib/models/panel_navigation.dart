import 'package:path/path.dart' as p;

import 'storage_reference.dart';

/// A location retains its storage identity independently of the active pane.
/// Credentials and file contents are never part of navigation history.
class PanelNavigationEntry {
  const PanelNavigationEntry({
    required this.path,
    required this.storage,
    this.cursorPath,
    this.cursorObjectId,
  });

  final String path;
  final StorageReference storage;
  final String? cursorPath;
  final String? cursorObjectId;

  bool sameLocation(PanelNavigationEntry other) =>
      storage == other.storage && path == other.path;

  Map<String, dynamic> toJson() => {
    'path': path,
    'storage': storage.toJson(),
    if (cursorPath != null) 'cursorPath': cursorPath,
    if (cursorObjectId != null) 'cursorObjectId': cursorObjectId,
  };

  factory PanelNavigationEntry.fromJson(Map<String, dynamic> json) {
    final storage = StorageReference.fromJson(
      Map<String, dynamic>.from(json['storage'] as Map),
    );
    final path = json['path'];
    final paths = storage.isLocal && storage.provider == 'windows'
        ? p.windows
        : p.posix;
    if (path is! String ||
        path.isEmpty ||
        path.contains('\u0000') ||
        !paths.isAbsolute(path)) {
      throw const FormatException('Navigation needs an absolute storage path.');
    }
    return PanelNavigationEntry(
      path: paths.normalize(path),
      storage: storage,
      cursorPath: json['cursorPath'] as String?,
      cursorObjectId: json['cursorObjectId'] as String?,
    );
  }
}

/// A bounded back/forward stack owned by one tab. Visiting the current
/// location keeps its forward entries; only a genuinely new route replaces
/// them. The index moves after navigation succeeds, so unavailable accounts
/// cannot silently consume history.
class PanelNavigationHistory {
  static const maxEntries = 100;

  final List<PanelNavigationEntry> _entries = [];
  int _index = -1;

  List<PanelNavigationEntry> get entries => List.unmodifiable(_entries);
  int get index => _index;
  bool get canGoBack => _index > 0;
  bool get canGoForward => _index >= 0 && _index + 1 < _entries.length;
  PanelNavigationEntry? get current =>
      _index >= 0 && _index < _entries.length ? _entries[_index] : null;

  void push(PanelNavigationEntry entry) {
    if (current?.sameLocation(entry) ?? false) return;
    if (_index + 1 < _entries.length) {
      _entries.removeRange(_index + 1, _entries.length);
    }
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    _index = _entries.length - 1;
  }

  void rememberCursor(PanelNavigationEntry entry) {
    if (current?.sameLocation(entry) ?? false) _entries[_index] = entry;
  }

  void select(int index) {
    if (index < 0 || index >= _entries.length) {
      throw RangeError.index(index, _entries);
    }
    _index = index;
  }

  Map<String, dynamic> toJson() => {
    'entries': _entries.map((entry) => entry.toJson()).toList(),
    'index': _index,
  };

  factory PanelNavigationHistory.fromJson(Map<String, dynamic> json) {
    final history = PanelNavigationHistory();
    final raw = json['entries'];
    if (raw is! List) return history;
    final savedIndex = json['index'] is int ? json['index'] as int : raw.length - 1;
    final start = (raw.length - maxEntries).clamp(0, raw.length);
    for (var i = start; i < raw.length; i++) {
      try {
        final entry = PanelNavigationEntry.fromJson(
          Map<String, dynamic>.from(raw[i] as Map),
        );
        history._entries.add(entry);
        if (i <= savedIndex) history._index = history._entries.length - 1;
      } on Object {
        // A malformed historical item must not erase the tab's valid routes.
      }
    }
    if (history._index < 0 && history._entries.isNotEmpty) history._index = 0;
    return history;
  }

  PanelNavigationHistory();

  PanelNavigationHistory copy() => PanelNavigationHistory.fromJson(toJson());
}
