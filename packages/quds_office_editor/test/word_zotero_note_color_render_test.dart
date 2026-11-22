import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundaryKey = ValueKey('zotero-note-color-raster');
const _documentId = 'zotero-note-color-raster';

WmlDocument _document() {
  final document = WmlDocument.empty();
  document.sections.first
    ..pageSize = const WmlPageSize(width: 420, height: 320)
    ..margins = const WmlPageMargins(top: 24, bottom: 24, left: 24, right: 24);
  final session = WordZoteroCitingSession(
    document: document,
    documentId: _documentId,
    insertionParagraph: document.paragraphs.first,
  );
  session.handle('Document.insertText', [
    _documentId,
    '<p><span style="color:#000000;background-color:rgb(255,212,0)">'
        'Paper highlight</span></p>'
        '<p><span style="color:#000000;background-color:#ffd400">'
        'Shaded highlight</span></p>'
        '<table><tr><td style="background-color:#193651">'
        '<p><span style="color:#000000;background-color:#ffd400">'
        'Cell highlight</span></p></td></tr></table>',
  ]);
  session.handle('Document.complete', [_documentId]);
  session.apply();
  for (final paragraph in document.paragraphs) {
    if (paragraph.text == 'Shaded highlight') {
      paragraph.properties.shadingFill = '315A80';
    }
    for (final run in paragraph.inlines.whereType<WmlRun>()) {
      run.properties.fontSizeHalfPoints = 32;
    }
  }
  return document;
}

List<Object?> _colors(WmlDocument document) => [
  for (final paragraph in document.paragraphs)
    [
      paragraph.text,
      paragraph.properties.shadingFill,
      for (final run in paragraph.inlines.whereType<WmlRun>())
        [run.text, run.properties.color, run.properties.highlight],
    ],
];

Future<({List<int> bytes, int width, int height})> _paint(
  WidgetTester tester,
  WmlDocument document,
  LaidOutDocument layout,
  OfficeTheme theme,
) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _boundaryKey,
          child: SizedBox(
            width: 500,
            height: 400,
            child: WordCanvas(
              document: document,
              laidOut: layout,
              caret: CaretEngine(),
              compact: true,
              config: OfficeSurfaceConfig(
                theme: theme,
                mode: OfficeInteractionMode.viewing,
                showRulers: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
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
        bytes: data.buffer.asUint8List().toList(),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  }))!;
}

int _countColor(
  ({List<int> bytes, int width, int height}) raster,
  ui.Rect area,
  int rgb,
) {
  var count = 0;
  for (
    var y = area.top.ceil().clamp(0, raster.height);
    y < area.bottom.floor().clamp(0, raster.height);
    y++
  ) {
    for (
      var x = area.left.ceil().clamp(0, raster.width);
      x < area.right.floor().clamp(0, raster.width);
      x++
    ) {
      final offset = (y * raster.width + x) * 4;
      if (raster.bytes[offset] == ((rgb >> 16) & 255) &&
          raster.bytes[offset + 1] == ((rgb >> 8) & 255) &&
          raster.bytes[offset + 2] == (rgb & 255) &&
          raster.bytes[offset + 3] == 255) {
        count++;
      }
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  for (final (name, theme) in [
    ('light', OfficeTheme.light),
    ('dark', OfficeTheme.dark),
  ]) {
    testWidgets(
      'Zotero RGB highlights stay opaque over $name paper and shaded content',
      (tester) async {
        var document = _document();
        for (var cycle = 0; cycle < 2; cycle++) {
          final before = _colors(document);
          final layout = WordLayoutEngine(font: null).layout(document);
          final raster = await _paint(tester, document, layout, theme);
          final highlighted = document.paragraphs
              .where((p) => p.text.endsWith('highlight'))
              .toList();
          expect(highlighted, hasLength(3));
          for (final paragraph in highlighted) {
            final lines = layout.pages.first.lines.where(
              (line) => identical(line.sourceParagraph, paragraph),
            );
            var backgroundPixels = 0;
            var inkPixels = 0;
            for (final line in lines) {
              final bounds = ui.Rect.fromLTWH(
                line.x,
                line.y,
                line.width,
                line.height,
              );
              backgroundPixels += _countColor(raster, bounds, 0xFFD400);
              inkPixels += _countColor(raster, bounds, 0x000000);
            }
            expect(
              backgroundPixels,
              greaterThan(100),
              reason:
                  '${paragraph.text} must paint the exported RGB exactly '
                  'on $name paper, cycle $cycle',
            );
            expect(
              inkPixels,
              greaterThan(10),
              reason: 'Black text must use its opaque highlight as backing',
            );
          }
          expect(_colors(document), before);
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          expect(_colors(document), before);
        }
      },
    );
  }
}
