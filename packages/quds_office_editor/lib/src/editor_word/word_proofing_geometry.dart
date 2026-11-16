import 'dart:math' as math;
import 'dart:ui';

import 'package:quds_office_engine/quds_office_engine.dart';

import 'caret_engine.dart';

/// Maps original paragraph ranges into a layout story. Display-only note
/// labels, generated fields and other synthetic characters never own findings.
List<(int, int)> proofingLayoutRanges(LaidOutLine line, int start, int end) {
  final List<int?>? offsets = line.proofingOffsets;
  if (offsets == null) return <(int, int)>[(start, end)];
  if (start == end) {
    for (int i = 0; i < offsets.length; i++) {
      if (offsets[i] == start) return <(int, int)>[(i, i)];
    }
    return const <(int, int)>[];
  }
  final List<(int, int)> ranges = <(int, int)>[];
  int? runStart;
  // The final item is the insertion boundary after the last displayed unit.
  for (int i = 0; i < offsets.length - 1; i++) {
    final int? source = offsets[i];
    final bool inside = source != null && source >= start && source < end;
    if (inside) {
      runStart ??= i;
    } else if (runStart != null) {
      ranges.add((runStart, i));
      runStart = null;
    }
  }
  if (runStart != null) ranges.add((runStart, offsets.length - 1));
  return ranges;
}

/// Uses the same visual boxes as selection, including wrapping and bidi runs.
List<Rect> proofingRectsOnLine(
  LaidOutLine line,
  OfficeProofingFinding finding,
) {
  if (line.glyphs.isEmpty) return const <Rect>[];
  final List<Rect> rects = <Rect>[];
  for (final (int start, int end) in proofingLayoutRanges(
    line,
    finding.start,
    finding.end,
  )) {
    if (start == end) {
      final int first = line.glyphs
          .map((g) => g.glyph.logicalIndex)
          .reduce(math.min);
      final int last = line.glyphs.map((g) => g.logicalEnd).reduce(math.max);
      if (start >= first && start <= last) {
        final double x = CaretEngine.caretX(line, start);
        rects.add(Rect.fromLTWH(x - 1, line.y, 3, line.height));
      }
    } else {
      rects.addAll(
        CaretEngine.rangeRectsOnLine(line, line.y, line.height, start, end),
      );
    }
  }
  return rects;
}
