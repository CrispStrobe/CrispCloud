import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import '../models/storage_analysis.dart';

/// One rectangle in an area-proportional, squarified layout.
class TreemapRect<T> {
  const TreemapRect(this.value, this.rect);

  final T value;
  final Rect rect;
}

class _WeightedItem<T> {
  _WeightedItem(this.value, this.weight, this.index);

  final T value;
  final double weight;
  final int index;
  double area = 0;
}

/// Partitions [bounds] in descending weight order without changing [items].
///
/// Nonpositive and nonfinite weights have no area. Weights are normalized
/// before summing so large byte counts cannot overflow the calculation. Ties
/// retain input order, making repeated layouts deterministic.
List<TreemapRect<T>> squarifyTreemap<T>(
  Iterable<T> items,
  Rect bounds,
  double Function(T item) weight,
) {
  if (!bounds.left.isFinite ||
      !bounds.top.isFinite ||
      !bounds.width.isFinite ||
      !bounds.height.isFinite ||
      bounds.width <= 0 ||
      bounds.height <= 0 ||
      !(bounds.width * bounds.height).isFinite) {
    return const [];
  }

  final weighted = <_WeightedItem<T>>[];
  var index = 0;
  for (final item in items) {
    final value = weight(item);
    if (value.isFinite && value > 0) {
      weighted.add(_WeightedItem(item, value, index));
    }
    index++;
  }
  if (weighted.isEmpty) return const [];
  weighted.sort((a, b) {
    final byWeight = b.weight.compareTo(a.weight);
    return byWeight == 0 ? a.index.compareTo(b.index) : byWeight;
  });

  final maximum = weighted.first.weight;
  final total = weighted.fold<double>(
    0,
    (sum, entry) => sum + entry.weight / maximum,
  );
  final area = bounds.width * bounds.height;
  for (final entry in weighted) {
    entry.area = (entry.weight / maximum) / total * area;
  }
  weighted.removeWhere((entry) => entry.area <= 0);
  if (weighted.isEmpty) return const [];

  final result = <TreemapRect<T>>[];
  var remaining = bounds;
  var start = 0;
  while (start < weighted.length && !remaining.isEmpty) {
    var end = start + 1;
    var rowArea = weighted[start].area;
    final largest = rowArea;
    var smallest = rowArea;
    final side = math.min(remaining.width, remaining.height);
    var worst = _worstRatio(rowArea, largest, smallest, side);
    while (end < weighted.length) {
      final candidate = weighted[end].area;
      final nextWorst = _worstRatio(
        rowArea + candidate,
        largest,
        candidate,
        side,
      );
      if (nextWorst > worst) break;
      rowArea += candidate;
      smallest = candidate;
      worst = nextWorst;
      end++;
    }

    final isLastRow = end == weighted.length;
    if (remaining.width >= remaining.height) {
      final width = isLastRow
          ? remaining.width
          : math.min(remaining.width, rowArea / remaining.height);
      var top = remaining.top;
      for (var i = start; i < end; i++) {
        final height = i == end - 1
            ? math.max(0.0, remaining.bottom - top)
            : math.min(remaining.bottom - top, weighted[i].area / width);
        result.add(
          TreemapRect(
            weighted[i].value,
            Rect.fromLTWH(remaining.left, top, width, height),
          ),
        );
        top += height;
      }
      remaining = Rect.fromLTWH(
        remaining.left + width,
        remaining.top,
        math.max(0.0, remaining.width - width),
        remaining.height,
      );
    } else {
      final height = isLastRow
          ? remaining.height
          : math.min(remaining.height, rowArea / remaining.width);
      var left = remaining.left;
      for (var i = start; i < end; i++) {
        final width = i == end - 1
            ? math.max(0.0, remaining.right - left)
            : math.min(remaining.right - left, weighted[i].area / height);
        result.add(
          TreemapRect(
            weighted[i].value,
            Rect.fromLTWH(left, remaining.top, width, height),
          ),
        );
        left += width;
      }
      remaining = Rect.fromLTWH(
        remaining.left,
        remaining.top + height,
        remaining.width,
        math.max(0.0, remaining.height - height),
      );
    }
    start = end;
  }
  return result;
}

double _worstRatio(double sum, double largest, double smallest, double side) {
  if (sum <= 0 || smallest <= 0 || side <= 0) return double.infinity;
  final sideSquared = side * side;
  final sumSquared = sum * sum;
  return math.max(
    sideSquared * largest / sumSquared,
    sumSquared / (sideSquared * smallest),
  );
}

/// A folder, file or explicit group of small siblings on the map.
///
/// An aggregate belongs to [node] (its containing folder); [aggregateCount]
/// counts its direct children and [bytes] preserves their combined area.
class StorageTreemapTile {
  const StorageTreemapTile({
    required this.node,
    required this.rect,
    required this.depth,
    required this.bytes,
    this.aggregateCount = 0,
    this.contentRect,
  });

  final StorageNode node;
  final Rect rect;
  final int depth;
  final int bytes;
  final int aggregateCount;
  final Rect? contentRect;

  bool get isAggregate => aggregateCount > 0;
  bool get isExpanded => contentRect != null;

  StorageTreemapTile _expanded(Rect content) => StorageTreemapTile(
    node: node,
    rect: rect,
    depth: depth,
    bytes: bytes,
    aggregateCount: aggregateCount,
    contentRect: content,
  );
}

class _LayoutEntry {
  const _LayoutEntry(this.node, this.bytes, [this.aggregateCount = 0]);

  final StorageNode node;
  final int bytes;
  final int aggregateCount;
}

class _FolderRegion {
  const _FolderRegion(this.node, this.rect, this.depth, [this.tileIndex]);

  final StorageNode node;
  final Rect rect;
  final int depth;
  final int? tileIndex;
}

/// Lays out nested folders with a bounded number of painted rectangles.
///
/// All positive known bytes remain represented. Tiny siblings and entries
/// beyond the paint budget are combined into a visibly distinct aggregate,
/// rather than discarded. Zero-byte and unknown-size items remain available
/// in the analyzer's accessible folder table. Folder headers consume space
/// inside their own rectangle, so sibling areas always compare like for like.
List<StorageTreemapTile> layoutStorageTreemap(
  StorageNode root,
  Size size, {
  int maxTiles = 1000,
  int maxDepth = 8,
  double minTileArea = 24,
  double folderHeaderHeight = 22,
}) {
  if (maxTiles <= 0 ||
      !size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0 ||
      !(size.width * size.height).isFinite) {
    return const [];
  }
  final bounds = Offset.zero & size;
  if (!root.isFolder) {
    return root.bytes > 0
        ? [StorageTreemapTile(node: root, rect: bounds, depth: 0, bytes: root.bytes)]
        : const [];
  }

  final result = <StorageTreemapTile>[];
  final pending = Queue<_FolderRegion>()
    ..add(_FolderRegion(root, bounds, 0));
  while (pending.isNotEmpty && result.length < maxTiles) {
    final folder = pending.removeFirst();
    final nodes = folder.node.children.where((node) => node.bytes > 0).toList()
      ..sort((a, b) {
        final byBytes = b.bytes.compareTo(a.bytes);
        return byBytes == 0 ? a.path.compareTo(b.path) : byBytes;
      });
    if (nodes.isEmpty) continue;
    final total = nodes.fold<int>(0, (sum, node) => sum + node.bytes);
    final available = maxTiles - result.length;
    final area = folder.rect.width * folder.rect.height;
    var individualCount = nodes.length;
    while (individualCount > 1 &&
        nodes[individualCount - 1].bytes / total * area < minTileArea) {
      individualCount--;
    }
    individualCount = math.min(individualCount, available);
    if (individualCount < nodes.length) {
      individualCount = math.min(individualCount, available - 1);
    }
    final entries = <_LayoutEntry>[
      for (var i = 0; i < individualCount; i++)
        _LayoutEntry(nodes[i], nodes[i].bytes),
      if (individualCount < nodes.length)
        _LayoutEntry(
          folder.node,
          nodes.skip(individualCount).fold<int>(0, (sum, node) => sum + node.bytes),
          nodes.length - individualCount,
        ),
    ];
    final rectangles = squarifyTreemap(
      entries,
      folder.rect,
      (entry) => entry.bytes.toDouble(),
    );
    if (rectangles.isEmpty) continue;
    if (folder.tileIndex != null) {
      result[folder.tileIndex!] = result[folder.tileIndex!]._expanded(folder.rect);
    }
    for (final cell in rectangles) {
      final entry = cell.value;
      final tileIndex = result.length;
      result.add(
        StorageTreemapTile(
          node: entry.node,
          rect: cell.rect,
          depth: folder.depth,
          bytes: entry.bytes,
          aggregateCount: entry.aggregateCount,
        ),
      );
      if (entry.aggregateCount == 0 &&
          entry.node.isFolder &&
          folder.depth < maxDepth &&
          cell.rect.width >= 48 &&
          cell.rect.height >= folderHeaderHeight + 24) {
        pending.add(
          _FolderRegion(
            entry.node,
            Rect.fromLTRB(
              cell.rect.left + 2,
              cell.rect.top + folderHeaderHeight,
              cell.rect.right - 2,
              cell.rect.bottom - 2,
            ),
            folder.depth + 1,
            tileIndex,
          ),
        );
      }
    }
  }
  return List.unmodifiable(result);
}
