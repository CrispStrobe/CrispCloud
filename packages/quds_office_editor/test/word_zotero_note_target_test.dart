import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _documentId = 'notes-pane-zotero';

ZoteroCitation _citation(String id, String text, {int noteIndex = 0}) =>
    ZoteroCitation(
      citationId: id,
      plainCitation: text,
      noteIndex: noteIndex,
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {
            'id': id,
            'type': 'book',
            'title': 'Notes source $id',
            'author': [
              {'family': 'Lovelace', 'given': 'Ada'},
            ],
          },
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
          locator: '34',
          label: 'page',
        ),
      ],
    );

({WordEditorController controller, WmlNote note}) _fixture({
  bool endnote = false,
  String first = 'LeftRight',
  String? second,
  bool marker = true,
}) {
  final note = WmlNote(
    id: 1,
    endnote: endnote,
    addReference: marker,
    addReferenceSpace: marker,
    paragraphs: [
      WmlParagraph(
        inlines: [
          if (marker)
            WmlNoteMarker(
              endnote: endnote,
              properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
            ),
          WmlRun(
            text: '${marker ? ' ' : ''}$first',
            properties: WmlRunProps(bold: true),
          ),
        ],
      ),
      if (second != null) WmlParagraph(inlines: [WmlRun(text: second)]),
    ],
  );
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(
            inlines: [
              WmlRun(text: 'Body '),
              WmlRun(text: '1', noteRefId: 1, noteRefEndnote: endnote),
              WmlRun(text: ' tail'),
            ],
          ),
        ],
      ),
    ],
    footnotes: endnote ? [] : [note],
    endnotes: endnote ? [note] : [],
  );
  final controller = WordEditorController(document: document);
  controller.caret.logicalIndex = 2;
  controller.caret.collapseSelection();
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return (controller: controller, note: note);
}

WordZoteroTransaction _begin(WordEditorController controller) =>
    controller.beginZoteroTransaction(documentId: _documentId);

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> args = const [],
]) {
  transaction.assertCurrent();
  return transaction.session.handle(command, [_documentId, ...args]);
}

void _set(
  WordZoteroTransaction transaction,
  String fieldId,
  ZoteroCitation citation,
) {
  _call(transaction, 'Field.setCode', [
    fieldId,
    'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
  ]);
  _call(transaction, 'Field.setText', [fieldId, citation.plainCitation, false]);
}

void _complete(WordZoteroTransaction transaction) {
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

WordZoteroTransaction _preparedInsertion(WordEditorController controller) {
  final transaction = _begin(controller);
  final inserted =
      _call(transaction, 'Document.insertField', ['Http', 0]) as Map;
  _set(transaction, inserted['id'] as String, _citation('new', '(Ada)'));
  _complete(transaction);
  return transaction;
}

List<Object?> _paragraph(WmlParagraph paragraph) => [
  paragraph.text,
  paragraph.properties.fieldInstruction,
  for (final inline in paragraph.inlines)
    if (inline is WmlRun)
      [
        inline.text,
        inline.fieldInstruction,
        inline.fieldLocked,
        inline.noteRefId,
        inline.noteRefEndnote,
        inline.properties.bold,
        inline.properties.italic,
      ]
    else if (inline is WmlNoteMarker)
      ['note-marker', inline.endnote],
];

String _state(WmlDocument document) => jsonEncode({
  'body': document.paragraphs.map(_paragraph).toList(),
  'footnotes': [
    for (final note in document.footnotes)
      [note.id, note.allParagraphs.map(_paragraph).toList()],
  ],
  'endnotes': [
    for (final note in document.endnotes)
      [note.id, note.allParagraphs.map(_paragraph).toList()],
  ],
  'preferences': WordZoteroDocumentData.read(document),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final endnote in [false, true]) {
    final kind = endnote ? 'endnote' : 'footnote';

    test('$kind target preserves the body caret and clean history', () {
      final (:controller, :note) = _fixture(endnote: endnote);
      final before = _state(controller.document);
      final revision = controller.contentRevision;
      controller.setNoteEditingTarget(
        note,
        const TextSelection(baseOffset: 6, extentOffset: 2),
      );
      expect(controller.noteEditingTarget?.note, same(note));
      expect(
        controller.noteEditingTarget?.selection,
        const TextSelection(baseOffset: 6, extentOffset: 2),
      );
      expect(controller.noteEditingTarget?.composing, TextRange.empty);
      expect(controller.caret.logicalIndex, 2);
      expect(controller.caret.isCollapsed, isTrue);
      expect(_state(controller.document), before);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      controller.clearNoteEditingTarget();
      expect(controller.noteEditingTarget, isNull);
      expect(controller.caret.logicalIndex, 2);
    });

    test('$kind field lookup accounts for the hidden marker separator', () {
      final (:controller, :note) = _fixture(endnote: endnote, first: 'Left');
      final paragraph = note.paragraphs.first;
      WordZotero.insertCitation(paragraph, _citation('existing', '(Ada)'));
      paragraph.inlines.add(WmlRun(text: 'Right'));
      expect(controller.noteEditText(note), 'Left(Ada)Right');
      expect(controller.zoteroFields.single.start, 5);
      for (final offset in [4, 5, 8]) {
        controller.setNoteEditingTarget(
          note,
          TextSelection.collapsed(offset: offset),
        );
        expect(controller.zoteroFieldAtCaret?.citation?.citationId, 'existing');
      }
      for (final offset in [0, 3, 9, 10]) {
        controller.setNoteEditingTarget(
          note,
          TextSelection.collapsed(offset: offset),
        );
        expect(controller.zoteroFieldAtCaret, isNull);
      }
      controller.setNoteEditingTarget(
        note,
        const TextSelection(baseOffset: 9, extentOffset: 4),
      );
      expect(controller.zoteroFieldAtCaret?.citation?.citationId, 'existing');
      controller.setNoteEditingTarget(
        note,
        const TextSelection(baseOffset: 3, extentOffset: 9),
      );
      expect(controller.zoteroFieldAtCaret, isNull);
    });

    test('$kind second paragraph uses pane offsets for field lookup', () {
      final (:controller, :note) = _fixture(
        endnote: endnote,
        first: 'First',
        second: 'Next ',
      );
      final paragraph = note.paragraphs.last;
      WordZotero.insertCitation(paragraph, _citation('second', '(Ada)'));
      paragraph.inlines.add(WmlRun(text: ' after'));
      expect(controller.noteEditText(note), 'First\nNext (Ada) after');
      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 12),
      );
      final field = controller.zoteroFieldAtCaret;
      expect(field?.paragraph, same(paragraph));
      expect(field?.citation?.citationId, 'second');
      final transaction = _begin(controller);
      final active =
          _call(transaction, 'Document.cursorInField', ['Http']) as Map;
      expect(active['text'], '(Ada)');
      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 16),
      );
      expect(controller.zoteroFieldAtCaret, isNull);
    });

    for (final requestedType in [0, endnote ? 2 : 1]) {
      test(
        '$kind native insertion with type $requestedType keeps note ownership and undo',
        () {
          final (:controller, :note) = _fixture(endnote: endnote);
          final paragraph = note.paragraphs.first;
          final body = controller.document.paragraphs.single;
          final before = _state(controller.document);
          controller.setNoteEditingTarget(
            note,
            const TextSelection.collapsed(offset: 4),
          );
          final transaction = _begin(controller);
          expect(transaction.session.insertionParagraph, same(paragraph));
          expect(transaction.session.insertionOffset, 5);
          expect(
            _call(transaction, 'Document.canInsertField', ['Http']),
            isTrue,
          );
          final inserted =
              _call(transaction, 'Document.insertField', [
                    'Http',
                    requestedType,
                  ])
                  as Map;
          expect(inserted['noteIndex'], 1);
          _set(
            transaction,
            inserted['id'] as String,
            _citation('new', '(Ada)', noteIndex: 1),
          );
          _complete(transaction);
          expect(_state(controller.document), before);
          transaction.apply();
          expect(controller.noteEditText(note), 'Left(Ada)Right');
          expect(body.text, 'Body 1 tail');
          expect(controller.document.footnotes, hasLength(endnote ? 0 : 1));
          expect(controller.document.endnotes, hasLength(endnote ? 1 : 0));
          expect(controller.zoteroFields.single.paragraph, same(paragraph));
          expect(controller.zoteroFields.single.citation!.noteIndex, 1);
          expect(controller.noteEditingTarget?.note, same(note));
          expect(
            controller.noteEditingTarget?.selection,
            const TextSelection.collapsed(offset: 9),
          );
          expect(controller.caret.logicalIndex, 2);
          final after = _state(controller.document);
          for (var cycle = 0; cycle < 2; cycle++) {
            controller.undo();
            expect(_state(controller.document), before);
            expect(controller.noteEditingTarget?.note, same(note));
            expect(
              controller.noteEditingTarget?.selection,
              const TextSelection.collapsed(offset: 4),
            );
            expect(controller.canUndo, isFalse);
            controller.redo();
            expect(_state(controller.document), after);
            expect(
              controller.noteEditingTarget?.selection,
              const TextSelection.collapsed(offset: 9),
            );
          }
          final reopened = WordDeserializer().readBytes(controller.saveBytes());
          final reopenedNote =
              (endnote ? reopened.endnotes : reopened.footnotes).single;
          expect(WordNotes.editableText(reopenedNote), 'Left(Ada)Right');
          expect(
            WordZotero.fields(reopened).single.citation!.citationId,
            'new',
          );
        },
      );
    }

    test(
      '$kind contained selection edits its citation and restores on undo',
      () {
        final (:controller, :note) = _fixture(endnote: endnote, first: 'Left');
        final paragraph = note.paragraphs.first;
        WordZotero.insertCitation(paragraph, _citation('existing', '(Ada)'));
        paragraph.inlines.add(WmlRun(text: 'Right'));
        const selection = TextSelection(baseOffset: 8, extentOffset: 5);
        controller.setNoteEditingTarget(note, selection);
        final transaction = _begin(controller);
        final active =
            _call(transaction, 'Document.cursorInField', ['Http']) as Map;
        _set(
          transaction,
          active['id'] as String,
          _citation('existing', '(Ada, p. 34)', noteIndex: 1),
        );
        _complete(transaction);
        transaction.apply();
        expect(controller.noteEditText(note), 'Left(Ada, p. 34)Right');
        expect(controller.zoteroFields, hasLength(1));
        expect(controller.noteEditingTarget?.note, same(note));
        controller.undo();
        expect(controller.noteEditText(note), 'Left(Ada)Right');
        expect(controller.noteEditingTarget?.selection, selection);
        expect(controller.canUndo, isFalse);
        controller.redo();
        expect(controller.noteEditText(note), 'Left(Ada, p. 34)Right');
        expect(controller.caret.logicalIndex, 2);
      },
    );

    test(
      '$kind local citation insertion retains metadata and selection history',
      () {
        final (:controller, :note) = _fixture(endnote: endnote);
        final before = _state(controller.document);
        controller.setNoteEditingTarget(
          note,
          const TextSelection.collapsed(offset: 4),
        );
        controller.insertZoteroCitation(_citation('imported', '(Ada)'));
        expect(controller.noteEditText(note), 'Left(Ada)Right');
        final field = controller.zoteroFields.single;
        expect(field.paragraph, same(note.paragraphs.first));
        expect(field.citation!.items.single.locator, '34');
        expect(
          field.citation!.items.single.itemData!['title'],
          'Notes source imported',
        );
        expect(field.run!.properties.bold, isTrue);
        expect(
          controller.noteEditingTarget?.selection,
          const TextSelection.collapsed(offset: 9),
        );
        expect(controller.document.paragraphs.single.text, 'Body 1 tail');
        final after = _state(controller.document);
        controller.undo();
        expect(_state(controller.document), before);
        expect(
          controller.noteEditingTarget?.selection,
          const TextSelection.collapsed(offset: 4),
        );
        expect(controller.canUndo, isFalse);
        controller.redo();
        expect(_state(controller.document), after);
        expect(
          controller.noteEditingTarget?.selection,
          const TextSelection.collapsed(offset: 9),
        );
      },
    );

    test(
      '$kind local second-paragraph insertion retains the first paragraph',
      () {
        final (:controller, :note) = _fixture(
          endnote: endnote,
          first: 'First',
          second: 'LeftRight',
        );
        final first = note.paragraphs.first;
        final second = note.paragraphs.last;
        controller.setNoteEditingTarget(
          note,
          const TextSelection.collapsed(offset: 10),
        );
        controller.insertZoteroCitation(_citation('second', '(Ada)'));
        expect(note.paragraphs.first, same(first));
        expect(first.text, ' First');
        expect(controller.noteEditText(note), 'First\nLeft(Ada)Right');
        expect(controller.zoteroFields.single.paragraph, same(second));
        expect(
          controller.noteEditingTarget?.selection,
          const TextSelection.collapsed(offset: 15),
        );
        controller.undo();
        expect(controller.noteEditText(note), 'First\nLeftRight');
        expect(
          controller.noteEditingTarget?.selection,
          const TextSelection.collapsed(offset: 10),
        );
      },
    );

    test(
      '$kind local bibliography insertion is refused without a body fallback',
      () {
        final (:controller, :note) = _fixture(endnote: endnote);
        controller.setNoteEditingTarget(
          note,
          const TextSelection.collapsed(offset: 4),
        );
        final before = _state(controller.document);
        expect(
          () => controller.insertZoteroBibliography(text: 'References'),
          throwsUnsupportedError,
        );
        expect(_state(controller.document), before);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      },
    );

    test('$kind native bibliography insertion is refused atomically', () {
      final (:controller, :note) = _fixture(endnote: endnote);
      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 4),
      );
      final before = _state(controller.document);
      final transaction = _begin(controller);
      final inserted =
          _call(transaction, 'Document.insertField', ['Http', 0]) as Map;
      expect(() {
        _call(transaction, 'Field.setCode', [
          inserted['id'],
          'BIBL {} CSL_BIBLIOGRAPHY',
        ]);
        _call(transaction, 'Field.setText', [
          inserted['id'],
          'References',
          false,
        ]);
        _complete(transaction);
        transaction.apply();
      }, throwsUnsupportedError);
      expect(_state(controller.document), before);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
    });
  }

  test('imported leading whitespace remains part of the note selection', () {
    final (:controller, :note) = _fixture(first: ' LeftRight', marker: false);
    expect(controller.noteEditText(note), ' LeftRight');
    controller.setNoteEditingTarget(
      note,
      const TextSelection.collapsed(offset: 1),
    );
    final transaction = _begin(controller);
    expect(transaction.session.insertionOffset, 1);
    controller.insertZoteroCitation(_citation('imported-space', '(Ada)'));
    expect(controller.noteEditText(note), ' (Ada)LeftRight');
    expect(
      controller.noteEditingTarget?.selection,
      const TextSelection.collapsed(offset: 6),
    );
  });

  test('foreign notes and invalid selections never replace a valid target', () {
    final (:controller, :note) = _fixture();
    const selection = TextSelection.collapsed(offset: 4);
    controller.setNoteEditingTarget(note, selection);
    final before = controller.noteEditingTarget;
    expect(
      () => controller.setNoteEditingTarget(
        WmlNote(id: note.id, endnote: note.endnote),
        selection,
      ),
      throwsStateError,
    );
    for (final invalid in [
      const TextSelection.collapsed(offset: -1),
      const TextSelection.collapsed(offset: 10),
      const TextSelection(baseOffset: 0, extentOffset: 10),
    ]) {
      expect(
        () => controller.setNoteEditingTarget(note, invalid),
        throwsArgumentError,
      );
      expect(controller.noteEditingTarget, before);
    }
    expect(
      () => controller.setNoteEditingTarget(
        note,
        selection,
        composing: const TextRange(start: 0, end: 10),
      ),
      throwsArgumentError,
    );
    expect(controller.noteEditingTarget, before);
    expect(controller.isDirty, isFalse);
  });

  test('body caret navigation invalidates the note target', () {
    final (:controller, :note) = _fixture();
    controller.setNoteEditingTarget(
      note,
      const TextSelection.collapsed(offset: 4),
    );
    controller.caret.logicalIndex = 3;
    controller.caret.collapseSelection();
    expect(controller.noteEditingTarget, isNull);
    final transaction = _begin(controller);
    expect(
      transaction.session.insertionParagraph,
      same(controller.document.paragraphs.single),
    );
    expect(transaction.session.insertionOffset, 3);
  });

  test('note selection spanning paragraphs never inserts into the body', () {
    final (:controller, :note) = _fixture(first: 'First', second: 'Second');
    controller.setNoteEditingTarget(
      note,
      const TextSelection(baseOffset: 3, extentOffset: 8),
    );
    final before = _state(controller.document);
    expect(controller.zoteroFieldAtCaret, isNull);
    final transaction = _begin(controller);
    expect(_call(transaction, 'Document.canInsertField', ['Http']), isFalse);
    expect(
      () => _call(transaction, 'Document.insertField', ['Http', 0]),
      throwsUnsupportedError,
    );
    expect(
      () => controller.insertZoteroCitation(_citation('crossing', '(Ada)')),
      throwsUnsupportedError,
    );
    expect(_state(controller.document), before);
    expect(controller.canUndo, isFalse);
  });

  test('active note IME composition prevents native and local insertion', () {
    final (:controller, :note) = _fixture();
    controller.setNoteEditingTarget(
      note,
      const TextSelection.collapsed(offset: 4),
      composing: const TextRange(start: 1, end: 4),
    );
    final before = _state(controller.document);
    expect(() => _begin(controller), throwsStateError);
    expect(
      () => controller.insertZoteroCitation(_citation('composing', '(Ada)')),
      throwsStateError,
    );
    expect(_state(controller.document), before);
    expect(controller.canUndo, isFalse);
    controller.setNoteEditingTarget(
      note,
      const TextSelection.collapsed(offset: 4),
    );
    expect(
      _call(_begin(controller), 'Document.canInsertField', ['Http']),
      isTrue,
    );
  });

  for (final scenario in [
    'selection',
    'other note',
    'clear',
    'deletion',
    'IME',
  ]) {
    test('$scenario change invalidates a pending note citation result', () {
      final (:controller, :note) = _fixture();
      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 4),
      );
      final transaction = _preparedInsertion(controller);
      switch (scenario) {
        case 'selection':
          controller.setNoteEditingTarget(
            note,
            const TextSelection.collapsed(offset: 5),
          );
        case 'other note':
          final other = WordNotes.insert(
            controller.document,
            controller.document.paragraphs.single,
            endnote: true,
            text: 'Another note',
          );
          controller.setNoteEditingTarget(
            other,
            const TextSelection.collapsed(offset: 4),
          );
        case 'clear':
          controller.clearNoteEditingTarget();
        case 'deletion':
          controller.deleteNote(note);
        case 'IME':
          controller.setNoteEditingTarget(
            note,
            const TextSelection.collapsed(offset: 4),
            composing: const TextRange(start: 1, end: 4),
          );
      }
      final current = _state(controller.document);
      final revision = controller.contentRevision;
      expect(() => transaction.assertCurrent(), throwsStateError);
      expect(() => transaction.apply(), throwsStateError);
      expect(_state(controller.document), current);
      expect(controller.contentRevision, revision);
      expect(controller.zoteroFields, isEmpty);
    });
  }

  for (final scenario in [
    'detached note',
    'replaced paragraph',
    'changed text',
  ]) {
    test('direct host $scenario rejects the detached note result', () {
      final (:controller, :note) = _fixture();
      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 4),
      );
      final transaction = _preparedInsertion(controller);
      switch (scenario) {
        case 'detached note':
          controller.document.footnotes.remove(note);
        case 'replaced paragraph':
          note.paragraphs[0] = WmlClone.paragraph(note.paragraphs.first);
        case 'changed text':
          note.paragraphs.first.inlines.add(WmlRun(text: '!'));
      }
      final current = _state(controller.document);
      expect(() => transaction.apply(), throwsStateError);
      expect(_state(controller.document), current);
      expect(controller.zoteroFields, isEmpty);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
    });
  }
}
