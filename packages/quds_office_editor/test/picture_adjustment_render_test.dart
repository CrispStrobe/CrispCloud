import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/visual/paint_office_visual.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

Future<Uint8List> _paint(PictureAdjust adjustment) async {
  final ui.PictureRecorder sourceRecorder = ui.PictureRecorder();
  ui.Canvas(sourceRecorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 2, 2),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  final ui.Picture sourcePicture = sourceRecorder.endRecording();
  final ui.Image source = sourcePicture.toImageSync(2, 2);
  sourcePicture.dispose();
  final Uint8List bytes = Uint8List.fromList([1]);
  final VisualImageCache cache = VisualImageCache(
    decodeImage: (_, onDecoded) => onDecoded(source),
  )..load(bytes, () {});
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
  PaintOfficeVisual.paint(
    canvas,
    const ui.Rect.fromLTWH(10, 10, 20, 20),
    OfficeVisual(
      kind: OfficeVisualKind.picture,
      imageBytes: bytes,
      picture: adjustment,
    ),
    fontFamily: 'Arial',
    images: cache,
  );
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = picture.toImageSync(40, 40);
  try {
    final ByteData pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    return Uint8List.fromList(pixels.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
    cache.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final double brightness in [0.0, 0.1]) {
    test(
      'picture opacity is applied once with brightness $brightness',
      () async {
        final Uint8List pixels = await _paint(
          PictureAdjust(transparency: 0.5, brightness: brightness),
        );
        final int middle = (20 * 40 + 20) * 4;
        expect(pixels[middle], greaterThan(245));
        final double expected = brightness == 0 ? 128 : 140;
        expect(pixels[middle + 1], closeTo(expected, 4));
        expect(pixels[middle + 2], closeTo(expected, 4));
        expect(pixels[middle + 3], 255);
      },
    );
  }

  test(
    'picture has one soft shadow instead of stacked hard and soft shadows',
    () async {
      final Uint8List pixels = await _paint(PictureAdjust(shadow: true));
      final int nearEdge = (31 * 40 + 31) * 4;
      // One blurred 0x55 shadow remains light at this corner. The old hard
      // shadow plus the added blur made the same corner substantially darker.
      expect(pixels[nearEdge], greaterThan(210));
      expect(pixels[nearEdge], lessThan(253));
      expect(pixels[nearEdge + 1], pixels[nearEdge]);
      expect(pixels[nearEdge + 2], pixels[nearEdge]);
    },
  );
}
