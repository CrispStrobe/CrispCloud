import 'dart:convert';

import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/model/word_zotero_note.dart';
import 'package:test/test.dart';

const _one = '<a href="https://www.zotero.org/?ABC123">(First)</a>';
const _two = '<a href="https://www.zotero.org/?DEF456">(Second)</a>';

String _table(String rows) => '<table><tbody>$rows</tbody></table>';

void _sameParagraphs(WordZoteroNoteText note) {
  final flattened = WordTree.paragraphs(note.blocks).toList();
  expect(flattened, hasLength(note.paragraphs.length));
  for (var index = 0; index < flattened.length; index++) {
    expect(flattened[index], same(note.paragraphs[index]));
  }
}

void main() {
  test('ordinary note blocks retain the existing paragraph identities', () {
    final note = WordZoteroNoteText.fromHtml('<p>First</p><p>Second</p>');
    expect(note.blocks, hasLength(2));
    expect(note.blocks.every((block) => block is WmlParagraph), isTrue);
    expect(note.plainText, 'First\nSecond');
    _sameParagraphs(note);
  });

  test(
    'native table cells retain row-major citation indexes and ownership',
    () {
      final note = WordZoteroNoteText.fromHtml(
        '<p>Before</p>'
        '<table><tbody><tr><th><p>Heading</p></th><th><p>Other</p></th></tr>'
        '<tr><td><p>One $_one</p><p>Tail</p></td>'
        '<td>Two $_two</td></tr></tbody></table><p>After</p>',
      );
      expect(note.blocks, hasLength(3));
      expect(note.blocks.first, same(note.paragraphs.first));
      expect(note.blocks.last, same(note.paragraphs.last));
      final table = note.blocks[1] as WmlTable;
      expect(table.rows, hasLength(2));
      expect(table.rows.map((row) => row.cells.length), [2, 2]);
      expect(note.paragraphs.map((paragraph) => paragraph.text), [
        'Before',
        'Heading',
        'Other',
        'One (First)',
        'Tail',
        'Two (Second)',
        'After',
      ]);
      expect(table.rows[1].cells[0].blocks, hasLength(2));
      expect(table.rows[1].cells[0].blocks.first, same(note.paragraphs[3]));
      for (final index in [1, 2]) {
        expect(
          note.paragraphs[index].inlines
              .whereType<WmlRun>()
              .single
              .properties
              .bold,
          isTrue,
        );
      }
      for (final (id, paragraphIndex, expected) in [
        ('ABC123', 3, '(First)'),
        ('DEF456', 5, '(Second)'),
      ]) {
        final placeholder = note.placeholders[id]!;
        expect(placeholder.paragraphIndex, paragraphIndex);
        expect(
          note.paragraphs[paragraphIndex].text.substring(
            placeholder.start,
            placeholder.end,
          ),
          expected,
        );
      }
      expect(note.plainText.contains(RegExp('[\uE000-\uE002]')), isFalse);
      _sameParagraphs(note);
    },
  );

  test('empty cells and a wholly empty table remain native structure', () {
    final note = WordZoteroNoteText.fromHtml(
      _table('<tr><td></td><td><p></p></td></tr>'),
    );
    expect(note.blocks, hasLength(1));
    final table = note.blocks.single as WmlTable;
    expect(table.rows.single.cells, hasLength(2));
    expect(note.paragraphs.map((paragraph) => paragraph.text), ['', '']);
    for (final cell in table.rows.single.cells) {
      expect(cell.blocks, hasLength(1));
      expect(cell.blocks.single, isA<WmlParagraph>());
    }
    _sameParagraphs(note);
  });

  test(
    'adjacent tables and multiple tbody groups retain source block order',
    () {
      final note = WordZoteroNoteText.fromHtml(
        '<table><tbody><tr><td>A</td></tr></tbody>'
        '<tbody><tr><td>B</td></tr></tbody></table>'
        '<table><tr><td>C</td></tr></table>',
      );
      expect(note.blocks, hasLength(2));
      expect(note.blocks.every((block) => block is WmlTable), isTrue);
      expect((note.blocks.first as WmlTable).rows, hasLength(2));
      expect(note.paragraphs.map((paragraph) => paragraph.text), [
        'A',
        'B',
        'C',
      ]);
      _sameParagraphs(note);
    },
  );

  test(
    'rich cell paragraphs, headings, pictures and ordinary links survive',
    () {
      final picture = image.encodePng(image.Image(width: 4, height: 2));
      final note = WordZoteroNoteText.fromHtml(
        _table(
          '<tr><td><h2>Title</h2><p><b>Bold</b> <i>Italic</i><br/>'
          '<a href="https://example.org/source">Link</a> $_one</p>'
          '<p><img src="data:image/png;base64,${base64Encode(picture)}" '
          'width="40" height="20" alt="Figure"></p></td><td></td></tr>',
        ),
      );
      expect(note.paragraphs.map((paragraph) => paragraph.text), [
        'Title',
        'Bold Italic\nLink (First)',
        '\uFFFC',
        '',
      ]);
      expect(note.paragraphs.first.properties.headingLevel, 2);
      final runs = note.paragraphs[1].inlines.whereType<WmlRun>();
      expect(runs.first.properties.bold, isTrue);
      expect(
        runs
            .singleWhere((run) => run.text.trim() == 'Italic')
            .properties
            .italic,
        isTrue,
      );
      expect(
        runs.singleWhere((run) => run.hyperlink != null).hyperlink!.url,
        'https://example.org/source',
      );
      final pictureRun = note.paragraphs[2].inlines.whereType<WmlRun>().single;
      expect(pictureRun.inlineVisual!.visual.imageBytes, picture);
      expect(pictureRun.inlineVisual!.visual.width, 30);
      expect(pictureRun.inlineVisual!.visual.height, 15);
      expect(note.placeholders['ABC123']!.paragraphIndex, 1);
      _sameParagraphs(note);
    },
  );

  for (final (content, expected) in [
    ('A<br/>', 'A\n'),
    ('A<br/><br/>', 'A\n\n'),
    ('<br/>', '\n'),
    ('<br/>A<br/>', '\nA\n'),
  ]) {
    for (final wrapped in [false, true]) {
      test(
        'cell soft breaks survive structural markers: $content wrapped $wrapped',
        () {
          final html = wrapped ? '<div><span>$content</span></div>' : content;
          final note = WordZoteroNoteText.fromHtml(
            _table('<tr><td>$html</td><td><p>Next $_one</p></td></tr>'),
          );
          expect(note.paragraphs.map((paragraph) => paragraph.text), [
            expected,
            'Next (First)',
          ]);
          expect(note.placeholders['ABC123']!.paragraphIndex, 1);
          expect(
            (note.blocks.single as WmlTable).rows.single.cells.first.blocks,
            hasLength(1),
          );
          _sameParagraphs(note);
        },
      );
    }
  }

  test('mixed cell and div blocks have no phantom continuation paragraphs', () {
    final note = WordZoteroNoteText.fromHtml(
      _table(
        '<tr><td>Before<br/><p>Paragraph<br/></p>After<br/></td>'
        '<td><div>Head<br/><div><p>Middle</p></div>Tail<br/></div></td></tr>',
      ),
    );
    expect(note.paragraphs.map((paragraph) => paragraph.text), [
      'Before\n',
      'Paragraph\n',
      'After\n',
      'Head\n',
      'Middle',
      'Tail\n',
    ]);
    final table = note.blocks.single as WmlTable;
    expect(table.rows.single.cells.map((cell) => cell.blocks.length), [3, 3]);
    _sameParagraphs(note);
  });

  test('header bold keeps host fonts and explicit emphasis resets', () {
    final note = WordZoteroNoteText.fromHtml(
      _table(
        '<tr><th><p>Header <span style="font-weight:normal">normal</span>'
        '</p></th><td>Body</td></tr>',
      ),
      baseProperties: WmlRunProps(
        asciiFont: 'Georgia',
        color: '336699',
        italic: true,
      ),
    );
    final header = note.paragraphs.first.inlines.whereType<WmlRun>().toList();
    expect(header.first.properties.bold, isTrue);
    expect(header.last.properties.bold, isFalse);
    expect(
      note.paragraphs
          .expand((paragraph) => paragraph.inlines)
          .whereType<WmlRun>()
          .every(
            (run) =>
                run.properties.asciiFont == 'Georgia' &&
                run.properties.color == '336699' &&
                !run.properties.italic,
          ),
      isTrue,
    );
    expect(
      note.paragraphs.last.inlines.whereType<WmlRun>().single.properties.bold,
      isFalse,
    );
  });

  test(
    'lists in separate cells keep independent starts and continuation indexes',
    () {
      final table = _table(
        '<tr><td><ol start="4"><li>First<p>Continuation</p>'
        '<ul><li>Deep $_one</li></ul></li></ol></td>'
        '<td><ol start="7"><li>Other $_two</li></ol></td></tr>',
      );
      final note = WordZoteroNoteText.fromHtml(
        '$table<ol start="2"><li>Tail</li></ol>',
      );
      expect(note.paragraphs.map((paragraph) => paragraph.text), [
        'First',
        'Continuation',
        'Deep (First)',
        'Other (Second)',
        'Tail',
      ]);
      expect(note.listItems.keys, [0, 1, 2, 3, 4]);
      expect(note.listItems.values.map((item) => item.listId), [0, 0, 1, 2, 3]);
      expect(note.listItems.values.map((item) => item.continuation), [
        false,
        true,
        false,
        false,
        false,
      ]);
      expect(note.listItems.values.map((item) => item.level), [0, 0, 1, 0, 0]);
      expect(note.listItems.values.map((item) => item.start), [4, 4, 1, 7, 2]);
      expect(note.placeholders['ABC123']!.paragraphIndex, 2);
      expect(note.placeholders['DEF456']!.paragraphIndex, 3);
      _sameParagraphs(note);
    },
  );

  test('column widths propagate consistently using CSS pixels', () {
    final note = WordZoteroNoteText.fromHtml(
      _table(
        '<tr><td data-colwidth="100">A</td><td>B</td></tr>'
        '<tr><td data-colwidth="100" colspan="1" rowspan="1">C</td>'
        '<td data-colwidth="200">D</td></tr>',
      ),
    );
    final table = note.blocks.single as WmlTable;
    expect(table.grid, [75, 150]);
    for (final row in table.rows) {
      expect(row.cells.map((cell) => cell.width), [75, 150]);
      expect(row.cells.map((cell) => cell.gridSpan), [1, 1]);
      expect(row.cells.map((cell) => cell.vMerge), [
        WmlVMerge.none,
        WmlVMerge.none,
      ]);
    }
  });

  test('unsized columns use independent 120-point defaults', () {
    final note = WordZoteroNoteText.fromHtml(
      _table('<tr><td>A</td><td>B</td></tr>'),
    );
    final table = note.blocks.single as WmlTable;
    expect(table.grid, [120, 120]);
    expect(table.rows.single.cells.map((cell) => cell.width), [120, 120]);
  });

  test('horizontal merges reconcile widths by logical column', () {
    final note = WordZoteroNoteText.fromHtml(
      _table(
        '<tr><td colspan="2" data-colwidth="100,200">Merged left</td>'
        '<td data-colwidth="120">Right</td></tr>'
        '<tr><td data-colwidth="100">Left</td>'
        '<td colspan="2" data-colwidth="200,120">Merged right</td></tr>'
        '<tr><td>A</td><td>B</td><td>C</td></tr>',
      ),
    );
    final table = note.blocks.single as WmlTable;
    expect(table.grid, [75, 150, 90]);
    expect(table.rows.map((row) => row.cells.length), [2, 2, 3]);
    expect(table.rows[0].cells.map((cell) => cell.gridSpan), [2, 1]);
    expect(table.rows[1].cells.map((cell) => cell.gridSpan), [1, 2]);
    expect(table.rows[0].cells.map((cell) => cell.width), [225, 90]);
    expect(table.rows[1].cells.map((cell) => cell.width), [75, 240]);
    expect(table.rows[2].cells.map((cell) => cell.width), [75, 150, 90]);
    expect(WordTable.supportsGridAddressing(table), isTrue);
    expect(WordTable.cellIndexAtGrid(table.rows[0], 1), 0);
    expect(WordTable.cellIndexAtGrid(table.rows[1], 2), 1);
    expect(
      table.rows.expand((row) => row.cells).map((cell) => cell.vMerge),
      everyElement(WmlVMerge.none),
    );
    _sameParagraphs(note);
  });

  for (final mergedFirst in [false, true]) {
    test(
      'zero widths remain unspecified across rows: merged first $mergedFirst',
      () {
        const merged =
            '<tr><td colspan="3" data-colwidth="0,0,400">Merged</td></tr>';
        const separate =
            '<tr><td data-colwidth="100">A</td>'
            '<td data-colwidth="0">B</td><td>C</td></tr>';
        final note = WordZoteroNoteText.fromHtml(
          _table(mergedFirst ? '$merged$separate' : '$separate$merged'),
        );
        final table = note.blocks.single as WmlTable;
        expect(table.grid, [75, 120, 300]);
        final mergedRow = table.rows[mergedFirst ? 0 : 1];
        final separateRow = table.rows[mergedFirst ? 1 : 0];
        expect(mergedRow.cells.single.width, 495);
        expect(separateRow.cells.map((cell) => cell.width), [75, 120, 300]);
        _sameParagraphs(note);
      },
    );
  }

  test('merged cells preserve source paragraphs, lists and citation indexes', () {
    final note = WordZoteroNoteText.fromHtml(
      '<p>Before</p>${_table('<tr><th colspan="2" style="background-color:#def">'
      '<p>Merged $_one</p><ol start="4"><li>List $_two</li></ol></th>'
      '<td>Right</td></tr>'
      '<tr><td>A</td><td>B</td><td>C</td></tr>')}<p>After</p>',
    );
    final table = note.blocks[1] as WmlTable;
    final merged = table.rows.first.cells.first;
    expect(merged.gridSpan, 2);
    expect(merged.width, 240);
    expect(merged.fillColor, 'DDEEFF');
    expect(merged.blocks, [same(note.paragraphs[1]), same(note.paragraphs[2])]);
    expect(note.paragraphs.map((paragraph) => paragraph.text), [
      'Before',
      'Merged (First)',
      'List (Second)',
      'Right',
      'A',
      'B',
      'C',
      'After',
    ]);
    expect(
      note.paragraphs[1].inlines.whereType<WmlRun>().first.properties.bold,
      isTrue,
    );
    expect(note.listItems.keys, [2]);
    expect(note.listItems[2]!.start, 4);
    expect(note.placeholders['ABC123']!.paragraphIndex, 1);
    expect(note.placeholders['DEF456']!.paragraphIndex, 2);
    for (final placeholder in note.placeholders.values) {
      expect(
        note.paragraphs[placeholder.paragraphIndex].text.substring(
          placeholder.start,
          placeholder.end,
        ),
        placeholder.id == 'ABC123' ? '(First)' : '(Second)',
      );
    }
    _sameParagraphs(note);
  });

  test('empty and picture-only merged cells retain their native owners', () {
    final picture = image.encodePng(image.Image(width: 4, height: 2));
    final note = WordZoteroNoteText.fromHtml(
      _table(
        '<tr><td colspan="2"></td><td>Tail</td></tr>'
        '<tr><td>A</td><td colspan="2"><p>'
        '<a href="https://example.org/figure"><img '
        'src="data:image/png;base64,${base64Encode(picture)}" '
        'width="40" height="20" alt="Merged figure"></a>'
        '</p></td></tr>',
      ),
    );
    final table = note.blocks.single as WmlTable;
    expect(note.paragraphs.map((paragraph) => paragraph.text), [
      '',
      'Tail',
      'A',
      '\uFFFC',
    ]);
    expect(
      table.rows.first.cells.first.blocks.single,
      same(note.paragraphs[0]),
    );
    expect(table.rows.last.cells.last.blocks.single, same(note.paragraphs[3]));
    final run = note.paragraphs[3].inlines.whereType<WmlRun>().single;
    expect(run.inlineVisual!.visual.imageBytes, picture);
    expect(run.inlineVisual!.visual.width, 30);
    expect(run.hyperlink!.url, 'https://example.org/figure');
    _sameParagraphs(note);
  });

  test('one cell can span the complete bounded 32-column grid', () {
    final note = WordZoteroNoteText.fromHtml(
      _table('<tr><td colspan="32">Wide</td></tr>'),
    );
    final table = note.blocks.single as WmlTable;
    expect(table.grid, List.filled(32, 120.0));
    expect(table.rows.single.cells.single.gridSpan, 32);
    expect(table.rows.single.cells.single.width, 3840);
    expect(table.rows.single.cells.single.blocks, hasLength(1));
    expect(WordTable.supportsGridAddressing(table), isTrue);
    _sameParagraphs(note);
  });

  test('explicit column-width bounds apply inside a merged width vector', () {
    final note = WordZoteroNoteText.fromHtml(
      _table('<tr><td colspan="2" data-colwidth="1,4000">Wide</td></tr>'),
    );
    final table = note.blocks.single as WmlTable;
    expect(table.grid, [0.75, 3000]);
    expect(table.rows.single.cells.single.width, 3000.75);
  });

  test('row spans create native continuations at their logical columns', () {
    final note = WordZoteroNoteText.fromHtml(
      _table(
        '<tr><td rowspan="3" colspan="2" data-colwidth="120,0" '
        'style="background-color:#def"><p>Origin</p></td>'
        '<td data-colwidth="80">Top</td>'
        '<td rowspan="2" data-colwidth="100">Outer</td></tr>'
        '<tr><td data-colwidth="80">Middle</td></tr>'
        '<tr><td colspan="2" data-colwidth="80,100">Bottom</td></tr>',
      ),
    );
    final table = note.blocks.single as WmlTable;
    expect(table.grid, [90, 120, 60, 75]);
    expect(
      table.rows.map((row) => row.cells.map((cell) => cell.gridSpan).toList()),
      [
        [2, 1, 1],
        [2, 1, 1],
        [2, 2],
      ],
    );
    expect(
      table.rows.map((row) => row.cells.map((cell) => cell.vMerge).toList()),
      [
        [WmlVMerge.restart, WmlVMerge.none, WmlVMerge.restart],
        [WmlVMerge.cont, WmlVMerge.none, WmlVMerge.cont],
        [WmlVMerge.cont, WmlVMerge.none],
      ],
    );
    expect(note.paragraphs.map((paragraph) => paragraph.text), [
      'Origin',
      'Top',
      'Outer',
      '',
      'Middle',
      '',
      '',
      'Bottom',
    ]);
    for (final row in table.rows) {
      expect(row.cells.first.width, 210);
      expect(row.cells.first.fillColor, 'DDEEFF');
    }
    expect(WordTable.supportsGridAddressing(table), isTrue);
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 2; column++) {
        expect(
          WordTable.cellAtGrid(table, row, column)!.cell,
          same(table.rows.first.cells.first),
        );
      }
    }
    expect(
      WordTable.cellAtGrid(table, 1, 3)!.cell,
      same(table.rows.first.cells.last),
    );
    _sameParagraphs(note);
  });

  test(
    'synthetic continuations preserve citation and list paragraph indexes',
    () {
      const middle = '<a href="https://www.zotero.org/?MIDDLE3">(Middle)</a>';
      final picture = image.encodePng(image.Image(width: 4, height: 2));
      final note = WordZoteroNoteText.fromHtml(
        '<p>Before $_one</p>'
        '${_table('<tr><td rowspan="2" colspan="2"><p>'
        '<img src="data:image/png;base64,${base64Encode(picture)}" '
        'alt="Origin picture"></p></td><td>Top</td></tr>'
        '<tr><td><ol start="7"><li><p>First $middle</p><p>Continued</p>'
        '<ul><li>Nested</li></ul></li><li>Next item</li></ol></td></tr>')}'
        '<p>After $_two</p>',
      );
      expect(note.paragraphs.map((paragraph) => paragraph.text), [
        'Before (First)',
        '\uFFFC',
        'Top',
        '',
        'First (Middle)',
        'Continued',
        'Nested',
        'Next item',
        'After (Second)',
      ]);
      expect(note.placeholders['ABC123']!.paragraphIndex, 0);
      expect(note.placeholders['MIDDLE3']!.paragraphIndex, 4);
      expect(note.placeholders['DEF456']!.paragraphIndex, 8);
      expect(note.listItems.keys, [4, 5, 6, 7]);
      expect(note.listItems[4]!.start, 7);
      expect(note.listItems[4]!.index, 0);
      expect(note.listItems[5]!.continuation, isTrue);
      expect(note.listItems[6]!.level, 1);
      expect(note.listItems[7]!.index, 1);
      final table = note.blocks[1] as WmlTable;
      expect(table.rows[1].cells.first.blocks.single, same(note.paragraphs[3]));
      expect(table.rows[1].cells.last.blocks.first, same(note.paragraphs[4]));
      expect(
        note.paragraphs[1].inlines
            .whereType<WmlRun>()
            .single
            .inlineVisual!
            .visual
            .imageBytes,
        picture,
      );
      _sameParagraphs(note);
    },
  );

  test(
    'covered rows may have no authored cells and preserve empty origins',
    () {
      final note = WordZoteroNoteText.fromHtml(
        _table('<tr><th rowspan=" 3 " colspan="2"></th></tr><tr/><tr></tr>'),
      );
      final table = note.blocks.single as WmlTable;
      expect(table.rows, hasLength(3));
      expect(table.rows.every((row) => row.cells.length == 1), isTrue);
      expect(table.rows.first.cells.single.vMerge, WmlVMerge.restart);
      expect(
        table.rows
            .skip(1)
            .every((row) => row.cells.single.vMerge == WmlVMerge.cont),
        isTrue,
      );
      expect(note.paragraphs.map((paragraph) => paragraph.text), ['', '', '']);
      _sameParagraphs(note);
    },
  );

  test('independent row groups retain their own vertical merge chains', () {
    final note = WordZoteroNoteText.fromHtml(
      '<table><tbody><tr><td rowspan="2">First</td></tr><tr/></tbody>'
      '<tbody><tr><td rowspan="2">Second</td></tr><tr/></tbody></table>',
    );
    final table = note.blocks.single as WmlTable;
    expect(table.rows.map((row) => row.cells.single.vMerge), [
      WmlVMerge.restart,
      WmlVMerge.cont,
      WmlVMerge.restart,
      WmlVMerge.cont,
    ]);
    expect(note.paragraphs.map((paragraph) => paragraph.text), [
      'First',
      '',
      'Second',
      '',
    ]);
    _sameParagraphs(note);
  });

  test('direct row groups stay separate across empty and populated bodies', () {
    String pair(String text) => '<tr><td rowspan="2">$text</td></tr><tr/>';
    final note = WordZoteroNoteText.fromHtml(
      '<table><tbody>${pair('First')}</tbody>${pair('Second')}'
      '<tbody>${pair('Third')}</tbody>${pair('Fourth')}'
      '<tbody/>${pair('Fifth')}</table>',
    );
    final table = note.blocks.single as WmlTable;
    expect(table.rows.map((row) => row.cells.single.vMerge), [
      for (var group = 0; group < 5; group++) ...[
        WmlVMerge.restart,
        WmlVMerge.cont,
      ],
    ]);
    expect(note.paragraphs.map((paragraph) => paragraph.text), [
      for (final text in ['First', 'Second', 'Third', 'Fourth', 'Fifth']) ...[
        text,
        '',
      ],
    ]);
    _sameParagraphs(note);
  });

  test('widths reconcile after skipping vertically covered columns', () {
    final note = WordZoteroNoteText.fromHtml(
      _table(
        '<tr><td rowspan="2" data-colwidth="100">Left</td>'
        '<td data-colwidth="0">Middle</td>'
        '<td rowspan="2" data-colwidth="200">Right</td></tr>'
        '<tr><td data-colwidth="80">Sized middle</td></tr>',
      ),
    );
    final table = note.blocks.single as WmlTable;
    expect(table.grid, [75, 60, 150]);
    for (final row in table.rows) {
      expect(row.cells.map((cell) => cell.width), [75, 60, 150]);
    }
    _sameParagraphs(note);
  });

  for (final span in [
    '0',
    '-1',
    '1.5',
    '01',
    '1e2',
    '+1',
    '',
    'NaN',
    '257',
    '999999999999999999999',
  ]) {
    test('invalid row span syntax or bound refuses: $span', () {
      expect(
        () => WordZoteroNoteText.fromHtml(
          _table('<tr><td rowspan="$span">Origin</td></tr><tr/>'),
        ),
        throwsUnsupportedError,
      );
    });
  }

  for (final rows in [
    '<tr><td rowspan="3">Past end</td></tr><tr/>',
    '<tr><td rowspan="2">Left</td><td>Right</td></tr><tr/>',
    '<tr><td>Left</td><td rowspan="2">Middle</td><td>Right</td></tr>'
        '<tr><td colspan="2">Collision</td><td>Right</td></tr>',
    '<tr><td rowspan="2" colspan="2">Covered</td></tr>'
        '<tr><td>Overflow</td></tr>',
    '<tr><td rowspan="2" data-colwidth="100">Left</td>'
        '<td data-colwidth="80">Right</td></tr>'
        '<tr><td data-colwidth="81">Conflicting right</td></tr>',
  ]) {
    test('invalid vertical coverage or column widths refuse: $rows', () {
      expect(
        () => WordZoteroNoteText.fromHtml(_table(rows)),
        throwsUnsupportedError,
      );
    });
  }

  for (final html in [
    '<table><tbody><tr><td rowspan="2">Cross group</td></tr></tbody>'
        '<tbody><tr/></tbody></table>',
    '<table><tr><td rowspan="2">Cross group</td></tr><tbody><tr/></tbody>'
        '</table>',
    '<table><tbody><tr><td rowspan="2">Cross group</td></tr></tbody><tr/>'
        '</table>',
    '<table><tr><td rowspan="2">Cross empty group</td></tr>'
        '<tbody/><tr/></table>',
    '<table><tr><td rowspan="2">Cross empty group</td></tr>'
        '<tbody></tbody><tbody/><tr/></table>',
  ]) {
    test('a vertical merge cannot cross row-group ownership: $html', () {
      expect(() => WordZoteroNoteText.fromHtml(html), throwsUnsupportedError);
    });
  }

  test('256-row spans require exactly covered actual rows', () {
    final rows =
        '<tr><td rowspan="256">Origin</td></tr>'
        '${List.filled(255, '<tr/>').join()}';
    final note = WordZoteroNoteText.fromHtml(_table(rows));
    expect(note.paragraphs, hasLength(256));
    expect((note.blocks.single as WmlTable).rows, hasLength(256));
    _sameParagraphs(note);
    expect(
      () => WordZoteroNoteText.fromHtml(
        _table(
          '<tr><td rowspan="256">Origin</td></tr>'
          '${List.filled(254, '<tr/>').join()}',
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('the global native-cell budget includes every vertical continuation', () {
    String tall(int columns) => _table(
      '<tr>${List.filled(columns, '<td rowspan="256">Origin</td>').join()}</tr>'
      '${List.filled(255, '<tr/>').join()}',
    );
    final full = tall(16);
    final note = WordZoteroNoteText.fromHtml(full);
    expect(note.paragraphs, hasLength(4096));
    expect(
      (note.blocks.single as WmlTable).rows.expand((row) => row.cells),
      hasLength(4096),
    );
    _sameParagraphs(note);
    for (final html in [
      tall(17),
      '$full${_table('<tr><td>One extra</td></tr>')}',
    ]) {
      expect(() => WordZoteroNoteText.fromHtml(html), throwsFormatException);
    }
  });

  test('the paragraph budget includes synthetic continuation paragraphs', () {
    String tall(int count) => _table(
      '<tr><td rowspan="256">${List.filled(count, '<p>Text</p>').join()}</td></tr>'
      '${List.filled(255, '<tr/>').join()}',
    );
    final note = WordZoteroNoteText.fromHtml(tall(9745));
    expect(note.paragraphs, hasLength(10000));
    _sameParagraphs(note);
    expect(
      () => WordZoteroNoteText.fromHtml(tall(9746)),
      throwsFormatException,
    );
  });

  test('cell background colors map to native fills without coloring text', () {
    final note = WordZoteroNoteText.fromHtml(
      _table(
        '<tr><td style="background-color: rgb(0, 128, 255)">A</td>'
        '<td style="BACKGROUND-COLOR: #aBc">B</td>'
        '<td style="background-color:#123456;">C</td>'
        '<td style="background-color:transparent">D</td></tr>',
      ),
    );
    final table = note.blocks.single as WmlTable;
    expect(table.rows.single.cells.map((cell) => cell.fillColor), [
      '0080FF',
      'AABBCC',
      '123456',
      null,
    ]);
    _sameParagraphs(note);
  });

  for (final html in [
    '<table></table>',
    '<table><tbody></tbody></table>',
    '<table><tr></tr></table>',
    '<table><tr><td>A</td><td>B</td></tr><tr><td>C</td></tr></table>',
    '<table><td>A</td></table>',
    '<table><tbody><td>A</td></tbody></table>',
    '<table><div><tr><td>A</td></tr></div></table>',
    '<table>Loose<tr><td>A</td></tr></table>',
    '<table><tr>Loose<td>A</td></tr></table>',
    '<p><table><tr><td>Inside paragraph</td></tr></table></p>',
    '<span><table><tr><td>Inside inline</td></tr></table></span>',
    '<ul><li><table><tr><td>Inside item</td></tr></table></li></ul>',
    '<a href="https://www.zotero.org/?ABC123">'
        '<table><tr><td>Inside citation</td></tr></table></a>',
    '<table><thead><tr><th>Header group</th></tr></thead></table>',
    '<table><tfoot><tr><td>Footer group</td></tr></tfoot></table>',
    '<table><caption>Caption</caption><tr><td>A</td></tr></table>',
    '<table><colgroup><col/></colgroup><tr><td>A</td></tr></table>',
    '<tbody><tr><td>Orphan</td></tr></tbody>',
    '<tr><td>Orphan</td></tr>',
    '<td>Orphan</td>',
    '<table class="custom"><tr><td>A</td></tr></table>',
    '<table style="width:100%"><tr><td>A</td></tr></table>',
    '<table><tbody style="color:red"><tr><td>A</td></tr></tbody></table>',
    '<table><tr style="height:20px"><td>A</td></tr></table>',
    '<table><tr><td class="custom">A</td></tr></table>',
    '<table><tr><td rowspan="2">Merged</td></tr></table>',
    '<table><tr><td colspan="0">Invalid</td></tr></table>',
    '<table><tr><td colspan="-1">Invalid</td></tr></table>',
    '<table><tr><td colspan="1.5">Invalid</td></tr></table>',
    '<table><tr><td colspan="33">Oversized</td></tr></table>',
    '<table><tr><td colspan="999999999999999999999">Oversized</td></tr></table>',
    '<table><tr><td rowspan="-1">Invalid</td></tr></table>',
    '<table><tr><td colspan="2" rowspan="2">Vertical merge</td></tr></table>',
    '<table><tr><td data-colwidth="4001">Oversized</td></tr></table>',
    '<table><tr><td data-colwidth="96,96">Merged widths</td></tr></table>',
    '<table><tr><td colspan="2" data-colwidth="96">Missing width</td></tr></table>',
    '<table><tr><td colspan="2" data-colwidth="0,96,0">Extra width</td></tr></table>',
    '<table><tr><td colspan="2" data-colwidth="96,">Missing width</td></tr></table>',
    '<table><tr><td colspan="2" data-colwidth=",96">Missing width</td></tr></table>',
    '<table><tr><td colspan="2" data-colwidth="-1,96">Negative</td></tr></table>',
    '<table><tr><td colspan="2" data-colwidth="1,4001">Oversized</td></tr></table>',
    '<table><tr><td colspan="2" data-colwidth="4000,4000">Too wide</td></tr></table>',
    '<table><tr><td colspan="2" data-colwidth="100,200">Merged</td></tr>'
        '<tr><td data-colwidth="100">A</td>'
        '<td data-colwidth="201">Conflicting</td></tr></table>',
    '<table><tr><td colspan="2">A</td><td>B</td></tr>'
        '<tr><td>C</td><td>D</td></tr></table>',
    '<table><tr><td>A</td><td>B</td></tr>'
        '<tr><td colspan="2">C</td><td>D</td></tr></table>',
    '<table><tr><td data-colwidth="12.5">Fractional</td></tr></table>',
    '<table><tr><td data-colwidth="NaN">Invalid</td></tr></table>',
    '<table><tr><td data-colwidth="100">A</td></tr>'
        '<tr><td data-colwidth="101">Conflicting</td></tr></table>',
    '<table><tr><td data-colwidth="4000">A</td>'
        '<td data-colwidth="4000">Too wide</td></tr></table>',
    '<table><tr><td style="padding:4px">Unsupported</td></tr></table>',
    '<table><tr><td style="font-weight:bold">Unsupported</td></tr></table>',
    '<table><tr><td style="background-color:rgba(0,0,0,0.5)">Alpha</td></tr>'
        '</table>',
    '<table><tr><td style="background-color:rgb(256,0,0)">Range</td></tr>'
        '</table>',
    '<table><tr><td style="background-color:red">Named</td></tr></table>',
    '<table><tr><td style="background-color:#fff;background-color:#000">'
        'Duplicate</td></tr></table>',
    '<table><tr><td style="background-color:">Empty</td></tr></table>',
  ]) {
    test('unsupported table structure or formatting refuses: $html', () {
      expect(
        () => WordZoteroNoteText.fromHtml('<p>Before</p>$html<p>After</p>'),
        throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())),
      );
    });
  }

  test('citation identities remain unique across different cells', () {
    expect(
      () => WordZoteroNoteText.fromHtml(
        _table('<tr><td>$_one</td><td>$_one</td></tr>'),
      ),
      throwsFormatException,
    );
  });

  test('authored structural-marker characters cannot impersonate a table', () {
    for (final marker in ['\uE000t0\uE001', '&#57344;c0&#57345;']) {
      expect(
        () => WordZoteroNoteText.fromHtml(_table('<tr><td>$marker</td></tr>')),
        throwsFormatException,
      );
    }
  });

  test('table count, row count and column count are independently bounded', () {
    final cell = '<td><p>A</p></td>';
    final row = '<tr>$cell</tr>';
    for (final html in [
      List.filled(65, _table(row)).join(),
      _table(List.filled(257, row).join()),
      _table('<tr>${List.filled(33, cell).join()}</tr>'),
      _table('<tr><td colspan="32">Wide</td><td>Overflow</td></tr>'),
      _table('<tr><td colspan="17">A</td><td colspan="16">B</td></tr>'),
    ]) {
      expect(() => WordZoteroNoteText.fromHtml(html), throwsFormatException);
    }
  });

  test('the cell budget is global across all tables in one note', () {
    final row = '<tr>${List.filled(16, '<td>A</td>').join()}</tr>';
    final fullTable = _table(List.filled(16, row).join());
    expect(
      () => WordZoteroNoteText.fromHtml(
        List.filled(16, fullTable).join() +
            _table('<tr><td>One cell too many</td></tr>'),
      ),
      throwsFormatException,
    );
  });

  test('horizontal merges retain the global authored-cell budget', () {
    final row = '<tr>${List.filled(16, '<td colspan="2">A</td>').join()}</tr>';
    final fullTable = _table(List.filled(16, row).join());
    final fullNote = List.filled(16, fullTable).join();
    final accepted = WordZoteroNoteText.fromHtml(fullNote);
    expect(accepted.paragraphs, hasLength(4096));
    expect(
      accepted.blocks.whereType<WmlTable>().every(
        (table) => table.grid.length == 32,
      ),
      isTrue,
    );
    expect(
      () => WordZoteroNoteText.fromHtml(
        '$fullNote${_table('<tr><td colspan="2">One cell too many</td></tr>')}',
      ),
      throwsFormatException,
    );
    _sameParagraphs(accepted);
  });

  test('the paragraph budget includes all cells in the entire note', () {
    final many = List.filled(10001, '<p>A</p>').join();
    expect(
      () => WordZoteroNoteText.fromHtml(_table('<tr><td>$many</td></tr>')),
      throwsFormatException,
    );
  });

  test('the image budget is shared by cells and surrounding paragraphs', () {
    final picture = image.encodePng(image.Image(width: 4, height: 2));
    final img = '<img src="data:image/png;base64,${base64Encode(picture)}">';
    final cells = List.filled(32, '<tr><td><p>$img</p></td></tr>').join();
    final accepted = WordZoteroNoteText.fromHtml(_table(cells));
    expect(accepted.paragraphs, hasLength(32));
    expect(
      accepted.paragraphs
          .expand((paragraph) => paragraph.inlines)
          .whereType<WmlRun>()
          .where((run) => run.inlineVisual != null),
      hasLength(32),
    );
    expect(
      () => WordZoteroNoteText.fromHtml('<p>$img</p>${_table(cells)}'),
      throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())),
    );
  });
}
