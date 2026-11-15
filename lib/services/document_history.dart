import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/storage_reference.dart';
import '../utils/async_lock.dart';

class DocumentHistoryEntry {
  const DocumentHistoryEntry({
    required this.file,
    this.editedAt,
    this.openedAt,
  });
  final FileReference file;
  final DateTime? editedAt, openedAt;
  DateTime get latest => editedAt == null
      ? openedAt!
      : openedAt == null || editedAt!.isAfter(openedAt!)
      ? editedAt!
      : openedAt!;
  // Paths, rather than provider object IDs, are portable across an export/load.
  String get key => jsonEncode([file.storage.toJson(), file.path]);
  Map<String, Object?> toJson() => {
    'file': FileReference(storage: file.storage, path: file.path).toJson(),
    if (editedAt != null) 'editedAt': editedAt!.toUtc().toIso8601String(),
    if (openedAt != null) 'openedAt': openedAt!.toUtc().toIso8601String(),
  };
  factory DocumentHistoryEntry.fromJson(Object? value) {
    if (value is! Map || value['file'] is! Map) {
      throw const FormatException('Invalid history entry.');
    }
    final file = FileReference.fromJson(
      Map<String, dynamic>.from(value['file'] as Map),
    );
    if (file.path.length > 16384 ||
        file.storage.root.length > 16384 ||
        file.storage.accountKey.length > 4096 ||
        !file.storage.persistent) {
      throw const FormatException('Unsupported history location.');
    }
    DateTime? date(String key) {
      final raw = value[key];
      if (raw == null) return null;
      if (raw is! String || raw.length > 64) {
        throw const FormatException('Invalid history date.');
      }
      return DateTime.parse(raw).toUtc();
    }

    final entry = DocumentHistoryEntry(
      file: file,
      editedAt: date('editedAt'),
      openedAt: date('openedAt'),
    );
    if (entry.editedAt == null && entry.openedAt == null) {
      throw const FormatException('History entry has no date.');
    }
    return entry;
  }
}

/// Metadata only: never document bytes, tokens or account passwords. Exports do
/// not carry logging preferences, and loading a list never enables recording.
class DocumentHistory extends ChangeNotifier {
  DocumentHistory({
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? now,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now {
    ready = _load();
  }
  static const storageKey = 'document_history.v1';
  static const maxEntries = 1000;
  static const maxImportBytes = 8 * 1024 * 1024;
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;
  final _lock = AsyncLock();
  late final Future<void> ready;
  final List<DocumentHistoryEntry> _entries = [];
  List<DocumentHistoryEntry> get entries => List.unmodifiable(_entries);
  bool recordEdits = true, recordOpens = false;
  bool _disposed = false;
  int _epoch = 0;
  String? persistenceError;

  Future<void> _load() async {
    final epoch = _epoch;
    try {
      final prefs = await _preferences();
      if (_disposed) return;
      recordEdits = prefs.getBool('$storageKey.edits') ?? true;
      recordOpens = prefs.getBool('$storageKey.opens') ?? false;
      final raw = prefs.getString(storageKey);
      if (raw != null && epoch == _epoch) _merge(decode(raw));
      notifyListeners();
    } catch (error) {
      if (!_disposed) {
        persistenceError = '$error';
        notifyListeners();
      }
    }
  }

  static List<DocumentHistoryEntry> decode(String raw) {
    if (raw.length > maxImportBytes ||
        utf8.encode(raw).length > maxImportBytes) {
      throw const FormatException('History exceeds 8 MiB.');
    }
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['version'] != 1 ||
        data['entries'] is! List ||
        (data['entries'] as List).length > maxEntries) {
      throw const FormatException(
        'Unsupported history file or more than 1000 entries.',
      );
    }
    return [
      for (final item in data['entries'] as List)
        DocumentHistoryEntry.fromJson(item),
    ];
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'entries': [for (final entry in _entries) entry.toJson()],
  });
  void _merge(Iterable<DocumentHistoryEntry> incoming) {
    final merged = {for (final entry in _entries) entry.key: entry};
    DateTime? newer(DateTime? a, DateTime? b) => a == null
        ? b
        : b == null || a.isAfter(b)
        ? a
        : b;
    for (final entry in incoming) {
      final old = merged[entry.key];
      merged[entry.key] = old == null
          ? entry
          : DocumentHistoryEntry(
              file: entry.file,
              editedAt: newer(old.editedAt, entry.editedAt),
              openedAt: newer(old.openedAt, entry.openedAt),
            );
    }
    final sorted = merged.values.toList()
      ..sort((a, b) => b.latest.compareTo(a.latest));
    _entries
      ..clear()
      ..addAll(sorted.take(maxEntries));
    // Indented exports must fit the same bounded format that imports accept.
    while (_entries.isNotEmpty &&
        utf8.encode(exportJson()).length > maxImportBytes) {
      _entries.removeLast();
    }
  }

  Future<void> record(FileReference file, {required bool edited}) async {
    final epoch = _epoch;
    await ready;
    if (_disposed ||
        epoch != _epoch ||
        !file.storage.persistent ||
        file.path.isEmpty ||
        file.path.contains('\u0000') ||
        (edited ? !recordEdits : !recordOpens)) {
      return;
    }
    _merge([
      DocumentHistoryEntry(
        file: file,
        editedAt: edited ? _now() : null,
        openedAt: edited ? null : _now(),
      ),
    ]);
    notifyListeners();
    await _save();
  }

  Future<void> configure({required bool edits, required bool opens}) async {
    await ready;
    if (_disposed) return;
    recordEdits = edits;
    recordOpens = opens;
    notifyListeners();
    await _save();
  }

  Future<void> importJson(String raw, {bool replace = false}) async {
    final incoming = decode(
      raw,
    ); // validate everything before changing any state
    await ready;
    if (_disposed) return;
    _epoch++;
    if (replace) _entries.clear();
    _merge(incoming);
    notifyListeners();
    await _save();
  }

  Future<void> purge() async {
    _epoch++;
    _entries.clear();
    if (!_disposed) notifyListeners();
    await ready;
    await _save();
  }

  Future<void> remove(DocumentHistoryEntry entry) async {
    await ready;
    _entries.removeWhere((e) => e.key == entry.key);
    if (!_disposed) notifyListeners();
    await _save();
  }

  Future<void> _save() => _lock.synchronized(() async {
    try {
      final prefs = await _preferences();
      if (!await prefs.setString(storageKey, exportJson()) ||
          !await prefs.setBool('$storageKey.edits', recordEdits) ||
          !await prefs.setBool('$storageKey.opens', recordOpens)) {
        throw StateError('Could not persist document history.');
      }
      if (!_disposed && persistenceError != null) {
        persistenceError = null;
        notifyListeners();
      }
    } catch (error) {
      if (!_disposed) {
        persistenceError = '$error';
        notifyListeners();
      }
    }
  });
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final documentHistoryProvider = ChangeNotifierProvider<DocumentHistory>(
  (ref) => DocumentHistory(),
);
