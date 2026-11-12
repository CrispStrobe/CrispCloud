// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

List<TableFixtureParagraph> _row(int origin, {List<int> extra = const []}) => [
  const TableFixtureParagraph('Left\x07', depth: 1, cell: true),
  const TableFixtureParagraph('Right\x07', depth: 1, cell: true),
  TableFixtureParagraph(
    '\x07',
    depth: 1,
    row: true,
    widths: const [1200, 1200],
    extra: [
      ...tableFixtureDefinition([1200, 1200], origin: origin),
      ...extra,
    ],
  ),
];

XmlDocument _document(List<int> bytes) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content,
  ),
);

void main() {
  test('retains the signed first table edge instead of shifting content', () {
    for (final origin in [-108, 0, 720]) {
      final bytes = tableFixture(_row(origin));
      final table =
          parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
      expect(table.rows.single.originTwips, origin);
      expect(table.rows.single.cells.map((c) => c.widthTwips), [1200, 1200]);
      final xml = _document(convertLegacyWordToStructuredDocx(bytes).bytes);
      expect(
        xml.findAllElements('w:tblInd').single.getAttribute('w:w'),
        '${origin + 108}',
      );
      expect(
        xml.findAllElements('w:gridCol').map((e) => e.getAttribute('w:w')),
        ['1200', '1200'],
      );
    }
  });

  test(
    'native indentation uses the explicit first-cell margin, not half-gap',
    () {
      for (final margin in [0, 108, 240]) {
        final bytes = tableFixture(
          _row(
            480,
            extra: [
              ...wordSprm(0xd632, [6, 0, 1, 2, 3, ...wordU16(margin)]),
            ],
          ),
        );
        final xml = _document(convertLegacyWordToStructuredDocx(bytes).bytes);
        expect(
          xml.findAllElements('w:tblInd').single.getAttribute('w:w'),
          '${480 + margin}',
        );
      }
    },
  );

  test('row origins share an absolute grid with missing edge cells', () {
    final bytes = tableFixture([..._row(-108), ..._row(492)]);
    final xml = _document(convertLegacyWordToStructuredDocx(bytes).bytes);
    expect(
      xml.findAllElements('w:gridCol').map((e) => e.getAttribute('w:w')),
      List.filled(5, '600'),
    );
    final rows = xml.findAllElements('w:tr').toList();
    expect(
      rows.first.findAllElements('w:gridAfter').single.getAttribute('w:val'),
      '1',
    );
    expect(
      rows.last.findAllElements('w:gridBefore').single.getAttribute('w:val'),
      '1',
    );
    expect(
      rows.last.findAllElements('w:wBefore').single.getAttribute('w:w'),
      '600',
    );
    expect(
      xml.findAllElements('w:gridSpan').map((e) => e.getAttribute('w:val')),
      List.filled(4, '2'),
    );
  });

  test('row padding defaults stay separate from cell overrides and resets', () {
    List<int> padding(int code, int side, int value, {int unit = 3}) =>
        wordSprm(code, [6, 0, 1, side, unit, ...wordU16(value)]);
    for (final (next, expected) in <(List<int>, int?)>[
      ([], 108),
      (padding(0xd634, 10, 0, unit: 0), null),
      (padding(0xd634, 10, 180), 180),
    ]) {
      final source = tableFixture([
        ..._row(
          -108,
          extra: [...padding(0xd634, 10, 0), ...padding(0xd632, 2, 240)],
        ),
        ..._row(-108, extra: next),
      ]);
      final table =
          parseLegacyWordDocument(source).blocks.single as LegacyWordTable;
      expect(table.rows.first.defaultCellMargins, {
        LegacyWordBorderSide.left: 0,
        LegacyWordBorderSide.right: 0,
      });
      expect(
        table.rows.last.defaultCellMargins,
        next.isEmpty
            ? isEmpty
            : {
                LegacyWordBorderSide.left: expected,
                LegacyWordBorderSide.right: expected,
              },
      );
      final xml = _document(convertLegacyWordToStructuredDocx(source).bytes);
      final defaults = xml.findAllElements('w:tblCellMar').toList();
      expect(defaults.length, 2);
      expect(defaults.first.childElements.map((e) => e.getAttribute('w:w')), [
        '0',
        '0',
      ]);
      expect(
        defaults.last.childElements.map((e) => e.getAttribute('w:w')),
        List.filled(2, '${expected ?? 0}'),
      );
      expect(
        defaults.last.childElements.map((e) => e.getAttribute('w:type')),
        List.filled(2, expected == null ? 'nil' : 'dxa'),
      );
      final cells = xml.findAllElements('w:tc').toList();
      expect(
        cells.first
            .findAllElements('w:tcMar')
            .single
            .findElements('w:left')
            .single
            .getAttribute('w:w'),
        '240',
      );
      expect(
        cells[1]
            .findAllElements('w:tcMar')
            .single
            .findElements('w:left')
            .single
            .getAttribute('w:w'),
        '0',
      );
      expect(xml.findAllElements('w:tblInd').single.getAttribute('w:w'), '132');
    }
  });

  test('row padding reset inherits the complete base table-style chain', () {
    List<int> padding(int value) =>
        wordSprm(0xd634, [6, 0, 1, 10, 3, ...wordU16(value)]);
    final source = tableFixture(
      [
        ..._row(0, extra: [...wordSprm(0x563a, wordU16(21)), ...padding(0)]),
        ..._row(0, extra: wordSprm(0x563a, wordU16(21))),
      ],
      styles: {
        0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
        20: WordFixtureStyle(
          name: 'Base padding',
          table: true,
          tableProperties: padding(300),
        ),
        21: const WordFixtureStyle(
          name: 'Child padding',
          table: true,
          parentIndex: 20,
        ),
      },
    );
    final table =
        parseLegacyWordDocument(source).blocks.single as LegacyWordTable;
    expect(table.rows.last.defaultCellMargins, {
      LegacyWordBorderSide.left: 300,
      LegacyWordBorderSide.right: 300,
    });
    final xml = _document(convertLegacyWordToStructuredDocx(source).bytes);
    final defaults = xml.findAllElements('w:tblCellMar').toList();
    expect(defaults.first.childElements.map((e) => e.getAttribute('w:w')), [
      '0',
      '0',
    ]);
    expect(defaults.last.childElements.map((e) => e.getAttribute('w:w')), [
      '300',
      '300',
    ]);
    expect(
      xml
          .findAllElements('w:tcMar')
          .map((e) => e.findElements('w:left').single.getAttribute('w:w')),
      ['0', '0', '300', '300'],
    );
  });

  test(
    'explicit left and half-gap are ordered independently of cell widths',
    () {
      final bytes = tableFixture(
        _row(
          -108,
          extra: [
            ...wordSprm(0x9601, wordU16(720)),
            ...wordSprm(0x9602, wordU16(120)),
          ],
        ),
      );
      final table =
          parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
      expect(table.rows.single.originTwips, 600);
      expect(table.rows.single.cells.map((c) => c.widthTwips), [1200, 1200]);
      expect(
        () => parseLegacyWordDocument(
          tableFixture(_row(0, extra: wordSprm(0x9602, wordU16(-1)))),
        ),
        throwsFormatException,
      );
    },
  );
}
