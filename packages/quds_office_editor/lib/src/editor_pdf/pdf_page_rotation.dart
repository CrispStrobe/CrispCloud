import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Turns the canvas so `/Rotate` is a real clockwise quarter-turn.
///
/// Call after scaling into the view box (`page.width` × `page.height`).
/// Content and annotations are then painted in unrotated crop space.
void applyPdfPageRotation(Canvas canvas, PdfPageInfo page) {
  final double w = page.cropBox.width;
  final double h = page.cropBox.height;
  switch (PdfPageView.normalizeQuarter(page.rotate)) {
    case 90:
      canvas.translate(h, 0);
      canvas.rotate(math.pi / 2);
    case 180:
      canvas.translate(w, h);
      canvas.rotate(math.pi);
    case 270:
      canvas.translate(0, w);
      canvas.rotate(-math.pi / 2);
    default:
      break;
  }
}
