import 'dart:collection';

import '../models/file_collection_page.dart';
import '../models/file_collection.dart';
import '../models/file_item.dart';
import '../utils/async_lock.dart';
import 'file_collection_store.dart';

String collectionRowKey(FileItem file) => '${file.storageId}\u0000${file.path}';

class CollectionViewProjection {
  const CollectionViewProjection({
    required this.owner,
    required this.signature,
    required this.matches,
    required this.compare,
  });
  final Object owner;
  final Object signature;
  final bool Function(FileCollectionEntry) matches;
  final Comparator<FileCollectionEntry> compare;
}

class CollectionRememberedRow {
  const CollectionRememberedRow({
    required this.objectId,
    required this.isFolder,
    required this.isSymlink,
    required this.storageId,
  });
  final String? objectId;
  final bool isFolder;
  final bool? isSymlink;
  final String storageId;
}

class CollectionSelectionMemory {
  const CollectionSelectionMemory({
    required this.rows,
    required this.sourceGuards,
    required this.bytes,
  });
  final Map<String, CollectionRememberedRow> rows;
  final Map<String, bool Function()> sourceGuards;
  final int bytes;
}

/// Only the active collection keeps compact mark identities. Inactive tabs keep
/// their collection ID/page number and obtain marks from persisted pages.
class CollectionMarkSession {
  CollectionMarkSession(this.manifest);
  FileCollectionManifest manifest;
  final Map<String, int> rowPages = {};
  final Map<String, int> saved = {};
  final Map<String, int> desired = {};
  final _lock = AsyncLock();

  Future<FileCollectionManifest> flush(FileCollectionStore store) =>
      _lock.synchronized(() async {
        final snapshot = Map<String, int>.of(desired);
        manifest = await _writeSnapshot(store, snapshot);
        saved
          ..clear()
          ..addAll(snapshot);
        return manifest;
      });

  /// A bulk selection becomes visible only after its cancellable page commit.
  /// Queued tab departure therefore cannot accidentally save a cancelled stage.
  Future<FileCollectionManifest> replaceMarks(
    FileCollectionStore store,
    Map<String, int> next, {
    bool Function()? isCancelled,
  }) => _lock.synchronized(() async {
    final snapshot = Map<String, int>.of(next);
    manifest = await _writeSnapshot(store, snapshot, isCancelled: isCancelled);
    saved
      ..clear()
      ..addAll(snapshot);
    desired
      ..clear()
      ..addAll(snapshot);
    return manifest;
  });

  Future<FileCollectionManifest> _writeSnapshot(
    FileCollectionStore store,
    Map<String, int> snapshot, {
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) {
      throw StateError('Collection selection cancelled.');
    }
    final changedPages = <int>{};
    for (final mark in saved.entries) {
      if (!snapshot.containsKey(mark.key)) changedPages.add(mark.value);
    }
    for (final mark in snapshot.entries) {
      if (!saved.containsKey(mark.key)) changedPages.add(mark.value);
    }
    if (changedPages.isEmpty) return manifest;
    final updates = {for (final index in changedPages) index: <String>{}};
    for (final mark in snapshot.entries) {
      updates[mark.value]?.add(mark.key);
    }
    return store.updateMarks(manifest, updates, isCancelled: isCancelled);
  }
}

/// A page's paths, rather than provider object IDs alone, identify its marks.
/// Hardlinks and same-path rows belonging to separate accounts remain distinct.
class PanelSelection extends SetBase<FileItem> {
  PanelSelection({
    required this.paged,
    required this.onAdd,
    required this.onRemove,
    required this.onClear,
    required this.canMutate,
  });
  final bool Function() paged;
  final void Function(FileItem) onAdd;
  final void Function(FileItem) onRemove;
  final void Function() onClear;
  final bool Function() canMutate;
  final Map<Object, FileItem> _values = {};
  Object _key(FileItem value) => paged() ? collectionRowKey(value) : value;
  @override
  bool add(FileItem value) {
    if (!canMutate()) return false;
    final key = _key(value);
    final added = !_values.containsKey(key);
    _values[key] = value;
    if (added) onAdd(value);
    return added;
  }

  @override
  bool contains(Object? element) =>
      element is FileItem && _values.containsKey(_key(element));
  @override
  bool remove(Object? value) {
    if (!canMutate()) return false;
    if (value is! FileItem) return false;
    final removed = _values.remove(_key(value));
    if (removed == null) return false;
    onRemove(removed);
    return true;
  }

  @override
  void clear() {
    if (!canMutate()) return;
    if (_values.isEmpty) return;
    _values.clear();
    onClear();
  }

  @override
  FileItem? lookup(Object? element) =>
      element is FileItem ? _values[_key(element)] : null;
  @override
  Iterator<FileItem> get iterator => _values.values.iterator;
  @override
  int get length => _values.length;
  @override
  Set<FileItem> toSet() => Set<FileItem>.identity()..addAll(_values.values);
}
