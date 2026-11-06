import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_collection.dart';
import '../models/file_item.dart';
import '../models/storage_reference.dart';
import 'file_collection_service.dart';
import '../utils/async_lock.dart';

/// Versioned, named collections. Loading a record never grants file access.
class FileCollectionStore extends ChangeNotifier {
  FileCollectionStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance {
    ready = _load();
  }
  final Future<SharedPreferences> Function() _preferences;
  final _lock = AsyncLock();
  final Map<String, FileCollection> _collections = {};
  final List<String> _errors = [];
  bool _disposed = false;
  late final Future<void> ready;
  static const _index = 'commander_collections_v1';
  static String _key(String id) => 'commander_collection_v1_$id';
  List<FileCollection> get collections => List.unmodifiable(
    _collections.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
  );
  List<String> get loadErrors => List.unmodifiable(_errors);
  FileCollection? get(String id) => _collections[id];

  Future<void> _load() async {
    try {
      final prefs = await _preferences();
      for (final id in prefs.getStringList(_index) ?? const <String>[]) {
        try {
          final raw = prefs.getString(_key(id));
          if (raw == null) {
            throw const FormatException('The saved record is missing.');
          }
          if (raw.length > 32 * 1024 * 1024) {
            throw const FormatException('Collection exceeds 32 MiB.');
          }
          final value = FileCollection.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          );
          if (value.id != id) {
            throw const FormatException('Collection ID mismatch.');
          }
          _collections[id] = value;
        } catch (error) {
          _errors.add('$id: $error');
        }
      }
    } catch (error) {
      _errors.add('Could not load collections: $error');
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> save(FileCollection collection) async {
    await ready;
    await _lock.synchronized(() => _write(collection));
  }

  Future<void> update(
    String id,
    FileCollection Function(FileCollection current) change,
  ) async {
    await ready;
    await _lock.synchronized(() async {
      final current = _collections[id];
      if (current == null) {
        throw StateError('The saved collection no longer exists.');
      }
      await _write(change(current));
    });
  }

  Future<void> _write(FileCollection collection) async {
    final raw = jsonEncode(collection.toJson());
    if (utf8.encode(raw).length > 32 * 1024 * 1024) {
      throw const FormatException(
        'Collection exceeds the 32 MiB storage limit.',
      );
    }
    final prefs = await _preferences();
    if (!await prefs.setString(_key(collection.id), raw)) {
      throw StateError('The collection could not be saved.');
    }
    final ids = {...?prefs.getStringList(_index), collection.id}.toList();
    if (!await prefs.setStringList(_index, ids)) {
      throw StateError('The collection index could not be saved.');
    }
    _collections[collection.id] = collection;
    if (!_disposed) notifyListeners();
  }

  Future<void> remove(String id) async {
    await ready;
    await _lock.synchronized(() async {
      final prefs = await _preferences();
      final ids = (prefs.getStringList(_index) ?? <String>[])..remove(id);
      if (!await prefs.setStringList(_index, ids)) {
        throw StateError('The collection could not be removed.');
      }
      await prefs.remove(_key(id));
      _collections.remove(id);
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> applyFileChanges(
    StorageReference storage,
    Map<String, FileItem?> replacements, {
    Set<String> removedDirectories = const {},
  }) async {
    await ready;
    await _lock.synchronized(() async {
      for (final before in _collections.values.toList()) {
        final after = const FileCollectionService().rewrite(
          before,
          storage,
          replacements,
          removedDirectories: removedDirectories,
        );
        if (!identical(before, after)) await _write(after);
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
