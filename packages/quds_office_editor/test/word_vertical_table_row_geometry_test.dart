import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlParagraph _paragraph(String text) => WmlParagraph(
  properties: WmlParagraphProps(
    spacingBefore: 0,
    spacingAfter: 0,
    lineSpacing: 1,
  ),
  inlines: [WmlRun(text: text)],
);

WmlDocument _document(bool rtl) => WmlDocument(
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 400, height: 240),
      margins: const WmlPageMargins(left: 30, right: 30, top: 20, bottom: 20),
      blocks: [
        WmlTable(
          grid: [100, 100],
          properties: WmlTableProps(rightToLeft: rtl),
          rows: [
            for (var row = 0; row < 4; row++)
              WmlTableRow(
                height: 70,
                cantSplit: true,
                cells: [
                  WmlTableCell(
                    gridSpan: 2,
                    vMerge: row == 0 ? WmlVMerge.restart : WmlVMerge.cont,
                    fillColor: 'FFEEDD',
                    blocks: [_paragraph(row == 0 ? 'Merged origin' : '')],
                  ),
                ],
              ),
          ],
        ),
      ],
    ),
  ],
);

Future<void> _click(
  WidgetTester tester,
  RenderWordCanvas canvas,
  int page,
  Offset point,
) async {
  final global = canvas.localToGlobal(canvas.windowForPagePoint(page, point));
  expect(tester.getRect(find.byType(WordCanvas)).contains(global), isTrue);
  final gesture = await tester.startGesture(
    global,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.up();
  await tester.pump();
}

void main() {
  setUpAll(OfficeHostFonts.ensureRegistered);
  for (final rtl in [false, true]) {
    for (final reopen in [false, true]) {
      testWidgets(
        '${reopen ? 'reopened' : 'live'} ${rtl ? 'RTL' : 'LTR'} merge row bands retain physical rows on each page',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var document = _document(rtl);
          if (reopen) {
            document = WordDeserializer().readBytes(
              WordSerializer().writeBytes(document),
            );
          }
          final table = document.sections.single.blocks.single as WmlTable;
          final layout = WordLayoutEngine(font: null).layout(document);
          expect(layout.pages, hasLength(2));
          final selected =
              <({WmlTable table, bool column, int from, int to})>[];
          final inserted = <int>[];
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: SizedBox(
                  width: 650,
                  height: 1000,
                  child: WordCanvas(
                    document: document,
                    laidOut: layout,
                    caret: CaretEngine(),
                    config: const OfficeSurfaceConfig(showRulers: false),
                    onSelectTableBand:
                        (value, {required column, required from, required to}) {
                          selected.add((
                            table: value,
                            column: column,
                            from: from,
                            to: to,
                          ));
                        },
                    onInsertTableRowAt: (value, index) {
                      expect(value, same(table));
                      inserted.add(index);
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final canvas = tester.renderObject<RenderWordCanvas>(
            find.byType(WordCanvas),
          );
          for (final page in layout.pages) {
            final boxes = page.frames
                .where((box) => identical(box.table, table))
                .toList();
            final physical = boxes
                .map((box) => box.tableRowGeometry)
                .nonNulls
                .toList();
            expect(
              physical.map((row) => row.row),
              page.index == 0 ? [0, 1] : [2, 3],
            );
            expect(boxes.where((box) => box.height > 0).single.tableRow, 0);
            for (final row in physical) {
              selected.clear();
              await _click(
                tester,
                canvas,
                page.index,
                Offset(boxes.first.x - 12, row.y + row.height / 2),
              );
              expect(selected, [
                (table: table, column: false, from: row.row, to: row.row),
              ]);
            }
            // The boundary between visible physical rows has its global row
            // index even though the sole painted cell is owned by row zero.
            inserted.clear();
            await _click(
              tester,
              canvas,
              page.index,
              Offset(boxes.first.x - 12, physical.last.y),
            );
            expect(inserted, [physical.last.row]);
            for (final boundary in [
              // Use the bottom of the top button's hit area, clear of the
              // table-move handle that sits immediately above it.
              (index: physical.first.row, y: physical.first.y + 7),
              (
                index: physical.last.row + 1,
                y: physical.last.y + physical.last.height,
              ),
            ]) {
              inserted.clear();
              await _click(
                tester,
                canvas,
                page.index,
                Offset(boxes.first.x - 12, boundary.y),
              );
              expect(inserted, [boundary.index]);
            }
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
