import 'dart:convert';

import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/model/word_zotero_note.dart';
import 'package:test/test.dart';

String _table(String content) => '<table><tr><td>$content</td></tr></table>';

String _nested(int levels) {
  var html = '<p>Deep</p>';
  for (var level = 0; level < levels; level++) {
    html = _table(html);
  }
  return html;
}

String _citation(String id, String text) =>
    '<a href="https://www.zotero.org/?$id">$text</a>';

List<WmlTable> _tables(WordZoteroNoteText note) =>
    WordTree.descendants(note.blocks).whereType<WmlTable>().toList();

void _expectNativeIndexes(WordZoteroNoteText note) {
  final native = WordTree.paragraphs(note.blocks).toList();
  expect(native.length, note.paragraphs.length);
  for (var index = 0; index < native.length; index++) {
    expect(native[index], same(note.paragraphs[index]));
  }
  expect(note.plainText, isNot(contains(RegExp('[\uE000-\uE002]'))));
}

void main() {
  test('nested cell ownership restores outer text and sibling cells', () {
    final note = WordZoteroNoteText.fromHtml(
      '<p>Body before</p><table><tr><td>Outer before<div>'
      '<table><tbody><tr><td>Middle before'
      '${_table('<p>Deep ${_citation('DEEP1', '(deep)')}</p>')}'
      'Middle after</td><td>Inner sibling</td></tr></tbody></table>'
      '</div>Outer after</td><td>Outer sibling</td></tr></table>'
      '<p>Body after</p>',
    );
    expect(note.paragraphs.map((p) => p.text), [
      'Body before',
      'Outer before',
      'Middle before',
      'Deep (deep)',
      'Middle after',
      'Inner sibling',
      'Outer after',
      'Outer sibling',
      'Body after',
    ]);
    final tables = _tables(note);
    expect(tables, hasLength(3));
    final outerCell = tables[0].rows.single.cells.first;
    final middleCell = tables[1].rows.single.cells.first;
    expect(outerCell.blocks[1], same(tables[1]));
    expect(middleCell.blocks[1], same(tables[2]));
    expect(outerCell.blocks.last, same(note.paragraphs[6]));
    expect(note.blocks, hasLength(3));
    final placeholder = note.placeholders['DEEP1']!;
    expect(placeholder.paragraphIndex, 3);
    expect(
      note.paragraphs[placeholder.paragraphIndex].text.substring(
        placeholder.start,
        placeholder.end,
      ),
      '(deep)',
    );
    _expectNativeIndexes(note);
  });

  test(
    'cell ending in a nested table owns its tail before later citations',
    () {
      final note = WordZoteroNoteText.fromHtml(
        '${_table(_table(_citation('INNER1', '(inner)')))}'
        '<p>After ${_citation('AFTER1', '(after)')}</p>',
      );
      final outer = note.blocks.first as WmlTable;
      final outerCell = outer.rows.single.cells.single;
      expect(outerCell.blocks, hasLength(2));
      expect(outerCell.blocks.first, isA<WmlTable>());
      expect(outerCell.blocks.last, isA<WmlParagraph>());
      expect((outerCell.blocks.last as WmlParagraph).text, isEmpty);
      expect(note.paragraphs.map((p) => p.text), [
        '(inner)',
        '',
        'After (after)',
      ]);
      expect(note.placeholders['INNER1']!.paragraphIndex, 0);
      expect(note.placeholders['AFTER1']!.paragraphIndex, 2);
      _expectNativeIndexes(note);

      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(
          WmlDocument(sections: [WmlSection(blocks: note.blocks)]),
        ),
      );
      expect(
        reopened.paragraphs.map((p) => p.text),
        note.paragraphs.map((p) => p.text),
      );
      final cell = (reopened.sections.single.blocks.first as WmlTable)
          .rows
          .single
          .cells
          .single;
      expect(cell.blocks.last, isA<WmlParagraph>());
      expect(cell.blocks.whereType<WmlTable>(), hasLength(1));
    },
  );

  test(
    'inner and outer merges keep widths rich content and indexes separate',
    () {
      final png = image.encodePng(image.Image(width: 4, height: 2));
      final note = WordZoteroNoteText.fromHtml(
        '<table><tbody><tr>'
        '<td rowspan="2" colspan="2" data-colwidth="240,120" '
        'style="background-color:#aabbcc"><p>Outer ${_citation('OUTER1', '(outer)')}</p>'
        '<table><tbody><tr>'
        '<th colspan="2" data-colwidth="80,160"><h2>Inner heading</h2></th>'
        '</tr><tr><td rowspan="2" data-colwidth="80">'
        '<ol start="5"><li>First ${_citation('INNER1', '(inner)')}</li>'
        '<li><b>Second</b></li></ol></td>'
        '<td data-colwidth="160"><p><a href="https://example.org/figure">'
        '<img src="data:image/png;base64,${base64Encode(png)}" width="24" '
        'alt="Nested image"></a></p></td></tr>'
        '<tr><td data-colwidth="160"><p>Inner bottom</p></td></tr>'
        '</tbody></table></td>'
        '<td data-colwidth="80"><p>Outer right</p></td></tr>'
        '<tr><td data-colwidth="80"><p>Outer bottom</p></td></tr>'
        '</tbody></table><p>After ${_citation('AFTER1', '(after)')}</p>',
      );
      final tables = _tables(note);
      expect(tables, hasLength(2));
      expect(tables.first.grid, [180, 90, 60]);
      expect(tables.last.grid, [60, 120]);
      expect(tables.first.rows.first.cells.first.gridSpan, 2);
      expect(tables.first.rows.first.cells.first.vMerge, WmlVMerge.restart);
      expect(tables.first.rows.last.cells.first.vMerge, WmlVMerge.cont);
      expect(tables.last.rows[1].cells.first.vMerge, WmlVMerge.restart);
      expect(tables.last.rows[2].cells.first.vMerge, WmlVMerge.cont);
      expect(note.paragraphs.map((p) => p.text), [
        'Outer (outer)',
        'Inner heading',
        'First (inner)',
        'Second',
        '\uFFFC',
        '',
        'Inner bottom',
        '',
        'Outer right',
        '',
        'Outer bottom',
        'After (after)',
      ]);
      expect(note.paragraphs[1].properties.headingLevel, 2);
      expect(
        note.paragraphs[3].inlines.whereType<WmlRun>().single.properties.bold,
        isTrue,
      );
      final picture = note.paragraphs[4].inlines.whereType<WmlRun>().single;
      expect(picture.hyperlink!.url, 'https://example.org/figure');
      expect(picture.inlineVisual!.visual.imageBytes, png);
      expect(
        note.listItems.entries.map(
          (entry) => (
            note.paragraphs[entry.key].text,
            entry.value.start,
            entry.value.index,
          ),
        ),
        [('First (inner)', 5, 0), ('Second', 5, 1)],
      );
      expect(note.placeholders.values.map((p) => p.paragraphIndex), [0, 2, 11]);
      _expectNativeIndexes(note);
    },
  );

  test('eight table levels preserve every cell tail; nine are refused', () {
    final note = WordZoteroNoteText.fromHtml(_nested(8));
    expect(_tables(note), hasLength(8));
    expect(note.paragraphs, hasLength(8));
    expect(note.paragraphs.first.text, 'Deep');
    expect(note.paragraphs.skip(1).every((p) => p.text.isEmpty), isTrue);
    _expectNativeIndexes(note);
    expect(
      () => WordZoteroNoteText.fromHtml(_nested(9)),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('eight levels'),
        ),
      ),
    );
  });

  test('the global table count includes nested siblings', () {
    final full = _table(List.filled(63, _table('Cell')).join());
    final note = WordZoteroNoteText.fromHtml(full);
    expect(_tables(note), hasLength(64));
    expect(note.paragraphs, hasLength(64));
    expect(
      () => WordZoteroNoteText.fromHtml(
        _table(List.filled(64, _table('Cell')).join()),
      ),
      throwsFormatException,
    );
    _expectNativeIndexes(note);
  });

  test('nested merge continuations share one native cell budget', () {
    final tall =
        '<table><tbody><tr>'
        '${List.filled(16, '<td rowspan="255">Origin</td>').join()}'
        '</tr>${List.filled(254, '<tr/>').join()}</tbody></table>';
    String short(int columns) =>
        '<table><tr>${List.filled(columns, '<td>Small</td>').join()}</tr></table>';
    final note = WordZoteroNoteText.fromHtml(_table('$tall${short(15)}'));
    expect(
      _tables(note).expand((t) => t.rows).expand((r) => r.cells),
      hasLength(4096),
    );
    expect(note.paragraphs, hasLength(4096));
    _expectNativeIndexes(note);
    expect(
      () => WordZoteroNoteText.fromHtml(_table('$tall${short(16)}')),
      throwsFormatException,
    );
  });

  test('generated cell tails count toward the paragraph limit', () {
    String payload(int ordinary) =>
        '${List.filled(ordinary, '<p></p>').join()}${_nested(2)}';
    final note = WordZoteroNoteText.fromHtml(payload(9998));
    expect(note.paragraphs, hasLength(10000));
    _expectNativeIndexes(note);
    expect(
      () => WordZoteroNoteText.fromHtml(payload(9999)),
      throwsFormatException,
    );
  });

  for (final (name, invalid) in <(String, String)>[
    ('paragraph', '<p>${_table('Invalid')}</p>'),
    ('inline', '<span>${_table('Invalid')}</span>'),
    ('hyperlink', '<a href="https://example.org">${_table('Invalid')}</a>'),
    ('list item', '<ul><li>${_table('Invalid')}</li></ul>'),
    ('wrapped list item', '<ol><li><div>${_table('Invalid')}</div></li></ol>'),
    ('table row', '<table><tr>${_table('Invalid')}</tr></table>'),
    ('table body', '<table><tbody>${_table('Invalid')}</tbody></table>'),
    ('header group', '<table><thead><tr><td>Invalid</td></tr></thead></table>'),
    ('caption', '<table><caption>Invalid</caption><tr><td>A</td></tr></table>'),
    (
      'custom table style',
      '<table style="width:100%"><tr><td>A</td></tr></table>',
    ),
    (
      'unequal inner rows',
      '<table><tr><td>A</td><td>B</td></tr><tr><td>C</td></tr></table>',
    ),
    (
      'inner rowspan crossing groups',
      '<table><tbody><tr><td rowspan="2">A</td></tr></tbody><tbody><tr/></tbody></table>',
    ),
  ]) {
    test('nested $name remains unsupported', () {
      expect(
        () => WordZoteroNoteText.fromHtml(_table(invalid)),
        throwsUnsupportedError,
      );
    });
  }

  test('malformed inner structure never produces a partial fragment', () {
    expect(
      () => WordZoteroNoteText.fromHtml(
        '<p>Before</p><table><tr><td>'
        '<table><tr><td>Inner</tr></td></table>'
        '</td></tr></table>',
      ),
      throwsFormatException,
    );
  });
}
