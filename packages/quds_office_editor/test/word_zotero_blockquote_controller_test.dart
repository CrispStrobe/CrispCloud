import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _documentId = 'quoted-research-controller';
const _html =
    '<p>Imported introduction</p><blockquote>'
    '<p>Quoted <i>evidence</i> '
    '<a href="https://example.org/research">link</a> '
    '<a href="https://www.zotero.org/?ABC123">old first</a></p>'
    '<blockquote><p>Nested '
    '<a href="https://www.zotero.org/?DEF456">old second</a></p>'
    '</blockquote><p></p></blockquote><p>Imported conclusion</p>';

String _preferences(int type) => jsonEncode(<String, Object>{
  'dataVersion': 4,
  'sessionID': 'quoted-research-session',
  'zoteroVersion': '10.0',
  'style': <String, Object>{
    'styleID': type == 1 || type == 2
        ? 'http://www.zotero.org/styles/chicago-note-bibliography'
        : 'http://www.zotero.org/styles/apa',
    'locale': 'en-US',
  },
  'prefs': <String, Object>{
    'fieldType': 'Http',
    'noteType': type == 3 ? 0 : type,
  },
});

String _citation(String id, int noteIndex) =>
    'ITEM CSL_CITATION ${jsonEncode(ZoteroCitation(
      citationId: id,
      plainCitation: '($id)',
      noteIndex: noteIndex,
      items: [
        ZoteroCitationItem.fromCsl(itemData: <String, Object>{'id': id, 'type': 'book', 'title': 'Quoted source $id'}, uris: ['http://zotero.org/users/42/items/ABCD1234'], locator: '12–14', label: 'page'),
      ],
    ).toJson())}';

typedef _Target = ({WordEditorController controller, WmlNote? note});

_Target _target(int type) {
  final paragraph = WmlParagraph(
    properties: WmlParagraphProps(
      indent: const WmlIndent(left: 7, right: 3, firstLine: 2),
      explicitIndent: true,
      spacingAfter: 6,
    ),
    inlines: [
      WmlRun(text: 'Before chosen', properties: WmlRunProps(bold: true)),
      WmlRun(
        text: ' After',
        properties: WmlRunProps(italic: true),
        hyperlink: const WmlHyperlink(url: 'https://example.org/tail'),
      ),
    ],
  );
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          if (type == 3)
            WmlTable(
              grid: [240, 200],
              rows: [
                WmlTableRow(
                  cells: [
                    WmlTableCell(blocks: [paragraph], width: 240),
                    WmlTableCell(
                      blocks: [
                        WmlParagraph(inlines: [WmlRun(text: 'Other cell')]),
                      ],
                      width: 200,
                    ),
                  ],
                ),
              ],
            )
          else
            paragraph,
          WmlParagraph(inlines: [WmlRun(text: 'Unrelated')]),
        ],
      ),
    ],
  );
  final note = type == 1 || type == 2
      ? WordNotes.insert(
          document,
          document.paragraphs.last,
          text: 'Before chosen After',
          endnote: type == 2,
        )
      : null;
  final controller = WordEditorController(document: document);
  controller.proofing.enabled = false;
  controller.caret
    ..paragraphIndex = 0
    ..logicalIndex = 7
    ..selectionAnchor = 13
    ..selectionAnchorParagraph = 0;
  if (note != null) {
    controller.setNoteEditingTarget(
      note,
      const TextSelection(baseOffset: 13, extentOffset: 7),
    );
  }
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return (controller: controller, note: note);
}

List<WmlParagraph> _story(WmlDocument document, int type) {
  if (type == 1 || type == 2) {
    return (type == 1 ? document.footnotes : document.endnotes)
        .single
        .allParagraphs
        .toList();
  }
  if (type == 3) {
    final table = document.sections.single.blocks.whereType<WmlTable>().single;
    return WordTree.paragraphs(table.rows.single.cells.first.blocks).toList();
  }
  return document.paragraphs.toList();
}

List<Object?> _paragraphState(WmlParagraph paragraph) => [
  paragraph.text,
  paragraph.properties.indent.left,
  paragraph.properties.indent.right,
  paragraph.properties.indent.firstLine,
  paragraph.properties.indent.hanging,
  paragraph.properties.headingLevel,
  paragraph.properties.numId,
  for (final inline in paragraph.inlines)
    if (inline is WmlRun)
      [
        inline.text,
        inline.properties.bold,
        inline.properties.italic,
        inline.hyperlink?.url,
        inline.fieldInstruction,
        inline.noteRefId,
        inline.noteRefEndnote,
      ]
    else if (inline is WmlNoteMarker)
      ['marker', inline.endnote],
];

String _state(WmlDocument document) => jsonEncode(<String, Object?>{
  'body': [
    for (final paragraph in document.paragraphs) _paragraphState(paragraph),
  ],
  'notes': [
    for (final note in [...document.footnotes, ...document.endnotes])
      [
        note.id,
        note.endnote,
        for (final p in note.allParagraphs) _paragraphState(p),
      ],
  ],
  'preferences': WordZoteroDocumentData.read(document),
});

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) {
  transaction.assertCurrent();
  return transaction.session.handle(command, [_documentId, ...arguments]);
}

void _insert(WordZoteroTransaction transaction, int type, String html) {
  final noteType = type == 3 ? 0 : type;
  _call(transaction, 'Document.setDocumentData', [_preferences(type)]);
  final temporary =
      _call(transaction, 'Document.insertField', ['Http', noteType])!
          as Map<String, Object>;
  _call(transaction, 'Field.delete', [temporary['id']]);
  _call(transaction, 'Document.insertText', [html]);
}

void _stage(WordZoteroTransaction transaction, int type) {
  _insert(transaction, type, _html);
  final fields =
      (_call(transaction, 'Document.convertPlaceholdersToFields', [
                ['DEF456', 'ABC123'],
                type == 3 ? 0 : type,
                'Http',
              ])!
              as List<Object?>)
          .cast<Map<String, Object>>();
  for (var index = 0; index < fields.length; index++) {
    final field = fields[index];
    final id = index == 0 ? 'nested' : 'quoted';
    _call(transaction, 'Field.setCode', [
      field['id'],
      _citation(id, field['noteIndex']! as int),
    ]);
    _call(transaction, 'Field.setText', [field['id'], '<i>($id)</i>', true]);
  }
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

void _expectQuote(WmlDocument document, int type) {
  final paragraphs = _story(document, type);
  final quoted = paragraphs.singleWhere((p) => p.text.startsWith('Quoted '));
  final nested = paragraphs.singleWhere((p) => p.text.startsWith('Nested '));
  expect(quoted.text, 'Quoted evidence link (quoted)');
  expect(quoted.properties.indent.left, 18);
  expect(nested.properties.indent.left, 36);
  expect(nested.text, 'Nested (nested)');
  expect(
    quoted.inlines
        .whereType<WmlRun>()
        .where((r) => r.text.contains('evidence'))
        .single
        .properties
        .italic,
    isTrue,
  );
  expect(
    quoted.inlines
        .whereType<WmlRun>()
        .where((r) => r.text.contains('link'))
        .single
        .hyperlink
        ?.url,
    'https://example.org/research',
  );
  for (final text in ['Imported introduction', 'Imported conclusion']) {
    expect(
      paragraphs.singleWhere((p) => p.text == text).properties.indent.left,
      0,
    );
  }
  expect(
    paragraphs.any((p) => p.text.isEmpty && p.properties.indent.left == 18),
    isTrue,
    reason: 'Authored empty quote paragraphs retain their native indentation',
  );
  expect(paragraphs.first.text.trim(), 'Before');
  final suffix = paragraphs.singleWhere((p) => p.text == ' After');
  if (type == 0 || type == 3) {
    expect(paragraphs.first.properties.indent.left, 7);
    expect(suffix.properties.indent.left, 7);
    expect(suffix.properties.indent.right, 3);
    expect(suffix.properties.indent.firstLine, 2);
    expect(suffix.inlines.whereType<WmlRun>().single.properties.italic, isTrue);
    expect(
      suffix.inlines.whereType<WmlRun>().single.hyperlink?.url,
      'https://example.org/tail',
    );
  }
  final fields = WordZotero.fields(document);
  expect(fields.map((f) => f.citation!.citationId), ['quoted', 'nested']);
  expect(fields.map((f) => f.cachedText), ['(quoted)', '(nested)']);
  expect(fields.every((f) => f.canEdit), isTrue);
  expect(
    fields.every((f) => f.citation!.items.single.locator == '12–14'),
    isTrue,
  );
  expect(fields.first.paragraph, same(quoted));
  expect(fields.last.paragraph, same(nested));
  expect(WordFieldSpans.unbalanced(document), isEmpty);
  if (type == 3) {
    final table = document.sections.single.blocks.whereType<WmlTable>().single;
    expect(
      WordTree.paragraphs(table.rows.single.cells.last.blocks).single.text,
      'Other cell',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  for (final command in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    for (final type in [0, 1, 2, 3]) {
      final story = ['body', 'footnote', 'endnote', 'table cell'][type];
      test(
        '${command.name} quotes retain $story ownership, undo and DOCX fields',
        () {
          final target = _target(type);
          final controller = target.controller;
          final document = controller.document;
          final before = _state(document);
          final noteSelection = controller.noteEditingTarget?.selection;
          final transaction = controller.beginZoteroTransaction(
            documentId: _documentId,
            command: command,
          );
          _stage(transaction, type);
          expect(_state(document), before);
          expect(controller.canUndo, isFalse);
          expect(controller.isDirty, isFalse);
          transaction.apply();
          _expectQuote(document, type);
          final after = _state(document);
          expect(controller.canUndo, isTrue);
          controller.undo();
          expect(_state(document), before);
          expect(controller.canUndo, isFalse);
          if (noteSelection == null) {
            expect(controller.caret.logicalIndex, 7);
            expect(controller.caret.selectionAnchor, 13);
          } else {
            expect(controller.noteEditingTarget?.selection, noteSelection);
          }
          controller.redo();
          expect(_state(document), after);
          var reopened = document;
          for (var cycle = 0; cycle < 2; cycle++) {
            reopened = WordDeserializer().readBytes(
              WordSerializer().writeBytes(reopened),
            );
            _expectQuote(reopened, type);
          }
        },
      );
    }
  }

  for (final type in [0, 1, 2, 3]) {
    test('quoted research refuses stale selection in target $type', () {
      final target = _target(type);
      final controller = target.controller;
      final before = _state(controller.document);
      final transaction = controller.beginZoteroTransaction(
        documentId: _documentId,
        command: ZoteroCitingCommand.addNote,
      );
      _stage(transaction, type);
      if (target.note == null) {
        controller.caret.logicalIndex = 8;
      } else {
        controller.setNoteEditingTarget(
          target.note!,
          const TextSelection.collapsed(offset: 2),
        );
      }
      expect(transaction.apply, throwsStateError);
      expect(_state(controller.document), before);
      expect(controller.canUndo, isFalse);
    });
  }

  for (final html in [
    '<blockquote><p>Supported</p><table><tr><td>Unsupported</td></tr></table></blockquote>',
    '${'<blockquote>' * 9}<p>Too deep</p>${'</blockquote>' * 9}',
    '<blockquote><p>First</p><p style="color:red">Unsupported style</p></blockquote>',
  ]) {
    test(
      'unsupported quote structure refuses the whole transaction: $html',
      () {
        final target = _target(0);
        final controller = target.controller;
        final before = _state(controller.document);
        final transaction = controller.beginZoteroTransaction(
          documentId: _documentId,
          command: ZoteroCitingCommand.addAnnotation,
        );
        expect(
          () => _insert(transaction, 0, html),
          throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())),
        );
        expect(transaction.apply, throwsStateError);
        expect(_state(controller.document), before);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      },
    );
  }

  test(
    'quote-only insertion retains layout and active fields in editable ODT',
    () async {
      final target = _target(0);
      final transaction = target.controller.beginZoteroTransaction(
        documentId: _documentId,
        command: ZoteroCitingCommand.addNote,
      );
      _stage(transaction, 0);
      transaction.apply();
      final source = target.controller.document;
      final original = _state(source);
      final bytes = OdtDocumentWriter.writeEditableZoteroBytes(source);
      final inventory = await OdfZotero.inspect(bytes);
      expect(inventory.fields, hasLength(2));
      expect(inventory.fields.every((f) => f.isImportCandidate), isTrue);
      final reopened = await OdtDocumentReader.readBytes(bytes);
      _expectQuote(reopened, 0);
      _expectQuote(
        WordDeserializer().readBytes(WordSerializer().writeBytes(reopened)),
        0,
      );
      expect(_state(source), original);
    },
  );
}
