import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

// Synthetic native ODT marks, not installed Zotero/LibreOffice output.
String _citation(String id, String text) {
  final name = encodeXmlAttribute(
    'ZOTERO_ITEM CSL_CITATION ${jsonEncode({
      'citationID': id,
      'citationItems': [
        {
          'id': id,
          'locator': '9',
          'itemData': {'id': id, 'type': 'book', 'title': 'Source $id'},
        },
      ],
      'properties': {'plainCitation': text},
    })} RND0123456789',
  );
  return '<text:reference-mark-start text:name="$name"/>'
      '${encodeXmlText(text)}<text:reference-mark-end text:name="$name"/>';
}

Uint8List _odt({bool hiddenContent = false}) {
  const covered = '<table:covered-table-cell/>';
  final coveredOrHidden = hiddenContent
      ? '<table:covered-table-cell><text:p>Hidden work</text:p>'
            '</table:covered-table-cell>'
      : covered;
  return (ZipWriter()
        ..addFile(
          'mimetype',
          utf8.encode('application/vnd.oasis.opendocument.text'),
          store: true,
        )
        ..addFile(
          'content.xml',
          utf8.encode(
            '<office:document-content '
            'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
            'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
            'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
            'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0">'
            '<office:automatic-styles>'
            '<style:style style:name="C1" style:family="table-column">'
            '<style:table-column-properties style:column-width="80pt"/>'
            '</style:style>'
            '<style:style style:name="C2" style:family="table-column">'
            '<style:table-column-properties style:column-width="100pt"/>'
            '</style:style>'
            '<style:style style:name="C3" style:family="table-column">'
            '<style:table-column-properties style:column-width="120pt"/>'
            '</style:style>'
            '</office:automatic-styles><office:body><office:text>'
            '<text:p>Before table</text:p><table:table>'
            '<table:table-column table:style-name="C1"/>'
            '<table:table-column table:style-name="C2"/>'
            '<table:table-column table:style-name="C3"/>'
            '<table:table-row>'
            '<table:table-cell table:number-columns-spanned="2" '
            'table:number-rows-spanned="2">'
            '<text:p>Origin ${_citation('first', '(First)')}</text:p>'
            '</table:table-cell>$coveredOrHidden'
            '<table:table-cell><text:p>${_citation('second', '(Second)')}'
            '</text:p></table:table-cell></table:table-row>'
            '<table:table-row>$covered$covered'
            '<table:table-cell><text:p>Neighbor</text:p></table:table-cell>'
            '</table:table-row><table:table-row>'
            '<table:table-cell table:number-columns-spanned="3">'
            '<text:p>${_citation('third', '(Third)')}</text:p>'
            '</table:table-cell>$covered$covered</table:table-row>'
            '</table:table><text:p>After table</text:p>'
            '</office:text></office:body></office:document-content>',
          ),
        ))
      .close();
}

WordEditorController _controller() {
  final controller = WordEditorController(
    document: WmlDocument.empty(text: 'Retain this draft'),
    proofingService: OfficeProofingService(providers: []),
  );
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return controller;
}

WmlTable _expectTopology(WmlDocument document) {
  final table = document.sections.single.blocks.whereType<WmlTable>().single;
  expect(table.grid, [80.0, 100.0, 120.0]);
  expect(table.rows.map((row) => row.cells.map((cell) => cell.gridSpan)), [
    [2, 1],
    [2, 1],
    [3],
  ]);
  expect(table.rows.first.cells.first.vMerge, WmlVMerge.restart);
  expect(table.rows[1].cells.first.vMerge, WmlVMerge.cont);
  expect(table.rows.last.cells.single.vMerge, WmlVMerge.none);
  expect(table.rows.first.cells.first.width, 180);
  expect(table.rows[1].cells.first.width, 180);
  expect(table.rows.last.cells.single.width, 300);
  expect(
    WordTree.paragraphs(table.rows[1].cells.first.blocks).single.text,
    isEmpty,
  );
  expect(WordTable.supportsGridAddressing(table), isTrue);
  for (var row = 0; row < 2; row++) {
    for (var column = 0; column < 2; column++) {
      expect(
        WordTable.cellAtGrid(table, row, column)!.cell,
        same(table.rows.first.cells.first),
      );
    }
  }
  expect(WordFieldSpans.unbalanced(document), isEmpty);
  return table;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native merged ODT loads, reveals and edits the origin citation',
    () async {
      final bytes = _odt();
      final originalBytes = Uint8List.fromList(bytes);
      final controller = _controller()..insertText('Draft ');
      final previous = controller.document;
      await controller.loadBytesAsync(
        bytes,
        onProgress: (_) => expect(controller.document, same(previous)),
      );
      final table = _expectTopology(controller.document);
      final fields = controller.zoteroFields;
      expect(fields.map((field) => field.citation!.citationId), [
        'first',
        'second',
        'third',
      ]);
      expect(
        fields.first.paragraph,
        same(table.rows.first.cells.first.blocks.single),
      );
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(controller.revealZoteroField(fields.first), isTrue);
      expect(controller.zoteroFieldAtCaret!.citation!.citationId, 'first');

      controller.updateZoteroCitation(
        fields.first,
        fields.first.citation!.withItems(
          fields.first.citation!.items,
          plainCitation: '(First, p. 9)',
        ),
      );
      expect(controller.zoteroFields.first.cachedText, '(First, p. 9)');
      expect(controller.isDirty, isTrue);
      _expectTopology(controller.document);
      controller.unlinkZoteroField(controller.zoteroFields.first);
      expect(
        controller.zoteroFields.map((field) => field.citation!.citationId),
        ['second', 'third'],
      );
      expect(
        WordTree.paragraphs(table.rows.first.cells.first.blocks).single.text,
        'Origin (First, p. 9)',
      );
      controller.undo();
      expect(controller.zoteroFields.first.cachedText, '(First, p. 9)');
      controller.undo();
      expect(controller.zoteroFields.first.cachedText, '(First)');
      controller.redo();
      expect(controller.zoteroFields.first.cachedText, '(First, p. 9)');
      _expectTopology(controller.document);

      final saved = controller.saveBytes();
      expect(OdtDocumentReader.isOdt(saved), isFalse);
      final reopened = _controller();
      await reopened.loadBytesAsync(saved);
      _expectTopology(reopened.document);
      expect(reopened.zoteroFields.map((field) => field.cachedText), [
        '(First, p. 9)',
        '(Second)',
        '(Third)',
      ]);
      expect(reopened.zoteroFields.every((field) => field.canEdit), isTrue);
      expect(bytes, originalBytes);
    },
  );

  test(
    'hidden covered content refuses before replacing current work',
    () async {
      final controller = _controller()..insertText('Draft ');
      final original = controller.document;
      final revision = controller.contentRevision;
      final caret = controller.caret.logicalIndex;
      await expectLater(
        controller.loadBytesAsync(_odt(hiddenContent: true)),
        throwsA(isA<StateError>()),
      );
      expect(controller.document, same(original));
      expect(controller.contentRevision, revision);
      expect(controller.caret.logicalIndex, caret);
      expect(controller.isDirty, isTrue);
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'Retain this draft');
    },
  );

  test(
    'an edit during merged ODT loading invalidates its pending result',
    () async {
      final controller = _controller();
      final original = controller.document;
      var edited = false;
      await expectLater(
        controller.loadBytesAsync(
          _odt(),
          onProgress: (_) {
            if (edited) return;
            edited = true;
            controller.insertText('Newer ');
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(controller.document, same(original));
      expect(
        controller.document.paragraphs.single.text,
        'Newer Retain this draft',
      );
      expect(controller.zoteroFields, isEmpty);
      expect(controller.canUndo, isTrue);
    },
  );
}
