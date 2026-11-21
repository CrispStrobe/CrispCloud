import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _documentId = 'transfer-controller';
const _instructions =
    'Open this document in the destination word processor and use Zotero Refresh.';
const _preferences =
    '<data data-version="3"><session id="transfer-session"/>'
    '<style id="http://www.zotero.org/styles/apa" '
    'locale="de-DE" hasBibliography="1"/>'
    '<prefs><pref name="fieldType" value="Field"/>'
    '<pref name="noteType" value="0"/></prefs></data>';

ZoteroCitation _citation(String id, String text) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': id, 'type': 'book', 'title': 'Research source $id'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
      locator: '34',
      label: 'page',
    ),
  ],
);

WmlDocument _activeDocument() {
  final document = WmlDocument.empty(text: 'Before ')
    ..zoteroDocumentData = _preferences;
  final paragraph = document.paragraphs.single;
  WordZotero.insertCitation(paragraph, _citation('first', '(First)'));
  paragraph.inlines.add(WmlRun(text: ' between '));
  WordZotero.insertCitation(paragraph, _citation('second', '(Second)'));
  paragraph.inlines.add(WmlRun(text: ' after'));
  return document;
}

WmlDocument _transferDocument() {
  final document = _activeDocument();
  WordZoteroTransfer.prepareExport(
    document,
    instructions: _instructions,
    documentData: _preferences,
  ).apply();
  return document;
}

WordEditorController _controller(WmlDocument document) {
  final controller = WordEditorController(document: document);
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return controller;
}

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) {
  transaction.assertCurrent();
  return transaction.session.handle(command, [_documentId, ...arguments]);
}

WordZoteroTransaction _export(WordEditorController controller) {
  final transaction = controller.beginZoteroTransaction(
    documentId: _documentId,
    command: ZoteroCitingCommand.exportDocument,
  );
  _call(transaction, 'Document.exportDocument', ['Http', _instructions]);
  _call(transaction, 'Document.setDocumentData', [
    WordZoteroDocumentData.toHttp(_preferences),
  ]);
  _call(transaction, 'Document.activate');
  return transaction;
}

WordZoteroTransaction _import(
  WordEditorController controller, {
  bool formatAll = true,
}) {
  final transaction = controller.beginZoteroTransaction(
    documentId: _documentId,
    command: ZoteroCitingCommand.refresh,
  );
  expect(_call(transaction, 'Document.importDocument', ['Http']), isTrue);
  final fields =
      (_call(transaction, 'Document.getFields', ['Http']) as List<Object?>)
          .cast<Map<String, Object>>();
  expect(fields, hasLength(2));
  for (var index = 0; index < (formatAll ? fields.length : 1); index++) {
    _call(transaction, 'Field.setText', [
      fields[index]['id']! as String,
      '<i>(Restored ${index + 1})</i>',
      true,
    ]);
  }
  return transaction;
}

void _complete(WordZoteroTransaction transaction) {
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

String _state(WmlDocument document) => jsonEncode({
  'data': document.zoteroDocumentData,
  'body': [
    for (final paragraph in document.paragraphs)
      {
        'text': paragraph.text,
        'runs': [
          for (final run in paragraph.inlines.whereType<WmlRun>())
            {
              'text': run.text,
              'url': run.hyperlink?.url,
              'field': run.fieldInstruction,
              'italic': run.properties.italic,
            },
        ],
      },
  ],
  'fields': [
    for (final field in WordZotero.fields(document))
      [field.instruction, field.cachedText, field.start, field.end],
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final narrowInlines in [false, true]) {
    test('export undo/redo retains covariant owners ($narrowInlines)', () {
      final run = WmlRun(
        text: '(First)',
        fieldInstruction: _citation('first', '(First)').fieldInstruction,
      );
      final paragraph = WmlParagraph(
        inlines: narrowInlines ? <WmlRun>[run] : <WmlInline>[run],
      );
      final owners = <WmlParagraph>[paragraph];
      final document = WmlDocument(sections: [WmlSection(blocks: owners)])
        ..zoteroDocumentData = _preferences;
      final controller = _controller(document);
      final before = _state(document);
      final transaction = _export(controller);
      _complete(transaction);
      transaction.apply();
      final after = _state(document);
      expect(document.sections.single.blocks, same(owners));
      controller.undo();
      expect(_state(document), before);
      expect(document.sections.single.blocks, same(owners));
      expect(document.paragraphs.single, same(paragraph));
      controller.redo();
      expect(_state(document), after);
      expect(document.sections.single.blocks, same(owners));
    });
  }

  for (final owner in [
    'fixed blocks',
    'immutable blocks',
    'fixed inlines',
    'immutable inlines',
  ]) {
    test('export rejects $owner before snapshot rollback can mutate', () {
      final runs = <WmlInline>[
        WmlRun(
          text: '(First)',
          fieldInstruction: _citation('first', '(First)').fieldInstruction,
        ),
      ];
      final paragraph = WmlParagraph(
        inlines: switch (owner) {
          'fixed inlines' => List<WmlInline>.of(runs, growable: false),
          'immutable inlines' => List<WmlInline>.unmodifiable(runs),
          _ => runs,
        },
      );
      final paragraphs = <WmlBlock>[paragraph];
      final blocks = switch (owner) {
        'fixed blocks' => List<WmlBlock>.of(paragraphs, growable: false),
        'immutable blocks' => List<WmlBlock>.unmodifiable(paragraphs),
        _ => paragraphs,
      };
      final document = WmlDocument(sections: [WmlSection(blocks: blocks)])
        ..zoteroDocumentData = _preferences;
      final controller = _controller(document);
      final before = _state(document);
      final revision = controller.contentRevision;
      final transaction = _export(controller);
      _complete(transaction);
      expect(() => transaction.apply(), throwsUnsupportedError);
      expect(_state(document), before);
      expect(document.paragraphs.single, same(paragraph));
      expect(controller.canUndo, isFalse);
      expect(controller.contentRevision, revision);
    });
  }

  test('export stays detached until complete and is one undoable change', () {
    final document = _activeDocument();
    final originalParagraph = document.paragraphs.single;
    final controller = _controller(document);
    final original = _state(document);
    final revision = controller.contentRevision;
    final transaction = _export(controller);
    expect(_state(document), original);
    expect(transaction.session.hasExportedDocument, isTrue);
    expect(transaction.session.hasImportedDocument, isFalse);
    expect(() => transaction.apply(), throwsStateError);
    expect(controller.canUndo, isFalse);
    expect(controller.contentRevision, revision);
    _complete(transaction);
    expect(_state(document), original);
    transaction.apply();
    final exported = _state(document);
    expect(WordZoteroTransfer.isTransferDocument(document), isTrue);
    expect(controller.zoteroFields, isEmpty);
    expect(document.paragraphs, contains(same(originalParagraph)));
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(_state(document), original);
    expect(document.paragraphs.single, same(originalParagraph));
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(_state(document), exported);
    expect(() => transaction.apply(), throwsStateError);
  });

  test(
    'export undo keeps paragraph identity for earlier text undo commands',
    () {
      final document = _activeDocument();
      final paragraph = document.paragraphs.single;
      final controller = _controller(document);
      final original = _state(document);
      controller.insertText('Typed ');
      final typed = _state(document);
      final transaction = _export(controller);
      _complete(transaction);
      transaction.apply();
      final exported = _state(document);
      controller.undo();
      expect(document.paragraphs.single, same(paragraph));
      expect(_state(document), typed);
      controller.undo();
      expect(_state(document), original);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_state(document), typed);
      controller.redo();
      expect(_state(document), exported);
    },
  );

  test(
    'Refresh imports formatted fields atomically with one undo and redo',
    () {
      final document = _transferDocument();
      final originalParagraphs = document.paragraphs.toList();
      final controller = _controller(document);
      final before = _state(document);
      final transaction = _import(controller);
      expect(transaction.session.hasImportedDocument, isTrue);
      expect(transaction.session.hasExportedDocument, isFalse);
      expect(_state(document), before);
      expect(controller.zoteroFields, isEmpty);
      expect(() => transaction.apply(), throwsStateError);
      _complete(transaction);
      expect(_state(document), before);
      transaction.apply();
      final after = _state(document);
      expect(WordZoteroTransfer.isTransferDocument(document), isFalse);
      expect(controller.zoteroFields.map((field) => field.cachedText), [
        '(Restored 1)',
        '(Restored 2)',
      ]);
      expect(
        controller.zoteroFields.map((field) => field.citation!.citationId),
        ['first', 'second'],
      );
      expect(WordZoteroDocumentData.read(document), contains('de-DE'));
      expect(
        document.paragraphs
            .expand((p) => p.inlines)
            .whereType<WmlRun>()
            .any((run) => run.properties.italic == true),
        isTrue,
      );
      controller.undo();
      expect(_state(document), before);
      final restoredParagraphs = document.paragraphs.toList();
      expect(restoredParagraphs, hasLength(originalParagraphs.length));
      for (var index = 0; index < originalParagraphs.length; index++) {
        expect(restoredParagraphs[index], same(originalParagraphs[index]));
      }
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_state(document), after);
    },
  );

  test('incomplete import cannot replace the original transfer document', () {
    final document = _transferDocument();
    final controller = _controller(document);
    final original = _state(document);
    final transaction = _import(controller, formatAll: false);
    expect(() => _complete(transaction), throwsFormatException);
    expect(() => transaction.apply(), throwsStateError);
    expect(_state(document), original);
    expect(controller.canUndo, isFalse);
    expect(controller.isDirty, isFalse);
  });

  test(
    'import undo retains earlier typing and its original paragraph target',
    () {
      final document = _transferDocument();
      final controller = _controller(document);
      final paragraphs = document.paragraphs.toList();
      final target = paragraphs.firstWhere((p) => p.text.startsWith('Before '));
      final original = _state(document);
      controller.caret
        ..paragraphIndex = paragraphs.indexOf(target)
        ..logicalIndex = 0
        ..collapseSelection();
      controller.insertText('Typed ');
      final typed = _state(document);
      final transaction = _import(controller);
      _complete(transaction);
      transaction.apply();
      final imported = _state(document);
      controller.undo();
      expect(document.paragraphs, contains(same(target)));
      expect(_state(document), typed);
      controller.undo();
      expect(_state(document), original);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_state(document), typed);
      controller.redo();
      expect(_state(document), imported);
    },
  );

  test('saved transfer reopens for Refresh and saves active DOCX fields', () {
    final exporting = _controller(_activeDocument());
    final exportTransaction = _export(exporting);
    _complete(exportTransaction);
    exportTransaction.apply();
    final reopened = WordDeserializer().readBytes(exporting.saveBytes());
    expect(WordZoteroTransfer.isTransferDocument(reopened), isTrue);
    final importing = _controller(reopened);
    final importTransaction = _import(importing);
    _complete(importTransaction);
    importTransaction.apply();
    final activeAgain = WordDeserializer().readBytes(importing.saveBytes());
    expect(WordZoteroTransfer.isTransferDocument(activeAgain), isFalse);
    final fields = WordZotero.fields(activeAgain);
    expect(fields.map((field) => field.cachedText), [
      '(Restored 1)',
      '(Restored 2)',
    ]);
    expect(fields.map((field) => field.citation!.citationId), [
      'first',
      'second',
    ]);
    expect(WordZoteroDocumentData.read(activeAgain), contains('de-DE'));
  });

  for (final operation in ['export', 'import']) {
    test('discarding an incomplete $operation leaves a clean document', () {
      final document = operation == 'export'
          ? _activeDocument()
          : _transferDocument();
      final controller = _controller(document);
      final original = _state(document);
      final transaction = operation == 'export'
          ? _export(controller)
          : _import(controller);
      expect(transaction.session.isComplete, isFalse);
      expect(_state(document), original);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
    });

    for (final scenario in ['caret', 'composition', 'document', 'revision']) {
      test('$scenario change refuses a pending $operation atomically', () {
        final document = operation == 'export'
            ? _activeDocument()
            : _transferDocument();
        final controller = _controller(document);
        final transaction = operation == 'export'
            ? _export(controller)
            : _import(controller);
        _complete(transaction);
        switch (scenario) {
          case 'caret':
            controller.caret.logicalIndex = 1;
          case 'composition':
            controller.input.setValue(
              TextEditingValue(
                text: document.paragraphs.first.text,
                selection: const TextSelection.collapsed(offset: 1),
                composing: const TextRange(start: 0, end: 1),
              ),
            );
          case 'document':
            controller.document = WmlDocument.empty(text: 'Replacement');
          case 'revision':
            controller.insertText('New ');
        }
        final beforeApply = _state(document);
        expect(() => transaction.assertCurrent(), throwsStateError);
        expect(() => transaction.apply(), throwsStateError);
        expect(_state(document), beforeApply);
      });
    }
  }

  for (final command in [
    ZoteroCitingCommand.addEditCitation,
    ZoteroCitingCommand.addEditBibliography,
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
    ZoteroCitingCommand.setDocPrefs,
    ZoteroCitingCommand.exportDocument,
    ZoteroCitingCommand.removeCodes,
  ]) {
    test('transfer documents require Refresh before ${command.name}', () {
      final document = _transferDocument();
      final controller = _controller(document);
      final before = _state(document);
      expect(
        () => controller.beginZoteroTransaction(
          documentId: _documentId,
          command: command,
        ),
        throwsUnsupportedError,
      );
      expect(_state(document), before);
      expect(controller.canUndo, isFalse);
    });
  }
}
