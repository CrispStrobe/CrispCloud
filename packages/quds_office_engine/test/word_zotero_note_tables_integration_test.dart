import 'dart:convert';

import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _documentId = 'research-target';
const _one = '<a href="https://www.zotero.org/?FIRST1">(old one)</a>';
const _two = '<a href="https://www.zotero.org/?SECOND2">(old two)</a>';

WordZoteroCitingSession _session(
  WmlDocument document,
  WmlParagraph paragraph, {
  int start = 0,
  int? end,
}) => WordZoteroCitingSession(
  document: document,
  documentId: _documentId,
  insertionParagraph: paragraph,
  insertionOffset: start,
  insertionEndOffset: end,
);

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_documentId, ...args]);

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http'])! as List<Object?>)
        .cast<Map<String, Object>>();

List<Map<String, Object>> _convert(
  WordZoteroCitingSession session,
  List<String> ids, {
  int type = 0,
}) =>
    (_call(session, 'Document.convertPlaceholdersToFields', [
              ids,
              type,
              'Http',
            ])!
            as List<Object?>)
        .cast<Map<String, Object>>();

ZoteroCitation _citation(String id, String text) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
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

void _start(WordZoteroCitingSession session, String html, {int type = 0}) {
  final temp =
      _call(session, 'Document.insertField', ['Http', type])!
          as Map<String, Object>;
  _call(session, 'Field.delete', [temp['id']]);
  _call(session, 'Document.insertText', [html]);
}

void _finish(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

String _table(String first, String second) =>
    '<table><tbody><tr><td><p>$first</p></td>'
    '<td><p>$second</p></td></tr></tbody></table>';

String _mergedTable(String first, String second) =>
    '<table><tbody><tr>'
    '<th colspan="3" data-colwidth="120,160,80" '
    'style="background-color: #eeeeee"><p>Combined heading</p></th></tr>'
    '<tr><td colspan="2" data-colwidth="120,160" '
    'style="background-color: #ffeedd">'
    '<ol start="3"><li>First $first</li><li>More detail</li></ol></td>'
    '<td data-colwidth="80"><p>Top right</p></td></tr>'
    '<tr><td data-colwidth="120"><p>Bottom left</p></td>'
    '<td colspan="2" data-colwidth="160,80"><p>Second $second</p></td>'
    '</tr></tbody></table>';

String _verticalTable(String first, String second) =>
    '<table><tbody><tr>'
    '<td rowspan="3" colspan="2" data-colwidth="120,160" '
    'style="background-color:#ffeedd"><p>First $first</p>'
    '<ol start="3"><li>Origin list</li></ol></td>'
    '<td data-colwidth="80"><p>Top</p></td></tr>'
    '<tr><td data-colwidth="80"><ol start="7"><li>Second $second</li>'
    '<li>Next</li></ol></td></tr>'
    '<tr><td data-colwidth="80"><p>Bottom</p></td></tr>'
    '</tbody></table>';

void _expectVerticalTable(WmlTable table) {
  expect(table.grid, [90, 120, 60]);
  expect(table.rows, hasLength(3));
  expect(WordTable.supportsGridAddressing(table), isTrue);
  for (var row = 0; row < 3; row++) {
    final cells = table.rows[row].cells;
    expect(cells.map((cell) => cell.gridSpan), [2, 1]);
    expect(cells.map((cell) => cell.width), [210, 60]);
    expect(cells.first.vMerge, row == 0 ? WmlVMerge.restart : WmlVMerge.cont);
    expect(cells.last.vMerge, WmlVMerge.none);
    expect(cells.first.fillColor, 'FFEEDD');
    if (row != 0) {
      expect(cells.first.blocks, hasLength(1));
      final continuation = cells.first.blocks.single as WmlParagraph;
      expect(continuation.text, isEmpty);
      expect(continuation.properties.numId, isNull);
    }
  }
  expect(
    WordTree.paragraphs([table])
        .where((paragraph) => paragraph.properties.listLabel != null)
        .map((paragraph) => paragraph.properties.listLabel),
    ['3. ', '7. ', '8. '],
  );
}

WmlTable _onlyTable(Iterable<WmlBlock> blocks) =>
    blocks.whereType<WmlTable>().single;

void _expectMergedTable(WmlTable table) {
  expect(table.grid, [90.0, 120.0, 60.0]);
  expect(
    table.rows.map((row) => row.cells.map((cell) => cell.gridSpan).toList()),
    [
      [3],
      [2, 1],
      [1, 2],
    ],
  );
  expect(
    table.rows.map((row) => row.cells.map((cell) => cell.width).toList()),
    [
      [270.0],
      [210.0, 60.0],
      [90.0, 180.0],
    ],
  );
  expect(table.rows.first.cells.single.fillColor, 'EEEEEE');
  expect(table.rows[1].cells.first.fillColor, 'FFEEDD');
  expect(WordTable.supportsGridAddressing(table), isTrue);
  final heading = table.rows.first.cells.single.blocks.single as WmlParagraph;
  expect(
    heading.inlines.whereType<WmlRun>().every((r) => r.properties.bold),
    isTrue,
  );
  expect(
    WordTree.paragraphs([table])
        .where((p) => p.properties.listLabel != null)
        .map((p) => p.properties.listLabel),
    ['3. ', '4. '],
  );
}

void main() {
  test('table replacement preserves rich prose and active field ownership', () {
    final original = WmlParagraph(
      inlines: [
        WmlRun(text: 'Before ', properties: WmlRunProps(bold: true)),
        WmlRun(text: 'TARGET'),
        WmlRun(
          text: ' after',
          properties: WmlRunProps(italic: true),
          hyperlink: const WmlHyperlink(url: 'https://example.org/authored'),
        ),
      ],
    );
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [original]),
      ],
    );
    final session = _session(document, original, start: 7, end: 13);
    _start(session, _table('First $_one', 'Second $_two'));
    final inserted = _convert(session, ['SECOND2', 'FIRST1']);
    _set(session, inserted[0], 'two', '(Two)');
    _set(session, inserted[1], 'one', '<i>(One)</i>');
    expect(original.text, 'Before TARGET after');
    expect(document.sections.single.blocks, [same(original)]);
    _finish(session);

    final blocks = document.sections.single.blocks;
    expect(blocks, hasLength(3));
    expect(blocks.first, same(original));
    final table = _onlyTable(blocks);
    expect(
      table.rows.single.cells.map(
        (c) => (c.blocks.single as WmlParagraph).text,
      ),
      ['First (One)', 'Second (Two)'],
    );
    final suffix = blocks.last as WmlParagraph;
    expect(original.text, 'Before ');
    expect(original.inlines.whereType<WmlRun>().single.properties.bold, isTrue);
    expect(suffix.text, ' after');
    final run = suffix.inlines.whereType<WmlRun>().single;
    expect(run.properties.italic, isTrue);
    expect(run.hyperlink!.url, 'https://example.org/authored');
    expect(session.caretAfter!.paragraph, same(suffix));
    expect(session.caretAfter!.offset, 0);
    final fields = WordZotero.fields(document);
    expect(fields.map((f) => f.citation!.citationId), ['one', 'two']);
    expect(fields[0].paragraph, same(table.rows.single.cells[0].blocks.single));
    expect(fields[1].paragraph, same(table.rows.single.cells[1].blocks.single));
  });

  test('table-only body insertion has no detached cell or missing caret', () {
    final document = WmlDocument.empty();
    final session = _session(document, document.paragraphs.single);
    _start(session, _table('Left', 'Right'));
    _finish(session);
    final blocks = document.sections.single.blocks;
    expect(blocks, hasLength(2));
    expect(blocks.first, isA<WmlTable>());
    final suffix = blocks.last as WmlParagraph;
    expect(suffix.text, isEmpty);
    expect(session.caretAfter, (paragraph: suffix, offset: 0));
    final reopened = _reopen(document);
    expect(reopened.sections.single.blocks.first, isA<WmlTable>());
    expect(reopened.sections.single.blocks.last, isA<WmlParagraph>());
  });

  test('fields before and after a table insertion retain document order', () {
    final document = WmlDocument.empty(text: 'Left TARGET Right');
    final paragraph = document.paragraphs.single;
    WordZotero.insertCitation(paragraph, _citation('before', '(B)'), index: 0);
    WordZotero.insertCitation(
      paragraph,
      _citation('after', '(A)'),
      index: paragraph.text.length,
    );
    final start = paragraph.text.indexOf('TARGET');
    final session = _session(document, paragraph, start: start, end: start + 6);
    final original = _fields(session);
    _start(session, _table(_one, _two));
    final inserted = _convert(session, ['SECOND2', 'FIRST1']);
    _set(session, original.first, 'before', '(Before expanded)');
    _set(session, original.last, 'after', '(After expanded)');
    _set(session, inserted[0], 'two', '(Two)');
    _set(session, inserted[1], 'one', '(One)');
    expect(_fields(session).map((f) => f['id']), [
      original.first['id'],
      inserted[1]['id'],
      inserted[0]['id'],
      original.last['id'],
    ]);
    _finish(session);
    expect(document.paragraphs.first.text, '(Before expanded)Left ');
    expect(document.paragraphs.last.text, ' Right(After expanded)');
    expect(session.caretAfter!.paragraph, same(document.paragraphs.last));
    expect(session.caretAfter!.offset, 0);
    for (final result in [document, _reopen(document)]) {
      expect(WordZotero.fields(result).map((f) => f.citation!.citationId), [
        'before',
        'one',
        'two',
        'after',
      ]);
      final fresh = _session(result, result.paragraphs.first);
      expect(_fields(fresh).map((f) => f['noteIndex']), [0, 0, 0, 0]);
    }
  });

  test('ordinary paragraphs around a table remain outside its cells', () {
    final document = WmlDocument.empty(text: 'BeforeAfter');
    final session = _session(document, document.paragraphs.single, start: 6);
    _start(session, '<p>Intro</p>${_table('Cell one', 'Cell two')}<p>End</p>');
    _finish(session);
    final blocks = document.sections.single.blocks;
    expect(blocks.map((b) => b is WmlParagraph ? b.text : 'TABLE'), [
      'Before',
      'Intro',
      'TABLE',
      'End',
      'After',
    ]);
    expect(session.caretAfter!.paragraph, same(blocks[3]));
    expect(session.caretAfter!.offset, 3);
  });

  for (final type in [0, 1, 2]) {
    final story = switch (type) {
      1 => 'footnote',
      2 => 'endnote',
      _ => 'body',
    };
    test(
      '$story merged cells retain DOCX geometry and live citation owners on refresh',
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
        final session = _session(
          document,
          paragraph,
          start: start,
          end: start + 6,
        );
        _start(session, _mergedTable(_one, _two), type: type);
        final inserted = _convert(session, ['SECOND2', 'FIRST1'], type: type);
        _set(session, inserted[0], 'two', '(Two)');
        _set(session, inserted[1], 'one', '<i>(One)</i>');
        expect(paragraph.text, originalText);
        expect(WordZotero.fields(document), isEmpty);
        _finish(session);
        final insertedBlocks = note?.blocks ?? document.sections.single.blocks;
        final insertedTable = _onlyTable(insertedBlocks);
        _expectMergedTable(insertedTable);
        expect(session.caretAfter!.paragraph, same(insertedBlocks.last));
        expect(session.caretAfter!.offset, 0);
        expect((insertedBlocks.last as WmlParagraph).text, ' after');

        var result = _reopen(document);
        for (var round = 0; round < 2; round++) {
          final currentNote = type == 0
              ? null
              : (type == 2 ? result.endnotes : result.footnotes).single;
          final blocks = currentNote?.blocks ?? result.sections.single.blocks;
          final table = _onlyTable(blocks);
          _expectMergedTable(table);
          expect(result.footnotes, hasLength(type == 1 ? 1 : 0));
          expect(result.endnotes, hasLength(type == 2 ? 1 : 0));
          if (currentNote != null) {
            expect(
              currentNote.paragraphs.first.inlines.first,
              isA<WmlNoteMarker>(),
            );
            expect(
              WordTree.paragraphs([
                table,
              ]).expand((p) => p.inlines.whereType<WmlNoteMarker>()),
              isEmpty,
            );
          }
          final firstCellParagraph =
              table.rows[1].cells.first.blocks.first as WmlParagraph;
          final secondCellParagraph =
              table.rows[2].cells.last.blocks.single as WmlParagraph;
          final fields = WordZotero.fields(result);
          expect(fields.map((f) => f.citation!.citationId), ['one', 'two']);
          expect(fields.every((f) => f.canEdit), isTrue);
          expect(fields[0].paragraph, same(firstCellParagraph));
          expect(fields[1].paragraph, same(secondCellParagraph));
          expect(WordTable.locationOfParagraph(result, fields[0].paragraph), (
            table: table,
            row: 1,
            col: 0,
          ));
          expect(WordTable.locationOfParagraph(result, fields[1].paragraph), (
            table: table,
            row: 2,
            col: 1,
          ));
          final refresh = _session(result, blocks.first as WmlParagraph);
          final current = _fields(refresh);
          expect(current.map((f) => f['noteIndex']), [
            type == 0 ? 0 : 1,
            type == 0 ? 0 : 1,
          ]);
          _set(refresh, current[0], 'one', '<i>(One refreshed)</i>');
          _set(refresh, current[1], 'two', '(Two refreshed)');
          _finish(refresh);
          expect(_onlyTable(blocks), same(table));
          _expectMergedTable(table);
          expect(WordZotero.fields(result).map((f) => f.cachedText), [
            '(One refreshed)',
            '(Two refreshed)',
          ]);
          expect(firstCellParagraph.text, 'First (One refreshed)');
          expect(secondCellParagraph.text, 'Second (Two refreshed)');
          expect((blocks.last as WmlParagraph).text, ' after');
          result = _reopen(result);
        }
      },
    );
  }

  for (final type in [0, 1, 2]) {
    final story = switch (type) {
      1 => 'footnote',
      2 => 'endnote',
      _ => 'body',
    };
    test(
      '$story vertical merges preserve field owners and lists through DOCX refresh',
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
        final session = _session(
          document,
          paragraph,
          start: start,
          end: start + 6,
        );
        _start(session, _verticalTable(_one, _two), type: type);
        final inserted = _convert(session, ['SECOND2', 'FIRST1'], type: type);
        _set(session, inserted[0], 'two', '(Two)');
        _set(session, inserted[1], 'one', '<i>(One)</i>');
        expect(paragraph.text, originalText);
        expect(WordZotero.fields(document), isEmpty);
        _finish(session);
        final insertedBlocks = note?.blocks ?? document.sections.single.blocks;
        _expectVerticalTable(_onlyTable(insertedBlocks));
        expect(session.caretAfter!.paragraph, same(insertedBlocks.last));
        expect(session.caretAfter!.offset, 0);
        expect((insertedBlocks.last as WmlParagraph).text, ' after');

        var current = document;
        for (var round = 0; round < 3; round++) {
          final currentNote = type == 0
              ? null
              : (type == 2 ? current.endnotes : current.footnotes).single;
          final blocks = currentNote?.blocks ?? current.sections.single.blocks;
          final table = _onlyTable(blocks);
          _expectVerticalTable(table);
          final origin =
              table.rows.first.cells.first.blocks.first as WmlParagraph;
          final middle = table.rows[1].cells.last.blocks.first as WmlParagraph;
          final fields = WordZotero.fields(current);
          expect(fields.map((field) => field.citation!.citationId), [
            'one',
            'two',
          ]);
          expect(fields.map((field) => field.paragraph), [
            same(origin),
            same(middle),
          ]);
          expect(fields.every((field) => field.canEdit), isTrue);
          expect(WordTable.locationOfParagraph(current, fields[0].paragraph), (
            table: table,
            row: 0,
            col: 0,
          ));
          expect(WordTable.locationOfParagraph(current, fields[1].paragraph), (
            table: table,
            row: 1,
            col: 1,
          ));
          if (currentNote != null) {
            expect(
              currentNote.paragraphs.first.inlines.first,
              isA<WmlNoteMarker>(),
            );
            expect(
              WordTree.paragraphs([
                table,
              ]).expand((p) => p.inlines.whereType<WmlNoteMarker>()),
              isEmpty,
            );
          }
          final refresh = _session(current, blocks.first as WmlParagraph);
          final exchanged = _fields(refresh);
          expect(exchanged.map((field) => field['noteIndex']), [
            type == 0 ? 0 : 1,
            type == 0 ? 0 : 1,
          ]);
          _set(refresh, exchanged[0], 'one', '<i>(One refreshed $round)</i>');
          _set(refresh, exchanged[1], 'two', '(Two refreshed $round)');
          _finish(refresh);
          expect(origin.text, 'First (One refreshed $round)');
          expect(middle.text, 'Second (Two refreshed $round)');
          _expectVerticalTable(table);
          current = _reopen(current);
        }
      },
    );
  }

  test('citations around a vertical table keep complete document order', () {
    const before = '<a href="https://www.zotero.org/?BEFORE3">(Before)</a>';
    const after = '<a href="https://www.zotero.org/?AFTER4">(After)</a>';
    final document = WmlDocument.empty(text: 'TARGET');
    final session = _session(document, document.paragraphs.single, end: 6);
    _start(session, '<p>$before</p>${_verticalTable(_one, _two)}<p>$after</p>');
    final converted = _convert(session, [
      'AFTER4',
      'SECOND2',
      'FIRST1',
      'BEFORE3',
    ]);
    for (var index = 0; index < converted.length; index++) {
      final id = ['after', 'two', 'one', 'before'][index];
      _set(session, converted[index], id, '($id)');
    }
    _finish(session);
    for (final current in [document, _reopen(document)]) {
      final fields = WordZotero.fields(current);
      expect(fields.map((field) => field.citation!.citationId), [
        'before',
        'one',
        'two',
        'after',
      ]);
      expect(fields.map((field) => field.cachedText), [
        '(before)',
        '(one)',
        '(two)',
        '(after)',
      ]);
      final blocks = current.sections.single.blocks;
      final table = _onlyTable(blocks);
      expect(fields.first.paragraph, same(blocks.first));
      expect(fields.last.paragraph, same(blocks.last));
      expect(fields[1].paragraph, same(table.rows[0].cells.first.blocks.first));
      expect(fields[2].paragraph, same(table.rows[1].cells.last.blocks.first));
      _expectVerticalTable(table);
    }
  });

  test('fully covered empty rows retain their merge chain through DOCX', () {
    final document = WmlDocument.empty(text: 'BeforeAfter');
    final session = _session(document, document.paragraphs.single, start: 6);
    _start(
      session,
      '<table><tbody><tr><td rowspan="3" colspan="2">$_one</td></tr>'
      '<tr/><tr/></tbody></table>',
    );
    _set(session, _convert(session, ['FIRST1']).single, 'one', '(One)');
    _finish(session);
    for (final current in [document, _reopen(document)]) {
      final table = _onlyTable(current.sections.single.blocks);
      expect(table.rows.map((row) => row.cells.length), [1, 1, 1]);
      expect(table.rows.map((row) => row.cells.single.vMerge), [
        WmlVMerge.restart,
        WmlVMerge.cont,
        WmlVMerge.cont,
      ]);
      expect(table.rows.every((row) => row.cells.single.gridSpan == 2), isTrue);
      expect(WordZotero.fields(current).single.cachedText, '(One)');
      expect(
        WordZotero.fields(current).single.paragraph,
        same(table.rows.first.cells.single.blocks.single),
      );
    }
  });

  test(
    'merged table layout and hit boxes cover the correct logical columns after DOCX reopen',
    () {
      final document = WmlDocument.empty(text: 'BeforeAfter');
      final session = _session(document, document.paragraphs.single, start: 6);
      _start(session, _mergedTable(_one, _two));
      final fields = _convert(session, ['SECOND2', 'FIRST1']);
      _set(session, fields[0], 'two', '(Two)');
      _set(session, fields[1], 'one', '(One)');
      _finish(session);

      for (final current in [document, _reopen(document)]) {
        final table = _onlyTable(current.sections.single.blocks);
        final laid = WordLayoutEngine(font: null).layout(current);
        expect(laid.pages, hasLength(1));
        final boxes = laid.pages.single.frames
            .where((box) => identical(box.table, table))
            .toList();
        expect(
          boxes,
          hasLength(5),
          reason: 'Covered grid slots must not create phantom cells',
        );
        final left = boxes.first.x;
        for (final (row, column, gridColumn, span, width) in [
          (0, 0, 0, 3, 270.0),
          (1, 0, 0, 2, 210.0),
          (1, 1, 2, 1, 60.0),
          (2, 0, 0, 1, 90.0),
          (2, 1, 1, 2, 180.0),
        ]) {
          final box = boxes.singleWhere(
            (b) => b.tableRow == row && b.tableCol == column,
          );
          final cell = table.rows[row].cells[column];
          final startX = table.grid.take(gridColumn).fold(0.0, (a, b) => a + b);
          expect(box.tableGridCol, gridColumn);
          expect(box.x, closeTo(left + startX, 0.01));
          expect(box.width, closeTo(width, 0.01));
          expect(box.height, greaterThan(0));
          expect(box.fillColor, cell.fillColor);
          final paragraphs = WordTree.paragraphs(cell.blocks).toList();
          expect(
            box.paragraphIndex,
            current.paragraphs.toList().indexOf(paragraphs.first),
          );
          expect(
            box.paragraphEnd,
            current.paragraphs.toList().indexOf(paragraphs.last),
          );
          for (
            var logical = gridColumn;
            logical < gridColumn + span;
            logical++
          ) {
            final x =
                left +
                table.grid.take(logical).fold(0.0, (a, b) => a + b) +
                table.grid[logical] / 2;
            final y = box.y + box.height / 2;
            final hits = boxes.where(
              (b) =>
                  x > b.x && x < b.x + b.width && y > b.y && y < b.y + b.height,
            );
            expect(
              hits,
              [same(box)],
              reason:
                  'Logical column $logical in row $row has one visible owner',
            );
            expect(WordTable.cellAtGrid(table, row, logical)!.cell, same(cell));
          }
        }
      }
    },
  );

  for (final endnote in [false, true]) {
    final label = endnote ? 'endnote' : 'footnote';
    final type = endnote ? 2 : 1;
    for (final separator in [false, true]) {
      test(
        '$label leading table preserves its marker and separator $separator',
        () {
          final document = WmlDocument.empty(text: 'Body');
          final note = WordNotes.insert(
            document,
            document.paragraphs.single,
            endnote: endnote,
            text: separator ? ' Trailing prose' : 'Trailing prose',
          );
          final original = note.paragraphs.single;
          original.inlines.insert(
            0,
            WmlNoteMarker(
              endnote: endnote,
              properties: WmlRunProps(bold: true),
            ),
          );
          final session = _session(
            document,
            original,
            start: separator ? 1 : 0,
          );
          _start(session, _table(_one, _two), type: type);
          final fields = _convert(session, ['SECOND2', 'FIRST1'], type: type);
          expect(fields.map((f) => f['noteIndex']), [1, 1]);
          _set(session, fields[0], 'two', '(Two)');
          _set(session, fields[1], 'one', '(One)');
          _finish(session);
          expect(note.blocks, hasLength(3));
          expect(note.blocks.first, same(original));
          expect(original.inlines.first, isA<WmlNoteMarker>());
          expect(original.text, separator ? ' ' : '');
          final table = _onlyTable(note.blocks);
          expect(
            WordTree.paragraphs([
              table,
            ]).expand((p) => p.inlines.whereType<WmlNoteMarker>()),
            isEmpty,
          );
          final suffix = note.blocks.last as WmlParagraph;
          expect(suffix.text, 'Trailing prose');
          expect(session.caretAfter, (paragraph: suffix, offset: 0));
          expect(WordNotes.editableParagraphs(note), contains(same(suffix)));
          expect(document.footnotes.length + document.endnotes.length, 1);
          for (final result in [document, _reopen(document)]) {
            final current =
                (endnote ? result.endnotes : result.footnotes).single;
            expect(current.blocks.first, isA<WmlParagraph>());
            expect(current.blocks[1], isA<WmlTable>());
            expect(
              current.paragraphs.first.inlines.first,
              isA<WmlNoteMarker>(),
            );
            expect(
              WordZotero.fields(result).map((f) => f.citation!.citationId),
              ['one', 'two'],
            );
            expect(
              _fields(
                _session(result, current.paragraphs.first),
              ).map((f) => f['noteIndex']),
              [1, 1],
            );
          }
        },
      );
    }

    test('$label offset zero keeps the automatic separator before a table', () {
      final document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: endnote,
        text: ' Tail',
      );
      final paragraph = note.paragraphs.single;
      paragraph.inlines.insert(
        0,
        WmlNoteMarker(endnote: endnote, properties: WmlRunProps()),
      );
      final session = _session(document, paragraph);
      _start(session, _table('Left', 'Right'), type: type);
      _finish(session);
      expect(note.paragraphs.first.text, ' ');
      expect(note.paragraphs.first.inlines.first, isA<WmlNoteMarker>());
      expect(note.paragraphs.last.text, 'Tail');
      expect(session.caretAfter, (paragraph: note.paragraphs.last, offset: 0));
    });

    test('$label empty authored story receives a main-flow table caret', () {
      final document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: endnote,
      );
      final session = _session(document, note.paragraphs.single);
      _start(session, _table('Cell', ''), type: type);
      _finish(session);
      expect(note.blocks.map((b) => b.runtimeType), [
        WmlParagraph,
        WmlTable,
        WmlParagraph,
      ]);
      final suffix = note.blocks.last as WmlParagraph;
      expect(session.caretAfter, (paragraph: suffix, offset: 0));
      expect(WordNotes.editableParagraphs(note).last, same(suffix));
      final restored =
          (endnote ? _reopen(document).endnotes : _reopen(document).footnotes)
              .single;
      expect(
        restored.paragraphs.first.inlines.any((i) => i is WmlNoteMarker),
        isTrue,
      );
    });

    test(
      '$label incompatible table citation conversion leaves all content staged',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'Keep',
        );
        final original = note.paragraphs.single;
        final session = _session(document, original);
        _start(session, _table(_one, ''), type: type);
        expect(
          () => _convert(session, ['FIRST1'], type: endnote ? 1 : 2),
          throwsUnsupportedError,
        );
        expect(
          () => _call(session, 'Document.complete'),
          throwsFormatException,
        );
        expect(note.blocks, [same(original)]);
        expect(note.text, 'Keep');
        expect(WordZotero.fields(document), isEmpty);
      },
    );
  }

  for (final type in [1, 2]) {
    test(
      'table cell citations create separate native notes for style $type',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final session = _session(
          document,
          document.paragraphs.single,
          start: 4,
        );
        _start(session, _table('First $_one', 'Second $_two'), type: type);
        final fields = _convert(session, ['SECOND2', 'FIRST1'], type: type);
        expect(fields.map((f) => f['noteIndex']), [2, 1]);
        _set(session, fields[0], 'two', '(Two)');
        _set(session, fields[1], 'one', '(One)');
        _finish(session);
        final table = _onlyTable(document.sections.single.blocks);
        final references = WordTree.paragraphs([table])
            .expand((p) => p.inlines.whereType<WmlRun>())
            .where((r) => r.noteRefId != null)
            .toList();
        expect(references, hasLength(2));
        expect(
          references.every((r) => r.noteRefEndnote == (type == 2)),
          isTrue,
        );
        for (final result in [document, _reopen(document)]) {
          expect(
            (type == 2 ? result.endnotes : result.footnotes),
            hasLength(2),
          );
          expect(
            _fields(
              _session(result, result.paragraphs.first),
            ).map((f) => f['noteIndex']),
            [1, 2],
          );
        }
      },
    );
  }

  test(
    'table geometry pictures lists and citations survive DOCX and refresh',
    () {
      final png = image.encodePng(
        image.Image(width: 2, height: 2, numChannels: 4),
      );
      final document = WmlDocument.empty(text: 'BeforeAfter');
      final session = _session(document, document.paragraphs.single, start: 6);
      final html =
          '<table><tbody><tr>'
          '<td data-colwidth="120" style="background-color: #abcdef">'
          '<ol start="3"><li>First $_one</li><li>Next</li></ol></td>'
          '<td data-colwidth="240"><p><img src="data:image/png;base64,'
          '${base64Encode(png)}" width="24" alt="Cell image"/></p>'
          '<ol start="7"><li>Second $_two</li></ol></td>'
          '</tr></tbody></table>';
      _start(session, html);
      final fields = _convert(session, ['SECOND2', 'FIRST1']);
      _set(session, fields[0], 'two', '(Two)');
      _set(session, fields[1], 'one', '(One)');
      _finish(session);
      var result = _reopen(document);
      for (var round = 0; round < 2; round++) {
        final table = _onlyTable(result.sections.single.blocks);
        expect(table.grid, [90.0, 180.0]);
        expect(table.rows.single.cells.first.fillColor, 'ABCDEF');
        final paragraphs = WordTree.paragraphs([table]).toList();
        expect(
          paragraphs
              .where((p) => p.properties.listLabel != null)
              .map((p) => p.properties.listLabel),
          ['3. ', '4. ', '7. '],
        );
        final visuals = paragraphs
            .expand((p) => p.inlines.whereType<WmlRun>())
            .where((r) => r.inlineVisual != null)
            .toList();
        expect(visuals, hasLength(1));
        final refresh = _session(result, result.paragraphs.first);
        final current = _fields(refresh);
        expect(current, hasLength(2));
        _set(refresh, current[0], 'one', '(One refreshed)');
        _set(refresh, current[1], 'two', '(Two refreshed)');
        _finish(refresh);
        expect(WordZotero.fields(result).map((f) => f.cachedText), [
          '(One refreshed)',
          '(Two refreshed)',
        ]);
        expect(_onlyTable(result.sections.single.blocks), same(table));
        expect(table.grid, [90.0, 180.0]);
        result = _reopen(result);
      }
    },
  );

  test('table payload cannot create a nested destination table', () {
    final target = WmlParagraph(inlines: [WmlRun(text: 'Keep')]);
    final cell = WmlTableCell(blocks: [target]);
    final outer = WmlTable(
      rows: [
        WmlTableRow(cells: [cell]),
      ],
      grid: [120],
    );
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [outer]),
      ],
    );
    final session = _session(document, target);
    expect(() => _start(session, _table('A', 'B')), throwsUnsupportedError);
    expect(cell.blocks, [same(target)]);
    expect(target.text, 'Keep');
    expect(document.sections.single.blocks, [same(outer)]);
  });

  test(
    'moving a staged table target into a cell refuses apply before mutation',
    () {
      final document = WmlDocument.empty(text: 'Keep');
      final paragraph = document.paragraphs.single;
      final session = _session(document, paragraph);
      _start(session, _table('A', 'B'));
      _call(session, 'Document.complete');
      final outer = WmlTable(
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(blocks: [paragraph]),
            ],
          ),
        ],
        grid: [120],
      );
      document.sections.single.blocks
        ..clear()
        ..add(outer);
      expect(session.apply, throwsA(anything));
      expect(outer.rows.single.cells.single.blocks, [same(paragraph)]);
      expect(paragraph.text, 'Keep');
    },
  );

  for (final ids in [
    <String>[],
    ['FIRST1'],
    ['FIRST1', 'FIRST1'],
    ['FIRST1', 'UNKNOWN'],
  ]) {
    test(
      'incomplete or invalid table placeholders reject atomically: $ids',
      () {
        final document = WmlDocument.empty(text: 'Keep');
        final paragraph = document.paragraphs.single;
        final session = _session(document, paragraph, end: 4);
        _start(session, _table(_one, _two));
        expect(() => _convert(session, ids), throwsFormatException);
        expect(
          () => _call(session, 'Document.complete'),
          throwsFormatException,
        );
        expect(document.sections.single.blocks, [same(paragraph)]);
        expect(paragraph.text, 'Keep');
        expect(WordZotero.fields(document), isEmpty);
        expect(document.footnotes, isEmpty);
        expect(document.endnotes, isEmpty);
      },
    );
  }
}
