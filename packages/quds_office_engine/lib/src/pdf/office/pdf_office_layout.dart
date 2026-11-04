import 'dart:math' as math;
import 'dart:typed_data';

import '../../bidi/arabic_shaping.dart';
import '../../visual/png_bytes.dart';
import '../file/interp/pdf_display_list.dart';
import '../file/model/pdf_annot.dart';
import '../file/model/pdf_file.dart';
import '../file/model/pdf_page_info.dart';
import 'pdf_office_model.dart';

/// Rebuilds lines, ruled tables, and embeddable images from a [PdfFile].
abstract final class PdfOfficeLayout {
  /// PdfOfficeLayout API.
  static PdfOfficeRecovery recover(
    PdfFile file, {
    void Function(int index, int count)? onPage,
  }) {
    final List<PdfOfficePage> pages = <PdfOfficePage>[];
    final List<PdfOfficeNotice> notices = <PdfOfficeNotice>[];
    final List<PdfOfficeTocEntry> toc = _outlineToc(file.outline);
    final int count = file.pageCount;
    for (var i = 0; i < count; i++) {
      onPage?.call(i, count);
      final _PageBuild built = _PageBuild.read(
        file.displayList(i),
        i,
        notices,
        toc,
      );
      pages.add(built.page);
    }
    return PdfOfficeRecovery(pages: pages, notices: notices, toc: toc);
  }
}

class _Glyph {
  _Glyph(this.op);

  final PdfDrawText op;
}

class _Seg {
  _Seg(this.x1, this.y1, this.x2, this.y2);

  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

class _PageBuild {
  _PageBuild(this.page);

  final PdfOfficePage page;

  static _PageBuild read(
    PdfDisplayList list,
    int index,
    List<PdfOfficeNotice> notices,
    List<PdfOfficeTocEntry> toc,
  ) {
    final List<_Glyph> glyphs = <_Glyph>[];
    final List<PdfTextRun> runs = <PdfTextRun>[
      for (final PdfTextRun run in list.runs)
        if (run.text.trim().isNotEmpty) run,
    ];
    final List<_Seg> strokes = <_Seg>[];
    final List<PdfOfficeImage> images = <PdfOfficeImage>[];
    for (final PdfPaintOp op in list.ops) {
      switch (op) {
        case PdfDrawText():
          if (op.text.isEmpty) {
            break;
          }
          if (_duplicate(glyphs, op)) {
            break;
          }
          if (op.angle.abs() > 0.02) {
            notices.add(
              PdfOfficeNotice(
                kind: PdfOfficeNoticeKind.rotationFlattened,
                message: 'Rotated text was written as a horizontal line.',
                pageIndex: index,
              ),
            );
          }
          glyphs.add(_Glyph(op));
        case PdfStrokePath():
          strokes.addAll(_segments(op.points));
        case PdfDrawImage():
          images.add(_image(op, index, notices));
        case PdfFillPath():
        case PdfClipPath():
        case PdfSaveGState():
        case PdfRestoreGState():
          break;
      }
    }
    final List<_Glyph> free = List<_Glyph>.of(glyphs);
    final List<_Box> fills = _fillBoxes(
      list.ops,
      list.page.width,
      list.page.height,
    );
    final List<PdfOfficeTable> tables = _withHeaderFills(
      _tables(strokes, free, list.page.width, list.page.height),
      fills,
    );
    final List<PdfOfficeChart> charts = _charts(fills, tables, free, list);
    final List<PdfOfficeLine> lines = _annotateLines(
      free.isNotEmpty ? _linesFromGlyphs(free) : _linesFromRuns(runs),
      list,
      index,
      toc,
    );
    if (lines.isEmpty && !_tableHasText(tables) && charts.isEmpty) {
      notices.add(
        PdfOfficeNotice(
          kind: PdfOfficeNoticeKind.noExtractableText,
          message: pdfOfficeNoTextMessage,
          pageIndex: index,
        ),
      );
    }
    return _PageBuild(
      PdfOfficePage(
        index: index,
        width: list.page.width,
        height: list.page.height,
        lines: lines,
        tables: tables,
        images: images,
        charts: charts,
      ),
    );
  }
}

List<_Seg> _segments(List<PdfPathVerb> points) {
  final List<_Seg> out = <_Seg>[];
  double cx = 0;
  double cy = 0;
  double sx = 0;
  double sy = 0;
  var started = false;
  for (final PdfPathVerb verb in points) {
    switch (verb.kind) {
      case PdfPathKind.move:
        cx = verb.x;
        cy = verb.y;
        sx = verb.x;
        sy = verb.y;
        started = true;
      case PdfPathKind.line:
        if (started) {
          out.add(_Seg(cx, cy, verb.x, verb.y));
        }
        cx = verb.x;
        cy = verb.y;
      case PdfPathKind.close:
        if (started) {
          out.add(_Seg(cx, cy, sx, sy));
        }
        cx = sx;
        cy = sy;
      case PdfPathKind.cubic:
        cx = verb.x3;
        cy = verb.y3;
      case PdfPathKind.rect:
        break;
    }
  }
  return out;
}

List<PdfOfficeTable> _tables(
  List<_Seg> strokes,
  List<_Glyph> free,
  double pageW,
  double pageH,
) {
  final List<_Seg> horizontal = <_Seg>[];
  final List<_Seg> vertical = <_Seg>[];
  for (final _Seg seg in strokes) {
    final double dx = (seg.x2 - seg.x1).abs();
    final double dy = (seg.y2 - seg.y1).abs();
    if (dy <= 1.2 && dx >= 8) {
      horizontal.add(seg);
    } else if (dx <= 1.2 && dy >= 8) {
      vertical.add(seg);
    }
  }
  if (horizontal.length < 3 || vertical.length < 3) {
    return const <PdfOfficeTable>[];
  }
  final List<double> xs = _cluster(<double>[
    for (final _Seg s in vertical) (s.x1 + s.x2) / 2,
  ], 2);
  final List<double> ys = _cluster(<double>[
    for (final _Seg s in horizontal) (s.y1 + s.y2) / 2,
  ], 2);
  if (xs.length < 3 || ys.length < 3 || xs.length > 48 || ys.length > 48) {
    return const <PdfOfficeTable>[];
  }
  final int rowCount = ys.length - 1;
  final int colCount = xs.length - 1;
  final List<List<bool>> ruled = <List<bool>>[
    for (var r = 0; r < rowCount; r++)
      <bool>[
        for (var c = 0; c < colCount; c++)
          _cellRuled(horizontal, vertical, xs[c], xs[c + 1], ys[r], ys[r + 1]),
      ],
  ];
  final List<({int r0, int c0, int r1, int c1})> spans =
      <({int r0, int c0, int r1, int c1})>[];
  for (var r0 = 0; r0 < rowCount; r0++) {
    for (var c0 = 0; c0 < colCount; c0++) {
      if (!ruled[r0][c0]) {
        continue;
      }
      var c1 = c0;
      while (c1 + 1 < colCount && ruled[r0][c1 + 1]) {
        c1++;
      }
      if (c1 == c0) {
        continue;
      }
      var r1 = r0;
      while (r1 + 1 < rowCount && _spanRuled(ruled, r1 + 1, c0, c1)) {
        r1++;
      }
      if (r1 == r0) {
        continue;
      }
      spans.add((r0: r0, c0: c0, r1: r1, c1: c1));
    }
  }
  spans.sort((a, b) {
    final int areaA = (a.r1 - a.r0 + 1) * (a.c1 - a.c0 + 1);
    final int areaB = (b.r1 - b.r0 + 1) * (b.c1 - b.c0 + 1);
    return areaB.compareTo(areaA);
  });
  final List<PdfOfficeTable> tables = <PdfOfficeTable>[];
  final List<({int r0, int c0, int r1, int c1})> taken =
      <({int r0, int c0, int r1, int c1})>[];
  for (final ({int r0, int c0, int r1, int c1}) span in spans) {
    if (taken.any(
      (({int r0, int c0, int r1, int c1}) other) =>
          span.r0 <= other.r1 &&
          other.r0 <= span.r1 &&
          span.c0 <= other.c1 &&
          other.c0 <= span.c1,
    )) {
      continue;
    }
    final PdfOfficeTable? table = _tableFromSpan(
      span,
      xs,
      ys,
      free,
      pageW,
      pageH,
    );
    if (table == null) {
      continue;
    }
    taken.add(span);
    tables.add(table);
  }
  return tables;
}

bool _spanRuled(List<List<bool>> ruled, int row, int c0, int c1) {
  for (var c = c0; c <= c1; c++) {
    if (!ruled[row][c]) {
      return false;
    }
  }
  return true;
}

PdfOfficeTable? _tableFromSpan(
  ({int r0, int c0, int r1, int c1}) span,
  List<double> xs,
  List<double> ys,
  List<_Glyph> free,
  double pageW,
  double pageH,
) {
  final int rows = span.r1 - span.r0 + 1;
  final int cols = span.c1 - span.c0 + 1;
  final double width = xs[span.c1 + 1] - xs[span.c0];
  final double height = ys[span.r1 + 1] - ys[span.r0];
  final double cellW = width / cols;
  final double cellH = height / rows;
  if (cellW > pageW * 0.62) {
    return null;
  }
  if (cellH > 90 && cellH > pageH * 0.22) {
    return null;
  }
  final List<List<String>> text = <List<String>>[];
  final List<_Glyph> used = <_Glyph>[];
  var filled = 0;
  for (var r = span.r0; r <= span.r1; r++) {
    final List<String> row = <String>[];
    for (var c = span.c0; c <= span.c1; c++) {
      final List<_Glyph> inside = <_Glyph>[];
      for (final _Glyph glyph in free) {
        if (used.contains(glyph)) {
          continue;
        }
        final double gx = glyph.op.x + glyph.op.size * 0.25;
        final double gy = glyph.op.y - glyph.op.size * 0.3;
        if (gx >= xs[c] && gx < xs[c + 1] && gy >= ys[r] && gy < ys[r + 1]) {
          inside.add(glyph);
        }
      }
      final String cell = _joinGlyphs(inside).trim();
      if (cell.isNotEmpty) {
        filled += 1;
        used.addAll(inside);
      }
      row.add(cell);
    }
    text.add(row);
  }
  final int cells = rows * cols;
  if (filled < 2 || filled / cells < 0.4) {
    return null;
  }
  free.removeWhere(used.contains);
  return PdfOfficeTable(
    rows: text,
    x: xs[span.c0],
    y: ys[span.r0],
    width: width,
    height: height,
  );
}

bool _cellRuled(
  List<_Seg> horizontal,
  List<_Seg> vertical,
  double x0,
  double x1,
  double y0,
  double y1,
) {
  return _coversHorizontal(horizontal, y0, x0, x1) &&
      _coversHorizontal(horizontal, y1, x0, x1) &&
      _coversVertical(vertical, x0, y0, y1) &&
      _coversVertical(vertical, x1, y0, y1);
}

bool _coversHorizontal(List<_Seg> segments, double y, double x0, double x1) {
  final double left = x0 < x1 ? x0 : x1;
  final double right = x0 < x1 ? x1 : x0;
  final double need = (right - left) * 0.55;
  for (final _Seg seg in segments) {
    if ((seg.y1 - y).abs() > 2.5 && (seg.y2 - y).abs() > 2.5) {
      continue;
    }
    final double a = seg.x1 < seg.x2 ? seg.x1 : seg.x2;
    final double b = seg.x1 < seg.x2 ? seg.x2 : seg.x1;
    final double overlap = (b < right ? b : right) - (a > left ? a : left);
    if (overlap >= need) {
      return true;
    }
  }
  return false;
}

bool _coversVertical(List<_Seg> segments, double x, double y0, double y1) {
  final double top = y0 < y1 ? y0 : y1;
  final double bottom = y0 < y1 ? y1 : y0;
  final double need = (bottom - top) * 0.55;
  for (final _Seg seg in segments) {
    if ((seg.x1 - x).abs() > 2.5 && (seg.x2 - x).abs() > 2.5) {
      continue;
    }
    final double a = seg.y1 < seg.y2 ? seg.y1 : seg.y2;
    final double b = seg.y1 < seg.y2 ? seg.y2 : seg.y1;
    final double overlap = (b < bottom ? b : bottom) - (a > top ? a : top);
    if (overlap >= need) {
      return true;
    }
  }
  return false;
}

List<double> _cluster(List<double> values, double tolerance) {
  if (values.isEmpty) {
    return const <double>[];
  }
  final List<double> sorted = List<double>.of(values)..sort();
  final List<double> out = <double>[sorted.first];
  for (final double value in sorted.skip(1)) {
    if (value - out.last <= tolerance) {
      continue;
    }
    out.add(value);
  }
  return out;
}

List<PdfOfficeLine> _linesFromGlyphs(List<_Glyph> glyphs) {
  final List<_Glyph> sorted = List<_Glyph>.of(glyphs)
    ..sort((a, b) {
      final int y = a.op.y.compareTo(b.op.y);
      return y != 0 ? y : a.op.x.compareTo(b.op.x);
    });
  final List<List<_Glyph>> bands = <List<_Glyph>>[];
  for (final _Glyph glyph in sorted) {
    if (bands.isEmpty) {
      bands.add(<_Glyph>[glyph]);
      continue;
    }
    final List<_Glyph> band = bands.last;
    final double size = band.first.op.size;
    if ((glyph.op.y - band.first.op.y).abs() <= size * 0.45 &&
        (glyph.op.size - size).abs() <= 1) {
      band.add(glyph);
    } else {
      bands.add(<_Glyph>[glyph]);
    }
  }
  final List<PdfOfficeLine> lines = <PdfOfficeLine>[];
  for (final List<_Glyph> band in bands) {
    for (final List<_Glyph> part in _splitWideGaps(band)) {
      final PdfOfficeLine? line = _lineFrom(part);
      if (line != null) {
        lines.add(line);
      }
    }
  }
  return _orderLines(lines);
}

PdfOfficeLine? _lineFrom(List<_Glyph> glyphs) {
  final String text = _joinGlyphs(glyphs);
  if (text.trim().isEmpty) {
    return null;
  }
  final List<_Glyph> ordered = List<_Glyph>.of(glyphs)
    ..sort((a, b) => a.op.x.compareTo(b.op.x));
  final PdfDrawText first = ordered.first.op;
  final PdfDrawText last = ordered.last.op;
  return PdfOfficeLine(
    text: text,
    x: first.x,
    y: first.y,
    width: (last.x - first.x) + last.size,
    fontSize: first.size,
    bold: first.bold,
    italic: first.italic,
    rtl: pdfOfficeIsRtl(text),
    color: first.color,
  );
}

/// A wide x gap is a column gutter, not a space inside a sentence.
List<List<_Glyph>> _splitWideGaps(List<_Glyph> band) {
  final List<_Glyph> ordered = List<_Glyph>.of(band)
    ..sort((a, b) => a.op.x.compareTo(b.op.x));
  final double size = ordered.first.op.size;
  final List<List<_Glyph>> parts = <List<_Glyph>>[<_Glyph>[]];
  for (final _Glyph glyph in ordered) {
    final List<_Glyph> current = parts.last;
    if (current.isNotEmpty) {
      final double gap = glyph.op.x - current.last.op.x;
      if (gap > size * 3 && gap > 28) {
        parts.add(<_Glyph>[]);
      }
    }
    parts.last.add(glyph);
  }
  return parts;
}

List<PdfOfficeLine> _orderLines(List<PdfOfficeLine> lines) {
  if (lines.length < 2) {
    return lines;
  }
  final List<PdfOfficeLine> sorted = List<PdfOfficeLine>.of(lines)
    ..sort((a, b) => a.y.compareTo(b.y));
  final List<PdfOfficeLine> out = <PdfOfficeLine>[];
  final List<PdfOfficeLine> narrow = <PdfOfficeLine>[];
  void flush() {
    if (narrow.isEmpty) {
      return;
    }
    out.addAll(_orderColumns(narrow));
    narrow.clear();
  }

  for (final PdfOfficeLine line in sorted) {
    if (line.width > 300) {
      flush();
      out.add(line);
    } else {
      narrow.add(line);
    }
  }
  flush();
  return out;
}

List<PdfOfficeLine> _orderColumns(List<PdfOfficeLine> lines) {
  final List<List<PdfOfficeLine>> columns = <List<PdfOfficeLine>>[];
  for (final PdfOfficeLine line in lines) {
    List<PdfOfficeLine>? column;
    for (final List<PdfOfficeLine> candidate in columns) {
      final double left = candidate
          .map((PdfOfficeLine item) => item.x)
          .reduce((double a, double b) => a < b ? a : b);
      if ((line.x - left).abs() < 80) {
        column = candidate;
        break;
      }
    }
    if (column == null) {
      columns.add(<PdfOfficeLine>[line]);
    } else {
      column.add(line);
    }
  }
  final bool rtl = lines.any((PdfOfficeLine line) => line.rtl);
  columns.sort((List<PdfOfficeLine> a, List<PdfOfficeLine> b) {
    if (_yOverlaps(a, b)) {
      return rtl
          ? b.first.x.compareTo(a.first.x)
          : a.first.x.compareTo(b.first.x);
    }
    return a.first.y.compareTo(b.first.y);
  });
  return <PdfOfficeLine>[
    for (final List<PdfOfficeLine> column in columns) ...column,
  ];
}

bool _yOverlaps(List<PdfOfficeLine> a, List<PdfOfficeLine> b) {
  double top(List<PdfOfficeLine> lines) => lines
      .map((PdfOfficeLine line) => line.y)
      .reduce((double x, double y) => x < y ? x : y);
  double bottom(List<PdfOfficeLine> lines) => lines
      .map((PdfOfficeLine line) => line.y)
      .reduce((double x, double y) => x > y ? x : y);
  return top(a) <= bottom(b) + 8 && top(b) <= bottom(a) + 8;
}

String _joinGlyphs(List<_Glyph> glyphs) {
  if (glyphs.isEmpty) {
    return '';
  }
  final List<_Glyph> ordered = List<_Glyph>.of(glyphs)
    ..sort((a, b) => a.op.x.compareTo(b.op.x));
  final List<double> steps = <double>[];
  for (var i = 1; i < ordered.length; i++) {
    steps.add(ordered[i].op.x - ordered[i - 1].op.x);
  }
  final double pitch = _median(steps);
  final StringBuffer buffer = StringBuffer();
  for (var i = 0; i < ordered.length; i++) {
    final PdfDrawText op = ordered[i].op;
    if (i > 0 && pitch > 0) {
      final double step = op.x - ordered[i - 1].op.x;
      final double size = op.size > ordered[i - 1].op.size
          ? op.size
          : ordered[i - 1].op.size;
      if (step > pitch + size * 0.42 && step > pitch * 1.7) {
        buffer.write(' ');
      }
    }
    buffer.write(op.text);
  }
  final String raw = buffer.toString().replaceAll(RegExp(r' +'), ' ').trim();
  if (!pdfOfficeIsRtl(raw)) {
    return raw;
  }
  return _visualToLogical(raw);
}

/// Glyphs are painted left to right. An RTL line is that order reversed,
/// with Latin words and numbers put back, then presentation forms folded.
String _visualToLogical(String visual) {
  final List<int> runes = visual.runes.toList().reversed.toList();
  final StringBuffer out = StringBuffer();
  var i = 0;
  while (i < runes.length) {
    if (_keptLtr(runes[i])) {
      final int start = i;
      while (i < runes.length && _keptLtr(runes[i])) {
        i += 1;
      }
      for (var j = i - 1; j >= start; j--) {
        out.writeCharCode(runes[j]);
      }
    } else {
      out.writeCharCode(runes[i]);
      i += 1;
    }
  }
  return ArabicShaper.foldPresentation(out.toString());
}

bool _keptLtr(int rune) {
  return (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A) ||
      rune == 0x25 ||
      rune == 0x2B ||
      rune == 0x2D ||
      rune == 0x2E ||
      rune == 0x2F ||
      rune == 0x3A;
}

List<PdfOfficeLine> _linesFromRuns(List<PdfTextRun> runs) {
  final List<PdfTextRun> ordered = List<PdfTextRun>.of(runs)
    ..sort((a, b) {
      final int y = a.y.compareTo(b.y);
      return y != 0 ? y : a.x.compareTo(b.x);
    });
  return <PdfOfficeLine>[
    for (final PdfTextRun run in ordered)
      if (run.text.trim().isNotEmpty)
        PdfOfficeLine(
          text: run.text.trim(),
          x: run.x,
          y: run.y,
          width: run.width,
          fontSize: run.height <= 0 ? 12 : run.height,
          bold: false,
          italic: false,
          rtl: pdfOfficeIsRtl(run.text),
          color: 0xFF000000,
        ),
  ];
}

bool _duplicate(List<_Glyph> glyphs, PdfDrawText op) {
  for (final _Glyph glyph in glyphs) {
    final PdfDrawText other = glyph.op;
    if (other.text == op.text &&
        (other.x - op.x).abs() < 0.5 &&
        (other.y - op.y).abs() < 0.5) {
      return true;
    }
  }
  return false;
}

double _median(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  final List<double> sorted = List<double>.of(values)..sort();
  return sorted[sorted.length ~/ 2];
}

PdfOfficeImage _image(
  PdfDrawImage op,
  int pageIndex,
  List<PdfOfficeNotice> notices,
) {
  Uint8List bytes = op.bytes;
  String? mime = op.placeholder ? null : _mime(bytes);
  if (mime == null && !op.placeholder) {
    final Uint8List? png = _pngFromPixels(op);
    if (png != null) {
      bytes = png;
      mime = 'image/png';
    }
  }
  if (mime == null) {
    final String reason = op.placeholder
        ? 'JPX and JBIG2 images are not embedded.'
        : 'Only JPEG and PNG images are embedded.';
    notices.add(
      PdfOfficeNotice(
        kind: PdfOfficeNoticeKind.imageSkipped,
        message: reason,
        pageIndex: pageIndex,
      ),
    );
    return PdfOfficeImage(
      x: op.x,
      y: op.y,
      width: op.width,
      height: op.height,
      skipReason: reason,
    );
  }
  return PdfOfficeImage(
    x: op.x,
    y: op.y,
    width: op.width,
    height: op.height,
    bytes: bytes,
    mime: mime,
  );
}

String? _mime(Uint8List bytes) {
  if (bytes.length < 4) {
    return null;
  }
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return 'image/jpeg';
  }
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  return null;
}

Uint8List? _pngFromPixels(PdfDrawImage op) {
  final int width = op.pixelWidth;
  final int height = op.pixelHeight;
  if (width < 1 || height < 1 || op.bytes.isEmpty) {
    return null;
  }
  if (op.hasAlpha && op.bytes.length >= width * height * 4) {
    return PngBytes.fromRgba(width: width, height: height, pixels: op.bytes);
  }
  if (op.bytes.length >= width * height * 3) {
    return PngBytes.fromRgb(width: width, height: height, pixels: op.bytes);
  }
  return null;
}

class _Box {
  _Box(this.x, this.y, this.w, this.h, this.color);

  final double x;
  final double y;
  final double w;
  final double h;
  final int color;

  double get right => x + w;

  double get bottom => y + h;
}

List<PdfOfficeTocEntry> _outlineToc(PdfOutlineNode? root) {
  if (root == null) {
    return const <PdfOfficeTocEntry>[];
  }
  final List<PdfOfficeTocEntry> out = <PdfOfficeTocEntry>[];
  void walk(PdfOutlineNode node, int level) {
    final String title = node.title.trim();
    if (title.isNotEmpty) {
      out.add(
        PdfOfficeTocEntry(
          title: title,
          level: level.clamp(1, 9),
          pageNumber: (node.pageIndex ?? 0) + 1,
        ),
      );
    }
    for (final PdfOutlineNode child in node.children) {
      walk(child, title.isEmpty ? level : level + 1);
    }
  }

  walk(root, 1);
  return out;
}

List<_Box> _fillBoxes(List<PdfPaintOp> ops, double pageW, double pageH) {
  final List<_Box> out = <_Box>[];
  for (final PdfPaintOp op in ops) {
    if (op is! PdfFillPath) {
      continue;
    }
    final _Box? box = _axisBox(op.points, op.color);
    if (box == null || _luma(box.color) > 245) {
      continue;
    }
    if (box.w * box.h > pageW * pageH * 0.5) {
      continue;
    }
    out.add(box);
  }
  return out;
}

_Box? _axisBox(List<PdfPathVerb> points, int color) {
  final List<double> xs = <double>[];
  final List<double> ys = <double>[];
  for (final PdfPathVerb verb in points) {
    if (verb.kind == PdfPathKind.cubic) {
      return null;
    }
    if (verb.kind == PdfPathKind.move || verb.kind == PdfPathKind.line) {
      xs.add(verb.x);
      ys.add(verb.y);
    }
  }
  if (xs.length < 4) {
    return null;
  }
  var minX = xs.first;
  var maxX = xs.first;
  var minY = ys.first;
  var maxY = ys.first;
  for (final double x in xs) {
    if (x < minX) {
      minX = x;
    }
    if (x > maxX) {
      maxX = x;
    }
  }
  for (final double y in ys) {
    if (y < minY) {
      minY = y;
    }
    if (y > maxY) {
      maxY = y;
    }
  }
  final double w = maxX - minX;
  final double h = maxY - minY;
  if (w < 4 || h < 4) {
    return null;
  }
  for (var i = 0; i < xs.length; i++) {
    final bool onV = (xs[i] - minX).abs() < 1.5 || (xs[i] - maxX).abs() < 1.5;
    final bool onH = (ys[i] - minY).abs() < 1.5 || (ys[i] - maxY).abs() < 1.5;
    if (!onV && !onH) {
      return null;
    }
  }
  return _Box(minX, minY, w, h, color);
}

double _luma(int argb) {
  final int r = (argb >> 16) & 0xFF;
  final int g = (argb >> 8) & 0xFF;
  final int b = argb & 0xFF;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

String _hex(int argb) {
  return (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
}

bool _inTable(_Box box, List<PdfOfficeTable> tables) {
  final double cx = box.x + box.w / 2;
  final double cy = box.y + box.h / 2;
  for (final PdfOfficeTable table in tables) {
    if (cx >= table.x &&
        cx <= table.x + table.width &&
        cy >= table.y &&
        cy <= table.y + table.height) {
      return true;
    }
  }
  return false;
}

List<PdfOfficeTable> _withHeaderFills(
  List<PdfOfficeTable> tables,
  List<_Box> fills,
) {
  return <PdfOfficeTable>[
    for (final PdfOfficeTable table in tables)
      PdfOfficeTable(
        rows: table.rows,
        x: table.x,
        y: table.y,
        width: table.width,
        height: table.height,
        headerFill: _headerFill(table, fills),
      ),
  ];
}

String? _headerFill(PdfOfficeTable table, List<_Box> fills) {
  if (table.rows.isEmpty || table.height < 8) {
    return null;
  }
  final double rowH = table.height / table.rows.length;
  for (final _Box box in fills) {
    final double overlapW =
        math.min(box.right, table.x + table.width) - math.max(box.x, table.x);
    final double overlapH =
        math.min(box.bottom, table.y + rowH) - math.max(box.y, table.y);
    if (overlapW > table.width * 0.6 && overlapH > rowH * 0.6) {
      return _hex(box.color);
    }
  }
  return null;
}

List<PdfOfficeChart> _charts(
  List<_Box> fills,
  List<PdfOfficeTable> tables,
  List<_Glyph> free,
  PdfDisplayList list,
) {
  final List<_Box> boxes = <_Box>[
    for (final _Box box in fills)
      if (!_inTable(box, tables)) box,
  ];
  final List<PdfOfficeChart> charts = <PdfOfficeChart>[];
  charts.addAll(_pieCharts(list.ops, boxes, free));
  charts.addAll(_barCharts(boxes, free));
  charts.addAll(_lineCharts(list.ops, free));
  return charts;
}

List<PdfOfficeChart> _barCharts(List<_Box> boxes, List<_Glyph> free) {
  final List<_Box> pool = List<_Box>.of(boxes);
  final List<PdfOfficeChart> charts = <PdfOfficeChart>[];
  while (pool.isNotEmpty) {
    final _Box seed = pool.first;
    final List<_Box> column = <_Box>[
      for (final _Box box in pool)
        if ((box.bottom - seed.bottom).abs() <= 3 &&
            box.h >= 18 &&
            box.w >= 8 &&
            box.h > box.w * 1.15)
          box,
    ];
    final List<_Box> horizontal = <_Box>[
      for (final _Box box in pool)
        if ((box.x - seed.x).abs() <= 3 &&
            box.w >= 18 &&
            box.h >= 8 &&
            box.w > box.h * 1.15)
          box,
    ];
    final bool useColumn = _barGroupOk(column, vertical: true);
    final bool useBar = _barGroupOk(horizontal, vertical: false);
    if (!useColumn && !useBar) {
      pool.remove(seed);
      continue;
    }
    final bool vertical =
        useColumn && (!useBar || column.length >= horizontal.length);
    final List<_Box> group = List<_Box>.of(vertical ? column : horizontal)
      ..sort((a, b) => vertical ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    final List<PdfOfficeChartPoint> points = <PdfOfficeChartPoint>[];
    final List<_Glyph> used = <_Glyph>[];
    var labeled = 0;
    var blocked = false;
    for (var i = 0; i < group.length; i++) {
      final _Box box = group[i];
      final List<_Glyph> hits = <_Glyph>[];
      for (final _Glyph glyph in free) {
        if (used.contains(glyph) || hits.contains(glyph)) {
          continue;
        }
        final bool inside =
            glyph.op.x >= box.x &&
            glyph.op.x <= box.right &&
            glyph.op.y >= box.y + 1 &&
            glyph.op.y <= box.bottom - 1;
        if (vertical && inside) {
          blocked = true;
          break;
        }
        final bool caption = vertical
            ? glyph.op.x >= box.x - 4 &&
                  glyph.op.x <= box.right + 4 &&
                  glyph.op.y >= box.bottom - 2 &&
                  glyph.op.y <= box.bottom + glyph.op.size * 3
            : inside ||
                  (glyph.op.y >= box.y - 2 &&
                      glyph.op.y <= box.bottom + 2 &&
                      glyph.op.x >= box.x - 4 &&
                      glyph.op.x <= box.right + glyph.op.size * 6);
        if (caption) {
          hits.add(glyph);
        }
      }
      if (blocked) {
        break;
      }
      final String text = _joinGlyphs(hits).trim();
      if (text.isNotEmpty) {
        labeled += 1;
        used.addAll(hits);
      }
      final double magnitude = vertical ? box.h : box.w;
      points.add(
        PdfOfficeChartPoint(
          label: text.isEmpty ? '${i + 1}' : text,
          value: double.parse(magnitude.toStringAsFixed(2)),
          color: _hex(box.color),
        ),
      );
    }
    if (blocked) {
      pool.remove(seed);
      continue;
    }
    final bool varied = _heightsVary(group, vertical);
    if (points.length < 2 ||
        points.length != group.length ||
        (!varied && labeled < 2)) {
      pool.remove(seed);
      continue;
    }
    final List<_Glyph> titleGlyphs = _titleGlyphs(group, free, used);
    final String title = _joinGlyphs(titleGlyphs).trim();
    used.addAll(titleGlyphs);
    free.removeWhere(used.contains);
    for (final _Box box in group) {
      pool.remove(box);
      boxes.remove(box);
    }
    charts.add(_chartFromBars(group, points, title, vertical));
  }
  return charts;
}

bool _barGroupOk(List<_Box> group, {required bool vertical}) {
  if (group.length < 2 || group.length > 16) {
    return false;
  }
  final List<double> widths = <double>[
    for (final _Box box in group) vertical ? box.w : box.h,
  ]..sort();
  final double median = widths[widths.length ~/ 2];
  if (median < 4) {
    return false;
  }
  for (final double width in widths) {
    if (width < median * 0.55 || width > median * 1.6) {
      return false;
    }
  }
  final List<_Box> ordered = List<_Box>.of(group)
    ..sort((a, b) => vertical ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  for (var i = 1; i < ordered.length; i++) {
    final double gap = vertical
        ? ordered[i].x - ordered[i - 1].right
        : ordered[i].y - ordered[i - 1].bottom;
    final double span = vertical ? ordered[i].w : ordered[i].h;
    if (gap < -2 || gap > span * 3) {
      return false;
    }
  }
  return true;
}

bool _heightsVary(List<_Box> group, bool vertical) {
  var minV = double.infinity;
  var maxV = 0.0;
  for (final _Box box in group) {
    final double value = vertical ? box.h : box.w;
    if (value < minV) {
      minV = value;
    }
    if (value > maxV) {
      maxV = value;
    }
  }
  return maxV > 0 && (maxV - minV) >= maxV * 0.15;
}

List<_Glyph> _titleGlyphs(
  List<_Box> group,
  List<_Glyph> free,
  List<_Glyph> used,
) {
  var left = group.first.x;
  var right = group.first.right;
  var top = group.first.y;
  for (final _Box box in group) {
    if (box.x < left) {
      left = box.x;
    }
    if (box.right > right) {
      right = box.right;
    }
    if (box.y < top) {
      top = box.y;
    }
  }
  final List<_Glyph> hits = <_Glyph>[];
  for (final _Glyph glyph in free) {
    if (used.contains(glyph)) {
      continue;
    }
    if (glyph.op.y < top &&
        glyph.op.y > top - 36 &&
        glyph.op.x >= left - 8 &&
        glyph.op.x <= right + 8) {
      hits.add(glyph);
    }
  }
  return hits;
}

PdfOfficeChart _chartFromBars(
  List<_Box> group,
  List<PdfOfficeChartPoint> points,
  String title,
  bool vertical,
) {
  var left = group.first.x;
  var right = group.first.right;
  var top = group.first.y;
  var bottom = group.first.bottom;
  for (final _Box box in group) {
    if (box.x < left) {
      left = box.x;
    }
    if (box.right > right) {
      right = box.right;
    }
    if (box.y < top) {
      top = box.y;
    }
    if (box.bottom > bottom) {
      bottom = box.bottom;
    }
  }
  if (title.isNotEmpty) {
    top -= 18;
  }
  bottom += 16;
  return PdfOfficeChart(
    kind: vertical ? PdfOfficeChartKind.column : PdfOfficeChartKind.bar,
    title: title,
    points: points,
    x: left < 4 ? 0 : left - 4,
    y: top < 4 ? 0 : top - 4,
    width: right - left + 24,
    height: bottom - top + 8,
  );
}

List<PdfOfficeChart> _pieCharts(
  List<PdfPaintOp> ops,
  List<_Box> boxes,
  List<_Glyph> free,
) {
  final List<({double cx, double cy, double radius, double sweep, int color})>
  wedges = <({double cx, double cy, double radius, double sweep, int color})>[];
  for (final PdfPaintOp op in ops) {
    if (op is! PdfFillPath || _luma(op.color) > 245) {
      continue;
    }
    final ({double cx, double cy, double radius, double sweep})? wedge = _wedge(
      op.points,
    );
    if (wedge == null) {
      continue;
    }
    wedges.add((
      cx: wedge.cx,
      cy: wedge.cy,
      radius: wedge.radius,
      sweep: wedge.sweep,
      color: op.color,
    ));
  }
  if (wedges.length < 2) {
    return const <PdfOfficeChart>[];
  }
  final List<PdfOfficeChart> charts = <PdfOfficeChart>[];
  final List<int> used = <int>[];
  for (var i = 0; i < wedges.length; i++) {
    if (used.contains(i)) {
      continue;
    }
    final List<int> group = <int>[i];
    for (var j = i + 1; j < wedges.length; j++) {
      if ((wedges[j].cx - wedges[i].cx).abs() <= 6 &&
          (wedges[j].cy - wedges[i].cy).abs() <= 6) {
        group.add(j);
      }
    }
    if (group.length < 2) {
      continue;
    }
    var sweep = 0.0;
    for (final int index in group) {
      sweep += wedges[index].sweep;
      used.add(index);
    }
    if (sweep < 4 || sweep > 8.5) {
      continue;
    }
    final List<PdfOfficeChartPoint> points = <PdfOfficeChartPoint>[];
    final List<_Glyph> consumed = <_Glyph>[];
    for (var n = 0; n < group.length; n++) {
      final wedge = wedges[group[n]];
      String label = '';
      for (final _Box box in List<_Box>.of(boxes)) {
        if (box.w > 16 || box.h > 16 || box.x < wedge.cx) {
          continue;
        }
        final List<_Glyph> hits = <_Glyph>[
          for (final _Glyph glyph in free)
            if (!consumed.contains(glyph) &&
                glyph.op.x >= box.right - 2 &&
                glyph.op.x <= box.right + 80 &&
                (glyph.op.y - (box.y + box.h)).abs() < 10)
              glyph,
        ];
        final String text = _joinGlyphs(hits).trim();
        if (text.isEmpty) {
          continue;
        }
        label = text;
        consumed.addAll(hits);
        boxes.remove(box);
        break;
      }
      points.add(
        PdfOfficeChartPoint(
          label: label.isEmpty ? '${n + 1}' : label,
          value: double.parse(wedges[group[n]].sweep.toStringAsFixed(3)),
          color: _hex(wedges[group[n]].color),
        ),
      );
    }
    free.removeWhere(consumed.contains);
    final double radius = wedges[group.first].radius;
    charts.add(
      PdfOfficeChart(
        kind: PdfOfficeChartKind.pie,
        title: '',
        points: points,
        x: wedges[i].cx - radius - 8,
        y: wedges[i].cy - radius - 8,
        width: radius * 2 + 120,
        height: radius * 2 + 24,
      ),
    );
  }
  return charts;
}

({double cx, double cy, double radius, double sweep})? _wedge(
  List<PdfPathVerb> points,
) {
  final List<PdfPathVerb> drawn = <PdfPathVerb>[
    for (final PdfPathVerb verb in points)
      if (verb.kind == PdfPathKind.move || verb.kind == PdfPathKind.line) verb,
  ];
  if (drawn.length < 10 ||
      points.any((PdfPathVerb v) => v.kind == PdfPathKind.cubic)) {
    return null;
  }
  final double cx = drawn.first.x;
  final double cy = drawn.first.y;
  final List<double> radii = <double>[];
  for (final PdfPathVerb verb in drawn.skip(1)) {
    final double dx = verb.x - cx;
    final double dy = verb.y - cy;
    radii.add(math.sqrt(dx * dx + dy * dy));
  }
  radii.sort();
  final double radius = radii[radii.length ~/ 2];
  if (radius < 12) {
    return null;
  }
  var onArc = 0;
  for (final double value in radii) {
    if ((value - radius).abs() <= radius * 0.3) {
      onArc += 1;
    }
  }
  if (onArc < radii.length * 0.5) {
    return null;
  }
  final PdfPathVerb start = drawn[1];
  final PdfPathVerb end = drawn[drawn.length - 1];
  var sweep =
      math.atan2(end.y - cy, end.x - cx) -
      math.atan2(start.y - cy, start.x - cx);
  if (sweep < 0) {
    sweep += math.pi * 2;
  }
  if (sweep < 0.15 || sweep > 6) {
    return null;
  }
  return (cx: cx, cy: cy, radius: radius, sweep: sweep);
}

List<PdfOfficeChart> _lineCharts(List<PdfPaintOp> ops, List<_Glyph> free) {
  final List<PdfOfficeChart> charts = <PdfOfficeChart>[];
  for (final PdfPaintOp op in ops) {
    if (op is! PdfStrokePath) {
      continue;
    }
    final List<PdfPathVerb> vertices = <PdfPathVerb>[
      for (final PdfPathVerb verb in op.points)
        if (verb.kind == PdfPathKind.move || verb.kind == PdfPathKind.line)
          verb,
    ];
    if (vertices.length < 3) {
      continue;
    }
    var monotonic = true;
    var diagonal = false;
    for (var i = 1; i < vertices.length; i++) {
      final double dx = vertices[i].x - vertices[i - 1].x;
      final double dy = vertices[i].y - vertices[i - 1].y;
      if (dx < 6) {
        monotonic = false;
      }
      if (dx.abs() > 4 && dy.abs() > 4) {
        diagonal = true;
      }
    }
    if (!monotonic || !diagonal) {
      continue;
    }
    final double x0 = vertices.first.x;
    final double x1 = vertices.last.x;
    var minY = vertices.first.y;
    var maxY = vertices.first.y;
    for (final PdfPathVerb verb in vertices) {
      if (verb.y < minY) {
        minY = verb.y;
      }
      if (verb.y > maxY) {
        maxY = verb.y;
      }
    }
    if (x1 - x0 < 36 || maxY - minY < 12) {
      continue;
    }
    final List<PdfOfficeChartPoint> points = <PdfOfficeChartPoint>[];
    final List<_Glyph> used = <_Glyph>[];
    for (var i = 0; i < vertices.length; i++) {
      final PdfPathVerb verb = vertices[i];
      final List<_Glyph> hits = <_Glyph>[
        for (final _Glyph glyph in free)
          if (!used.contains(glyph) &&
              (glyph.op.x - verb.x).abs() < 14 &&
              glyph.op.y >= verb.y &&
              glyph.op.y <= maxY + glyph.op.size * 2)
            glyph,
      ];
      final String text = _joinGlyphs(hits).trim();
      used.addAll(hits);
      points.add(
        PdfOfficeChartPoint(
          label: text.isEmpty ? '${i + 1}' : text,
          value: double.parse((maxY - verb.y).toStringAsFixed(2)),
          color: _hex(op.color),
        ),
      );
    }
    free.removeWhere(used.contains);
    charts.add(
      PdfOfficeChart(
        kind: PdfOfficeChartKind.line,
        title: '',
        points: points,
        x: x0 - 8,
        y: minY - 16,
        width: x1 - x0 + 24,
        height: maxY - minY + 36,
      ),
    );
  }
  return charts;
}

List<PdfOfficeLine> _annotateLines(
  List<PdfOfficeLine> lines,
  PdfDisplayList list,
  int pageIndex,
  List<PdfOfficeTocEntry> toc,
) {
  final List<double> sizes = <double>[
    for (final PdfOfficeLine line in lines) line.fontSize,
  ]..sort();
  final double median = sizes.isEmpty ? 12 : sizes[sizes.length ~/ 2];
  final List<PdfOfficeTocEntry> here = <PdfOfficeTocEntry>[
    for (final PdfOfficeTocEntry entry in toc)
      if (entry.pageNumber == pageIndex + 1) entry,
  ];
  return <PdfOfficeLine>[
    for (final PdfOfficeLine line in lines)
      _annotateOne(line, list.hotspots, here, median),
  ];
}

PdfOfficeLine _annotateOne(
  PdfOfficeLine line,
  List<PdfHotspot> hotspots,
  List<PdfOfficeTocEntry> toc,
  double median,
) {
  var level = line.headingLevel;
  for (final PdfOfficeTocEntry entry in toc) {
    if (_sameTitle(line.text, entry.title)) {
      level = entry.level;
      break;
    }
  }
  if (level == 0 &&
      line.text.trim().length <= 80 &&
      line.fontSize >= median * 1.5) {
    level = 1;
  }
  String? url;
  int? page;
  for (final PdfHotspot spot in hotspots) {
    if (!_linkHits(line, spot.rect)) {
      continue;
    }
    final String? uri = spot.action.uri;
    if (uri != null && uri.isNotEmpty) {
      url = uri;
    } else if (spot.action.pageIndex != null) {
      page = spot.action.pageIndex! + 1;
    }
    break;
  }
  return PdfOfficeLine(
    text: line.text,
    x: line.x,
    y: line.y,
    width: line.width,
    fontSize: line.fontSize,
    bold: line.bold || level > 0,
    italic: line.italic,
    rtl: line.rtl,
    color: line.color,
    headingLevel: level,
    linkUrl: url,
    linkPage: page,
    listKind: _listKind(line.text),
  );
}

bool _linkHits(PdfOfficeLine line, PdfRect rect) {
  final double left = line.x;
  final double right = line.x + (line.width < 4 ? line.fontSize : line.width);
  final double top = line.y - line.fontSize;
  final double bottom = line.y + line.fontSize * 0.4;
  final double otherLeft = rect.width < 0 ? rect.x + rect.width : rect.x;
  final double otherTop = rect.height < 0 ? rect.y + rect.height : rect.y;
  final double otherRight = otherLeft + rect.width.abs();
  final double otherBottom = otherTop + rect.height.abs();
  return left < otherRight &&
      right > otherLeft &&
      top < otherBottom &&
      bottom > otherTop;
}

bool _sameTitle(String line, String title) {
  final String a = line.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final String b = title.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  return a == b || a.startsWith(b);
}

PdfOfficeListKind _listKind(String text) {
  final String trimmed = text.trim();
  if (RegExp(r'^[•·●◦▪‣\-–—*]\s+\S').hasMatch(trimmed)) {
    return PdfOfficeListKind.bullet;
  }
  if (RegExp(r'^(?:\d+|[٠-٩]+)[.)]\s+\S').hasMatch(trimmed)) {
    return PdfOfficeListKind.number;
  }
  return PdfOfficeListKind.none;
}

bool _tableHasText(List<PdfOfficeTable> tables) {
  for (final PdfOfficeTable table in tables) {
    for (final List<String> row in table.rows) {
      for (final String cell in row) {
        if (cell.trim().isNotEmpty) {
          return true;
        }
      }
    }
  }
  return false;
}
