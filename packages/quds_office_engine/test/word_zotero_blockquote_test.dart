import 'dart:convert';

import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/model/word_zotero_note.dart';
import 'package:test/test.dart';

const _documentId = 'zotero-blockquote';

String _placeholder(String id, String text) =>
    '<a href="https://www.zotero.org/?$id">$text</a>';

WordZoteroCitingSession _session(
  WmlDocument document,
  WmlParagraph paragraph, {
  int start = 0,
  WmlParagraph? endParagraph,
  int? end,
}) => WordZoteroCitingSession(
  document: document,
  documentId: _documentId,
  insertionParagraph: paragraph,
  insertionOffset: start,
  insertionEndParagraph: endParagraph,
  insertionEndOffset: end,
);

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_documentId, ...args]);

void _start(WordZoteroCitingSession session, String html, {int type = 0}) {
  final temp = _call(session, 'Document.insertField', ['Http', type]) as Map;
  _call(session, 'Field.delete', [temp['id']]);
  _call(session, 'Document.insertText', [html]);
}

void _convert(
  WordZoteroCitingSession session,
  List<String> ids, {
  int type = 0,
}) {
  final fields =
      _call(session, 'Document.convertPlaceholdersToFields', [
            ids,
            type,
            'Http',
          ])
          as List;
  for (var index = 0; index < ids.length; index++) {
    final id = ids[index];
    final field = fields[index] as Map;
    final citation = ZoteroCitation(
      citationId: id,
      plainCitation: '($id)',
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
        ),
      ],
    );
    _call(session, 'Field.setCode', [
      field['id'],
      'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
    ]);
    _call(session, 'Field.setText', [field['id'], '<i>($id)</i>', true]);
  }
}

void _finish(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

String _nested(int depth) =>
    '${List.filled(depth, '<blockquote>').join()}<p>Deep</p>'
    '${List.filled(depth, '</blockquote>').join()}';

void main() {
  test('quote scopes keep rich paragraphs and placeholder coordinates', () {
    final note = WordZoteroNoteText.fromHtml(
      '<p>Before</p><blockquote>\n<h2>Heading</h2>'
      '<p><b>Outer</b> ${_placeholder('FIRST1', '(old)')}</p>'
      '<blockquote><p><a href="https://example.org/source"><i>Nested</i></a>'
      '<br>continued</p></blockquote>'
      '<ol start="4"><li><p>Item ${_placeholder('SECOND2', '(other)')}</p>'
      '<p>Item continuation</p><ul><li>Nested item</li></ul></li></ol>'
      '<p>Outer again</p></blockquote><p>After</p>',
    );
    expect(note.paragraphs.map((p) => p.text), [
      'Before',
      'Heading',
      'Outer (old)',
      'Nested\ncontinued',
      'Item (other)',
      'Item continuation',
      'Nested item',
      'Outer again',
      'After',
    ]);
    expect(note.quoteDepths, {1: 1, 2: 1, 3: 2, 4: 1, 5: 1, 6: 1, 7: 1});
    expect(note.paragraphs[2].inlines.first, isA<WmlRun>());
    expect(
      (note.paragraphs[2].inlines.first as WmlRun).properties.bold,
      isTrue,
    );
    final linked = note.paragraphs[3].inlines.whereType<WmlRun>().first;
    expect(linked.hyperlink!.url, 'https://example.org/source');
    expect(linked.properties.italic, isTrue);
    expect(note.listItems.keys, [4, 5, 6]);
    expect(note.listItems[5]!.continuation, isTrue);
    for (final entry in {
      'FIRST1': (2, '(old)'),
      'SECOND2': (4, '(other)'),
    }.entries) {
      final placeholder = note.placeholders[entry.key]!;
      expect(placeholder.paragraphIndex, entry.value.$1);
      expect(
        note.paragraphs[placeholder.paragraphIndex].text.substring(
          placeholder.start,
          placeholder.end,
        ),
        entry.value.$2,
      );
    }
    expect(note.plainText, isNot(contains(RegExp('[\uE000-\uE002]'))));
  });

  test('empty and adjacent quotes retain boundaries without phantom prose', () {
    final note = WordZoteroNoteText.fromHtml(
      '<p>Before</p><blockquote></blockquote>'
      '<blockquote><blockquote><p></p></blockquote></blockquote>'
      '<blockquote><p>Next</p></blockquote><p>After</p>',
    );
    expect(note.paragraphs.map((p) => p.text), [
      'Before',
      '',
      '',
      'Next',
      'After',
    ]);
    expect(note.quoteDepths, {1: 1, 2: 2, 3: 1});
    expect(
      () => WordZoteroNoteText.fromHtml('<blockquote/>'),
      throwsFormatException,
    );
  });

  test('an empty quoted heading owns exactly one paragraph', () {
    for (final html in [
      '<blockquote><h2></h2></blockquote><p>After</p>',
      '<table><tr><td><blockquote><h2></h2></blockquote><p>After</p>'
          '</td></tr></table>',
    ]) {
      final note = WordZoteroNoteText.fromHtml(html);
      expect(note.paragraphs.map((p) => p.text), ['', 'After']);
      expect(note.paragraphs.first.properties.headingLevel, 2);
      expect(note.quoteDepths, {0: 1});
    }
  });

  test('quote ownership remaps after merged table continuation paragraphs', () {
    final note = WordZoteroNoteText.fromHtml(
      '<table><tr><td rowspan="2"><p>Spanning</p></td>'
      '<td>Before<blockquote><p>Quote ${_placeholder('FIRST1', '(one)')}</p>'
      '</blockquote>After</td></tr><tr><td><div><blockquote>'
      '<p>Second ${_placeholder('SECOND2', '(two)')}</p></blockquote></div>'
      '</td></tr></table><p>Tail</p>',
    );
    expect(note.paragraphs.map((p) => p.text), [
      'Spanning',
      'Before',
      'Quote (one)',
      'After',
      '',
      'Second (two)',
      'Tail',
    ]);
    expect(note.quoteDepths, {2: 1, 5: 1});
    expect(note.placeholders['FIRST1']!.paragraphIndex, 2);
    expect(note.placeholders['SECOND2']!.paragraphIndex, 5);
    final native = WordTree.paragraphs(note.blocks).toList();
    for (var index = 0; index < native.length; index++) {
      expect(note.paragraphs[index], same(native[index]));
    }
  });

  test(
    'native quote insertion composes headings and lists without changing prose',
    () {
      final document = WmlDocument.empty(text: 'BeforeAfter');
      final source = document.paragraphs.single;
      source.properties
        ..justification = WmlJustification.right
        ..indent = const WmlIndent(left: 5, right: 9, firstLine: 3)
        ..explicitIndent = true;
      document.styles.add(
        const WmlStyle(
          id: 'Heading2',
          name: 'Heading',
          nameAr: 'Heading',
          bold: true,
          italic: true,
          fontSizePoints: 19,
        ),
      );
      final session = _session(document, source, start: 6);
      _start(
        session,
        '<blockquote><h2>Quoted heading</h2><p>Outer '
        '${_placeholder('FIRST1', '(old)')}</p><blockquote><p>Inner</p>'
        '</blockquote><ol start="4"><li><p>Item</p><p>Continuation</p>'
        '<ul><li>Child ${_placeholder('SECOND2', '(old)')}</li></ul></li></ol>'
        '</blockquote>',
      );
      _convert(session, ['SECOND2', 'FIRST1']);
      expect(document.paragraphs.single, same(source));
      expect(source.text, 'BeforeAfter');
      _finish(session);
      for (final current in [document, _reopen(document)]) {
        final paragraphs = current.paragraphs.toList();
        expect(paragraphs.map((p) => p.text), [
          'Before',
          'Quoted heading',
          'Outer (FIRST1)',
          'Inner',
          'Item',
          'Continuation',
          'Child (SECOND2)',
          'After',
        ]);
        expect(paragraphs.map((p) => p.properties.indent.left), [
          5,
          18,
          18,
          36,
          36,
          36,
          54,
          5,
        ]);
        expect(paragraphs[1].properties.headingLevel, 2);
        expect(
          paragraphs[1].inlines
              .whereType<WmlRun>()
              .first
              .properties
              .fontSizeHalfPoints,
          38,
        );
        expect(paragraphs[4].properties.listLabel, '4. ');
        expect(paragraphs[4].properties.indent.hanging, 9);
        expect(paragraphs[5].properties.numId, isNull);
        expect(paragraphs[5].properties.numberingSuppressed, isTrue);
        for (final paragraph in [paragraphs.first, paragraphs.last]) {
          expect(paragraph.properties.justification, WmlJustification.right);
          expect(paragraph.properties.indent.right, 9);
          expect(paragraph.properties.indent.firstLine, 3);
        }
        final fields = WordZotero.fields(current);
        expect(fields.map((f) => f.citation!.citationId), [
          'FIRST1',
          'SECOND2',
        ]);
        expect(fields.map((f) => f.cachedText), ['(FIRST1)', '(SECOND2)']);
        expect(
          paragraphs.skip(1).take(6).every((p) => p.properties.explicitIndent),
          isTrue,
        );
      }
      expect(session.caretAfter!.paragraph.text, 'Child (SECOND2)');
    },
  );

  for (final endnote in [false, true]) {
    test(
      'quoted content retains ${endnote ? 'endnote' : 'footnote'} ownership and marker',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: ' Trailing prose',
        );
        final source = note.paragraphs.single;
        source.inlines.insert(
          0,
          WmlNoteMarker(endnote: endnote, properties: WmlRunProps()),
        );
        final session = _session(document, source, start: 1);
        _start(
          session,
          '<blockquote><p>Quote ${_placeholder('FIRST1', '(old)')}</p></blockquote>',
          type: endnote ? 2 : 1,
        );
        _convert(session, ['FIRST1'], type: endnote ? 2 : 1);
        _finish(session);
        for (final current in [document, _reopen(document)]) {
          final currentNote =
              (endnote ? current.endnotes : current.footnotes).single;
          expect(current.footnotes.length + current.endnotes.length, 1);
          expect(currentNote.paragraphs.map((p) => p.text), [
            ' Quote (FIRST1)',
            'Trailing prose',
          ]);
          expect(
            currentNote.paragraphs.first.inlines.first,
            isA<WmlNoteMarker>(),
          );
          expect(currentNote.paragraphs.first.properties.indent.left, 18);
          expect(currentNote.paragraphs.last.properties.indent.left, 0);
          expect(
            WordZotero.fields(current).single.citation!.citationId,
            'FIRST1',
          );
        }
      },
    );
  }

  test('cell-local range replacement keeps quote and untouched cell styles', () {
    final first = WmlParagraph(inlines: [WmlRun(text: 'Before remove')]);
    final last = WmlParagraph(
      inlines: [WmlRun(text: 'remove After')],
      properties: WmlParagraphProps(
        indent: const WmlIndent(left: 7, right: 11),
      ),
    );
    final sibling = WmlParagraph(inlines: [WmlRun(text: 'Sibling')]);
    final cell = WmlTableCell(blocks: [first, last]);
    final table = WmlTable(
      rows: [
        WmlTableRow(
          cells: [
            cell,
            WmlTableCell(blocks: [sibling]),
          ],
        ),
      ],
    );
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [table]),
      ],
    );
    final session = _session(
      document,
      first,
      start: 7,
      endParagraph: last,
      end: 7,
    );
    _start(
      session,
      '<blockquote><p>Replacement ${_placeholder('FIRST1', '(old)')}</p></blockquote>',
    );
    _convert(session, ['FIRST1']);
    _finish(session);
    expect(cell.blocks.whereType<WmlParagraph>().map((p) => p.text), [
      'Before ',
      'Replacement (FIRST1)',
      'After',
    ]);
    expect((cell.blocks[1] as WmlParagraph).properties.indent.left, 18);
    expect((cell.blocks.last as WmlParagraph).properties.indent.left, 7);
    expect((cell.blocks.last as WmlParagraph).properties.indent.right, 11);
    expect(table.rows.single.cells.last.blocks.single, same(sibling));
    expect(sibling.text, 'Sibling');
    expect(WordZotero.fields(_reopen(document)).single.cachedText, '(FIRST1)');
  });

  test(
    'quoted inline pictures survive citation insertion and DOCX persistence',
    () {
      final png = image.encodePng(image.Image(width: 4, height: 2));
      final document = WmlDocument.empty();
      final session = _session(document, document.paragraphs.single);
      _start(
        session,
        '<blockquote><p><a href="https://example.org/picture">'
        '<img src="data:image/png;base64,${base64Encode(png)}" width="24" alt="Quoted image"></a>'
        ' ${_placeholder('FIRST1', '(old)')}</p></blockquote>',
      );
      _convert(session, ['FIRST1']);
      _finish(session);
      for (final current in [document, _reopen(document)]) {
        final paragraph = current.paragraphs.single;
        expect(paragraph.text, '\uFFFC (FIRST1)');
        expect(paragraph.properties.indent.left, 18);
        final picture = paragraph.inlines.whereType<WmlRun>().first;
        expect(picture.inlineVisual!.visual.imageBytes, png);
        expect(picture.hyperlink!.url, 'https://example.org/picture');
      }
    },
  );

  test(
    'eight quote levels have bounded indentation and nine fail before changes',
    () {
      final document = WmlDocument.empty();
      final session = _session(document, document.paragraphs.single);
      _start(session, _nested(8));
      _finish(session);
      expect(document.paragraphs.single.text, 'Deep');
      expect(document.paragraphs.single.properties.indent.left, 144);
      expect(
        () => WordZoteroNoteText.fromHtml(_nested(9)),
        throwsFormatException,
      );
    },
  );

  final unsupported = <String>[
    '<blockquote>Inline-only</blockquote>',
    '<blockquote><b>Inline-only</b></blockquote>',
    '<p><blockquote><p>Invalid paragraph ownership</p></blockquote></p>',
    '<ul><li><p>Item</p><blockquote><p>Quote</p></blockquote></li></ul>',
    '<blockquote><table><tr><td>Table</td></tr></table></blockquote>',
    '<blockquote><div><table><tr><td>Table</td></tr></table></div></blockquote>',
    '<blockquote style="margin-left:1em"><p>Custom geometry</p></blockquote>',
    '<blockquote cite="https://example.org"><p>Citation attribute</p></blockquote>',
  ];
  for (final (index, html) in unsupported.indexed) {
    test('unsupported quote structure $index leaves the source untouched', () {
      final document = WmlDocument.empty(text: 'Keep original');
      final source = document.paragraphs.single;
      final sourceRun = source.inlines.single;
      final session = _session(document, source);
      expect(() => _start(session, html), throwsUnsupportedError);
      expect(document.paragraphs.single, same(source));
      expect(source.inlines.single, same(sourceRun));
      expect(source.text, 'Keep original');
      expect(WordZotero.fields(document), isEmpty);
      expect(() => session.apply(), throwsStateError);
    });
  }

  test(
    'unfinished quote citation and changed source cannot publish staged content',
    () {
      final document = WmlDocument.empty(text: 'Keep');
      final source = document.paragraphs.single;
      final session = _session(document, source);
      _start(
        session,
        '<blockquote><p>${_placeholder('FIRST1', '(old)')}</p></blockquote>',
      );
      expect(() => _call(session, 'Document.complete'), throwsFormatException);
      expect(source.text, 'Keep');
      _convert(session, ['FIRST1']);
      _call(session, 'Document.complete');
      source.inlines.add(WmlRun(text: ' changed'));
      expect(() => session.apply(), throwsStateError);
      expect(document.paragraphs.single.text, 'Keep changed');
      expect(WordZotero.fields(document), isEmpty);
    },
  );
}
