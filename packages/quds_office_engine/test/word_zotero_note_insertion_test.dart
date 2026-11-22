import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _documentId = 'note-insertion-test';

ZoteroCitation _citation(String id, String text, {int noteIndex = 0}) =>
    ZoteroCitation(
      citationId: id,
      plainCitation: text,
      noteIndex: noteIndex,
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
        ),
      ],
    );

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

String _preferences(int type) => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'note-test',
  'style': {
    'styleID': 'http://www.zotero.org/styles/chicago-note-bibliography',
    'locale': 'de-DE',
    'hasBibliography': true,
  },
  'prefs': {'fieldType': 'Http', 'noteType': type},
});

WordZoteroCitingSession _session(
  WmlDocument document,
  WmlParagraph paragraph,
  int offset, {
  ZoteroCitation? seed,
}) => WordZoteroCitingSession(
  document: document,
  documentId: _documentId,
  insertionParagraph: paragraph,
  insertionOffset: offset,
  seedCitation: seed,
);

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_documentId, ...args]);

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http']) as List)
        .cast<Map<String, Object>>();

String _citationId(Map<String, Object> field) =>
    (jsonDecode(
              (field['code']! as String).substring('ITEM CSL_CITATION '.length),
            )
            as Map)['citationID']
        as String;

Map<String, Object> _insert(WordZoteroCitingSession session, int type) =>
    (_call(session, 'Document.insertField', ['Http', type]) as Map)
        .cast<String, Object>();

void _set(
  WordZoteroCitingSession session,
  Map<String, Object> field,
  String id,
  String text, {
  String? html,
}) {
  final citation = _citation(id, text, noteIndex: field['noteIndex']! as int);
  _call(session, 'Field.setCode', [
    field['id'],
    'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
  ]);
  _call(session, 'Field.setText', [field['id'], html ?? text, html != null]);
}

void _apply(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

String _snapshot(WmlDocument document) => jsonEncode({
  'body': [for (final paragraph in document.paragraphs) paragraph.text],
  'notes': [
    for (final note in [...document.footnotes, ...document.endnotes])
      {
        'id': note.id,
        'endnote': note.endnote,
        'paragraphs': [
          for (final paragraph in note.allParagraphs) paragraph.text,
        ],
      },
  ],
  'fields': [
    for (final field in WordZotero.fields(document))
      {
        'instruction': field.instruction,
        'text': field.cachedText,
        'start': field.start,
        'end': field.end,
      },
  ],
  'data': WordZoteroDocumentData.read(document),
});

void main() {
  for (final endnote in [false, true]) {
    final label = endnote ? 'endnote' : 'footnote';
    final type = endnote ? 2 : 1;

    for (final requestedType in [0, type]) {
      test(
        '$label insertion with request type $requestedType preserves prose and rich text through DOCX',
        () {
          final document = WmlDocument.empty(text: 'Body ');
          final note = WordNotes.insert(
            document,
            document.paragraphs.single,
            endnote: endnote,
            text: 'See  for the discussion.',
          );
          final paragraph = note.paragraphs.single;
          (paragraph.inlines.single as WmlRun).properties.bold = true;
          final body = document.paragraphs.single.text;
          final before = _snapshot(document);
          final session = _session(document, paragraph, 4);
          expect(_call(session, 'Document.canInsertField', ['Http']), isTrue);
          expect(_call(session, 'Document.cursorInField', ['Http']), isNull);
          final inserted = _insert(session, requestedType);
          expect(inserted['noteIndex'], 1);
          _set(
            session,
            inserted,
            'new',
            'New source',
            html: '<i>New</i> source',
          );
          expect(_snapshot(document), before);
          _apply(session);

          expect(paragraph.text, 'See New source for the discussion.');
          expect(document.paragraphs.single.text, body);
          expect(document.footnotes.length + document.endnotes.length, 1);
          expect(
            (endnote ? document.endnotes : document.footnotes).single,
            same(note),
          );
          expect(session.caretAfter, (paragraph: paragraph, offset: 14));
          expect(
            paragraph.inlines.whereType<WmlRun>().first.properties.bold,
            isTrue,
          );
          expect(
            paragraph.inlines
                .whereType<WmlRun>()
                .singleWhere((run) => run.text == 'New')
                .properties
                .italic,
            isTrue,
          );
          expect(
            note.allParagraphs
                .expand((p) => p.inlines.whereType<WmlRun>())
                .every((run) => run.noteRefId == null),
            isTrue,
          );

          final reopened = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          expect(reopened.footnotes.length + reopened.endnotes.length, 1);
          final reopenedNote =
              (endnote ? reopened.endnotes : reopened.footnotes).single;
          expect(reopenedNote.text, 'See New source for the discussion.');
          final reopenedField = WordZotero.fields(reopened).single;
          expect(reopenedField.citation!.citationId, 'new');
          expect(reopenedField.citation!.properties['noteIndex'], 1);
          expect(
            _fields(
              _session(reopened, reopenedNote.paragraphs.single, 0),
            ).single['noteIndex'],
            1,
          );
        },
      );
    }

    for (final position in ['before', 'between', 'after', 'later paragraph']) {
      test(
        '$label insertion $position keeps processor order and note numbers',
        () {
          final firstBody = _paragraph('First ');
          final lastBody = _paragraph('Last ');
          final document = WmlDocument(
            sections: [
              WmlSection(blocks: [firstBody, lastBody]),
            ],
          );
          WordZotero.insertCitation(
            firstBody,
            _citation('body-first', '(Body)'),
          );
          WordNotes.insert(
            document,
            firstBody,
            endnote: endnote,
            text: 'Earlier ordinary note',
          );
          // The other note kind has its own numbering sequence.
          WordNotes.insert(
            document,
            firstBody,
            endnote: !endnote,
            text: 'Other kind',
          );
          final note = WordNotes.insert(
            document,
            firstBody,
            endnote: endnote,
            text: 'Lead ',
          );
          final first = note.paragraphs.single;
          WordZotero.insertCitation(first, _citation('left', '(Left)'));
          first.inlines.add(WmlRun(text: ' gap '));
          final between = first.text.length;
          WordZotero.insertCitation(first, _citation('right', '(Right)'));
          first.inlines.add(WmlRun(text: ' end'));
          final second = _paragraph('Next ');
          WordZotero.insertCitation(second, _citation('last', '(Last)'));
          note.blocks.add(second);
          final later = WordNotes.insert(document, firstBody, endnote: endnote);
          WordZotero.insertCitation(
            later.paragraphs.single,
            _citation('later-note', '(Later)'),
          );
          WordZotero.insertCitation(
            lastBody,
            _citation('body-last', '(Body end)'),
          );
          final paragraph = position == 'later paragraph' ? second : first;
          final offset = switch (position) {
            'before' => 0,
            'between' => between,
            _ => paragraph.text.length,
          };
          var expectedText =
              '${paragraph.text.substring(0, offset)}(New)${paragraph.text.substring(offset)}';
          expectedText = expectedText.replaceAll(
            '(Left)',
            'A longer left citation',
          );
          final session = _session(document, paragraph, offset);
          final inserted = _insert(session, 0);
          _set(session, inserted, 'new', '(New)');
          final fields = _fields(session);
          _set(
            session,
            fields.singleWhere((f) => _citationId(f) == 'left'),
            'left',
            'A longer left citation',
          );
          final noteOrder = switch (position) {
            'before' => ['new', 'left', 'right', 'last'],
            'between' => ['left', 'new', 'right', 'last'],
            'after' => ['left', 'right', 'new', 'last'],
            _ => ['left', 'right', 'last', 'new'],
          };
          expect(_fields(session).map(_citationId), [
            'body-first',
            ...noteOrder,
            'later-note',
            'body-last',
          ]);
          expect(_fields(session).map((f) => f['noteIndex']), [
            0,
            2,
            2,
            2,
            2,
            3,
            0,
          ]);
          _apply(session);

          expect(paragraph.text, expectedText);
          expect(
            (endnote ? document.endnotes : document.footnotes),
            hasLength(3),
          );
          final after = _fields(_session(document, firstBody, 0));
          expect(after.map(_citationId), [
            'body-first',
            ...noteOrder,
            'later-note',
            'body-last',
          ]);
          expect(after.map((f) => f['noteIndex']), [0, 2, 2, 2, 2, 3, 0]);
          final added = WordZotero.fields(
            document,
          ).singleWhere((f) => f.citation?.citationId == 'new');
          expect(session.caretAfter, (paragraph: paragraph, offset: added.end));
        },
      );
    }

    for (final preferredType in [0, type]) {
      for (final accepted in [false, true]) {
        test(
          '$label catalog seed with preference $preferredType ${accepted ? 'applies' : 'cancels'} atomically',
          () {
            final document = WmlDocument.empty(text: 'Body ');
            document.zoteroDocumentData = _preferences(preferredType);
            final note = WordNotes.insert(
              document,
              document.paragraphs.single,
              endnote: endnote,
              text: 'See  here.',
            );
            final before = _snapshot(document);
            final session = _session(
              document,
              note.paragraphs.single,
              4,
              seed: _citation('seed', '(Seed)'),
            );
            final seed = _fields(session).single;
            expect(seed['noteIndex'], 1);
            if (accepted) _set(session, seed, 'seed', '(Accepted)');
            expect(_snapshot(document), before);
            _apply(session);
            expect(session.hasAcceptedSeedCitation, accepted);
            if (accepted) {
              expect(note.text, 'See (Accepted) here.');
              expect(document.footnotes.length + document.endnotes.length, 1);
            } else {
              expect(_snapshot(document), before);
              expect(session.hasChanges, isFalse);
            }
          },
        );
      }
    }

    test(
      '$label preferences can be chosen before seeding in the same transaction',
      () {
        final document = WmlDocument.empty(text: 'Body ');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'See ',
        );
        final before = _snapshot(document);
        final session = _session(document, note.paragraphs.single, 4);
        _call(session, 'Document.setDocumentData', [_preferences(type)]);
        _call(session, 'Document.complete');
        session.continueWithCitation(_citation('seed', '(Seed)'));
        final seed = _fields(session).single;
        _set(session, seed, 'seed', '(Accepted)');
        expect(_snapshot(document), before);
        _apply(session);
        expect(note.text, 'See (Accepted)');
        expect(
          WordZoteroDocumentData.citationNoteType(
            WordZoteroDocumentData.read(document),
          ),
          type,
        );
        expect(document.footnotes.length + document.endnotes.length, 1);
      },
    );

    test(
      '$label insertion refuses an incompatible note kind and bibliography',
      () {
        final document = WmlDocument.empty(text: 'Body ');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'Keep',
        );
        final before = _snapshot(document);
        final session = _session(document, note.paragraphs.single, 0);
        expect(() => _insert(session, endnote ? 1 : 2), throwsUnsupportedError);
        expect(_fields(session), isEmpty);
        final field = _insert(session, 0);
        expect(
          () => _call(session, 'Field.setCode', [
            field['id'],
            'BIBL {} CSL_BIBLIOGRAPHY',
          ]),
          throwsUnsupportedError,
        );
        expect(
          () => _call(session, 'Document.convert', [
            [field['id']],
            'Http',
            [0],
          ]),
          throwsUnsupportedError,
        );
        _call(session, 'Field.delete', [field['id']]);
        _apply(session);
        expect(_snapshot(document), before);
      },
    );

    test(
      '$label seed refuses a later incompatible preference without applying',
      () {
        final document = WmlDocument.empty(text: 'Body ');
        document.zoteroDocumentData = _preferences(type);
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'Keep',
        );
        final before = _snapshot(document);
        final session = _session(
          document,
          note.paragraphs.single,
          0,
          seed: _citation('seed', '(Seed)'),
        );
        _set(session, _fields(session).single, 'seed', '(Accepted)');
        _call(session, 'Document.setDocumentData', [
          _preferences(endnote ? 1 : 2),
        ]);
        expect(() => _call(session, 'Document.complete'), throwsStateError);
        expect(session.apply, throwsStateError);
        expect(_snapshot(document), before);
      },
    );

    test(
      '$label deletion of an old sole citation keeps the newly inserted citation and note',
      () {
        final document = WmlDocument.empty(text: 'Body ');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
        );
        WordZotero.insertCitation(
          note.paragraphs.single,
          _citation('old', '(Old)'),
        );
        final session = _session(
          document,
          note.paragraphs.single,
          note.text.length,
        );
        final old = _fields(session).single;
        final inserted = _insert(session, 0);
        _set(session, inserted, 'new', '(New)');
        _call(session, 'Field.delete', [old['id']]);
        expect(_fields(session).single['noteIndex'], 1);
        _apply(session);
        expect(
          (endnote ? document.endnotes : document.footnotes).single,
          same(note),
        );
        expect(note.text, '(New)');
        expect(WordZotero.fields(document).single.citation!.citationId, 'new');
      },
    );
  }

  test(
    'a staged new citation prevents converting the existing sole-citation note',
    () {
      final document = WmlDocument.empty(text: 'Body ');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: false,
      );
      WordZotero.insertCitation(
        note.paragraphs.single,
        _citation('old', '(Old)'),
      );
      final before = _snapshot(document);
      final session = _session(
        document,
        note.paragraphs.single,
        note.text.length,
      );
      final old = _fields(session).single;
      final inserted = _insert(session, 0);
      _set(session, inserted, 'new', '(New)');
      expect(
        () => _call(session, 'Document.convert', [
          [old['id']],
          'Http',
          [0],
        ]),
        throwsUnsupportedError,
      );
      expect(_fields(session).map((f) => f['noteIndex']), [1, 1]);
      expect(_snapshot(document), before);
    },
  );

  test(
    'an already staged note conversion prevents inserting into that note',
    () {
      final document = WmlDocument.empty(text: 'Body ');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: false,
      );
      WordZotero.insertCitation(
        note.paragraphs.single,
        _citation('old', '(Old)'),
      );
      final before = _snapshot(document);
      final session = _session(
        document,
        note.paragraphs.single,
        note.text.length,
      );
      _call(session, 'Document.convert', [
        [_fields(session).single['id']],
        'Http',
        [0],
      ]);
      expect(() => _insert(session, 0), throwsUnsupportedError);
      expect(_snapshot(document), before);
    },
  );

  test('a note table cell is an anchored insertion location', () {
    final document = WmlDocument.empty(text: 'Body ');
    final note = WordNotes.insert(
      document,
      document.paragraphs.single,
      endnote: false,
      text: 'Explanation',
    );
    final cell = _paragraph('Cell ');
    note.blocks.add(
      WmlTable(
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(blocks: [cell]),
            ],
          ),
        ],
      ),
    );
    final session = _session(document, cell, 5);
    final inserted = _insert(session, 0);
    _set(session, inserted, 'cell', '(Cell citation)');
    _apply(session);
    expect(cell.text, 'Cell (Cell citation)');
    expect(note.blocks.last, isA<WmlTable>());
    expect(document.footnotes, hasLength(1));
    expect(_fields(_session(document, cell, 0)).single['noteIndex'], 1);
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    expect(
      reopened.footnotes.single.blocks.whereType<WmlTable>(),
      hasLength(1),
    );
    expect(WordZotero.fields(reopened).single.citation!.citationId, 'cell');
  });

  test('unanchored and detached note paragraphs do not accept new fields', () {
    final document = WmlDocument.empty(text: 'Body ');
    final note = WmlNote(
      id: 1,
      endnote: false,
      paragraphs: [_paragraph('Unanchored')],
    );
    document.footnotes.add(note);
    for (final paragraph in [note.paragraphs.single, _paragraph('Detached')]) {
      final session = _session(document, paragraph, 0);
      expect(_call(session, 'Document.canInsertField', ['Http']), isFalse);
      expect(() => _insert(session, 0), throwsUnsupportedError);
    }
    expect(WordZotero.fields(document), isEmpty);
  });

  for (final kind in ['locked', 'malformed repair', 'malformed unlink']) {
    test(
      kind == 'locked'
          ? 'locked citation in the destination note prevents native insertion'
          : '$kind in the destination note must finish before insertion publishes',
      () {
        final document = WmlDocument.empty(text: 'Body ');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: false,
          text: 'See ',
        );
        WordZotero.insertCitation(
          note.paragraphs.single,
          _citation('old', '(Old)'),
        );
        final run = WordZotero.fields(document).single.run!;
        if (kind == 'locked') {
          run.fieldLocked = true;
        } else {
          run.fieldInstruction = ' ADDIN ZOTERO_ITEM CSL_CITATION {broken} ';
        }
        final before = _snapshot(document);
        if (kind == 'locked') {
          expect(
            () => _session(document, note.paragraphs.single, 0),
            throwsUnsupportedError,
          );
          expect(_snapshot(document), before);
          return;
        }

        final session = _session(document, note.paragraphs.single, 0);
        final damaged = _fields(session).single;
        expect(damaged['code'], 'ITEM CSL_CITATION {broken}');
        expect(damaged['text'], '(Old)');
        expect(damaged['noteIndex'], 1);
        final inserted = _insert(session, 0);
        _set(session, inserted, 'new', '(New)');
        expect(_snapshot(document), before);
        expect(
          () => _call(session, 'Document.complete'),
          throwsFormatException,
        );
        expect(session.isComplete, isFalse);
        expect(session.apply, throwsStateError);
        expect(_snapshot(document), before);

        if (kind == 'malformed repair') {
          _set(session, damaged, 'repaired', '(Repaired)');
        } else {
          _call(session, 'Field.removeCode', [damaged['id']]);
        }
        expect(_snapshot(document), before);
        _apply(session);
        expect(
          note.paragraphs.single.text,
          kind == 'malformed repair' ? '(New)See (Repaired)' : '(New)See (Old)',
        );
        expect(
          WordZotero.fields(
            document,
          ).map((field) => field.citation!.citationId),
          kind == 'malformed repair' ? ['new', 'repaired'] : ['new'],
        );
      },
    );
  }

  test('a nested note reference is rejected without creating another note', () {
    final document = WmlDocument.empty(text: 'Body ');
    final note = WordNotes.insert(
      document,
      document.paragraphs.single,
      endnote: false,
      text: 'See ',
    );
    note.paragraphs.single.inlines.add(WmlRun(text: '1', noteRefId: note.id));
    final before = _snapshot(document);
    final session = _session(document, note.paragraphs.single, 0);
    expect(() => _insert(session, 0), throwsUnsupportedError);
    expect(_snapshot(document), before);
  });

  for (final change in [
    'remove note',
    'replace note',
    'detach paragraph',
    'reorder paragraphs',
    'change note ID',
    'replace anchor',
  ]) {
    test('$change after staging rejects stale note insertion', () {
      final document = WmlDocument.empty(text: 'Body ');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: false,
        text: 'First',
      );
      final paragraph = note.paragraphs.single;
      note.blocks.add(_paragraph('Second'));
      final session = _session(document, paragraph, 0);
      final inserted = _insert(session, 0);
      _set(session, inserted, 'new', '(New)');
      _call(session, 'Document.complete');
      switch (change) {
        case 'remove note':
          document.footnotes.clear();
        case 'replace note':
          document.footnotes[0] = WmlNote(
            id: note.id,
            endnote: false,
            paragraphs: [_paragraph('First'), _paragraph('Second')],
          );
        case 'detach paragraph':
          note.blocks[0] = _paragraph('First');
        case 'reorder paragraphs':
          note.blocks.setAll(0, note.blocks.reversed.toList());
        case 'change note ID':
          note.id = 9;
        case 'replace anchor':
          final anchor = document.paragraphs.single;
          final ref = anchor.inlines.indexWhere(
            (inline) => inline is WmlRun && inline.noteRefId != null,
          );
          anchor.inlines[ref] = WmlRun(
            text: (anchor.inlines[ref] as WmlRun).text,
          );
      }
      final afterExternalChange = _snapshot(document);
      expect(session.apply, throwsStateError);
      expect(_snapshot(document), afterExternalChange);
      expect(paragraph.text, 'First');
    });
  }
}
