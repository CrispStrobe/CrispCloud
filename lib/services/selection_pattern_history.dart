import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'file_selection_pattern.dart';

/// A bounded, most-recent-first history shared by both panel selection tools.
/// Only successfully applied, validated expressions enter the history.
class SelectionPatternHistory {
  static const storageKey = 'commander_selection_pattern_history_v1';
  static const maxEntries = 20;
  static Future<void> _pendingWrite = Future.value();

  Future<List<FileSelectionPattern>> load() async {
    await _pendingWrite;
    return _read();
  }

  Future<List<FileSelectionPattern>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.get(storageKey);
    if (stored is! List) return const [];
    final patterns = <FileSelectionPattern>[];
    final seen = <String>{};
    // Bound corrupt or manually edited settings as well as our own writes.
    for (final value in stored.take(maxEntries)) {
      if (value is! String || value.length > 32768) continue;
      try {
        final decoded = jsonDecode(value);
        if (decoded is! Map<String, dynamic>) continue;
        final pattern = FileSelectionPattern.fromJson(decoded);
        if (seen.add(jsonEncode(pattern.toJson()))) patterns.add(pattern);
      } on FormatException {
        // A bad entry does not hide the remaining usable history.
      }
    }
    return List.unmodifiable(patterns);
  }

  Future<void> remember(FileSelectionPattern pattern) {
    final write = _pendingWrite.then((_) => _remember(pattern));
    // Preserve the caller's error while allowing a later dialog to retry.
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }

  Future<void> _remember(FileSelectionPattern pattern) async {
    final recent = jsonEncode(pattern.toJson());
    final previous = await _read();
    final entries = <String>[
      recent,
      for (final entry in previous)
        if (jsonEncode(entry.toJson()) != recent) jsonEncode(entry.toJson()),
    ];
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(
      storageKey,
      entries.take(maxEntries).toList(),
    )) {
      throw StateError('The recent selection patterns could not be saved.');
    }
  }
}
