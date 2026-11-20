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
    '<table><tr><td><table><tr><td>Nested</td></tr></table></td></tr></table>',
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
    '<table><tr><td colspan="2">Merged</td></tr></table>',
    '<table><tr><td rowspan="2">Merged</td></tr></table>',
    '<table><tr><td colspan="0">Invalid</td></tr></table>',
    '<table><tr><td rowspan="-1">Invalid</td></tr></table>',
    '<table><tr><td data-colwidth="0">Invalid</td></tr></table>',
    '<table><tr><td data-colwidth="4001">Oversized</td></tr></table>',
    '<table><tr><td data-colwidth="96,96">Merged widths</td></tr></table>',
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
