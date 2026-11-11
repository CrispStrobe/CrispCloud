import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Each collection page is a separate record. Production implementations never
/// preload all values into the SharedPreferences process-wide cache.
abstract class FileCollectionStorage {
  Future<String?> read(String key, {required int maxBytes});
  Future<void> write(String key, String value);
  Future<void> remove(String key);

  /// A committed catalog is the only authority for live revision/page records.
  /// Returns false only when this call did not install [value]. A thrown error
  /// may follow a successful commit; callers must read back the catalog before
  /// deleting candidate records, or retain them if the outcome stays unknown.
  Future<bool> compareAndSwap(String key, String? expected, String value);
}

/// One immutable page, encoded once for budgeting, checksums and native writes.
/// The string remains available for IndexedDB and existing storage adapters.
final class FileCollectionStorageRecord {
  FileCollectionStorageRecord(this.key, this.value)
    : bytes = utf8.encode(value).asUnmodifiableView();

  final String key;
  final String value;
  final Uint8List bytes;
}

/// Optional acceleration for independent immutable pages. Implementations must
/// finish every submitted write before completing, including on failure. This
/// lets callers safely remove staged keys after a failed batch without a late
/// write recreating them. Publication still uses the separate catalog CAS.
abstract interface class FileCollectionStorageBatchWriter {
  Future<void> writeBatch(List<FileCollectionStorageRecord> records);
}

/// Batches are deliberately small: neither a transaction nor concurrent native
/// writes may retain an entire collection. Manifests/catalogs use normal writes.
class FileCollectionStorageBatch {
  static const maxRecords = 4;
  static const maxRecordBytes = 512 * 1024;
  static const maxBytes = 2 * 1024 * 1024;

  static void validate(List<FileCollectionStorageRecord> records) {
    if (records.length > maxRecords) {
      throw ArgumentError('A storage batch supports at most four records.');
    }
    final keys = <String>{};
    var bytes = 0;
    for (final record in records) {
      if (!keys.add(record.key)) {
        throw ArgumentError('A storage batch contains duplicate keys.');
      }
      bytes += record.bytes.length;
      if (record.bytes.length > maxRecordBytes || bytes > maxBytes) {
        throw ArgumentError('A storage batch exceeds its page-byte budget.');
      }
    }
  }

  static Future<void> write(
    FileCollectionStorage storage,
    List<FileCollectionStorageRecord> records,
  ) async {
    // Own the collection passed to an asynchronous adapter. The records and
    // their encoded bytes cannot change while a write is outstanding.
    final batch = List<FileCollectionStorageRecord>.unmodifiable(records);
    validate(batch);
    if (batch.isEmpty) return;
    if (storage is FileCollectionStorageBatchWriter) {
      await (storage as FileCollectionStorageBatchWriter).writeBatch(batch);
    } else {
      for (final record in batch) {
        await storage.write(record.key, record.value);
      }
    }
  }
}

class MemoryFileCollectionStorage implements FileCollectionStorage {
  final values = <String, String>{};
  final reads = <String>[];
  int maxReadBytes = 0;
  @override
  Future<String?> read(String key, {required int maxBytes}) async {
    reads.add(key);
    final value = values[key];
    if (value != null) {
      final size = utf8.encode(value).length;
      if (size > maxReadBytes) {
        maxReadBytes = size;
      }
      if (size > maxBytes) {
        throw const FormatException(
          'Saved collection record exceeds its size limit.',
        );
      }
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    if (values[key] != expected) {
      return false;
    }
    values[key] = value;
    return true;
  }
}

/// Test-only persistence adapter. Keeps existing preference fixtures isolated
/// while native/browser production pages use independent disk/IndexedDB records.
class PreferencesFileCollectionStorage implements FileCollectionStorage {
  PreferencesFileCollectionStorage(this.preferences);
  final Future<SharedPreferences> Function() preferences;
  static String _key(String key) => 'commander_collection_test_v2_$key';
  @override
  Future<String?> read(String key, {required int maxBytes}) async {
    final value = (await preferences()).getString(_key(key));
    if (value != null && utf8.encode(value).length > maxBytes) {
      throw const FormatException(
        'Saved collection record exceeds its size limit.',
      );
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    if (!await (await preferences()).setString(_key(key), value)) {
      throw StateError('The collection page could not be saved.');
    }
  }

  @override
  Future<void> remove(String key) async =>
      (await preferences()).remove(_key(key));
  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    final prefs = await preferences();
    if (prefs.getString(_key(key)) != expected) {
      return false;
    }
    if (!await prefs.setString(_key(key), value)) {
      throw StateError('The collection catalog could not be saved.');
    }
    return true;
  }
}
