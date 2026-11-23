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
  testWidgets(
    'radial fills shade the center and equal radii in shapes and backgrounds',
    (tester) async {
      for (final bool background in [false, true]) {
        final shape = PmlShape(
          id: 2,
          name: 'Radial',
          fillColor: 'FF0000',
          gradient: PmlGradientFill(
            radial: true,
            stops: [
              PmlGradientStop(position: 0, color: 'FF0000'),
              PmlGradientStop(position: 0.5, color: '00FF00'),
              PmlGradientStop(position: 1, color: '0000FF'),
            ],
          ),
          transform: const PmlTransform(
            x: 40 * 12700,
            y: 40 * 12700,
            cx: 100 * 12700,
            cy: 100 * 12700,
          ),
        );
        await _present(
          tester,
          PmlSlide(
            id: 256,
            shapes: background ? [] : [shape],
            backgroundShapes: background ? [shape] : [],
          ),
        );
        final RenderRepaintBoundary boundary = tester.renderObject(
          find.byKey(_boundaryKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final pixels = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            List<int> pixel(int x, int y) => pixels.sublist(
              (y * image.width + x) * 4,
              (y * image.width + x) * 4 + 3,
            );
            expect(pixel(90, 90)[0], greaterThan(245));
            for (final offset in [
              const Offset(55, 90),
              const Offset(125, 90),
              const Offset(90, 55),
              const Offset(90, 125),
            ]) {
              final rgb = pixel(offset.dx.toInt(), offset.dy.toInt());
              expect(rgb[1], greaterThan(240));
              expect(rgb[0], lessThan(15));
              expect(rgb[2], lessThan(15));
            }
            expect(pixel(44, 44)[2], greaterThan(200));
            expect(pixel(30, 30), [255, 255, 255]);
          } finally {
            image.dispose();
          }
        });
      }
    },
  );

  testWidgets(
    'rich paragraphs keep independent alignment, spacing, and caret offsets',
    (tester) async {
      final shape = _shape()
        ..text = 'Alpha\nBeta'
        ..richText = [
          PmlTextParagraph(
            runs: [PmlTextRun(text: 'Alpha', fontSizePt: 20, color: 'FF0000')],
          ),
          PmlTextParagraph(
            align: PmlTextAlign.right,
            spaceBeforePt: 24,
            bullet: '•',
            runs: [PmlTextRun(text: 'Beta', fontSizePt: 20, color: '0000FF')],
          ),
        ];
      int? caret;
      await _mount(
        tester,
        shape,
        onPlaceCaret: (int index, {bool extend = false}) => caret = index,
      );
      final first = (await _inkBounds(tester, 0xFF0000))!;
      final second = (await _inkBounds(tester, 0x0000FF))!;
      expect(second.left - first.left, greaterThan(140));
      expect(second.top - first.bottom, greaterThan(22));
      await tester.tapAt(second.center);
      expect(caret, inInclusiveRange(6, 10));
    },
  );

  testWidgets('hanging indent preserves the wrap and continuation caret', (
    tester,
  ) async {
    const first = 'First line\n';
    const continuation = 'Continuation';
    final shape = _shape()
      ..text = '$first$continuation'
      ..transform = const PmlTransform(
        x: 30 * 12700,
        y: 40 * 12700,
        cx: 272 * 12700,
        cy: 180 * 12700,
      )
      ..richText = [
        PmlTextParagraph(
          marginLeftPt: 48,
          indentPt: -48,
          runs: [
            PmlTextRun(text: first, color: 'FF0000'),
            PmlTextRun(text: continuation, color: '0000FF'),
          ],
        ),
      ];
    int? caret;
    await _mount(
      tester,
      shape,
      onPlaceCaret: (int index, {bool extend = false}) => caret = index,
    );
    final head = (await _inkBounds(tester, 0xFF0000))!;
    final tail = (await _inkBounds(tester, 0x0000FF))!;
    expect(tail.left - head.left, closeTo(48, 6));
    expect(tail.top, greaterThanOrEqualTo(head.bottom));
    await tester.tapAt(tail.center);
    expect(caret, inInclusiveRange(first.length, shape.text.length));
  });

  testWidgets('percentage paragraph gaps use the corresponding font height', (
    tester,
  ) async {
    final shape = _shape()
      ..text = 'Small\nLarge'
      ..richText = [
        PmlTextParagraph(
          runs: [PmlTextRun(text: 'Small', fontSizePt: 16, color: 'FF0000')],
        ),
        PmlTextParagraph(
          runs: [PmlTextRun(text: 'Large', fontSizePt: 32, color: '0000FF')],
        ),
      ];
    await _mount(tester, shape);
    final baseline = (await _inkBounds(tester, 0x0000FF))!.top;
    final before = shape.copy()..richText.last.spaceBeforeLineRatio = 0.5;
    await _mount(tester, before);
    final beforeGap = (await _inkBounds(tester, 0x0000FF))!.top - baseline;
    final after = shape.copy()..richText.first.spaceAfterLineRatio = 0.5;
    await _mount(tester, after);
    final afterGap = (await _inkBounds(tester, 0x0000FF))!.top - baseline;
    expect(afterGap, greaterThan(5));
    expect(beforeGap, closeTo(2 * afterGap, 2));
  });

  testWidgets('imported vertical overflow paints beyond a finite frame', (
    tester,
  ) async {
    final shape = _shape()
      ..text = 'First\nOverflow'
      ..transform = const PmlTransform(
        x: 30 * 12700,
        y: 40 * 12700,
        cx: 300 * 12700,
        cy: 28 * 12700,
      );
    _captureRichRuns(shape);
    shape.richText.last.runs.single.color = '0000FF';
    await _mount(tester, shape, presenting: true);
    final overflow = (await _inkBounds(tester, 0x0000FF))!;
    await _mount(
      tester,
      shape.copy()..clipsTextVertically = true,
      presenting: true,
    );
    final clipped = await _inkBounds(tester, 0x0000FF);
    expect(clipped?.bottom ?? 0, lessThan(overflow.bottom));
  });

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

  testWidgets('imported normal autofit paints at the fitted whole point size', (
    tester,
  ) async {
    final imported = _shape()
      ..text = 'Autofit sample'
      ..fontSizePt = 24
      ..textScale = 0.85;
    _captureRichRuns(imported);
    await _mount(tester, imported);
    final fitted = await _inkBounds(tester, 0xFF0000);

    final reference = _shape()
      ..text = imported.text
      ..fontSizePt = 20;
    _captureRichRuns(reference);
    await _mount(tester, reference);
    expect(fitted, isNotNull);
    expect(fitted, await _inkBounds(tester, 0xFF0000));
    expect(imported.richText.single.runs.single.fontSizePt, 24);
  });

  testWidgets('percentage leading uses the fitted whole point size', (
    tester,
  ) async {
    const paragraphCount = 10;
    final shape = _shape()
      ..text = List.filled(paragraphCount, 'Glyph').join('\n')
      ..fontSizePt = 19
      ..textScale = 0.625
      ..lineSpacingReduction = 0.2;
    _captureRichRuns(shape);
    for (final paragraph in shape.richText) {
      paragraph
        ..lineSpacing = 1.5
        ..spaceBeforeLineRatio = 0.2;
    }
    shape.richText.last.runs.single.color = '0000FF';

    await _mount(tester, shape);
    final first = (await _inkBounds(tester, 0xFF0000))!;
    final last = (await _inkBounds(tester, 0x0000FF))!;
    // PowerPoint fits 19 pt at 62.5% to 12 pt before applying leading.
    // The 20% space before offsets the autofit reduction.
    expect(last.top - first.top, closeTo(194.4, 0.8));
  });

  testWidgets('default leading matches explicit single spacing', (
    tester,
  ) async {
    final shape = _shape()
      ..text = List.filled(10, 'Glyph').join('\n')
      ..fontSizePt = 19;
    _captureRichRuns(shape);
    shape.richText.last.runs.single.color = '0000FF';
    await _mount(tester, shape);
    final first = (await _inkBounds(tester, 0xFF0000))!;
    final last = (await _inkBounds(tester, 0x0000FF))!;
    expect(last.top - first.top, closeTo(205.2, 1.2));

    for (final paragraph in shape.richText) {
      paragraph.definedProperties.add(PmlParagraphProperty.lineSpacing);
    }
    await _mount(tester, shape);
    expect(await _inkBounds(tester, 0xFF0000), first);
    expect(await _inkBounds(tester, 0x0000FF), last);
  });

  testWidgets('mixed font styles retain the advance of a uniform point size', (
    tester,
  ) async {
    final shape = _shape()
      ..text = List.filled(10, 'Glyph sample').join('\n')
      ..textColor = '222222'
      ..fontSizePt = 19;
    _captureRichRuns(shape);
    for (final (index, paragraph) in shape.richText.indexed) {
      paragraph.runs.single
        ..text = 'Glyph'
        ..color = index == 9 ? '0000FF' : 'FF0000';
      paragraph.runs.add(
        PmlTextRun(text: ' sample', fontSizePt: 19, bold: true, italic: true),
      );
    }
    await _mount(tester, shape);
    final first = (await _inkBounds(tester, 0xFF0000))!;
    final last = (await _inkBounds(tester, 0x0000FF))!;
    expect(last.top - first.top, closeTo(205.2, 1.2));
  });

  testWidgets('character spacing changes the rendered width under autofit', (
    tester,
  ) async {
    final shape = _shape()
      ..text = 'Spacing sample'
      ..textScale = 0.625;
    _captureRichRuns(shape);
    final paragraph = shape.richText.single;
    final run = paragraph.runs.single;
    await _mount(tester, shape);
    final normal = (await _inkBounds(tester, 0xFF0000))!;

    paragraph.defaultLetterSpacingPt = 2;
    await _mount(tester, shape);
    final expanded = (await _inkBounds(tester, 0xFF0000))!;
    expect(expanded.width - normal.width, greaterThan(16));

    run.letterSpacingPt = 0;
    await _mount(tester, shape);
    expect(await _inkBounds(tester, 0xFF0000), normal);

    run.letterSpacingPt = -1.5;
    await _mount(tester, shape);
    final tightened = (await _inkBounds(tester, 0xFF0000))!;
    expect(normal.width - tightened.width, greaterThan(8));
  });

  testWidgets('disabled wrapping honors alignment and manual line breaks', (
    tester,
  ) async {
    for (final rich in [false, true]) {
      final shape = _shape()
        ..text = 'Alpha Beta Gamma\nShort'
        ..transform = const PmlTransform(
          x: 330 * 12700,
          y: 40 * 12700,
          cx: 90 * 12700,
          cy: 180 * 12700,
        );
      if (rich) _captureRichRuns(shape);
      await _mount(tester, shape);
      final wrapped = (await _inkBounds(tester, 0xFF0000))!;
      shape.textWrap = false;
      await _mount(tester, shape);
      final left = (await _inkBounds(tester, 0xFF0000))!;
      expect(left.width, greaterThan(wrapped.width * 1.6));
      expect(left.height, lessThan(wrapped.height * 0.8));
      expect(left.height, greaterThan(24));

      shape.textAlignOverride = true;
      shape.textAlign = PmlTextAlign.center;
      await _mount(tester, shape);
      final centered = (await _inkBounds(tester, 0xFF0000))!;
      shape.textAlign = PmlTextAlign.right;
      await _mount(tester, shape);
      final right = (await _inkBounds(tester, 0xFF0000))!;
      expect(centered.left, lessThan(left.left - 20));
      expect(right.left, lessThan(centered.left - 20));
      expect(right.width, closeTo(left.width, 2));
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

  testWidgets('rounded callout insets text and uses the same caret origin', (
    tester,
  ) async {
    final shape = _shape()
      ..text = 'Alpha'
      ..preset = PmlShapePreset.roundRect
      ..transform = const PmlTransform(
        x: 30 * 12700,
        y: 40 * 12700,
        cx: 250 * 12700,
        cy: 100 * 12700,
      );
    _captureRichRuns(shape);
    await _mount(tester, shape);
    final ordinary = (await _inkBounds(tester, 0xFF0000))!;

    shape.roundedCallout = const PmlRoundedCallout(corner: 40000);
    int? caret;
    await _mount(
      tester,
      shape,
      onPlaceCaret: (int index, {bool extend = false}) => caret = index,
    );
    final callout = (await _inkBounds(tester, 0xFF0000))!;
    expect(callout.left - ordinary.left, closeTo(11.7, 1));
    expect(callout.top - ordinary.top, closeTo(11.7, 1));
    await tester.tapAt(callout.topLeft + const Offset(1, 1));
    expect(caret, lessThanOrEqualTo(1));
  });

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

  testWidgets('justified text wraps at the quantized glyph advances', (
    tester,
  ) async {
    await OfficeHostFonts.ensureRegistered();
    final shape = _shape()
      ..text = 'a readable editor'
      ..fontSizePt = 28;
    _captureRichRuns(shape);
    final paragraph = shape.richText.single..align = PmlTextAlign.justify;
    paragraph.runs.single
      ..fontFamily = 'Liberation Sans'
      ..text = 'a readable ';
    paragraph.runs.add(
      PmlTextRun(
        fontFamily: 'Liberation Sans',
        fontSizePt: 28,
        text: 'editor',
        color: '0000FF',
      ),
    );

    Future<double> inkLineDifference(double contentWidth) async {
      shape.transform = PmlTransform(
        x: 30 * 12700,
        y: 40 * 12700,
        cx: ((contentWidth + 14.4) * 12700).round(),
        cy: 160 * 12700,
      );
      await _mount(tester, shape);
      final first = (await _inkBounds(tester, 0xFF0000))!;
      final last = (await _inkBounds(tester, 0x0000FF))!;
      return last.top - first.top;
    }

    // The font's fractional advances total 210.15 pt. PowerPoint's rounded
    // advances total 210.75 pt, so 210.5 pt fits only the first two words.
    expect(await inkLineDifference(210.5), greaterThan(20));
    expect(await inkLineDifference(211), closeTo(0, 1));
  });
}
