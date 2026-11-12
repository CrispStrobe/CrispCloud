import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _sourceLine =
    '<a:ln><a:solidFill><a:srgbClr val="355C7D"/></a:solidFill></a:ln>';

WmlDocument _nativeFrame(String properties, String children) {
  final package = OpcPackage.create(OpcPackageKind.word);
  final xml = File(
    '../quds_office_engine/test/fixtures/fidelity/frame_wrap_source.xml',
  ).readAsStringSync();
  package
      .getPart('/word/document.xml')!
      .writeText(
        xml.replaceFirst(
          _sourceLine,
          '<a:ln $properties><a:solidFill><a:srgbClr val="355C7D"/>'
          '</a:solidFill>$children</a:ln>',
        ),
      );
  return WordDeserializer().read(package);
}

class _CanvasPixels {
  _CanvasPixels(this.data, this.width, this.canvas, this.frame);

  final ByteData data;
  final int width;
  final RenderWordCanvas canvas;
  final WmlFrame frame;

  bool strokeAt(
    double x,
    double y, {
    int red = 0x35,
    int green = 0x5c,
    int blue = 0x7d,
  }) {
    final point = canvas.windowForPagePoint(
      0,
      Offset(frame.x + 24 + x, frame.y + 24 + y),
    );
    final offset = (point.dy.floor() * width + point.dx.floor()) * 4;
    return (data.getUint8(offset) - red).abs() < 12 &&
        (data.getUint8(offset + 1) - green).abs() < 12 &&
        (data.getUint8(offset + 2) - blue).abs() < 12;
  }
}

Future<_CanvasPixels> _paint(
  WidgetTester tester,
  WmlDocument document, {
  bool selected = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(640, 460);
  final frame = document.sections.single.blocks.whereType<WmlFrame>().single;
  final laid = WordLayoutEngine(font: null).layout(document);
  expect(laid.pages, hasLength(1));
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: const ValueKey('outline-page'),
        child: WordCanvas(
          document: document,
          laidOut: laid,
          caret: CaretEngine(),
          selectedFrame: selected ? frame : null,
          editingFrame: selected,
          config: OfficeSurfaceConfig(
            mode: OfficeInteractionMode.viewing,
            theme: OfficeTheme.light.copyWith(fontFamily: 'Arial'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('outline-page')),
  );
  final canvas = tester.renderObject<RenderWordCanvas>(find.byType(WordCanvas));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final result = _CanvasPixels(pixels, image.width, canvas, frame);
    image.dispose();
    return result;
  }))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets('native six-point dashes and a color edit survive three saves', (
    tester,
  ) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var document = _nativeFrame(
      'w="76200" cap="flat"',
      '<a:prstDash val="dash"/><a:miter lim="800000"/>',
    );
    for (var cycle = 0; cycle < 4; cycle++) {
      if (cycle == 2) {
        document.sections.single.blocks
                .whereType<WmlFrame>()
                .single
                .strokeColor =
            'AA1122';
      }
      final image = await _paint(tester, document);
      bool painted(double x, double y) => image.strokeAt(
        x,
        y,
        red: cycle < 2 ? 0x35 : 0xaa,
        green: cycle < 2 ? 0x5c : 0x11,
        blue: cycle < 2 ? 0x7d : 0x22,
      );
      expect(painted(6, -2), isTrue, reason: '6 pt width, cycle $cycle');
      expect(painted(6, -4), isFalse, reason: 'outside stroke, cycle $cycle');
      expect(painted(30, 0), isFalse, reason: '18 pt native gap, cycle $cycle');
      expect(painted(48, -2), isTrue, reason: 'next dash, cycle $cycle');
      if (cycle < 3) {
        final bytes = cycle.isEven
            ? WordSerializer().writeBytes(document)
            : (await tester.runAsync(() => OfficeIsolateSave.word(document)))!;
        document = WordDeserializer().readBytes(bytes);
      }
    }
  });

  testWidgets('custom dash percentages control actual painted intervals', (
    tester,
  ) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final image = await _paint(
      tester,
      _nativeFrame(
        'w="76200" cap="flat"',
        '<a:custDash><a:ds d="200000" sp="100000"/></a:custDash>',
      ),
    );
    expect(image.strokeAt(6, -2), isTrue);
    expect(image.strokeAt(15, 0), isFalse);
    expect(image.strokeAt(24, -2), isTrue);
  });

  testWidgets(
    'round dot caps remain dots rather than square or solid strokes',
    (tester) async {
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final image = await _paint(
        tester,
        _nativeFrame('w="152400" cap="rnd"', '<a:prstDash val="dot"/>'),
      );
      expect(image.strokeAt(6, -4), isTrue);
      expect(image.strokeAt(1, -5), isFalse);
      expect(image.strokeAt(30, 0), isFalse);
      expect(image.strokeAt(54, -4), isTrue);
    },
  );

  testWidgets(
    'miter, round and bevel joins have their native corner geometry',
    (tester) async {
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final join in ['miter', 'round', 'bevel']) {
        final image = await _paint(
          tester,
          _nativeFrame('w="228600" cap="flat"', '<a:$join/>'),
        );
        expect(image.strokeAt(-7.5, -7.5), join == 'miter', reason: join);
        expect(image.strokeAt(-5.5, -5.5), join != 'bevel', reason: join);
        expect(image.strokeAt(10, -6), isTrue, reason: join);
      }
    },
  );

  testWidgets('inset outlines remain inside the frame bounds', (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final image = await _paint(
      tester,
      _nativeFrame('w="76200" cap="flat" algn="in"', '<a:bevel/>'),
    );
    expect(image.strokeAt(10, -2), isFalse);
    expect(image.strokeAt(10, 2), isTrue);
    expect(image.strokeAt(10, 8), isFalse);
  });

  testWidgets('selection chrome retains the native outline beneath it', (
    tester,
  ) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final image = await _paint(
      tester,
      _nativeFrame('w="76200" cap="flat"', '<a:prstDash val="dash"/>'),
      selected: true,
    );
    expect(image.strokeAt(6, -2), isTrue);
    expect(image.strokeAt(30, -2), isFalse);
  });
}
