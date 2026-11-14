import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/file_collection_storage.dart';
import '../services/file_collection_storage_factory.dart';

class CatalogueRecord {
  const CatalogueRecord({
    required this.id,
    required this.path,
    required this.label,
    required this.managed,
    required this.root,
    required this.savedAt,
  });
  final String id, path, label, root;
  final bool managed;
  final DateTime savedAt;
  CatalogueRecord renamed(String value) => CatalogueRecord(
    id: id,
    path: path,
    label: value,
    managed: managed,
    root: root,
    savedAt: savedAt,
  );
  Map<String, Object> toJson() => {
    'id': id,
    'path': path,
    'label': label,
    'managed': managed,
    'root': root,
    'savedAt': savedAt.toUtc().toIso8601String(),
  };
  factory CatalogueRecord.fromJson(Map<String, dynamic> json) {
    for (final key in ['id', 'path', 'label', 'root', 'savedAt']) {
      if (json[key] is! String) {
        throw const FormatException('Invalid catalogue library entry.');
      }
    }
    if (json['id'].isEmpty ||
        json['path'].isEmpty ||
        json['managed'] is! bool) {
      throw const FormatException('Invalid catalogue library entry.');
    }
    return CatalogueRecord(
      id: json['id'],
      path: json['path'],
      label: json['label'],
      root: json['root'],
      managed: json['managed'],
      savedAt: DateTime.parse(json['savedAt']),
    );
  }
}

/// Metadata references only. Catalogue files are independent of this registry.
/// Reuse the existing atomic/CAS record store instead of another preferences
/// write protocol. Removing a reference never recursively deletes a directory.
class CatalogueLibrary {
  CatalogueLibrary({FileCollectionStorage? storage})
    : storage =
          storage ??
          createFileCollectionStorage(
            preferences: SharedPreferences.getInstance,
          );
  final FileCollectionStorage storage;
  static const key = 'native-catalogue-library-v1';
  static const maxRegistryBytes = 4 * 1024 * 1024;
  Future<(String?, List<CatalogueRecord>)> _read() async {
    final raw = await storage.read(key, maxBytes: maxRegistryBytes);
    if (raw == null) return (null, <CatalogueRecord>[]);
    final value = jsonDecode(raw);
    if (value is! Map || value['version'] != 1 || value['records'] is! List) {
      throw const FormatException('Unsupported catalogue library.');
    }
    final result = (value['records'] as List)
        .map(
          (e) => CatalogueRecord.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    if (result.map((e) => e.id).toSet().length != result.length) {
      throw const FormatException('Duplicate catalogue library ID.');
    }
    return (raw, result);
  }

  Future<List<CatalogueRecord>> list() async {
    final (_, result) = await _read();
    result.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return result;
  }

  Future<void> _change(void Function(List<CatalogueRecord>) change) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final (raw, records) = await _read();
      change(records);
      final next = jsonEncode({
        'version': 1,
        'records': records.map((e) => e.toJson()).toList(),
      });
      if (utf8.encode(next).length > maxRegistryBytes) {
        throw StateError(
          'Catalogue library metadata is full; files remain available through Open catalogue.',
        );
      }
      try {
        if (await storage.compareAndSwap(key, raw, next)) return;
      } catch (error, stack) {
        // A failed acknowledgement can follow a committed atomic write.
        // Recover by reading back before declaring failure or trying again.
        try {
          final (current, _) = await _read();
          if (current == next) return;
        } catch (_) {}
        Error.throwWithStackTrace(error, stack);
      }
    }
    throw StateError(
      'Catalogue library changed concurrently; reopen the library and retry.',
    );
  }

  Future<void> remember(CatalogueRecord record) => _change((rows) {
    rows.removeWhere((e) => e.id == record.id || e.path == record.path);
    rows.add(record);
  });
  Future<void> forget(String id) =>
      _change((rows) => rows.removeWhere((e) => e.id == id));
}
