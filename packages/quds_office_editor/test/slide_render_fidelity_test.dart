import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundaryKey = ValueKey<String>('slide-fidelity-raster');

PmlShape _shape({PmlTextAnchor anchor = PmlTextAnchor.top}) => PmlShape(
  id: 2,
  name: 'Text',
  text: 'Alpha\nBeta\nGamma',
  fillColor: '',
  textColor: 'FF0000',
  fontSizePt: 20,
  rightToLeft: false,
  textAnchor: anchor,
  transform: const PmlTransform(
    x: 30 * 12700,
    y: 40 * 12700,
    cx: 300 * 12700,
    cy: 180 * 12700,
  ),
);

Future<void> _mount(
  WidgetTester tester,
  PmlShape shape, {
  void Function(int index, {bool extend})? onPlaceCaret,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _boundaryKey,
          child: SizedBox(
            width: 768,
            height: 453,
            child: SlideStage(
              slide: PmlSlide(id: 256, shapes: <PmlShape>[shape]),
              selected: shape,
              editing: true,
              onPlaceCaret: onPlaceCaret,
              config: const OfficeSurfaceConfig(showSlideHandles: false),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<Rect?> _inkBounds(WidgetTester tester, int rgb) async {
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byKey(_boundaryKey),
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
          final int index = (y * image.width + x) * 4;
          if ((pixels[index] - ((rgb >> 16) & 255)).abs() <= 2 &&
              (pixels[index + 1] - ((rgb >> 8) & 255)).abs() <= 2 &&
              (pixels[index + 2] - (rgb & 255)).abs() <= 2) {
            left = left == null || x < left ? x : left;
            top = top == null || y < top ? y : top;
            if (x > right) right = x;
            if (y > bottom) bottom = y;
          }
        }
      }
      return left == null || top == null
          ? null
          : Rect.fromLTRB(
              left.toDouble(),
              top.toDouble(),
              right.toDouble() + 1,
              bottom.toDouble() + 1,
            );
    } finally {
      image.dispose();
    }
  });
}

void _captureRichRuns(PmlShape shape) {
  shape.textSource = PmlTextSource(
    xml: '',
    text: shape.text,
    fontSizePt: shape.fontSizePt,
    textColor: shape.textColor,
    textAlign: shape.textAlign,
    rightToLeft: shape.rightToLeft,
  );
  shape.richText = <PmlTextParagraph>[
    for (final String line in shape.text.split('\n'))
      PmlTextParagraph(
        runs: <PmlTextRun>[
          PmlTextRun(
            text: line,
            fontSizePt: shape.fontSizePt,
            color: shape.textColor,
          ),
        ],
      ),
  ];
}

void main() {
  for (final PmlTextAnchor anchor in <PmlTextAnchor>[
    PmlTextAnchor.center,
    PmlTextAnchor.bottom,
  ]) {
    testWidgets('clicking the first painted $anchor line selects that line', (
      WidgetTester tester,
    ) async {
      final PmlShape shape = _shape(anchor: anchor);
      int? caret;
      await _mount(
        tester,
        shape,
        onPlaceCaret: (int index, {bool extend = false}) => caret = index,
      );
      final Rect ink = (await _inkBounds(tester, 0xFF0000))!;
      await tester.tapAt(ink.topLeft + const Offset(1, 1));
      expect(caret, isNotNull);
      expect(caret, lessThanOrEqualTo(1));
    });
  }

  testWidgets('edited scalar size and ink replace stale imported rendering', (
    WidgetTester tester,
  ) async {
    final PmlShape shape = _shape()..text = 'Alpha';
    _captureRichRuns(shape);
    await _mount(tester, shape);
    final Rect before = (await _inkBounds(tester, 0xFF0000))!;
    shape.fontSizePt = 32;
    await _mount(tester, shape);
    final Rect resized = (await _inkBounds(tester, 0xFF0000))!;
    expect(resized.width, greaterThan(before.width * 1.3));
    shape.fontSizePt = 20;
    shape.textColor = '0000FF';
    await _mount(tester, shape);
    expect(await _inkBounds(tester, 0x0000FF), isNotNull);
    expect(await _inkBounds(tester, 0xFF0000), isNull);
  });

  testWidgets('rich runs without explicit size or ink inherit shape values', (
    WidgetTester tester,
  ) async {
    final PmlShape shape = _shape()
      ..text = 'Alpha'
      ..fontSizePt = 32
      ..textColor = '0000FF';
    _captureRichRuns(shape);
    shape.richText.single.runs.single
      ..fontSizePt = 0
      ..color = '';
    await _mount(tester, shape);
    final Rect rich = (await _inkBounds(tester, 0x0000FF))!;
    shape.richText.clear();
    await _mount(tester, shape);
    final Rect plain = (await _inkBounds(tester, 0x0000FF))!;
    expect(rich.width, closeTo(plain.width, 1));
    expect(rich.height, closeTo(plain.height, 1));
  });
}
