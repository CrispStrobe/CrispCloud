import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/file_collection.dart';
import '../models/file_collection_page.dart';
import '../models/file_item.dart';
import '../models/storage_reference.dart';
import '../utils/async_lock.dart';
import 'file_collection_service.dart';
import 'file_collection_storage.dart';
import 'file_collection_storage_factory.dart';

/// Lazy catalog plus immutable, independently persisted row pages. Loaded rows
/// share one byte/entry-budgeted LRU cache across every collection and pane.
class FileCollectionStore extends ChangeNotifier {
  FileCollectionStore({
    Future<SharedPreferences> Function()? preferences,
    FileCollectionStorage? storage,
    this.cacheByteLimit = 4 * 1024 * 1024,
    this.cacheEntryLimit = 4000,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _storage =
           storage ??
           createFileCollectionStorage(
             preferences: preferences ?? SharedPreferences.getInstance,
           ) {
    if (cacheByteLimit < 0 || cacheEntryLimit < 0) {
      throw ArgumentError('Invalid collection cache budget.');
    }
    ready = _load();
  }
  final Future<SharedPreferences> Function() _preferences;
  final FileCollectionStorage _storage;
  final int cacheByteLimit;
  final int cacheEntryLimit;
  static const pageEntryLimit = 500;
  static const pageByteLimit = 512 * 1024;
  static const collectionByteLimit = 32 * 1024 * 1024;
  static const manifestByteLimit = 4 * 1024 * 1024;
  static const catalogByteLimit = 8 * 1024 * 1024;
  static const collectionCountLimit = 10000;
  static const _catalogKey = 'catalog-v2';
  static const _legacyIndex = 'commander_collections_v1';
  static String _legacyKey(String id) => 'commander_collection_v1_$id';
  static String _manifestKey(String id, String revision) =>
      'manifest:$id:$revision';
  final _lock = AsyncLock();
  final Map<String, FileCollectionSummary> _collections = {};
  final _cache = <String, _CachedPage>{};
  int _cachedBytes = 0;
  int _cachedEntries = 0;
  final List<String> _errors = [];
  String? _catalogRaw;
  bool _healthy = true;
  bool _disposed = false;
  bool _loading = true;
  String? _loadProgress;
  late final Future<void> ready;
  bool get isLoading => _loading;
  String? get loadProgress => _loadProgress;
  int get residentPageBytes => _cachedBytes;
  int get residentEntryCount => _cachedEntries;
  int get residentPageCount => _cache.length;
  List<FileCollectionSummary> get collections => List.unmodifiable(
    _collections.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
  );
  List<String> get loadErrors => List.unmodifiable(_errors);
  FileCollectionSummary? get(String id) => _collections[id];
  void _changed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _error(String message) {
    if (_errors.length < 100 && !_errors.contains(message)) {
      _errors.add(message);
    }
    _changed();
  }

  Future<void> _load() async {
    _loading = true;
    try {
      _catalogRaw = await _storage.read(
        _catalogKey,
        maxBytes: catalogByteLimit,
      );
      if (_catalogRaw != null) {
        final json = jsonDecode(_catalogRaw!) as Map;
        if (json['version'] != 2 || json['collections'] is! List) {
          throw const FormatException('Unsupported collection catalog.');
        }
        final records = json['collections'] as List;
        if (records.length > collectionCountLimit) {
          throw const FormatException(
            'Collection catalog exceeds 10,000 records.',
          );
        }
        for (final record in records) {
          final summary = FileCollectionSummary.fromJson(
            Map<String, dynamic>.from(record as Map),
          );
          if (_collections.containsKey(summary.id)) {
            throw const FormatException('Duplicate collection catalog ID.');
          }
          _collections[summary.id] = summary;
        }
      }
      // Legacy records are migrated one at a time and removed only after the
      // immutable page manifest is committed. A failed migration preserves the
      // original preference value and remains visible for retry/export.
      final prefs = await _preferences();
      final legacyIds = List<String>.of(
        prefs.getStringList(_legacyIndex) ?? const [],
      );
      for (var index = 0; index < legacyIds.length; index++) {
        final id = legacyIds[index];
        _loadProgress = '${index + 1} / ${legacyIds.length}';
        _changed();
        try {
          if (!_collections.containsKey(id)) {
            final raw = prefs.getString(_legacyKey(id));
            if (raw == null) {
              throw const FormatException('The saved record is missing.');
            }
            if (raw.length > collectionByteLimit ||
                utf8.encode(raw).length > collectionByteLimit) {
              throw const FormatException('Collection exceeds 32 MiB.');
            }
            final collection = FileCollection.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            );
            if (collection.id != id) {
              throw const FormatException('Collection ID mismatch.');
            }
            await _writeRows(
              collection,
              Stream.fromIterable(
                collection.entries.map(
                  (entry) =>
                      (entry, collection.selectedKeys.contains(entry.key)),
                ),
              ),
            );
          }
          // A previous migration may have committed its catalog but stopped
          // before clearing the legacy record. The ID alone is not proof that
          // its replacement is still readable. Check every immutable page
          // without filling the browsing cache before removing this fallback.
          await _validateLegacyReplacement(id);
          if (await prefs.remove(_legacyKey(id))) {
            final remaining = List<String>.of(
              prefs.getStringList(_legacyIndex) ?? const [],
            )..remove(id);
            if (!await prefs.setStringList(_legacyIndex, remaining)) {
              throw StateError(
                'The legacy collection index could not be updated.',
              );
            }
          }
        } catch (error) {
          _error('$id: $error');
        }
      }
    } catch (error) {
      _healthy = false;
      _error('Could not load collections: $error');
    } finally {
      _loading = false;
      _loadProgress = null;
      _changed();
    }
  }

  Future<void> _validateLegacyReplacement(String id) async {
    final record = await _readManifest(id);
    final keys = <String>{};
    for (var index = 0; index < record.pages.length; index++) {
      final page = await _readPage(record, index, useCache: false);
      _addUniqueKeys(keys, page.collection.entries);
    }
    if (await _storage.read(_catalogKey, maxBytes: catalogByteLimit) !=
        _catalogRaw) {
      throw StateError(
        'The collection catalog changed during migration. Reload and retry.',
      );
    }
  }

  Future<void> reload() async {
    await ready;
    await _lock.synchronized(() async {
      _collections.clear();
      _errors.clear();
      _healthy = true;
      _clearCache();
      await _load();
    });
  }

  void _checkWritable() {
    if (_disposed) {
      throw StateError('The collection store was closed.');
    }
    if (!_healthy) {
      throw StateError(
        'Reload or repair the collection catalog before saving.',
      );
    }
  }

  void _checkRevision(FileCollectionSummary expected) {
    if (_collections[expected.id]?.revision != expected.revision) {
      throw StateError(
        'The saved collection changed. Reopen it before continuing.',
      );
    }
  }

  Future<FileCollectionManifest> manifest(String id, {String? revision}) async {
    await ready;
    return _readManifest(id, revision: revision);
  }

  Future<FileCollectionManifest> _readManifest(
    String id, {
    String? revision,
  }) async {
    final summary = _collections[id];
    if (summary == null) {
      throw StateError('The saved collection no longer exists.');
    }
    if (revision != null && revision != summary.revision) {
      throw StateError(
        'The saved collection changed. Reopen it before continuing.',
      );
    }
    try {
      final raw = await _storage.read(
        _manifestKey(id, summary.revision),
        maxBytes: manifestByteLimit,
      );
      if (raw == null) {
        throw const FormatException(
          'The saved collection manifest is missing.',
        );
      }
      final record = FileCollectionManifest.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (jsonEncode(record.summary.toJson()) != jsonEncode(summary.toJson())) {
        throw const FormatException(
          'The collection manifest does not match its catalog.',
        );
      }
      _checkRevision(summary);
      return record;
    } catch (error) {
      _error('${summary.name}: $error');
      rethrow;
    }
  }

  Future<FileCollectionPage> loadPage(
    String id,
    int index, {
    String? revision,
  }) async {
    final record = await manifest(id, revision: revision);
    return _readPage(record, index);
  }

  Future<FileCollectionPage> _readPage(
    FileCollectionManifest record,
    int index, {
    bool useCache = true,
  }) async {
    _checkRevision(record.summary);
    if (index < 0 ||
        index >= (record.pages.isEmpty ? 1 : record.pages.length)) {
      throw RangeError.index(index, record.pages, 'index');
    }
    if (record.pages.isEmpty) {
      return FileCollectionPage(
        manifest: record,
        index: 0,
        collection: _pageCollection(record, const [], const {}),
      );
    }
    final descriptor = record.pages[index];
    var value = useCache ? _cache.remove(descriptor.key) : null;
    if (value != null) {
      _cache[descriptor.key] = value;
    }
    try {
      if (value == null) {
        final raw = await _storage.read(
          descriptor.key,
          maxBytes: pageByteLimit,
        );
        if (raw == null) {
          throw const FormatException('A saved collection page is missing.');
        }
        final bytes = utf8.encode(raw).length;
        if (bytes != descriptor.bytes ||
            sha256.convert(utf8.encode(raw)).toString() != descriptor.digest) {
          throw const FormatException('A saved collection page changed.');
        }
        final json = jsonDecode(raw) as Map;
        if (json['version'] != 2 || json['rows'] is! List) {
          throw const FormatException('Invalid collection page.');
        }
        final rows = json['rows'] as List;
        if (rows.length != descriptor.count) {
          throw const FormatException(
            'The saved collection page count changed.',
          );
        }
        final entries = <FileCollectionEntry>[];
        final selected = <String>{};
        for (final row in rows) {
          final data = row as Map;
          final entry = FileCollectionEntry.fromJson(
            Map<String, dynamic>.from(data['entry'] as Map),
          );
          entries.add(entry);
          if (data['selected'] == true) {
            selected.add(entry.key);
          }
        }
        if (selected.length != descriptor.selectedCount ||
            entries.map((entry) => entry.key).toSet().length !=
                entries.length) {
          throw const FormatException(
            'Invalid collection page selection or duplicate paths.',
          );
        }
        value = _CachedPage(
          List.unmodifiable(entries),
          Set.unmodifiable(selected),
          bytes,
          descriptor.digest,
        );
      }
      if (value.bytes != descriptor.bytes ||
          value.digest != descriptor.digest ||
          value.entries.length != descriptor.count ||
          value.selected.length != descriptor.selectedCount ||
          value.entries.where(_isUnavailable).length !=
              descriptor.unavailableCount ||
          !setEquals(
            value.entries.map((entry) => entry.reference.storage.id).toSet(),
            descriptor.sources,
          )) {
        throw const FormatException(
          'The saved collection page does not match its manifest.',
        );
      }
      if (useCache) _cachePage(descriptor.key, value);
      _checkRevision(record.summary);
      return FileCollectionPage(
        manifest: record,
        index: index,
        collection: _pageCollection(record, value.entries, value.selected),
      );
    } catch (error) {
      _error('${record.summary.name}, page ${index + 1}: $error');
      rethrow;
    }
  }

  static bool _isUnavailable(FileCollectionEntry entry) =>
      entry.replacement ||
      entry.state == CollectionItemState.missing ||
      entry.state == CollectionItemState.offline;

  static void _addUniqueKeys(
    Set<String> keys,
    Iterable<FileCollectionEntry> entries,
  ) {
    for (final entry in entries) {
      if (!keys.add(entry.key)) {
        throw const FormatException(
          'A collection contains duplicate source paths.',
        );
      }
      if (keys.length > 100000) {
        throw const FormatException(
          'A collection can hold up to 100,000 items.',
        );
      }
    }
  }

  FileCollection _pageCollection(
    FileCollectionManifest record,
    List<FileCollectionEntry> entries,
    Set<String> selected,
  ) => FileCollection(
    id: record.summary.id,
    name: record.summary.name,
    entries: entries,
    selectedKeys: selected,
    search: record.search,
    updatedAt: record.summary.updatedAt,
  );
  void _cachePage(String key, _CachedPage page) {
    if (page.bytes > cacheByteLimit || page.entries.length > cacheEntryLimit) {
      return;
    }
    final existing = _cache.remove(key);
    if (existing != null) {
      _cachedBytes -= existing.bytes;
      _cachedEntries -= existing.entries.length;
    }
    while (_cache.isNotEmpty &&
        (_cachedBytes + page.bytes > cacheByteLimit ||
            _cachedEntries + page.entries.length > cacheEntryLimit)) {
      final removed = _cache.remove(_cache.keys.first)!;
      _cachedBytes -= removed.bytes;
      _cachedEntries -= removed.entries.length;
    }
    _cache[key] = page;
    _cachedBytes += page.bytes;
    _cachedEntries += page.entries.length;
  }

  void _clearCache() {
    _cache.clear();
    _cachedBytes = 0;
    _cachedEntries = 0;
  }

  Stream<FileCollectionPage> pages(String id, {String? revision}) async* {
    final record = await manifest(id, revision: revision);
    for (var index = 0; index < record.pages.length; index++) {
      yield await _readPage(record, index);
    }
  }

  /// Explicit bounded materialization for JSON export/clipboard compatibility.
  /// Browsing, refresh, rename, appends, and operation rewrites use page APIs.
  Future<FileCollection> load(String id) async {
    final record = await manifest(id);
    final entries = <FileCollectionEntry>[];
    final selected = <String>{};
    for (var index = 0; index < record.pages.length; index++) {
      final page = await _readPage(record, index);
      entries.addAll(page.collection.entries);
      selected.addAll(page.collection.selectedKeys);
    }
    return _pageCollection(record, entries, selected);
  }

  Future<void> save(
    FileCollection collection, {
    String? expectedRevision,
    bool Function()? isCancelled,
  }) async {
    await ready;
    await _lock.synchronized(() async {
      final before = expectedRevision == null
          ? null
          : await _readManifest(collection.id, revision: expectedRevision);
      await _writeRows(
        collection,
        Stream.fromIterable(
          collection.entries.map(
            (entry) => (entry, collection.selectedKeys.contains(entry.key)),
          ),
        ),
        before: before,
        isCancelled: isCancelled,
      );
    });
  }

  Future<void> rename(String id, String name) async {
    await ready;
    await _lock.synchronized(() async {
      final before = await _readManifest(id);
      final metadata = _pageCollection(
        before,
        const [],
        const {},
      ).copyWith(name: name.trim());
      await _commit(metadata, before.pages, before: before);
    });
  }

  /// Transform all saved rows incrementally and commit one immutable revision.
  /// Exceptions/cancellation leave the entire previous record and marks intact.
  Future<void> transform(
    String id,
    Future<FileCollection> Function(FileCollection page) change, {
    bool Function()? isCancelled,
    String? expectedRevision,
  }) async {
    await ready;
    await _lock.synchronized(() async {
      _checkWritable();
      final before = await _readManifest(id, revision: expectedRevision);
      final descriptors = <CollectionPageDescriptor>[];
      final written = <String>[];
      final keys = <String>{};
      var changed = false;
      try {
        for (var index = 0; index < before.pages.length; index++) {
          if (isCancelled?.call() ?? false) {
            throw StateError('Collection update cancelled.');
          }
          final page = await _readPage(before, index);
          final after = await change(page.collection);
          _addUniqueKeys(keys, after.entries);
          if (identical(after, page.collection)) {
            descriptors.add(before.pages[index]);
            continue;
          }
          changed = true;
          if (after.entries.length > pageEntryLimit) {
            throw const FormatException('This collection page is too large.');
          }
          if (after.entries.isEmpty) continue;
          final key = 'page:${const Uuid().v4()}';
          written.add(key);
          descriptors.add(
            await _writePage(key, [
              for (final entry in after.entries)
                (entry, after.selectedKeys.contains(entry.key)),
            ]),
          );
        }
        if (isCancelled?.call() ?? false) {
          throw StateError('Collection update cancelled.');
        }
        if (changed) {
          await _commit(
            _pageCollection(before, const [], const {}),
            descriptors,
            before: before,
            isCancelled: isCancelled,
          );
        }
      } catch (error) {
        await _discardUncommitted(written, error);
        rethrow;
      }
    });
  }

  /// Apply a captured selection across any number of pages in one revision.
  /// The expected page identities prevent stale panes overwriting newer marks.
  Future<FileCollectionManifest> updateMarks(
    FileCollectionManifest expected,
    Map<int, Set<String>> selections, {
    bool Function()? isCancelled,
  }) async {
    await ready;
    return _lock.synchronized(() async {
      _checkWritable();
      final before = await _readManifest(expected.summary.id);
      final descriptors = List<CollectionPageDescriptor>.of(before.pages);
      final written = <String>[];
      try {
        for (final change in selections.entries) {
          if (isCancelled?.call() ?? false) {
            throw StateError('Collection selection cancelled.');
          }
          final index = change.key;
          if (index < 0 ||
              index >= expected.pages.length ||
              index >= before.pages.length ||
              expected.pages[index].key != before.pages[index].key) {
            throw StateError(
              'The collection marks changed. Reload before selecting again.',
            );
          }
          final page = await _readPage(before, index);
          final valid = page.collection.entries
              .map((entry) => entry.key)
              .toSet();
          if (!valid.containsAll(change.value)) {
            throw StateError(
              'The selection contains a row outside its captured page.',
            );
          }
          if (setEquals(page.collection.selectedKeys, change.value)) continue;
          final key = 'page:${const Uuid().v4()}';
          written.add(key);
          descriptors[index] = await _writePage(key, [
            for (final entry in page.collection.entries)
              (entry, change.value.contains(entry.key)),
          ]);
        }
        if (written.isEmpty) return before;
        if (isCancelled?.call() ?? false) {
          throw StateError('Collection selection cancelled.');
        }
        return await _commit(
          _pageCollection(before, const [], const {}),
          descriptors,
          before: before,
          isCancelled: isCancelled,
        );
      } catch (error) {
        await _discardUncommitted(written, error);
        rethrow;
      }
    });
  }

  /// Stream one saved collection into another without retaining their payloads.
  Future<void> appendCollection(
    String id,
    String sourceId, {
    bool selectedOnly = true,
  }) async {
    await ready;
    if (id == sourceId) return;
    await _lock.synchronized(() async {
      final before = await _readManifest(id);
      final source = await _readManifest(sourceId);
      final incoming = <String>{};
      for (var index = 0; index < source.pages.length; index++) {
        final page = await _readPage(source, index);
        for (final entry in page.collection.entries) {
          if (!selectedOnly ||
              page.collection.selectedKeys.contains(entry.key)) {
            incoming.add(entry.key);
          }
        }
      }
      final previousMarks = <String>{};
      Stream<(FileCollectionEntry, bool)> rows() async* {
        for (var index = 0; index < before.pages.length; index++) {
          final page = await _readPage(before, index);
          for (final entry in page.collection.entries) {
            final selected = page.collection.selectedKeys.contains(entry.key);
            if (incoming.contains(entry.key)) {
              if (selected) previousMarks.add(entry.key);
            } else {
              yield (entry, selected);
            }
          }
        }
        for (var index = 0; index < source.pages.length; index++) {
          final page = await _readPage(source, index);
          for (final entry in page.collection.entries) {
            if (incoming.contains(entry.key)) {
              yield (
                entry,
                previousMarks.contains(entry.key) ||
                    page.collection.selectedKeys.contains(entry.key),
              );
            }
          }
        }
      }

      await _writeRows(
        _pageCollection(before, const [], const {}).copyWith(clearSearch: true),
        rows(),
        before: before,
      );
    });
  }

  Future<void> updatePage(
    FileCollectionPage expected,
    FileCollection Function(FileCollection page) change,
  ) async {
    await ready;
    await _lock.synchronized(() async {
      _checkWritable();
      final before = await _readManifest(expected.summary.id);
      if (before.pages.isEmpty) {
        return;
      }
      if (expected.index >= before.pages.length ||
          before.pages[expected.index].key != expected.pageKey) {
        throw StateError(
          'This collection page changed. Reload it before saving marks.',
        );
      }
      final current = await _readPage(before, expected.index);
      final after = change(current.collection);
      if (after.entries.length > pageEntryLimit) {
        throw const FormatException('This collection page is too large.');
      }
      final addedKeys = after.entries.map((entry) => entry.key).toSet()
        ..removeAll(current.collection.entries.map((entry) => entry.key));
      // Mark-only changes retain their lazy single-page behavior. If paths
      // change, compare the new keys with every other page before any write.
      if (addedKeys.isNotEmpty) {
        for (var index = 0; index < before.pages.length; index++) {
          if (index == expected.index) continue;
          final page = await _readPage(before, index);
          if (page.collection.entries.any(
            (entry) => addedKeys.contains(entry.key),
          )) {
            throw const FormatException(
              'A collection contains duplicate source paths.',
            );
          }
        }
      }
      final key = 'page:${const Uuid().v4()}';
      try {
        final replacement = after.entries.isEmpty
            ? null
            : await _writePage(
                key,
                after.entries
                    .map(
                      (entry) =>
                          (entry, after.selectedKeys.contains(entry.key)),
                    )
                    .toList(),
              );
        final descriptors = List<CollectionPageDescriptor>.of(before.pages);
        if (replacement == null) {
          descriptors.removeAt(expected.index);
        } else {
          descriptors[expected.index] = replacement;
        }
        await _commit(
          _pageCollection(before, const [], const {}),
          descriptors,
          before: before,
        );
      } catch (error) {
        await _discardUncommitted([key], error);
        rethrow;
      }
    });
  }

  Future<void> copyCollection(
    String sourceId, {
    required String id,
    required String name,
    bool selectedOnly = false,
  }) async {
    await ready;
    await _lock.synchronized(() async {
      final source = await _readManifest(sourceId);
      Stream<(FileCollectionEntry, bool)> rows() async* {
        for (var index = 0; index < source.pages.length; index++) {
          final page = await _readPage(source, index);
          for (final entry in page.collection.entries) {
            final selected = page.collection.selectedKeys.contains(entry.key);
            if (!selectedOnly || selected) {
              yield (entry, selected);
            }
          }
        }
      }

      await _writeRows(
        FileCollection(
          id: id,
          name: name,
          entries: const [],
          search: selectedOnly ? null : source.search,
        ),
        rows(),
      );
    });
  }

  Future<void> append(String id, FileCollection additions) async {
    await ready;
    await _lock.synchronized(() async {
      final before = await _readManifest(id);
      final pending = {for (final entry in additions.entries) entry.key: entry};
      Stream<(FileCollectionEntry, bool)> rows() async* {
        for (var index = 0; index < before.pages.length; index++) {
          final page = await _readPage(before, index);
          for (final old in page.collection.entries) {
            final entry = pending.remove(old.key) ?? old;
            yield (
              entry,
              page.collection.selectedKeys.contains(old.key) ||
                  additions.selectedKeys.contains(entry.key),
            );
          }
        }
        for (final entry in pending.values) {
          yield (entry, additions.selectedKeys.contains(entry.key));
        }
      }

      await _writeRows(
        _pageCollection(before, const [], const {}).copyWith(clearSearch: true),
        rows(),
        before: before,
      );
    });
  }

  Future<void> _writeRows(
    FileCollection metadata,
    Stream<(FileCollectionEntry, bool)> rows, {
    FileCollectionManifest? before,
    bool Function()? isCancelled,
  }) async {
    _checkWritable();
    if (isCancelled?.call() ?? false) {
      throw StateError('Collection update cancelled.');
    }
    before ??= _collections.containsKey(metadata.id)
        ? await _readManifest(metadata.id)
        : null;
    final descriptors = <CollectionPageDescriptor>[];
    final pending = <(FileCollectionEntry, bool)>[];
    final keys = <String>{};
    final written = <String>[];
    var pendingBytes = 32;
    var totalBytes = 0;
    Future<void> flush() async {
      if (pending.isEmpty) {
        return;
      }
      final key = 'page:${const Uuid().v4()}';
      written.add(key);
      final descriptor = await _writePage(key, pending);
      totalBytes += descriptor.bytes;
      if (totalBytes > collectionByteLimit) {
        throw const FormatException(
          'Collection exceeds the 32 MiB storage limit.',
        );
      }
      descriptors.add(descriptor);
      pending.clear();
      pendingBytes = 32;
    }

    try {
      await for (final row in rows) {
        if (isCancelled?.call() ?? false) {
          throw StateError('Collection update cancelled.');
        }
        if (!keys.add(row.$1.key)) {
          throw const FormatException(
            'A collection contains duplicate source paths.',
          );
        }
        if (keys.length > 100000) {
          throw const FormatException(
            'A collection can hold up to 100,000 items.',
          );
        }
        final size =
            utf8
                .encode(
                  jsonEncode({'entry': row.$1.toJson(), 'selected': row.$2}),
                )
                .length +
            1;
        if (size + 32 > pageByteLimit) {
          throw const FormatException(
            'A collection row exceeds the 512 KiB page limit.',
          );
        }
        if (pending.length >= pageEntryLimit ||
            pendingBytes + size > pageByteLimit) {
          await flush();
        }
        pending.add(row);
        pendingBytes += size;
      }
      await flush();
      await _commit(
        metadata,
        descriptors,
        before: before,
        isCancelled: isCancelled,
      );
    } catch (error) {
      await _discardUncommitted(written, error);
      rethrow;
    }
  }

  Future<void> _discardUncommitted(Iterable<String> keys, Object error) async {
    // An unsuccessful acknowledgement does not prove the catalog stayed old.
    // Keep both revisions until a reload can establish the authoritative one.
    if (error is _UncertainCatalogCommit) return;
    for (final key in keys) {
      try {
        await _storage.remove(key);
      } catch (_) {
        // Uncommitted immutable records may safely remain after cleanup fails.
      }
    }
  }

  Future<CollectionPageDescriptor> _writePage(
    String key,
    List<(FileCollectionEntry, bool)> rows,
  ) async {
    final raw = jsonEncode({
      'version': 2,
      'rows': [
        for (final row in rows) {'entry': row.$1.toJson(), 'selected': row.$2},
      ],
    });
    final bytes = utf8.encode(raw).length;
    if (bytes > pageByteLimit) {
      throw const FormatException('A collection page exceeds 512 KiB.');
    }
    await _storage.write(key, raw);
    return CollectionPageDescriptor(
      key: key,
      count: rows.length,
      selectedCount: rows.where((row) => row.$2).length,
      bytes: bytes,
      digest: sha256.convert(utf8.encode(raw)).toString(),
      unavailableCount: rows.where((row) => _isUnavailable(row.$1)).length,
      sources: rows.map((row) => row.$1.reference.storage.id).toSet(),
    );
  }

  Future<FileCollectionManifest> _commit(
    FileCollection metadata,
    List<CollectionPageDescriptor> pages, {
    FileCollectionManifest? before,
    bool Function()? isCancelled,
  }) async {
    _checkWritable();
    final revision = const Uuid().v4();
    final summary = FileCollectionSummary(
      id: metadata.id,
      name: metadata.name,
      revision: revision,
      updatedAt: DateTime.now(),
      itemCount: pages.fold(0, (sum, page) => sum + page.count),
      selectedCount: pages.fold(0, (sum, page) => sum + page.selectedCount),
      unavailableCount: pages.fold(
        0,
        (sum, page) => sum + page.unavailableCount,
      ),
      sourceCount: pages.expand((page) => page.sources).toSet().length,
      hasSearch: metadata.search != null,
    );
    if (summary.itemCount > 100000 ||
        pages.fold<int>(0, (sum, page) => sum + page.bytes) >
            collectionByteLimit) {
      throw const FormatException(
        'Collection exceeds 100,000 items or 32 MiB.',
      );
    }
    final record = FileCollectionManifest(
      summary: summary,
      pages: List.unmodifiable(pages),
      search: metadata.search,
    );
    final raw = jsonEncode(record.toJson());
    if (utf8.encode(raw).length > manifestByteLimit) {
      throw const FormatException('Collection metadata exceeds 4 MiB.');
    }
    final manifestKey = _manifestKey(metadata.id, revision);
    final next = {..._collections, metadata.id: summary};
    try {
      await _storage.write(manifestKey, raw);
      // The catalog CAS is the atomic commit point. Cancellation before it
      // leaves the previous revision authoritative and removes staged pages.
      if (isCancelled?.call() ?? false) {
        throw StateError('Collection update cancelled.');
      }
      await _writeCatalog(next);
    } catch (error) {
      await _discardUncommitted([manifestKey], error);
      rethrow;
    }
    _collections[metadata.id] = summary;
    if (before != null) {
      final retained = pages.map((page) => page.key).toSet();
      for (final page in before.pages.where(
        (page) => !retained.contains(page.key),
      )) {
        final cached = _cache.remove(page.key);
        if (cached != null) {
          _cachedBytes -= cached.bytes;
          _cachedEntries -= cached.entries.length;
        }
        try {
          await _storage.remove(page.key);
        } catch (_) {
          /* Obsolete immutable record; safe to leave after commit. */
        }
      }
      try {
        await _storage.remove(
          _manifestKey(before.summary.id, before.summary.revision),
        );
      } catch (_) {
        /* Obsolete metadata. */
      }
    }
    _changed();
    return record;
  }

  Future<void> _writeCatalog(Map<String, FileCollectionSummary> next) async {
    if (next.length > collectionCountLimit) {
      throw const FormatException(
        'The collection catalog supports up to 10,000 collections.',
      );
    }
    final raw = jsonEncode({
      'version': 2,
      'collections': next.values.map((value) => value.toJson()).toList(),
    });
    if (utf8.encode(raw).length > catalogByteLimit) {
      throw const FormatException('Collection catalog exceeds 8 MiB.');
    }
    final expected = _catalogRaw;
    bool committed;
    try {
      committed = await _storage.compareAndSwap(_catalogKey, expected, raw);
    } catch (error, stack) {
      String? observed;
      try {
        observed = await _storage.read(_catalogKey, maxBytes: catalogByteLimit);
      } catch (_) {
        throw _uncertainCommit(error);
      }
      if (observed == raw) {
        // The durable catalog is the acknowledgement. Do not delete the
        // manifest/pages it has just made live when its write reply is lost.
        _catalogRaw = raw;
        return;
      }
      if (observed == expected) {
        Error.throwWithStackTrace(error, stack);
      }
      // A later writer may already have built on our revision. Keeping only
      // records directly mentioned in the proposed catalog would be unsafe.
      throw _uncertainCommit(error);
    }
    if (!committed) {
      throw StateError(
        'Another window changed the collection catalog. Reload and retry.',
      );
    }
    _catalogRaw = raw;
  }

  _UncertainCatalogCommit _uncertainCommit(Object cause) {
    _healthy = false;
    final error = _UncertainCatalogCommit(cause);
    _error(error.toString());
    return error;
  }

  Future<void> remove(String id) async {
    await ready;
    await _lock.synchronized(() async {
      _checkWritable();
      final before = await _readManifest(id);
      await _writeCatalog({..._collections}..remove(id));
      _collections.remove(id);
      for (final page in before.pages) {
        final cached = _cache.remove(page.key);
        if (cached != null) {
          _cachedBytes -= cached.bytes;
          _cachedEntries -= cached.entries.length;
        }
        try {
          await _storage.remove(page.key);
        } catch (_) {}
      }
      try {
        await _storage.remove(_manifestKey(id, before.summary.revision));
      } catch (_) {}
      _changed();
    });
  }

  Future<void> applyFileChanges(
    StorageReference storage,
    Map<String, FileItem?> replacements, {
    Set<String> removedDirectories = const {},
  }) async {
    await ready;
    for (final id in _collections.keys.toList()) {
      await transform(
        id,
        (page) async => const FileCollectionService().rewrite(
          page,
          storage,
          replacements,
          removedDirectories: removedDirectories,
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _clearCache();
    super.dispose();
  }
}

class _CachedPage {
  const _CachedPage(this.entries, this.selected, this.bytes, this.digest);
  final List<FileCollectionEntry> entries;
  final Set<String> selected;
  final int bytes;
  final String digest;
}

class _UncertainCatalogCommit extends StateError {
  _UncertainCatalogCommit(Object cause)
    : super(
        'The collection catalog commit could not be confirmed. '
        'Both revisions were kept. Reload before saving again. $cause',
      );
}
