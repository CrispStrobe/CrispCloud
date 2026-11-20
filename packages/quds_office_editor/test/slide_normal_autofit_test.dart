import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundary = ValueKey('normal-autofit-raster');

PmlShape _shape({bool rich = false, bool blank = false, bool fixed = false}) {
  final lines = blank ? ['MMMM', '', 'MMMM'] : ['MMMM', 'MMMM'];
  return PmlShape(
    id: 2,
    name: 'Fitted text',
    text: lines.join('\n'),
    fillColor: '',
    textColor: 'FF0000',
    fontSizePt: 20,
    rightToLeft: false,
    transform: const PmlTransform(
      x: 40 * 12700,
      y: 40 * 12700,
      cx: 300 * 12700,
      cy: 220 * 12700,
    ),
    richText: !rich
        ? null
        : [
            for (final line in lines)
              PmlTextParagraph(
                lineSpacingPt: fixed ? 40 : null,
                runs: [PmlTextRun(text: line, fontSizePt: 20, color: 'FF0000')],
              ),
          ],
  );
}

Future<Rect?> _paint(WidgetTester tester, PmlShape shape) async {
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
              slide: PmlSlide(id: 256, shapes: [shape]),
              presenting: true,
              config: const OfficeSurfaceConfig(showSlideHandles: false),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byKey(_boundary),
  );
  return tester.runAsync<Rect?>(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    try {
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      int? left;
      int? top;
      var right = 0;
      var bottom = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final at = (y * image.width + x) * 4;
          if (pixels[at] < 220 || pixels[at + 1] > 30 || pixels[at + 2] > 30) {
            continue;
          }
          if (left == null || x < left) left = x;
          if (top == null || y < top) top = y;
          if (x > right) right = x;
          if (y > bottom) bottom = y;
        }
      }
      return left == null || top == null
          ? null
          : Rect.fromLTRB(
              left.toDouble(),
              top.toDouble(),
              right + 1.0,
              bottom + 1.0,
            );
    } finally {
      image.dispose();
    }
  });
}

void main() {
  for (final rich in [false, true]) {
    testWidgets(
      'autofit reduces actual ${rich ? 'rich' : 'plain'} line spacing',
      (tester) async {
        final shape = _shape(rich: rich);
        final original = (await _paint(tester, shape))!;
        shape.lineSpacingReduction = 0.4;
        final reduced = (await _paint(tester, shape))!;
        expect(reduced.height, lessThan(original.height - 4));
        expect(reduced.width, original.width);
        shape.lineSpacingReduction = 1;
        final collapsed = (await _paint(tester, shape))!;
        expect(collapsed.height, closeTo(original.height / 2, 1));
      },
    );
  }

  testWidgets(
    'autofit scales empty rich paragraphs with their surrounding text',
    (tester) async {
      final shape = _shape(rich: true, blank: true);
      final original = (await _paint(tester, shape))!;
      shape.textScale = 0.5;
      final scaled = (await _paint(tester, shape))!;
      expect(scaled.height, lessThan(original.height * 0.65));
      expect(scaled.width, lessThan(original.width * 0.65));
    },
  );

  testWidgets(
    'fixed-point paragraph spacing does not receive percentage reduction',
    (tester) async {
      final shape = _shape(rich: true, fixed: true);
      final original = (await _paint(tester, shape))!;
      shape.lineSpacingReduction = 0.6;
      expect(await _paint(tester, shape), original);
    },
  );

  testWidgets('zero font scale paints no text and retains its authored text', (
    tester,
  ) async {
    for (final rich in [false, true]) {
      final shape = _shape(rich: rich)..textScale = 0;
      expect(await _paint(tester, shape), isNull);
      expect(shape.text, 'MMMM\nMMMM');
    }
  });
}
