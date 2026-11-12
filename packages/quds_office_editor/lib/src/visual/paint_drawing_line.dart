import 'dart:math' as math;
import 'dart:ui';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Paints the supported native geometry of a rectangular DrawingML outline.
abstract final class PaintDrawingLine {
  static void rectangle(
    Canvas canvas,
    Rect rect,
    Color color,
    DrawingLineStyle style,
  ) {
    final width = style.widthPoints.isFinite && style.widthPoints >= 0
        ? style.widthPoints
        : 1.0;
    final inset = math.min(width, math.min(rect.width, rect.height)) / 2;
    final path = Path()..addRect(style.inset ? rect.deflate(inset) : rect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = switch (style.cap) {
        DrawingLineCap.flat => StrokeCap.butt,
        DrawingLineCap.round => StrokeCap.round,
        DrawingLineCap.square => StrokeCap.square,
      }
      ..strokeJoin = switch (style.join) {
        DrawingLineJoin.miter => StrokeJoin.miter,
        DrawingLineJoin.round => StrokeJoin.round,
        DrawingLineJoin.bevel => StrokeJoin.bevel,
      }
      ..strokeMiterLimit = style.miterLimit.isFinite && style.miterLimit >= 0
          ? style.miterLimit
          : 4;
    if (style.dashLengths.isEmpty ||
        style.dashLengths.length.isOdd ||
        style.dashLengths.any((value) => !value.isFinite || value < 0)) {
      canvas.drawPath(path, paint);
      return;
    }
    // A zero native width is a device hairline, not a zero-length dash cycle.
    final unit = width == 0 ? 1.0 : width;
    final pattern = style.dashLengths.map((value) => value * unit).toList();
    final period = pattern.fold<double>(0, (sum, value) => sum + value);
    for (final metric in path.computeMetrics()) {
      // Subpixel/untrusted dash periods must not create an unbounded paint
      // loop. Such extreme patterns use the existing solid approximation.
      if (!period.isFinite ||
          period <= 0 ||
          metric.length / period * pattern.length > 20000) {
        canvas.drawPath(path, paint);
        return;
      }
      var distance = 0.0;
      var index = 0;
      while (distance < metric.length) {
        final dash = pattern[index];
        final space = pattern[index + 1];
        final end = math.min(distance + dash, metric.length);
        final capInset =
            style.capsIncludedInDash && style.cap != DrawingLineCap.flat
            ? math.min(unit / 2, dash / 2)
            : 0.0;
        final start = math.min(distance + capInset, end);
        final stop = math.max(start, end - capInset);
        if (stop > start) {
          canvas.drawPath(metric.extractPath(start, stop), paint);
        } else if (style.cap != DrawingLineCap.flat) {
          final tangent = metric.getTangentForOffset(start);
          if (tangent != null) {
            canvas.drawPoints(PointMode.points, [tangent.position], paint);
          }
        }
        distance += dash + space;
        index = (index + 2) % pattern.length;
      }
    }
  }
}
