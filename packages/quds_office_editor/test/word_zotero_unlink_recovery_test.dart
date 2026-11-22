import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _damaged = ' ADDIN ZOTERO_ITEM CSL_CITATION {broken} ';
const _schemaDamaged =
    ' ADDIN ZOTERO_ITEM CSL_CITATION '
    '{"citationID":"broken-schema","citationItems":"not-a-list"} ';
const _damagedBibliography = ' ADDIN ZOTERO_BIBL {broken} CSL_BIBLIOGRAPHY ';

ZoteroCitation _citation(String id) => ZoteroCitation(
  citationId: id,
  plainCitation: '($id)',
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

WmlParagraph _damagedParagraph({String shape = 'atomic'}) {
  final paragraph = WmlParagraph();
  if (shape == 'paragraph') {
    paragraph.properties
      ..fieldInstruction = _damaged
      ..fieldBegin = true
      ..fieldSeparate = true
      ..fieldEnd = true;
  } else {
    paragraph.inlines.add(WmlRun(text: 'Before '));
  }
  if (shape == 'complex') {
    paragraph.inlines.addAll([
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: _damaged),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
      WmlRun(text: 'Alpha', properties: WmlRunProps(italic: true)),
      WmlRun(text: ' Beta', properties: WmlRunProps(bold: true)),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
    ]);
  } else {
    paragraph.inlines.add(
      WmlRun(
        text: 'Alpha Beta',
        properties: WmlRunProps(italic: true),
        fieldInstruction: shape == 'paragraph'
            ? null
            : shape == 'schema'
            ? _schemaDamaged
            : _damaged,
      ),
    );
  }
  if (shape != 'paragraph') paragraph.inlines.add(WmlRun(text: ' after'));
  return paragraph;
}

List<WmlParagraph> _damagedBibliographyParagraphs() {
  final entries = WordZotero.nativeBibliographyParagraphs(
    instruction: ' ADDIN ZOTERO_BIBL {} CSL_BIBLIOGRAPHY ',
    text: 'First source\nSecond source',
    paragraphProperties: WmlParagraphProps(
      indent: const WmlIndent(left: 36, hanging: 36),
      lineSpacing: 2,
      spacingAfter: 12,
    ),
  );
  final index = entries.first.inlines.indexWhere(
    (inline) =>
        inline is WmlFieldBoundary &&
        inline.kind == WmlFieldBoundaryKind.instruction,
  );
  entries.first.inlines[index] = WmlFieldBoundary(
    kind: WmlFieldBoundaryKind.instruction,
    text: _damagedBibliography,
  );
  entries.first.inlines.whereType<WmlRun>().single.properties.italic = true;
  entries.last.inlines.whereType<WmlRun>().single.properties.bold = true;
  return entries;
}

WmlDocument _mixed({String shape = 'atomic'}) {
  final document = WmlDocument.empty(text: 'Healthy before ');
  WordZotero.insertCitation(document.paragraphs.single, _citation('healthy'));
  document.paragraphs.single.inlines.add(WmlRun(text: ' after'));
  document.sections.single.blocks.add(_damagedParagraph(shape: shape));
  document.zoteroDocumentData =
      '<data data-version="3"><style id="http://www.zotero.org/styles/apa" '
      'locale="en-US"/><prefs><pref name="fieldType" value="Field"/></prefs></data>';
  return document;
}

WordEditorController _controller(WmlDocument document) {
  final controller = WordEditorController(document: document);
  controller.proofing.enabled = false;
  addTearDown(controller.dispose);
  return controller;
}

Map<String, String> _xml(WmlDocument document) {
  // The first serialization seeds default note-separator source XML. A second
  // one captures its stable namespace declarations, independently of unlinking.
  WordSerializer().write(document);
  final package = WordSerializer().write(document);
  return {
    for (final part in package.parts)
      if (part.uri.startsWith('/word/') && part.uri.endsWith('.xml'))
        part.uri: part.readText(),
  };
}

List<WmlParagraph> _paragraphs(WmlDocument document) => [
  ...document.paragraphs,
  for (final note in [...document.footnotes, ...document.endnotes])
    ...note.allParagraphs,
  for (final section in document.sections) ...section.header,
];

String _visibleState(WmlDocument document) => jsonEncode([
  for (final paragraph in _paragraphs(document))
    [
      paragraph.text,
      paragraph.properties.indent.left,
      paragraph.properties.indent.hanging,
      paragraph.properties.lineSpacing,
      paragraph.properties.spacingAfter,
      for (final run in paragraph.inlines.whereType<WmlRun>())
        [
          run.text,
          run.properties.bold,
          run.properties.italic,
          run.noteRefId,
          run.noteRefEndnote,
        ],
    ],
]);

void _refusesWithoutHistoryChange(WordEditorController controller) {
  controller.caret.logicalIndex = 0;
  controller.caret.collapseSelection();
  controller.insertText('Draft ');
  controller.undo();
  final original = _xml(controller.document);
  final revision = controller.contentRevision;
  final fields = controller.zoteroFields
      .map((field) => (field.instruction, field.cachedText))
      .toList();
  expect(controller.canRedo, isTrue);
  expect(controller.unlinkZoteroFields, throwsUnsupportedError);
  expect(_xml(controller.document), original);
  expect(
    controller.zoteroFields.map(
      (field) => (field.instruction, field.cachedText),
    ),
    fields,
  );
  expect(controller.contentRevision, revision);
  expect(controller.canUndo, isFalse);
  expect(controller.canRedo, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final shape in ['atomic', 'complex', 'paragraph', 'schema']) {
    test('bulk unlink preserves healthy and damaged $shape results', () {
      final controller = _controller(_mixed(shape: shape));
      final document = controller.document;
      final original = _xml(document);
      final visible = _visibleState(document);
      final preferences = WordZoteroDocumentData.read(document);
      final paragraphs = _paragraphs(document);
      expect(controller.zoteroFields.map((field) => field.isValid), [
        true,
        false,
      ]);

      expect(controller.unlinkZoteroFields(), 2);
      expect(controller.zoteroFields, isEmpty);
      expect(_visibleState(document), visible);
      expect(_paragraphs(document), orderedEquals(paragraphs));
      expect(WordZoteroDocumentData.read(document), preferences);
      final converted = _xml(document);
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      expect(WordZotero.fields(reopened), isEmpty);
      expect(
        _paragraphs(reopened).map((paragraph) => paragraph.text),
        paragraphs.map((paragraph) => paragraph.text),
      );
      expect(
        reopened.paragraphs.last.inlines
            .whereType<WmlRun>()
            .where((run) => run.text.startsWith('Alpha'))
            .single
            .properties
            .italic,
        isTrue,
      );
      expect(WordZoteroDocumentData.read(reopened), preferences);
      controller.undo();
      expect(_xml(document), original);
      expect(controller.zoteroFields.map((field) => field.isValid), [
        true,
        false,
      ]);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_xml(document), converted);
    });
  }

  test('mixed table, notes and multipart bibliography convert in one step', () {
    final document = _mixed(shape: 'complex');
    final body = document.paragraphs.first;
    final cell = _damagedParagraph(shape: 'schema');
    document.sections.single.blocks.add(
      WmlTable(
        grid: [200],
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(blocks: [cell], width: 200),
            ],
          ),
        ],
      ),
    );
    for (final endnote in [false, true]) {
      final note = WordNotes.insert(
        document,
        body,
        text: 'Note ',
        endnote: endnote,
      );
      note.paragraphs.single.inlines.addAll(_damagedParagraph().inlines);
    }
    document.sections.single.blocks.addAll(_damagedBibliographyParagraphs());
    final header = WmlParagraph(inlines: [WmlRun(text: 'Header ')]);
    WordZotero.insertCitation(header, _citation('header'));
    document.sections.single.header.add(header);
    final controller = _controller(document);
    final original = _xml(document);
    final visible = _visibleState(document);
    final paragraphs = _paragraphs(document);
    final footnote = document.footnotes.single;
    final endnote = document.endnotes.single;
    final preferences = WordZoteroDocumentData.read(document);
    expect(controller.zoteroFields, hasLength(7));
    expect(
      controller.zoteroFields.where((field) => !field.isValid),
      hasLength(5),
    );

    expect(controller.unlinkZoteroFields(), 7);
    expect(controller.zoteroFields, isEmpty);
    expect(_visibleState(document), visible);
    expect(_paragraphs(document), orderedEquals(paragraphs));
    expect(document.footnotes.single, same(footnote));
    expect(document.endnotes.single, same(endnote));
    final converted = _xml(document);
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(WordZotero.fields(reopened), isEmpty);
    expect(reopened.footnotes.single.text, footnote.text);
    expect(reopened.endnotes.single.text, endnote.text);
    expect(reopened.sections.single.header.single.text, header.text);
    expect(
      reopened.paragraphs.map((paragraph) => paragraph.text),
      document.paragraphs.map((paragraph) => paragraph.text),
    );
    expect(WordZoteroDocumentData.read(reopened), preferences);
    final bibliography = reopened.paragraphs
        .where((p) => p.text == 'First source')
        .single;
    expect(bibliography.properties.indent.left, 36);
    expect(bibliography.properties.indent.hanging, 36);
    expect(
      bibliography.inlines.whereType<WmlRun>().single.properties.italic,
      isTrue,
    );

    for (var cycle = 0; cycle < 2; cycle++) {
      controller.undo();
      expect(_xml(document), original);
      expect(controller.zoteroFields, hasLength(7));
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_xml(document), converted);
      expect(_visibleState(document), visible);
    }
  });

  for (final unsafe in ['locked', 'nested', 'hyperlink', 'opaque']) {
    test(
      'a $unsafe damaged result blocks healthy fields and preserves redo',
      () {
        final document = _mixed(
          shape: unsafe == 'opaque' ? 'complex' : 'atomic',
        );
        final paragraph = document.paragraphs.last;
        final damaged = WordZotero.fields(document).last;
        switch (unsafe) {
          case 'locked':
            damaged.run!.fieldLocked = true;
          case 'nested':
            paragraph.inlines
              ..insert(0, WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin))
              ..insert(
                1,
                WmlFieldBoundary(
                  kind: WmlFieldBoundaryKind.instruction,
                  text: ' IF 1 = 1 ',
                ),
              )
              ..insert(2, WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate))
              ..add(WmlFieldBoundary(kind: WmlFieldBoundaryKind.end));
          case 'hyperlink':
            damaged.run!.hyperlink = const WmlHyperlink(
              url: 'https://example.org/',
            );
          case 'opaque':
            final index = paragraph.inlines.indexWhere(
              (inline) => inline is WmlFieldBoundary,
            );
            paragraph.inlines[index] = WmlFieldBoundary(
              kind: WmlFieldBoundaryKind.begin,
              runPropertiesXml: '<w:rPr><w:b/></w:rPr>',
            );
        }
        _refusesWithoutHistoryChange(_controller(document));
      },
    );
  }

  for (final alias in ['paragraph', 'run']) {
    test('shared damaged $alias ownership blocks the whole conversion', () {
      final document = _mixed();
      final damaged = WordZotero.fields(document).last;
      document.sections.single.blocks.add(
        alias == 'paragraph'
            ? damaged.paragraph
            : WmlParagraph(inlines: [damaged.run!]),
      );
      _refusesWithoutHistoryChange(_controller(document));
    });
  }

  for (final story in ['header', 'frame', 'comment']) {
    test('damaged metadata in an unsupported $story keeps all links', () {
      final document = _mixed();
      final paragraph = document.paragraphs.last;
      document.sections.single.blocks.remove(paragraph);
      switch (story) {
        case 'header':
          document.sections.single.header.add(paragraph);
        case 'frame':
          document.sections.single.blocks.add(WmlFrame(blocks: [paragraph]));
        case 'comment':
          final comment = WmlComment(id: 1, text: '');
          comment.paragraphs
            ..clear()
            ..add(paragraph);
          document.comments.add(comment);
      }
      _refusesWithoutHistoryChange(_controller(document));
    });
  }

  test('a damaged bibliography crossing cells blocks the whole conversion', () {
    final document = _mixed();
    final entries = _damagedBibliographyParagraphs();
    document.sections.single.blocks.add(
      WmlTable(
        grid: [100, 100],
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(blocks: [entries.first], width: 100),
              WmlTableCell(blocks: [entries.last], width: 100),
            ],
          ),
        ],
      ),
    );
    _refusesWithoutHistoryChange(_controller(document));
  });

  test('incomplete damage cannot be silently omitted from a mixed batch', () {
    final document = _mixed(shape: 'complex');
    document.paragraphs.last.inlines.removeWhere(
      (inline) =>
          inline is WmlFieldBoundary && inline.kind == WmlFieldBoundaryKind.end,
    );
    _refusesWithoutHistoryChange(_controller(document));
  });
}
