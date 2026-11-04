import 'dart:math' as math;
import 'dart:typed_data';

import '../builders/office_markup.dart';
import '../visual/office_visual.dart';
import 'pdf_canvas.dart';
import 'pdf_document.dart';
import 'pdf_image.dart';

/// Paints [OfficeVisual] charts, diagrams, and pictures onto a PDF page.
abstract final class OfficePdfVisuals {
  /// paint API.
  static void paint(
    PdfCanvas canvas,
    double x,
    double y,
    double width,
    double height,
    OfficeVisual visual,
    List<PdfEmbeddedImage> images, {
    required void Function(
      String text,
      double x,
      double y,
      double size,
      String color,
    )
    drawText,
    String Function()? nextImageName,
  }) {
    switch (visual.kind) {
      case OfficeVisualKind.picture:
        _picture(
          canvas,
          x,
          y,
          width,
          height,
          visual,
          images,
          drawText,
          nextImageName,
        );
      case OfficeVisualKind.chartColumn:
        _column(canvas, x, y, width, height, visual, drawText);
      case OfficeVisualKind.chartBar:
        _bar(canvas, x, y, width, height, visual, drawText);
      case OfficeVisualKind.chartPie:
        _pie(canvas, x, y, width, height, visual, drawText);
      case OfficeVisualKind.chartLine:
        _line(canvas, x, y, width, height, visual, drawText);
      case OfficeVisualKind.diagramProcess:
        _process(canvas, x, y, width, height, visual, drawText);
      case OfficeVisualKind.diagramCycle:
        _cycle(canvas, x, y, width, height, visual, drawText);
      case OfficeVisualKind.diagramHierarchy:
        _hierarchy(canvas, x, y, width, height, visual, drawText);
    }
  }

  static void _frame(
    PdfCanvas canvas,
    double x,
    double y,
    double w,
    double h,
    OfficeVisual visual,
    void Function(String, double, double, double, String) drawText,
  ) {
    canvas.fillRect(x, y, w, h, 'FFFFFF');
    canvas.strokeRect(x, y, w, h, '8FAADC');
    if (visual.title.isNotEmpty) {
      drawText(visual.title, x + 6, y + 14, 10, '1F4E79');
    }
  }

  static ({double x, double y, double w, double h}) _plot(
    double x,
    double y,
    double w,
    double h,
  ) {
    return (x: x + 10, y: y + 22, w: w - 20, h: h - 40);
  }

  static void _picture(
    PdfCanvas canvas,
    double x,
    double y,
    double w,
    double h,
    OfficeVisual visual,
    List<PdfEmbeddedImage> images,
    void Function(String, double, double, double, String) drawText,
    String Function()? nextImageName,
  ) {
    final Uint8List? bytes = visual.imageBytes;
    if (bytes == null) {
      canvas.fillRect(x, y, w, h, 'F3F6FB');
      canvas.strokeRect(x, y, w, h, '8FAADC');
      drawText(
        visual.title.isEmpty ? 'Picture' : visual.title,
        x + 8,
        y + h / 2,
        11,
        '595959',
      );
      return;
    }
    final PdfRaster? raster = PdfImageCodec.decode(bytes);
    if (raster == null) {
      canvas.fillRect(x, y, w, h, 'F3F6FB');
      canvas.strokeRect(x, y, w, h, '8FAADC');
      drawText(
        visual.title.isEmpty ? 'Picture' : visual.title,
        x + 8,
        y + h / 2,
        11,
        '595959',
      );
      return;
    }
    final String name = nextImageName?.call() ?? 'Im${images.length + 1}';
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
    canvas.drawImage(name, x, y, w, h);
  }

  static void _column(
    PdfCanvas canvas,
    double x,
    double y,
    double w,
    double h,
    OfficeVisual visual,
    void Function(String, double, double, double, String) drawText,
  ) {
    _frame(canvas, x, y, w, h, visual, drawText);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final plot = _plot(x, y, w, h);
    final double maxV = pts.fold<double>(
      1,
      (double m, ChartPoint p) => math.max(m, p.value),
    );
    const double gap = 8;
    final double barW = (plot.w - gap * (pts.length + 1)) / pts.length;
    for (int i = 0; i < pts.length; i++) {
      final double bh = plot.h * (pts[i].value / maxV);
      final double bx = plot.x + gap + i * (barW + gap);
      canvas.fillRect(bx, plot.y + plot.h - bh, barW, bh, pts[i].color);
      drawText(pts[i].label, bx, plot.y + plot.h + 10, 7, '595959');
    }
  }

  static void _bar(
    PdfCanvas canvas,
    double x,
    double y,
    double w,
    double h,
    OfficeVisual visual,
    void Function(String, double, double, double, String) drawText,
  ) {
    _frame(canvas, x, y, w, h, visual, drawText);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final plot = _plot(x, y, w, h);
    final double maxV = pts.fold<double>(
      1,
      (double m, ChartPoint p) => math.max(m, p.value),
    );
    final double gap = 6;
    final double barH = (plot.h - gap * (pts.length + 1)) / pts.length;
    for (int i = 0; i < pts.length; i++) {
      final double bw = plot.w * (pts[i].value / maxV);
      final double by = plot.y + gap + i * (barH + gap);
      canvas.fillRect(plot.x, by, bw, barH, pts[i].color);
      drawText(pts[i].label, plot.x + 4, by + barH * 0.7, 7, 'FFFFFF');
    }
  }

  static void _pie(
    PdfCanvas canvas,
    double x,
    double y,
    double w,
    double h,
    OfficeVisual visual,
    void Function(String, double, double, double, String) drawText,
  ) {
    _frame(canvas, x, y, w, h, visual, drawText);
    final List<ChartPoint> pts = <ChartPoint>[
      for (final ChartPoint p in visual.points)
        if (p.value.isFinite && p.value > 0) p,
    ];
    if (pts.isEmpty) {
      return;
    }
    final double cx = x + w * 0.38;
    final double cy = y + h * 0.58;
    final double r = math.min(w, h) * 0.28;
    final double sum = pts.fold<double>(
      0,
      (double a, ChartPoint p) => a + p.value,
    );
    var angle = -math.pi / 2;
    for (int i = 0; i < pts.length; i++) {
      final double sweep = 2 * math.pi * (pts[i].value / sum);
      canvas.setFillColor(pts[i].color);
      canvas.moveTo(cx, cy);
      const int steps = 16;
      for (int s = 0; s <= steps; s++) {
        final double a = angle + sweep * (s / steps);
        canvas.lineTo(cx + r * math.cos(a), cy + r * math.sin(a));
      }
      canvas.closePath();
      canvas.fill();
      angle += sweep;
    }
    var ly = y + 28;
    for (final ChartPoint p in pts) {
      canvas.fillRect(x + w * 0.68, ly - 6, 7, 7, p.color);
      drawText(p.label, x + w * 0.68 + 10, ly, 8, '333333');
      ly += 12;
    }
  }

  static void _line(
    PdfCanvas canvas,
    double x,
    double y,
    double w,
    double h,
    OfficeVisual visual,
    void Function(String, double, double, double, String) drawText,
  ) {
    _frame(canvas, x, y, w, h, visual, drawText);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final plot = _plot(x, y, w, h);
    final double maxV = pts.fold<double>(
      1,
      (double m, ChartPoint p) => math.max(m, p.value),
    );
    canvas.setStrokeColor(pts.first.color);
    canvas.setLineWidth(1.4);
    for (int i = 0; i < pts.length; i++) {
      final double px =
          plot.x +
          (pts.length == 1 ? plot.w / 2 : i * (plot.w / (pts.length - 1)));
      final double py = plot.y + plot.h - (pts[i].value / maxV) * plot.h;
      if (i == 0) {
        canvas.moveTo(px, py);
      } else {
        canvas.lineTo(px, py);
      }
    }
    canvas.stroke();
  }

  static void _process(
    PdfCanvas canvas,
    double x,
    double y,
    double w,
    double h,
    OfficeVisual visual,
    void Function(String, double, double, double, String) drawText,
  ) {
    _frame(canvas, x, y, w, h, visual, drawText);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final double boxW = (w - 20 - (pts.length - 1) * 16) / pts.length;
    final double boxH = h - 40;
    for (int i = 0; i < pts.length; i++) {
      final double bx = x + 10 + i * (boxW + 16);
      final double by = y + 26;
      canvas.setFillColor(pts[i].color);
      canvas.roundedRect(bx, by, boxW, boxH, 4);
      canvas.fill();
      drawText(pts[i].label, bx + 6, by + boxH / 2, 8, 'FFFFFF');
      if (i < pts.length - 1) {
        canvas.setStrokeColor('8FAADC');
        canvas.setLineWidth(1);
        canvas.moveTo(bx + boxW, by + boxH / 2);
        canvas.lineTo(bx + boxW + 16, by + boxH / 2);
        canvas.stroke();
      }
    }
  }

  static void _cycle(
    PdfCanvas canvas,
    double x,
    double y,
    double w,
    double h,
    OfficeVisual visual,
    void Function(String, double, double, double, String) drawText,
  ) {
    _frame(canvas, x, y, w, h, visual, drawText);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    final double cx = x + w / 2;
    final double cy = y + h * 0.58;
    final double r = math.min(w, h) * 0.28;
    for (int i = 0; i < pts.length; i++) {
      final double a = -math.pi / 2 + i * (2 * math.pi / pts.length);
      final double px = cx + r * math.cos(a) - 28;
      final double py = cy + r * math.sin(a) - 12;
      canvas.fillRect(px, py, 56, 24, pts[i].color);
      drawText(pts[i].label, px + 4, py + 16, 7, 'FFFFFF');
    }
  }

  static void _hierarchy(
    PdfCanvas canvas,
    double x,
    double y,
    double w,
    double h,
    OfficeVisual visual,
    void Function(String, double, double, double, String) drawText,
  ) {
    _frame(canvas, x, y, w, h, visual, drawText);
    final List<ChartPoint> pts = visual.points;
    if (pts.isEmpty) {
      return;
    }
    canvas.fillRect(x + w / 2 - 40, y + 26, 80, 22, pts.first.color);
    drawText(pts.first.label, x + w / 2 - 34, y + 41, 8, 'FFFFFF');
    if (pts.length == 1) {
      return;
    }
    final double childW = (w - 24) / (pts.length - 1);
    for (int i = 1; i < pts.length; i++) {
      final double bx = x + 12 + (i - 1) * childW;
      canvas.setStrokeColor('8FAADC');
      canvas.moveTo(x + w / 2, y + 48);
      canvas.lineTo(bx + childW / 2, y + 62);
      canvas.stroke();
      canvas.fillRect(bx + 4, y + 62, childW - 8, 22, pts[i].color);
      drawText(pts[i].label, bx + 8, y + 77, 7, 'FFFFFF');
    }
  }
}
