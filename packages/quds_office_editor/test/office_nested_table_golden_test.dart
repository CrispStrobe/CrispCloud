import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlParagraph _paragraph(String text) => WmlParagraph(
  properties: WmlParagraphProps(spacingAfter: 0, lineSpacing: 1),
  inlines: [
    WmlRun(
      text: text,
      properties: WmlRunProps(asciiFont: 'Arial'),
    ),
  ],
);

WmlDocument _source() {
  final heading = _paragraph('Section heading');
  WordToc.applyHeading(heading, 1);
  final document = WmlDocument(
    sections: [
      WmlSection(
        pageSize: const WmlPageSize(width: 500, height: 520),
        margins: const WmlPageMargins(left: 24, right: 24, top: 24, bottom: 24),
        blocks: [
          _paragraph('Rich content inside a table cell'),
          WmlTable(
            grid: [260, 160],
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    fillColor: 'FFF1D6',
                    blocks: [
                      _paragraph('Before the picture'),
                      WmlVisual(
                        visual: OfficeVisual(
                          kind: OfficeVisualKind.picture,
                          title: 'Authored green picture',
                          width: 72,
                          height: 36,
                          imageBytes: File(
                            '../quds_office_engine/test/fixtures/fidelity/scripts/replacement.png',
                          ).readAsBytesSync(),
                        ),
                      ),
                      WmlTable(
                        grid: [118, 118],
                        rows: [
                          WmlTableRow(
                            cells: [
                              WmlTableCell(
                                fillColor: 'E8EEF4',
                                blocks: [_paragraph('Nested left')],
                              ),
                              WmlTableCell(
                                fillColor: 'E8EEF4',
                                blocks: [_paragraph('Nested right')],
                              ),
                            ],
                          ),
                        ],
                      ),
                      WmlFrame(
                        x: 280,
                        y: 360,
                        width: 150,
                        height: 52,
                        anchor: WmlFrameAnchor.page,
                        wrap: WmlFrameWrap.none,
                        fillColor: 'E8F0FB',
                        strokeColor: '355C7D',
                        blocks: [_paragraph('Absolute cell frame')],
                      ),
                      WmlToc(title: 'Cell contents'),
                      _paragraph('After the nested content'),
                    ],
                  ),
                  WmlTableCell(blocks: [_paragraph('Sibling cell')]),
                ],
              ),
            ],
          ),
          heading,
        ],
      ),
    ],
  );
  WordToc.refreshAll(document);
  return document;
}

Future<void> _expectPicturePixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('nested-table-page')),
  );
  var visible = false;
  for (var attempt = 0; attempt < 100 && !visible; attempt++) {
    visible =
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final width = image.width;
          image.dispose();
          var green = 0;
          var frameInk = 0;
          var pageNumberInk = 0;
          for (var offset = 0; offset < data.lengthInBytes; offset += 4) {
            final x = (offset ~/ 4) % width;
            final y = (offset ~/ 4) ~/ width;
            final dark =
                data.getUint8(offset) < 100 &&
                data.getUint8(offset + 1) < 150 &&
                data.getUint8(offset + 2) < 230;
            // Fixed authored scene/viewport regions exclude borders, leaders and
            // backgrounds. These checks reject blank frame text and a page number
            // painted at the document edge outside its cell.
            if (dark && x >= 445 && x < 630 && y >= 510 && y < 552) frameInk++;
            if (dark && x >= 422 && x < 438 && y >= 267 && y < 292)
              pageNumberInk++;
            if ((data.getUint8(offset) - 11).abs() <= 2 &&
                (data.getUint8(offset + 1) - 177).abs() <= 2 &&
                (data.getUint8(offset + 2) - 59).abs() <= 2)
              green++;
          }
          if (green >= 100 && frameInk >= 40 && pageNumberInk >= 5) return true;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return false;
        }) ??
        false;
    await tester.pumpAndSettle();
  }
  expect(
    visible,
    isTrue,
    reason: 'Picture, frame text and cell TOC page number must all be painted',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);
  testWidgets('rich nested cell paints every object through three saves', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(760, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var document = _source();
    for (var cycle = 0; cycle < 4; cycle++) {
      final laid = WordLayoutEngine(font: null).layout(document);
      expect(laid.pages, hasLength(1));
      expect(
        laid.pages.single.frames.where(
          (b) => b.kind == LaidOutBoxKind.tableCell,
        ),
        hasLength(4),
      );
      expect(
        laid.pages.single.frames.where((b) => b.kind == LaidOutBoxKind.picture),
        hasLength(1),
      );
      expect(
        laid.pages.single.frames.where((b) => b.kind == LaidOutBoxKind.frame),
        hasLength(1),
      );
      expect(
        laid.pages.single.frames.where(
          (b) => b.kind == LaidOutBoxKind.tocEntry,
        ),
        hasLength(1),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: const ValueKey('nested-table-page'),
            child: WordCanvas(
              document: document,
              laidOut: laid,
              caret: CaretEngine(),
              config: OfficeSurfaceConfig(
                mode: OfficeInteractionMode.viewing,
                theme: OfficeTheme.light.copyWith(fontFamily: 'Arial'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expectPicturePixels(tester);
      await expectLater(
        find.byKey(const ValueKey('nested-table-page')),
        matchesGoldenFile('goldens/nested_table_content.png'),
        reason: 'Native cycle $cycle',
      );
      if (cycle < 3) {
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    }
  });
}
