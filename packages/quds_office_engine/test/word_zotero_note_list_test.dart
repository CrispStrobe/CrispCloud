import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/model/word_zotero_note.dart';
import 'package:test/test.dart';

const _id = 'note-lists';
const _one = '<a href="https://www.zotero.org/?ABC123">(First)</a>';
const _two = '<a href="https://www.zotero.org/?DEF456">(Second)</a>';

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, [_id, ...arguments]);

WordZoteroCitingSession _start(
  WmlDocument document,
  String html, {
  int offset = 0,
  WmlParagraph? paragraph,
}) {
  final session = WordZoteroCitingSession(
    document: document,
    documentId: _id,
    insertionParagraph: paragraph ?? document.paragraphs.first,
    insertionOffset: offset,
  );
  _call(session, 'Document.insertText', [html]);
  return session;
}

void _complete(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http'])! as List<Object?>)
        .cast<Map<String, Object>>();

void _cite(WordZoteroCitingSession session, int noteType) {
  // Zotero sends placeholders in reverse reading order.
  final fields =
      (_call(session, 'Document.convertPlaceholdersToFields', [
                ['DEF456', 'ABC123'],
                noteType,
                'Http',
              ])!
              as List<Object?>)
          .cast<Map<String, Object>>();
  for (final (index, field) in fields.indexed) {
    final name = index == 0 ? 'Second' : 'First';
    final citation = ZoteroCitation(
      citationId: name,
      plainCitation: '($name)',
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: <String, Object?>{
            'id': name,
            'type': 'book',
            'title': name,
          },
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
        ),
      ],
    );
    _call(session, 'Field.setCode', [
      field['id'],
      'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
    ]);
    _call(session, 'Field.setText', [field['id'], '<i>($name)</i>', true]);
  }
}

void main() {
  test(
    'flat lists preserve rich items, empty items, breaks and active links',
    () {
      final note = WordZoteroNoteText.fromHtml(
        '<p>Intro</p><ul><li><p><b>Strong</b><br/>line $_one</p></li>'
        '<li></li><li><a href="https://example.org">Link</a></li></ul>'
        '<ol start="4"><li>Four</li><li><p>Five</p></li></ol><p>End</p>',
      );
      expect(note.paragraphs.map((paragraph) => paragraph.text), [
        'Intro',
        'Strong\nline (First)',
        '',
        'Link',
        'Four',
        'Five',
        'End',
      ]);
      expect(note.listItems.keys, [1, 2, 3, 4, 5]);
      expect(note.listItems.values.map((item) => item.numbered), [
        false,
        false,
        false,
        true,
        true,
      ]);
      expect(note.listItems[1]!.listId, note.listItems[3]!.listId);
      expect(note.listItems[3]!.listId, isNot(note.listItems[4]!.listId));
      expect(note.listItems[4]!.start, 4);
      expect(note.listItems[5]!.index, 1);
      final first = note.paragraphs[1].inlines.whereType<WmlRun>();
      expect(first.first.properties.bold, isTrue);
      expect(
        note.paragraphs[3].inlines.whereType<WmlRun>().single.hyperlink!.url,
        'https://example.org',
      );
      final placeholder = note.placeholders['ABC123']!;
      expect(placeholder.paragraphIndex, 1);
      expect(
        note.paragraphs[1].text.substring(placeholder.start, placeholder.end),
        '(First)',
      );
    },
  );

  test('independent lists retain boundaries, start and surrounding prose', () {
    final document = WmlDocument.empty(text: 'BeforeAfter');
    document.paragraphs.single.properties.styleId = 'BodyText';
    (document.paragraphs.single.inlines.single as WmlRun).properties.italic =
        true;
    final session = _start(
      document,
      '<ol start="7"><li>Seven</li><li>Eight</li></ol>'
      '<p>Between</p><ol><li>One</li></ol><ul><li>Bullet</li></ul>',
      offset: 6,
    );
    expect(document.package, isNull);
    expect(document.paragraphs.single.text, 'BeforeAfter');
    _complete(session);
    final paragraphs = document.paragraphs.toList();
    expect(paragraphs.map((paragraph) => paragraph.text), [
      'Before',
      'Seven',
      'Eight',
      'Between',
      'One',
      'Bullet',
      'After',
    ]);
    expect(paragraphs.map((paragraph) => paragraph.properties.listLabel), [
      null,
      '7. ',
      '8. ',
      null,
      '1. ',
      '• ',
      null,
    ]);
    expect(paragraphs[1].properties.numId, paragraphs[2].properties.numId);
    expect({
      paragraphs[1].properties.numId,
      paragraphs[4].properties.numId,
      paragraphs[5].properties.numId,
    }, hasLength(3));
    for (final paragraph in [paragraphs.first, paragraphs.last]) {
      expect(paragraph.properties.numId, isNull);
      expect(paragraph.properties.styleId, 'BodyText');
      expect(
        paragraph.inlines.whereType<WmlRun>().single.properties.italic,
        isTrue,
      );
    }
    expect(session.caretAfter!.paragraph, same(paragraphs[5]));
    expect(session.caretAfter!.offset, 'Bullet'.length);
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    expect(
      reopened.paragraphs.map((paragraph) => paragraph.properties.listLabel),
      [null, '7. ', '8. ', null, '1. ', '• ', null],
    );
  });

  for (final noteType in [0, 1, 2]) {
    test(
      'list citations retain active order for note type $noteType and DOCX',
      () {
        final document = WmlDocument.empty(text: 'BeforeAfter');
        final session = _start(
          document,
          '<ul><li>Item $_one</li><li><p>Item $_two</p></li></ul>',
          offset: 6,
        );
        _cite(session, noteType);
        expect(_fields(session).map((field) => field['text']), [
          '(First)',
          '(Second)',
        ]);
        expect(
          _fields(session).map((field) => field['noteIndex']),
          noteType == 0 ? [0, 0] : [1, 2],
        );
        _complete(session);
        for (final checked in [
          document,
          WordDeserializer().readBytes(WordSerializer().writeBytes(document)),
        ]) {
          expect(
            checked.paragraphs.map(
              (paragraph) => paragraph.properties.listLabel,
            ),
            [null, '• ', '• ', null],
          );
          final fields = WordZotero.fields(checked);
          expect(fields.map((field) => field.citation!.citationId).toSet(), {
            'First',
            'Second',
          });
          expect(fields.every((field) => field.canEdit), isTrue);
          if (noteType != 0) {
            expect(
              noteType == 1 ? checked.footnotes : checked.endnotes,
              hasLength(2),
            );
          }
          final refreshed = WordZoteroCitingSession(
            document: checked,
            documentId: _id,
          );
          expect(_fields(refreshed).map((field) => field['text']), [
            '(First)',
            '(Second)',
          ]);
          expect(
            _fields(refreshed).map((field) => field['noteIndex']),
            noteType == 0 ? [0, 0] : [1, 2],
          );
        }
      },
    );
  }

  test(
    'list insertion does not continue or restart surrounding document lists',
    () {
      final document = WmlDocument.empty(text: 'Existing first');
      final middle = WmlParagraph(inlines: [WmlRun(text: 'Body')]);
      final last = WmlParagraph(inlines: [WmlRun(text: 'Existing second')]);
      document.sections.single.blocks.addAll([middle, last]);
      for (final paragraph in [document.paragraphs.first, last]) {
        WordLists.applyLevel(paragraph, numbered: true, document: document);
      }
      final originalId = last.properties.numId;
      _complete(
        _start(
          document,
          '<ol start="9"><li>Nine</li><li>Ten</li></ol>',
          paragraph: middle,
        ),
      );
      final inserted = document.paragraphs
          .where(
            (paragraph) => paragraph.text == 'Nine' || paragraph.text == 'Ten',
          )
          .toList();
      expect(inserted.first.properties.numId, isNot(originalId));
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(
        reopened.paragraphs.map((paragraph) => paragraph.properties.listLabel),
        ['1. ', '9. ', '10. ', null, '2. '],
      );
    },
  );

  for (final reopenBefore in [false, true]) {
    test(
      'later ordinary numbering stays separate after research list, reopened $reopenBefore',
      () {
        var document = WmlDocument.empty(text: 'New ordinary item');
        _complete(
          _start(document, '<ol start="7"><li>Seven</li><li>Eight</li></ol>'),
        );
        if (reopenBefore) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
        WordLists.applyLevel(
          document.paragraphs.last,
          numbered: true,
          document: document,
        );
        expect(
          document.paragraphs.last.properties.numId,
          isNot(document.paragraphs.first.properties.numId),
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(
            document.paragraphs.map(
              (paragraph) => paragraph.properties.listLabel,
            ),
            ['7. ', '8. ', '1. '],
          );
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
      },
    );
  }

  for (final html in [
    '<ul><li>Outer<ul><li>Nested</li></ul></li></ul>',
    '<ol reversed="reversed"><li>Backwards</li></ol>',
    '<ol start="0"><li>Zero</li></ol>',
    '<ol start="-1"><li>Negative</li></ol>',
    '<ol start="1000000"><li>Too large</li></ol>',
    '<ol start="one"><li>Invalid</li></ol>',
    '<ol type="A"><li>Custom</li></ol>',
    '<ol><li value="2">Custom item</li></ol>',
    '<ul><li><p>First</p><p>Second</p></li></ul>',
    '<ul><li>Before<p>Paragraph</p></li></ul>',
    '<ul><li><p>Paragraph</p>After</li></ul>',
    '<ul><li><p>Paragraph</p><b>After</b></li></ul>',
    '<ul><li><div>Wrapped</div></li></ul>',
    '<ul><li><h1>Heading</h1></li></ul>',
    '<ul><p>Not an item</p></ul>',
    '<ul>Loose text<li>Item</li></ul>',
    '<ul></ul>',
    '<li>Orphan</li>',
    '<p><ul><li>Nested paragraph</li></ul></p>',
    '<ul style="list-style-type:square"><li>Custom</li></ul>',
  ]) {
    test(
      'unsupported list refuses complete insertion without package edits: $html',
      () {
        final document = WmlDocument.empty(text: 'Keep');
        expect(
          () => _start(document, html),
          throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())),
        );
        expect(document.paragraphs.single.text, 'Keep');
        expect(document.package, isNull);
        expect(WordZotero.fields(document), isEmpty);
      },
    );
  }
}
