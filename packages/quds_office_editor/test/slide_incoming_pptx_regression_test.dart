import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundaryKey = ValueKey('incoming-pptx-raster');

PmlShape _shape(
  int id, {
  double x = 30,
  double y = 30,
  double width = 100,
  double height = 40,
  double rotation = 0,
  String fill = 'FF0000',
  String text = '',
}) => PmlShape(
  id: id,
  name: 'Shape $id',
  fillColor: fill,
  textColor: '000000',
  text: text,
  fontSizePt: 20,
  rightToLeft: false,
  transform: PmlTransform(
    x: (x * 12700).round(),
    y: (y * 12700).round(),
    cx: (width * 12700).round(),
    cy: (height * 12700).round(),
    rot: (rotation * 60000).round(),
  ),
);

PmlShape _connector({
  int id = 2,
  bool flipH = false,
  bool flipV = false,
  bool fillOnly = false,
}) => _shape(id, fill: fillOnly ? 'FF0000' : '')
  ..preset = PmlShapePreset.connector
  ..strokeColor = fillOnly ? '' : 'FF0000'
  ..strokeWidth = 2
  ..transform = PmlTransform(
    x: 30 * 12700,
    y: 30 * 12700,
    cx: 100 * 12700,
    cy: 40 * 12700,
    flipH: flipH,
    flipV: flipV,
  );

class _Raster {
  _Raster(this.width, this.height, this.bytes);
  final int width;
  final int height;
  final List<int> bytes;

  int count(int rgb, {Rect? area}) {
    final Rect bounds =
        area ?? Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    var count = 0;
    for (
      var y = bounds.top.floor().clamp(0, height);
      y < bounds.bottom.ceil().clamp(0, height);
      y++
    ) {
      for (
        var x = bounds.left.floor().clamp(0, width);
        x < bounds.right.ceil().clamp(0, width);
        x++
      ) {
        final int index = (y * width + x) * 4;
        if ((bytes[index] - ((rgb >> 16) & 255)).abs() <= 2 &&
            (bytes[index + 1] - ((rgb >> 8) & 255)).abs() <= 2 &&
            (bytes[index + 2] - (rgb & 255)).abs() <= 2) {
          count++;
        }
      }
    }
    return count;
  }
}

Future<_Raster> _render(
  WidgetTester tester,
  PmlSlide slide, {
  Map<int, PmlAnimSample>? samples,
  OfficeTheme theme = OfficeTheme.light,
  PmlSlide? outgoing,
  double progress = 0.5,
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
              preview: samples == null && outgoing == null,
              presenting: samples != null || outgoing != null,
              animSamples: samples,
              outgoingSlide: outgoing,
              transitionProgress: progress,
              playingTransition: outgoing == null
                  ? null
                  : const PmlSlideTransition(kind: PmlTransitionKind.morph),
              config: OfficeSurfaceConfig(
                theme: theme,
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
    find.byKey(_boundaryKey),
  );
  return (await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return _Raster(image.width, image.height, bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  testWidgets('hidden master flag retains resolved layout decorations', (
    tester,
  ) async {
    final _Raster raster = await _render(
      tester,
      PmlSlide(
        id: 256,
        background: 'FFFFFF',
        showMasterShapes: false,
        backgroundShapes: [_shape(2)],
        shapes: [_shape(3, x: 220, fill: '0000FF')],
      ),
    );
    expect(raster.count(0xFF0000), greaterThan(3000));
    expect(raster.count(0x0000FF), greaterThan(3000));
  });

  for (final (bool flipH, bool flipV) in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    testWidgets('connector H=$flipH V=$flipV paints its authored diagonal', (
      tester,
    ) async {
      final _Raster raster = await _render(
        tester,
        PmlSlide(
          id: 256,
          background: 'FFFFFF',
          shapes: [_connector(flipH: flipH, flipV: flipV)],
        ),
      );
      final bool ascending = flipH != flipV;
      expect(
        raster.count(
          0xFF0000,
          area: Rect.fromLTWH(ascending ? 115 : 35, 28, 15, 15),
        ),
        greaterThan(10),
      );
      expect(
        raster.count(
          0xFF0000,
          area: Rect.fromLTWH(ascending ? 35 : 115, 28, 15, 15),
        ),
        0,
      );
    });
  }

  testWidgets('legacy fill-only connectors remain visible in the editor', (
    tester,
  ) async {
    final _Raster raster = await _render(
      tester,
      PmlSlide(
        id: 256,
        background: 'FFFFFF',
        shapes: [_connector(flipH: true, fillOnly: true)],
      ),
    );
    expect(
      raster.count(0xFF0000, area: const Rect.fromLTWH(115, 28, 15, 15)),
      greaterThan(0),
    );
    expect(
      raster.count(0xFF0000, area: const Rect.fromLTWH(35, 28, 15, 15)),
      0,
    );
  });

  testWidgets('rotated single-axis connector keeps its authored diagonal', (
    tester,
  ) async {
    final PmlShape shape = _connector(flipH: true)
      ..transform = const PmlTransform(
        x: 80 * 12700,
        y: 80 * 12700,
        cx: 100 * 12700,
        cy: 40 * 12700,
        rot: 90 * 60000,
        flipH: true,
      );
    final _Raster raster = await _render(
      tester,
      PmlSlide(id: 256, background: 'FFFFFF', shapes: [shape]),
    );
    expect(
      raster.count(0xFF0000, area: const Rect.fromLTWH(142, 135, 15, 15)),
      greaterThan(10),
    );
    expect(
      raster.count(0xFF0000, area: const Rect.fromLTWH(105, 135, 15, 15)),
      0,
    );
  });

  test('clipboard clones preserve connector flips, stroke and geometry', () {
    final PmlShape source = _connector(flipH: true);
    final PmlShape copied = cloneClipboardShape(source, id: 9, nudgeEmu: 12700);
    expect(copied.id, 9);
    expect((copied.transform.flipH, copied.transform.flipV), (true, false));
    expect(copied.transform.x, source.transform.x + 12700);
    expect(copied.transform.y, source.transform.y + 12700);
    expect(copied.strokeColor, source.strokeColor);
    expect(copied.strokeWidth, source.strokeWidth);
    expect(copied.preset, PmlShapePreset.connector);
  });

  test('nudge, grouped edits and undo retain independent connector flips', () {
    final PmlShape first = _connector(flipH: true)..groupId = 1;
    final PmlShape mate = _connector(id: 3, flipV: true)..groupId = 1;
    final SlideEditorController controller = SlideEditorController(
      presentation: PmlPresentation(
        slides: [
          PmlSlide(id: 256, shapes: [first, mate]),
        ],
      ),
    );
    addTearDown(controller.dispose);
    void expectFlips() {
      expect((first.transform.flipH, first.transform.flipV), (true, false));
      expect((mate.transform.flipH, mate.transform.flipV), (false, true));
    }

    controller.selectShape(first);
    controller.nudgeSelected(12700, 25400);
    expect(first.transform.xPoints, 31);
    expectFlips();
    controller.undo();
    expect(first.transform.xPoints, 30);
    expectFlips();
    controller.redo();
    expect(first.transform.xPoints, 31);
    expectFlips();
    controller.applyTransform(
      first,
      const PmlTransform(
        x: 35 * 12700,
        y: 36 * 12700,
        cx: 100 * 12700,
        cy: 40 * 12700,
        flipH: true,
      ),
    );
    expect(mate.transform.xPoints, 35);
    expectFlips();
    controller.undo();
    expectFlips();
  });

  testWidgets('morph paints sampled connector flips rather than target flags', (
    tester,
  ) async {
    final PmlSlide outgoing = PmlSlide(
      id: 256,
      background: 'FFFFFF',
      shapes: [_connector(flipH: true)],
    );
    final PmlSlide incoming = PmlSlide(
      id: 257,
      background: 'FFFFFF',
      shapes: [_connector()],
    );
    final _Raster before = await _render(
      tester,
      incoming,
      outgoing: outgoing,
      progress: 0.25,
    );
    final _Raster after = await _render(
      tester,
      incoming,
      outgoing: outgoing,
      progress: 0.75,
    );
    expect(
      before.count(0xFF0000, area: const Rect.fromLTWH(115, 28, 15, 15)),
      greaterThan(10),
    );
    expect(
      before.count(0xFF0000, area: const Rect.fromLTWH(35, 28, 15, 15)),
      0,
    );
    expect(
      after.count(0xFF0000, area: const Rect.fromLTWH(35, 28, 15, 15)),
      greaterThan(10),
    );
    expect(
      after.count(0xFF0000, area: const Rect.fromLTWH(115, 28, 15, 15)),
      0,
    );
  });

  testWidgets('foreground animation IDs never hide master decorations', (
    tester,
  ) async {
    final PmlSlide slide = PmlSlide(
      id: 256,
      background: 'FFFFFF',
      backgroundShapes: [_shape(2)],
      shapes: [_shape(2, x: 220, fill: '0000FF')],
    );
    final _Raster raster = await _render(
      tester,
      slide,
      samples: {2: PmlAnimSample.hidden},
    );
    expect(raster.count(0xFF0000), greaterThan(3000));
    expect(raster.count(0x0000FF), 0);
  });

  testWidgets('morph foreground IDs never skip master decorations', (
    tester,
  ) async {
    final PmlSlide outgoing = PmlSlide(
      id: 256,
      background: 'FFFFFF',
      backgroundShapes: [_shape(2)],
      shapes: [_shape(2, x: 220, fill: '0000FF')],
    );
    final PmlSlide incoming = outgoing.copy(id: 257);
    incoming.shapes.single.transform = const PmlTransform(
      x: 300 * 12700,
      y: 30 * 12700,
      cx: 100 * 12700,
      cy: 40 * 12700,
    );
    final _Raster raster = await _render(tester, incoming, outgoing: outgoing);
    expect(raster.count(0xFF0000), greaterThan(3000));
    expect(raster.count(0x0000FF), greaterThan(3000));
  });

  testWidgets('master decoration rotation matches authored geometry', (
    tester,
  ) async {
    final _Raster raster = await _render(
      tester,
      PmlSlide(
        id: 256,
        background: 'FFFFFF',
        backgroundShapes: [
          _shape(2, x: 100, y: 100, width: 100, height: 20, rotation: 90),
        ],
      ),
    );
    expect(
      raster.count(0xFF0000, area: const Rect.fromLTWH(142, 65, 16, 90)),
      greaterThan(1300),
    );
    expect(
      raster.count(0xFF0000, area: const Rect.fromLTWH(102, 102, 25, 16)),
      0,
    );
  });

  testWidgets('dark-slide ink respects a white master decoration behind text', (
    tester,
  ) async {
    final PmlShape backing = _shape(2, width: 350, height: 80, fill: 'FFFFFF');
    final PmlShape text = _shape(
      2,
      x: 40,
      y: 40,
      width: 300,
      height: 50,
      fill: '',
      text: 'Black text on white decoration',
    );
    final _Raster raster = await _render(
      tester,
      PmlSlide(id: 256, backgroundShapes: [backing], shapes: [text]),
      theme: OfficeTheme.dark,
    );
    expect(
      raster.count(0x000000, area: const Rect.fromLTWH(40, 40, 300, 50)),
      greaterThan(200),
    );
    expect(
      raster.count(0xFFFFFF, area: const Rect.fromLTWH(30, 30, 350, 80)),
      greaterThan(20000),
    );
  });

  testWidgets('curved decorations do not imply a uniform backing rectangle', (
    tester,
  ) async {
    final PmlShape backing = _shape(8, width: 350, height: 80, fill: '000000')
      ..preset = PmlShapePreset.ellipse;
    final PmlShape text = _shape(
      2,
      x: 40,
      y: 40,
      width: 300,
      height: 50,
      fill: '',
      text: 'Authored text',
    );
    final PmlSlide slide = PmlSlide(
      id: 256,
      backgroundShapes: [backing],
      shapes: [text],
    );
    final _Raster adapted = await _render(
      tester,
      slide,
      theme: OfficeTheme.dark,
    );
    final _Raster authored = await _render(
      tester,
      slide,
      theme: OfficeTheme.dark.copyWith(adaptDocumentColors: false),
    );
    // A curved/mixed backing retains authored text color; it cannot safely
    // establish a uniform dark rectangle for automatic brightening.
    expect(adapted.bytes, authored.bytes);
  });
}
