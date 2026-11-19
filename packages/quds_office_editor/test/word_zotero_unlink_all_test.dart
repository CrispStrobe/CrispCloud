import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

ZoteroCitation _citation(String id, String text) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'type': 'book', 'title': 'Source $id'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

WordEditorController _controller(
  WmlDocument document, {
  OfficeSurfaceConfig? config,
}) {
  final controller = WordEditorController(document: document, config: config);
  addTearDown(controller.dispose);
  return controller;
}

WmlDocument _twoFields() {
  final document = WmlDocument.empty(text: 'Before ');
  final paragraph = document.paragraphs.single;
  WordZotero.insertCitation(paragraph, _citation('a', '(A)'));
  paragraph.inlines.add(WmlRun(text: ' between '));
  WordZotero.insertCitation(paragraph, _citation('b', '(B)'));
  paragraph.inlines.add(WmlRun(text: ' after'));
  return document;
}

void _richCitation(WmlParagraph paragraph, String id) {
  final formatted = ZoteroFormattedText.fromHtml('<i>$id</i> <b>source</b>');
  final citation = _citation(id, formatted.plainText);
  WordZotero.insertNativeCitation(
    paragraph,
    instruction: citation.fieldInstruction,
    text: formatted.plainText,
    formattedText: formatted,
  );
}

List<WmlParagraph> _allParagraphs(WmlDocument document) => [
  ...document.paragraphs,
  for (final section in document.sections) ...[
    ...section.header,
    ...section.footer,
    ...section.firstHeader,
    ...section.firstFooter,
    ...section.evenHeader,
    ...section.evenFooter,
  ],
  for (final note in [...document.footnotes, ...document.endnotes])
    ...note.allParagraphs,
  for (final comment in document.comments) ...comment.paragraphs,
];

String _visibleState(WmlDocument document) => jsonEncode([
  for (final paragraph in _allParagraphs(document))
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
          run.properties.smallCaps,
          run.noteRefId,
          run.noteRefEndnote,
          run.hyperlink,
          run.commentIds,
        ],
    ],
]);

String _fieldState(WmlDocument document) => jsonEncode([
  for (final field in WordZotero.fields(document))
    [field.instruction, field.cachedText, field.start, field.end],
]);

WmlOpaqueBlock _opaque(String xml) => WmlOpaqueBlock(
  xml: xml,
  sourcePartUri: '/word/header1.xml',
  relationships: [],
);

const _complexOpaque =
    '<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>'
    '<w:r><w:instrText> ADDIN ZOTE</w:instrText></w:r>'
    '<w:r><w:instrText>RO_ITEM CSL_CITATION {}</w:instrText></w:r>'
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
    '<w:r><w:t>Preserved source</w:t></w:r>'
    '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p></w:hdr>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all story fields retain formatting and notes in one undo step', () {
    final document = _twoFields();
    final body = document.paragraphs.single;
    for (final endnote in [false, true]) {
      final note = WordNotes.insert(
        document,
        body,
        text: 'Note: ',
        endnote: endnote,
      );
      _richCitation(note.paragraphs.single, endnote ? 'Endnote' : 'Footnote');
    }
    final header = WmlParagraph(inlines: [WmlRun(text: 'Header ')]);
    _richCitation(header, 'Header');
    document.sections.single.header.add(header);
    final comment = WmlComment(id: 1, text: 'Comment ');
    _richCitation(comment.paragraphs.single, 'Comment');
    document.comments.add(comment);
    final instruction = WordZotero.bibliography(
      text: 'unused',
    ).inlines.whereType<WmlRun>().single.fieldInstruction!;
    final bibliography = [
      WmlParagraph(
        properties: WmlParagraphProps(
          indent: const WmlIndent(left: 36, hanging: 36),
          lineSpacing: 2,
          spacingAfter: 12,
        ),
        inlines: [
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: instruction,
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlRun(text: 'First source', properties: WmlRunProps(italic: true)),
        ],
      ),
      WmlParagraph(
        inlines: [
          WmlRun(text: 'Second source', properties: WmlRunProps(bold: true)),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
        ],
      ),
    ];
    document.sections.single.blocks.addAll(bibliography);
    document.zoteroDocumentData =
        '<data data-version="3"><style id="http://www.zotero.org/styles/apa" '
        'locale="en-US"/><prefs><pref name="fieldType" value="Field"/></prefs></data>';
    final controller = _controller(document);
    final visible = _visibleState(document);
    final fields = _fieldState(document);
    final preferences = WordZoteroDocumentData.read(document);
    final paragraphs = _allParagraphs(document);
    final footnote = document.footnotes.single;
    final endnote = document.endnotes.single;
    final revision = controller.contentRevision;
    expect(controller.zoteroFields, hasLength(7));

    expect(controller.unlinkZoteroFields(), 7);
    expect(controller.zoteroFields, isEmpty);
    expect(_visibleState(document), visible);
    expect(_allParagraphs(document), orderedEquals(paragraphs));
    expect(document.footnotes.single, same(footnote));
    expect(document.endnotes.single, same(endnote));
    expect(WordZoteroDocumentData.read(document), preferences);
    expect(controller.contentRevision, greaterThan(revision));
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(WordZotero.fields(reopened), isEmpty);
    expect(reopened.footnotes.single.text, footnote.text);
    expect(reopened.endnotes.single.text, endnote.text);
    expect(
      reopened.paragraphs
          .where((p) => p.text == 'First source')
          .single
          .inlines
          .whereType<WmlRun>()
          .single
          .properties
          .italic,
      isTrue,
    );

    for (var cycle = 0; cycle < 3; cycle++) {
      controller.undo();
      expect(_fieldState(document), fields);
      expect(_visibleState(document), visible);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(controller.zoteroFields, isEmpty);
      expect(_visibleState(document), visible);
    }
  });

  for (final invalid in ['locked', 'malformed', 'nested']) {
    test(
      '$invalid field leaves other fields, revisions and redo untouched',
      () {
        final document = _twoFields();
        final controller = _controller(document);
        controller.caret.logicalIndex = 0;
        controller.caret.collapseSelection();
        controller.insertText('Draft ');
        controller.undo();
        final last = controller.zoteroFields.last;
        if (invalid == 'locked') {
          last.run!.fieldLocked = true;
        } else if (invalid == 'malformed') {
          last.run!.fieldInstruction =
              ' ADDIN ZOTERO_ITEM CSL_CITATION broken ';
        } else {
          last.paragraph.inlines
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
        }
        final visible = _visibleState(document);
        final fields = _fieldState(document);
        final revision = controller.contentRevision;
        expect(controller.canRedo, isTrue);
        expect(controller.unlinkZoteroFields, throwsUnsupportedError);
        expect(_visibleState(document), visible);
        expect(_fieldState(document), fields);
        expect(controller.contentRevision, revision);
        expect(controller.canUndo, isFalse);
        expect(controller.canRedo, isTrue);
      },
    );
  }

  for (final missing in ['begin', 'separator', 'end']) {
    test(
      'missing $missing in a modeled Zotero packet blocks the whole batch',
      () {
        final document = _twoFields();
        document.sections.single.blocks.add(
          WmlParagraph(
            inlines: [
              if (missing != 'begin')
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
              WmlFieldBoundary(
                kind: WmlFieldBoundaryKind.instruction,
                text: ' ADDIN ZOTE',
              ),
              WmlFieldBoundary(
                kind: WmlFieldBoundaryKind.instruction,
                text: 'RO_ITEM CSL_CITATION {} ',
              ),
              if (missing != 'separator')
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
              WmlRun(text: 'Unreported citation'),
              if (missing != 'end')
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
            ],
          ),
        );
        final controller = _controller(document);
        expect(controller.zoteroFields, hasLength(2));
        final fields = _fieldState(document);
        final visible = _visibleState(document);
        final revision = controller.contentRevision;
        expect(controller.unlinkZoteroFields, throwsUnsupportedError);
        expect(_fieldState(document), fields);
        expect(_visibleState(document), visible);
        expect(controller.contentRevision, revision);
        expect(controller.canUndo, isFalse);
      },
    );
  }

  test('pending tracked changes prevent the whole conversion', () {
    final document = _twoFields();
    document.revisions.add(
      WmlRevision(
        id: 1,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        targetParagraph: document.paragraphs.single,
        start: 0,
        end: 6,
        text: 'Before',
      ),
    );
    final controller = _controller(document);
    final fields = _fieldState(document);
    final revision = controller.contentRevision;
    expect(controller.unlinkZoteroFields, throwsUnsupportedError);
    expect(_fieldState(document), fields);
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
  });

  test('viewing and empty documents do not create a history step', () {
    final viewing = _controller(
      _twoFields(),
      config: const OfficeSurfaceConfig(mode: OfficeInteractionMode.viewing),
    );
    final empty = _controller(WmlDocument.empty(text: 'No citations'));
    for (final controller in [viewing, empty]) {
      final revision = controller.contentRevision;
      final fields = _fieldState(controller.document);
      expect(controller.unlinkZoteroFields(), 0);
      expect(_fieldState(controller.document), fields);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
    }
  });

  test('a pending note draft is committed before the single unlink step', () {
    final document = _twoFields();
    final note = WordNotes.insert(
      document,
      document.paragraphs.single,
      text: 'Before ',
      endnote: false,
    );
    WordZotero.insertCitation(note.paragraphs.single, _citation('note', '(N)'));
    final controller = _controller(document);
    controller.setNoteText(note, 'Changed (N)');
    expect(controller.canUndo, isFalse);
    expect(controller.unlinkZoteroFields(), 3);
    expect(note.text, 'Changed (N)');
    controller.undo();
    expect(controller.zoteroFields, hasLength(3));
    expect(note.text, 'Changed (N)');
    controller.undo();
    expect(note.text, 'Before (N)');
    expect(controller.zoteroFields, hasLength(3));
    controller.redo();
    controller.redo();
    expect(note.text, 'Changed (N)');
    expect(controller.zoteroFields, isEmpty);
  });

  for (final placement in ['header', 'block', 'inline']) {
    test('preserved $placement citation prevents partial conversion', () {
      final document = _twoFields();
      final opaque = _opaque(_complexOpaque);
      if (placement == 'header') {
        document.sections.single.preservedStories['header'] = opaque;
      } else if (placement == 'block') {
        document.sections.single.blocks.add(opaque);
      } else {
        document.paragraphs.single.inlines.add(
          WmlOpaqueInline(content: opaque),
        );
      }
      final controller = _controller(document);
      final fields = _fieldState(document);
      expect(controller.unlinkZoteroFields, throwsUnsupportedError);
      expect(_fieldState(document), fields);
      expect(controller.canUndo, isFalse);
    });
  }

  test(
    'prose, unrelated quoted fields and replaced preserved stories are safe',
    () {
      final document = _twoFields();
      document.sections.single.blocks.add(
        _opaque(
          '<w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
          '<w:r><w:t>ZOTERO_ITEM CSL_CITATION is a field format.</w:t></w:r>'
          '<w:fldSimple w:instr=" IF &quot;ZOTERO_ITEM CSL_CITATION&quot; = &quot;x&quot; ">'
          '<w:r><w:t>Unrelated result</w:t></w:r></w:fldSimple></w:p>',
        ),
      );
      document.sections.single.preservedStories['header'] = _opaque(
        _complexOpaque,
      );
      document.sections.single.header.add(
        WmlParagraph(inlines: [WmlRun(text: 'Replacement header')]),
      );
      final controller = _controller(document);
      expect(controller.unlinkZoteroFields(), 2);
      expect(controller.zoteroFields, isEmpty);
      expect(document.sections.single.header.single.text, 'Replacement header');
    },
  );
}
