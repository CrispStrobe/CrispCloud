import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundaryKey = ValueKey('footnote-separator-raster');
const _canvasKey = ValueKey('footnote-separator-canvas');

WmlDocument _document({
  required WmlFootnoteSeparator separator,
  bool note = true,
}) {
  final document = WmlDocument(
    footnoteSeparator: separator,
    sections: [
      WmlSection(
        pageSize: const WmlPageSize(width: 320, height: 260),
        margins: const WmlPageMargins(top: 20, bottom: 20, left: 24, right: 16),
        blocks: [
          WmlParagraph(inlines: [WmlRun(text: 'Body text')]),
        ],
      ),
    ],
  );
  if (note) {
    WordNotes.insert(
      document,
      document.paragraphs.first,
      endnote: false,
      text: 'Footnote text',
    );
  }
  return document;
}

WmlFootnoteSeparator _separator({
  WmlFootnoteSeparatorAlignment alignment = WmlFootnoteSeparatorAlignment.left,
  WmlFootnoteSeparatorLineStyle lineStyle = WmlFootnoteSeparatorLineStyle.solid,
  double thickness = 4,
  int color = 0xCC3399,
}) => WmlFootnoteSeparator(
  beforeSpacing: 12,
  thickness: thickness,
  afterSpacing: 8,
  relativeWidth: .5,
  alignment: alignment,
  color: color,
  lineStyle: lineStyle,
);

Future<RenderWordCanvas> _mount(
  WidgetTester tester,
  WmlDocument document,
  LaidOutDocument layout, {
  OfficeTheme theme = OfficeTheme.light,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: WordCanvas(
          key: _canvasKey,
          document: document,
          laidOut: layout,
          caret: CaretEngine(),
          config: OfficeSurfaceConfig(
            theme: theme,
            mode: OfficeInteractionMode.selecting,
            showRulers: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return tester.renderObject<RenderWordCanvas>(find.byKey(_canvasKey));
}

Future<({Uint8List bytes, int width})> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return (
        bytes: Uint8List.fromList(data.buffer.asUint8List()),
        width: image.width,
      );
    } finally {
      image.dispose();
    }
  }))!;
}

Rect? _colorBounds(({Uint8List bytes, int width}) raster, int color) {
  var left = raster.width;
  var right = -1;
  var top = raster.bytes.length ~/ (raster.width * 4);
  var bottom = -1;
  final red = (color >> 16) & 255;
  final green = (color >> 8) & 255;
  final blue = color & 255;
  for (var offset = 0; offset < raster.bytes.length; offset += 4) {
    if ((raster.bytes[offset] - red).abs() > 2 ||
        (raster.bytes[offset + 1] - green).abs() > 2 ||
        (raster.bytes[offset + 2] - blue).abs() > 2 ||
        raster.bytes[offset + 3] != 255) {
      continue;
    }
    final pixel = offset ~/ 4;
    final x = pixel % raster.width;
    final y = pixel ~/ raster.width;
    left = math.min(left, x);
    right = math.max(right, x);
    top = math.min(top, y);
    bottom = math.max(bottom, y);
  }
  return right < 0
      ? null
      : Rect.fromLTRB(
          left.toDouble(),
          top.toDouble(),
          (right + 1).toDouble(),
          (bottom + 1).toDouble(),
        );
}

void _expectRasterBounds(
  Rect actual,
  RenderWordCanvas canvas,
  LaidOutBox rule,
) {
  final start = canvas.windowForPagePoint(0, Offset(rule.x, rule.y));
  final end = canvas.windowForPagePoint(
    0,
    Offset(rule.x + rule.width, rule.y + rule.height),
  );
  expect(actual.left, closeTo(start.dx, 1.1));
  expect(actual.top, closeTo(start.dy, 1.1));
  expect(actual.right, closeTo(end.dx, 1.1));
  expect(actual.bottom, closeTo(end.dy, 1.1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final alignment in WmlFootnoteSeparatorAlignment.values) {
    testWidgets('native $alignment separator paints its color and thickness', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(520, 460);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final document = _document(separator: _separator(alignment: alignment));
      final layout = WordLayoutEngine(font: null).layout(document);
      final canvas = await _mount(tester, document, layout);
      final rule = layout.pages.single.frames.singleWhere(
        (box) => box.kind == LaidOutBoxKind.footnote,
      );
      final pixels = await _pixels(tester);
      final bounds = _colorBounds(pixels, 0xCC3399);
      expect(bounds, isNotNull);
      _expectRasterBounds(bounds!, canvas, rule);
    });
  }

  testWidgets('dark canvas redraws the new separator geometry and color', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(520, 460);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final document = _document(separator: _separator());
    final firstLayout = WordLayoutEngine(font: null).layout(document);
    final firstCanvas = await _mount(
      tester,
      document,
      firstLayout,
      theme: OfficeTheme.dark,
    );
    expect(_colorBounds(await _pixels(tester), 0xCC3399), isNotNull);
    document.footnoteSeparator = _separator(
      alignment: WmlFootnoteSeparatorAlignment.right,
      thickness: 7,
      color: 0x3399CC,
    );
    final secondLayout = WordLayoutEngine(font: null).layout(document);
    final canvas = await _mount(
      tester,
      document,
      secondLayout,
      theme: OfficeTheme.dark,
    );
    expect(canvas, same(firstCanvas));
    final pixels = await _pixels(tester);
    expect(_colorBounds(pixels, 0xCC3399), isNull);
    final bounds = _colorBounds(pixels, 0x3399CC);
    expect(bounds, isNotNull);
    final rule = secondLayout.pages.single.frames.singleWhere(
      (box) => box.kind == LaidOutBoxKind.footnote,
    );
    _expectRasterBounds(bounds!, canvas, rule);
  });

  testWidgets(
    'explicit hidden separator reserves gaps without painted pixels',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(520, 460);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final document = _document(
        separator: _separator(lineStyle: WmlFootnoteSeparatorLineStyle.none),
      );
      final layout = WordLayoutEngine(font: null).layout(document);
      await _mount(tester, document, layout);
      expect(layout.pages.single.notes, isNotEmpty);
      expect(
        layout.pages.single.frames.where(
          (box) => box.kind == LaidOutBoxKind.footnote,
        ),
        isEmpty,
      );
      expect(_colorBounds(await _pixels(tester), 0xCC3399), isNull);
    },
  );

  test('footnote insertion undo and redo retain separator preferences', () {
    final separator = _separator(
      alignment: WmlFootnoteSeparatorAlignment.center,
    );
    final controller = WordEditorController(
      document: _document(separator: separator, note: false),
    );
    addTearDown(controller.dispose);
    controller.proofing.enabled = false;
    controller.insertFootnote(text: 'Inserted note');
    expect(controller.document.footnoteSeparator, separator);
    expect(
      controller.laidOut.pages.single.frames.where(
        (box) => box.kind == LaidOutBoxKind.footnote,
      ),
      hasLength(1),
    );
    controller.undo();
    expect(controller.document.footnoteSeparator, separator);
    expect(controller.document.footnotes, isEmpty);
    expect(
      controller.laidOut.pages
          .expand((page) => page.frames)
          .where((box) => box.kind == LaidOutBoxKind.footnote),
      isEmpty,
    );
    controller.redo();
    expect(controller.document.footnoteSeparator, separator);
    final rule = controller.laidOut.pages.single.frames.singleWhere(
      (box) => box.kind == LaidOutBoxKind.footnote,
    );
    expect(rule.width, 140);
    expect(rule.height, 4);
  });
}
