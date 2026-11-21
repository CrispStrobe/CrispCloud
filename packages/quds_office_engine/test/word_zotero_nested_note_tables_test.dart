import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/model/word_zotero_note.dart';
import 'package:test/test.dart';

const _documentId = 'nested-research-tables';
const _first = '<a href="https://www.zotero.org/?FIRST1">(old one)</a>';
const _second = '<a href="https://www.zotero.org/?SECOND2">(old two)</a>';

String _table(String content) => '<table><tr><td>$content</td></tr></table>';
String _nested(int depth) => depth == 0 ? 'Leaf' : _table(_nested(depth - 1));

void _sameParagraphs(WordZoteroNoteText note) {
  final flattened = WordTree.paragraphs(note.blocks).toList();
  expect(flattened, hasLength(note.paragraphs.length));
  for (var index = 0; index < flattened.length; index++) {
    expect(flattened[index], same(note.paragraphs[index]));
  }
}

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, [_documentId, ...arguments]);

void _start(WordZoteroCitingSession session, String html, int type) {
  final temporary =
      _call(session, 'Document.insertField', ['Http', type])!
          as Map<String, Object>;
  _call(session, 'Field.delete', [temporary['id']]);
  _call(session, 'Document.insertText', [html]);
}

void _setField(
  WordZoteroCitingSession session,
  Map<String, Object> field,
  String id,
  String text,
) {
  final citation = ZoteroCitation(
    citationId: id,
    plainCitation: text,
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
  _call(session, 'Field.setText', [field['id'], text, true]);
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

void main() {
  test(
    'nested ownership keeps placeholders and lists aligned after trailing paragraphs',
    () {
      final note = WordZoteroNoteText.fromHtml(
        '<p>Lead</p><table><tr><td><p>Outer before</p>'
        '${_table('<ol start="3"><li>Nested $_first</li><li>More</li></ol>')}'
        '</td><td>Sibling $_second</td></tr></table><p>Tail</p>',
      );
      final outer = note.blocks[1] as WmlTable;
      final firstCell = outer.rows.single.cells.first;
      expect(firstCell.blocks, hasLength(3));
      expect(firstCell.blocks[0], isA<WmlParagraph>());
      expect(firstCell.blocks[1], isA<WmlTable>());
      expect((firstCell.blocks[2] as WmlParagraph).text, isEmpty);
      expect(note.paragraphs.map((paragraph) => paragraph.text), [
        'Lead',
        'Outer before',
        'Nested (old one)',
        'More',
        '',
        'Sibling (old two)',
        'Tail',
      ]);
      expect(note.placeholders['FIRST1']!.paragraphIndex, 2);
      expect(note.placeholders['SECOND2']!.paragraphIndex, 5);
      expect(note.listItems.keys, [2, 3]);
      expect(note.listItems.values.map((item) => item.start), [3, 3]);
      expect(note.plainText.contains(RegExp('[\uE000-\uE002]')), isFalse);
      _sameParagraphs(note);
    },
  );

  test('inner row spans and widths remain independent of the outer table', () {
    final note = WordZoteroNoteText.fromHtml(
      '<table><tr><td data-colwidth="200"><table><tbody><tr>'
      '<td rowspan="2" data-colwidth="40">Origin</td>'
      '<td data-colwidth="60">Right</td></tr>'
      '<tr><td data-colwidth="60">Bottom</td></tr>'
      '</tbody></table></td></tr></table>',
    );
    final outer = note.blocks.single as WmlTable;
    final inner = outer.rows.single.cells.single.blocks.first as WmlTable;
    expect(outer.grid, [150.0]);
    expect(inner.grid, [30.0, 45.0]);
    expect(inner.rows[0].cells[0].vMerge, WmlVMerge.restart);
    expect(inner.rows[1].cells[0].vMerge, WmlVMerge.cont);
    expect(note.paragraphs.map((paragraph) => paragraph.text), [
      'Origin',
      'Right',
      '',
      'Bottom',
      '',
    ]);
    _sameParagraphs(note);
    var document = WmlDocument(sections: [WmlSection(blocks: note.blocks)]);
    for (var round = 0; round < 3; round++) {
      document = _reopen(document);
      final current = document.sections.single.blocks.single as WmlTable;
      final nested = current.rows.single.cells.single.blocks.first as WmlTable;
      expect(current.grid, [150.0]);
      expect(nested.grid, [30.0, 45.0]);
      expect(nested.rows[1].cells.first.vMerge, WmlVMerge.cont);
      expect(
        WordTree.paragraphs([current]).map((paragraph) => paragraph.text),
        ['Origin', 'Right', '', 'Bottom', ''],
      );
    }
  });

  test('eight table levels are admitted and a ninth is refused', () {
    final note = WordZoteroNoteText.fromHtml(_nested(8));
    expect(
      WordTree.descendants(note.blocks).whereType<WmlTable>(),
      hasLength(8),
    );
    expect(note.paragraphs, hasLength(8));
    expect(note.paragraphs.first.text, 'Leaf');
    expect(
      note.paragraphs.skip(1).map((paragraph) => paragraph.text),
      everyElement(isEmpty),
    );
    _sameParagraphs(note);
    expect(
      () => WordZoteroNoteText.fromHtml(_nested(9)),
      throwsFormatException,
    );
  });

  test('the global 64-table budget includes all sibling nested tables', () {
    String siblings(int count) =>
        _table(List.generate(count, (i) => _table('Cell $i')).join());
    final note = WordZoteroNoteText.fromHtml(siblings(63));
    expect(
      WordTree.descendants(note.blocks).whereType<WmlTable>(),
      hasLength(64),
    );
    expect(note.paragraphs.last.text, isEmpty);
    _sameParagraphs(note);
    expect(
      () => WordZoteroNoteText.fromHtml(siblings(64)),
      throwsFormatException,
    );
  });

  for (final wrapper in [
    '<p>${_table('Invalid')}</p>',
    '<span>${_table('Invalid')}</span>',
    '<ul><li>${_table('Invalid')}</li></ul>',
  ]) {
    test(
      'nested tables retain the ordinary cell block placement rule: $wrapper',
      () {
        expect(
          () => WordZoteroNoteText.fromHtml(_table(wrapper)),
          throwsUnsupportedError,
        );
      },
    );
  }

  for (final type in [0, 1, 2]) {
    test(
      'nested type $type insertion stages and reopens live citation ownership',
      () {
        final document = WmlDocument.empty(text: 'Before TARGET after');
        WmlNote? note;
        var paragraph = document.paragraphs.single;
        if (type != 0) {
          note = WordNotes.insert(
            document,
            paragraph,
            endnote: type == 2,
            text: ' Before TARGET after',
          );
          paragraph = note.paragraphs.single;
          paragraph.inlines.insert(
            0,
            WmlNoteMarker(endnote: type == 2, properties: WmlRunProps()),
          );
        }
        final start = paragraph.text.indexOf('TARGET');
        final originalText = paragraph.text;
        final session = WordZoteroCitingSession(
          document: document,
          documentId: _documentId,
          insertionParagraph: paragraph,
          insertionOffset: start,
          insertionEndOffset: start + 6,
        );
        _start(
          session,
          '<table><tr><td>${_table('Inner $_first')}</td>'
          '<td>Outer $_second</td></tr></table>',
          type,
        );
        final fields =
            (_call(session, 'Document.convertPlaceholdersToFields', [
                      ['SECOND2', 'FIRST1'],
                      type,
                      'Http',
                    ])!
                    as List<Object?>)
                .cast<Map<String, Object>>();
        _setField(session, fields[0], 'outer', '(Two)');
        _setField(session, fields[1], 'inner', '(One)');
        expect(paragraph.text, originalText);
        expect(WordZotero.fields(document), isEmpty);
        _call(session, 'Document.complete');
        session.apply();
        final blocks = note?.blocks ?? document.sections.single.blocks;
        expect((blocks.last as WmlParagraph).text, ' after');
        expect(session.caretAfter!.paragraph, same(blocks.last));

        var result = document;
        for (var round = 0; round < 3; round++) {
          final currentNote = type == 0
              ? null
              : (type == 2 ? result.endnotes : result.footnotes).single;
          final currentBlocks =
              currentNote?.blocks ?? result.sections.single.blocks;
          final outer = currentBlocks.whereType<WmlTable>().single;
          final outerCell = outer.rows.single.cells.first;
          final inner = outerCell.blocks.first as WmlTable;
          expect(outerCell.blocks, hasLength(2));
          expect((outerCell.blocks.last as WmlParagraph).text, isEmpty);
          final live = WordZotero.fields(result);
          expect(live.map((field) => field.citation!.citationId), [
            'inner',
            'outer',
          ]);
          expect(live.map((field) => field.cachedText), ['(One)', '(Two)']);
          expect(live.every((field) => field.canEdit), isTrue);
          expect(
            live.first.paragraph,
            same(inner.rows.single.cells.single.blocks.single),
          );
          expect(
            live.last.paragraph,
            same(outer.rows.single.cells.last.blocks.single),
          );
          expect(result.footnotes, hasLength(type == 1 ? 1 : 0));
          expect(result.endnotes, hasLength(type == 2 ? 1 : 0));
          result = _reopen(result);
        }
      },
    );
  }

  test(
    'rejected nesting leaves the original document and insertion target intact',
    () {
      final document = WmlDocument.empty(text: 'Untouched');
      final paragraph = document.paragraphs.single;
      final session = WordZoteroCitingSession(
        document: document,
        documentId: _documentId,
        insertionParagraph: paragraph,
        insertionOffset: 0,
      );
      expect(() => _start(session, _nested(9), 0), throwsFormatException);
      expect(document.sections.single.blocks.single, same(paragraph));
      expect(paragraph.text, 'Untouched');
      expect(WordZotero.fields(document), isEmpty);
      expect(document.footnotes, isEmpty);
      expect(document.endnotes, isEmpty);
    },
  );
}
