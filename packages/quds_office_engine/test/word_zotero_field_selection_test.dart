import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _id = 'field-selection';
const _bibliographyCode =
    ' ADDIN ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY ';

ZoteroCitation _citation(String id, [String text = '(Original)']) =>
    ZoteroCitation(
      citationId: id,
      plainCitation: text,
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: <String, Object?>{
            'id': id,
            'type': 'book',
            'title': 'Source $id',
          },
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
        ),
      ],
    );

String _code(String id) =>
    'ITEM CSL_CITATION ${jsonEncode(_citation(id).toJson())}';

WmlDocument _document() {
  final document = WmlDocument.empty(text: 'Before  after');
  WordZotero.insertCitation(
    document.paragraphs.single,
    _citation('original'),
    index: 7,
  );
  return document;
}

WordZoteroCitingSession _session(
  WmlDocument document, {
  WmlParagraph? paragraph,
  int offset = 0,
  WmlZoteroField? selected,
}) => WordZoteroCitingSession(
  document: document,
  documentId: _id,
  insertionParagraph: paragraph ?? document.paragraphs.first,
  insertionOffset: offset,
  selectedField: selected,
);

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, [_id, ...arguments]);

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http'])! as List<Object?>)
        .cast<Map<String, Object>>();

String _snapshot(WmlDocument document) => jsonEncode(<String, Object?>{
  'body': document.paragraphs.map((paragraph) => paragraph.text).toList(),
  'notes': [
    for (final note in [...document.footnotes, ...document.endnotes])
      <String, Object?>{
        'id': note.id,
        'endnote': note.endnote,
        'text': note.text,
      },
  ],
  'fields': [
    for (final field in WordZotero.fields(document))
      <String, Object?>{
        'code': field.instruction,
        'text': field.cachedText,
        'start': field.start,
        'end': field.end,
      },
  ],
  'preferences': document.zoteroDocumentData,
});

void _expectNoSource(
  WordZoteroFieldSelectionContext context,
  WordZoteroFieldSelectionSource source,
) {
  expect(context.source, source);
  expect(context.sourceField, isNull);
  expect(context.sourceNote, isNull);
  expect(context.sourceRanges, isEmpty);
  expect(context.sourceText, isNull);
}

void main() {
  test(
    'implicit cursor and constructor selection do not request a highlight',
    () {
      final document = _document();
      final original = WordZotero.fields(document).single;
      for (final session in [
        _session(document, offset: original.start + 1),
        _session(document, selected: original),
      ]) {
        expect(_call(session, 'Document.cursorInField', ['Http']), isNotNull);
        expect(session.selectedFieldContext, isNull);
      }
    },
  );

  test('explicit selection exposes original source despite staged updates', () {
    final document = _document();
    final paragraph = document.paragraphs.single;
    final before = _snapshot(document);
    final session = _session(document);
    final fieldId = _fields(session).single['id'];
    _call(session, 'Field.select', [fieldId]);
    expect(session.hasChanges, isFalse);
    _call(session, 'Field.setText', [fieldId, '<i>(New result)</i>', true]);
    _call(session, 'Field.setCode', [fieldId, _code('new')]);
    _call(session, 'Document.convert', [
      [fieldId],
      'Http',
      [1],
    ]);

    final context = session.selectedFieldContext!;
    expect(context.fieldId, fieldId);
    expect(context.source, WordZoteroFieldSelectionSource.document);
    expect(context.kind, ZoteroFieldKind.citation);
    expect(context.sourceText, '(Original)');
    expect(context.sourceField!.citation!.citationId, 'original');
    expect(context.sourceNote, isNull);
    expect(context.sourceRanges, [
      (paragraph: paragraph, start: 7, end: 7 + '(Original)'.length),
    ]);
    expect(() => context.sourceRanges.clear(), throwsUnsupportedError);
    expect(_snapshot(document), before);
    expect(session.hasChanges, isTrue);
  });

  test('later select replaces context without moving any source text', () {
    final document = _document();
    final paragraph = document.paragraphs.single;
    WordZotero.insertCitation(paragraph, _citation('second', '(Second)'));
    final before = _snapshot(document);
    final session = _session(document);
    final fields = _fields(session);
    _call(session, 'Field.select', [fields.first['id']]);
    _call(session, 'Field.select', [fields.last['id']]);
    final context = session.selectedFieldContext!;
    expect(context.fieldId, fields.last['id']);
    expect(context.sourceText, '(Second)');
    expect(context.sourceField!.citation!.citationId, 'second');
    expect(_snapshot(document), before);
    expect(session.hasChanges, isFalse);
  });

  for (final endnote in [false, true]) {
    test(
      'selection identifies the original ${endnote ? 'endnote' : 'footnote'}',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'Note prose ',
        );
        final paragraph = note.paragraphs.single;
        WordZotero.insertCitation(paragraph, _citation('note'));
        final original = WordZotero.fields(document).single;
        final before = _snapshot(document);
        final session = _session(document);
        _call(session, 'Field.select', [_fields(session).single['id']]);
        final context = session.selectedFieldContext!;
        expect(context.sourceNote, same(note));
        expect(context.sourceField!.paragraph, same(paragraph));
        expect(context.sourceRanges, [
          (paragraph: paragraph, start: original.start, end: original.end),
        ]);
        expect(_snapshot(document), before);
      },
    );
  }

  test('multipart bibliography exposes every unchanged entry range', () {
    final entries = WordZotero.nativeBibliographyParagraphs(
      instruction: _bibliographyCode,
      text: 'First entry\nSecond entry\nThird entry',
    );
    final document = WmlDocument(sections: [WmlSection(blocks: entries)]);
    final before = _snapshot(document);
    final session = _session(document);
    final fieldId = _fields(session).single['id'];
    _call(session, 'Field.select', [fieldId]);
    _call(session, 'Field.setText', [fieldId, 'New bibliography', false]);
    final context = session.selectedFieldContext!;
    expect(context.kind, ZoteroFieldKind.bibliography);
    expect(context.sourceText, 'First entry\nSecond entry\nThird entry');
    expect(context.sourceRanges, [
      for (final paragraph in entries)
        (paragraph: paragraph, start: 0, end: paragraph.text.length),
    ]);
    expect(_snapshot(document), before);
  });

  test('new field reports a staged insertion without a live source', () {
    final document = WmlDocument.empty(text: 'Body');
    final session = _session(document);
    final inserted =
        _call(session, 'Document.insertField', ['Http', 1])!
            as Map<String, Object>;
    expect(session.selectedFieldContext, isNull);
    _call(session, 'Field.select', [inserted['id']]);
    final temporary = session.selectedFieldContext!;
    _expectNoSource(temporary, WordZoteroFieldSelectionSource.stagedInsertion);
    expect(temporary.kind, isNull);
    _call(session, 'Field.setCode', [inserted['id'], _code('new')]);
    _call(session, 'Field.setText', [inserted['id'], '(Pending)', false]);
    final assigned = session.selectedFieldContext!;
    _expectNoSource(assigned, WordZoteroFieldSelectionSource.stagedInsertion);
    expect(assigned.kind, ZoteroFieldKind.citation);
    expect(document.footnotes, isEmpty);
    expect(WordZotero.fields(document), isEmpty);
    expect(document.paragraphs.single.text, 'Body');
  });

  test(
    'detached research-note placeholder never resolves into source prose',
    () {
      final document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: false,
        text: 'Existing note',
      );
      final session = _session(document, paragraph: note.paragraphs.single);
      final before = _snapshot(document);
      _call(session, 'Document.insertText', [
        '<p>Research <a href="https://www.zotero.org/?ABC123">(Pending)</a></p>',
      ]);
      final fields =
          (_call(session, 'Document.convertPlaceholdersToFields', [
                    ['ABC123'],
                    0,
                    'Http',
                  ])!
                  as List<Object?>)
              .cast<Map<String, Object>>();
      _call(session, 'Field.select', [fields.single['id']]);
      _expectNoSource(
        session.selectedFieldContext!,
        WordZoteroFieldSelectionSource.stagedInsertion,
      );
      expect(_snapshot(document), before);
    },
  );

  test('transfer import exposes no detached clone as a live source', () {
    final document = _document();
    final preferences = jsonEncode(<String, Object?>{
      'dataVersion': 4,
      'sessionID': 'selection-transfer',
      'style': <String, Object?>{
        'styleID': 'http://www.zotero.org/styles/apa',
        'hasBibliography': true,
      },
      'prefs': <String, Object?>{'fieldType': 'Field', 'noteType': 0},
    });
    document.zoteroDocumentData = preferences;
    WordZoteroTransfer.prepareExport(
      document,
      instructions: 'Open in the destination and click Refresh.',
      documentData: preferences,
    ).apply();
    final before = _snapshot(document);
    final session = _session(document);
    _call(session, 'Document.importDocument', ['Http']);
    final fieldId = _fields(session).single['id'];
    _call(session, 'Field.select', [fieldId]);
    final context = session.selectedFieldContext!;
    _expectNoSource(context, WordZoteroFieldSelectionSource.importedDocument);
    expect(context.kind, ZoteroFieldKind.citation);
    expect(context.fieldId, fieldId);
    expect(_snapshot(document), before);
    _call(session, 'Field.setText', [fieldId, '(Imported)', false]);
    _call(session, 'Document.complete');
    expect(session.selectedFieldContext, isNull);
    expect(_snapshot(document), before);
  });

  for (final command in ['Field.delete', 'Field.removeCode']) {
    test('$command clears only the explicitly selected field', () {
      final document = _document();
      WordZotero.insertCitation(
        document.paragraphs.single,
        _citation('second', '(Second)'),
      );
      final before = _snapshot(document);
      final session = _session(document);
      final fields = _fields(session);
      _call(session, 'Field.select', [fields.first['id']]);
      _call(session, command, [fields.last['id']]);
      expect(session.selectedFieldContext!.fieldId, fields.first['id']);
      _call(session, command, [fields.first['id']]);
      expect(session.selectedFieldContext, isNull);
      expect(
        () => _call(session, 'Field.select', [fields.first['id']]),
        throwsFormatException,
      );
      expect(_snapshot(document), before);
    });
  }

  test('completion clears explicit context before application', () {
    final document = _document();
    final before = _snapshot(document);
    final session = _session(document);
    _call(session, 'Field.select', [_fields(session).single['id']]);
    expect(session.selectedFieldContext, isNotNull);
    _call(session, 'Document.complete');
    expect(session.selectedFieldContext, isNull);
    expect(_snapshot(document), before);
    session.apply();
    expect(session.selectedFieldContext, isNull);
  });

  test('source text and note anchor changes invalidate context', () {
    final document = _document();
    final session = _session(document);
    _call(session, 'Field.select', [_fields(session).single['id']]);
    document.paragraphs.single.inlines.whereType<WmlRun>().first.text =
        'Changed';
    expect(() => session.selectedFieldContext, throwsStateError);

    final noteDocument = WmlDocument.empty(text: 'Body');
    final paragraph = noteDocument.paragraphs.single;
    final note = WordNotes.insert(noteDocument, paragraph, endnote: false);
    WordZotero.insertCitation(note.paragraphs.single, _citation('note'));
    final noteSession = _session(noteDocument);
    _call(noteSession, 'Field.select', [_fields(noteSession).single['id']]);
    paragraph.inlines.whereType<WmlRun>().last.noteRefId = 99;
    expect(() => noteSession.selectedFieldContext, throwsStateError);
  });

  test(
    'equivalent markup replacement returns the current live field handle',
    () {
      final document = _document();
      final original = WordZotero.fields(document).single;
      final session = _session(document);
      _call(session, 'Field.select', [_fields(session).single['id']]);
      final replacement = WmlRun(
        text: original.run!.text,
        properties: original.run!.properties.copy(),
        fieldInstruction: original.instruction,
      );
      final index = original.paragraph.inlines.indexOf(original.run!);
      original.paragraph.inlines[index] = replacement;
      final context = session.selectedFieldContext!;
      expect(context.sourceField!.run, same(replacement));
      expect(context.sourceField!.run, isNot(same(original.run)));
      expect(context.sourceText, original.cachedText);
    },
  );
}
