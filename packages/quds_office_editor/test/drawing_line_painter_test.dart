import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/visual/paint_drawing_line.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

void main() {
  for (final pattern in <List<double>>[
    [1],
    [double.nan, 1],
    [-1, 2],
    [0, 0],
    [1e-100, 1e-100],
    [0, 0, 1, 1],
  ]) {
    test('invalid or extreme dash pattern remains bounded: $pattern', () {
      final recorder = PictureRecorder();
      PaintDrawingLine.rectangle(
        Canvas(recorder),
        const Rect.fromLTWH(20, 20, 120, 80),
        const Color(0xff355c7d),
        DrawingLineStyle(widthPoints: 3, dashLengths: pattern),
      );
      final picture = recorder.endRecording();
      expect(picture.approximateBytesUsed, lessThan(1000000));
      picture.dispose();
    });
  }

  test(
    'nonfinite public width and miter values cannot break frame painting',
    () {
      final recorder = PictureRecorder();
      PaintDrawingLine.rectangle(
        Canvas(recorder),
        const Rect.fromLTWH(20, 20, 120, 80),
        const Color(0xff355c7d),
        const DrawingLineStyle(
          widthPoints: double.nan,
          miterLimit: double.infinity,
        ),
      );
      recorder.endRecording().dispose();
    },
  );
}
