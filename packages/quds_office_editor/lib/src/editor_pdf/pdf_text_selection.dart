import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:quds_office_engine/pdf_file.dart';

/// One caret/hit in visual run order (`page`, `run`, code-unit `offset`).
class PdfTextHit {
  /// PdfTextHit API.
  const PdfTextHit({
    required this.page,
    required this.run,
    required this.offset,
  });

  /// page API.
  final int page;

  /// run API.
  final int run;

  /// offset API.
  final int offset;

  /// compareTo API.
  int compareTo(PdfTextHit other) {
    if (page != other.page) {
      return page.compareTo(other.page);
    }
    if (run != other.run) {
      return run.compareTo(other.run);
    }
    return offset.compareTo(other.offset);
  }
}

/// Interactive PDF text range (ISO 32000 display-list runs).
class PdfTextSelection {
  /// PdfTextSelection API.
  const PdfTextSelection({required this.anchor, required this.extent});

  /// Collapsed caret.
  factory PdfTextSelection.collapsed(PdfTextHit hit) =>
      PdfTextSelection(anchor: hit, extent: hit);

  /// Whole [run] on [page].
  factory PdfTextSelection.run(int page, int runIndex, PdfTextRun run) {
    return PdfTextSelection(
      anchor: PdfTextHit(page: page, run: runIndex, offset: 0),
      extent: PdfTextHit(page: page, run: runIndex, offset: run.text.length),
    );
  }

  /// Word around [hit] using whitespace boundaries.
  factory PdfTextSelection.word(PdfTextHit hit, PdfTextRun run) {
    final String text = run.text;
    var start = hit.offset.clamp(0, text.length);
    var end = start;
    while (start > 0 && !_sep(text.codeUnitAt(start - 1))) {
      start--;
    }
    while (end < text.length && !_sep(text.codeUnitAt(end))) {
      end++;
    }
    if (start == end && end < text.length) {
      end++;
    }
    return PdfTextSelection(
      anchor: PdfTextHit(page: hit.page, run: hit.run, offset: start),
      extent: PdfTextHit(page: hit.page, run: hit.run, offset: end),
    );
  }

  /// Drag anchor.
  final PdfTextHit anchor;

  /// Drag extent.
  final PdfTextHit extent;

  /// isCollapsed API.
  bool get isCollapsed => anchor.compareTo(extent) == 0;

  /// Normalized start ≤ end.
  PdfTextSelection get normalized {
    return anchor.compareTo(extent) <= 0
        ? this
        : PdfTextSelection(anchor: extent, extent: anchor);
  }

  /// extendTo API.
  PdfTextSelection extendTo(PdfTextHit hit) =>
      PdfTextSelection(anchor: anchor, extent: hit);

  /// Unicode for copy / find.
  String plainText(List<PdfDisplayList> lists) {
    final StringBuffer buf = StringBuffer();
    _visit(lists, (int _, PdfTextRun run, int from, int to, bool breakBefore) {
      if (from >= to) {
        return;
      }
      if (buf.isNotEmpty && breakBefore) {
        buf.write('\n');
      }
      buf.write(run.text.substring(from, to));
    });
    return buf.toString();
  }

  /// Highlight boxes in page space, tagged with the page index.
  ///
  /// Same-line ranges use the pointer span, so an RTL drag to the left grows
  /// the highlight left instead of as an LTR offset bar.
  List<({int page, Rect rect})> boxes(List<PdfDisplayList> lists) {
    final List<({int page, Rect rect})> out = <({int page, Rect rect})>[];
    final PdfTextSelection n = normalized;
    if (lists.isEmpty) {
      return out;
    }
    if (n.anchor.page == n.extent.page && n.anchor.run == n.extent.run) {
      _visit(lists, (int page, PdfTextRun run, int from, int to, bool _) {
        if (from >= to) {
          return;
        }
        out.add((page: page, rect: sliceRect(run, from, to)));
      });
      return out;
    }
    // Select-page / select-all / drag from a run start through a run end:
    // every intervening run is highlighted. An x-band between the two
    // endpoint carets drops most of the page when those carets don't span it.
    if (_coversRunSpan(lists, n)) {
      _visit(lists, (int page, PdfTextRun run, int from, int to, bool _) {
        if (run.text.isEmpty && run.width <= 0) {
          return;
        }
        out.add((
          page: page,
          rect: Rect.fromLTWH(
            run.x,
            run.y,
            math.max(run.width, 1),
            math.max(run.height, 1),
          ),
        ));
      });
      return out;
    }
    final int p0 = n.anchor.page.clamp(0, lists.length - 1);
    final int p1 = n.extent.page.clamp(0, lists.length - 1);
    for (int p = p0; p <= p1; p++) {
      final List<PdfTextRun> runs = lists[p].runs;
      if (runs.isEmpty) {
        continue;
      }
      final PdfTextRun start =
          runs[(p == p0 ? n.anchor.run : 0).clamp(0, runs.length - 1)];
      final PdfTextRun end =
          runs[(p == p1 ? n.extent.run : runs.length - 1).clamp(
            0,
            runs.length - 1,
          )];
      final double x0 = math.min(
        caretX(start, p == p0 ? n.anchor.offset : 0),
        caretX(end, p == p1 ? n.extent.offset : end.text.length),
      );
      final double x1 = math.max(
        caretX(start, p == p0 ? n.anchor.offset : 0),
        caretX(end, p == p1 ? n.extent.offset : end.text.length),
      );
      final bool oneLine = sameLine(start, end);
      final double bandTop = math.min(start.y, end.y);
      final double bandBottom = math.max(start.y, end.y);
      for (final PdfTextRun run in runs) {
        final bool onStart = sameLine(run, start);
        final bool onEnd = sameLine(run, end);
        final bool middle =
            !oneLine &&
            !onStart &&
            !onEnd &&
            run.y > bandTop + 1 &&
            run.y < bandBottom - 1;
        if (!onStart && !onEnd && !middle) {
          continue;
        }
        if ((onStart || onEnd) &&
            (run.x + run.width < x0 - 0.4 || run.x > x1 + 0.4)) {
          continue;
        }
        out.add((
          page: p,
          rect: Rect.fromLTWH(run.x, run.y, math.max(run.width, 1), run.height),
        ));
      }
    }
    return out;
  }

  /// True when the range starts at a run boundary and ends at a run end,
  /// so every run between the indices belongs in the highlight.
  static bool _coversRunSpan(List<PdfDisplayList> lists, PdfTextSelection n) {
    if (n.anchor.offset != 0) {
      return false;
    }
    final int page = n.extent.page;
    if (page < 0 || page >= lists.length) {
      return false;
    }
    final List<PdfTextRun> runs = lists[page].runs;
    if (n.extent.run < 0 || n.extent.run >= runs.length) {
      return false;
    }
    return n.extent.offset >= runs[n.extent.run].text.length;
  }

  /// Primary visual run (highlight / redact fallback).
  PdfTextRun? primaryRun(List<PdfDisplayList> lists) {
    final PdfTextSelection n = normalized;
    if (n.anchor.page < 0 || n.anchor.page >= lists.length) {
      return null;
    }
    final List<PdfTextRun> runs = lists[n.anchor.page].runs;
    if (n.anchor.run < 0 || n.anchor.run >= runs.length) {
      return null;
    }
    return runs[n.anchor.run];
  }

  void _visit(
    List<PdfDisplayList> lists,
    void Function(int page, PdfTextRun run, int from, int to, bool breakBefore)
    emit,
  ) {
    final PdfTextSelection n = normalized;
    if (lists.isEmpty) {
      return;
    }
    final int p0 = n.anchor.page.clamp(0, lists.length - 1);
    final int p1 = n.extent.page.clamp(0, lists.length - 1);
    for (int p = p0; p <= p1; p++) {
      final List<PdfTextRun> runs = lists[p].runs;
      if (runs.isEmpty) {
        continue;
      }
      final int r0 = p == p0 ? n.anchor.run.clamp(0, runs.length - 1) : 0;
      final int r1 = p == p1
          ? n.extent.run.clamp(0, runs.length - 1)
          : runs.length - 1;
      for (int r = r0; r <= r1; r++) {
        final PdfTextRun run = runs[r];
        final int len = run.text.length;
        final int from = (p == p0 && r == n.anchor.run)
            ? n.anchor.offset.clamp(0, len)
            : 0;
        final int to = (p == p1 && r == n.extent.run)
            ? n.extent.offset.clamp(0, len)
            : len;
        emit(p, run, from, to, run.breakBefore);
      }
    }
  }

  /// Sub-rectangle of [run] for code units `[from, to)`.
  ///
  /// RTL runs store visual left at offset 0, so the highlight and hit test
  /// grow from the right edge. An LTR map paints the selection the wrong way.
  static Rect sliceRect(PdfTextRun run, int from, int to) {
    final int n = run.text.length;
    if (n <= 0 || run.width <= 0) {
      return Rect.fromLTWH(run.x, run.y, math.max(run.width, 1), run.height);
    }
    final int a = from.clamp(0, n);
    final int b = to.clamp(0, n);
    final double x0 = _xAt(run, a);
    final double x1 = _xAt(run, b);
    return Rect.fromLTRB(
      math.min(x0, x1),
      run.y,
      math.max(x0, x1),
      run.y + math.max(run.height, 1),
    );
  }

  /// Code-unit index at page-space [x].
  static int offsetAt(PdfTextRun run, double x) {
    final int n = run.text.length;
    if (n <= 0 || run.width <= 0) {
      return 0;
    }
    final double t = _isRtl(run.text)
        ? ((run.x + run.width - x) / run.width).clamp(0.0, 1.0)
        : ((x - run.x) / run.width).clamp(0.0, 1.0);
    return (t * n).round().clamp(0, n);
  }

  /// True when two runs share a visual line.
  ///
  /// The gap to the next line is usually about one em. A full font-size
  /// window treated the heading under a title as the same line.
  static bool sameLine(PdfTextRun a, PdfTextRun b) {
    final double h = math.min(math.max(a.height, 1), math.max(b.height, 1));
    return (a.y - b.y).abs() <= math.max(1.5, h * 0.45);
  }

  /// Page X of code-unit [offset]. RTL offset 0 is the right edge.
  static double caretX(PdfTextRun run, int offset) => _xAt(run, offset);

  static double _xAt(PdfTextRun run, int offset) {
    final int n = run.text.isEmpty ? 1 : run.text.length;
    final double t = offset.clamp(0, n) / n;
    if (_isRtl(run.text)) {
      return run.x + run.width * (1 - t);
    }
    return run.x + run.width * t;
  }

  static bool _isRtl(String text) {
    for (final int cp in text.runes) {
      if ((cp >= 0x0590 && cp <= 0x08FF) ||
          (cp >= 0xFB1D && cp <= 0xFDFF) ||
          (cp >= 0xFE70 && cp <= 0xFEFF)) {
        return true;
      }
      if ((cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A)) {
        return false;
      }
    }
    return false;
  }

  /// Hit-test pad so thin PDF em-boxes stay selectable.
  static bool containsPadded(PdfTextRun run, double x, double y) {
    const double pad = 3;
    return x >= run.x - pad &&
        y >= run.y - pad &&
        x <= run.x + run.width + pad &&
        y <= run.y + run.height + pad;
  }

  static bool _sep(int unit) {
    return unit == 0x20 ||
        unit == 0x09 ||
        unit == 0x0A ||
        unit == 0x0D ||
        unit == 0xA0;
  }
}
