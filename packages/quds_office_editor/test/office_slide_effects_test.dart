import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundary = ValueKey('slide-gradient-effects');

PmlGradientFill _gradient({double angle = 0}) => PmlGradientFill(
  stops: [
    PmlGradientStop(position: 0, color: 'FF0000'),
    PmlGradientStop(position: .5, color: '00FF00'),
    PmlGradientStop(position: 1, color: '0000FF'),
  ],
  angleDegrees: angle,
);

PmlShape _shape({
  double angle = 0,
  PmlShapePreset preset = PmlShapePreset.rect,
}) => PmlShape(
  id: 2,
  name: 'Gradient',
  fillColor: 'FF0000',
  gradient: _gradient(angle: angle),
  preset: preset,
  transform: const PmlTransform(
    x: 20 * 12700,
    y: 30 * 12700,
    cx: 200 * 12700,
    cy: 80 * 12700,
  ),
);

Future<Uint8List> _paint(WidgetTester tester, PmlPresentation deck) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _boundary,
          child: SizedBox(
            width: 720,
            height: 405,
            child: SlideStage(
              slide: deck.slides.single,
              master: deck.master,
              preview: true,
              config: const OfficeSurfaceConfig(
                theme: OfficeTheme.light,
                mode: OfficeInteractionMode.viewing,
                showSlideHandles: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byKey(_boundary),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}

(int, int, int) _pixel(Uint8List bytes, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return (bytes[offset], bytes[offset + 1], bytes[offset + 2]);
}

Future<Uint8List> _picturePixels(
  WidgetTester tester, {
  double transparency = 0,
  double brightness = 0,
  bool shadow = false,
}) async {
  final imageRecorder = ui.PictureRecorder();
  Canvas(imageRecorder).drawRect(
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..color = const Color(0xFFFF0000),
  );
  final picture = imageRecorder.endRecording();
  final source = picture.toImageSync(1, 1);
  picture.dispose();
  final bytes = Uint8List.fromList([1]);
  final images = VisualImageCache(
    decodeImage: (bytes, onDecoded) => onDecoded(source),
  );
  images.load(bytes, () {});
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 64, 64),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  PaintOfficeVisual.paint(
    canvas,
    const Rect.fromLTWH(10, 10, 20, 20),
    OfficeVisual(
      kind: OfficeVisualKind.picture,
      imageBytes: bytes,
      picture: PictureAdjust(
        transparency: transparency,
        brightness: brightness,
        shadow: shadow,
      ),
    ),
    fontFamily: 'Arial',
    images: images,
  );
  final rendered = recorder.endRecording();
  try {
    return (await tester.runAsync(() async {
      final image = await rendered.toImage(64, 64);
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
  } finally {
    rendered.dispose();
    images.dispose();
  }
}

void main() {
  for (final angle in [0.0, 90.0]) {
    testWidgets('wide gradient reaches its endpoints at $angle degrees', (
      tester,
    ) async {
      final pixels = await _paint(
        tester,
        PmlPresentation(
          slides: [
            PmlSlide(id: 256, shapes: [_shape(angle: angle)]),
          ],
        ),
      );
      final start = angle == 0
          ? _pixel(pixels, 720, 22, 70)
          : _pixel(pixels, 720, 120, 32);
      final middle = _pixel(pixels, 720, 120, 70);
      final end = angle == 0
          ? _pixel(pixels, 720, 217, 70)
          : _pixel(pixels, 720, 120, 107);
      expect(start.$1, greaterThan(235));
      expect(start.$3, 0);
      expect(middle.$2, greaterThan(245));
      expect(end.$1, 0);
      expect(end.$3, greaterThan(235));
    });
  }

  testWidgets('homePlate gradient keeps its flat back and clipped tip', (
    tester,
  ) async {
    final pixels = await _paint(
      tester,
      PmlPresentation(
        slides: [
          PmlSlide(id: 256, shapes: [_shape(preset: PmlShapePreset.homePlate)]),
        ],
      ),
    );
    expect(_pixel(pixels, 720, 22, 32).$1, greaterThan(240));
    expect(_pixel(pixels, 720, 210, 40), (255, 255, 255));
    expect(_pixel(pixels, 720, 210, 70).$3, greaterThan(220));
    expect(_pixel(pixels, 720, 230, 70), (255, 255, 255));
  });

  for (final inherited in [true, false]) {
    testWidgets(
      'direct master edit respects gradient ownership inherited=$inherited',
      (tester) async {
        final deck = PmlPresentation(
          master: PmlMaster(name: 'Imported')..setImportedBackground('FFFFFF'),
          slides: [
            PmlSlide(
              id: 256,
              background: 'FFFFFF',
              inheritsMasterBackground: inherited,
              backgroundShapes: [
                PmlShape(
                  id: 1,
                  name: 'Selected gradient',
                  isBackgroundGradient: true,
                  fillColor: 'FF0000',
                  gradient: _gradient(),
                  transform: const PmlTransform(cx: 9144000, cy: 5143500),
                ),
                PmlShape(
                  id: 2,
                  name: 'Ordinary decoration',
                  fillColor: '0000FF',
                  transform: const PmlTransform(
                    x: 20 * 12700,
                    y: 20 * 12700,
                    cx: 40 * 12700,
                    cy: 40 * 12700,
                  ),
                ),
              ],
            ),
          ],
        );
        final before = await _paint(tester, deck);
        expect(_pixel(before, 720, 100, 100), isNot((255, 255, 255)));
        deck.master.background = '112233';
        final after = await _paint(tester, deck);
        expect(
          _pixel(after, 720, 100, 100),
          inherited ? (17, 34, 51) : _pixel(before, 720, 100, 100),
        );
        expect(_pixel(after, 720, 30, 30), (0, 0, 255));
        expect(deck.slides.single.backgroundShapes, hasLength(2));
      },
    );
  }

  for (final brightness in [0.0, -.2]) {
    testWidgets('picture opacity applies once with brightness $brightness', (
      tester,
    ) async {
      final pixels = await _picturePixels(
        tester,
        transparency: .5,
        brightness: brightness,
      );
      final center = _pixel(pixels, 64, 20, 20);
      expect(center.$1, closeTo(brightness == 0 ? 255 : 230, 2));
      expect(center.$2, closeTo(128, 2));
      expect(center.$3, closeTo(128, 2));
      expect(_pixel(pixels, 64, 40, 40), (255, 255, 255));
    });
  }

  testWidgets('full picture transparency leaves the background visible', (
    tester,
  ) async {
    final pixels = await _picturePixels(tester, transparency: 1);
    expect(_pixel(pixels, 64, 20, 20), (255, 255, 255));
  });

  testWidgets(
    'picture shadow has one soft footprint without a second hard rectangle',
    (tester) async {
      final pixels = await _picturePixels(tester, shadow: true);
      expect(_pixel(pixels, 64, 20, 20), (255, 0, 0));
      final edge = _pixel(pixels, 64, 31, 25);
      // One 1/3-opacity blurred shadow is light at this exterior edge. The
      // previous additional 40%-opacity hard rectangle made this much darker.
      expect(edge.$1, inInclusiveRange(180, 245));
      expect(edge.$2, edge.$1);
      expect(edge.$3, edge.$1);
      expect(_pixel(pixels, 64, 60, 60), (255, 255, 255));
    },
  );
}
