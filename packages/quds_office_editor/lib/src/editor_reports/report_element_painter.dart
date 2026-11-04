import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:quds_office_engine/pdf_widgets.dart'
    show Code128Encoder, QrEncoder;
import 'package:quds_office_engine/quds_office_engine.dart';

import 'report_design_layout.dart';
import 'report_layout_painter.dart';

/// Paints template elements on the band canvas: text with its placeholders
/// highlighted, tables as header + template row + totals, real barcode
/// symbols, images, and shapes. Coordinates are document points.
class ReportElementPainter {
  /// ReportElementPainter API.
  ReportElementPainter(this.raster);

  /// Shared image decoder.
  final ReportLayoutPainter raster;

  final Map<String, TextPainter> _text = <String, TextPainter>{};
  final Map<String, List<bool>?> _code128 = <String, List<bool>?>{};
  final Map<String, List<List<bool>>?> _qr = <String, List<List<bool>>?>{};
  final Map<String, Uint8List?> _decoded = <String, Uint8List?>{};
  final Map<String, List<ReportPrimitive>> _charts =
      <String, List<ReportPrimitive>>{};
  late final ReportFontRegistry _defaultFonts = ReportFontRegistry();

  static const List<double> _sample = <double>[42, 68, 35, 80, 55, 62, 47, 73];
  static const List<String> _latin = <String>['A', 'B', 'C', 'D', 'E', 'F'];
  static const List<String> _arabic = <String>['أ', 'ب', 'ج', 'د', 'هـ', 'و'];

  /// Placeholder text color.
  static const Color bindingColor = Color(0xFF1565C0);

  static const Color _guide = Color(0x55808080);
  static final RegExp _binding = RegExp(r'\{\{.*?\}\}', dotAll: true);

  /// Fallback faces for template fonts the host has not loaded.
  static const List<String> fallbackFamilies = <String>[
    'Noto Naskh Arabic',
    'Liberation Sans',
  ];

  /// Paints [e] inside [r].
  void paint(
    Canvas canvas,
    ReportDesignLayout layout,
    ReportDesignSlot slot,
    ReportElement e,
    Rect r,
    Map<String, Uint8List> images, {
    Map<String, Uint8List> shapes = const <String, Uint8List>{},
    bool hideText = false,
    ReportFontRegistry? fonts,
    Map<String, Object?>? data,
  }) {
    final ReportTemplate t = layout.template;
    switch (e) {
      case ReportTextElement():
        _paintText(canvas, t, e, r, hideText: hideText);
      case ReportTableElement():
        _paintTable(canvas, t, slot.band, e, r);
      case ReportImageElement():
        _paintImage(canvas, t, e, r, images);
      case ReportBarcodeElement():
        _paintBarcode(canvas, t, e, r);
      case ReportShapeElement():
        _paintShape(canvas, layout, e, r);
      case ReportChartElement():
        _paintChart(canvas, t, e, r, fonts ?? _defaultFonts, shapes, data);
      case ReportCrosstabElement():
      case ReportSubreportElement():
        _paintFrame(canvas, r, e.displayName);
    }
  }

  /// Whether [e] paints right to left.
  static bool isRtl(ReportTemplate t, ReportTextDirection d, String text) {
    switch (d) {
      case ReportTextDirection.rtl:
        return true;
      case ReportTextDirection.ltr:
        return false;
      case ReportTextDirection.auto:
        for (final int cp in text.runes) {
          if ((cp >= 0x0590 && cp <= 0x08FF) ||
              (cp >= 0xFB1D && cp <= 0xFDFF) ||
              (cp >= 0xFE70 && cp <= 0xFEFF)) {
            return true;
          }
          if ((cp >= 0x41 && cp <= 0x5A) ||
              (cp >= 0x61 && cp <= 0x7A) ||
              (cp >= 0xC0 && cp <= 0x24F)) {
            return false;
          }
        }
        return t.isRtl;
    }
  }

  static TextAlign _align(ReportTextAlign a) => switch (a) {
    ReportTextAlign.start => TextAlign.start,
    ReportTextAlign.end => TextAlign.end,
    ReportTextAlign.left => TextAlign.left,
    ReportTextAlign.right => TextAlign.right,
    ReportTextAlign.center => TextAlign.center,
    ReportTextAlign.justify => TextAlign.justify,
  };

  /// Text style of [e] (also used by the inline editor).
  static TextStyle styleOf(ReportTemplate t, ReportTextElement e) {
    final ReportTextStyle s = e.style;
    final String family = (s.fontFamily ?? '').isNotEmpty
        ? s.fontFamily!
        : (t.defaultFont.isNotEmpty ? t.defaultFont : fallbackFamilies.first);
    return TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallbackFamilies,
      fontSize: s.fontSize ?? t.defaultFontSize,
      fontWeight: s.bold ?? false ? FontWeight.bold : FontWeight.normal,
      fontStyle: s.italic ?? false ? FontStyle.italic : FontStyle.normal,
      decoration: s.underline ?? false
          ? TextDecoration.underline
          : TextDecoration.none,
      color: Color(t.resolveColor(s.color, t.textColor).argb),
      height: e.lineSpacing == 1 ? null : 1.2 * e.lineSpacing,
    );
  }

  /// Laid-out painter for [text] in [e]'s style; bindings are highlighted
  /// unless [plain].
  TextPainter textPainter(
    ReportTemplate t,
    ReportTextElement e,
    String text,
    double width, {
    bool plain = false,
    Color? color,
  }) {
    final TextStyle base = styleOf(t, e);
    final TextStyle style = color == null ? base : base.copyWith(color: color);
    final bool rtl = isRtl(t, e.direction, text);
    final String key =
        '${plain ? 1 : 0}|$width|${e.align.index}|$rtl|${e.wordWrap}|'
        '${style.fontFamily}|${style.fontSize}|${style.fontWeight}|'
        '${style.fontStyle}|${style.decoration}|${style.color}|'
        '${style.height}|$text';
    final TextPainter? hit = _text[key];
    if (hit != null) {
      return hit;
    }
    _trim();
    final TextPainter tp = TextPainter(
      text: plain ? TextSpan(text: text, style: style) : _spans(text, style),
      textAlign: _align(e.align),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    );
    final double w = width < 1 ? 1 : width;
    if (e.wordWrap) {
      tp.layout(minWidth: w, maxWidth: w);
    } else {
      tp.layout(minWidth: w);
    }
    _text[key] = tp;
    return tp;
  }

  static TextSpan _spans(String text, TextStyle style) {
    final List<InlineSpan> children = <InlineSpan>[];
    var at = 0;
    for (final RegExpMatch m in _binding.allMatches(text)) {
      if (m.start > at) {
        children.add(TextSpan(text: text.substring(at, m.start)));
      }
      children.add(
        TextSpan(
          text: m.group(0),
          style: const TextStyle(color: bindingColor),
        ),
      );
      at = m.end;
    }
    if (at < text.length) {
      children.add(TextSpan(text: text.substring(at)));
    }
    return TextSpan(style: style, children: children);
  }

  void _trim() {
    if (_text.length < 800) {
      return;
    }
    for (final TextPainter tp in _text.values) {
      tp.dispose();
    }
    _text.clear();
  }

  /// Drops cached text layouts (after new fonts load).
  void clearText() {
    for (final TextPainter tp in _text.values) {
      tp.dispose();
    }
    _text.clear();
  }

  /// Releases cached painters.
  void dispose() {
    _charts.clear();
    clearText();
  }

  void _guideOutline(Canvas canvas, Rect r) {
    canvas.drawPath(
      ReportLayoutPainter.dashPath(
        Path()..addRect(r),
        ReportLineStyle.dashed,
        0.5,
      ),
      Paint()
        ..color = _guide
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  void _box(
    Canvas canvas,
    ReportTemplate t,
    Rect r,
    String? background,
    String? borderColor,
    double borderWidth,
  ) {
    final ReportColor bg = t.resolveColor(background, ReportColor.transparent);
    if (bg.alpha > 0) {
      canvas.drawRect(r, Paint()..color = Color(bg.argb));
    }
    if (borderWidth > 0 && borderColor != null) {
      canvas.drawRect(
        r,
        Paint()
          ..color = Color(t.resolveColor(borderColor, ReportColor.black).argb)
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    } else {
      _guideOutline(canvas, r);
    }
  }

  void _paintText(
    Canvas canvas,
    ReportTemplate t,
    ReportTextElement e,
    Rect r, {
    required bool hideText,
  }) {
    _box(canvas, t, r, e.background, e.borderColor, e.borderWidth);
    if (hideText) {
      return;
    }
    final Rect content = r.deflate(e.padding);
    final TextPainter tp = textPainter(t, e, e.text, content.width);
    final double slack = content.height - tp.height;
    final double dy = switch (e.verticalAlign) {
      ReportVerticalAlign.top => 0,
      ReportVerticalAlign.middle => slack > 0 ? slack / 2 : 0,
      ReportVerticalAlign.bottom => slack > 0 ? slack : 0,
    };
    canvas.save();
    canvas.clipRect(r.inflate(0.5));
    tp.paint(canvas, Offset(content.left, content.top + dy));
    canvas.restore();
  }

  void _cellText(
    Canvas canvas,
    Rect cell,
    String text,
    TextStyle style,
    ReportTextAlign align,
    bool rtl,
    double padding,
  ) {
    final double w = cell.width - 2 * padding;
    if (w <= 1 || text.isEmpty) {
      return;
    }
    final String key =
        'cell|$w|${align.index}|$rtl|${style.fontSize}|${style.fontWeight}|'
        '${style.color}|$text';
    TextPainter? tp = _text[key];
    if (tp == null) {
      _trim();
      tp = TextPainter(
        text: _spans(text, style),
        textAlign: _align(align),
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(minWidth: w, maxWidth: w);
      _text[key] = tp;
    }
    tp.paint(
      canvas,
      Offset(cell.left + padding, cell.top + (cell.height - tp.height) / 2),
    );
  }

  void _paintTable(
    Canvas canvas,
    ReportTemplate t,
    ReportBand band,
    ReportTableElement e,
    Rect r,
  ) {
    final List<double> widths = e.resolvedColumnWidths();
    if (widths.isEmpty) {
      _guideOutline(canvas, r);
      return;
    }
    var total = 0.0;
    for (final double w in widths) {
      total += w;
    }
    final List<double> lefts = <double>[];
    var acc = 0.0;
    for (final double w in widths) {
      lefts.add(t.isRtl ? r.left + total - acc - w : r.left + acc);
      acc += w;
    }
    final TableRows rows = ReportDesignLayout.tableRows(t, band, e);
    final double fs = e.fontSize ?? t.defaultFontSize;
    final TextStyle base = TextStyle(
      fontFamily: (e.fontFamily ?? '').isNotEmpty
          ? e.fontFamily
          : (t.defaultFont.isEmpty ? fallbackFamilies.first : t.defaultFont),
      fontFamilyFallback: fallbackFamilies,
      fontSize: fs,
      color: Color(t.resolveColor(e.color, t.textColor).argb),
    );
    final Paint grid = Paint()
      ..color = Color(
        t.resolveColor(e.borderColor, const ReportColor(0xFFBFBFBF)).argb,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = e.borderWidth < 0.5 ? 0.5 : e.borderWidth;
    var y = r.top;
    if (e.showHeader) {
      final Rect row = Rect.fromLTWH(r.left, y, total, rows.header);
      canvas.drawRect(
        row,
        Paint()
          ..color = Color(
            t.resolveColor(e.headerBackground, t.primaryColor).argb,
          ),
      );
      final TextStyle hs = base.copyWith(
        fontSize: e.headerFontSize ?? fs,
        fontWeight: e.headerBold ? FontWeight.bold : FontWeight.normal,
        color: Color(t.resolveColor(e.headerColor, ReportColor.white).argb),
      );
      for (int i = 0; i < widths.length; i++) {
        final ReportTableColumn c = e.columns[i];
        final Rect cell = Rect.fromLTWH(lefts[i], y, widths[i], rows.header);
        _cellText(
          canvas,
          cell,
          c.header,
          hs,
          c.headerAlign ?? c.align,
          t.isRtl,
          e.padding,
        );
        if (e.showGrid) {
          canvas.drawRect(cell, grid);
        }
      }
      y += rows.header;
    }
    for (int i = 0; i < widths.length; i++) {
      final ReportTableColumn c = e.columns[i];
      final ReportTableCell? cell = i < e.cells.length ? e.cells[i] : null;
      final Rect box = Rect.fromLTWH(lefts[i], y, widths[i], rows.body);
      final ReportColor? fill = cell?.background == null
          ? null
          : t.resolveColor(cell!.background, ReportColor.transparent);
      if (fill != null && fill.alpha > 0) {
        canvas.drawRect(box, Paint()..color = Color(fill.argb));
      }
      _cellText(
        canvas,
        box,
        cell?.template ?? '',
        base.copyWith(
          fontWeight: cell?.bold ?? false ? FontWeight.bold : FontWeight.normal,
          color: cell?.color == null
              ? null
              : Color(t.resolveColor(cell!.color, t.textColor).argb),
        ),
        cell?.align ?? c.align,
        t.isRtl,
        e.padding,
      );
      if (e.showGrid) {
        canvas.drawRect(box, grid);
      }
    }
    y += rows.body;
    if (e.footerCells.isNotEmpty) {
      for (int i = 0; i < widths.length; i++) {
        final ReportTableCell? cell = i < e.footerCells.length
            ? e.footerCells[i]
            : null;
        final Rect box = Rect.fromLTWH(lefts[i], y, widths[i], rows.footer);
        _cellText(
          canvas,
          box,
          cell?.template ?? '',
          base.copyWith(fontWeight: FontWeight.bold),
          cell?.align ?? e.columns[i].align,
          t.isRtl,
          e.padding,
        );
        if (e.showGrid) {
          canvas.drawRect(box, grid);
        }
      }
    }
    if (!e.showGrid) {
      _guideOutline(canvas, Rect.fromLTWH(r.left, r.top, total, r.height));
    }
  }

  Uint8List? _bytesFor(String source, Map<String, Uint8List> images) {
    final Uint8List? named = images[source];
    if (named != null) {
      return named;
    }
    if (source.contains('{{')) {
      return null;
    }
    return _decoded.putIfAbsent(source, () {
      final String s = source.trim();
      final int comma = s.indexOf(',');
      final String payload = s.startsWith('data:') && comma > 0
          ? s.substring(comma + 1)
          : s;
      if (payload.length < 32) {
        return null;
      }
      try {
        return base64Decode(payload.replaceAll(RegExp(r'\s'), ''));
      } on FormatException {
        return null;
      }
    });
  }

  void _paintImage(
    Canvas canvas,
    ReportTemplate t,
    ReportImageElement e,
    Rect r,
    Map<String, Uint8List> images,
  ) {
    final Uint8List? bytes = _bytesFor(e.source, images);
    final ui.Image? image = bytes == null ? null : raster.imageFor(bytes);
    final ReportColor bg = t.resolveColor(
      e.background,
      ReportColor.transparent,
    );
    if (bg.alpha > 0) {
      canvas.drawRect(r, Paint()..color = Color(bg.argb));
    }
    if (image == null) {
      canvas.drawRect(r, Paint()..color = const Color(0xFFF1F3F5));
      final Paint cross = Paint()
        ..color = const Color(0xFFC5CAD1)
        ..strokeWidth = 0.75;
      canvas.drawLine(r.topLeft, r.bottomRight, cross);
      canvas.drawLine(r.bottomLeft, r.topRight, cross);
      final String label = e.source.isEmpty
          ? 'Image'
          : (e.source.length > 40 ? 'Image' : e.source);
      _caption(canvas, r, label);
    } else {
      final double iw = image.width.toDouble();
      final double ih = image.height.toDouble();
      final Rect dst = _fit(e.fit, r, iw, ih);
      canvas.save();
      canvas.clipRect(r);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, iw, ih),
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    }
    if (e.borderWidth > 0 && e.borderColor != null) {
      canvas.drawRect(
        r,
        Paint()
          ..color = Color(t.resolveColor(e.borderColor, ReportColor.black).argb)
          ..style = PaintingStyle.stroke
          ..strokeWidth = e.borderWidth,
      );
    } else {
      _guideOutline(canvas, r);
    }
  }

  static Rect _fit(ReportImageFit fit, Rect r, double iw, double ih) {
    if (iw <= 0 || ih <= 0) {
      return r;
    }
    switch (fit) {
      case ReportImageFit.fill:
        return r;
      case ReportImageFit.none:
        return Rect.fromCenter(
          center: r.center,
          width: iw * 0.75,
          height: ih * 0.75,
        );
      case ReportImageFit.contain:
      case ReportImageFit.cover:
        final double sx = r.width / iw;
        final double sy = r.height / ih;
        final double s = fit == ReportImageFit.contain
            ? (sx < sy ? sx : sy)
            : (sx > sy ? sx : sy);
        return Rect.fromCenter(center: r.center, width: iw * s, height: ih * s);
    }
  }

  void _caption(Canvas canvas, Rect r, String label) {
    final String key = 'cap|${r.width}|$label';
    TextPainter? tp = _text[key];
    if (tp == null) {
      _trim();
      tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontFamily: 'Liberation Sans',
            fontFamilyFallback: fallbackFamilies,
            fontSize: 7,
            color: Color(0xFF6B7280),
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: r.width < 8 ? 8 : r.width - 4);
      _text[key] = tp;
    }
    tp.paint(
      canvas,
      Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2),
    );
  }

  void _paintBarcode(
    Canvas canvas,
    ReportTemplate t,
    ReportBarcodeElement e,
    Rect r,
  ) {
    final ReportColor bg = t.resolveColor(
      e.background,
      ReportColor.transparent,
    );
    if (bg.alpha > 0) {
      canvas.drawRect(r, Paint()..color = Color(bg.argb));
    }
    final Paint ink = Paint()
      ..color = Color(t.resolveColor(e.color, ReportColor.black).argb);
    final String data = e.data;
    if (e.symbology == ReportBarcodeType.qr) {
      final List<List<bool>>? m = _qr.putIfAbsent(data, () {
        if (data.isEmpty) {
          return null;
        }
        try {
          return const QrEncoder().encode(
            String.fromCharCodes(utf8.encode(data)),
          );
        } on Object {
          return null;
        }
      });
      if (m == null || m.isEmpty) {
        _invalid(canvas, r);
        return;
      }
      final int n = m.length;
      final double side = r.width < r.height ? r.width : r.height;
      final double cell = side / (n + 8);
      final double ox = r.left + (r.width - cell * n) / 2;
      final double oy = r.top + (r.height - cell * n) / 2;
      for (int y = 0; y < n; y++) {
        for (int x = 0; x < m[y].length; x++) {
          if (m[y][x]) {
            canvas.drawRect(
              Rect.fromLTWH(
                ox + x * cell,
                oy + y * cell,
                cell + 0.02,
                cell + 0.02,
              ),
              ink,
            );
          }
        }
      }
      _guideOutline(canvas, r);
      return;
    }
    final List<bool>? modules = _code128.putIfAbsent(data, () {
      if (data.isEmpty) {
        return null;
      }
      try {
        return const Code128Encoder().encodeWithQuietZone(data);
      } on Object {
        return null;
      }
    });
    if (modules == null || modules.isEmpty) {
      _invalid(canvas, r);
      return;
    }
    final double labelH = e.showText ? e.fontSize * 1.25 : 0;
    final double barH = r.height - labelH > 4 ? r.height - labelH : r.height;
    final double w = r.width / modules.length;
    var i = 0;
    while (i < modules.length) {
      if (!modules[i]) {
        i++;
        continue;
      }
      final int start = i;
      while (i < modules.length && modules[i]) {
        i++;
      }
      canvas.drawRect(
        Rect.fromLTWH(r.left + start * w, r.top, (i - start) * w, barH),
        ink,
      );
    }
    if (e.showText && barH < r.height) {
      final Rect label = Rect.fromLTWH(r.left, r.top + barH, r.width, labelH);
      _cellText(
        canvas,
        label,
        data,
        TextStyle(
          fontFamily: 'Liberation Sans',
          fontSize: e.fontSize,
          color: ink.color,
        ),
        ReportTextAlign.center,
        false,
        0,
      );
    }
  }

  void _invalid(Canvas canvas, Rect r) {
    canvas.drawRect(r, Paint()..color = const Color(0x22D32F2F));
    _caption(canvas, r, 'Invalid barcode data');
    _guideOutline(canvas, r);
  }

  void _paintShape(
    Canvas canvas,
    ReportDesignLayout layout,
    ReportShapeElement e,
    Rect r,
  ) {
    final ReportTemplate t = layout.template;
    final ReportColor stroke = t.resolveColor(e.strokeColor, ReportColor.black);
    final double sw = e.strokeWidth;
    if (e.kind == ReportShapeKind.line) {
      final (Offset a, Offset b) = layout.lineEnds(r, e);
      final Path path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
      canvas.drawPath(
        ReportLayoutPainter.dashPath(path, e.lineStyle, sw > 0 ? sw : 0.5),
        ReportLayoutPainter.strokePaint(
          sw > 0 ? stroke : const ReportColor(0x55808080),
          sw > 0 ? sw : 0.5,
          e.lineStyle,
        ),
      );
      return;
    }
    final Path path = Path();
    switch (e.kind) {
      case ReportShapeKind.ellipse:
        path.addOval(r);
      case ReportShapeKind.roundedRectangle:
        final double radius = e.cornerRadius > 0 ? e.cornerRadius : 4;
        path.addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
      case ReportShapeKind.rectangle:
        path.addRect(r);
      case ReportShapeKind.line:
        break;
    }
    final ReportColor fill = t.resolveColor(e.fill, ReportColor.transparent);
    if (fill.alpha > 0) {
      canvas.drawPath(path, Paint()..color = Color(fill.argb));
    }
    if (sw > 0 && stroke.alpha > 0) {
      canvas.drawPath(
        ReportLayoutPainter.dashPath(path, e.lineStyle, sw),
        ReportLayoutPainter.strokePaint(stroke, sw, e.lineStyle),
      );
    } else {
      _guideOutline(canvas, r);
    }
  }

  void _paintFrame(Canvas canvas, Rect r, String label) {
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF6B7280),
    );
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 11, color: Color(0xFF374151)),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: r.width > 8 ? r.width - 8 : r.width);
    painter.paint(canvas, r.topLeft + const Offset(4, 4));
  }

  /// Chart drawn by the engine's renderer: static points with their literal
  /// values, data-bound series with sample values over sample categories.
  void _paintChart(
    Canvas canvas,
    ReportTemplate t,
    ReportChartElement e,
    Rect r,
    ReportFontRegistry fonts,
    Map<String, Uint8List> shapes,
    Map<String, Object?>? data,
  ) {
    final ReportColor bg = t.resolveColor(
      e.background,
      ReportColor.transparent,
    );
    if (bg.alpha > 0) {
      canvas.drawRect(r, Paint()..color = Color(bg.argb));
    }
    final ReportChartData chart = sampleChartData(
      t,
      e,
      shapes: shapes,
      data: data,
    );
    final String key = <Object?>[
      r.width,
      r.height,
      identityHashCode(fonts),
      chart.type,
      chart.title,
      chart.rtl,
      chart.showLegend,
      chart.showValues,
      chart.showGrid,
      chart.showAxes,
      chart.valueFormat,
      chart.categories.join('\u0001'),
      for (final String label in chart.regionLabels ?? const <String>[]) label,
      for (final String label
          in chart.featureLabels?.values ?? const <String>[])
        label,
      for (final ReportChartSeriesData s in chart.series) ...<Object>[
        s.name,
        s.color.argb,
        s.values.join(','),
      ],
      for (final ReportColor c in chart.pointColors) c.argb,
      e.shape,
      e.showLabels,
      e.labelField,
      e.regionColor,
      e.lowColor,
      e.highColor,
      e.emptyColor,
      identityHashCode(shapes[e.shape]),
      e.fontFamily,
      e.fontSize,
      e.bold,
      e.italic,
      e.textColor,
      e.titleStyle.fontFamily,
      e.titleStyle.fontSize,
      e.titleStyle.bold,
      e.titleStyle.italic,
      e.titleStyle.color,
      e.labelStyle.fontFamily,
      e.labelStyle.fontSize,
      e.labelStyle.bold,
      e.labelStyle.italic,
      e.labelStyle.color,
      e.legendStyle.fontFamily,
      e.legendStyle.fontSize,
      e.legendStyle.bold,
      e.legendStyle.italic,
      e.legendStyle.color,
      t.defaultFont,
    ].join('|');
    List<ReportPrimitive>? prims = _charts[key];
    if (prims == null) {
      if (_charts.length > 200) {
        _charts.clear();
      }
      final ReportTextShaper shaper = ReportTextShaper(fonts);
      prims =
          ReportChartRenderer(
            shaper: shaper,
            formatter: ReportFormatter(defaults: t.formats),
          ).render(
            chart,
            ReportRect(0, 0, r.width, r.height),
            font: ReportFontSpec(
              family: e.fontFamily ?? t.defaultFont,
              size: e.fontSize > 0 ? e.fontSize : 7.5,
              bold: e.bold,
              italic: e.italic,
            ),
            textColor: t.resolveColor(e.textColor, t.textColor),
            labelColor: (e.labelStyle.color ?? e.textColor) == null
                ? null
                : t.resolveColor(
                    e.labelStyle.color ?? e.textColor,
                    t.textColor,
                  ),
          );
      _charts[key] = prims;
    }
    canvas.save();
    canvas.clipRect(r.inflate(0.5));
    canvas.translate(r.left, r.top);
    raster.paintPrimitives(canvas, fonts, prims);
    canvas.restore();
    final String? source = e.series.isEmpty
        ? null
        : (e.dataSet ?? '').trim().isNotEmpty
        ? e.dataSet!.trim()
        : 'band rows';
    if (source != null) {
      _bindingTag(canvas, r, '$source · ${e.category ?? ''}');
    }
    if (e.borderWidth > 0 && e.borderColor != null) {
      canvas.drawRect(
        r,
        Paint()
          ..color = Color(t.resolveColor(e.borderColor, ReportColor.black).argb)
          ..style = PaintingStyle.stroke
          ..strokeWidth = e.borderWidth,
      );
    } else {
      _guideOutline(canvas, r);
    }
  }

  /// Design-time content of [e]: literal static points, or sample values
  /// for data-bound series (the real values come from the data source).
  static ReportChartData sampleChartData(
    ReportTemplate t,
    ReportChartElement e, {
    Map<String, Uint8List> shapes = const <String, Uint8List>{},
    Map<String, Object?>? data,
  }) {
    ReportColor palette(int i) =>
        t.resolveColor(e.paletteColor(i), t.primaryColor);
    final List<String> categories = <String>[];
    final List<ReportChartSeriesData> series = <ReportChartSeriesData>[];
    final List<ReportColor> pointColors = <ReportColor>[];
    var varyColors = e.isRadial;
    if (e.series.isEmpty) {
      final List<double> values = <double>[];
      final List<double> xs = <double>[];
      final List<double> sizes = <double>[];
      final List<bool> totals = <bool>[];
      for (int i = 0; i < e.points.length; i++) {
        final ReportChartPoint p = e.points[i];
        categories.add(p.label);
        values.add(double.tryParse(p.value.trim()) ?? _sample[i % 8]);
        xs.add(double.tryParse(p.x?.trim() ?? '') ?? (i + 1).toDouble());
        sizes.add(double.tryParse(p.size?.trim() ?? '') ?? (4 + i).toDouble());
        totals.add(p.total || (e.lastIsTotal && i == e.points.length - 1));
        pointColors.add(
          p.color == null ? palette(i) : t.resolveColor(p.color, palette(i)),
        );
        varyColors = varyColors || p.color != null;
      }
      series.add(
        ReportChartSeriesData(
          name: '',
          color: palette(0),
          values: values,
          xs: xs,
          sizes: sizes,
          totals: totals,
        ),
      );
    } else {
      final List<String> labels = e.chartType.isShapeMap
          ? const <String>['LY', 'EG', 'SA', 'US', 'FR', 'CN', 'BR', 'IN']
          : (t.isRtl ? _arabic : _latin);
      final int n = e.chartType.isShapeMap
          ? labels.length
          : e.limit > 0 && e.limit < labels.length
          ? e.limit
          : (e.isRadial ? 4 : 5);
      for (int i = 0; i < n; i++) {
        categories.add(labels[i]);
        pointColors.add(palette(i));
      }
      for (int s = 0; s < e.series.length; s++) {
        final ReportChartSeries def = e.series[s];
        series.add(
          ReportChartSeriesData(
            name: def.name.isEmpty && e.series.length > 1
                ? 'Series ${s + 1}'
                : def.name,
            color: def.color == null
                ? palette(s)
                : t.resolveColor(def.color, palette(s)),
            values: <double>[
              for (int i = 0; i < n; i++)
                _sample[(i + 3 * s) % 8] * (1 + s / 4),
            ],
            xs: <double>[for (int i = 0; i < n; i++) (i + 1).toDouble()],
            sizes: <double>[for (int i = 0; i < n; i++) 4 + i.toDouble()],
            style: def.style,
            secondary: def.secondary,
          ),
        );
      }
      if (e.sortBy == ReportChartSort.value) {
        final List<int> order = List<int>.generate(n, (int i) => i)
          ..sort((int a, int b) {
            final int c = series.first.values[a].compareTo(
              series.first.values[b],
            );
            return e.descending ? -c : c;
          });
        for (int s = 0; s < series.length; s++) {
          final ReportChartSeriesData d = series[s];
          series[s] = d.pick(order);
        }
        final List<String> sorted = <String>[
          for (final int i in order) categories[i],
        ];
        categories
          ..clear()
          ..addAll(sorted);
      }
    }
    final List<String>? regionLabels = _formulaLabels(
      e,
      data,
      categories,
      series,
      pointColors,
      palette,
      shapes,
    );
    Map<String, String>? featureLabels;
    if (e.chartType.isShapeMap && e.showLabels) {
      final ReportShapeLayer? layer = ReportShapes.resolve(e.shape, shapes);
      final String field = (e.labelField ?? '').trim();
      if (layer != null && field.isNotEmpty) {
        final ReportValue root = data == null
            ? ReportRecord.empty
            : ReportValue.from(data);
        featureLabels = QudsExpressionEngine().shapeFieldLabels(
          field: field,
          layer: layer,
          schema: t.dataSchema,
          data: root is ReportRecord ? root : null,
          keyField: e.shapeKey,
        );
      }
    }
    final ReportFontSpec chartFont = ReportFontSpec(
      family: e.fontFamily ?? t.defaultFont,
      size: e.fontSize > 0 ? e.fontSize : 7.5,
      bold: e.bold,
      italic: e.italic,
    );
    final bool map = e.chartType.isShapeMap;
    return ReportChartData(
      type: e.chartType,
      title: e.title,
      categories: categories,
      series: series,
      pointColors: pointColors,
      rtl: t.mirrored,
      varyColors: varyColors,
      showLegend: e.showLegend,
      showValues: e.showValues,
      showGrid: e.showGrid,
      showAxes: e.showAxes,
      valueFormat: e.valueFormat,
      depth: e.depth,
      skew: e.skew,
      hole: e.hole,
      startAngle: e.startAngle,
      smooth: e.smooth,
      showMarkers: e.showMarkers,
      markerSize: e.markerSize,
      lineWidth: e.lineWidth,
      axisMin: e.axisMin,
      axisMax: e.axisMax,
      axisMin2: e.axisMin2,
      axisMax2: e.axisMax2,
      showPercent: e.showPercent,
      lastIsTotal: e.lastIsTotal,
      bands: e.bands,
      increase: t.resolveColor(e.increaseColor, const ReportColor(0xFF2E7D32)),
      decrease: t.resolveColor(e.decreaseColor, const ReportColor(0xFFC62828)),
      total: t.resolveColor(e.totalColor, const ReportColor(0xFF37474F)),
      shapes: e.chartType.isShapeMap
          ? ReportShapes.resolve(e.shape, shapes)
          : null,
      showLabels: e.showLabels,
      labelField: e.labelField,
      regionLabels: regionLabels,
      featureLabels: featureLabels,
      titleFont: map ? reportStyleFont(e.titleStyle, chartFont) : null,
      titleInk: map
          ? t.resolveColor(e.titleStyle.color ?? e.textColor, t.textColor)
          : null,
      labelFont: map ? reportStyleFont(e.labelStyle, chartFont) : null,
      legendFont: map ? reportStyleFont(e.legendStyle, chartFont) : null,
      legendInk: map
          ? t.resolveColor(e.legendStyle.color ?? e.textColor, t.textColor)
          : null,
      regionColors: (e.regionColor ?? '').trim().isEmpty
          ? null
          : <ReportColor?>[
              for (int i = 0; i < categories.length; i++) palette(i),
            ],
      low: t.resolveColor(e.lowColor, const ReportColor(0xFFDEEBF7)),
      high: t.resolveColor(e.highColor, const ReportColor(0xFF08306B)),
      empty: t.resolveColor(e.emptyColor, const ReportColor(0xFFE4E4E4)),
    );
  }

  /// When the label is a formula, captions come from [data] and the
  /// sample categories become the real region keys. An empty list still
  /// marks formula mode, so a missing row is not labeled with the key.
  static List<String>? _formulaLabels(
    ReportChartElement e,
    Map<String, Object?>? data,
    List<String> categories,
    List<ReportChartSeriesData> series,
    List<ReportColor> pointColors,
    ReportColor Function(int) palette,
    Map<String, Uint8List> shapes,
  ) {
    if (!e.chartType.isShapeMap ||
        !QudsExpressionEngine.isLabelFormula(e.labelField)) {
      return null;
    }
    final List<ReportValue> rows = data == null
        ? const <ReportValue>[]
        : _boundRows(data, e.dataSet);
    final ReportValue root = ReportValue.from(data);
    final Map<String, String> captions = rows.isEmpty
        ? const <String, String>{}
        : QudsExpressionEngine().regionCaptions(
            e.labelField!.trim(),
            e.category,
            rows,
            ReportScope(
              data: root is ReportRecord ? root : ReportRecord.empty,
              variables: ReportRecord.empty,
              system: ReportSystemInfo(now: DateTime.utc(2020)),
            ),
            shapes: ReportShapes.resolve(e.shape, shapes),
          );
    if (captions.isNotEmpty) {
      categories
        ..clear()
        ..addAll(captions.keys);
      pointColors
        ..clear()
        ..addAll(<ReportColor>[
          for (int i = 0; i < categories.length; i++) palette(i),
        ]);
      for (int s = 0; s < series.length; s++) {
        final ReportChartSeriesData old = series[s];
        series[s] = ReportChartSeriesData(
          name: old.name,
          color: old.color,
          values: <double>[
            for (int i = 0; i < categories.length; i++)
              _sample[(i + 3 * s) % 8] * (1 + s / 4),
          ],
          style: old.style,
          secondary: old.secondary,
        );
      }
      return <String>[for (final String key in categories) captions[key] ?? ''];
    }
    return List<String>.filled(categories.length, '');
  }

  static List<ReportValue> _boundRows(
    Map<String, Object?> data,
    String? dataSet,
  ) {
    final String set = (dataSet ?? '').trim();
    if (set.isEmpty) {
      return const <ReportValue>[];
    }
    final String path = set.replaceFirst(
      RegExp(r'^Data\.', caseSensitive: false),
      '',
    );
    final ReportValue value = ReportValue.from(ReportData.valueAt(data, path));
    if (value is ReportList) {
      return value.items;
    }
    return const <ReportValue>[];
  }

  void _bindingTag(Canvas canvas, Rect r, String label) {
    final String key = 'tag|${r.width}|$label';
    TextPainter? tp = _text[key];
    if (tp == null) {
      _trim();
      tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontFamily: 'Liberation Sans',
            fontFamilyFallback: fallbackFamilies,
            fontSize: 5.5,
            color: bindingColor,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: r.width < 8 ? 8 : r.width - 4);
      _text[key] = tp;
    }
    final Rect chip = Rect.fromLTWH(
      r.left + 1,
      r.top + 1,
      tp.width + 3,
      tp.height + 1,
    );
    canvas.drawRect(chip, Paint()..color = const Color(0xE6E3F2FD));
    tp.paint(canvas, Offset(chip.left + 1.5, chip.top + 0.5));
  }
}
