import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import '../models/storage_analysis.dart';

const _fullCircle = math.pi * 2;

/// A byte-proportional angular sector at one level of a folder hierarchy.
///
/// A grouped sector belongs to [node], the containing folder. Its [bytes] and
/// [aggregateCount] include all grouped positive-size direct children. Folder
/// sectors already represent their entire subtree, including depths that are
/// not expanded because of the rendering budget.
class StorageSunburstSegment {
  const StorageSunburstSegment({
    required this.node,
    required this.depth,
    required this.bytes,
    required this.startAngle,
    required this.sweepAngle,
    required this.innerRadius,
    required this.outerRadius,
    this.aggregateCount = 0,
    this.isExpanded = false,
  });

  final StorageNode node;
  final int depth;
  final int bytes;
  final double startAngle;
  final double sweepAngle;
  final double innerRadius;
  final double outerRadius;
  final int aggregateCount;
  final bool isExpanded;

  bool get isAggregate => aggregateCount > 0;
  double get middleAngle => startAngle + sweepAngle / 2;

  Offset middlePoint(Offset center) =>
      center +
      Offset.fromDirection(middleAngle, (innerRadius + outerRadius) / 2);

  /// The exact sector, also used for clipping labels and hover outlines.
  Path path(Offset center, {double? outerLimit}) {
    final outer = outerLimit ?? outerRadius;
    return Path()
      ..moveTo(
        center.dx + math.cos(startAngle) * innerRadius,
        center.dy + math.sin(startAngle) * innerRadius,
      )
      ..lineTo(
        center.dx + math.cos(startAngle) * outer,
        center.dy + math.sin(startAngle) * outer,
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: outer),
        startAngle,
        sweepAngle,
        false,
      )
      ..lineTo(
        center.dx + math.cos(startAngle + sweepAngle) * innerRadius,
        center.dy + math.sin(startAngle + sweepAngle) * innerRadius,
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: innerRadius),
        startAngle + sweepAngle,
        -sweepAngle,
        false,
      )
      ..close();
  }
}

class StorageSunburstLayout {
  const StorageSunburstLayout({
    required this.center,
    required this.radius,
    required this.holeRadius,
    required this.ringCount,
    required this.segments,
  });

  final Offset center;
  final double radius;
  final double holeRadius;
  final int ringCount;
  final List<StorageSunburstSegment> segments;

  StorageSunburstSegment? hitTest(Offset position) {
    final offset = position - center;
    final distance = offset.distance;
    if (distance < holeRadius || distance > radius) return null;
    final angle =
        (math.atan2(offset.dy, offset.dx) + math.pi / 2) % _fullCircle;
    for (final segment in segments) {
      if (distance < segment.innerRadius || distance >= segment.outerRadius) {
        continue;
      }
      final start = segment.startAngle + math.pi / 2;
      if (angle >= start && angle < start + segment.sweepAngle) return segment;
    }
    return null;
  }
}

class _PendingFolder {
  const _PendingFolder(
    this.node,
    this.start,
    this.sweep,
    this.depth, [
    this.index,
  ]);

  final StorageNode node;
  final double start;
  final double sweep;
  final int depth;
  final int? index;
}

class _Sector {
  _Sector(
    this.node,
    this.bytes,
    this.start,
    this.sweep,
    this.depth, [
    this.aggregateCount = 0,
  ]);

  final StorageNode node;
  final int bytes;
  final double start;
  final double sweep;
  final int depth;
  final int aggregateCount;
  bool expanded = false;
}

/// Builds a bounded sunburst without recursively walking arbitrarily deep trees.
///
/// Each expanded folder's next ring partitions the same angular interval in
/// proportion to the children's known bytes. Tiny siblings and entries beyond
/// [maxSegments] are combined, never dropped. Files and unexpanded folders end
/// at their own ring; their bytes are not counted again in later rings. Unknown
/// sizes and zero-byte items remain available in the analyzer's folder list.
StorageSunburstLayout layoutStorageSunburst(
  StorageNode root,
  Size size, {
  int maxSegments = 600,
  int maxDepth = 5,
  double minSweepAngle = 0.012,
}) {
  if (maxSegments <= 0 ||
      maxDepth <= 0 ||
      !size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 16 ||
      size.height <= 16) {
    return const StorageSunburstLayout(
      center: Offset.zero,
      radius: 0,
      holeRadius: 0,
      ringCount: 0,
      segments: [],
    );
  }
  final center = Offset(size.width / 2, size.height / 2);
  final radius = math.min(size.width, size.height) / 2 - 8;
  final hole = radius * 0.29;
  final levels = math.min(
    maxDepth,
    math.max(1, ((radius - hole) / 26).floor()),
  );
  final minSweep = minSweepAngle.isFinite
      ? minSweepAngle.clamp(0.0, _fullCircle)
      : 0.012;
  final sectors = <_Sector>[];
  final pending = Queue<_PendingFolder>();
  if (root.isFolder) {
    pending.add(_PendingFolder(root, -math.pi / 2, _fullCircle, 0));
  } else if (root.bytes > 0 && root.item.isSymlink != true) {
    sectors.add(_Sector(root, root.bytes, -math.pi / 2, _fullCircle, 0));
  }
  while (pending.isNotEmpty && sectors.length < maxSegments) {
    final folder = pending.removeFirst();
    final children =
        folder.node.children
            .where((node) => node.bytes > 0 && node.item.isSymlink != true)
            .toList()
          ..sort((a, b) {
            final size = b.bytes.compareTo(a.bytes);
            return size == 0 ? a.path.compareTo(b.path) : size;
          });
    if (children.isEmpty) continue;
    final total = children.fold<int>(0, (sum, child) => sum + child.bytes);
    final available = maxSegments - sectors.length;
    var individual = children.length;
    while (individual > 0 &&
        children[individual - 1].bytes / total * folder.sweep < minSweep) {
      individual--;
    }
    final needed = individual + (individual < children.length ? 1 : 0);
    if (needed > available) individual = math.max(0, available - 1);
    final count = individual + (individual < children.length ? 1 : 0);
    if (folder.index != null) sectors[folder.index!].expanded = true;
    var start = folder.start;
    for (var index = 0; index < count; index++) {
      final grouped = index == individual;
      final node = grouped ? folder.node : children[index];
      final bytes = grouped
          ? children
                .skip(individual)
                .fold<int>(0, (sum, node) => sum + node.bytes)
          : node.bytes;
      final sweep = index == count - 1
          ? folder.start + folder.sweep - start
          : bytes / total * folder.sweep;
      final segmentIndex = sectors.length;
      sectors.add(
        _Sector(
          node,
          bytes,
          start,
          sweep,
          folder.depth,
          grouped ? children.length - individual : 0,
        ),
      );
      if (!grouped &&
          node.isFolder &&
          folder.depth + 1 < levels &&
          sweep >= minSweep * 2) {
        pending.add(
          _PendingFolder(node, start, sweep, folder.depth + 1, segmentIndex),
        );
      }
      start += sweep;
    }
  }
  final rings = sectors.fold<int>(
    0,
    (count, sector) => math.max(count, sector.depth + 1),
  );
  final width = rings == 0 ? 0.0 : (radius - hole) / rings;
  return StorageSunburstLayout(
    center: center,
    radius: radius,
    holeRadius: hole,
    ringCount: rings,
    segments: List.unmodifiable([
      for (final sector in sectors)
        StorageSunburstSegment(
          node: sector.node,
          depth: sector.depth,
          bytes: sector.bytes,
          startAngle: sector.start,
          sweepAngle: sector.sweep,
          innerRadius: hole + sector.depth * width,
          outerRadius: hole + (sector.depth + 1) * width,
          aggregateCount: sector.aggregateCount,
          isExpanded: sector.expanded,
        ),
    ]),
  );
}
