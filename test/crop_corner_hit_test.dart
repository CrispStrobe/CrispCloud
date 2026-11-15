import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/features/crop_rotate_editor/enums/crop_area_part.dart';
import 'package:pro_image_editor/features/crop_rotate_editor/enums/crop_mode.enum.dart';
import 'package:pro_image_editor/features/crop_rotate_editor/utils/crop_area_utils.dart';

void main() {
  const size = Size(500, 400);
  const crop = Rect.fromLTRB(70, 40, 430, 340);
  for (final zoom in [1.0, 2.0, 4.0]) {
    test('corner targets retain two-axis intent after pan and zoom $zoom', () {
      const shift = Offset(13, -19);
      CropAreaPart hit(Offset point) => determineCropAreaPart(
        localPosition:
            const Offset(250, 200) +
            (point - const Offset(250, 200)) / zoom -
            shift,
        translate: shift,
        interactiveCornerArea: 7,
        cornerHitArea: 44,
        userScaleFactor: zoom,
        cropRect: crop,
        cropMode: CropMode.rectangular,
        renderedImageSize: size,
      );
      for (final c in [
        (crop.topLeft, CropAreaPart.topLeft),
        (crop.topRight, CropAreaPart.topRight),
        (crop.bottomLeft, CropAreaPart.bottomLeft),
        (crop.bottomRight, CropAreaPart.bottomRight),
      ]) {
        expect(hit(c.$1), c.$2);
        expect(hit(c.$1 + const Offset(12, 12)), c.$2);
        expect(hit(c.$1 - const Offset(12, 12)), c.$2);
      }
      expect(hit(crop.topCenter), CropAreaPart.top);
      expect(hit(crop.centerLeft), CropAreaPart.left);
      expect(hit(crop.center), CropAreaPart.inside);
      expect(hit(const Offset(0, 0)), CropAreaPart.none);
    });
  }
}
