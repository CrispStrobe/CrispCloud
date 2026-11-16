import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _documentId = 'zotero-scaling-test';

ZoteroCitation _citation(String id, {String text = 'Citation'}) =>
    ZoteroCitation(
      citationId: id,
      plainCitation: text,
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {'id': id, 'type': 'book', 'title': 'Source'},
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
        ),
      ],
    );

WmlParagraph _paragraph([String text = '']) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlNote _note(
  WmlDocument document,
  WmlParagraph anchor, {
  required int id,
  bool endnote = false,
  List<String> citations = const [],
}) {
  final paragraph = _paragraph(citations.isEmpty ? 'Explanatory note' : '');
  for (final citation in citations) {
    WordZotero.insertCitation(paragraph, _citation(citation));
  }
  final note = WmlNote(id: id, endnote: endnote, paragraphs: [paragraph]);
  (endnote ? document.endnotes : document.footnotes).add(note);
  anchor.inlines.add(
    WmlRun(text: '$id', noteRefId: id, noteRefEndnote: endnote),
  );
  return note;
}

WordZoteroCitingSession _session(
  WmlDocument document, {
  WmlParagraph? insertionParagraph,
}) => WordZoteroCitingSession(
  document: document,
  documentId: _documentId,
  insertionParagraph: insertionParagraph ?? document.paragraphs.first,
);

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, [_documentId, ...arguments]);

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http']) as List)
        .cast<Map<String, Object>>();

String _citationId(Map<String, Object> field) =>
    (jsonDecode(
          (field['code'] as String).substring('ITEM CSL_CITATION '.length),
        ) as Map)['citationID']
        as String;

Map<String, Object> _field(WordZoteroCitingSession session, String id) =>
    _fields(session).singleWhere((field) => _citationId(field) == id);

void main() {
  test(
    'large mixed-story field snapshots preserve reading order and guards',
    () {
      final blocks = <WmlBlock>[];
      final document = WmlDocument(sections: [WmlSection(blocks: blocks)]);
      final expectedIds = <String>[];
      final expectedIndexes = <int>[];
      var footIndex = 0;
      var endIndex = 0;
      for (var i = 0; i < 240; i++) {
        final paragraph = _paragraph();
        blocks.add(
          i % 4 == 0
              ? WmlTable(
                  rows: [
                    WmlTableRow(
                      cells: [
                        WmlTableCell(blocks: [paragraph]),
                      ],
                    ),
                  ],
                )
              : paragraph,
        );
        WordZotero.insertCitation(paragraph, _citation('body-$i'));
        expectedIds.add('body-$i');
        expectedIndexes.add(0);
        if (i % 3 == 0) {
          _note(document, paragraph, id: ++footIndex);
        }
        _note(document, paragraph, id: ++footIndex, citations: ['foot-$i']);
        expectedIds.add('foot-$i');
        expectedIndexes.add(footIndex);
        _note(
          document,
          paragraph,
          id: ++endIndex,
          endnote: true,
          citations: ['end-$i'],
        );
        expectedIds.add('end-$i');
        expectedIndexes.add(endIndex);
      }
      // The same numeric IDs legitimately occur in both note types, and neither
      // storage order nor numeric ID determines the citation processor's order.
      document.footnotes.setAll(0, document.footnotes.reversed.toList());
      document.endnotes.setAll(0, document.endnotes.reversed.toList());
      final session = _session(document);
      for (var pass = 0; pass < 3; pass++) {
        final fields = _fields(session);
        expect(fields.map(_citationId), expectedIds);
        expect(fields.map((field) => field['noteIndex']), expectedIndexes);
        expect(fields.map((field) => field['id']).toSet(), hasLength(720));
        session.assertUnchanged();
      }
      final last = _fields(session).last;
      _call(session, 'Field.select', [last['id']]);
      expect(_call(session, 'Document.cursorInField', ['Http']), last);
      _call(session, 'Document.complete');
      expect(session.hasChanges, isFalse);
      session.assertUnchanged();
    },
  );

  test(
    'note snapshots follow deletes, conversions and new field identities',
    () {
      final paragraphs = List.generate(4, (_) => _paragraph());
      final document = WmlDocument(sections: [WmlSection(blocks: paragraphs)]);
      _note(document, paragraphs[0], id: 1);
      _note(
        document,
        paragraphs[0],
        id: 2,
        citations: ['shared-a', 'shared-b'],
      );
      _note(document, paragraphs[1], id: 3, citations: ['sole-foot']);
      _note(
        document,
        paragraphs[2],
        id: 1,
        endnote: true,
        citations: ['sole-end'],
      );
      WordZotero.insertCitation(paragraphs[3], _citation('inline'));
      final session = _session(document, insertionParagraph: paragraphs[1]);
      final initial = _fields(session);
      expect(initial.map((field) => field['noteIndex']), [2, 2, 3, 1, 0]);
      final sharedA = _field(session, 'shared-a')['id'];
      final sharedB = _field(session, 'shared-b')['id'];
      final foot = _field(session, 'sole-foot')['id'];
      final end = _field(session, 'sole-end')['id'];
      final inline = _field(session, 'inline')['id'];

      _call(session, 'Field.delete', [foot]);
      _call(session, 'Document.convert', [
        [end, inline],
        'Http',
        [0, 2],
      ]);
      expect(_fields(session).map((field) => field['noteIndex']), [2, 2, 0, 1]);
      expect(
        () => _call(session, 'Field.select', [foot]),
        throwsFormatException,
      );
      expect(
        () => _call(session, 'Field.select', ['unrecognized']),
        throwsFormatException,
      );

      final inserted =
          _call(session, 'Document.insertField', ['Http', 1]) as Map;
      expect(inserted['noteIndex'], 3);
      _call(session, 'Field.delete', [inserted['id']]);
      expect(
        () => _call(session, 'Field.setText', [inserted['id'], 'stale', false]),
        throwsFormatException,
      );
      final replacement =
          _call(session, 'Document.insertField', ['Http', 1]) as Map;
      expect(replacement['id'], isNot(inserted['id']));
      expect(replacement['noteIndex'], 3);
      _call(session, 'Field.delete', [replacement['id']]);
      expect(_fields(session).map((field) => field['noteIndex']), [2, 2, 0, 1]);

      // Deleting one staged field must not make a multi-citation source note
      // eligible for conversion; its original content still owns both fields.
      _call(session, 'Field.delete', [sharedB]);
      expect(
        () => _call(session, 'Document.convert', [
          [sharedA],
          'Http',
          [2],
        ]),
        throwsUnsupportedError,
      );
      session.assertUnchanged();
      expect(document.footnotes, hasLength(3));
      expect(document.endnotes, hasLength(1));
    },
  );

  test(
    'equal codes in different notes cannot replace original field identity',
    () {
      final document = WmlDocument.empty();
      final body = document.paragraphs.single;
      final first = _note(document, body, id: 1, citations: ['identical']);
      _note(document, body, id: 2, citations: ['identical']);
      final session = _session(document);
      session.assertUnchanged();
      final old = first.paragraphs.single;
      first.paragraphs = [
        WmlParagraph(
          inlines: List<WmlInline>.of(old.inlines),
          properties: old.properties,
        ),
      ];
      expect(first.paragraphs.single.text, old.text);
      expect(WordZotero.fields(document), hasLength(2));
      expect(session.assertUnchanged, throwsStateError);
    },
  );

  test(
    'same-length metadata changes cannot hide among duplicate citations',
    () {
      final paragraphs = List.generate(64, (_) {
        final paragraph = _paragraph();
        WordZotero.insertCitation(paragraph, _citation('original'));
        return paragraph;
      });
      final document = WmlDocument(sections: [WmlSection(blocks: paragraphs)]);
      final session = _session(document);
      session.assertUnchanged();
      WordZotero.updateCitation(
        WordZotero.fields(document)[32],
        _citation('modified'),
      );
      expect(paragraphs[32].text, paragraphs[31].text);
      expect(session.assertUnchanged, throwsStateError);
    },
  );

  test(
    'duplicate anchored note IDs remain invalid within their own bucket',
    () {
      for (final endnote in [false, true]) {
        final document = WmlDocument.empty();
        final body = document.paragraphs.single;
        _note(document, body, id: 7, endnote: endnote, citations: ['first']);
        (endnote ? document.endnotes : document.footnotes).add(
          WmlNote(
            id: 7,
            endnote: endnote,
            paragraphs: [_paragraph('Duplicate')],
          ),
        );
        expect(() => _session(document), throwsUnsupportedError);
      }
    },
  );
}
