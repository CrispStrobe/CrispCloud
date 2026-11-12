import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WordEditorController _withTable(WmlTable table) {
  final controller = WordEditorController(
    document: WmlDocument(
      sections: [
        WmlSection(blocks: [_paragraph('Body'), table]),
      ],
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

WmlTable _table() => WmlTable(
  grid: [90, 90],
  rows: [
    for (final names in [
      ['A', 'B'],
      ['C', 'D'],
    ])
      WmlTableRow(
        cells: [
          for (final name in names) WmlTableCell(blocks: [_paragraph(name)]),
        ],
      ),
  ],
);

void _at(
  WordEditorController controller,
  WmlParagraph paragraph, [
  int offset = 0,
]) {
  controller.jumpToParagraph(
    controller.document.paragraphs.toList().indexOf(paragraph),
  );
  controller.caret.logicalIndex = offset;
  controller.caret.collapseSelection();
}

void _replay(WordEditorController controller, int steps) {
  for (var i = 0; i < steps; i++) {
    controller.undo();
  }
  for (var i = 0; i < steps; i++) {
    controller.redo();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final column in [false, true]) {
    test(
      'insert ${column ? 'column' : 'row'}, type and link survive structural replay',
      () {
        final table = _table();
        final original = table.rows.first.cells.first.blocks.single;
        final controller = _withTable(table);
        if (column) {
          controller.insertTableColumnAt(table, 1);
        } else {
          controller.insertTableRowAt(table, 1);
        }
        final inserted =
            table.rows[column ? 0 : 1].cells[column ? 1 : 0].blocks.first
                as WmlParagraph;
        controller.insertText('Inserted');
        controller.selectParagraphAtCaret();
        controller.insertHyperlink(
          text: '',
          target: 'https://example.com/cell',
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(table.rows.length, column ? 2 : 3);
          expect(table.rows.first.cells.length, column ? 3 : 2);
          expect(table.rows.first.cells.first.blocks.single, same(original));
          expect(
            table.rows[column ? 0 : 1].cells[column ? 1 : 0].blocks.first,
            same(inserted),
          );
          expect(inserted.text, 'Inserted');
          expect(
            inserted.inlines.whereType<WmlRun>().single.hyperlink?.url,
            'https://example.com/cell',
          );
          _replay(controller, 3);
        }
        final reopened = WordDeserializer().readBytes(controller.saveBytes());
        final imported = reopened.sections.single.blocks
            .whereType<WmlTable>()
            .single;
        expect(
          (imported.rows[column ? 0 : 1].cells[column ? 1 : 0].blocks.first
                  as WmlParagraph)
              .text,
          'Inserted',
        );
      },
    );
  }

  test(
    'delete a row, edit a survivor and repeatedly restore original topology',
    () {
      final table = _table();
      final survivor =
          table.rows.last.cells.first.blocks.single as WmlParagraph;
      final controller = _withTable(table);
      controller.deleteTableRow(table: table, row: 0);
      _at(controller, survivor, 1);
      controller.insertText(' edited');
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(table.rows, hasLength(1));
        expect(table.rows.first.cells.first.blocks.single, same(survivor));
        expect(survivor.text, 'C edited');
        controller.undo();
        controller.undo();
        expect(table.rows, hasLength(2));
        expect(
          (table.rows.first.cells.first.blocks.single as WmlParagraph).text,
          'A',
        );
        expect(table.rows.last.cells.first.blocks.single, same(survivor));
        controller.redo();
        controller.redo();
      }
    },
  );

  test(
    'resizing a table preserves nested frame and drawing history targets',
    () {
      final frameParagraph = _paragraph('Frame');
      final frame = WmlFrame(blocks: [frameParagraph]);
      final visual = WmlVisual(
        visual: OfficeVisual(
          kind: OfficeVisualKind.chartColumn,
          title: 'Chart',
          points: OfficeVisual.sampleSeries(),
        ),
      );
      final table = _table();
      table.rows.first.cells.first.blocks.addAll([frame, visual]);
      final controller = _withTable(table);
      controller.beginTableResize(table);
      controller.previewTableColumnWidth(table, 0, 140);
      controller.commitTableResize(table);
      expect(table.rows.first.cells.first.blocks, containsAll([frame, visual]));
      _at(controller, frameParagraph, 5);
      controller.insertText(' edited');
      controller.selectFrame(frame);
      controller.nudgeSelectedFrame(dx: 15, dy: 20);
      controller.selectVisual(visual);
      controller.updateSelectedVisual(title: 'Updated chart');
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(table.grid.first, 140);
        expect(frameParagraph.text, 'Frame edited');
        expect(frame.x, 87);
        expect(frame.y, 92);
        expect(visual.visual.title, 'Updated chart');
        _replay(controller, 4);
        expect(
          table.rows.first.cells.first.blocks,
          containsAll([frame, visual]),
        );
      }
    },
  );

  test('merge then edit a moved paragraph survives undo and redo', () {
    final table = _table();
    final controller = _withTable(table);
    final first = table.rows.first.cells.first.blocks.single as WmlParagraph;
    final second = table.rows.first.cells.last.blocks.single as WmlParagraph;
    final paragraphs = controller.document.paragraphs.toList();
    controller.caret
      ..selectionAnchorParagraph = paragraphs.indexOf(first)
      ..selectionAnchor = 0
      ..paragraphIndex = paragraphs.indexOf(second)
      ..logicalIndex = second.text.length;
    controller.mergeTableCells();
    final mergedParagraph =
        table.rows.first.cells.first.blocks.last as WmlParagraph;
    _at(controller, mergedParagraph, 1);
    controller.insertText(' merged');
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(table.rows.first.cells, hasLength(1));
      expect(table.rows.first.cells.first.gridSpan, 2);
      expect(mergedParagraph.text, 'B merged');
      _replay(controller, 2);
      expect(table.rows.first.cells.first.blocks.last, same(mergedParagraph));
    }
  });

  for (final story in ['header', 'footer', 'comment']) {
    test(
      '$story range deletion joins endpoints, preserves links and isolates body',
      () {
        final controller = WordEditorController(
          document: WmlDocument.empty(text: 'Untouched body'),
        );
        addTearDown(controller.dispose);
        final first = _paragraph('First prefix');
        final middle = _paragraph('Middle');
        final last = _paragraph('Last suffix');
        final link = WmlHyperlink(url: 'https://example.com/story');
        last.inlines.whereType<WmlRun>().single.hyperlink = link;
        final List<WmlParagraph> parent;
        if (story == 'comment') {
          controller.document.comments.add(
            WmlComment(id: 7, paragraphs: [first, middle, last]),
          );
          controller.beginCommentEdit(7);
          parent = controller.document.comments.single.paragraphs;
        } else {
          final section = controller.document.sections.single;
          parent = story == 'header' ? section.header : section.footer;
          parent.addAll([first, middle, last]);
          controller.beginHeaderFooterEdit(0, footer: story == 'footer');
        }
        controller.caret
          ..selectionAnchorParagraph = 0
          ..selectionAnchor = 6
          ..paragraphIndex = 2
          ..logicalIndex = 5;
        controller.deleteSelectionOr(backward: false);
        expect(parent.map((p) => p.text), ['First suffix']);
        expect(
          first.inlines
              .whereType<WmlRun>()
              .where((r) => r.hyperlink != null)
              .single
              .text,
          'suffix',
        );
        expect(controller.document.paragraphs.single.text, 'Untouched body');
        if (story == 'comment') {
          controller.endCommentEdit();
        } else {
          controller.endHeaderFooterEdit();
        }
        for (var cycle = 0; cycle < 3; cycle++) {
          controller.undo();
          expect(parent, [first, middle, last]);
          expect(parent.map((p) => p.text), [
            'First prefix',
            'Middle',
            'Last suffix',
          ]);
          controller.redo();
          expect(parent.map((p) => p.text), ['First suffix']);
          expect(controller.document.paragraphs.single.text, 'Untouched body');
        }
      },
    );

    test(
      '$story backspace joins paragraphs without dropping hyperlink metadata',
      () {
        final controller = WordEditorController(
          document: WmlDocument.empty(text: 'Body'),
        );
        addTearDown(controller.dispose);
        final first = _paragraph('One');
        final second = _paragraph('Two');
        second.inlines.whereType<WmlRun>().single.hyperlink = WmlHyperlink(
          url: 'https://example.com/two',
        );
        final List<WmlParagraph> parent;
        if (story == 'comment') {
          controller.document.comments.add(
            WmlComment(id: 7, paragraphs: [first, second]),
          );
          controller.beginCommentEdit(7);
          parent = controller.document.comments.single.paragraphs;
        } else {
          final section = controller.document.sections.single;
          parent = story == 'header' ? section.header : section.footer;
          parent.addAll([first, second]);
          controller.beginHeaderFooterEdit(0, footer: story == 'footer');
        }
        controller.caret
          ..paragraphIndex = 1
          ..logicalIndex = 0
          ..collapseSelection();
        controller.deleteSelectionOr(backward: true);
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(parent.map((p) => p.text), ['OneTwo']);
          expect(
            first.inlines
                .whereType<WmlRun>()
                .where((r) => r.hyperlink != null)
                .single
                .text,
            'Two',
          );
          expect(controller.document.paragraphs.single.text, 'Body');
          _replay(controller, 1);
        }
      },
    );
  }

  test(
    'body paragraph join preserves native note and hyperlink identities',
    () {
      final controller = WordEditorController(
        document: WmlDocument.empty(text: 'One'),
      );
      addTearDown(controller.dispose);
      final second = WmlParagraph(
        inlines: [
          WmlRun(
            text: 'Two',
            hyperlink: WmlHyperlink(url: 'https://example.com/two'),
          ),
          WmlRun(
            text: '12',
            noteRefId: 12,
            properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
          ),
          WmlRun(
            text: 'Reference',
            fieldInstruction: ' REF bookmark ',
            fieldLocked: true,
            fieldDirty: false,
          ),
        ],
      );
      controller.document.footnotes.add(
        WmlNote(id: 12, endnote: false)..text = 'A note',
      );
      controller.document.sections.single.blocks.add(second);
      controller.relayout();
      _at(controller, second);
      controller.deleteSelectionOr(backward: true);
      for (var cycle = 0; cycle < 3; cycle++) {
        final runs = controller.document.paragraphs.single.inlines
            .whereType<WmlRun>();
        expect(runs.where((r) => r.noteRefId != null).single.noteRefId, 12);
        expect(runs.where((r) => r.hyperlink != null).single.text, 'Two');
        final field = runs.where((r) => r.fieldInstruction != null).single;
        expect(field.fieldInstruction, ' REF bookmark ');
        expect(field.fieldLocked, isTrue);
        expect(field.fieldDirty, isFalse);
        _replay(controller, 1);
      }
    },
  );
}
