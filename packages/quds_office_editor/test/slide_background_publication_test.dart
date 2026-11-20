import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundary = ValueKey('direct-master-background');

PmlPresentation _deck({required bool inherited, bool gradient = false}) {
  final bytes = PngBytes.rgb(
    width: 1,
    height: 1,
    plot: (x, y, rgb) {
      rgb[0] = 255;
      rgb[1] = 0;
      rgb[2] = 0;
    },
  );
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
            name: 'Background picture',
            isBackgroundPicture: true,
            visual: OfficeVisual(
              kind: OfficeVisualKind.picture,
              imageBytes: bytes,
            ),
            transform: const PmlTransform(cx: 9144000, cy: 5143500),
          ),
          PmlShape(
            id: 2,
            name: 'Layout decoration',
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
  if (gradient) {
    final slide = deck.slides.single;
    slide.backgroundShapes.removeAt(0);
    slide.retainSourceBackground(
      null,
      gradient: PmlShape(
        id: 1,
        name: 'Background gradient',
        isBackgroundGradient: true,
        fillColor: 'FF0000',
        gradient: PmlGradientFill(
          stops: [
            PmlGradientStop(position: 0, color: 'FF0000'),
            PmlGradientStop(position: 1, color: 'FF0000'),
          ],
        ),
        transform: const PmlTransform(cx: 9144000, cy: 5143500),
      ),
    );
  }
  return deck;
}

Future<List<int>> _paint(
  WidgetTester tester,
  PmlPresentation deck, {
  bool waitForPicture = false,
}) async {
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
  Future<List<int>> capture() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  var pixels = (await tester.runAsync(capture))!;
  // The platform image decoder completes outside the fake test clock. Wait
  // for the known fixture image before asserting changes to its visibility.
  for (
    var attempt = 0;
    waitForPicture && attempt < 20 && _pixel(pixels, 100, 100) != 0xFF0000;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    pixels = (await tester.runAsync(capture))!;
  }
  return pixels;
}

int _pixel(List<int> bytes, int x, int y) {
  final offset = (y * 720 + x) * 4;
  return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
}

void main() {
  for (final color in ['112233', 'FFFFFF']) {
    testWidgets(
      'direct master $color replaces inherited gradient before saving',
      (tester) async {
        for (final inherited in [true, false]) {
          final deck = _deck(inherited: inherited, gradient: true);
          final selected = deck.slides.single.backgroundGradient;
          final before = await _paint(tester, deck);
          expect(_pixel(before, 100, 100), 0xFF0000);
          deck.master.background = color;
          final after = await _paint(tester, deck);
          expect(
            _pixel(after, 100, 100),
            inherited ? int.parse(color, radix: 16) : 0xFF0000,
          );
          expect(_pixel(after, 30, 30), 0x0000FF);
          expect(deck.slides.single.backgroundGradient, same(selected));
          expect(deck.slides.single.backgroundShapes, hasLength(2));
        }
      },
    );

    testWidgets(
      'direct master $color paints before saving or controller edits',
      (tester) async {
        for (final inherited in [true, false]) {
          final deck = _deck(inherited: inherited);
          final before = await _paint(tester, deck, waitForPicture: true);
          expect(_pixel(before, 100, 100), 0xFF0000);
          deck.master.background = color;
          final after = await _paint(tester, deck);
          expect(
            _pixel(after, 100, 100),
            inherited ? int.parse(color, radix: 16) : 0xFF0000,
          );
          expect(_pixel(after, 30, 30), 0x0000FF);
          expect(deck.slides.single.backgroundShapes, hasLength(2));
          expect(deck.slides.single.background, 'FFFFFF');
        }
      },
    );
  }
}
