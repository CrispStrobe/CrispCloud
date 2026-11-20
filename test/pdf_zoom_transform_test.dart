import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/pdf_zoom_transform.dart';

void main() {
  test('zoom preserves the visible scene point even far down a document', () {
    final current = Matrix4.identity()
      ..setTranslationRaw(-70, -3500, 0)
      ..scaleByDouble(1.3, 1.3, 1, 1);
    const viewport = Size(900, 650);
    final center = viewport.center(Offset.zero);
    final point = MatrixUtils.transformPoint(Matrix4.inverted(current), center);
    final next = pdfZoomTransform(current, viewport, 3.2);
    final actual = MatrixUtils.transformPoint(next, point);
    expect(actual.dx, closeTo(center.dx, .0001));
    expect(actual.dy, closeTo(center.dy, .0001));
  });
  test('zoom limits and fit preserve a chosen page centre', () {
    final next = pdfZoomTransform(
      Matrix4.identity(),
      const Size(800, 600),
      100,
      sceneCenter: const Offset(300, 5000),
    );
    expect(next.getMaxScaleOnAxis(), 16);
    expect(
      MatrixUtils.transformPoint(next, const Offset(300, 5000)),
      const Offset(400, 300),
    );
    expect(
      pdfZoomTransform(next, const Size(800, 600), .01).getMaxScaleOnAxis(),
      .25,
    );
  });
}
