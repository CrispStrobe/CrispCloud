import 'dart:math' as math;
import 'dart:typed_data';

import '../builders/image_fit.dart';
import '../builders/office_document_theme.dart';
import '../builders/office_markup.dart';
import '../fonts/font_metrics.dart';
import '../fonts/font_subsetter.dart';
import '../fonts/sfnt_parser.dart';
import 'pdf_canvas.dart';
import 'pdf_document.dart';
import 'pdf_image.dart';

enum _PdfRole { title, heading, body, caption }

class _PdfBlock {
  _PdfBlock._(
    this.kind, {
    this.text,
    this.rows,
    this.cards,
    this.bytes,
    this.points,
    this.height = 0,
  });

  /// text API.
  factory _PdfBlock.text(_PdfRole role, String text) =>
      _PdfBlock._('text', text: text)..role = role;

  /// spacer API.
  factory _PdfBlock.spacer(double h) => _PdfBlock._('spacer', height: h);

  /// table API.
  factory _PdfBlock.table(List<List<String>> rows) =>
      _PdfBlock._('table', rows: rows);

  /// kpi API.
  factory _PdfBlock.kpi(List<({String label, String value})> cards) =>
      _PdfBlock._('kpi', cards: cards);

  /// image API.
  factory _PdfBlock.image(Uint8List bytes) =>
      _PdfBlock._('image', bytes: bytes);

  /// chart API.
  factory _PdfBlock.chart(String kind, List<ChartPoint> points) =>
      _PdfBlock._('chart', text: kind, points: points);

  /// breakPage API.
  factory _PdfBlock.breakPage() => _PdfBlock._('break');

  /// kind API.
  final String kind;

  /// text API.
  final String? text;

  /// rows API.
  final List<List<String>>? rows;

  /// cards API.
  final List<({String label, String value})>? cards;

  /// bytes API.
  final Uint8List? bytes;

  /// points API.
  final List<ChartPoint>? points;

  /// height API.
  double height;

  /// role API.
  _PdfRole role = _PdfRole.body;
}

/// Block-oriented PDF 1.7 report surface. Branding comes from [theme] only.
class PdfReportBuilder {
  /// PdfReportBuilder API.
  PdfReportBuilder({
    OfficeDocumentTheme? theme,
    this.font,
    this.title = 'Quds Office',
    this.author = '',
    OfficePageSize? page,
    this.margin = 48,
    this.header,
    this.footer,
  }) : theme = theme ?? const OfficeDocumentTheme(),
       page = page ?? theme?.page ?? OfficePageSize.a4Portrait;

  /// theme API.
  final OfficeDocumentTheme theme;

  /// font API.
  final SfntFont? font;

  /// title API.
  final String title;

  /// author API.
  final String author;

  /// page API.
  final OfficePageSize page;

  /// margin API.
  final double margin;

  /// header API.
  final String? header;

  /// footer API.
  final String? footer;
  final List<_PdfBlock> _blocks = <_PdfBlock>[];
  FontSubset? _activeSubset;

  /// widthPoints API.
  double get _width => page.widthPoints;

  /// heightPoints API.
  double get _height => page.heightPoints;
  double get _contentTop => margin + 22;
  double get _contentBottom => _height - margin - 22;
  double get _contentWidth => _width - margin * 2;

  /// titleText API.
  void titleText(String text) =>
      _blocks.add(_PdfBlock.text(_PdfRole.title, text));

  /// heading API.
  void heading(String text) =>
      _blocks.add(_PdfBlock.text(_PdfRole.heading, text));

  /// body API.
  void body(String text) => _blocks.add(_PdfBlock.text(_PdfRole.body, text));

  /// caption API.
  void caption(String text) =>
      _blocks.add(_PdfBlock.text(_PdfRole.caption, text));

  /// spacer API.
  void spacer({double height = 12}) => _blocks.add(_PdfBlock.spacer(height));

  /// table API.
  void table(List<List<String>> rows, {bool hasHeader = true}) =>
      _blocks.add(_PdfBlock.table(rows));

  /// kpiRow API.
  void kpiRow(List<({String label, String value})> cards) =>
      _blocks.add(_PdfBlock.kpi(cards));

  /// image API.
  void image(Uint8List bytes, {double? maxWidth, double? maxHeight}) =>
      _blocks.add(_PdfBlock.image(bytes));

  /// barChart API.
  void barChart(List<ChartPoint> points) =>
      _blocks.add(_PdfBlock.chart('bar', points));

  /// pieChart API.
  void pieChart(List<ChartPoint> points) =>
      _blocks.add(_PdfBlock.chart('pie', points));

  /// lineChart API.
  void lineChart(List<ChartPoint> points) =>
      _blocks.add(_PdfBlock.chart('line', points));

  /// pageBreak API.
  void pageBreak() => _blocks.add(_PdfBlock.breakPage());

  /// build API.
  Uint8List build() {
    final List<List<_PdfBlock>> pages = <List<_PdfBlock>>[];
    List<_PdfBlock> current = <_PdfBlock>[];
    var y = _contentTop;
    void flush() {
      if (current.isNotEmpty) {
        pages.add(current);
        current = <_PdfBlock>[];
      }
      y = _contentTop;
    }

    for (final _PdfBlock block in _blocks) {
      if (block.kind == 'break') {
        flush();
        continue;
      }
      final double h = _measure(block);
      if (current.isNotEmpty && y + h > _contentBottom) {
        flush();
      }
      current.add(block);
      y += h + 8;
    }
    flush();
    if (pages.isEmpty) {
      pages.add(<_PdfBlock>[]);
    }

    final PdfDocument pdf = PdfDocument(title: title, author: author);
    final Set<int> cps = <int>{};
    _collectReportCodepoints(pages, cps);
    if (header != null) {
      cps.addAll(header!.runes);
    }
    if (footer != null) {
      cps.addAll(footer!.runes);
    }
    FontSubset? subset;
    if (font != null && cps.isNotEmpty && font!.hasTable('glyf')) {
      subset = FontSubsetter(font!).subset(cps);
    }
    _activeSubset = subset;
    var imgSeq = 0;
    for (int i = 0; i < pages.length; i++) {
      final PdfCanvas canvas = PdfCanvas(_width, _height);
      canvas.fillRect(0, 0, _width, _height, theme.palette.surface);
      final List<PdfEmbeddedImage> images = <PdfEmbeddedImage>[];
      _paintChrome(canvas, i + 1, pages.length);
      var cursor = _contentTop;
      for (final _PdfBlock block in pages[i]) {
        cursor = _paintBlock(
          canvas,
          block,
          cursor,
          images,
          () => ++imgSeq,
          cps,
        );
        cursor += 8;
      }
      canvas.endText();
      pdf.addPage(
        PdfPage(
          width: _width,
          height: _height,
          content: canvas.toStream(),
          images: images,
        ),
      );
    }
    _activeSubset = null;
    return pdf.save(subset: subset, font: font);
  }

  void _collectReportCodepoints(List<List<_PdfBlock>> pages, Set<int> cps) {
    for (final List<_PdfBlock> page in pages) {
      for (final _PdfBlock block in page) {
        if (block.text != null) {
          cps.addAll(block.text!.runes);
        }
        if (block.rows != null) {
          for (final List<String> row in block.rows!) {
            for (final String cell in row) {
              cps.addAll(cell.runes);
            }
          }
        }
        if (block.cards != null) {
          for (final ({String label, String value}) card in block.cards!) {
            cps.addAll(card.label.runes);
            cps.addAll(card.value.runes);
          }
        }
        if (block.points != null) {
          for (final ChartPoint point in block.points!) {
            cps.addAll(point.label.runes);
          }
        }
      }
    }
  }

  void _paintChrome(PdfCanvas canvas, int n, int total) {
    if (header != null && header!.isNotEmpty) {
      _drawString(
        canvas,
        header!,
        margin,
        margin,
        10,
        theme.palette.muted,
        <int>{},
      );
    }
    final String foot = <String>[
      if (footer != null && footer!.isNotEmpty) footer!,
      '$n / $total',
    ].join('   ');
    _drawString(
      canvas,
      foot,
      margin,
      _height - margin,
      10,
      theme.palette.muted,
      <int>{},
    );
    canvas.endText();
    canvas.setStrokeColor(theme.palette.rule);
    canvas.setLineWidth(0.6);
    canvas.moveTo(margin, margin + 14);
    canvas.lineTo(_width - margin, margin + 14);
    canvas.stroke();
    canvas.moveTo(margin, _height - margin - 8);
    canvas.lineTo(_width - margin, _height - margin - 8);
    canvas.stroke();
  }

  double _paintBlock(
    PdfCanvas canvas,
    _PdfBlock block,
    double y,
    List<PdfEmbeddedImage> images,
    int Function() nextImg,
    Set<int> cps,
  ) {
    switch (block.kind) {
      case 'spacer':
        return y + block.height;
      case 'text':
        final double size = switch (block.role) {
          _PdfRole.title => 22,
          _PdfRole.heading => 16,
          _PdfRole.body => 11,
          _PdfRole.caption => 9,
        };
        final String color = switch (block.role) {
          _PdfRole.title || _PdfRole.heading => theme.palette.primary,
          _PdfRole.caption => theme.palette.muted,
          _PdfRole.body => '222222',
        };
        final List<String> lines = _wrap(block.text ?? '', size);
        var yy = y;
        for (final String line in lines) {
          final double x = theme.rtl
              ? _width - margin - _measureLine(line, size)
              : margin;
          _drawString(canvas, line, x, yy + size, size, color, cps);
          yy += size * 1.35;
        }
        canvas.endText();
        return yy;
      case 'table':
        return _paintTable(
          canvas,
          block.rows ?? const <List<String>>[],
          y,
          cps,
        );
      case 'kpi':
        return _paintKpi(
          canvas,
          block.cards ?? const <({String label, String value})>[],
          y,
          cps,
        );
      case 'image':
        return _paintImage(
          canvas,
          block.bytes ?? Uint8List(0),
          y,
          images,
          nextImg,
        );
      case 'chart':
        return _paintChart(
          canvas,
          block.text ?? 'bar',
          block.points ?? const <ChartPoint>[],
          y,
        );
      default:
        return y;
    }
  }

  double _paintTable(
    PdfCanvas canvas,
    List<List<String>> rows,
    double y,
    Set<int> cps,
  ) {
    if (rows.isEmpty) {
      return y;
    }
    final int cols = rows.fold<int>(
      0,
      (int a, List<String> r) => a > r.length ? a : r.length,
    );
    final double colW = _contentWidth / cols;
    const double rowH = 18;
    var yy = y;
    for (int r = 0; r < rows.length; r++) {
      final bool header = r == 0;
      final String fill = header
          ? theme.palette.tableHeader
          : (r.isOdd ? theme.palette.tableBand : theme.palette.surface);
      canvas.fillRect(margin, yy, _contentWidth, rowH, fill);
      canvas.strokeRect(margin, yy, _contentWidth, rowH, theme.palette.rule);
      for (int c = 0; c < cols; c++) {
        final String text = c < rows[r].length ? rows[r][c] : '';
        final double x = theme.rtl
            ? margin + (cols - 1 - c) * colW + 4
            : margin + c * colW + 4;
        _drawString(
          canvas,
          text,
          x,
          yy + 13,
          9,
          header ? theme.palette.onPrimary : '222222',
          cps,
        );
      }
      canvas.endText();
      yy += rowH;
    }
    return yy;
  }

  double _paintKpi(
    PdfCanvas canvas,
    List<({String label, String value})> cards,
    double y,
    Set<int> cps,
  ) {
    final List<({String label, String value})> items = cards.take(6).toList();
    if (items.isEmpty) {
      return y;
    }
    final int n = items.length;
    final double gap = 8;
    final double cardW = (_contentWidth - gap * (n - 1)) / n;
    const double cardH = 52;
    for (int i = 0; i < n; i++) {
      final double x = theme.rtl
          ? margin + (n - 1 - i) * (cardW + gap)
          : margin + i * (cardW + gap);
      canvas.fillRect(x, y, cardW, cardH, theme.palette.surface);
      canvas.fillRect(x, y, cardW, 4, theme.palette.accent);
      canvas.strokeRect(x, y, cardW, cardH, theme.palette.rule);
      _drawString(
        canvas,
        items[i].label,
        x + 6,
        y + 20,
        8,
        theme.palette.muted,
        cps,
      );
      _drawString(
        canvas,
        items[i].value,
        x + 6,
        y + 40,
        14,
        theme.palette.primary,
        cps,
      );
      canvas.endText();
    }
    return y + cardH;
  }

  double _paintImage(
    PdfCanvas canvas,
    Uint8List bytes,
    double y,
    List<PdfEmbeddedImage> images,
    int Function() nextImg,
  ) {
    if (bytes.isEmpty) {
      return y;
    }
    final PdfRaster? raster = PdfImageCodec.decode(bytes);
    if (raster == null) {
      return y;
    }
    final ImageSize size = ImageSize(raster.width, raster.height);
    final ({int cx, int cy}) fitted = ImageFit.containEmu(
      srcWidthPx: size.widthPx,
      srcHeightPx: size.heightPx,
      maxCx: (_contentWidth * 12700).round(),
      maxCy: (220 * 12700).round(),
    );
    final double w = fitted.cx / 12700;
    final double h = fitted.cy / 12700;
    final String name = 'Im${nextImg()}';
    images.add(
      PdfEmbeddedImage(
        name: name,
        width: raster.width,
        height: raster.height,
        bytes: raster.jpegBytes ?? raster.rgb,
        jpeg: raster.isJpeg,
        maskBytes: raster.alpha,
      ),
    );
    final double x = margin + (_contentWidth - w) / 2;
    canvas.drawImage(name, x, y, w, h);
    return y + h;
  }

  double _paintChart(
    PdfCanvas canvas,
    String kind,
    List<ChartPoint> points,
    double y,
  ) {
    final List<ChartPoint> pts = <ChartPoint>[
      for (final ChartPoint p in points)
        if (p.value.isFinite && p.value > 0) p,
    ];
    if (pts.isEmpty) {
      return y;
    }
    const double boxH = 140;
    canvas.strokeRect(margin, y, _contentWidth, boxH, theme.palette.rule);
    if (kind == 'pie') {
      final double cx = margin + _contentWidth / 2;
      final double cy = y + boxH / 2;
      const double r = 50;
      final double sum = pts.fold<double>(
        0,
        (double a, ChartPoint p) => a + p.value,
      );
      var angle = -math.pi / 2;
      for (int i = 0; i < pts.length; i++) {
        final double sweep = 2 * math.pi * (pts[i].value / sum);
        canvas.setFillColor(theme.colorAt(i));
        canvas.moveTo(cx, cy);
        const int steps = 12;
        for (int s = 0; s <= steps; s++) {
          final double a = angle + sweep * (s / steps);
          canvas.lineTo(cx + r * math.cos(a), cy + r * math.sin(a));
        }
        canvas.fill();
        angle += sweep;
      }
    } else if (kind == 'line') {
      final double maxV = pts.fold<double>(
        0,
        (double a, ChartPoint p) => math.max(a, p.value),
      );
      canvas.setStrokeColor(theme.palette.primary);
      canvas.setLineWidth(1.4);
      for (int i = 0; i < pts.length; i++) {
        final double x =
            margin +
            16 +
            i * ((_contentWidth - 32) / math.max(1, pts.length - 1));
        final double yy = y + boxH - 16 - (pts[i].value / maxV) * (boxH - 32);
        if (i == 0) {
          canvas.moveTo(x, yy);
        } else {
          canvas.lineTo(x, yy);
        }
      }
      canvas.stroke();
    } else {
      final double maxV = pts.fold<double>(
        0,
        (double a, ChartPoint p) => math.max(a, p.value),
      );
      final double barW = (_contentWidth - 24) / pts.length;
      for (int i = 0; i < pts.length; i++) {
        final double h = (pts[i].value / maxV) * (boxH - 24);
        canvas.fillRect(
          margin + 12 + i * barW,
          y + boxH - 8 - h,
          barW * 0.7,
          h,
          theme.colorAt(i),
        );
      }
    }
    return y + boxH;
  }

  double _measure(_PdfBlock block) {
    switch (block.kind) {
      case 'spacer':
        return block.height;
      case 'text':
        final double size = switch (block.role) {
          _PdfRole.title => 22,
          _PdfRole.heading => 16,
          _PdfRole.body => 11,
          _PdfRole.caption => 9,
        };
        return _wrap(block.text ?? '', size).length * size * 1.35;
      case 'table':
        return (block.rows?.length ?? 0) * 18;
      case 'kpi':
        return 52;
      case 'image':
        return 160;
      case 'chart':
        return 140;
      default:
        return 0;
    }
  }

  List<String> _wrap(String text, double fontSize) {
    if (text.isEmpty) {
      return <String>[''];
    }
    final List<String> words = text.split(RegExp(r'\s+'));
    final List<String> lines = <String>[];
    var current = '';
    for (final String word in words) {
      final String next = current.isEmpty ? word : '$current $word';
      if (_measureLine(next, fontSize) <= _contentWidth) {
        current = next;
      } else {
        if (current.isNotEmpty) {
          lines.add(current);
        }
        current = word;
      }
    }
    if (current.isNotEmpty) {
      lines.add(current);
    }
    return lines;
  }

  double _measureLine(String text, double fontSize) {
    if (font != null) {
      return FontMetrics(
        font: font!,
        fontSizePoints: fontSize,
      ).measureText(text);
    }
    return text.length * fontSize * 0.5;
  }

  void _drawString(
    PdfCanvas canvas,
    String text,
    double x,
    double y,
    double size,
    String color,
    Set<int> cps,
  ) {
    if (font != null) {
      var cx = x;
      final FontMetrics metrics = FontMetrics(
        font: font!,
        fontSizePoints: size,
      );
      for (final int cp in text.runes) {
        cps.add(cp);
        final int oldGid = font!.glyphIdFor(cp);
        final int gid = _activeSubset?.unicodeToNewGlyph[cp] ?? oldGid;
        canvas.showGlyph(
          x: cx,
          y: y,
          fontSize: size,
          glyphId: gid,
          color: color,
        );
        cx += metrics.characterWidth(cp);
      }
      return;
    }
    canvas.showLatin(x: x, y: y, fontSize: size, text: text, color: color);
  }
}
