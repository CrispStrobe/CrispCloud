import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/model/word_zotero_note.dart';
import 'package:test/test.dart';

const _id = 'zotero-add-note';
const _one = '<a href="https://www.zotero.org/?ABC123">(Old 1)</a>';
const _two = '<a href="https://www.zotero.org/?DEF456">(Old 2)</a>';

WordZoteroCitingSession _session(
  WmlDocument document, {
  int offset = 0,
  WmlParagraph? paragraph,
}) => WordZoteroCitingSession(
  document: document,
  documentId: _id,
  insertionParagraph: paragraph ?? document.paragraphs.first,
  insertionOffset: offset,
);
Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_id, ...args]);
List<Map<String, Object>> _convert(
  WordZoteroCitingSession session,
  List<String> ids, [
  int noteType = 0,
]) =>
    (_call(session, 'Document.convertPlaceholdersToFields', [
              ids,
              noteType,
              'Http',
            ])!
            as List<Object?>)
        .cast<Map<String, Object>>();
List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http'])! as List<Object?>)
        .cast<Map<String, Object>>();

ZoteroCitation _citation(String id, String text) => ZoteroCitation(
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
void _set(
  WordZoteroCitingSession session,
  Map<String, Object> field,
  String id,
  String html,
) {
  _call(session, 'Field.setCode', [
    field['id'],
    'ITEM CSL_CITATION ${jsonEncode(_citation(id, html).toJson())}',
  ]);
  _call(session, 'Field.setText', [field['id'], html, true]);
}

void _finish(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

void _nativeStart(
  WordZoteroCitingSession session,
  String html, [
  int type = 0,
]) {
  final temp =
      _call(session, 'Document.insertField', ['Http', type])!
          as Map<String, Object>;
  _call(session, 'Field.delete', [temp['id']]);
  _call(session, 'Document.insertText', [html]);
}

String _snapshot(WmlDocument document) => jsonEncode(<String, Object?>{
  'paragraphs': [for (final p in document.paragraphs) p.text],
  'footnotes': [for (final n in document.footnotes) n.text],
  'endnotes': [for (final n in document.endnotes) n.text],
  'fields': [
    for (final f in WordZotero.fields(document)) [f.instruction, f.cachedText],
  ],
  'preferences': WordZoteroDocumentData.read(document),
});

void main() {
  test(
    'rich paragraphs, empty paragraphs, soft breaks, and hyperlinks survive',
    () {
      final note = WordZoteroNoteText.fromHtml(
        '<html><body><div data-schema-version="9"><p><b>Bold</b> &amp; '
        '<i>italic</i><br>next</p><p></p>'
        '<p><a href="https://example.org/?a=1&amp;b=2"><u>linked</u> text</a> $_one</p>'
        '</div></body></html>',
      );
      expect(note.paragraphs.map((p) => p.text), [
        'Bold & italic\nnext',
        '',
        'linked text (Old 1)',
      ]);
      final first = note.paragraphs.first.inlines.whereType<WmlRun>();
      expect(first.first.properties.bold, isTrue);
      expect(
        first.any((r) => r.text.contains('italic') && r.properties.italic),
        isTrue,
      );
      final linked = note.paragraphs.last.inlines
          .whereType<WmlRun>()
          .where((r) => r.hyperlink != null)
          .toList();
      expect(linked.map((r) => r.text).join(), 'linked text');
      expect(linked.first.hyperlink!.url, 'https://example.org/?a=1&b=2');
      expect(linked.first.properties.underline, WmlUnderline.single);
      final placeholder = note.placeholders['ABC123']!;
      expect(placeholder.paragraphIndex, 2);
      expect(
        note.paragraphs[2].text.substring(placeholder.start, placeholder.end),
        '(Old 1)',
      );
    },
  );

  test(
    'default Zotero annotation export keeps heading quote comment and active citation',
    () {
      // Shape from pinned notes.js:getExportableNote, editorInstance.js:
      // serializeAnnotations and defaults/preferences/zotero.js noteTemplates.
      final document = WmlDocument.empty(text: 'BeforeAfter');
      final session = _session(document, offset: 6);
      _nativeStart(
        session,
        '<html><body><div data-schema-version="9" '
        'data-citation-items="%5B%5D"><h1>Annotations<br/>(2026-11-18)</h1>'
        '<p><span class="highlight" data-annotation="%7B%22pageLabel%22%3A%224%22%7D">'
        '&#8220;A <i>quoted</i> passage&#8221;</span> $_one My comment</p>'
        '</div></body></html>',
      );
      _set(
        session,
        _convert(session, ['ABC123']).single,
        'quote',
        '(Author 2026, p. 4)',
      );
      _finish(session);
      expect(document.paragraphs.map((p) => p.text), [
        'Before',
        'Annotations\n(2026-11-18)',
        '“A quoted passage” (Author 2026, p. 4) My comment',
        'After',
      ]);
      expect(document.paragraphs.elementAt(1).properties.headingLevel, 1);
      expect(document.paragraphs.elementAt(1).properties.styleId, 'Heading1');
      expect(document.paragraphs.first.properties.headingLevel, isNull);
      expect(document.paragraphs.last.properties.headingLevel, isNull);
      expect(WordZotero.fields(document).single.citation!.citationId, 'quote');
      expect(session.caretAfter!.paragraph.text, contains('My comment'));
      expect(
        session.caretAfter!.offset,
        session.caretAfter!.paragraph.text.length,
      );
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(reopened.paragraphs.elementAt(1).properties.headingLevel, 1);
      expect(WordZotero.fields(reopened).single.citation!.citationId, 'quote');
      expect(
        reopened.paragraphs
            .elementAt(2)
            .inlines
            .whereType<WmlRun>()
            .any((r) => r.text.contains('quoted') && r.properties.italic),
        isTrue,
      );
    },
  );

  test(
    'custom heading styles retain structural level and explicit character resets',
    () {
      final document = WmlDocument.empty(text: '');
      document.styles.add(
        const WmlStyle(
          id: 'Heading2',
          name: 'Custom heading',
          nameAr: 'Custom',
          bold: true,
          italic: true,
          fontSizePoints: 19,
        ),
      );
      final session = _session(document);
      _nativeStart(
        session,
        '<h2><span style="font-weight:normal;font-style:normal">Plain</span> '
        '<b>Strong</b></h2><p>Body</p>',
      );
      _finish(session);
      final heading = document.paragraphs.first;
      expect(heading.properties.headingLevel, 2);
      expect(heading.properties.styleId, 'Heading2');
      final runs = heading.inlines.whereType<WmlRun>();
      expect(runs.first.properties.bold, isFalse);
      expect(runs.first.properties.italic, isFalse);
      expect(runs.first.properties.fontSizeHalfPoints, 38);
      expect(runs.last.properties.bold, isTrue);
      expect(document.paragraphs.last.text, 'Body');
      expect(document.paragraphs.last.properties.headingLevel, isNull);
    },
  );

  test('existing ordinary notes count around inserted citation notes', () {
    final document = WmlDocument.empty(text: 'Start End');
    final p = document.paragraphs.first;
    final earlier = WordNotes.insert(
      document,
      p,
      endnote: false,
      text: 'Earlier',
    );
    final reference = p.inlines.removeLast();
    p.inlines.insert(0, reference);
    final later = WordNotes.insert(document, p, endnote: false, text: 'Later');
    final session = _session(document, offset: 6);
    _nativeStart(session, '<p>$_one $_two</p>', 1);
    final converted = _convert(session, ['DEF456', 'ABC123'], 1);
    expect(converted.map((f) => f['noteIndex']), [3, 2]);
    _set(session, converted.first, 'second', 'Second');
    _set(session, converted.last, 'first', 'First');
    _finish(session);
    expect(earlier.text, 'Earlier');
    expect(later.text, 'Later');
    final reopened = _session(document);
    expect(_fields(reopened).map((f) => f['noteIndex']), [2, 3]);
  });

  for (final originalType in [1, 2]) {
    test(
      'inserted notes precede converted type $originalType note at the same anchor',
      () {
        final document = WmlDocument.empty(text: 'After');
        final paragraph = document.paragraphs.first;
        final existing = WordNotes.insert(
          document,
          paragraph,
          endnote: originalType == 2,
        );
        final reference = paragraph.inlines.removeLast();
        paragraph.inlines.insert(0, reference);
        WordZotero.insertCitation(
          existing.paragraphs.single,
          _citation('old', 'Old citation'),
          index: 0,
        );
        final before = _snapshot(document);
        final session = _session(document);
        final oldField = _fields(session).single;
        final destinationType = originalType == 1 ? 2 : 1;
        _nativeStart(session, '<p>$_one</p><p>$_two</p>', destinationType);
        _call(session, 'Document.convert', [
          [oldField['id']],
          'Http',
          [destinationType],
        ]);
        final inserted = _convert(session, [
          'DEF456',
          'ABC123',
        ], destinationType);
        expect(inserted.map((field) => field['noteIndex']), [2, 1]);
        _set(session, inserted.first, 'second', 'Second citation');
        _set(session, inserted.last, 'first', 'First citation');
        final staged = _fields(session);
        expect(staged.map((field) => field['text']), [
          'First citation',
          'Second citation',
          'Old citation',
        ]);
        expect(staged.map((field) => field['noteIndex']), [1, 2, 3]);
        expect(_snapshot(document), before);
        _finish(session);
        final reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        for (final result in [document, reopened]) {
          final fields = _fields(_session(result));
          expect(fields.map((field) => field['text']), [
            'First citation',
            'Second citation',
            'Old citation',
          ]);
          expect(fields.map((field) => field['noteIndex']), [1, 2, 3]);
          expect(
            originalType == 1 ? result.footnotes : result.endnotes,
            isEmpty,
          );
        }
      },
    );
  }

  test(
    'existing bibliography updates in same transaction as inserted note citations',
    () {
      final p = WmlParagraph(inlines: [WmlRun(text: 'Body')]);
      final bibliography = WordZotero.nativeBibliographyParagraphs(
        instruction:
            'ADDIN ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY',
        text: 'Old reference',
      );
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [p, ...bibliography]),
        ],
      );
      final session = _session(document, offset: 4);
      final bib = _fields(session).single;
      _nativeStart(session, '<p>$_one</p>');
      _set(
        session,
        _convert(session, ['ABC123']).single,
        'new-source',
        '(New source)',
      );
      _call(session, 'Field.setText', [
        bib['id'],
        '<p>Old reference</p><p>New reference</p>',
        true,
      ]);
      _finish(session);
      final fields = WordZotero.fields(document);
      expect(fields.first.citation!.citationId, 'new-source');
      expect(fields.last.kind, ZoteroFieldKind.bibliography);
      expect(fields.last.paragraphs.map((p) => p.text), [
        'Old reference',
        'New reference',
      ]);
    },
  );

  for (final type in [0, 1, 2]) {
    test('native note type $type preserves citation order and DOCX fields', () {
      final document = WmlDocument.empty(text: 'BeforeAfter');
      final before = _snapshot(document);
      final session = _session(document, offset: 6);
      _nativeStart(
        session,
        '<p>Quote $_one middle $_two</p><p>Conclusion</p>',
        type,
      );
      final converted = _convert(session, ['DEF456', 'ABC123'], type);
      expect(converted.map((f) => f['text']), ['(Old 2)', '(Old 1)']);
      expect(converted.map((f) => f['noteIndex']), type == 0 ? [0, 0] : [2, 1]);
      _set(session, converted[0], 'second', '<i>Second</i> citation');
      _set(session, converted[1], 'first', '<b>First</b> citation');
      expect(_fields(session).map((f) => f['id']), [
        converted[1]['id'],
        converted[0]['id'],
      ]);
      expect(_snapshot(document), before);
      _finish(session);
      expect(document.paragraphs.first.text, startsWith('BeforeQuote '));
      expect(document.paragraphs.last.text, 'ConclusionAfter');
      expect(session.caretAfter!.offset, 'Conclusion'.length);
      if (type == 0) {
        expect(
          document.paragraphs.first.text,
          'BeforeQuote First citation middle Second citation',
        );
      } else {
        final notes = type == 1 ? document.footnotes : document.endnotes;
        expect(notes.map((n) => n.text).toSet(), {
          'First citation',
          'Second citation',
        });
        final reread = _session(document);
        expect(_fields(reread).map((f) => f['text']), [
          'First citation',
          'Second citation',
        ]);
        expect(_fields(reread).map((f) => f['noteIndex']), [1, 2]);
      }
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final citations = WordZotero.fields(
        reopened,
      ).map((f) => f.citation!.citationId).toSet();
      expect(citations, {'first', 'second'});
      expect(WordZotero.fields(reopened).every((f) => f.canEdit), isTrue);
    });
  }

  test(
    'plain note without citations is staged and inserted at the body caret',
    () {
      final document = WmlDocument.empty(text: 'AB');
      final session = _session(document, offset: 1);
      _nativeStart(session, '<p><b>note</b></p>');
      expect(document.paragraphs.single.text, 'AB');
      expect(session.hasInsertedNoteText, isTrue);
      expect(session.hasChanges, isTrue);
      _finish(session);
      expect(document.paragraphs.single.text, 'AnoteB');
      expect(WordZotero.fields(document), isEmpty);
      expect(session.caretAfter!.offset, 5);
    },
  );

  test('cancelled TEMP field does not count as an inserted research note', () {
    final document = WmlDocument.empty(text: 'unchanged');
    final session = _session(document);
    final temp =
        _call(session, 'Document.insertField', ['Http', 0])!
            as Map<String, Object>;
    _call(session, 'Field.delete', [temp['id']]);
    _call(session, 'Document.complete');
    expect(session.hasInsertedNoteText, isFalse);
    expect(session.hasChanges, isFalse);
    expect(document.paragraphs.single.text, 'unchanged');
  });

  test(
    'uncited heading note replaces an empty prefix without extra blank paragraph',
    () {
      final document = WmlDocument.empty(text: '');
      final session = _session(document);
      _nativeStart(session, '<h2>Research</h2><p>Text</p>');
      _finish(session);
      expect(document.paragraphs.map((p) => p.text), ['Research', 'Text']);
      expect(document.paragraphs.first.properties.headingLevel, 2);
    },
  );

  test(
    'existing fields before and after insertion update without shifting note caret',
    () {
      final p = WmlParagraph(inlines: [WmlRun(text: ' / ')]);
      WordZotero.insertCitation(p, _citation('left', 'L'), index: 0);
      WordZotero.insertCitation(
        p,
        _citation('right', 'R'),
        index: p.text.length,
      );
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [p]),
        ],
      );
      final session = _session(document, offset: 3);
      final original = _fields(session);
      _nativeStart(session, '<p>$_one</p>');
      final field = _convert(session, ['ABC123']).single;
      _set(session, field, 'new', 'NEW');
      _set(session, original.first, 'left', 'LEFT-LONG');
      _set(session, original.last, 'right', 'RIGHT-LONG');
      _finish(session);
      expect(p.text, 'LEFT-LONG /NEW RIGHT-LONG');
      expect(session.caretAfter!.offset, 'LEFT-LONG /NEW'.length);
      expect(WordZotero.fields(document).map((f) => f.citation!.citationId), [
        'left',
        'new',
        'right',
      ]);
    },
  );

  test(
    'note citations can be explicitly unlinked or deleted before completion',
    () {
      final document = WmlDocument.empty();
      final session = _session(document);
      _nativeStart(session, '<p>$_one + $_two</p>');
      final fields = _convert(session, ['DEF456', 'ABC123']);
      _set(session, fields[0], 'second', 'Second');
      _set(session, fields[1], 'first', 'First');
      _call(session, 'Field.delete', [fields[0]['id']]);
      _call(session, 'Field.removeCode', [fields[1]['id']]);
      _finish(session);
      expect(document.paragraphs.single.text, 'First + ');
      expect(WordZotero.fields(document), isEmpty);
    },
  );

  for (final ids in <List<String>>[
    [],
    ['ABC123'],
    ['ABC123', 'ABC123'],
    ['ABC123', 'UNKNOWN'],
  ]) {
    test(
      'incomplete repeated or unknown placeholder request $ids is atomic',
      () {
        final document = WmlDocument.empty(text: 'Original');
        final session = _session(document);
        final before = _snapshot(document);
        _nativeStart(session, '<p>$_one $_two</p>');
        expect(() => _convert(session, ids), throwsFormatException);
        expect(
          () => _call(session, 'Document.complete'),
          throwsFormatException,
        );
        expect(_snapshot(document), before);
      },
    );
  }

  test('unconverted and TEMP placeholders cannot complete', () {
    final document = WmlDocument.empty(text: 'Original');
    final before = _snapshot(document);
    final session = _session(document);
    _nativeStart(session, '<p>$_one</p>');
    expect(() => _call(session, 'Document.complete'), throwsFormatException);
    _convert(session, ['ABC123']);
    expect(
      () => _call(session, 'Document.complete'),
      throwsA(isA<Exception>()),
    );
    expect(_snapshot(document), before);
  });

  test('repeat conversion and bibliography placeholder type are rejected', () {
    final document = WmlDocument.empty(text: 'Original');
    final session = _session(document);
    _nativeStart(session, '<p>$_one</p>');
    final field = _convert(session, ['ABC123']).single;
    expect(() => _convert(session, ['ABC123']), throwsFormatException);
    expect(
      () => _call(session, 'Field.setCode', [
        field['id'],
        'BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY',
      ]),
      throwsFormatException,
    );
    expect(document.paragraphs.single.text, 'Original');
  });

  test('stale body text refuses applying a complete research note', () {
    final document = WmlDocument.empty(text: 'Original');
    final session = _session(document);
    _nativeStart(session, '<p>Note</p>');
    _call(session, 'Document.complete');
    document.paragraphs.first.inlines.add(WmlRun(text: ' changed'));
    expect(session.apply, throwsStateError);
    expect(document.paragraphs.single.text, 'Original changed');
  });

  test(
    'existing footnote and existing citation do not advertise text insertion',
    () {
      final document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.first,
        endnote: false,
        text: 'Note',
      );
      final inNote = _session(document, paragraph: note.paragraphs.single);
      expect(inNote.canInsertNoteText, isFalse);
      expect(inNote.assertCanInsertNoteText, throwsUnsupportedError);
      WordZotero.insertCitation(
        document.paragraphs.first,
        _citation('field', 'Citation'),
        index: 0,
      );
      final inField = _session(document, offset: 1);
      expect(inField.canInsertNoteText, isFalse);
      expect(
        () => _call(inField, 'Document.insertText', ['<p>New</p>']),
        throwsUnsupportedError,
      );
    },
  );

  for (final html in [
    '<p>$_one $_one</p>',
    '<p><a href="https://www.zotero.org/?ABC123"></a></p>',
    '<a href="https://www.zotero.org/?ABC123"><p>Cross</p><p>paragraphs</p></a>',
    '<p><a href="https://www.zotero.org/?ABC123#bad">Bad</a></p>',
    '<p><a href="javascript:alert(1)">Bad</a></p>',
    '<p><img src="https://example.org/image.png"/></p>',
    '<p><span data-citation="broken">Unconverted</span></p>',
    '<table><tr><td>Layout</td></tr></table>',
    '<p><span style="color:red">Color</span></p>',
    '<p><a href="https://example.org" title="tooltip">Extra attributes</a></p>',
    '<p>\uE0000\uE001</p>',
    '<p>Unclosed',
  ]) {
    test('unsupported or malformed note is refused before edits: $html', () {
      final document = WmlDocument.empty(text: 'Keep');
      final session = _session(document);
      expect(
        () => _nativeStart(session, html),
        throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())),
      );
      expect(document.paragraphs.single.text, 'Keep');
      expect(session.hasInsertedNoteText, isFalse);
    });
  }
}
