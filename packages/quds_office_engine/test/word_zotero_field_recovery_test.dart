import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _id = 'native-field-recovery';
const _badCitation = ' ADDIN ZOTERO_ITEM CSL_CITATION {broken} ';
const _badBibliography = ' ADDIN ZOTERO_BIBL {broken} CSL_BIBLIOGRAPHY ';

// Zotero CitationField.clearCode() deliberately sends this incomplete code
// before reselection. It is a transaction state, never a completed citation.
// Source: zotero/zotero chrome/content/zotero/xpcom/integration.js,
// Git blob 19deafdfc35ea25d7e9f82ab2e9afad83d0c28a0, clearCode/resolveCorrupt.
const _emptyCitation = 'ITEM CSL_CITATION {"citationItems":[],"properties":{}}';

WmlParagraph _p(String text) => WmlParagraph(inlines: [WmlRun(text: text)]);

WmlDocument _document(List<WmlBlock> blocks) =>
    WmlDocument(sections: [WmlSection(blocks: blocks)]);

WmlTable _table(List<List<WmlBlock>> cells) => WmlTable(
  grid: [for (final _ in cells) 200],
  rows: [
    WmlTableRow(
      cells: [for (final blocks in cells) WmlTableCell(blocks: blocks)],
    ),
  ],
);

WmlParagraph _atomic({String instruction = _badCitation}) => WmlParagraph(
  inlines: [
    WmlRun(text: 'Before '),
    WmlRun(
      text: '(Old source)',
      properties: WmlRunProps(italic: true),
      fieldInstruction: instruction,
    ),
    WmlRun(text: ' After'),
  ],
);

WmlParagraph _richPacket({String instruction = _badCitation}) => WmlParagraph(
  inlines: [
    WmlRun(text: 'Before '),
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: instruction),
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
    WmlRun(text: 'Old ', properties: WmlRunProps(bold: true)),
    WmlRun(text: 'source', properties: WmlRunProps(italic: true)),
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
    WmlRun(text: ' After'),
  ],
);

({WmlParagraph first, WmlParagraph last}) _multipartBibliography() => (
  first: WmlParagraph(
    inlines: [
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
      WmlFieldBoundary(
        kind: WmlFieldBoundaryKind.instruction,
        text: _badBibliography,
      ),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
      WmlRun(text: 'Alpha book.', properties: WmlRunProps(bold: true)),
    ],
  ),
  last: WmlParagraph(
    inlines: [
      WmlRun(text: 'Beta book.', properties: WmlRunProps(italic: true)),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
    ],
  ),
);

WordZoteroCitingSession _session(WmlDocument document, {WmlParagraph? at}) =>
    WordZoteroCitingSession(
      document: document,
      documentId: _id,
      insertionParagraph: at ?? document.paragraphs.first,
    );

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_id, ...args]);

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http']) as List)
        .cast<Map<String, Object>>();

ZoteroCitation _citation({
  int noteIndex = 0,
  String text = 'Repaired source',
}) => ZoteroCitation(
  citationId: 'recovered-cluster',
  plainCitation: text,
  noteIndex: noteIndex,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {
        'type': 'book',
        'title': 'Recovered source',
        'author': [
          {'family': 'Lovelace', 'given': 'Ada'},
        ],
      },
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
      locator: '17–19',
      label: 'page',
      prefix: 'see ',
    ),
  ],
);

String _repairedCode({int noteIndex = 0, String text = 'Repaired source'}) =>
    'ITEM CSL_CITATION ${jsonEncode(_citation(noteIndex: noteIndex, text: text).toJson())}';

void _finish(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

String _snapshot(WmlDocument document) => jsonEncode({
  'body': [for (final p in document.paragraphs) p.text],
  'notes': [
    for (final n in [...document.footnotes, ...document.endnotes])
      {'id': n.id, 'endnote': n.endnote, 'text': n.text},
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
  'data': document.zoteroDocumentData,
});

void main() {
  for (final payload in [
    '',
    '{broken}',
    '{broken',
    '{\n  "citationID": "broken-schema", "citationItems": "not-an-array"\n}',
    '{"citationItems":[],"properties":{}}',
  ]) {
    test(
      'exposes original damaged citation payload without normalizing $payload',
      () {
        final paragraph = _atomic(
          instruction: ' ADDIN ZOTERO_ITEM CSL_CITATION $payload ',
        );
        final document = _document([paragraph]);
        final original = WordZotero.fields(document).single;
        expect(original.isValid, isFalse);
        expect(original.canEdit, isFalse);
        final before = _snapshot(document);

        final session = _session(document);
        final field = _fields(session).single;
        expect(field['code'], 'ITEM CSL_CITATION $payload');
        expect(field['text'], '(Old source)');
        _call(session, 'Field.select', [field['id']]);
        expect(
          session.selectedFieldContext!.sourceField!.instruction,
          original.instruction,
        );
        expect(session.selectedFieldContext!.sourceText, '(Old source)');
        expect(
          session.selectedFieldContext!.sourceRanges.single.paragraph,
          same(paragraph),
        );
        expect(_snapshot(document), before);
      },
    );
  }

  test(
    'citation reselection clears transient code, then repairs existing field',
    () {
      final paragraph = _richPacket();
      final document = _document([paragraph]);
      final before = _snapshot(document);
      final session = _session(document);
      final field = _fields(session).single;
      _call(session, 'Field.select', [field['id']]);
      _call(session, 'Document.activate');
      _call(session, 'Field.setCode', [field['id'], _emptyCitation]);
      expect(_fields(session).single['code'], _emptyCitation);
      expect(session.selectedFieldContext!.sourceText, 'Old source');
      expect(_snapshot(document), before);

      _call(session, 'Field.setCode', [field['id'], _repairedCode()]);
      _call(session, 'Field.setText', [
        field['id'],
        '<i>Repaired</i> <b>source</b>',
        true,
      ]);
      expect(session.selectedFieldContext!.sourceText, 'Old source');
      expect(_snapshot(document), before);
      _finish(session);

      expect(session.selectedFieldContext, isNull);
      expect(paragraph.text, 'Before Repaired source After');
      final repaired = WordZotero.fields(document).single;
      expect(repaired.citation!.citationId, 'recovered-cluster');
      expect(repaired.citation!.items.single.locator, '17–19');
      expect(repaired.citation!.items.single.prefix, 'see ');
      final reopened = _reopen(document);
      final saved = WordZotero.fields(reopened).single;
      expect(saved.isValid, isTrue);
      expect(saved.cachedText, 'Repaired source');
      expect(saved.citation!.citationId, 'recovered-cluster');
      expect(WmlRunEdit.propsAt(saved.paragraph, saved.start).italic, isTrue);
      expect(
        WmlRunEdit.propsAt(
          saved.paragraph,
          saved.start + 'Repaired '.length,
        ).bold,
        isTrue,
      );
    },
  );

  for (final state in ['unresolved', 'cleared', 'TEMP']) {
    test(
      'completion refuses $state recovery without publishing staged content',
      () {
        final document = _document([_atomic()]);
        final before = _snapshot(document);
        final session = _session(document);
        final field = _fields(session).single;
        if (state != 'unresolved') {
          _call(session, 'Field.setCode', [
            field['id'],
            state == 'cleared' ? _emptyCitation : 'TEMP',
          ]);
        }
        _call(session, 'Field.setText', [
          field['id'],
          'Staged replacement',
          false,
        ]);
        expect(
          () => _call(session, 'Document.complete'),
          throwsFormatException,
        );
        expect(session.isComplete, isFalse);
        expect(session.apply, throwsStateError);
        expect(_snapshot(document), before);
      },
    );
  }

  test(
    'malformed inbound repairs remain refused despite recoverable source',
    () {
      final document = _document([_atomic()]);
      final before = _snapshot(document);
      final session = _session(document);
      final field = _fields(session).single;
      for (final code in [
        'ITEM CSL_CITATION {broken}',
        'ITEM CSL_CITATION {}',
        'ITEM CSL_CITATION {"citationItems":[],"properties":null}',
        'ITEM CSL_CITATION {"citationItems":[{}],"properties":{}}',
      ]) {
        expect(
          () => _call(session, 'Field.setCode', [field['id'], code]),
          throwsFormatException,
          reason: code,
        );
      }
      expect(_fields(session).single['code'], 'ITEM CSL_CITATION {broken}');
      expect(_snapshot(document), before);
    },
  );

  for (final clearFirst in [false, true]) {
    test(
      'removeCode preserves rich damaged cache (clearFirst=$clearFirst)',
      () {
        final paragraph = _richPacket();
        final originalRuns = paragraph.inlines.whereType<WmlRun>().toList();
        final document = _document([paragraph]);
        final session = _session(document);
        final field = _fields(session).single;
        _call(session, 'Field.select', [field['id']]);
        if (clearFirst) {
          _call(session, 'Field.setCode', [field['id'], _emptyCitation]);
        }
        _call(session, 'Field.removeCode', [field['id']]);
        expect(session.selectedFieldContext, isNull);
        _finish(session);

        expect(WordZotero.fields(document), isEmpty);
        expect(paragraph.text, 'Before Old source After');
        expect(paragraph.inlines.whereType<WmlRun>().toList(), originalRuns);
        expect(originalRuns[1].properties.bold, isTrue);
        expect(originalRuns[2].properties.italic, isTrue);
        final reopened = _reopen(document);
        expect(WordZotero.fields(reopened), isEmpty);
        expect(reopened.paragraphs.single.text, 'Before Old source After');
        expect(
          reopened.paragraphs.single.inlines.whereType<WmlRun>().any(
            (run) => run.text == 'Old ' && run.properties.bold,
          ),
          isTrue,
        );
        expect(
          reopened.paragraphs.single.inlines.whereType<WmlRun>().any(
            (run) => run.text == 'source' && run.properties.italic,
          ),
          isTrue,
        );
      },
    );
  }

  test(
    'unlink publishes explicitly returned rich text without persisting damaged metadata',
    () {
      for (final clearFirst in [false, true]) {
        final paragraph = _richPacket();
        final document = _document([paragraph]);
        final before = _snapshot(document);
        final session = _session(document);
        final field = _fields(session).single;
        if (clearFirst) {
          _call(session, 'Field.setCode', [field['id'], _emptyCitation]);
        }
        _call(session, 'Field.setText', [
          field['id'],
          '<i>Changed</i> <b>cache</b>',
          true,
        ]);
        _call(session, 'Field.removeCode', [field['id']]);
        expect(_snapshot(document), before);
        _finish(session);

        expect(WordZotero.fields(document), isEmpty);
        expect(paragraph.text, 'Before Changed cache After');
        final reopened = _reopen(document);
        expect(WordZotero.fields(reopened), isEmpty);
        expect(reopened.paragraphs.single.text, 'Before Changed cache After');
        final result = reopened.paragraphs.single;
        expect(WmlRunEdit.propsAt(result, 'Before '.length).italic, isTrue);
        expect(
          WmlRunEdit.propsAt(result, 'Before Changed '.length).bold,
          isTrue,
        );
      }
    },
  );

  test(
    'Field.delete removes damaged citation text; it is distinct from unlink',
    () {
      final paragraph = _richPacket();
      final document = _document([paragraph]);
      final session = _session(document);
      final field = _fields(session).single;
      _call(session, 'Field.select', [field['id']]);
      _call(session, 'Field.delete', [field['id']]);
      expect(session.selectedFieldContext, isNull);
      _finish(session);
      expect(WordZotero.fields(document), isEmpty);
      expect(paragraph.text, 'Before  After');
      expect(_reopen(document).paragraphs.single.text, 'Before  After');
    },
  );

  for (final story in ['body', 'table', 'footnote', 'endnote']) {
    test(
      'repair retains original $story ownership and authored surrounding text',
      () {
        final paragraph = _atomic();
        final document = _document([_p('Body anchor')]);
        WmlNote? note;
        if (story == 'body') {
          document.sections.single.blocks.add(paragraph);
        } else if (story == 'table') {
          document.sections.single.blocks.add(
            _table([
              [paragraph],
              [_p('Neighbor cell')],
            ]),
          );
        } else {
          note = WordNotes.insert(
            document,
            document.paragraphs.first,
            text: 'Authored note lead',
            endnote: story == 'endnote',
          );
          note.blocks.add(paragraph);
        }
        final originalStoryText = story == 'table' ? 'Neighbor cell' : null;
        final session = _session(document, at: paragraph);
        final field = _fields(session).single;
        expect(field['noteIndex'], note == null ? 0 : 1);
        _call(session, 'Field.select', [field['id']]);
        expect(session.selectedFieldContext!.sourceNote, same(note));
        _call(session, 'Field.setCode', [field['id'], _emptyCitation]);
        _call(session, 'Field.setCode', [
          field['id'],
          _repairedCode(noteIndex: field['noteIndex'] as int),
        ]);
        _call(session, 'Field.setText', [
          field['id'],
          'Repaired source',
          false,
        ]);
        _finish(session);
        expect(paragraph.text, 'Before Repaired source After');
        if (note != null) {
          expect(note.paragraphs.first.text, contains('Authored note lead'));
          expect(note.blocks, contains(same(paragraph)));
        }
        if (originalStoryText != null) {
          expect(
            document.paragraphs.map((p) => p.text),
            contains(originalStoryText),
          );
        }
        final reopened = _reopen(document);
        final reopenedField = WordZotero.fields(reopened).single;
        expect(reopenedField.citation!.citationId, 'recovered-cluster');
        expect(reopenedField.cachedText, 'Repaired source');
        final next = _session(reopened);
        expect(_fields(next).single['noteIndex'], field['noteIndex']);
      },
    );
  }

  for (final wholeParagraph in [false, true]) {
    test(
      'damaged bibliography repairs an ${wholeParagraph ? 'entire paragraph' : 'atomic run'}',
      () {
        final paragraph = wholeParagraph
            ? _p('Old bibliography')
            : _atomic(instruction: _badBibliography);
        if (wholeParagraph) {
          paragraph.properties.fieldInstruction = _badBibliography;
        }
        final document = _document([paragraph]);
        final before = _snapshot(document);
        final session = _session(document);
        final field = _fields(session).single;
        expect(field['code'], 'BIBL {broken} CSL_BIBLIOGRAPHY');
        _call(session, 'Field.setCode', [
          field['id'],
          'BIBL {} CSL_BIBLIOGRAPHY',
        ]);
        _call(session, 'Field.setText', [
          field['id'],
          'Rebuilt bibliography',
          false,
        ]);
        expect(_snapshot(document), before);
        _finish(session);
        expect(
          paragraph.text,
          wholeParagraph
              ? 'Rebuilt bibliography'
              : 'Before Rebuilt bibliography After',
        );
        final saved = WordZotero.fields(_reopen(document)).single;
        expect(saved.kind, ZoteroFieldKind.bibliography);
        expect(saved.metadata, isEmpty);
        expect(saved.cachedText, 'Rebuilt bibliography');
      },
    );
  }

  for (final action in ['repair', 'unlink', 'delete']) {
    test(
      '$action handles one damaged bibliography across complete entry paragraphs',
      () {
        final parts = _multipartBibliography();
        final beforeParagraph = _p('Keep before');
        final afterParagraph = _p('Keep after');
        final document = _document([
          beforeParagraph,
          parts.first,
          parts.last,
          afterParagraph,
        ]);
        final originalRuns = [
          ...parts.first.inlines.whereType<WmlRun>(),
          ...parts.last.inlines.whereType<WmlRun>(),
        ];
        final session = _session(document);
        final field = _fields(session).single;
        expect(field['text'], 'Alpha book.\nBeta book.');
        _call(session, 'Field.select', [field['id']]);
        expect(session.selectedFieldContext!.sourceRanges.length, 2);
        if (action == 'repair') {
          _call(session, 'Field.setCode', [
            field['id'],
            'BIBL {} CSL_BIBLIOGRAPHY',
          ]);
          _call(session, 'Field.setText', [
            field['id'],
            '<div class="csl-bib-body"><div class="csl-entry">'
                '<b>New Alpha.</b></div><div class="csl-entry">'
                '<i>New Beta.</i></div></div>',
            true,
          ]);
        } else {
          _call(
            session,
            action == 'unlink' ? 'Field.removeCode' : 'Field.delete',
            [field['id']],
          );
        }
        _finish(session);
        expect(document.sections.single.blocks.first, same(beforeParagraph));
        expect(document.sections.single.blocks.last, same(afterParagraph));
        if (action == 'repair') {
          final repaired = WordZotero.fields(document).single;
          expect(repaired.cachedText, 'New Alpha.\nNew Beta.');
          expect(repaired.paragraphs.length, 2);
          expect(WordZotero.fields(_reopen(document)).single.isValid, isTrue);
        } else {
          expect(WordZotero.fields(document), isEmpty);
          if (action == 'unlink') {
            expect(document.paragraphs.map((p) => p.text), [
              'Keep before',
              'Alpha book.',
              'Beta book.',
              'Keep after',
            ]);
            expect(
              parts.first.inlines.whereType<WmlRun>().single,
              same(originalRuns[0]),
            );
            expect(
              parts.last.inlines.whereType<WmlRun>().single,
              same(originalRuns[1]),
            );
            expect(WordZotero.fields(_reopen(document)), isEmpty);
          } else {
            expect(document.paragraphs.map((p) => p.text), [
              'Keep before',
              '',
              'Keep after',
            ]);
          }
        }
      },
    );
  }

  test(
    'multipart bibliography can publish new entries and unlink damaged code',
    () {
      final parts = _multipartBibliography();
      final document = _document([
        _p('Keep before'),
        parts.first,
        parts.last,
        _p('Keep after'),
      ]);
      final before = _snapshot(document);
      final session = _session(document);
      final field = _fields(session).single;
      _call(session, 'Field.setText', [
        field['id'],
        '<div class="csl-bib-body"><div class="csl-entry">'
            '<i>Replacement first.</i></div><div class="csl-entry">'
            '<b>Replacement second.</b></div></div>',
        true,
      ]);
      _call(session, 'Field.removeCode', [field['id']]);
      expect(_snapshot(document), before);
      _finish(session);

      expect(WordZotero.fields(document), isEmpty);
      final reopened = _reopen(document);
      expect(WordZotero.fields(reopened), isEmpty);
      final paragraphs = reopened.paragraphs.toList();
      expect(paragraphs.map((p) => p.text), [
        'Keep before',
        'Replacement first.',
        'Replacement second.',
        'Keep after',
      ]);
      expect(WmlRunEdit.propsAt(paragraphs[1], 0).italic, isTrue);
      expect(WmlRunEdit.propsAt(paragraphs[2], 0).bold, isTrue);
    },
  );

  final unsafe = <String, WmlDocument Function()>{
    'locked atomic field': () {
      final paragraph = _atomic();
      paragraph.inlines.whereType<WmlRun>().elementAt(1).fieldLocked = true;
      return _document([paragraph]);
    },
    'nested field packet': () {
      final paragraph = _richPacket();
      paragraph.inlines.insertAll(4, [
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
        WmlFieldBoundary(
          kind: WmlFieldBoundaryKind.instruction,
          text: ' DATE ',
        ),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
        WmlRun(text: 'Nested date'),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
      ]);
      return _document([paragraph]);
    },
    'opaque instruction properties': () {
      final paragraph = _richPacket();
      paragraph.inlines[2] = WmlFieldBoundary(
        kind: WmlFieldBoundaryKind.instruction,
        text: _badCitation,
        runPropertiesXml:
            '<w:rPr xmlns:w="${OfficeNamespaces.w}"><w:b/></w:rPr>',
      );
      return _document([paragraph]);
    },
    'unclosed field packet': () {
      final paragraph = _richPacket();
      paragraph.inlines.removeAt(6);
      return _document([paragraph]);
    },
    'repeated separator': () {
      final paragraph = _richPacket();
      paragraph.inlines.insert(
        4,
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
      );
      return _document([paragraph]);
    },
    'citation across paragraphs': () {
      final parts = _multipartBibliography();
      parts.first.inlines[1] = WmlFieldBoundary(
        kind: WmlFieldBoundaryKind.instruction,
        text: _badCitation,
      );
      return _document([parts.first, parts.last]);
    },
    'bibliography across table cells': () {
      final parts = _multipartBibliography();
      return _document([
        _table([
          [parts.first],
          [parts.last],
        ]),
      ]);
    },
    'paragraph aliased by two cell owners': () {
      final paragraph = _atomic();
      return _document([
        _table([
          [paragraph],
          [paragraph],
        ]),
      ]);
    },
  };
  for (final entry in unsafe.entries) {
    test(
      'metadata recovery refuses ${entry.key} without changing the source',
      () {
        final document = entry.value();
        final before = _snapshot(document);
        expect(() => _session(document), throwsUnsupportedError);
        expect(_snapshot(document), before);
      },
    );
  }

  for (final change in ['code', 'text', 'lock', 'cell owner']) {
    test('staged repair refuses source changes to $change', () {
      final paragraph = _atomic();
      final table = _table([
        [paragraph],
        [_p('Other cell')],
      ]);
      final document = _document([table]);
      final session = _session(document);
      final field = _fields(session).single;
      _call(session, 'Field.setCode', [field['id'], _repairedCode()]);
      _call(session, 'Field.setText', [field['id'], 'Repaired source', false]);
      _call(session, 'Document.complete');
      final run = paragraph.inlines.whereType<WmlRun>().elementAt(1);
      switch (change) {
        case 'code':
          run.fieldInstruction = ' ADDIN ZOTERO_ITEM CSL_CITATION {different} ';
        case 'text':
          run.text = 'Externally changed';
        case 'lock':
          run.fieldLocked = true;
        case 'cell owner':
          // Flattened paragraph order remains identical, but the first cell
          // no longer owns the source; coordinate matching alone is unsafe.
          table.rows.single.cells.first.blocks.remove(paragraph);
          table.rows.single.cells.last.blocks.insert(0, paragraph);
      }
      final external = _snapshot(document);
      expect(session.apply, throwsStateError);
      expect(_snapshot(document), external);
    });
  }

  test(
    'direct recovery refuses a stale complex owner after zero-width markup appears',
    () {
      final paragraph = _richPacket();
      final document = _document([paragraph]);
      final original = WordZotero.fields(document).single;
      expect(original.canEdit, isFalse);
      expect(original.canEditNativeResult, isTrue);
      final bookmarkStart = WmlBookmarkBoundary(
        id: '81',
        isStart: true,
        name: 'AddedDuringRecovery',
      );
      final bookmarkEnd = WmlBookmarkBoundary(id: '81', isStart: false);
      paragraph.inlines.insertAll(4, [bookmarkStart, bookmarkEnd]);
      final afterExternalEdit = List<WmlInline>.of(paragraph.inlines);
      final afterExternalSnapshot = _snapshot(document);
      final current = WordZotero.fields(document).single;
      expect(current.canEdit, isFalse);
      expect(current.canEditNativeResult, isFalse);
      expect(current.cachedText, original.cachedText);
      expect(current.instruction, original.instruction);
      expect(current.start, original.start);
      expect(current.end, original.end);

      expect(
        () => WordZotero.replaceNativeResult(
          original,
          instruction: _citation().fieldInstruction,
          text: 'Repaired source',
        ),
        throwsStateError,
      );
      expect(paragraph.inlines, afterExternalEdit);
      expect(_snapshot(document), afterExternalSnapshot);
    },
  );

  test(
    'valid citation outside an unrelated inline control remains processable',
    () {
      final paragraph = _atomic(
        instruction: _citation(text: '(Old source)').fieldInstruction,
      );
      final control = WmlContentControlData(
        xml:
            '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr>'
            '<w:id w:val="71"/><w:lock w:val="sdtContentLocked"/>'
            '</w:sdtPr><w:sdtContent/></w:sdt>',
        sourcePartUri: '/word/document.xml',
        relationships: [],
        id: '71',
      );
      final start = WmlContentControlBoundary(control: control, start: true);
      final end = WmlContentControlBoundary(control: control, start: false);
      paragraph.inlines.insert(0, start);
      paragraph.inlines.insert(2, end);
      final document = _document([paragraph]);
      final session = _session(document);
      final field = _fields(session).single;
      _call(session, 'Field.setCode', [field['id'], _repairedCode()]);
      _call(session, 'Field.setText', [field['id'], 'Repaired source', false]);
      _finish(session);

      expect(paragraph.text, 'Before Repaired source After');
      expect(paragraph.inlines.whereType<WmlContentControlBoundary>(), [
        start,
        end,
      ]);
      final span = WordContentControls.spans(paragraph).single;
      expect(span.control, same(control));
      expect(span.start, 0);
      expect(span.end, 'Before '.length);
      expect(
        WordZotero.fields(document).single.citation!.citationId,
        'recovered-cluster',
      );
      final reopened = _reopen(document);
      expect(reopened.paragraphs.single.text, paragraph.text);
      expect(
        WordContentControls.spans(reopened.paragraphs.single).single.end,
        'Before '.length,
      );
      expect(WordZotero.fields(reopened).single.isValid, isTrue);

      WordZotero.unlinkNative(
        WordZotero.fields(document).single,
        document: document,
      );
      expect(WordZotero.fields(document), isEmpty);
      expect(paragraph.text, 'Before Repaired source After');
      expect(paragraph.inlines.whereType<WmlContentControlBoundary>(), [
        start,
        end,
      ]);
      expect(
        WordContentControls.spans(paragraph).single.control,
        same(control),
      );
      final unlinked = _reopen(document);
      expect(WordZotero.fields(unlinked), isEmpty);
      expect(unlinked.paragraphs.single.text, paragraph.text);
      expect(
        WordContentControls.spans(unlinked.paragraphs.single).single.end,
        'Before '.length,
      );
    },
  );
}
