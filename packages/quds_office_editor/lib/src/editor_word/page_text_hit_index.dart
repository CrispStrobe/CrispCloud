import 'dart:ui';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Finds the text lines a pointer can hit without scanning unrelated rows.
final class WordPageTextHitIndex {
  WordPageTextHitIndex(LaidOutPage page) {
    var order = 0;
    for (final story in [page.header, page.lines, page.footer]) {
      for (final line in story) {
        final top = line.y - 2;
        final bottom = line.y + line.height + 2;
        if (top <= bottom) {
          _lines.add((top: top, bottom: bottom, order: order, line: line));
        }
        order++;
      }
    }
    _lines.sort((a, b) => a.top.compareTo(b.top));
    var furthestBottom = double.negativeInfinity;
    for (final entry in _lines) {
      if (entry.bottom > furthestBottom) furthestBottom = entry.bottom;
      _bottomsThrough.add(furthestBottom);
    }
  }

  final _lines = <({double top, double bottom, int order, LaidOutLine line})>[];
  final _bottomsThrough = <double>[];

  WmlHyperlink? linkAt(Offset point) => _firstHit(point.dy, (line) {
    if (line.hyperlink != null &&
        point.dx >= line.x - 4 &&
        point.dx <= line.x + line.width + 4) {
      return line.hyperlink;
    }
    for (final glyph in line.glyphs) {
      if (glyph.hyperlink != null &&
          point.dx >= glyph.x &&
          point.dx <= glyph.x + glyph.advance) {
        return glyph.hyperlink;
      }
    }
    return null;
  });

  int? commentIdAt(Offset point) => _firstHit(point.dy, (line) {
    for (final glyph in line.glyphs) {
      if (glyph.commentIds.isNotEmpty &&
          point.dx >= glyph.x - 2 &&
          point.dx <= glyph.x + glyph.advance + 2) {
        return glyph.commentIds.last;
      }
    }
    return null;
  });

  T? _firstHit<T extends Object>(double y, T? Function(LaidOutLine) hit) {
    var lower = 0;
    var upper = _lines.length;
    while (lower < upper) {
      final middle = lower + ((upper - lower) >> 1);
      if (_lines[middle].top <= y) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }

    T? best;
    int? bestOrder;
    // Keep header, body and footer precedence even when lines overlap or the
    // document order differs from the vertical order, as in tables and frames.
    for (
      var index = lower - 1;
      index >= 0 && _bottomsThrough[index] >= y;
      index--
    ) {
      final entry = _lines[index];
      if (entry.bottom < y || (bestOrder != null && entry.order >= bestOrder)) {
        continue;
      }
      final result = hit(entry.line);
      if (result != null) {
        best = result;
        bestOrder = entry.order;
      }
    }
    return best;
  }
}
