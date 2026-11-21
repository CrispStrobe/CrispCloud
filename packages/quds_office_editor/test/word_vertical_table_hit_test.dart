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
      margins: const WmlPageMargins(left: 20, right: 20, top: 20, bottom: 20),
      blocks: [
        WmlTable(
          grid: [100, 100, 100],
          properties: WmlTableProps(rightToLeft: rtl),
          rows: [
            for (var row = 0; row < 3; row++)
              WmlTableRow(
                height: 70,
                cantSplit: true,
                cells: [
                  WmlTableCell(
                    gridSpan: 2,
                    vMerge: row == 0 ? WmlVMerge.restart : WmlVMerge.cont,
                    fillColor: 'FFEEDD',
                    blocks: [_paragraph(row == 0 ? 'Master source' : '')],
                  ),
                  WmlTableCell(blocks: [_paragraph('Neighbor $row')]),
                ],
              ),
            WmlTableRow(
              height: 70,
              cantSplit: true,
              cells: [
                WmlTableCell(
                  gridSpan: 3,
                  blocks: [_paragraph('Independent final row')],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<RenderWordCanvas> _mount(
  WidgetTester tester,
  WmlDocument document,
  LaidOutDocument layout,
  CaretEngine caret,
  VirtualViewport viewport,
  List<OfficeContextHit> hits,
) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 650,
          height: 500,
          child: WordCanvas(
            document: document,
            laidOut: layout,
            caret: caret,
            viewport: viewport,
            config: const OfficeSurfaceConfig(showRulers: false),
            onContextMenu: hits.add,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return tester.renderObject<RenderWordCanvas>(find.byType(WordCanvas));
}

Future<void> _rightClick(
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
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
}

void main() {
  setUpAll(OfficeHostFonts.ensureRegistered);
  for (final rtl in [false, true]) {
    for (final reopen in [false, true]) {
      testWidgets(
        '${reopen ? 'reopened' : 'live'} ${rtl ? 'RTL' : 'LTR'} vertical fragments hit the master on both pages and at continuation seams',
        (tester) async {
          var document = _document(rtl);
          if (reopen) {
            document = WordDeserializer().readBytes(
              WordSerializer().writeBytes(document),
            );
          }
          final table = document.sections.single.blocks.single as WmlTable;
          final master =
              table.rows.first.cells.first.blocks.single as WmlParagraph;
          final paragraphs = document.paragraphs.toList();
          final masterIndex = paragraphs.indexOf(master);
          final layout = WordLayoutEngine(font: null).layout(document);
          expect(layout.pages, hasLength(2));
          final caret = CaretEngine()..paragraphIndex = masterIndex;
          final viewport = VirtualViewport();
          final hits = <OfficeContextHit>[];
          final canvas = await _mount(
            tester,
            document,
            layout,
            caret,
            viewport,
            hits,
          );

          for (final page in layout.pages) {
            final neighbors = page.frames
                .where(
                  (box) =>
                      identical(box.table, table) &&
                      box.tableCol == 1 &&
                      box.height > 0,
                )
                .toList();
            expect(neighbors, isNotEmpty);
            final left = rtl
                ? neighbors.first.x + neighbors.first.width
                : neighbors.first.x - 200;
            final x = left + 100;
            viewport.origin = Offset(
              0,
              layout.pageStackTop(page.index, 96 / 72),
            );
            final samples = <Offset>[
              // The second page has no master text, so its visible fragment
              // must still own the original editable paragraph.
              Offset(x, neighbors.last.y + neighbors.last.height / 2),
              if (page.index == 0)
                // A hidden continuation box has zero height at this seam.
                Offset(x, neighbors.last.y),
            ];
            for (final point in samples) {
              final global = canvas.localToGlobal(
                canvas.windowForPagePoint(page.index, point),
              );
              expect(
                tester.getRect(find.byType(WordCanvas)).contains(global),
                isTrue,
              );
              await tester.tapAt(global);
              await tester.pump();
              expect(caret.paragraphIndex, masterIndex);
              expect(caret.isCollapsed, isTrue);
              await _rightClick(tester, canvas, page.index, point);
              expect(hits.last.kind, OfficeContextKind.table);
              expect(hits.last.table, same(table));
              expect((hits.last.tableRow, hits.last.tableCol), (0, 0));
            }

            // Adjacent source content retains its own physical row and cell.
            final neighbor = neighbors.last;
            final row = neighbor.tableRow!;
            final paragraph =
                table.rows[row].cells.last.blocks.single as WmlParagraph;
            final point = Offset(
              neighbor.x + neighbor.width / 2,
              neighbor.y + neighbor.height / 2,
            );
            await tester.tapAt(
              canvas.localToGlobal(
                canvas.windowForPagePoint(page.index, point),
              ),
            );
            await tester.pump();
            expect(caret.paragraphIndex, paragraphs.indexOf(paragraph));
            await _rightClick(tester, canvas, page.index, point);
            expect((hits.last.tableRow, hits.last.tableCol), (row, 1));
          }

          caret
            ..paragraphIndex = masterIndex
            ..logicalIndex = 3
            ..collapseSelection();
          final keyboard = canvas.contextHitForCaret()!;
          expect(keyboard.kind, OfficeContextKind.table);
          expect(keyboard.paragraph, same(master));
          expect(keyboard.table, same(table));
          expect((keyboard.tableRow, keyboard.tableCol), (0, 0));
          for (final row in table.rows.skip(1).take(2)) {
            expect(
              (row.cells.first.blocks.single as WmlParagraph).text,
              isEmpty,
            );
          }
          expect(master.text, 'Master source');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final (name, move)
      in <(String, void Function(WordEditorController, int))>[
        ('logical', (controller, delta) => controller.moveCaret(delta)),
        (
          'visual',
          (controller, delta) => controller.moveCaretVisual(toRight: delta > 0),
        ),
        ('vertical', (controller, delta) => controller.moveCaretLine(delta)),
        ('paragraph', (controller, delta) => controller.moveParagraph(delta)),
      ]) {
    for (final delta in [-1, 1]) {
      test(
        '$name ${delta > 0 ? 'forward' : 'backward'} navigation skips a native vertical continuation',
        () {
          final document = _document(false);
          final table = document.sections.single.blocks.single as WmlTable;
          final controller = WordEditorController(document: document);
          controller.proofing.enabled = false;
          addTearDown(controller.dispose);
          final paragraphs = document.paragraphs.toList();
          final first = table.rows[0].cells[1].blocks.single as WmlParagraph;
          final second = table.rows[1].cells[1].blocks.single as WmlParagraph;
          final from = delta > 0 ? first : second;
          final to = delta > 0 ? second : first;
          controller.caret
            ..paragraphIndex = paragraphs.indexOf(from)
            ..logicalIndex = delta > 0 ? from.text.length : 0
            ..collapseSelection();
          move(controller, delta);
          expect(controller.caret.paragraphIndex, paragraphs.indexOf(to));
          expect(controller.tableAtCaret?.col, 1);
          expect(
            (table.rows[1].cells.first.blocks.single as WmlParagraph).text,
            isEmpty,
          );
          expect(controller.canUndo, isFalse);
        },
      );
    }
  }
  for (final (name, move) in <(String, void Function(WordEditorController))>[
    ('logical', (controller) => controller.moveCaret(1)),
    ('paragraph', (controller) => controller.moveParagraph(1)),
  ]) {
    for (final kind in [
      'ordinary empty',
      'orphan',
      'authored text',
      'bookmark',
      'paragraph bookmark',
      'empty field',
      'multiple paragraphs',
    ]) {
      test('$name navigation retains an $kind cell paragraph', () {
        final document = _document(false);
        final table = document.sections.single.blocks.single as WmlTable;
        final target = table.rows[1].cells.first.blocks.single as WmlParagraph;
        switch (kind) {
          case 'ordinary empty':
            table.rows[1].cells.first.vMerge = WmlVMerge.none;
            table.rows[2].cells.first.vMerge = WmlVMerge.none;
          case 'orphan':
            table.rows.first.cells.first.vMerge = WmlVMerge.none;
          case 'authored text':
            target.inlines = [WmlRun(text: 'Retained imported content')];
          case 'bookmark':
            target.inlines = [
              WmlBookmarkBoundary(id: '17', isStart: true, name: 'Retained'),
              WmlBookmarkBoundary(id: '17', isStart: false),
            ];
          case 'paragraph bookmark':
            target.properties.bookmarkName = 'Retained';
          case 'empty field':
            target.inlines = [
              WmlRun(fieldInstruction: 'REF Retained', fieldLocked: true),
            ];
          case 'multiple paragraphs':
            table.rows[1].cells.first.blocks.add(_paragraph(''));
        }
        final controller = WordEditorController(document: document);
        controller.proofing.enabled = false;
        addTearDown(controller.dispose);
        final paragraphs = document.paragraphs.toList();
        final before =
            table.rows.first.cells.last.blocks.single as WmlParagraph;
        controller.caret
          ..paragraphIndex = paragraphs.indexOf(before)
          ..logicalIndex = before.text.length
          ..collapseSelection();
        move(controller);
        expect(controller.caret.paragraphIndex, paragraphs.indexOf(target));
        expect(controller.canUndo, isFalse);
        if (kind == 'authored text') {
          expect(target.text, 'Retained imported content');
        }
        if (kind == 'bookmark') {
          expect(target.inlines.whereType<WmlBookmarkBoundary>(), hasLength(2));
        }
      });
    }
  }

  test(
    'logical and paragraph steps cross multiple continuation placeholders without changing model indexes',
    () {
      final document = _document(false);
      final table = document.sections.single.blocks.single as WmlTable;
      final controller = WordEditorController(document: document);
      controller.proofing.enabled = false;
      addTearDown(controller.dispose);
      final paragraphs = document.paragraphs.toList();
      final first = table.rows.first.cells.last.blocks.single as WmlParagraph;
      final last = table.rows[2].cells.last.blocks.single as WmlParagraph;
      final initialIndexes = [
        for (final paragraph in paragraphs)
          document.paragraphs.toList().indexOf(paragraph),
      ];
      controller.caret
        ..paragraphIndex = paragraphs.indexOf(first)
        ..logicalIndex = first.text.length
        ..collapseSelection();
      controller.moveParagraph(2, extend: true);
      expect(controller.caret.paragraphIndex, paragraphs.indexOf(last));
      expect(
        controller.caret.selectionAnchorParagraph,
        paragraphs.indexOf(first),
      );
      expect(controller.caret.selectionAnchor, first.text.length);
      controller.moveParagraph(-2);
      expect(controller.caret.paragraphIndex, paragraphs.indexOf(first));
      controller.moveCaret(1 + 'Neighbor 1'.length + 1);
      expect(controller.caret.paragraphIndex, paragraphs.indexOf(last));
      expect(controller.caret.logicalIndex, 0);
      expect([
        for (final paragraph in paragraphs)
          document.paragraphs.toList().indexOf(paragraph),
      ], initialIndexes);
      expect(controller.canUndo, isFalse);
    },
  );
}
