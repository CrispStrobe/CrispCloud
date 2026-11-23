import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/visual/paint_office_visual.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

Future<Uint8List> _paint(
  PictureAdjust adjustment, {
  bool thinLines = false,
  bool transparentCorners = false,
}) async {
  final ui.PictureRecorder sourceRecorder = ui.PictureRecorder();
  final ui.Canvas sourceCanvas = ui.Canvas(sourceRecorder);
  final int size = thinLines ? 320 : (transparentCorners ? 32 : 2);
  if (thinLines) {
    sourceCanvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    for (var x = 0; x < size; x += 16) {
      sourceCanvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), 0, 1, size.toDouble()),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
    }
  } else if (transparentCorners) {
    sourceCanvas.drawOval(
      const ui.Rect.fromLTWH(2, 2, 28, 28),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    );
  } else {
    sourceCanvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 2, 2),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    );
  }
  final ui.Picture sourcePicture = sourceRecorder.endRecording();
  final ui.Image source = sourcePicture.toImageSync(size, size);
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

  test('strong picture minification retains thin raster lines', () async {
    final pixels = await _paint(PictureAdjust(), thinLines: true);
    final middle = (20 * 40 + 20) * 4;
    expect(pixels[middle], closeTo(239, 6));
    expect(pixels[middle + 1], pixels[middle]);
    expect(pixels[middle + 2], pixels[middle]);
  });

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

  test(
    'transparent corners cast no shadow and the tint follows the alpha',
    () async {
      final pixels = await _paint(
        PictureAdjust(
          shadow: true,
          outerShadow: const PictureOuterShadow(
            blurRadius: 2,
            distance: 7,
            color: '0000FF',
            opacity: 0.5,
          ),
        ),
        transparentCorners: true,
      );
      List<int> at(int x, int y) {
        final offset = (y * 40 + x) * 4;
        return pixels.sublist(offset, offset + 3);
      }

      expect(at(35, 11), [255, 255, 255]);
      expect(at(32, 20)[0], lessThan(200));
      expect(at(32, 20)[1], at(32, 20)[0]);
      expect(at(32, 20)[2], 255);
      expect(at(20, 20), [255, 0, 0]);
    },
  );
}
