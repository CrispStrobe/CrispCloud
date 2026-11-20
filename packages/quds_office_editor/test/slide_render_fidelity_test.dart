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
  List<PmlShape> backgroundShapes = const <PmlShape>[],
  Map<int, PmlAnimSample>? animSamples,
  bool presenting = false,
  OfficeTheme theme = OfficeTheme.light,
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
              slide: PmlSlide(
                id: 256,
                shapes: <PmlShape>[shape],
                backgroundShapes: backgroundShapes,
              ),
              selected: shape,
              editing: !presenting,
              presenting: presenting,
              animSamples: animSamples,
              onPlaceCaret: onPlaceCaret,
              config: OfficeSurfaceConfig(
                theme: theme,
                showSlideHandles: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _present(
  WidgetTester tester,
  PmlSlide slide, {
  Map<int, PmlAnimSample>? samples,
  PmlSlide? outgoing,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _boundaryKey,
          child: SizedBox(
            width: 720,
            height: 405,
            child: SlideStage(
              slide: slide,
              presenting: true,
              animSamples: samples,
              outgoingSlide: outgoing,
              transitionProgress: outgoing == null ? 1 : 0.5,
              playingTransition: outgoing == null
                  ? null
                  : const PmlSlideTransition(kind: PmlTransitionKind.morph),
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

PmlSlide _decoratedSlide() => PmlSlide(
  id: 256,
  backgroundShapes: <PmlShape>[
    PmlShape(
      id: 2,
      name: 'Master decoration',
      fillColor: 'FF0000',
      transform: const PmlTransform(
        x: 30 * 12700,
        y: 40 * 12700,
        cx: 60 * 12700,
        cy: 40 * 12700,
      ),
    ),
  ],
  shapes: <PmlShape>[
    PmlShape(
      id: 2,
      name: 'Slide content',
      fillColor: '0000FF',
      transform: const PmlTransform(
        x: 180 * 12700,
        y: 40 * 12700,
        cx: 60 * 12700,
        cy: 40 * 12700,
      ),
    ),
  ],
);

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
  testWidgets('autofit scales all rich lines and their paragraph terminators', (
    tester,
  ) async {
    final PmlShape shape = _shape()
      ..text = 'Alpha\nBeta\nGamma'
      ..richText = [
        for (final word in ['Alpha', 'Beta', 'Gamma'])
          PmlTextParagraph(runs: [PmlTextRun(text: word, fontSizePt: 20)]),
      ];
    await _mount(tester, shape);
    final Rect before = (await _inkBounds(tester, 0xFF0000))!;
    final PmlShape fitted = shape.copy()..textScale = 0.5;
    await _mount(tester, fitted);
    final Rect after = (await _inkBounds(tester, 0xFF0000))!;
    expect(after.width, lessThan(before.width * 0.7));
    expect(after.height, lessThan(before.height * 0.7));
  });

  testWidgets('autofit spacing reduction reaches plain and rich rendering', (
    tester,
  ) async {
    for (final bool rich in [false, true]) {
      final PmlShape shape = _shape();
      if (rich) {
        shape.richText = [
          for (final word in ['Alpha', 'Beta', 'Gamma'])
            PmlTextParagraph(runs: [PmlTextRun(text: word, fontSizePt: 20)]),
        ];
      }
      await _mount(tester, shape);
      final Rect before = (await _inkBounds(tester, 0xFF0000))!;
      await _mount(tester, shape.copy()..lineSpacingReduction = 0.3);
      final Rect after = (await _inkBounds(tester, 0xFF0000))!;
      expect(after.height, lessThan(before.height - 5), reason: 'rich=$rich');
      expect(after.width, before.width);
    }
  });

  testWidgets('autofit keeps every fitted line in a small frame', (
    tester,
  ) async {
    final PmlShape shape = _shape()
      ..text = 'Alpha\nBeta\nGamma\nDelta'
      ..fontSizePt = 40
      ..textScale = 0.25
      ..transform = const PmlTransform(
        x: 30 * 12700,
        y: 40 * 12700,
        cx: 300 * 12700,
        cy: 80 * 12700,
      )
      ..richText = [
        for (final word in ['Alpha', 'Beta', 'Gamma', 'Delta'])
          PmlTextParagraph(
            runs: [
              PmlTextRun(
                text: word,
                fontSizePt: 40,
                color: word == 'Delta' ? '0000FF' : 'FF0000',
              ),
            ],
          ),
      ];
    await _mount(tester, shape);
    expect(await _inkBounds(tester, 0x0000FF), isNotNull);
  });

  testWidgets('fixed rich leading is unchanged by autofit spacing reduction', (
    tester,
  ) async {
    final PmlShape shape = _shape()
      ..richText = [
        for (final word in ['Alpha', 'Beta', 'Gamma'])
          PmlTextParagraph(
            lineSpacingPt: 30,
            runs: [PmlTextRun(text: word, fontSizePt: 20)],
          ),
      ];
    await _mount(tester, shape);
    final Rect before = (await _inkBounds(tester, 0xFF0000))!;
    await _mount(tester, shape.copy()..lineSpacingReduction = 0.5);
    expect(await _inkBounds(tester, 0xFF0000), before);
  });

  testWidgets(
    'slide animation cannot hide an inherited decoration with the same id',
    (WidgetTester tester) async {
      final PmlSlide slide = _decoratedSlide();
      await _present(tester, slide);
      final Rect decoration = (await _inkBounds(tester, 0xFF0000))!;
      expect(await _inkBounds(tester, 0x0000FF), isNotNull);

      await _present(
        tester,
        slide,
        samples: <int, PmlAnimSample>{2: PmlAnimSample.hidden},
      );
      expect(await _inkBounds(tester, 0x0000FF), isNull);
      expect(await _inkBounds(tester, 0xFF0000), decoration);
    },
  );

  testWidgets('morph keeps inherited decorations when content ids match', (
    WidgetTester tester,
  ) async {
    final PmlSlide outgoing = _decoratedSlide();
    final PmlSlide incoming = outgoing.copy(id: 257);
    await _present(tester, outgoing);
    final Rect decoration = (await _inkBounds(tester, 0xFF0000))!;

    await _present(tester, incoming, outgoing: outgoing);
    expect(await _inkBounds(tester, 0xFF0000), decoration);
    expect(await _inkBounds(tester, 0x0000FF), isNotNull);
  });

  testWidgets('inherited decorations retain their authored rotation', (
    WidgetTester tester,
  ) async {
    final PmlSlide slide = _decoratedSlide();
    final PmlTransform original = slide.backgroundShapes.single.transform;
    slide.backgroundShapes.single.transform = PmlTransform(
      x: original.x,
      y: original.y,
      cx: original.cx,
      cy: original.cy,
      rot: 90 * 60000,
    );
    await _present(tester, slide);
    final Rect decoration = (await _inkBounds(tester, 0xFF0000))!;
    expect(decoration.width, closeTo(40, 1));
    expect(decoration.height, closeTo(60, 1));
  });

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
  testWidgets('master decoration IDs do not inherit slide animation samples', (
    WidgetTester tester,
  ) async {
    final PmlShape content = _shape()..text = 'Hidden slide content';
    final PmlShape decoration = PmlShape(
      id: content.id,
      name: 'Master decoration',
      fillColor: '00FF00',
      transform: const PmlTransform(cx: 100 * 12700, cy: 100 * 12700),
    );
    await _mount(
      tester,
      content,
      backgroundShapes: <PmlShape>[decoration],
      presenting: true,
      animSamples: <int, PmlAnimSample>{content.id: PmlAnimSample.hidden},
    );
    expect(await _inkBounds(tester, 0x00FF00), isNotNull);
    expect(await _inkBounds(tester, 0xFF0000), isNull);
  });

  testWidgets('dark slide text uses the decoration painted behind it', (
    WidgetTester tester,
  ) async {
    final PmlShape content = _shape()
      ..text = 'Readable ink'
      ..textColor = '000000';
    final PmlShape decoration = PmlShape(
      id: content.id,
      name: 'White layout background',
      fillColor: 'FFFFFF',
      transform: const PmlTransform(cx: 720 * 12700, cy: 405 * 12700),
    );
    await _mount(
      tester,
      content,
      backgroundShapes: <PmlShape>[decoration],
      theme: OfficeTheme.dark,
    );
    expect(await _inkBounds(tester, 0x000000), isNotNull);
    expect(content.textColor, '000000');
  });
}
