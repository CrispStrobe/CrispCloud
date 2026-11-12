// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';
import 'support/table_border_fixture.dart';
import 'support/table_word_fixture.dart';

LegacyWordTable _table(Uint8List bytes) =>
    parseLegacyWordDocument(bytes).blocks.whereType<LegacyWordTable>().single;

void main() {
  for (final old in [false, true]) {
    test(
      '${old ? 'old' : 'modern'} row borders survive both property orders',
      () {
        for (final before in [false, true]) {
          final table = _table(
            tableBorderFixture(
              TableBorderCase('probe', old: old, beforeDefinition: before),
            ),
          );
          expect(table.rows.first.borders, hasLength(6));
          for (final cell in table.rows.expand((row) => row.cells)) {
            expect(
              cell.formatting.borders.values.map((b) => (b.style, b.colorHex)),
              List.filled(4, ('single', 'FF0000')),
            );
          }
        }
      },
    );
  }

  test('nil suppresses row inheritance and explicit TC80 borders win', () {
    for (final value in tableBorderCases.where((c) => c.cellBorder != 'none')) {
      final table = _table(tableBorderFixture(value));
      for (final cell in table.rows.expand((row) => row.cells)) {
        final top = cell.formatting.borders[LegacyWordTableBorderSide.top]!;
        if (value.rangeBorder == 'none') {
          expect((top.style, top.colorHex), ('single', 'FF0000'));
        } else if (value.cellBorder == 'nil') {
          expect(top.style, 'nil');
          expect(
            cell.formatting.borders.values.every((b) => b.style == 'nil'),
            true,
          );
        } else {
          expect(
            (top.style, top.colorHex, top.widthEighthPoints),
            ('double', '008000', 16),
          );
        }
      }
    }
  });

  test('ordered nil/none range resets and whole-row reset stay distinct', () {
    for (final mode in ['nil', 'none']) {
      final table = _table(
        tableBorderFixture(
          TableBorderCase('range', rangeBorder: mode, cellBorder: 'explicit'),
        ),
      );
      expect(
        table
            .rows
            .first
            .cells
            .first
            .formatting
            .borders[LegacyWordTableBorderSide.top]!
            .style,
        mode == 'nil' ? 'nil' : 'single',
      );
    }
    final reset = _table(
      tableBorderFixture(const TableBorderCase('reset', reset: true)),
    );
    expect(
      reset.rows
          .expand((r) => r.cells)
          .expand((c) => c.formatting.borders.values)
          .every((b) => b.style == 'none'),
      true,
    );
  });

  test(
    'all six row border positions map to the correct outer/interior edges',
    () {
      final table = _table(
        tableBorderFixture(const TableBorderCase('colors', coloredEdges: true)),
      );
      const expected = [
        ['FF0000', '00FF00', 'FF00FF', '00FFFF'],
        ['FF0000', '00FFFF', 'FF00FF', 'FFFF00'],
        ['FF00FF', '00FF00', '0000FF', '00FFFF'],
        ['FF00FF', '00FFFF', '0000FF', 'FFFF00'],
      ];
      final cells = table.rows.expand((row) => row.cells).toList();
      for (var i = 0; i < cells.length; i++) {
        expect([
          for (final side in LegacyWordTableBorderSide.values.take(4))
            cells[i].formatting.borders[side]!.colorHex,
        ], expected[i]);
      }
    },
  );

  test('native row exceptions and resolved cell borders are both editable', () {
    final result = convertLegacyWordToStructuredDocx(
      tableBorderFixture(const TableBorderCase('colors', coloredEdges: true)),
    );
    final xml = XmlDocument.parse(
      utf8.decode(
        ZipDecoder()
            .decodeBytes(result.bytes)
            .findFile('word/document.xml')!
            .content,
      ),
    );
    expect(xml.findAllElements('w:tblPrEx'), hasLength(2));
    expect(
      xml.findAllElements('w:tblBorders').map((e) => e.childElements.length),
      [6, 6],
    );
    expect(
      xml.findAllElements('w:tcBorders').map((e) => e.childElements.length),
      [4, 4, 4, 4],
    );
  });

  test(
    'row defaults override base style borders but conditional cell edges win',
    () {
      final greenTop = wordSprm(0xd47f, [8, 0, 128, 0, 0, 16, 3, 0, 0]);
      final condition = wordSprm(0xd66a, [
        greenTop.length + 2,
        ...wordU16(1),
        ...greenTop,
      ]);
      final bytes = tableFixture(
        [
          const TableFixtureParagraph('A\x07', depth: 1, cell: true),
          const TableFixtureParagraph('B\x07', depth: 1, cell: true),
          TableFixtureParagraph(
            '\x07',
            depth: 1,
            row: true,
            extra: [
              ...wordSprm(0x563a, wordU16(20)),
              ...wordSprm(0x740a, [...wordU16(0), ...wordU16(0x20)]),
              ...tableBorderDefinition('none'),
              ...tableBorderProperties(),
            ],
          ),
        ],
        styles: {
          0: const WordFixtureStyle(name: 'Normal'),
          20: WordFixtureStyle(
            name: 'Border style',
            table: true,
            tableProperties: [
              ...tableBorderProperties(colors: true),
              ...condition,
            ],
          ),
        },
      );
      final borders = _table(bytes).rows.single.cells.first.formatting.borders;
      expect(
        (
          borders[LegacyWordTableBorderSide.top]!.style,
          borders[LegacyWordTableBorderSide.top]!.colorHex,
        ),
        ('double', '008000'),
      );
      expect(borders[LegacyWordTableBorderSide.left]!.colorHex, 'FF0000');
    },
  );

  test('rejects truncated or oversized row-border records', () {
    for (final code in [0xd605, 0xd613]) {
      for (final length in [
        0,
        code == 0xd605 ? 23 : 47,
        code == 0xd605 ? 25 : 49,
      ]) {
        final bytes = tableFixture([
          const TableFixtureParagraph('Cell\x07', depth: 1, cell: true),
          TableFixtureParagraph(
            '\x07',
            depth: 1,
            row: true,
            widths: const [2000],
            extra: wordSprm(code, [length, ...List.filled(length, 0)]),
          ),
        ]);
        expect(() => parseLegacyWordDocument(bytes), throwsFormatException);
      }
    }
  });
}
