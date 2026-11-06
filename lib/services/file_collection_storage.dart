import 'dart:convert';

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
