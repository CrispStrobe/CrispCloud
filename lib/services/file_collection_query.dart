import '../models/file_collection.dart';
import '../models/file_collection_page.dart';
import '../models/file_item.dart';
import 'file_collection_store.dart';

class CollectionQueryRow {
  const CollectionQueryRow(this.entry, this.pageIndex);
  final FileCollectionEntry entry;
  final int pageIndex;
}

class CollectionQueryWindow {
  const CollectionQueryWindow({
    required this.manifest,
    required this.rows,
    required this.total,
    required this.start,
  });
  final FileCollectionManifest manifest;
  final List<CollectionQueryRow> rows;
  final int total;
  final int start;
  int get index => start ~/ FileCollectionQuery.windowSize;
  int get pageCount => total == 0
      ? 1
      : (total + FileCollectionQuery.windowSize - 1) ~/
            FileCollectionQuery.windowSize;
}

/// Collection-wide sorting/filtering with a bounded top-k heap. No metadata
/// index grows with the total number of saved rows. Adjacent windows scan the
/// pages using the previous window's stable sort cursor; account/path breaks
/// all comparator ties so equal names and hardlinks cannot vanish at boundaries.
class FileCollectionQuery {
  static const windowSize = 500;

  Future<CollectionQueryWindow> run(
    FileCollectionStore store,
    FileCollectionManifest manifest, {
    required Comparator<FileItem> compare,
    required bool Function(FileItem) matches,
    bool Function(FileCollectionEntry)? matchesEntry,
    Comparator<FileCollectionEntry>? compareEntry,
    FileCollectionEntry? after,
    FileCollectionEntry? before,
    bool last = false,
    bool Function()? isCancelled,
    void Function(int scanned, int total)? onProgress,
  }) async {
    if (after != null && before != null) {
      throw ArgumentError('Use one collection cursor.');
    }
    int order(FileCollectionEntry a, FileCollectionEntry b) {
      final primary = compareEntry?.call(a, b) ?? compare(a.file, b.file);
      return primary != 0 ? primary : a.key.compareTo(b.key);
    }

    final reverse = before != null || last;
    int desired(CollectionQueryRow a, CollectionQueryRow b) =>
        reverse ? order(b.entry, a.entry) : order(a.entry, b.entry);
    final heap = <CollectionQueryRow>[];
    void add(CollectionQueryRow row) {
      if (heap.length < windowSize) {
        heap.add(row);
        var child = heap.length - 1;
        while (child > 0) {
          final parent = (child - 1) ~/ 2;
          if (desired(heap[parent], heap[child]) >= 0) break;
          final swap = heap[parent];
          heap[parent] = heap[child];
          heap[child] = swap;
          child = parent;
        }
      } else if (desired(row, heap.first) < 0) {
        heap[0] = row;
        var parent = 0;
        while (parent * 2 + 1 < heap.length) {
          var child = parent * 2 + 1;
          if (child + 1 < heap.length &&
              desired(heap[child + 1], heap[child]) > 0) {
            child++;
          }
          if (desired(heap[parent], heap[child]) >= 0) break;
          final swap = heap[parent];
          heap[parent] = heap[child];
          heap[child] = swap;
          parent = child;
        }
      }
    }

    var total = 0;
    var eligible = 0;
    var preceding = 0;
    var scanned = 0;
    await for (final page in store.pages(
      manifest.summary.id,
      revision: manifest.summary.revision,
    )) {
      if (isCancelled?.call() ?? false) {
        throw StateError('Collection query cancelled.');
      }
      for (final entry in page.collection.entries) {
        if (!matches(entry.file) || !(matchesEntry?.call(entry) ?? true)) {
          continue;
        }
        total++;
        if (after != null && order(entry, after) <= 0) {
          preceding++;
          continue;
        }
        if (before != null && order(entry, before) >= 0) continue;
        eligible++;
        add(CollectionQueryRow(entry, page.index));
      }
      scanned += page.collection.entries.length;
      onProgress?.call(scanned, manifest.summary.itemCount);
    }
    if (isCancelled?.call() ?? false) {
      throw StateError('Collection query cancelled.');
    }
    heap.sort((a, b) => order(a.entry, b.entry));
    if (last && total % windowSize != 0 && heap.length > total % windowSize) {
      heap.removeRange(0, heap.length - total % windowSize);
    }
    return CollectionQueryWindow(
      manifest: manifest,
      rows: List.unmodifiable(heap),
      total: total,
      start: reverse ? eligible - heap.length : preceding,
    );
  }
}
