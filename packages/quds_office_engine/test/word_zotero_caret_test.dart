import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _documentId = 'caret-citation-test';

ZoteroCitation _citation(String id, String text) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'type': 'book', 'title': 'Source $id'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_documentId, ...args]);

WordZoteroCitingSession _session(
  WmlDocument document,
  WmlParagraph paragraph,
  int offset,
) => WordZoteroCitingSession(
  document: document,
  documentId: _documentId,
  insertionParagraph: paragraph,
  insertionOffset: offset,
);

WmlNote _note(WmlDocument document, {required bool endnote}) {
  final note = WordNotes.insert(
    document,
    document.paragraphs.first,
    endnote: endnote,
    text: 'See ',
  );
  WordZotero.insertCitation(
    note.paragraphs.single,
    _citation(endnote ? 'endnote' : 'footnote', '(Source)'),
  );
  note.paragraphs.single.inlines.add(WmlRun(text: ' for context.'));
  return note;
}

void main() {
  for (final endnote in [false, true]) {
    final kind = endnote ? 'endnote' : 'footnote';

    test('native add/edit finds the existing $kind citation at its caret', () {
      final document = WmlDocument.empty(text: 'Body');
      final note = _note(document, endnote: endnote);
      final paragraph = note.paragraphs.single;
      final beforeBody = document.paragraphs.single.text;
      final field = WordZotero.fields(document).single;
      final session = _session(document, paragraph, field.start + 1);
      final selected =
          _call(session, 'Document.cursorInField', ['Http'])
              as Map<String, Object>;

      expect(selected['code'], contains('CSL_CITATION'));
      expect(selected['noteIndex'], 1);
      expect(_call(session, 'Document.canInsertField', ['Http']), isTrue);
      _call(session, 'Field.setText', [
        selected['id'],
        '<i>Updated source</i>',
        true,
      ]);
      _call(session, 'Document.complete');
      session.apply();

      expect(paragraph.text, 'See Updated source for context.');
      expect(document.paragraphs.single.text, beforeBody);
      expect(document.footnotes.length + document.endnotes.length, 1);
      expect(
        (endnote ? document.endnotes : document.footnotes).single,
        same(note),
      );
      expect(WordZotero.fields(document), hasLength(1));
      expect(
        paragraph.inlines
            .whereType<WmlRun>()
            .singleWhere((run) => run.text == 'Updated source')
            .properties
            .italic,
        isTrue,
      );
    });

    test('$kind caret boundaries distinguish editing from insertion', () {
      final document = WmlDocument.empty(text: 'Body');
      final note = _note(document, endnote: endnote);
      final paragraph = note.paragraphs.single;
      final field = WordZotero.fields(document).single;

      final atStart = _session(document, paragraph, field.start);
      expect(_call(atStart, 'Document.cursorInField', ['Http']), isNotNull);
      final inside = _session(document, paragraph, field.start + 1);
      expect(
        () => _call(inside, 'Document.insertField', ['Http', 0]),
        throwsUnsupportedError,
      );
      for (final offset in [0, field.end, paragraph.text.length]) {
        final outside = _session(document, paragraph, offset);
        expect(_call(outside, 'Document.cursorInField', ['Http']), isNull);
        expect(_call(outside, 'Document.canInsertField', ['Http']), isTrue);
        final added =
            _call(outside, 'Document.insertField', ['Http', 0]) as Map;
        expect(added['noteIndex'], 1);
        _call(outside, 'Field.delete', [added['id']]);
        _call(outside, 'Document.complete');
        outside.apply();
      }
      expect(paragraph.text, 'See (Source) for context.');
      expect(WordZotero.fields(document), hasLength(1));
    });

    test('$kind caret offsets outside the paragraph are rejected', () {
      final document = WmlDocument.empty(text: 'Body');
      final paragraph = _note(document, endnote: endnote).paragraphs.single;
      for (final offset in [-1, paragraph.text.length + 1]) {
        expect(
          () => _session(document, paragraph, offset),
          throwsArgumentError,
        );
      }
    });
  }

  test(
    'same numeric footnote and endnote IDs select by paragraph identity',
    () {
      final document = WmlDocument.empty(text: 'Body');
      final footnote = _note(document, endnote: false);
      final endnote = _note(document, endnote: true);
      expect(footnote.id, endnote.id);
      final selectedCodes = <String>[];
      for (final note in [footnote, endnote]) {
        final session = _session(document, note.paragraphs.single, 5);
        final selected =
            _call(session, 'Document.cursorInField', ['Http']) as Map;
        selectedCodes.add(selected['code'] as String);
      }
      expect(selectedCodes[0], contains('"citationID":"footnote"'));
      expect(selectedCodes[1], contains('"citationID":"endnote"'));
    },
  );

  test('a detached lookalike paragraph cannot select an anchored citation', () {
    final document = WmlDocument.empty(text: 'Body');
    final paragraph = _note(document, endnote: false).paragraphs.single;
    final detached = WmlParagraph(inlines: [WmlRun(text: paragraph.text)]);
    final session = _session(document, detached, 5);
    expect(_call(session, 'Document.cursorInField', ['Http']), isNull);
    expect(_call(session, 'Document.canInsertField', ['Http']), isFalse);
  });

  test('unanchored note citations remain unsupported', () {
    final document = WmlDocument.empty(text: 'Body');
    final note = _note(document, endnote: false);
    document.paragraphs.single.inlines.removeWhere(
      (inline) => inline is WmlRun && inline.noteRefId != null,
    );
    expect(
      () => _session(document, note.paragraphs.single, 5),
      throwsUnsupportedError,
    );
  });
}
