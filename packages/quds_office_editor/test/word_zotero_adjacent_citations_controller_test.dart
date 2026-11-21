import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _id = 'adjacent-controller';

ZoteroCitationItem _item(String key) => ZoteroCitationItem.fromCsl(
  itemData: {'type': 'book', 'title': 'Source $key'},
  uris: ['http://zotero.org/users/42/items/$key'],
  locator: '12',
  label: 'page',
);

ZoteroCitation _citation(
  String id,
  String text, {
  List<ZoteroCitationItem>? items,
}) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  items: items ?? [_item(id == 'a' ? 'AAAA0001' : 'BBBB0002')],
);

void _citations(WmlParagraph paragraph) {
  for (final id in ['a', 'b']) {
    WordZotero.insertNativeCitation(
      paragraph,
      instruction: _citation(id, '($id)').fieldInstruction,
      text: '($id)',
      formattedText: ZoteroFormattedText.fromHtml('(<i>$id</i>)'),
    );
  }
  paragraph.inlines.add(WmlRun(text: ' after'));
}

WordEditorController _controller(WmlDocument document) {
  final controller = WordEditorController(document: document);
  controller.proofing.enabled = false;
  addTearDown(controller.dispose);
  return controller;
}

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) {
  transaction.assertCurrent();
  return transaction.session.handle(command, [_id, ...arguments]);
}

WordZoteroTransaction _stage(WordEditorController controller) {
  final transaction = controller.beginZoteroTransaction(
    documentId: _id,
    command: ZoteroCitingCommand.refresh,
  );
  final fields =
      (_call(transaction, 'Document.getFields', ['Http'])! as List<Object?>)
          .cast<Map<String, Object>>();
  expect(fields.map((field) => field['adjacent']), [true, false]);
  final merged = _citation(
    'b',
    '(b; a)',
    items: [_item('BBBB0002'), _item('AAAA0001')],
  );
  _call(transaction, 'Field.setCode', [
    fields.last['id'],
    'ITEM CSL_CITATION ${jsonEncode(merged.toJson())}',
  ]);
  _call(transaction, 'Field.setText', [
    fields.last['id'],
    '(<i>b</i>; a)',
    true,
  ]);
  _call(transaction, 'Field.delete', [fields.first['id']]);
  return transaction;
}

void _complete(WordZoteroTransaction transaction) {
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

String _state(WmlDocument document) => jsonEncode({
  'body': [for (final paragraph in document.paragraphs) paragraph.text],
  'notes': [
    for (final note in [...document.footnotes, ...document.endnotes])
      {
        'id': note.id,
        'endnote': note.endnote,
        'text': WordNotes.editableText(note),
      },
  ],
  'fields': [
    for (final field in WordZotero.fields(document))
      {
        'code': field.instruction,
        'text': field.cachedText,
        'runs': [
          for (final run in WordZotero.copyCitationResult(field))
            [run.text, run.properties.italic],
        ],
      },
  ],
  'data': WordZoteroDocumentData.read(document),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  for (final reverse in [false, true]) {
    test(
      'adjacent refresh is one undo step and restores ${reverse ? 'backward' : 'forward'} selection',
      () {
        final document = WmlDocument.empty(text: 'Before ');
        _citations(document.paragraphs.single);
        final controller = _controller(document);
        controller.caret
          ..logicalIndex = reverse ? 1 : 4
          ..selectionAnchor = reverse ? 4 : 1
          ..selectionAnchorParagraph = 0;
        final before = _state(document);
        final transaction = _stage(controller);
        _complete(transaction);
        expect(_state(document), before);
        expect(controller.canUndo, isFalse);
        transaction.apply();
        expect(document.paragraphs.single.text, 'Before (b; a) after');
        expect(controller.zoteroFields.single.citation!.citationId, 'b');
        expect(controller.zoteroFields.single.citation!.items, hasLength(2));
        final after = _state(document);
        final reopened = WordDeserializer().readBytes(controller.saveBytes());
        expect(WordZotero.fields(reopened), hasLength(1));
        expect(WordZotero.fields(reopened).single.cachedText, '(b; a)');
        controller.undo();
        expect(_state(document), before);
        expect(controller.canUndo, isFalse);
        expect(controller.caret.logicalIndex, reverse ? 1 : 4);
        expect(controller.caret.selectionAnchor, reverse ? 4 : 1);
        expect(controller.caret.selectionAnchorParagraph, 0);
        controller.redo();
        expect(_state(document), after);
      },
    );
  }

  for (final endnote in [false, true]) {
    test(
      'authored ${endnote ? 'endnote' : 'footnote'} merge restores Notes selection and marker on undo',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'Before ',
        );
        _citations(note.paragraphs.single);
        final controller = _controller(document);
        const selection = TextSelection(baseOffset: 4, extentOffset: 1);
        controller.setNoteEditingTarget(note, selection);
        final before = _state(document);
        final transaction = _stage(controller);
        _complete(transaction);
        transaction.apply();
        expect(WordNotes.editableText(note), 'Before (b; a) after');
        expect(
          (endnote ? document.endnotes : document.footnotes).single,
          same(note),
        );
        expect(controller.zoteroFields, hasLength(1));
        final after = _state(document);
        controller.undo();
        expect(_state(document), before);
        expect(controller.noteEditingTarget!.note, same(note));
        expect(controller.noteEditingTarget!.selection, selection);
        expect(controller.canUndo, isFalse);
        controller.redo();
        expect(_state(document), after);
        final reopened = WordDeserializer().readBytes(controller.saveBytes());
        final savedNote =
            (endnote ? reopened.endnotes : reopened.footnotes).single;
        expect(WordNotes.editableText(savedNote), 'Before (b; a) after');
        expect(
          WordZotero.fields(reopened).single.paragraph,
          same(savedNote.paragraphs.single),
        );
      },
    );
  }

  test(
    'abandoned merge preserves fields, preferences, selection and undo stack',
    () {
      final document = WmlDocument.empty(text: 'Before ');
      _citations(document.paragraphs.single);
      final controller = _controller(document);
      controller.caret.logicalIndex = 3;
      final before = _state(document);
      final transaction = _stage(controller);
      expect(transaction.apply, throwsStateError);
      expect(_state(document), before);
      expect(controller.caret.logicalIndex, 3);
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'stale native merge keeps the current selection and original fields',
    () {
      final document = WmlDocument.empty(text: 'Before ');
      _citations(document.paragraphs.single);
      final controller = _controller(document);
      final before = _state(document);
      final transaction = _stage(controller);
      _complete(transaction);
      controller.caret.logicalIndex = 2;
      expect(transaction.apply, throwsStateError);
      expect(_state(document), before);
      expect(controller.caret.logicalIndex, 2);
      expect(controller.canUndo, isFalse);
    },
  );
}
