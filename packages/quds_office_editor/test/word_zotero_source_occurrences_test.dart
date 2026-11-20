import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/word_zotero_sources.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _personal = 'http://zotero.org/users/42/items/SOURCE01';
const _group = 'http://zotero.org/groups/42/items/SOURCE01';
const _local = 'http://zotero.org/users/local/LOCALKEY/items/SOURCE01';

ZoteroCitationItem _item({
  String title = 'Stored source',
  List<String> uris = const [],
  bool snapshot = true,
  String locator = '',
}) => ZoteroCitationItem.fromJson({
  'id': 'same-id',
  if (snapshot)
    'itemData': {
      'id': 'same-id',
      'type': 'book',
      'title': title,
      'custom': {'retained': true},
    },
  if (uris.isNotEmpty) 'uris': uris,
  if (locator.isNotEmpty) 'locator': locator,
});

WmlParagraph _paragraph(String id, List<ZoteroCitationItem> items) {
  final paragraph = WmlParagraph(inlines: [WmlRun(text: 'Before ')]);
  WordZotero.insertCitation(
    paragraph,
    ZoteroCitation(citationId: id, plainCitation: '($id)', items: items),
  );
  paragraph.inlines.add(WmlRun(text: ' after'));
  return paragraph;
}

List<ZoteroDocumentReference> _references(List<WmlZoteroField> fields) =>
    zoteroDocumentReferences([
      for (final field in fields) ...?field.citation?.items,
    ]);

void main() {
  test('late transitive aliases link distinct fields only once', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            _paragraph('first', [
              _item(uris: [_local], locator: '1'),
              _item(uris: [_local], locator: '2'),
            ]),
            _paragraph('second', [
              _item(uris: [_personal]),
            ]),
            _paragraph('third', [
              _item(uris: [_group]),
            ]),
            _paragraph('bridge-one', [
              _item(uris: [_local, _personal], snapshot: false),
            ]),
            _paragraph('bridge-two', [
              _item(uris: [_personal, _group], snapshot: false),
            ]),
          ],
        ),
      ],
    );
    final fields = WordZotero.fields(document);
    final before = fields
        .map((field) => (field.instruction, field.cachedText))
        .toList();
    final reference = _references(fields).single;

    final occurrences = zoteroDocumentCitationOccurrences(document, fields);

    expect(reference.occurrences, 6);
    expect(occurrences.keys, [reference.selectionKey]);
    expect(
      occurrences[reference.selectionKey]!.map((entry) => entry.field),
      orderedEquals(fields),
    );
    expect(
      occurrences[reference.selectionKey]!.map((entry) => entry.location),
      [for (var i = 1; i <= 5; i++) 'Body · section 1 · paragraph $i'],
    );
    expect(
      fields.map((field) => (field.instruction, field.cachedText)),
      before,
    );
    expect(() => occurrences.clear(), throwsUnsupportedError);
    expect(
      () => occurrences[reference.selectionKey]!.clear(),
      throwsUnsupportedError,
    );
  });

  test(
    'same keys across libraries and differing offline snapshots stay apart',
    () {
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              _paragraph('personal', [
                _item(uris: [_personal]),
              ]),
              _paragraph('group', [
                _item(uris: [_group]),
              ]),
              _paragraph('local', [
                _item(uris: [_local]),
              ]),
              _paragraph('offline-one', [_item(title: 'First offline')]),
              _paragraph('offline-two', [_item(title: 'Second offline')]),
              _paragraph('offline-one-again', [
                _item(title: 'First offline', locator: '99'),
              ]),
            ],
          ),
        ],
      );
      final fields = WordZotero.fields(document);
      final references = _references(fields);

      final occurrences = zoteroDocumentCitationOccurrences(document, fields);

      expect(references, hasLength(5));
      expect(occurrences.keys, references.map((item) => item.selectionKey));
      expect(occurrences.values.map((entries) => entries.length), [
        1,
        1,
        1,
        2,
        1,
      ]);
      expect(
        occurrences[references[3].selectionKey]!.map(
          (entry) => entry.field.citation!.citationId,
        ),
        ['offline-one', 'offline-one-again'],
      );
    },
  );

  test(
    'multiple fields in one paragraph stay distinct and repeated handles do not',
    () {
      final paragraph = _paragraph('first', [
        _item(uris: [_personal]),
      ]);
      WordZotero.insertCitation(
        paragraph,
        ZoteroCitation(
          citationId: 'second',
          plainCitation: '(second)',
          items: [
            _item(uris: [_personal]),
          ],
        ),
      );
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      );
      final fields = WordZotero.fields(document);
      final reference = _references(fields).single;

      final occurrences = zoteroDocumentCitationOccurrences(document, [
        ...fields,
        ...WordZotero.fields(document),
      ]);

      expect(occurrences[reference.selectionKey], hasLength(2));
      expect(
        occurrences[reference.selectionKey]!.map((entry) => entry.field),
        orderedEquals(fields),
      );
    },
  );

  test('labels notes with display numbers and retains unsupported stories', () {
    final document = WmlDocument.empty(text: 'Body ');
    final footnote = WordNotes.insert(
      document,
      document.paragraphs.single,
      endnote: false,
      text: 'Footnote ',
    );
    final endnote = WordNotes.insert(
      document,
      document.paragraphs.single,
      endnote: true,
      text: 'Endnote ',
    );
    for (final note in [footnote, endnote]) {
      final item = _item(uris: [_personal]);
      WordZotero.insertCitation(
        note.paragraphs.single,
        ZoteroCitation(
          citationId: note.endnote ? 'end' : 'foot',
          plainCitation: '(Note citation)',
          items: [item],
        ),
      );
    }
    document.sections.single.header.add(
      _paragraph('header', [
        _item(uris: [_personal]),
      ]),
    );
    document.comments.add(
      WmlComment(
        id: 7,
        paragraphs: [
          _paragraph('comment', [
            _item(uris: [_personal]),
          ]),
        ],
      ),
    );
    final fields = WordZotero.fields(document);
    final before = jsonEncode([
      for (final field in fields) field.citation!.toJson(),
    ]);

    final occurrences = zoteroDocumentCitationOccurrences(document, fields);

    expect(occurrences.values.single.map((entry) => entry.location), [
      'Header · section 1 · paragraph 1',
      'Footnote 1 · paragraph 1',
      'Endnote i · paragraph 1',
      'Comment 7 · paragraph 1',
    ]);
    expect(
      jsonEncode([for (final field in fields) field.citation!.toJson()]),
      before,
    );
  });

  test(
    'orphaned notes use an explicit source ID and bibliographies add no sources',
    () {
      final document = WmlDocument.empty(text: 'Body');
      document.footnotes.add(
        WmlNote(
          id: 42,
          endnote: false,
          paragraphs: [
            _paragraph('orphan', [
              _item(uris: [_personal]),
            ]),
          ],
        ),
      );
      document.sections.single.blocks.addAll(
        WordZotero.nativeBibliographyParagraphs(
          instruction:
              ' ADDIN ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY ',
          text: 'First entry.\nSecond entry.',
        ),
      );
      final fields = WordZotero.fields(document);

      final occurrences = zoteroDocumentCitationOccurrences(document, fields);

      expect(occurrences, hasLength(1));
      expect(occurrences.values.single, hasLength(1));
      expect(
        occurrences.values.single.single.location,
        'Footnote (source ID 42) · paragraph 1',
      );
      expect(
        occurrences.values.single.single.field.citation!.citationId,
        'orphan',
      );
    },
  );
}
