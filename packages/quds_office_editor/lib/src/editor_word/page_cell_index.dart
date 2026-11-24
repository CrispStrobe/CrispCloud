import 'package:quds_office_engine/quds_office_engine.dart';

/// Resolves the innermost table cell for a paragraph on one laid-out page.
final class WordPageCellIndex {
  WordPageCellIndex(this._frames);

  final List<LaidOutBox> _frames;
  late final _paragraphs = _ParagraphCells(_frames);
  late final pointer = WordPagePointerIndex._(_frames);

  LaidOutBox? smallestAt(int paragraph, {WmlFrame? containingFrame}) =>
      _paragraphs.smallestAt(paragraph, containingFrame: containingFrame);
}

final class _ParagraphCells {
  _ParagraphCells(List<LaidOutBox> frames) {
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

/// The boxes pointer events can target, built only when a page is interacted with.
final class WordPagePointerIndex {
  WordPagePointerIndex._(List<LaidOutBox> boxes) {
    for (final (order, box) in boxes.indexed) {
      if (box.kind == LaidOutBoxKind.tableCell) {
        final bottom = box.y + box.height;
        if (box.height > 0 && !bottom.isNaN) {
          _cells.add((bottom: bottom, order: order, box: box));
        }
        continue;
      }
      if (box.kind == LaidOutBoxKind.equation && box.equation != null) {
        _equations.add(box);
      }
      if (box.kind == LaidOutBoxKind.frame && box.frame != null) {
        _frames.add(box);
      }
      if (box.visual != null) _visuals.add(box);
      if (box.kind == LaidOutBoxKind.tocEntry && box.paragraphIndex != null) {
        _tocEntries.add(box);
      }
    }
  }

  final _cells = <({double bottom, int order, LaidOutBox box})>[];
  late final _bottomsThrough = _indexCellBounds();
  final _equations = <LaidOutBox>[];
  final _frames = <LaidOutBox>[];
  final _visuals = <LaidOutBox>[];
  final _tocEntries = <LaidOutBox>[];

  List<double> _indexCellBounds() {
    _cells.sort((left, right) => left.box.y.compareTo(right.box.y));
    var furthestBottom = double.negativeInfinity;
    final bottomsThrough = <double>[];
    for (final cell in _cells) {
      if (cell.bottom > furthestBottom) furthestBottom = cell.bottom;
      bottomsThrough.add(furthestBottom);
    }
    return bottomsThrough;
  }

  Iterable<LaidOutBox> get equations => _equations;
  Iterable<LaidOutBox> get frames => _frames;
  Iterable<LaidOutBox> get visuals => _visuals;
  Iterable<LaidOutBox> get tocEntriesInHitOrder => _tocEntries.reversed;

  LaidOutBox? cellAt(double x, double y) {
    final bottomsThrough = _bottomsThrough;
    var lower = 0;
    var upper = _cells.length;
    while (lower < upper) {
      final middle = lower + ((upper - lower) >> 1);
      if (_cells[middle].box.y <= y) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    LaidOutBox? best;
    var bestArea = double.infinity;
    var bestOrder = 0;
    // Earlier rows can be skipped once none of their cells reaches y.
    for (
      var index = lower - 1;
      index >= 0 && bottomsThrough[index] >= y;
      index--
    ) {
      final cell = _cells[index];
      final box = cell.box;
      if (cell.bottom < y || !(x >= box.x && x <= box.x + box.width)) {
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
