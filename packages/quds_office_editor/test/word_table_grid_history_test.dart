import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'omitted-grid edits reject before dirty state, selection or history',
    () {
      final table = WmlTable(
        grid: [60, 60, 60, 60],
        rows: [
          for (var row = 0; row < 2; row++)
            WmlTableRow(
              gridBefore: 1,
              gridAfter: 1,
              cells: [
                WmlTableCell(blocks: [_paragraph('First $row')]),
                WmlTableCell(blocks: [_paragraph('Second $row')]),
              ],
            ),
        ],
      );
      final controller = WordEditorController(
        document: WmlDocument(
          sections: [
            WmlSection(blocks: [table]),
          ],
        ),
      );
      addTearDown(controller.dispose);
      final rows = List<WmlTableRow>.of(table.rows);
      final first = rows.first.cells.first.blocks.single as WmlParagraph;
      final revision = controller.contentRevision;
      final position = (
        controller.caret.paragraphIndex,
        controller.caret.logicalIndex,
      );
      for (final action in <void Function()>[
        () => controller.insertTableRowAt(table, 1),
        () => controller.insertTableColumnAt(table, 1),
        () => controller.deleteTableRow(table: table, row: 0),
        () => controller.deleteTableColumn(table: table, col: 0),
        for (final mode in WordTableAutoFit.values)
          () => controller.autoFitTable(mode, table: table),
        () {
          controller.beginTableResize(table);
          controller.previewTableColumnWidth(table, 1, 200);
          controller.previewTableRowHeight(table, 0, 100);
          controller.commitTableResize(table);
        },
      ]) {
        action();
        expect(table.rows, orderedEquals(rows));
        expect(table.grid, [60, 60, 60, 60]);
        expect(rows.map((row) => row.cells.length), [2, 2]);
        expect(rows.map((row) => (row.gridBefore, row.gridAfter)), [
          (1, 1),
          (1, 1),
        ]);
        expect(rows.first.height, isNull);
        expect(rows.first.cells.first.blocks.single, same(first));
        expect(controller.contentRevision, revision);
        expect(controller.isDirty, isFalse);
        expect(controller.canUndo, isFalse);
        expect((
          controller.caret.paragraphIndex,
          controller.caret.logicalIndex,
        ), position);
      }
      // Ordinary paragraph edits and their history remain available.
      controller.insertText('Edited ');
      expect(first.text, 'Edited First 0');
      controller.undo();
      expect(first.text, 'First 0');
      controller.redo();
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      final saved = reopened.sections.single.blocks.single as WmlTable;
      expect(saved.rows.map((row) => (row.gridBefore, row.gridAfter)), [
        (1, 1),
        (1, 1),
      ]);
      expect(
        (saved.rows.first.cells.first.blocks.single as WmlParagraph).text,
        'Edited First 0',
      );
    },
  );

  test('partial vertical merge rejects without creating an undo step', () {
    final first = _paragraph('Top');
    final second = _paragraph('Right');
    final table = WmlTable(
      grid: [60, 60],
      rows: [
        WmlTableRow(
          cells: [
            WmlTableCell(vMerge: WmlVMerge.restart, blocks: [first]),
            WmlTableCell(blocks: [second]),
          ],
        ),
        WmlTableRow(
          cells: [
            WmlTableCell(vMerge: WmlVMerge.cont, blocks: [_paragraph('')]),
            WmlTableCell(blocks: [_paragraph('Bottom')]),
          ],
        ),
      ],
    );
    final controller = WordEditorController(
      document: WmlDocument(
        sections: [
          WmlSection(blocks: [table]),
        ],
      ),
    );
    addTearDown(controller.dispose);
    controller.caret
      ..selectionAnchorParagraph = 0
      ..selectionAnchor = 0
      ..paragraphIndex = 1
      ..logicalIndex = second.text.length;
    expect(controller.canMergeTableCells, isFalse);
    controller.mergeTableCells();
    expect(table.rows.map((row) => row.cells.length), [2, 2]);
    expect(table.rows.first.cells.first.blocks, [same(first)]);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    expect(controller.contentRevision, 0);
  });
}
