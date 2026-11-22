import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _id = 'controller-note-colors';

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) {
  transaction.assertCurrent();
  return transaction.session.handle(command, [_id, ...arguments]);
}

List<Object?> _state(WmlDocument document) => [
  for (final paragraph in document.paragraphs)
    [
      paragraph.text,
      for (final run in paragraph.inlines.whereType<WmlRun>())
        [
          run.text,
          run.properties.color,
          run.properties.highlight,
          run.properties.bold,
          run.properties.italic,
          run.fieldInstruction,
        ],
    ],
];

void main() {
  for (final command in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    test('$command commits note colors and fields as one undoable change', () {
      final document = WmlDocument.empty(text: 'BeforeAfter');
      final controller = WordEditorController(document: document);
      controller.proofing.enabled = false;
      controller.caret
        ..logicalIndex = 6
        ..collapseSelection();
      addTearDown(controller.dispose);
      final before = _state(document);
      final transaction = controller.beginZoteroTransaction(
        documentId: _id,
        command: command,
      );
      _call(transaction, 'Document.setDocumentData', [
        jsonEncode({
          'dataVersion': 4,
          'sessionID': _id,
          'style': {
            'styleID': 'http://www.zotero.org/styles/apa',
            'locale': 'en-US',
          },
          'prefs': {'fieldType': 'Http', 'noteType': 0},
        }),
      ]);
      final temporary =
          _call(transaction, 'Document.insertField', ['Http', 0])! as Map;
      _call(transaction, 'Field.delete', [temporary['id']]);
      _call(transaction, 'Document.insertText', [
        '<p><span style="color:rgb(255,32,32);background-color:#ffd400">'
            '<i>Colored quote</i> <a href="https://www.zotero.org/?ABC123">(Old)</a>'
            '</span></p>',
      ]);
      final fields =
          _call(transaction, 'Document.convertPlaceholdersToFields', [
                ['ABC123'],
                0,
                'Http',
              ])!
              as List;
      final fieldId = (fields.single as Map)['id'];
      final citation = ZoteroCitation(
        citationId: 'colored-citation',
        plainCitation: '(Author, 2026)',
        items: [
          ZoteroCitationItem.fromCsl(
            itemData: {'id': 'source', 'type': 'book', 'title': 'Source'},
            uris: ['http://zotero.org/users/42/items/ABCD1234'],
          ),
        ],
      );
      _call(transaction, 'Field.setCode', [
        fieldId,
        'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
      ]);
      _call(transaction, 'Field.setText', [
        fieldId,
        '<b>(Author, 2026)</b>',
        true,
      ]);
      _call(transaction, 'Document.complete');
      transaction.session.prepareReview();
      expect(_state(document), before);
      transaction.apply();
      final after = _state(document);
      final quote = document.paragraphs
          .expand((p) => p.inlines)
          .whereType<WmlRun>()
          .firstWhere((run) => run.text.contains('Colored quote'));
      expect(quote.properties.color, 'FF2020');
      expect(quote.properties.highlight, 'FFD400');
      expect(quote.properties.italic, isTrue);
      expect(
        controller.zoteroFields.single.citation!.citationId,
        'colored-citation',
      );
      controller.undo();
      expect(_state(document), before);
      expect(controller.zoteroFields, isEmpty);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_state(document), after);
      expect(controller.zoteroFields.single.canEdit, isTrue);
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final reopenedQuote = reopened.paragraphs
          .expand((p) => p.inlines)
          .whereType<WmlRun>()
          .firstWhere((run) => run.text.contains('Colored quote'));
      expect(reopenedQuote.properties.color, 'FF2020');
      expect(reopenedQuote.properties.highlight, 'FFD400');
      expect(WordZotero.fields(reopened).single.canEdit, isTrue);
    });
  }
}
