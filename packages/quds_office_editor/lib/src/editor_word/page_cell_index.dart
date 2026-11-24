import 'dart:math' as math;
import 'dart:ui';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Locates table cells by paragraph range or position on a laid-out page.
final class WordPageCellIndex {
  WordPageCellIndex(this._frames);

  final List<LaidOutBox> _frames;
  late final _paragraphs = _ParagraphCells(_frames);
  late final pointer = WordPagePointerIndex._(_frames);
  late final _paintIndex = WordPagePaintIndex._(_frames);
  WordPagePaintIndex? _overlayIndex;

  WordPagePaintIndex? get paintIndex =>
      _frames.length <= WordPagePaintIndex._batchSize ? null : _paintIndex;

  WordPagePaintIndex? overlayIndexFor(
    int lineCount,
    Rect? Function(int) clipForLine,
  ) {
    if (lineCount <= WordPagePaintIndex._batchSize || _paragraphs.isEmpty) {
      return null;
    }
    return _overlayIndex ??= WordPagePaintIndex._forClips(
      lineCount,
      clipForLine,
    );
  }

  LaidOutBox? smallestAt(int paragraph, {WmlFrame? containingFrame}) =>
      _paragraphs.smallestAt(paragraph, containingFrame: containingFrame);

  bool anyAt(int paragraph, bool Function(LaidOutBox) matches) =>
      _paragraphs.anyAt(paragraph, matches);
}

/// Conservative bounds for consecutive boxes in paint order.
final class WordPagePaintIndex {
  WordPagePaintIndex._(List<LaidOutBox> boxes)
    : this._forClips(boxes.length, (index) {
        final box = boxes[index];
        // Non-cells may paint outside their layout box.
        return box.kind == LaidOutBoxKind.tableCell
            ? Rect.fromLTWH(box.x, box.y, box.width, box.height)
            : null;
      });

  WordPagePaintIndex._forClips(this._length, Rect? Function(int) clipAt) {
    for (var start = 0; start < _length; start += _batchSize) {
      _bounds.add(
        _batchBounds(clipAt, start, math.min(start + _batchSize, _length)),
      );
    }
  }

  static const _batchSize = 32;
  final int _length;
  final _bounds = <Rect?>[];

  static Rect? _batchBounds(Rect? Function(int) clipAt, int start, int end) {
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (var index = start; index < end; index++) {
      final clip = clipAt(index);
      if (clip == null || !clip.isFinite) return null;
      left = math.min(left, clip.left);
      top = math.min(top, clip.top);
      right = math.max(right, clip.right);
      bottom = math.max(bottom, clip.bottom);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// The next batch in drawing order, skipping batches entirely outside
  /// the viewport. [from] is zero or the end of the previous batch.
  ({int start, int end})? nextBatch(int from, Rect visibleCells) {
    if (from >= _length) return null;
    for (var batch = from ~/ _batchSize; batch < _bounds.length; batch++) {
      final bounds = _bounds[batch];
      if (bounds != null && !bounds.overlaps(visibleCells)) continue;
      final start = batch * _batchSize;
      return (start: start, end: math.min(start + _batchSize, _length));
    }
    return null;
  }
}

final class _ParagraphCells {
  _ParagraphCells(List<LaidOutBox> frames) {
    for (var order = 0; order < frames.length; order++) {
      final box = frames[order];
      if (box.kind != LaidOutBoxKind.tableCell) continue;
      if (box.paragraphIndex == null && box.paragraphEnd == null) continue;
      // Table-band selection can cover an end-only range, even though
      // the box does not own text for clipping.
      final start = box.paragraphIndex ?? -1;
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

  bool get isEmpty => _cells.isEmpty;

  int _afterStart(int paragraph) {
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
    return lower;
  }

  bool anyAt(int paragraph, bool Function(LaidOutBox) matches) {
    for (
      var index = _afterStart(paragraph) - 1;
      index >= 0 && _endsThrough[index] >= paragraph;
      index--
    ) {
      final cell = _cells[index];
      if (cell.end >= paragraph && matches(cell.box)) return true;
    }
    return false;
  }

  LaidOutBox? smallestAt(int paragraph, {WmlFrame? containingFrame}) {
    late final frameTables = WordTree.descendants(
      containingFrame!.blocks,
    ).whereType<WmlTable>().toSet();
    LaidOutBox? best;
    var bestArea = double.infinity;
    var bestOrder = _cells.length;
    for (
      var index = _afterStart(paragraph) - 1;
      index >= 0 && _endsThrough[index] >= paragraph;
      index--
    ) {
      final cell = _cells[index];
      final box = cell.box;
      if (cell.end < paragraph ||
          box.paragraphIndex == null ||
          box.height <= 0) {
        continue;
      }
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

/// The boxes pointer events or selection handles can target.
final class WordPagePointerIndex {
  WordPagePointerIndex._(this._boxes) {
    for (final box in _boxes) {
      if (box.kind == LaidOutBoxKind.tableCell) continue;
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

  final List<LaidOutBox> _boxes;
  late final _cells = _indexCells();
  late final _bottomsThrough = _indexCellBounds();
  final _equations = <LaidOutBox>[];
  final _frames = <LaidOutBox>[];
  final _visuals = <LaidOutBox>[];
  final _tocEntries = <LaidOutBox>[];

  List<({double bottom, int order, LaidOutBox box})> _indexCells() {
    final cells = <({double bottom, int order, LaidOutBox box})>[];
    for (final (order, box) in _boxes.indexed) {
      if (box.kind != LaidOutBoxKind.tableCell || !(box.height > 0)) continue;
      final bottom = box.y + box.height;
      if (!bottom.isNaN) cells.add((bottom: bottom, order: order, box: box));
    }
    cells.sort((left, right) => left.box.y.compareTo(right.box.y));
    return cells;
  }

  List<double> _indexCellBounds() {
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
