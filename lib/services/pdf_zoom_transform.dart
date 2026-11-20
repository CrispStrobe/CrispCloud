import 'package:flutter/widgets.dart';

/// Preserve the document point under the viewport centre when zoom changes.
Matrix4 pdfZoomTransform(
  Matrix4 current,
  Size viewport,
  double scale, {
  Offset? sceneCenter,
}) {
  final center = viewport.center(Offset.zero);
  final focal =
      sceneCenter ??
      MatrixUtils.transformPoint(Matrix4.inverted(current), center);
  final next = scale.clamp(.25, 16.0);
  return Matrix4.identity()
    ..setTranslationRaw(
      center.dx - focal.dx * next,
      center.dy - focal.dy * next,
      0,
    )
    ..scaleByDouble(next, next, next, 1);
}
