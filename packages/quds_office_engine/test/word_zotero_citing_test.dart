import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _documentId = 'quds-test-document';

ZoteroCitation _citation(String id, [String text = '(Ada)', int note = 0]) =>
    ZoteroCitation(
      citationId: id,
      plainCitation: text,
      noteIndex: note,
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {
            'type': 'book',
            'title': 'Source $id',
            'author': [
              {'family': 'Lovelace', 'given': 'Ada'},
            ],
            'issued': {
              'date-parts': [
                [1843],
              ],
            },
          },
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
          locator: '12',
          label: 'page',
        ),
      ],
    );

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WordZoteroCitingSession _session(
  WmlDocument document, {
  int offset = 0,
  WmlParagraph? paragraph,
  WmlZoteroField? selected,
  ZoteroCitation? seed,
}) => WordZoteroCitingSession(
  document: document,
  documentId: _documentId,
  insertionParagraph: paragraph ?? document.paragraphs.first,
  insertionOffset: offset,
  selectedField: selected,
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

String _code(ZoteroCitation citation) =>
    'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}';

void _set(
  WordZoteroCitingSession session,
  String field,
  ZoteroCitation citation, {
  String? html,
}) {
  _call(session, 'Field.setCode', [field, _code(citation)]);
  _call(session, 'Field.setText', [
    field,
    html ?? citation.plainCitation,
    html != null,
  ]);
}

void _apply(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

String _preferences({
  String style = 'chicago-note-bibliography',
  int note = 1,
}) => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'session-test',
  'style': {
    'styleID': style.startsWith('http')
        ? style
        : 'http://www.zotero.org/styles/$style',
    'locale': 'de-DE',
    'hasBibliography': true,
  },
  'prefs': {'fieldType': 'Http', 'noteType': note},
});

String _xmlPreferences({int? note = 1}) =>
    '<data data-version="3"><session id="session-test"/>'
    '<style id="http://www.zotero.org/styles/chicago-note-bibliography" '
    'locale="de-DE" hasBibliography="1"/>'
    '<prefs><pref name="fieldType" value="Field"/>'
    '${note == null ? '' : '<pref name="noteType" value="$note"/>'}'
    '</prefs></data>';

String _snapshot(WmlDocument document) => jsonEncode({
  'paragraphs': [for (final p in document.paragraphs) p.text],
  'footnotes': [
    for (final n in document.footnotes) {'id': n.id, 'text': n.text},
  ],
  'endnotes': [
    for (final n in document.endnotes) {'id': n.id, 'text': n.text},
  ],
  'fields': [
    for (final f in WordZotero.fields(document))
      {
        'code': f.instruction,
        'text': f.cachedText,
        'start': f.start,
        'end': f.end,
      },
  ],
  'data': WordZoteroDocumentData.read(document),
});

WmlNote _note(
  WmlDocument document,
  WmlParagraph anchor, {
  required String citationId,
  bool endnote = false,
  String surrounding = '',
}) {
  final note = WordNotes.insert(
    document,
    anchor,
    endnote: endnote,
    text: surrounding,
  );
  WordZotero.insertCitation(note.paragraphs.single, _citation(citationId));
  return note;
}

Map<String, dynamic> _scenario(String id) {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/zotero/citing/processor-output.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  expect(fixture['processorVersion'], '1.4.61');
  return (fixture['scenarios'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((v) => v['id'] == id);
}

ZoteroCitation _processorCitation(
  Map<String, dynamic> json,
  Map<String, dynamic> rendered,
) {
  final html = rendered['html'] as String;
  return ZoteroCitation.fromJson({
    ...json,
    'properties': {
      ...json['properties'] as Map<String, dynamic>,
      'plainCitation': ZoteroFormattedText.fromHtml(html).plainText,
      'formattedCitation': html,
    },
  });
}

void main() {
  test('application and field objects expose the current HTTP contract', () {
    final document = WmlDocument.empty(text: 'Before After');
    WordZotero.insertCitation(
      document.paragraphs.single,
      _citation('original'),
      index: 7,
    );
    final original = WordZotero.fields(document).single;
    final session = _session(document, offset: 8);
    final application =
        session.handle('Application.getActiveDocument', []) as Map;
    expect(application, containsPair('documentID', _documentId));
    expect(application, containsPair('outputFormat', 'html'));
    expect(application['supportedNotes'], ['footnotes', 'endnotes']);
    expect(application['supportsCitationMerging'], isTrue);
    expect(_call(session, 'Document.activate'), isNull);
    expect(_call(session, 'Document.canInsertField', ['Http']), isTrue);
    final field = _fields(session).single;
    expect(field.keys.toSet(), {'id', 'code', 'text', 'noteIndex', 'adjacent'});
    expect(field['code'], _code(original.citation!));
    expect(field['code'], isNot(contains('ADDIN ZOTERO_')));
    expect(field['text'], '(Ada)');
    expect(field['noteIndex'], 0);
    expect(field['adjacent'], isFalse);
    expect(_call(session, 'Document.cursorInField', ['Http']), field);
    expect(_call(session, 'Field.select', [field['id']]), isNull);
    expect(session.hasChanges, isFalse);
  });

  test(
    'reading order follows body and note anchors including noncitation notes',
    () {
      final first = _paragraph('First ');
      final middle = _paragraph('Middle ');
      final last = _paragraph('Last ');
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [first, middle, last]),
        ],
      );
      WordZotero.insertCitation(first, _citation('body-a'));
      WordNotes.insert(
        document,
        first,
        endnote: false,
        text: 'Uncited explanatory note',
      );
      _note(document, first, citationId: 'foot-a');
      WordNotes.insert(document, first, endnote: true, text: 'Uncited endnote');
      _note(document, first, citationId: 'end-a', endnote: true);
      WordZotero.insertCitation(middle, _citation('body-b'));
      _note(document, last, citationId: 'foot-b');
      const footIds = {1: 99, 2: 7, 3: 42};
      const endIds = {1: 51, 2: 3};
      for (final note in document.footnotes) {
        note.id = footIds[note.id]!;
      }
      for (final note in document.endnotes) {
        note.id = endIds[note.id]!;
      }
      for (final run in document.paragraphs.expand(
        (p) => p.inlines.whereType<WmlRun>(),
      )) {
        if (run.noteRefId != null) {
          run.noteRefId = (run.noteRefEndnote
              ? endIds
              : footIds)[run.noteRefId]!;
        }
      }
      // Bucket order and storage IDs do not determine document reading order.
      document.footnotes.setAll(0, document.footnotes.reversed.toList());
      document.endnotes.setAll(0, document.endnotes.reversed.toList());
      final session = _session(document);
      final fields = _fields(session);
      expect(
        fields.map(
          (f) =>
              (jsonDecode(
                    (f['code'] as String).substring(
                      'ITEM CSL_CITATION '.length,
                    ),
                  )
                  as Map)['citationID'],
        ),
        ['body-a', 'foot-a', 'end-a', 'body-b', 'foot-b'],
      );
      expect(fields.map((f) => f['noteIndex']), [0, 2, 2, 0, 3]);
    },
  );

  test(
    'body table fields retain reading order with surrounding paragraphs',
    () {
      final before = _paragraph('');
      final cell = _paragraph('');
      final after = _paragraph('');
      for (final pair in [
        (before, 'before'),
        (cell, 'cell'),
        (after, 'after'),
      ]) {
        WordZotero.insertCitation(pair.$1, _citation(pair.$2, pair.$2));
      }
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              before,
              WmlTable(
                rows: [
                  WmlTableRow(
                    cells: [
                      WmlTableCell(blocks: [cell]),
                    ],
                  ),
                ],
              ),
              after,
            ],
          ),
        ],
      );
      expect(_fields(_session(document)).map((f) => f['text']), [
        'before',
        'cell',
        'after',
      ]);
    },
  );

  test(
    'codes results and preferences stay staged until complete and apply',
    () {
      final document = WmlDocument.empty(text: 'Left Right');
      WordZotero.insertCitation(
        document.paragraphs.single,
        _citation('existing'),
        index: 5,
      );
      final before = _snapshot(document);
      final session = _session(document);
      final id = _fields(session).single['id'] as String;
      _set(session, id, _citation('existing', 'Ebd., 34.'));
      _call(session, 'Document.setDocumentData', [_preferences()]);
      expect(
        _call(session, 'Document.getDocumentData'),
        contains('"fieldType":"Http"'),
      );
      expect(session.hasChanges, isTrue);
      expect(session.changedFieldCount, 1);
      expect(session.previewTexts, ['Ebd., 34.']);
      expect(_snapshot(document), before);
      expect(session.apply, throwsStateError);
      expect(_snapshot(document), before);
      _call(session, 'Document.complete');
      expect(_snapshot(document), before);
      session.apply();
      expect(document.paragraphs.single.text, 'Left Ebd., 34.Right');
      expect(
        WordZotero.fields(document).single.instruction,
        startsWith(' ADDIN ZOTERO_ITEM CSL_CITATION '),
      );
      expect(
        WordZoteroDocumentData.read(document),
        contains('"fieldType":"Field"'),
      );
      expect(session.apply, throwsStateError);
      expect(
        () => _call(session, 'Document.getFields', ['Http']),
        throwsStateError,
      );
    },
  );

  test(
    'refresh replaces changing field lengths from the end of the paragraph',
    () {
      final document = WmlDocument.empty(text: 'Start ');
      final p = document.paragraphs.single;
      for (var i = 0; i < 3; i++) {
        WordZotero.insertCitation(p, _citation('c$i', '[old-$i]'));
        p.inlines.add(WmlRun(text: ' between '));
      }
      final session = _session(document);
      final ids = _fields(session).map((f) => f['id'] as String).toList();
      for (var i = 0; i < ids.length; i++) {
        _set(session, ids[i], _citation('c$i', i == 1 ? '[12345]' : '[$i]'));
      }
      _apply(session);
      expect(p.text, 'Start [0] between [12345] between [2] between ');
      expect(WordZotero.fields(document).map((f) => f.citation!.citationId), [
        'c0',
        'c1',
        'c2',
      ]);
    },
  );

  for (final mode in ['code and text', 'text-only', 'code-only']) {
    test('native $mode refresh retires basic formatting', () {
      var document = WmlDocument.empty(text: 'Before ');
      final base = _citation('basic', '(Lovelace, 1843)');
      final basic = ZoteroCitation.fromJson({
        ...base.toJson(),
        'properties': {
          ...base.properties,
          'qudsFormat': 'basic-author-year',
          'customProperty': 'preserved',
        },
      });
      WordZotero.insertCitation(document.paragraphs.single, basic);
      final session = _session(document);
      final id = _fields(session).single['id'] as String;
      final resultText = mode == 'code-only'
          ? basic.plainCitation
          : 'Ebd., 34.';
      final processor = basic.withItems(basic.items, plainCitation: resultText);
      if (mode != 'text-only') {
        _call(session, 'Field.setCode', [id, _code(processor)]);
      }
      if (mode != 'code-only') {
        _call(session, 'Field.setText', [id, resultText, false]);
      }
      expect(
        WordZotero.fields(document).single.citation!.properties['qudsFormat'],
        'basic-author-year',
      );
      _apply(session);
      for (var cycle = 0; cycle < 2; cycle++) {
        final field = WordZotero.fields(document).single;
        expect(field.cachedText, resultText);
        expect(field.citation!.properties['qudsFormat'], 'zotero-desktop');
        expect(field.citation!.properties['customProperty'], 'preserved');
        expect(field.citation!.citationId, 'basic');
        expect(
          field.citation!.items.single.toJson(),
          basic.items.single.toJson(),
        );
        expect(
          WordZotero.fields(document).where(
            (field) =>
                field.citation!.properties['qudsFormat'] == 'basic-author-year',
          ),
          isEmpty,
        );
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    });
  }

  for (final noteType in [0, 1, 2]) {
    test('new citation inserts as note type $noteType and survives DOCX', () {
      var document = WmlDocument.empty(text: 'Before After');
      final original = _snapshot(document);
      final session = _session(document, offset: 7);
      final added =
          _call(session, 'Document.insertField', ['Http', noteType]) as Map;
      expect(added['code'], 'TEMP');
      expect(added['noteIndex'], noteType == 0 ? 0 : 1);
      _set(
        session,
        added['id'] as String,
        _citation('new', 'Ebd., 34.', noteType == 0 ? 0 : 1),
      );
      expect(_snapshot(document), original);
      _apply(session);
      expect(document.footnotes.length, noteType == 1 ? 1 : 0);
      expect(document.endnotes.length, noteType == 2 ? 1 : 0);
      if (noteType != 0) {
        final ref = document.paragraphs.first.inlines
            .whereType<WmlRun>()
            .singleWhere((r) => r.noteRefId != null);
        expect(ref.noteRefEndnote, noteType == 2);
        expect(ref.properties.vertAlign, WmlVertAlign.superscript);
        expect(document.paragraphs.first.text, 'Before 1After');
      } else {
        expect(document.paragraphs.first.text, 'Before Ebd., 34.After');
      }
      expect(session.caretAfter!.paragraph, same(document.paragraphs.first));
      expect(
        session.caretAfter!.offset,
        document.paragraphs.first.text.indexOf('After'),
      );
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final fields = WordZotero.fields(document);
      expect(fields.single.cachedText, 'Ebd., 34.');
      expect(fields.single.citation!.citationId, 'new');
      expect(
        _fields(_session(document)).single['noteIndex'],
        noteType == 0 ? 0 : 1,
      );
    });
  }

  for (final noteType in [0, 1, 2]) {
    test(
      'caret follows inserted note type $noteType after an earlier citation expands',
      () {
        final document = WmlDocument.empty(text: 'Lead ');
        final paragraph = document.paragraphs.single;
        WordZotero.insertCitation(paragraph, _citation('earlier', '[1]'));
        paragraph.inlines.add(WmlRun(text: ' gap end'));
        final session = _session(
          document,
          offset: paragraph.text.indexOf('end'),
        );
        final oldId = _fields(session).single['id'] as String;
        final newField =
            _call(session, 'Document.insertField', ['Http', noteType]) as Map;
        _set(
          session,
          oldId,
          _citation('earlier', '[expanded earlier citation]'),
        );
        _set(session, newField['id'] as String, _citation('new', 'NEW'));
        expect(session.caretAfter, isNull);
        _apply(session);
        expect(session.caretAfter!.paragraph, same(paragraph));
        expect(session.caretAfter!.offset, paragraph.text.indexOf('end'));
        expect(
          paragraph.text,
          startsWith('Lead [expanded earlier citation] gap '),
        );
      },
    );
  }

  test('a newly inserted note precedes existing notes in processor order', () {
    final document = WmlDocument.empty(text: 'Before After ');
    final paragraph = document.paragraphs.single;
    _note(document, paragraph, citationId: 'existing');
    final session = _session(document, offset: 7);
    final inserted = _call(session, 'Document.insertField', ['Http', 1]) as Map;
    expect(inserted['noteIndex'], 1);
    _set(session, inserted['id'] as String, _citation('new', 'New note'));
    final fields = _fields(session);
    expect(fields.map((f) => f['noteIndex']), [1, 2]);
    expect(fields.first['id'], inserted['id']);
    _apply(session);
    expect(_fields(_session(document)).map((f) => f['noteIndex']), [1, 2]);
    expect(_fields(_session(document)).map((f) => f['text']), [
      'New note',
      '(Ada)',
    ]);
  });

  test(
    'a note inserted directly before an existing marker uses its new order',
    () {
      final document = WmlDocument.empty(text: 'Before ');
      final paragraph = document.paragraphs.single;
      final insertionOffset = paragraph.text.length;
      _note(document, paragraph, citationId: 'existing');
      final session = _session(document, offset: insertionOffset);
      final inserted =
          _call(session, 'Document.insertField', ['Http', 1]) as Map;
      expect(inserted['noteIndex'], 1);
      _set(session, inserted['id'] as String, _citation('new', 'New note'));
      final fields = _fields(session);
      expect(fields.first['id'], inserted['id']);
      expect(fields.map((field) => field['noteIndex']), [1, 2]);
      _apply(session);
      expect(_fields(_session(document)).map((field) => field['noteIndex']), [
        1,
        2,
      ]);
      expect(_fields(_session(document)).map((field) => field['text']), [
        'New note',
        '(Ada)',
      ]);
    },
  );

  for (final from in [0, 1, 2]) {
    for (final to in [0, 1, 2].where((v) => v != from)) {
      test(
        'a sole citation converts from note type $from to $to without losing text',
        () {
          final document = WmlDocument.empty(text: 'Before ');
          final p = document.paragraphs.single;
          if (from == 0) {
            WordZotero.insertCitation(p, _citation('moving'));
          } else {
            _note(document, p, citationId: 'moving', endnote: from == 2);
          }
          p.inlines.add(WmlRun(text: ' After'));
          final before = _snapshot(document);
          final session = _session(document);
          final id = _fields(session).single['id'] as String;
          _call(session, 'Document.convert', [
            [id],
            'Http',
            [to],
          ]);
          expect(_snapshot(document), before);
          expect(_fields(session).single['noteIndex'], to == 0 ? 0 : 1);
          _apply(session);
          expect(WordZotero.fields(document).single.cachedText, '(Ada)');
          expect(document.footnotes.length, to == 1 ? 1 : 0);
          expect(document.endnotes.length, to == 2 ? 1 : 0);
          expect(p.text, to == 0 ? 'Before (Ada) After' : 'Before 1 After');
        },
      );
    }
  }

  test(
    'conversion refuses extra note prose without staging earlier conversions',
    () {
      final document = WmlDocument.empty(text: 'Body ');
      WordZotero.insertCitation(
        document.paragraphs.single,
        _citation('inline'),
      );
      _note(
        document,
        document.paragraphs.single,
        citationId: 'complex',
        surrounding: 'Keep this explanation. ',
      );
      final before = _snapshot(document);
      final session = _session(document);
      final fields = _fields(session);
      expect(
        () => _call(session, 'Document.convert', [
          fields.map((f) => f['id']).toList(),
          'Http',
          [2, 2],
        ]),
        throwsUnsupportedError,
      );
      expect(_fields(session).map((f) => f['noteIndex']), [0, 1]);
      expect(session.hasChanges, isFalse);
      expect(_snapshot(document), before);
    },
  );

  test(
    'two citations in one note share the note index and refuse note conversion',
    () {
      final document = WmlDocument.empty(text: 'Body ');
      final note = _note(
        document,
        document.paragraphs.single,
        citationId: 'one',
      );
      WordZotero.insertCitation(note.paragraphs.single, _citation('two'));
      final session = _session(document);
      final fields = _fields(session);
      expect(fields.map((f) => f['noteIndex']), [1, 1]);
      expect(
        () => _call(session, 'Document.convert', [
          [fields.first['id']],
          'Http',
          [0],
        ]),
        throwsUnsupportedError,
      );
      expect(session.hasChanges, isFalse);
    },
  );

  for (final extraField in [true, false]) {
    final label = extraField
        ? 'an unrelated empty PAGE field'
        : 'two note markers';
    WmlNote makeNote(WmlDocument document) {
      final note = _note(
        document,
        document.paragraphs.single,
        citationId: 'citation',
      );
      note.paragraphs.single.inlines.addAll(
        extraField
            ? <WmlInline>[
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
                WmlFieldBoundary(
                  kind: WmlFieldBoundaryKind.instruction,
                  text: ' PAGE ',
                ),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
              ]
            : <WmlInline>[
                WmlNoteMarker(endnote: false, properties: WmlRunProps()),
                WmlNoteMarker(endnote: false, properties: WmlRunProps()),
              ],
      );
      return note;
    }

    test('conversion refuses a citation note with $label', () {
      final document = WmlDocument.empty(text: 'Body ');
      final note = makeNote(document);
      final originalInlines = List<WmlInline>.of(
        note.paragraphs.single.inlines,
      );
      final session = _session(document);
      final id = _fields(session).single['id'];
      expect(
        () => _call(session, 'Document.convert', [
          [id],
          'Http',
          [0],
        ]),
        throwsUnsupportedError,
      );
      expect(session.hasChanges, isFalse);
      expect(note.paragraphs.single.inlines, originalInlines);
    });

    test('deleting a citation keeps its note containing $label', () {
      final document = WmlDocument.empty(text: 'Body ');
      final note = makeNote(document);
      final extra = note.paragraphs.single.inlines
          .where((v) => v is WmlFieldBoundary || v is WmlNoteMarker)
          .toList();
      final session = _session(document);
      _call(session, 'Field.delete', [_fields(session).single['id']]);
      _apply(session);
      expect(document.footnotes, [note]);
      expect(WordZotero.fields(document), isEmpty);
      expect(note.paragraphs.single.inlines, containsAllInOrder(extra));
      expect(
        document.paragraphs.first.inlines.whereType<WmlRun>().where(
          (r) => r.noteRefId != null,
        ),
        hasLength(1),
      );
      if (extraField) {
        final saved = WordSerializer().write(document);
        expect(
          saved.getPart('/word/footnotes.xml')!.readText(),
          contains(' PAGE '),
        );
      }
    });
  }

  test(
    'deleting an explanatory-note citation keeps the note and surrounding prose',
    () {
      final document = WmlDocument.empty(text: 'Body ');
      final note = _note(
        document,
        document.paragraphs.single,
        citationId: 'remove',
        surrounding: 'Keep explanation. ',
      );
      final session = _session(document);
      _call(session, 'Field.delete', [_fields(session).single['id']]);
      _apply(session);
      expect(WordZotero.fields(document), isEmpty);
      expect(document.footnotes, [note]);
      expect(note.text, 'Keep explanation.');
      expect(document.paragraphs.first.text, 'Body 1');
    },
  );

  test(
    'deleting a sole-citation note removes its body reference and updates later note indices',
    () {
      final document = WmlDocument.empty(text: 'Body ');
      final p = document.paragraphs.single;
      _note(document, p, citationId: 'first');
      _note(document, p, citationId: 'second');
      final session = _session(document);
      final fields = _fields(session);
      _call(session, 'Field.delete', [fields.first['id']]);
      expect(_fields(session).single['noteIndex'], 1);
      _apply(session);
      expect(document.footnotes, hasLength(1));
      expect(WordZotero.fields(document).single.citation!.citationId, 'second');
      expect(
        p.inlines.whereType<WmlRun>().where((r) => r.noteRefId != null),
        hasLength(1),
      );
    },
  );

  test(
    'unlink retains processor-updated visible text and removes only native code',
    () {
      final document = WmlDocument.empty(text: 'Left Right');
      WordZotero.insertCitation(
        document.paragraphs.single,
        _citation('remove'),
        index: 5,
      );
      final session = _session(document);
      final id = _fields(session).single['id'] as String;
      _set(session, id, _citation('remove', 'Updated citation'));
      _call(session, 'Field.removeCode', [id]);
      expect(_fields(session), isEmpty);
      _apply(session);
      expect(WordZotero.fields(document), isEmpty);
      expect(document.paragraphs.single.text, 'Left Updated citationRight');
    },
  );

  test(
    'cancelled TEMP insertion and untouched seeded citation leave no field',
    () {
      for (final seeded in [false, true]) {
        final document = WmlDocument.empty(text: 'Untouched');
        if (seeded) document.zoteroDocumentData = _preferences(note: 0);
        final before = _snapshot(document);
        final session = _session(
          document,
          offset: 3,
          seed: seeded ? _citation('seed') : null,
        );
        if (!seeded) {
          final added =
              _call(session, 'Document.insertField', ['Http', 1]) as Map;
          _call(session, 'Field.delete', [added['id']]);
        }
        _call(session, 'Document.complete');
        expect(session.hasChanges, isFalse);
        session.apply();
        expect(_snapshot(document), before);
      }
    },
  );

  test(
    'seeded catalog selection is visible to Zotero and inserts only after it updates',
    () {
      final document = WmlDocument.empty(text: 'Before After');
      document.zoteroDocumentData = _preferences(note: 0);
      final session = _session(
        document,
        offset: 7,
        seed: _citation('selected', '(Selected)'),
      );
      final seed = _call(session, 'Document.cursorInField', ['Http']) as Map;
      expect(seed['text'], '(Selected)');
      expect(_fields(session), hasLength(1));
      _set(
        session,
        seed['id'] as String,
        _citation('selected', '(Lovelace, 1843)'),
      );
      _apply(session);
      expect(document.paragraphs.single.text, 'Before (Lovelace, 1843)After');
      expect(
        WordZotero.fields(document).single.citation!.citationId,
        'selected',
      );
    },
  );

  for (final xml in [false, true]) {
    for (final noteType in [0, 1, 2]) {
      test(
        'catalog seed respects ${xml ? 'XML' : 'JSON'} note type $noteType',
        () {
          var document = WmlDocument.empty(text: 'Before After');
          document.zoteroDocumentData = xml
              ? _xmlPreferences(note: noteType)
              : _preferences(note: noteType);
          final before = _snapshot(document);
          final session = _session(
            document,
            offset: 7,
            seed: _citation('selected', '(Selected)'),
          );
          final field = _fields(session).single;
          expect(field['noteIndex'], noteType == 0 ? 0 : 1);
          expect(_snapshot(document), before);
          _set(
            session,
            field['id'] as String,
            _citation('selected', 'Native result', noteType == 0 ? 0 : 1),
          );
          _apply(session);
          expect(document.footnotes.length, noteType == 1 ? 1 : 0);
          expect(document.endnotes.length, noteType == 2 ? 1 : 0);
          expect(
            document.paragraphs.first.text,
            noteType == 0 ? 'Before Native resultAfter' : 'Before 1After',
          );
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          expect(
            _fields(_session(document)).single['noteIndex'],
            noteType == 0 ? 0 : 1,
          );
          expect(
            WordZotero.fields(document).single.cachedText,
            'Native result',
          );
          expect(
            WordZoteroDocumentData.citationNoteType(
              WordZoteroDocumentData.read(document),
            ),
            noteType,
          );
        },
      );
    }
  }

  test('native XML with omitted falsey note type seeds an inline citation', () {
    final document = WmlDocument.empty(text: 'Before After');
    document.zoteroDocumentData = _xmlPreferences(note: null);
    final session = _session(document, offset: 7, seed: _citation('seed'));
    final field = _fields(session).single;
    expect(field['noteIndex'], 0);
    _set(session, field['id'] as String, _citation('seed', 'Inline'));
    _apply(session);
    expect(document.paragraphs.single.text, 'Before InlineAfter');
    expect(document.footnotes, isEmpty);
    expect(document.endnotes, isEmpty);
  });

  test(
    'catalog seeds reject missing or invalid native style data without mutation',
    () {
      final valid = jsonDecode(_preferences()) as Map<String, dynamic>;
      final cases = <String, String>{
        'no preferences': '',
        'malformed JSON': '{broken',
        'missing JSON prefs': '{}',
        'missing JSON style': jsonEncode({'prefs': valid['prefs']}),
        'empty JSON style ID': jsonEncode({
          ...valid,
          'style': {'styleID': ' '},
        }),
        'nonstring JSON style ID': jsonEncode({
          ...valid,
          'style': {'styleID': 42},
        }),
        'missing JSON note type': jsonEncode({
          ...valid,
          'prefs': {'fieldType': 'Field'},
        }),
        for (final value in [null, '1', -1, 3, 1.5, true])
          'invalid JSON note type $value': jsonEncode({
            ...valid,
            'prefs': {'fieldType': 'Field', 'noteType': value},
          }),
        'missing XML style':
            '<data><prefs><pref name="fieldType" value="Field"/></prefs></data>',
        'empty XML style ID': _xmlPreferences().replaceFirst(
          'http://www.zotero.org/styles/chicago-note-bibliography',
          '',
        ),
        'duplicate XML styles': _xmlPreferences().replaceFirst(
          '<prefs>',
          '<style id="http://www.zotero.org/styles/apa"/><prefs>',
        ),
        'duplicate XML note type': _xmlPreferences().replaceFirst(
          '</prefs>',
          '<pref name="noteType" value="2"/></prefs>',
        ),
        for (final value in ['-1', '3', '1.0', 'footnote', ''])
          'invalid XML note type $value': _xmlPreferences().replaceFirst(
            'name="noteType" value="1"',
            'name="noteType" value="$value"',
          ),
      };
      for (final entry in cases.entries) {
        final document = WmlDocument.empty(text: 'Untouched');
        document.zoteroDocumentData = entry.value;
        expect(
          () => _session(document, seed: _citation('seed')),
          throwsFormatException,
          reason: entry.key,
        );
        expect(document.paragraphs.single.text, 'Untouched', reason: entry.key);
        expect(document.footnotes, isEmpty, reason: entry.key);
        expect(document.endnotes, isEmpty, reason: entry.key);
        expect(WordZotero.fields(document), isEmpty, reason: entry.key);
        expect(document.zoteroDocumentData, entry.value, reason: entry.key);
      }
    },
  );

  for (final from in [0, 1, 2]) {
    for (final to in [0, 1, 2].where((type) => type != from)) {
      test(
        'seed placement $from refuses silently changed final preference $to',
        () {
          final document = WmlDocument.empty(text: 'Untouched');
          document.zoteroDocumentData = _preferences(note: from);
          final before = _snapshot(document);
          final session = _session(document, seed: _citation('seed'));
          final field = _fields(session).single;
          _set(
            session,
            field['id'] as String,
            _citation('seed', 'Native result'),
          );
          _call(session, 'Document.setDocumentData', [_preferences(note: to)]);
          expect(() => _call(session, 'Document.complete'), throwsStateError);
          expect(session.isComplete, isFalse);
          expect(session.apply, throwsStateError);
          expect(_snapshot(document), before);
        },
      );
    }
  }

  test(
    'Zotero can explicitly convert a seed before returning matching preferences',
    () {
      final document = WmlDocument.empty(text: 'Before After');
      document.zoteroDocumentData = _preferences(note: 0);
      final session = _session(document, offset: 7, seed: _citation('seed'));
      final field = _fields(session).single;
      _call(session, 'Document.convert', [
        [field['id']],
        'Http',
        [1],
      ]);
      _set(session, field['id'] as String, _citation('seed', 'In note', 1));
      _call(session, 'Document.setDocumentData', [_preferences(note: 1)]);
      _apply(session);
      expect(document.paragraphs.single.text, 'Before 1After');
      expect(document.footnotes.single.text, 'In note');
      expect(_fields(_session(document)).single['noteIndex'], 1);
    },
  );

  test(
    'unfinished TEMP result refuses completion and leaves the original document intact',
    () {
      final document = WmlDocument.empty(text: 'Untouched');
      final before = _snapshot(document);
      final session = _session(document);
      _call(session, 'Document.insertField', ['Http', 0]);
      expect(() => _call(session, 'Document.complete'), throwsFormatException);
      expect(session.isComplete, isFalse);
      expect(_snapshot(document), before);
    },
  );

  test(
    'citation and bibliography wrappers preserve metadata and rich results',
    () {
      final document = WmlDocument.empty(text: 'Paragraph');
      final bibliography = WordZotero.bibliography(
        text: 'Old bibliography',
        metadata: {
          'uncited': <dynamic>[],
          'omitted': <dynamic>[],
          'custom': <dynamic>[],
          'future': 'retain',
        },
      );
      document.sections.single.blocks.add(bibliography);
      final session = _session(document);
      final field = _fields(session).single;
      expect(field['code'], startsWith('BIBL '));
      expect(field['code'], endsWith(' CSL_BIBLIOGRAPHY'));
      _call(session, 'Field.setCode', [field['id'], field['code']]);
      _call(session, 'Field.setText', [
        field['id'],
        '<div class="csl-entry">Müller. <i>Forschung</i>.</div>',
        true,
      ]);
      _call(session, 'Document.setBibliographyStyle', [
        -720,
        720,
        240,
        240,
        <int>[720],
        1,
      ]);
      _call(session, 'Document.complete');
      session.prepareReview();
      expect(session.formattingWarnings, isEmpty);
      session.apply();
      final saved = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final result = WordZotero.fields(saved).single;
      expect(result.metadata!['future'], 'retain');
      expect(result.instruction, startsWith(' ADDIN ZOTERO_BIBL '));
      expect(result.cachedText, 'Müller. Forschung.');
      expect(result.paragraph.properties.indent.hanging, 36);
      expect(result.paragraph.properties.indent.left, 36);
      expect(result.paragraph.properties.lineSpacing, 1);
      expect(result.paragraph.properties.spacingAfter, 12);
      expect(
        result.paragraph.inlines
            .whereType<WmlRun>()
            .where((r) => r.properties.italic)
            .map((r) => r.text)
            .join()
            .trim(),
        'Forschung',
      );
    },
  );

  test(
    'new bibliography inserts a separate linked paragraph after the anchor',
    () {
      final document = WmlDocument.empty(text: 'Keep the body');
      final session = _session(document, offset: 4);
      final added = _call(session, 'Document.insertField', ['Http', 0]) as Map;
      _call(session, 'Field.setCode', [
        added['id'],
        'BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY',
      ]);
      _call(session, 'Field.setText', [
        added['id'],
        '<div class="csl-entry"><b>First</b></div><div class="csl-entry">Second</div>',
        true,
      ]);
      _apply(session);
      expect(document.paragraphs.map((p) => p.text), [
        'Keep the body',
        'First',
        'Second',
      ]);
      expect(session.caretAfter!.paragraph, same(document.paragraphs.last));
      expect(session.caretAfter!.offset, 'Second'.length);
      expect(
        WordZotero.fields(document).single.kind,
        ZoteroFieldKind.bibliography,
      );
    },
  );

  test(
    'uniform superscript survives native result replacement and DOCX reopening',
    () {
      var document = WmlDocument.empty(text: 'Text ');
      WordZotero.insertCitation(
        document.paragraphs.single,
        _citation('numeric', '[old]'),
      );
      final session = _session(document);
      final id = _fields(session).single['id'] as String;
      _set(session, id, _citation('numeric', '3'), html: '<sup>3</sup>');
      _call(session, 'Document.complete');
      session.prepareReview();
      expect(session.formattingWarnings, isEmpty);
      session.apply();
      for (var cycle = 0; cycle < 2; cycle++) {
        final result = WordZotero.fields(document).single;
        expect(result.cachedText, '3');
        expect(result.run!.isAtomic, isTrue);
        expect(result.run!.properties.vertAlign, WmlVertAlign.superscript);
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    },
  );

  test(
    'mixed inline formatting retains styled runs in one protected field',
    () {
      final document = WmlDocument.empty(text: 'Text ');
      final session = _session(document, offset: 5);
      final field = _call(session, 'Document.insertField', ['Http', 0]) as Map;
      _set(
        session,
        field['id'] as String,
        _citation('mixed', 'Book 12'),
        html: '<i>Book</i> 12',
      );
      _call(session, 'Document.complete');
      session.prepareReview();
      expect(session.formattingWarnings, isEmpty);
      session.apply();
      final result = WordZotero.fields(document).single;
      expect(result.cachedText, 'Book 12');
      expect(result.run, isNull);
      expect(result.canEdit, isTrue);
      expect(
        result.paragraph.inlines
            .whereType<WmlRun>()
            .singleWhere((run) => run.text == 'Book')
            .properties
            .italic,
        isTrue,
      );
      expect(
        WmlRunEdit.normalizeRange(
          result.paragraph,
          result.start + 1,
          result.end - 1,
        ),
        (start: result.start, end: result.end),
      );
    },
  );

  test(
    'foreign document and field identities and malformed commands are rejected before mutation',
    () {
      final document = WmlDocument.empty(text: 'Keep ');
      WordZotero.insertCitation(
        document.paragraphs.single,
        _citation('original'),
      );
      final session = _session(document);
      final before = _snapshot(document);
      for (final input in <(String, List<dynamic>)>[
        ('Application.getActiveDocument', ['unexpected']),
        ('Document.getFields', []),
        ('Document.getFields', ['other-document', 'Http']),
        ('Document.getFields', [_documentId]),
        ('Field.setText', [_documentId, 'missing', 'Text', false]),
        ('Field.setText', [_documentId, 'f0', 'Text', 'true']),
        ('Field.setCode', [_documentId, 'f0', 'ITEM CSL_CITATION {}']),
        (
          'Field.setCode',
          [_documentId, 'f0', 'ADDIN ZOTERO_ITEM CSL_CITATION {}'],
        ),
        ('Field.select', [_documentId, 0]),
        ('Document.insertField', [_documentId, 'Http', 3]),
        (
          'Document.convert',
          [
            _documentId,
            ['f0', 'f0'],
            'Http',
            [1, 1],
          ],
        ),
        (
          'Document.convert',
          [
            _documentId,
            ['f0'],
            'Http',
            <int>[],
          ],
        ),
        (
          'Document.setBibliographyStyle',
          [
            _documentId,
            0,
            0,
            1,
            1,
            [double.nan],
            1,
          ],
        ),
      ]) {
        expect(
          () => session.handle(input.$1, input.$2),
          throwsFormatException,
          reason: input.$1,
        );
        expect(_snapshot(document), before);
      }
      expect(
        () => _call(session, 'Document.getFields', ['Field']),
        throwsUnsupportedError,
      );
      expect(
        () => _call(session, 'Document.exportDocument'),
        throwsFormatException,
      );
      expect(
        () =>
            _call(session, 'Field.setCode', ['f0', 'BIBL {} CSL_BIBLIOGRAPHY']),
        throwsUnsupportedError,
      );
      expect(_snapshot(document), before);
    },
  );

  test(
    'changed text or replaced citation metadata invalidates a prepared result',
    () {
      for (final editCode in [false, true]) {
        final document = WmlDocument.empty(text: 'Keep ');
        WordZotero.insertCitation(
          document.paragraphs.single,
          _citation('original'),
        );
        final session = _session(document);
        _set(
          session,
          _fields(session).single['id'] as String,
          _citation('original', 'New result'),
        );
        _call(session, 'Document.complete');
        if (editCode) {
          WordZotero.updateCitation(
            WordZotero.fields(document).single,
            _citation('other'),
          );
        } else {
          document.paragraphs.single.inlines.insert(
            0,
            WmlRun(text: 'changed '),
          );
        }
        final afterExternalEdit = _snapshot(document);
        expect(session.apply, throwsStateError);
        expect(_snapshot(document), afterExternalEdit);
      }
    },
  );

  test('locked documents and missing or repeated note anchors are refused', () {
    for (final tracked in [true, false]) {
      final document = WmlDocument.empty();
      document.trackRevisions = tracked;
      document.restrictEditing = !tracked;
      expect(() => _session(document), throwsUnsupportedError);
    }
    final document = WmlDocument.empty(text: 'Body ');
    _note(document, document.paragraphs.single, citationId: 'note');
    final ref = document.paragraphs.single.inlines
        .whereType<WmlRun>()
        .singleWhere((r) => r.noteRefId != null);
    document.paragraphs.single.inlines.add(
      WmlRun(text: ref.text, noteRefId: ref.noteRefId),
    );
    expect(() => _session(document), throwsUnsupportedError);
    document.paragraphs.single.inlines.removeLast();
    document.footnotes.clear();
    expect(() => _session(document), throwsUnsupportedError);
  });

  test(
    'real Zotero processor German ibid and locators survive whole-document refresh',
    () async {
      final scenario = _scenario('german-ibid');
      final citations = (scenario['citations'] as List)
          .cast<Map<String, dynamic>>();
      final rendered = (scenario['rendered'] as List)
          .cast<Map<String, dynamic>>();
      var document = WmlDocument.empty(text: 'Citations ');
      for (var i = 0; i < citations.length; i++) {
        final note = WordNotes.insert(
          document,
          document.paragraphs.first,
          endnote: false,
        );
        WordZotero.insertCitation(
          note.paragraphs.single,
          ZoteroCitation.fromJson({
            ...citations[i],
            'properties': {
              ...citations[i]['properties'] as Map<String, dynamic>,
              'plainCitation': 'Old $i',
            },
          }),
        );
      }
      final before = _snapshot(document);
      final session = _session(document);
      final fields = _fields(session);
      expect(fields.map((f) => f['noteIndex']), List.generate(9, (i) => i + 1));
      for (var i = 0; i < fields.length; i++) {
        _set(
          session,
          fields[i]['id'] as String,
          _processorCitation(citations[i], rendered[i]),
          html: rendered[i]['html'] as String,
        );
      }
      _call(session, 'Document.setDocumentData', [
        _preferences(style: scenario['styleId'] as String),
      ]);
      expect(_snapshot(document), before);
      _apply(session);
      for (var cycle = 0; cycle < 2; cycle++) {
        final caches = _fields(
          _session(document),
        ).map((f) => f['text']).toList();
        expect(caches[1], 'Ebd.');
        expect(caches[2], 'Ebd., 34.');
        expect(caches[4], contains('Müller'));
        expect(caches[4], isNot(startsWith('Ebd.')));
        expect(
          caches,
          rendered.map(
            (r) => ZoteroFormattedText.fromHtml(r['html'] as String).plainText,
          ),
        );
        document = WordDeserializer().readBytes(
          await OfficeIsolateSave.word(document),
        );
      }
    },
  );

  test(
    'real numeric processor output renumbers existing citations after a preceding insertion',
    () {
      final original = _scenario('numeric-original');
      final prepended = _scenario('numeric-prepend');
      final beforeCitations = (original['citations'] as List)
          .cast<Map<String, dynamic>>();
      final beforeRendered = (original['rendered'] as List)
          .cast<Map<String, dynamic>>();
      final afterCitations = (prepended['citations'] as List)
          .cast<Map<String, dynamic>>();
      final afterRendered = (prepended['rendered'] as List)
          .cast<Map<String, dynamic>>();
      final document = WmlDocument.empty(text: 'Start ');
      final p = document.paragraphs.single;
      for (var i = 0; i < beforeCitations.length; i++) {
        WordZotero.insertCitation(
          p,
          _processorCitation(beforeCitations[i], beforeRendered[i]),
        );
        p.inlines.add(WmlRun(text: ' '));
      }
      final session = _session(document, offset: 0);
      final added = _call(session, 'Document.insertField', ['Http', 0]) as Map;
      _set(
        session,
        added['id'] as String,
        _processorCitation(afterCitations.first, afterRendered.first),
        html: afterRendered.first['html'] as String,
      );
      final fields = _fields(session);
      for (var i = 1; i < fields.length; i++) {
        _set(
          session,
          fields[i]['id'] as String,
          _processorCitation(afterCitations[i], afterRendered[i]),
          html: afterRendered[i]['html'] as String,
        );
      }
      _apply(session);
      expect(WordZotero.fields(document).map((f) => f.cachedText), [
        '[1]',
        '[2]',
        '[3]',
        '[2]',
      ]);
      expect(p.text, '[1]Start [2] [3] [2] ');
    },
  );

  test(
    'real author-year disambiguation updates both existing and newly inserted citations',
    () {
      final original = _scenario('author-year-single');
      final changed = _scenario('author-year-disambiguation');
      final first = _processorCitation(
        (original['citations'] as List).single as Map<String, dynamic>,
        (original['rendered'] as List).single as Map<String, dynamic>,
      );
      final document = WmlDocument.empty();
      WordZotero.insertCitation(document.paragraphs.single, first);
      final session = _session(
        document,
        offset: document.paragraphs.single.text.length,
      );
      _call(session, 'Document.insertField', ['Http', 0]);
      final fields = _fields(session);
      final citations = (changed['citations'] as List)
          .cast<Map<String, dynamic>>();
      final rendered = (changed['rendered'] as List)
          .cast<Map<String, dynamic>>();
      for (var i = 0; i < fields.length; i++) {
        _set(
          session,
          fields[i]['id'] as String,
          _processorCitation(citations[i], rendered[i]),
          html: rendered[i]['html'] as String,
        );
      }
      _apply(session);
      expect(WordZotero.fields(document).map((f) => f.cachedText), [
        '(Müller, 2024a)',
        '(Müller, 2024b)',
      ]);
    },
  );
}
