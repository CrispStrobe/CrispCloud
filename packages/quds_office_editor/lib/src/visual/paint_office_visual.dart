import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../editor_word/paint_run_text.dart';

/// Decodes PNG bytes once and paints charts / diagrams on any Office canvas.
class VisualImageCache {
  final Map<int, ui.Image> _ready = <int, ui.Image>{};
  final Set<int> _loading = <int>{};

  ui.Image? get(Uint8List bytes) => _ready[identityHashCode(bytes)];

  /// load API.
  void load(Uint8List bytes, VoidCallback onReady) {
    final int key = identityHashCode(bytes);
    if (_ready.containsKey(key) || _loading.contains(key)) {
      return;
    }
    _loading.add(key);
    ui.decodeImageFromList(bytes, (ui.Image image) {
      _ready[key] = image;
      _loading.remove(key);
      onReady();
    });
  }
}

/// Class PaintOfficeVisual.
abstract final class PaintOfficeVisual {
  /// paint API.
  static void paint(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual, {
    required String fontFamily,
    VisualImageCache? images,
    VoidCallback? onImageReady,
    bool cropPreview = false,
  }) {
    switch (visual.kind) {
      case OfficeVisualKind.picture:
        _picture(
          canvas,
          rect,
          visual,
          images,
          onImageReady,
          cropPreview: cropPreview,
        );
      case OfficeVisualKind.chartColumn:
        _column(canvas, rect, visual, fontFamily);
      case OfficeVisualKind.chartBar:
        _bar(canvas, rect, visual, fontFamily);
      case OfficeVisualKind.chartPie:
        _pie(canvas, rect, visual, fontFamily);
      case OfficeVisualKind.chartLine:
        _line(canvas, rect, visual, fontFamily);
      case OfficeVisualKind.diagramProcess:
        _process(canvas, rect, visual, fontFamily);
      case OfficeVisualKind.diagramCycle:
        _cycle(canvas, rect, visual, fontFamily);
      case OfficeVisualKind.diagramHierarchy:
        _hierarchy(canvas, rect, visual, fontFamily);
    }
  }

  static void _picture(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    VisualImageCache? images,
    VoidCallback? onImageReady, {
    bool cropPreview = false,
  }) {
    final Uint8List? bytes = visual.imageBytes;
    if (bytes == null || bytes.isEmpty) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = const Color(0xFFF3F6FB),
      );
      _label(
        canvas,
        rect,
        visual.title.isEmpty ? 'Picture' : visual.title,
        fontSize: 12,
      );
      return;
    }
    if (images == null) {
      return;
    }
    final ui.Image? image = images.get(bytes);
    if (image == null) {
      images.load(bytes, onImageReady ?? () {});
      return;
    }
    final PictureAdjust adj = visual.picture;
    final Rect dest = adj.borderWidth > 0
        ? rect.deflate(adj.borderWidth)
        : rect;
    canvas.save();
    final Offset c = dest.center;
    if (adj.shadow) {
      canvas.drawRect(
        dest.shift(const Offset(3, 3)),
        Paint()..color = const Color(0x66000000),
      );
    }
    if (adj.rotationDeg.abs() > 0.05 || adj.flipH || adj.flipV) {
      canvas.translate(c.dx, c.dy);
      if (adj.rotationDeg.abs() > 0.05) {
        canvas.rotate(adj.rotationDeg * math.pi / 180);
      }
      canvas.scale(adj.flipH ? -1 : 1, adj.flipV ? -1 : 1);
      canvas.translate(-c.dx, -c.dy);
    }
    final Paint paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true
      ..blendMode = BlendMode.srcOver;
    if (adj.transparency > 0.01) {
      paint.color = Color.fromRGBO(255, 255, 255, 1 - adj.transparency);
    }
    if (adj.brightness.abs() > 0.01 || (adj.contrast - 1).abs() > 0.01) {
      final double k = adj.contrast;
      final double b = adj.brightness * 255;
      paint.colorFilter = ColorFilter.matrix(<double>[
        k,
        0,
        0,
        0,
        b,
        0,
        k,
        0,
        0,
        b,
        0,
        0,
        k,
        0,
        b,
        0,
        0,
        0,
        1 - adj.transparency,
        0,
      ]);
    }
    final double sl = (image.width * adj.cropLeft).clamp(0, image.width / 2);
    final double st = (image.height * adj.cropTop).clamp(0, image.height / 2);
    final double sr = (image.width * adj.cropRight).clamp(0, image.width / 2);
    final double sb = (image.height * adj.cropBottom).clamp(
      0,
      image.height / 2,
    );
    if (cropPreview) {
      final double keepW = (1 - adj.cropLeft - adj.cropRight).clamp(0.12, 1);
      final double keepH = (1 - adj.cropTop - adj.cropBottom).clamp(0.12, 1);
      final Rect full = Rect.fromLTWH(
        dest.left - dest.width * adj.cropLeft / keepW,
        dest.top - dest.height * adj.cropTop / keepH,
        dest.width / keepW,
        dest.height / keepH,
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        full,
        Paint()..color = const Color(0x99FFFFFF),
      );
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        sl,
        st,
        (image.width - sl - sr).clamp(1, image.width.toDouble()),
        (image.height - st - sb).clamp(1, image.height.toDouble()),
      ),
      dest,
      paint,
    );
    if (adj.borderWidth > 0 && adj.borderColor.isNotEmpty) {
      canvas.drawRect(
        dest.inflate(adj.borderWidth / 2),
        Paint()
          ..color = _hex(adj.borderColor)
          ..style = PaintingStyle.stroke
          ..strokeWidth = adj.borderWidth,
      );
    }
    canvas.restore();
  }

  static void _column(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final double maxV = pts.fold<double>(
      1,
      (double m, ChartPoint p) => math.max(m, p.value),
    );
    final double gap = 8;
    final double barW = (plot.width - gap * (pts.length + 1)) / pts.length;
    for (int i = 0; i < pts.length; i++) {
      final double h = plot.height * (pts[i].value / maxV);
      final Rect bar = Rect.fromLTWH(
        plot.left + gap + i * (barW + gap),
        plot.bottom - h,
        barW,
        h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(3)),
        Paint()..color = _hex(pts[i].color),
      );
      if (visual.chart.showDataLabels) {
        _label(
          canvas,
          Rect.fromLTWH(bar.left, bar.top - 14, barW, 14),
          pts[i].value.toStringAsFixed(0),
          fontSize: 8,
          fontFamily: fontFamily,
        );
      }
      _label(
        canvas,
        Rect.fromLTWH(bar.left, plot.bottom + 2, barW, 14),
        pts[i].label,
        fontSize: 9,
        fontFamily: fontFamily,
      );
    }
  }

  static void _bar(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final double maxV = pts.fold<double>(
      1,
      (double m, ChartPoint p) => math.max(m, p.value),
    );
    final double gap = 6;
    final double barH = (plot.height - gap * (pts.length + 1)) / pts.length;
    for (int i = 0; i < pts.length; i++) {
      final double w = plot.width * (pts[i].value / maxV);
      final Rect bar = Rect.fromLTWH(
        plot.left,
        plot.top + gap + i * (barH + gap),
        w,
        barH,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(3)),
        Paint()..color = _hex(pts[i].color),
      );
      _label(
        canvas,
        Rect.fromLTWH(bar.right + 4, bar.top, 48, barH),
        pts[i].label,
        fontSize: 9,
        fontFamily: fontFamily,
        align: TextAlign.left,
      );
    }
  }

  static void _pie(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    final double sum = pts.fold<double>(
      0,
      (double a, ChartPoint p) => a + p.value,
    );
    if (sum <= 0) {
      return;
    }
    final double side = math.min(plot.width * 0.55, plot.height);
    final Rect pie = Rect.fromCenter(
      center: Offset(plot.left + side / 2 + 8, plot.center.dy),
      width: side,
      height: side,
    );
    var start = -math.pi / 2;
    for (final ChartPoint p in pts) {
      final double sweep = (p.value / sum) * math.pi * 2;
      canvas.drawArc(pie, start, sweep, true, Paint()..color = _hex(p.color));
      start += sweep;
    }
    if (visual.chart.showLegend) {
      var ly = plot.top + 8;
      for (final ChartPoint p in pts) {
        final Rect swatch = Rect.fromLTWH(pie.right + 16, ly + 3, 8, 8);
        canvas.drawRect(swatch, Paint()..color = _hex(p.color));
        _label(
          canvas,
          Rect.fromLTWH(swatch.right + 6, ly, 90, 16),
          visual.chart.showDataLabels
              ? '${p.label} ${p.value.toStringAsFixed(0)}'
              : p.label,
          fontSize: 10,
          fontFamily: fontFamily,
          align: TextAlign.left,
        );
        ly += 16;
      }
    }
  }

  static void _line(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    if (pts.length < 2) {
      return;
    }
    final double maxV = pts.fold<double>(
      1,
      (double m, ChartPoint p) => math.max(m, p.value),
    );
    final Path path = Path();
    for (int i = 0; i < pts.length; i++) {
      final double x = plot.left + plot.width * i / (pts.length - 1);
      final double y = plot.bottom - plot.height * (pts[i].value / maxV);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = _hex(pts[i].color));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF2B579A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  static void _process(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final double boxW = math.min(
      110,
      (plot.width - 24 * pts.length) / pts.length,
    );
    final double boxH = 44;
    final double y = plot.center.dy - boxH / 2;
    for (int i = 0; i < pts.length; i++) {
      final double x = plot.left + i * (boxW + 24);
      final Rect box = Rect.fromLTWH(x, y, boxW, boxH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(6)),
        Paint()..color = _hex(pts[i].color),
      );
      _label(
        canvas,
        box,
        pts[i].label,
        fontFamily: fontFamily,
        color: const Color(0xFFFFFFFF),
      );
      if (i < pts.length - 1) {
        final Offset a = Offset(box.right + 2, box.center.dy);
        final Offset b = Offset(box.right + 20, box.center.dy);
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFF555555)
            ..strokeWidth = 1.5,
        );
        canvas.drawLine(
          b,
          Offset(b.dx - 6, b.dy - 4),
          Paint()
            ..color = const Color(0xFF555555)
            ..strokeWidth = 1.5,
        );
        canvas.drawLine(
          b,
          Offset(b.dx - 6, b.dy + 4),
          Paint()
            ..color = const Color(0xFF555555)
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  static void _cycle(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final Offset c = plot.center;
    final double r = math.min(plot.width, plot.height) / 2 - 28;
    for (int i = 0; i < pts.length; i++) {
      final double a = -math.pi / 2 + i * (math.pi * 2 / pts.length);
      final Offset p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      final Rect box = Rect.fromCenter(center: p, width: 72, height: 28);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(14)),
        Paint()..color = _hex(pts[i].color),
      );
      _label(
        canvas,
        box,
        pts[i].label,
        fontFamily: fontFamily,
        color: const Color(0xFFFFFFFF),
      );
    }
    canvas.drawCircle(
      c,
      18,
      Paint()
        ..color = const Color(0xFF2B579A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  static void _hierarchy(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    _frame(canvas, rect, visual, fontFamily);
    final Rect plot = _plot(rect, visual);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final Rect root = Rect.fromCenter(
      center: Offset(plot.center.dx, plot.top + 22),
      width: 100,
      height: 28,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(root, const Radius.circular(4)),
      Paint()..color = _hex(pts.first.color),
    );
    _label(
      canvas,
      root,
      pts.first.label,
      fontFamily: fontFamily,
      color: const Color(0xFFFFFFFF),
    );
    final List<ChartPoint> kids = pts.length > 1
        ? pts.sublist(1)
        : <ChartPoint>[];
    if (kids.isEmpty) {
      return;
    }
    final double gap = plot.width / kids.length;
    for (int i = 0; i < kids.length; i++) {
      final Rect child = Rect.fromCenter(
        center: Offset(plot.left + gap * (i + 0.5), plot.bottom - 22),
        width: math.min(90, gap - 8),
        height: 28,
      );
      canvas.drawLine(
        root.bottomCenter,
        child.topCenter,
        Paint()..color = const Color(0xFF888888),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(child, const Radius.circular(4)),
        Paint()..color = _hex(kids[i].color),
      );
      _label(
        canvas,
        child,
        kids[i].label,
        fontFamily: fontFamily,
        color: const Color(0xFFFFFFFF),
      );
    }
  }

  static void _frame(
    Canvas canvas,
    Rect rect,
    OfficeVisual visual,
    String fontFamily,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..color = const Color(0xFF8FAADC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    if (visual.title.isNotEmpty &&
        (!visual.isChart || visual.chart.showTitle)) {
      _label(
        canvas,
        Rect.fromLTWH(rect.left + 8, rect.top + 4, rect.width - 16, 16),
        visual.title,
        fontSize: 11,
        fontFamily: fontFamily,
        align: TextAlign.left,
        bold: true,
      );
    }
    if (visual.chart.showAxes &&
        visual.isChart &&
        visual.kind != OfficeVisualKind.chartPie) {
      final Rect plot = _plot(rect, visual);
      final Paint axis = Paint()
        ..color = const Color(0xFF888888)
        ..strokeWidth = 0.8;
      canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
      canvas.drawLine(plot.bottomLeft, plot.topLeft, axis);
      if (visual.chart.showGridlines) {
        final Paint grid = Paint()
          ..color = const Color(0xFFD0D0D0)
          ..strokeWidth = 0.6;
        for (int i = 1; i <= 3; i++) {
          final double y = plot.bottom - plot.height * i / 4;
          canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
        }
      }
    }
    if (visual.chart.showLegend &&
        visual.isChart &&
        visual.kind != OfficeVisualKind.chartPie) {
      var x = rect.left + 10;
      final double y = rect.bottom - 16;
      for (final ChartPoint p in visual.points.take(6)) {
        canvas.drawRect(
          Rect.fromLTWH(x, y + 3, 8, 8),
          Paint()..color = _hex(p.color),
        );
        _label(
          canvas,
          Rect.fromLTWH(x + 10, y, 36, 14),
          p.label,
          fontSize: 8,
          fontFamily: fontFamily,
          align: TextAlign.left,
        );
        x += 48;
      }
    }
  }

  /// Plot area inside the frame: title strip on top, category labels below,
  /// plus a legend strip when an axis chart shows its bottom legend.
  static Rect _plot(Rect rect, OfficeVisual visual) {
    final bool legend =
        visual.isChart &&
        visual.chart.showLegend &&
        visual.kind != OfficeVisualKind.chartPie;
    return Rect.fromLTWH(
      rect.left + 10,
      rect.top + 24,
      rect.width - 20,
      rect.height - (legend ? 56 : 40),
    );
  }

  static void _label(
    Canvas canvas,
    Rect rect,
    String text, {
    double fontSize = 11,
    String? fontFamily,
    Color color = const Color(0xFF222222),
    TextAlign align = TextAlign.center,
    bool bold = false,
  }) {
    if (text.isEmpty || rect.width <= 2) {
      return;
    }
    final bool rtl = PaintRunText.looksRtl(text);
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          fontFamily: fontFamily ?? PaintRunText.fontFallbacks.first,
          fontFamilyFallback: PaintRunText.fontFallbacks,
        ),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width);
    painter.paint(
      canvas,
      Offset(
        align == TextAlign.left
            ? rect.left
            : rect.left + (rect.width - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }

  static Color _hex(String hex) {
    final String clean = hex.replaceFirst('#', '');
    return Color(
      0xFF000000 | (int.tryParse(clean.padLeft(6, '0'), radix: 16) ?? 0x4472C4),
    );
  }
}
