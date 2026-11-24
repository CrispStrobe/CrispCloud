import 'package:quds_office_engine/quds_office_engine.dart';

/// Resolves the innermost table cell for a paragraph on one laid-out page.
final class WordPageCellIndex {
  WordPageCellIndex(List<LaidOutBox> frames) {
    for (var order = 0; order < frames.length; order++) {
      final box = frames[order];
      final start = box.paragraphIndex;
      if (box.kind != LaidOutBoxKind.tableCell || start == null) continue;
      final end = box.paragraphEnd ?? start;
      if (end < start) continue;
      _cells.add((start: start, end: end, order: order, box: box));
    }
    _cells.sort((left, right) => left.start.compareTo(right.start));
    var furthestEnd = _cells.firstOrNull?.end ?? 0;
    for (final cell in _cells) {
      if (cell.end > furthestEnd) furthestEnd = cell.end;
      _endsThrough.add(furthestEnd);
    }
  }

  final _cells = <({int start, int end, int order, LaidOutBox box})>[];
  final _endsThrough = <int>[];

  LaidOutBox? smallestAt(int paragraph, {WmlFrame? containingFrame}) {
    // Only cells starting at or before this paragraph can own its text.
    var lower = 0;
    var upper = _cells.length;
    while (lower < upper) {
      final middle = lower + ((upper - lower) >> 1);
      if (_cells[middle].start <= paragraph) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    late final frameTables = WordTree.descendants(
      containingFrame!.blocks,
    ).whereType<WmlTable>().toSet();
    LaidOutBox? best;
    var bestArea = double.infinity;
    var bestOrder = _cells.length;
    for (
      var index = lower - 1;
      index >= 0 && _endsThrough[index] >= paragraph;
      index--
    ) {
      final cell = _cells[index];
      final box = cell.box;
      if (cell.end < paragraph || box.height <= 0) continue;
      if (containingFrame != null && !frameTables.contains(box.table)) {
        // An absolute frame's text must only be clipped by its own tables.
        continue;
      }
      final area = box.width * box.height;
      if (area < bestArea ||
          (best != null && area == bestArea && cell.order < bestOrder)) {
        best = box;
        bestArea = area;
        bestOrder = cell.order;
      }
    }
    return best;
  }
}
