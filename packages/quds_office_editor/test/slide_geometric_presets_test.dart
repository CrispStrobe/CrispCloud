import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundaryKey = ValueKey('geometric-preset-raster');

Future<List<int>> _render(
  WidgetTester tester,
  String preset, {
  bool flipH = false,
  String guides = '',
}) async {
  final PmlShape shape = parseSlideShapes(
    '<p:sld xmlns:p="${OfficeNamespaces.p}" '
    'xmlns:a="${OfficeNamespaces.a}"><p:cSld><p:spTree><p:sp>'
    '<p:nvSpPr><p:cNvPr id="2" name="Geometry"/>'
    '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>'
    '<a:xfrm flipH="${flipH ? 1 : 0}"><a:off x="381000" y="381000"/>'
    '<a:ext cx="1270000" cy="1270000"/></a:xfrm>'
    '<a:prstGeom prst="$preset"><a:avLst>$guides</a:avLst></a:prstGeom>'
    '<a:solidFill><a:srgbClr val="FF0000"/></a:solidFill>'
    '</p:spPr></p:sp></p:spTree></p:cSld></p:sld>',
  ).single;
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
              slide: PmlSlide(id: 256, background: 'FFFFFF', shapes: [shape]),
              preview: true,
              config: const OfficeSurfaceConfig(
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
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(image.width, 720);
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}

int _pixel(List<int> bytes, int x, int y) {
  final int offset = (y * 720 + x) * 4;
  return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
}

void main() {
  testWidgets('rounded callout paints and flips the external tail', (
    tester,
  ) async {
    const guides =
        '<a:gd name="adj1" fmla="val 25000"/>'
        '<a:gd name="adj2" fmla="val 75000"/>';
    final normal = await _render(
      tester,
      'wedgeRoundRectCallout',
      guides: guides,
    );
    final flipped = await _render(
      tester,
      'wedgeRoundRectCallout',
      guides: guides,
      flipH: true,
    );
    expect(_pixel(normal, 32, 32), 0xFFFFFF);
    expect(_pixel(normal, 80, 80), 0xFF0000);
    expect(_pixel(normal, 104, 145), 0xFF0000);
    expect(_pixel(normal, 56, 145), 0xFFFFFF);
    expect(_pixel(flipped, 104, 145), 0xFFFFFF);
    expect(_pixel(flipped, 56, 145), 0xFF0000);
  });

  testWidgets('pentagon paints a convex body with sloping top corners', (
    tester,
  ) async {
    final List<int> pixels = await _render(tester, 'pentagon');
    expect(_pixel(pixels, 40, 80), 0xFF0000);
    expect(_pixel(pixels, 35, 35), 0xFFFFFF);
    expect(_pixel(pixels, 35, 125), 0xFFFFFF);
    expect(_pixel(pixels, 80, 125), 0xFF0000);
  });

  testWidgets('homePlate paints a flat back and one outward point', (
    tester,
  ) async {
    final List<int> pixels = await _render(tester, 'homePlate');
    expect(_pixel(pixels, 35, 80), 0xFF0000);
    expect(_pixel(pixels, 35, 35), 0xFF0000);
    expect(_pixel(pixels, 105, 35), 0xFFFFFF);
  });

  testWidgets('chevron keeps its inward notch', (tester) async {
    final List<int> pixels = await _render(tester, 'chevron');
    expect(_pixel(pixels, 35, 80), 0xFFFFFF);
    expect(_pixel(pixels, 35, 35), 0xFF0000);
    expect(_pixel(pixels, 80, 80), 0xFF0000);
  });
}
