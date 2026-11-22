import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _documentId = 'paragraph-format-controller';
const _html =
    '<p dir="rtl" data-indent="2" '
    'style="padding-right: 80px; text-align: right">'
    'دليل عربي <i>evidence</i> '
    '<a href="https://example.org/research">link</a> '
    '<a href="https://www.zotero.org/?ABC123">old first</a></p>'
    '<p dir="ltr" data-indent="1" '
    'style="padding-left: 40px; text-align: justify">'
    'Latin <a href="https://www.zotero.org/?DEF456">old second</a></p>'
    '<h3 dir="ltr" data-indent="1" style="text-align: center">'
    'Aligned heading</h3>'
    '<p dir="ltr" data-indent="3" style="padding-left: 120px"></p>';

String _preferences(int type) => jsonEncode(<String, Object>{
  'dataVersion': 4,
  'sessionID': 'paragraph-format-session',
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
        ZoteroCitationItem.fromCsl(itemData: <String, Object>{'id': id, 'type': 'book', 'title': 'Formatted source $id'}, uris: ['http://zotero.org/users/42/items/ABCD1234'], locator: '12–14', label: 'page'),
      ],
    ).toJson())}';

typedef _Target = ({WordEditorController controller, WmlNote? note});

_Target _target(int type) {
  final paragraph = WmlParagraph(
    properties: WmlParagraphProps(
      indent: const WmlIndent(left: 7, right: 3, firstLine: 2),
      explicitIndent: true,
      spacingAfter: 6,
      rightToLeft: true,
      justification: WmlJustification.right,
      explicitJustification: true,
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
  if (note != null) {
    WordNotes.editableParagraphs(note).first.properties = paragraph.properties
        .copy();
  }
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
  paragraph.properties.rightToLeft,
  paragraph.properties.justification.name,
  paragraph.properties.explicitJustification,
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

void _stage(
  WordZoteroTransaction transaction,
  int type, {
  bool complete = true,
}) {
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
    final id = index == 0 ? 'ltr' : 'rtl';
    _call(transaction, 'Field.setCode', [
      field['id'],
      _citation(id, field['noteIndex']! as int),
    ]);
    _call(transaction, 'Field.setText', [field['id'], '<i>($id)</i>', true]);
  }
  if (complete) _complete(transaction);
}

void _complete(WordZoteroTransaction transaction) {
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

void _expectFormatted(WmlDocument document, int type) {
  final paragraphs = _story(document, type);
  final rtl = paragraphs.singleWhere((p) => p.text.startsWith('دليل عربي '));
  final ltr = paragraphs.singleWhere((p) => p.text.startsWith('Latin '));
  expect(rtl.text, 'دليل عربي evidence link (rtl)');
  expect(rtl.properties.rightToLeft, isTrue);
  expect(rtl.properties.justification, WmlJustification.right);
  expect(rtl.properties.indent.right, 60);
  expect(rtl.properties.indent.left, 0);
  expect(ltr.text, 'Latin (ltr)');
  expect(ltr.properties.rightToLeft, isFalse);
  expect(ltr.properties.justification, WmlJustification.justify);
  expect(ltr.properties.indent.left, 30);
  expect(ltr.properties.indent.right, 0);
  expect(
    rtl.inlines
        .whereType<WmlRun>()
        .singleWhere((r) => r.text.contains('evidence'))
        .properties
        .italic,
    isTrue,
  );
  expect(
    rtl.inlines
        .whereType<WmlRun>()
        .singleWhere((r) => r.text.contains('link'))
        .hyperlink
        ?.url,
    'https://example.org/research',
  );
  final heading = paragraphs.singleWhere((p) => p.text == 'Aligned heading');
  expect(heading.properties.headingLevel, 3);
  expect(heading.properties.rightToLeft, isFalse);
  expect(heading.properties.justification, WmlJustification.center);
  expect(heading.properties.indent.left, 30);
  expect(
    paragraphs.any(
      (p) =>
          p.text.isEmpty &&
          p.properties.rightToLeft == false &&
          p.properties.indent.left == 90,
    ),
    isTrue,
    reason: 'Empty paragraphs retain their authored direction and indentation',
  );
  final prefix = paragraphs.first;
  final suffix = paragraphs.singleWhere((p) => p.text == ' After');
  expect(prefix.text.trim(), 'Before');
  for (final original in [prefix, suffix]) {
    expect(original.properties.rightToLeft, isTrue);
    expect(original.properties.justification, WmlJustification.right);
    expect(original.properties.indent.left, 7);
    expect(original.properties.indent.right, 3);
    expect(original.properties.indent.firstLine, 2);
  }
  if (type == 0 || type == 3) {
    expect(suffix.inlines.whereType<WmlRun>().single.properties.italic, isTrue);
    expect(
      suffix.inlines.whereType<WmlRun>().single.hyperlink?.url,
      'https://example.org/tail',
    );
  }
  final fields = WordZotero.fields(document);
  expect(fields.map((f) => f.citation!.citationId), ['rtl', 'ltr']);
  expect(fields.map((f) => f.cachedText), ['(rtl)', '(ltr)']);
  expect(fields.every((f) => f.canEdit), isTrue);
  expect(
    fields.every((f) => f.citation!.items.single.locator == '12–14'),
    isTrue,
  );
  expect(fields.first.paragraph, same(rtl));
  expect(fields.last.paragraph, same(ltr));
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
        '${command.name} paragraph formatting preserves $story lifecycle',
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
          _stage(transaction, type, complete: false);
          expect(_state(document), before);
          expect(controller.canUndo, isFalse);
          expect(controller.isDirty, isFalse);
          expect(transaction.apply, throwsStateError);
          expect(_state(document), before);
          _complete(transaction);
          expect(_state(document), before);
          transaction.apply();
          _expectFormatted(document, type);
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
            _expectFormatted(reopened, type);
          }
        },
      );
    }

    test('${command.name} refuses a changed paragraph source atomically', () {
      final target = _target(0);
      final controller = target.controller;
      final before = _state(controller.document);
      final transaction = controller.beginZoteroTransaction(
        documentId: _documentId,
        command: command,
      );
      _stage(transaction, 0);
      controller.applyParagraphFormat(
        (properties) => properties.indent = const WmlIndent(left: 11),
      );
      final changed = _state(controller.document);
      expect(transaction.apply, throwsStateError);
      expect(_state(controller.document), changed);
      expect(controller.zoteroFields, isEmpty);
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(_state(controller.document), before);
      expect(controller.canUndo, isFalse);
    });
  }

  test('implicit right padding does not invent RTL in an RTL host', () {
    final controller = _target(0).controller;
    final transaction = controller.beginZoteroTransaction(
      documentId: _documentId,
      command: ZoteroCitingCommand.addNote,
    );
    _insert(
      transaction,
      0,
      '<p data-indent="1" style="padding-right: 40px">Implicit</p>'
      '<p dir="ltr">Explicit left-to-right</p>'
      '<p dir="rtl">Explicit right-to-left</p>',
    );
    _complete(transaction);
    transaction.apply();
    for (final document in [
      controller.document,
      WordDeserializer().readBytes(
        WordSerializer().writeBytes(controller.document),
      ),
    ]) {
      final paragraphs = document.paragraphs.toList();
      final implicit = paragraphs.singleWhere((p) => p.text == 'Implicit');
      expect(implicit.properties.rightToLeft, isNull);
      expect(implicit.properties.indent.right, 30);
      expect(implicit.properties.indent.left, 0);
      final ltr = paragraphs.singleWhere(
        (p) => p.text == 'Explicit left-to-right',
      );
      expect(ltr.properties.rightToLeft, isFalse);
      expect(ltr.properties.justification, WmlJustification.left);
      final rtl = paragraphs.singleWhere(
        (p) => p.text == 'Explicit right-to-left',
      );
      expect(rtl.properties.rightToLeft, isTrue);
      expect(rtl.properties.justification, WmlJustification.right);
    }
  });

  test('paragraph indent composes with quotes and list hanging markers', () {
    final controller = _target(3).controller;
    final transaction = controller.beginZoteroTransaction(
      documentId: _documentId,
      command: ZoteroCitingCommand.addAnnotation,
    );
    _insert(
      transaction,
      3,
      '<blockquote><h6 dir="rtl" data-indent="1" '
      'style="padding-right:40px;text-align:center">Quoted heading</h6>'
      '<ol start="3"><li><p dir="ltr" data-indent="1" '
      'style="padding-left:40px;text-align:justify">List item</p>'
      '<p data-indent="2" style="padding-left:80px">Continuation</p>'
      '</li></ol></blockquote>',
    );
    _complete(transaction);
    transaction.apply();
    for (final document in [
      controller.document,
      WordDeserializer().readBytes(
        WordSerializer().writeBytes(controller.document),
      ),
    ]) {
      final paragraphs = _story(document, 3);
      final heading = paragraphs.singleWhere((p) => p.text == 'Quoted heading');
      expect(heading.properties.headingLevel, 6);
      expect(heading.properties.rightToLeft, isTrue);
      expect(heading.properties.justification, WmlJustification.center);
      expect(heading.properties.indent.left, 18);
      expect(heading.properties.indent.right, 30);
      final item = paragraphs.singleWhere((p) => p.text == 'List item');
      expect(item.properties.rightToLeft, isFalse);
      expect(item.properties.justification, WmlJustification.justify);
      expect(item.properties.indent.left, 66);
      expect(item.properties.indent.hanging, 9);
      expect(item.properties.numId, isNotNull);
      expect(item.properties.listLabel, '3. ');
      final continuation = paragraphs.singleWhere(
        (p) => p.text == 'Continuation',
      );
      expect(continuation.properties.indent.left, 96);
      expect(continuation.properties.indent.hanging, 0);
      expect(continuation.properties.numberingSuppressed, isTrue);
      expect(continuation.properties.numId, isNull);
    }
  });

  test('unsupported paragraph payloads preserve the complete source', () {
    for (final invalid in [
      '<p dir="auto">Invalid direction</p>',
      '<p data-indent="0">Zero</p>',
      '<p data-indent="8">Too deep</p>',
      '<p data-indent="1.5">Fraction</p>',
      '<p data-indent="1" style="padding-left:41px">Wrong spacing</p>',
      '<p style="padding-left:40px">No level</p>',
      '<p data-indent="1" style="padding:40px">Shorthand</p>',
      '<p dir="rtl" data-indent="1" style="padding-left:40px">Wrong side</p>',
      '<p data-indent="1" style="padding-left:40px;padding-right:40px">Both</p>',
      '<p style="text-align:start">Logical alignment</p>',
      '<p style="margin-left:40px">Arbitrary CSS</p>',
      '<p><span dir="rtl">Inline direction</span></p>',
      '<ol dir="rtl"><li><p>List direction</p></li></ol>',
      '<ul><li><p dir="rtl">RTL list paragraph</p></li></ul>',
    ]) {
      final controller = _target(0).controller;
      final before = _state(controller.document);
      final transaction = controller.beginZoteroTransaction(
        documentId: _documentId,
        command: ZoteroCitingCommand.addAnnotation,
      );
      expect(
        () => _insert(transaction, 0, '<p dir="rtl">Valid prefix</p>$invalid'),
        throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())),
        reason: invalid,
      );
      expect(transaction.apply, throwsStateError, reason: invalid);
      expect(_state(controller.document), before, reason: invalid);
      expect(controller.canUndo, isFalse, reason: invalid);
      expect(controller.isDirty, isFalse, reason: invalid);
    }
  });
}
