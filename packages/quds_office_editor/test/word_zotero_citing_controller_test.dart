import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _documentId = 'controller-zotero-test';
const _preferences =
    '<data data-version="3"><session id="test-session"/>'
    '<style id="http://www.zotero.org/styles/chicago-note-bibliography" '
    'locale="de-DE" hasBibliography="1"/>'
    '<prefs><pref name="fieldType" value="Http"/>'
    '<pref name="noteType" value="1"/></prefs></data>';
const _initialInlinePreferences =
    '<data data-version="3"><session id="before-session"/>'
    '<style id="http://www.zotero.org/styles/nature" '
    'locale="en-US" hasBibliography="1"/>'
    '<prefs><pref name="fieldType" value="Field"/>'
    '<pref name="noteType" value="0"/></prefs></data>';

String get _updatedInlinePreferences => WordZoteroDocumentData.toHttp(
  _initialInlinePreferences
      .replaceAll('before-session', 'after-session')
      .replaceAll('locale="en-US"', 'locale="de-DE"'),
);

ZoteroCitation _citation(String id, String text, {int note = 0}) =>
    ZoteroCitation(
      citationId: id,
      plainCitation: text,
      noteIndex: note,
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {
            'id': id,
            'type': 'book',
            'title': 'Source $id',
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

WordEditorController _controller({WmlDocument? document}) {
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: 'LeftRight'),
  );
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
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

WordZoteroTransaction _begin(
  WordEditorController controller, {
  ZoteroCitation? seed,
}) => controller.beginZoteroTransaction(
  documentId: _documentId,
  seedCitation: seed,
);

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> args = const [],
]) {
  transaction.assertCurrent();
  return transaction.session.handle(command, [_documentId, ...args]);
}

List<Map<String, Object>> _fields(WordZoteroTransaction transaction) =>
    (_call(transaction, 'Document.getFields', ['Http']) as List)
        .cast<Map<String, Object>>();

void _set(
  WordZoteroTransaction transaction,
  String field,
  ZoteroCitation citation, {
  String? html,
}) {
  _call(transaction, 'Field.setCode', [
    field,
    'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
  ]);
  _call(transaction, 'Field.setText', [
    field,
    html ?? citation.plainCitation,
    html != null,
  ]);
}

void _complete(WordZoteroTransaction transaction) {
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

List<Object?> _paragraph(WmlParagraph paragraph) => [
  paragraph.text,
  paragraph.properties.noteId,
  paragraph.properties.endnoteRef,
  paragraph.properties.fieldInstruction,
  paragraph.properties.pageNumberField,
  for (final run in paragraph.inlines.whereType<WmlRun>())
    [
      run.text,
      run.fieldInstruction,
      run.fieldLocked,
      run.noteRefId,
      run.noteRefEndnote,
      run.properties.bold,
      run.properties.italic,
      run.properties.vertAlign.name,
    ],
];

String _state(WmlDocument document) => jsonEncode({
  'body': document.paragraphs.map(_paragraph).toList(),
  'footnotes': [
    for (final note in document.footnotes)
      [note.id, note.endnote, note.allParagraphs.map(_paragraph).toList()],
  ],
  'endnotes': [
    for (final note in document.endnotes)
      [note.id, note.endnote, note.allParagraphs.map(_paragraph).toList()],
  ],
  'data': WordZoteroDocumentData.read(document),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all processor calls remain detached until complete and explicit apply',
    () {
      final controller = _controller(document: _twoFields());
      final before = _state(controller.document);
      final revision = controller.contentRevision;
      final transaction = _begin(controller);
      final fields = _fields(transaction);
      _set(
        transaction,
        fields[0]['id'] as String,
        _citation('a', 'A longer author citation'),
      );
      _set(transaction, fields[1]['id'] as String, _citation('b', 'Ebd. (34)'));
      _call(transaction, 'Document.setDocumentData', [_preferences]);
      expect(_state(controller.document), before);
      expect(() => transaction.apply(), throwsStateError);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      _complete(transaction);
      expect(_state(controller.document), before);
      transaction.apply();
      expect(
        controller.document.paragraphs.single.text,
        'Before A longer author citation between Ebd. (34) after',
      );
      expect(
        WordZoteroDocumentData.read(controller.document),
        contains('value="Field"'),
      );
      expect(controller.contentRevision, greaterThan(revision));
      final after = _state(controller.document);
      controller.undo();
      expect(_state(controller.document), before);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_state(controller.document), after);
      expect(() => transaction.apply(), throwsStateError);
    },
  );

  test('refresh undo restores the original noncollapsed text selection', () {
    final controller = _controller(document: _twoFields());
    controller.caret.logicalIndex = 4;
    controller.caret.selectionAnchor = 1;
    controller.caret.selectionAnchorParagraph = 0;
    final transaction = _begin(controller);
    final field = _fields(transaction).first;
    _set(transaction, field['id'] as String, _citation('a', 'Updated'));
    _complete(transaction);
    transaction.apply();
    controller.undo();
    expect(controller.caret.paragraphIndex, 0);
    expect(controller.caret.logicalIndex, 4);
    expect(controller.caret.selectionAnchorParagraph, 0);
    expect(controller.caret.selectionAnchor, 1);
    expect(controller.caret.isCollapsed, isFalse);
    expect(
      controller.document.paragraphs.single.text,
      'Before (A) between (B) after',
    );
  });

  test(
    'an explicitly selected citation edits in place without a new field',
    () {
      final controller = _controller(document: _twoFields());
      final selected = controller.zoteroFields.last;
      final transaction = controller.beginZoteroTransaction(
        documentId: _documentId,
        selectedField: selected,
      );
      final active =
          _call(transaction, 'Document.cursorInField', ['Http']) as Map;
      _set(transaction, active['id'] as String, _citation('b', 'Ebd. (35)'));
      _complete(transaction);
      transaction.apply();
      expect(controller.zoteroFields, hasLength(2));
      expect(controller.zoteroFields.last.citation!.citationId, 'b');
      expect(controller.zoteroFields.last.citation!.items.single.uris, [
        'http://zotero.org/users/42/items/ABCD1234',
      ]);
      expect(
        controller.document.paragraphs.single.text,
        'Before (A) between Ebd. (35) after',
      );
      controller.undo();
      expect(
        controller.document.paragraphs.single.text,
        'Before (A) between (B) after',
      );
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'new catalog citation, preferences and formatting form one undo step',
    () {
      final controller = _controller();
      controller.document.zoteroDocumentData = _initialInlinePreferences;
      controller.caret.logicalIndex = 4;
      controller.caret.collapseSelection();
      final transaction = _begin(controller, seed: _citation('new', 'New'));
      final newField = _fields(transaction).single;
      _set(
        transaction,
        newField['id'] as String,
        _citation('new', '1'),
        html: '<sup>1</sup>',
      );
      _call(transaction, 'Document.setDocumentData', [
        _updatedInlinePreferences,
      ]);
      _complete(transaction);
      transaction.apply();
      expect(controller.document.paragraphs.single.text, 'Left1Right');
      expect(controller.caret.logicalIndex, 5);
      expect(controller.caret.isCollapsed, isTrue);
      expect(controller.zoteroFields.single.citation!.citationId, 'new');
      expect(
        controller.zoteroFields.single.run!.properties.vertAlign,
        WmlVertAlign.superscript,
      );
      final after = _state(controller.document);
      final saved = WordDeserializer().readBytes(controller.saveBytes());
      expect(
        WordZotero.fields(saved).single.run!.properties.vertAlign,
        WmlVertAlign.superscript,
      );
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'LeftRight');
      expect(controller.caret.logicalIndex, 4);
      expect(controller.caret.isCollapsed, isTrue);
      expect(
        WordZoteroDocumentData.read(controller.document),
        WordZoteroDocumentData.toNative(_initialInlinePreferences),
      );
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_state(controller.document), after);
    },
  );

  for (final noteType in [1, 2]) {
    test(
      'native picker insertion into note type $noteType is fully undoable',
      () {
        final controller = _controller();
        controller.caret.logicalIndex = 4;
        controller.caret.collapseSelection();
        final before = _state(controller.document);
        final transaction = _begin(controller);
        final inserted =
            _call(transaction, 'Document.insertField', ['Http', noteType])
                as Map;
        _set(
          transaction,
          inserted['id'] as String,
          _citation('new-note', 'Ebd. (34)', note: 1),
        );
        _call(transaction, 'Document.setDocumentData', [_preferences]);
        _complete(transaction);
        transaction.apply();
        expect(controller.document.paragraphs.single.text, 'Left1Right');
        expect(controller.caret.logicalIndex, 5);
        expect(controller.caret.isCollapsed, isTrue);
        final notes = noteType == 1
            ? controller.document.footnotes
            : controller.document.endnotes;
        expect(notes.single.text, 'Ebd. (34)');
        final id = notes.single.id;
        final note = notes.single;
        final after = _state(controller.document);
        controller.undo();
        expect(_state(controller.document), before);
        expect(controller.caret.logicalIndex, 4);
        expect(controller.canUndo, isFalse);
        controller.redo();
        expect(_state(controller.document), after);
        expect(notes.single, same(note));
        expect(notes.single.id, id);
      },
    );
  }

  test(
    'two citations convert in descending order without losing surrounding text',
    () {
      final controller = _controller(document: _twoFields());
      final document = controller.document;
      final paragraph = document.paragraphs.single;
      final original = _state(document);
      final transaction = _begin(controller);
      final fields = _fields(transaction);
      _call(transaction, 'Document.convert', [
        fields.map((f) => f['id']).toList(),
        'Http',
        [1, 1],
      ]);
      _set(
        transaction,
        fields[0]['id'] as String,
        _citation('a', 'First source, p. 12', note: 1),
      );
      _set(
        transaction,
        fields[1]['id'] as String,
        _citation('b', 'Ebd. (34)', note: 2),
      );
      _call(transaction, 'Document.setDocumentData', [_preferences]);
      _complete(transaction);
      transaction.apply();
      final references = paragraph.inlines
          .whereType<WmlRun>()
          .where((run) => run.noteRefId != null)
          .toList();
      expect(references, hasLength(2));
      expect(
        paragraph.inlines
            .whereType<WmlRun>()
            .where((run) => run.noteRefId == null)
            .map((run) => run.text)
            .join(),
        'Before  between  after',
      );
      final sourceOrder = [
        for (final reference in references)
          WordZotero.fields(
            WmlDocument(
              footnotes: [
                document.footnotes.singleWhere(
                  (note) => note.id == reference.noteRefId,
                ),
              ],
            ),
          ).single.citation!.citationId,
      ];
      expect(sourceOrder, ['a', 'b']);
      final ids = references.map((run) => run.noteRefId).toList();
      expect(ids.toSet(), hasLength(2));
      final after = _state(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        controller.undo();
        expect(_state(document), original);
        expect(controller.canUndo, isFalse);
        controller.redo();
        expect(_state(document), after);
        expect(
          paragraph.inlines
              .whereType<WmlRun>()
              .where((run) => run.noteRefId != null)
              .map((run) => run.noteRefId),
          ids,
        );
      }
    },
  );

  test(
    'citation conversion retains an unrelated note reference in the same paragraph',
    () {
      final document = WmlDocument.empty(text: 'Before ');
      final paragraph = document.paragraphs.single;
      final unrelated = WordNotes.insert(
        document,
        paragraph,
        endnote: false,
        text: 'Unrelated explanatory note',
      );
      paragraph.inlines.add(WmlRun(text: ' between '));
      WordZotero.insertCitation(paragraph, _citation('moving', '(A)'));
      paragraph.inlines.add(WmlRun(text: ' after'));
      final controller = _controller(document: document);
      final original = _state(document);
      final transaction = _begin(controller);
      final id = _fields(transaction).single['id'];
      _call(transaction, 'Document.convert', [
        [id],
        'Http',
        [2],
      ]);
      _complete(transaction);
      transaction.apply();
      expect(document.footnotes.single, same(unrelated));
      expect(document.footnotes.single.text, 'Unrelated explanatory note');
      expect(document.endnotes, hasLength(1));
      expect(
        paragraph.inlines.whereType<WmlRun>().where(
          (run) => run.noteRefId == unrelated.id && !run.noteRefEndnote,
        ),
        hasLength(1),
      );
      final after = _state(document);
      controller.undo();
      expect(_state(document), original);
      controller.redo();
      expect(_state(document), after);
    },
  );

  test(
    'undo after DOCX save restores native preferences and note ownership',
    () {
      final controller = _controller(document: _twoFields());
      final document = controller.document;
      final original = _state(document);
      final transaction = _begin(controller);
      final fields = _fields(transaction);
      _call(transaction, 'Document.convert', [
        [fields[0]['id']],
        'Http',
        [1],
      ]);
      _call(transaction, 'Document.setDocumentData', [_preferences]);
      _complete(transaction);
      transaction.apply();
      final savedAfter = WordDeserializer().readBytes(controller.saveBytes());
      expect(savedAfter.footnotes, hasLength(1));
      expect(
        WordZoteroDocumentData.read(savedAfter),
        contains('locale="de-DE"'),
      );
      controller.undo();
      expect(_state(document), original);
      final savedUndo = WordDeserializer().readBytes(controller.saveBytes());
      expect(savedUndo.footnotes, isEmpty);
      expect(WordZoteroDocumentData.read(savedUndo), '');
      expect(
        WordZotero.fields(savedUndo).map((field) => field.citation!.citationId),
        ['a', 'b'],
      );
      controller.redo();
      final savedRedo = WordDeserializer().readBytes(controller.saveBytes());
      expect(savedRedo.footnotes, hasLength(1));
      expect(
        WordZoteroDocumentData.read(savedRedo),
        contains('locale="de-DE"'),
      );
    },
  );

  test(
    'late insertion refusal rolls back earlier field updates and leaves history clean',
    () {
      final document = WmlDocument.empty(text: 'Page result');
      document.zoteroDocumentData = _initialInlinePreferences;
      final first = document.paragraphs.single;
      first.properties.pageNumberField = true;
      first.properties.fieldInstruction = ' PAGE ';
      final last = WmlParagraph(inlines: [WmlRun(text: 'Later ')]);
      WordZotero.insertCitation(last, _citation('existing', '(A)'));
      document.sections.single.blocks.add(last);
      final controller = _controller(document: document);
      final before = _state(document);
      final revision = controller.contentRevision;
      final transaction = _begin(controller, seed: _citation('new', 'new'));
      final fields = _fields(transaction);
      _set(
        transaction,
        fields.first['id'] as String,
        _citation('new', 'New citation'),
      );
      _set(
        transaction,
        fields.last['id'] as String,
        _citation('existing', 'Earlier applied change'),
      );
      _call(transaction, 'Document.setDocumentData', [
        _updatedInlinePreferences,
      ]);
      _complete(transaction);
      expect(() => transaction.apply(), throwsUnsupportedError);
      expect(_state(document), before);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
    },
  );

  test('locked field introduced during review refuses the whole result', () {
    final controller = _controller(document: _twoFields());
    final transaction = _begin(controller);
    final fields = _fields(transaction);
    for (var index = 0; index < fields.length; index++) {
      _set(
        transaction,
        fields[index]['id'] as String,
        _citation(index == 0 ? 'a' : 'b', 'Changed $index'),
      );
    }
    _complete(transaction);
    controller.zoteroFields.first.run!.fieldLocked = true;
    final protectedState = _state(controller.document);
    expect(() => transaction.apply(), throwsStateError);
    expect(_state(controller.document), protectedState);
    expect(controller.canUndo, isFalse);
    expect(controller.isDirty, isFalse);
  });

  for (final scenario in [
    'caret',
    'selection',
    'revision',
    'view mode',
    'track changes',
    'protection',
    'document',
    'dispose',
  ]) {
    test('$scenario change invalidates a pending processor result', () {
      final controller = _controller(document: _twoFields());
      final originalDocument = controller.document;
      final transaction = _begin(controller);
      final first = _fields(transaction).first;
      _set(
        transaction,
        first['id'] as String,
        _citation('a', 'Should not apply'),
      );
      _complete(transaction);
      switch (scenario) {
        case 'caret':
          controller.caret.logicalIndex = 1;
        case 'selection':
          controller.caret.selectionAnchor = 1;
        case 'revision':
          controller.insertText('X');
        case 'view mode':
          controller.setMode(OfficeInteractionMode.viewing);
        case 'track changes':
          controller.document.trackRevisions = true;
        case 'protection':
          controller.document.restrictEditing = true;
        case 'document':
          controller.document = WmlDocument.empty(text: 'Different');
        case 'dispose':
          controller.dispose();
      }
      final unchanged = _state(originalDocument);
      expect(() => transaction.assertCurrent(), throwsStateError);
      expect(() => transaction.apply(), throwsStateError);
      expect(_state(originalDocument), unchanged);
      expect(WordZotero.fields(originalDocument).first.cachedText, '(A)');
    });
  }

  test('processor cancellation, canceled seed and no-op keep clean history', () {
    final controller = _controller();
    controller.document.zoteroDocumentData = _initialInlinePreferences;
    final before = _state(controller.document);
    final revision = controller.contentRevision;
    final canceled = _begin(
      controller,
      seed: _citation('canceled', '(Canceled)'),
    );
    expect(_fields(canceled), hasLength(1));
    // The caller can simply discard an incomplete transaction on cancellation.
    expect(_state(controller.document), before);
    final canceledAtZotero = _begin(
      controller,
      seed: _citation('canceled-again', '(Canceled)'),
    );
    _complete(canceledAtZotero);
    canceledAtZotero.apply();
    final noop = _begin(controller);
    _complete(noop);
    noop.apply();
    expect(_state(controller.document), before);
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
    expect(controller.isDirty, isFalse);
  });

  test(
    'new bibliography block and preferences have one undo and retain paragraph identities',
    () {
      final controller = _controller(document: _twoFields());
      final document = controller.document;
      final original = document.paragraphs.single;
      final before = _state(document);
      final transaction = _begin(controller);
      final inserted =
          _call(transaction, 'Document.insertField', ['Http', 0]) as Map;
      _call(transaction, 'Field.setCode', [
        inserted['id'],
        'BIBL {} CSL_BIBLIOGRAPHY',
      ]);
      _call(transaction, 'Field.setText', [
        inserted['id'],
        '<div class="csl-entry"><i>Book</i>. Author.</div>',
        true,
      ]);
      _call(transaction, 'Document.setDocumentData', [_preferences]);
      _complete(transaction);
      transaction.apply();
      expect(document.paragraphs, hasLength(2));
      expect(document.paragraphs.first, same(original));
      final bibliography = document.paragraphs.last;
      final after = _state(document);
      controller.undo();
      expect(_state(document), before);
      expect(document.paragraphs.single, same(original));
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_state(document), after);
      expect(document.paragraphs.last, same(bibliography));
    },
  );
}
