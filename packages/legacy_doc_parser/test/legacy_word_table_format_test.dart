// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';
import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

List<int> _margin(
  int code,
  int first,
  int limit,
  int mask,
  int width, {
  int unit = 3,
}) => wordSprm(code, [6, first, limit, mask, unit, ...wordU16(width)]);

List<TableFixtureParagraph> _row(List<int> extra) => [
  const TableFixtureParagraph('Cell\x07', depth: 1, cell: true),
  TableFixtureParagraph(
    '\x07',
    depth: 1,
    row: true,
    widths: const [1800],
    extra: extra,
  ),
];

XmlElement _cellXml(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return XmlDocument.parse(
    utf8.decode(archive.findFile('word/document.xml')!.content),
  ).findAllElements('w:tcPr').single;
}

void main() {
  test('native noWrap uses OnOffOnly values for true and explicit false', () {
    for (final nowrap in [false, true]) {
      final bytes = tableFixture(
        _row(tableFixtureDefinition([1800], flags: [nowrap ? 1 << 13 : 0])),
      );
      final cell = _cellXml(convertLegacyWordToStructuredDocx(bytes).bytes);
      expect(
        cell.getElement('w:noWrap')!.getAttribute('w:val'),
        nowrap ? 'on' : 'off',
      );
    }
  });

  test('source default margins are explicit and independent of half-gap', () {
    final bytes = tableFixture(
      _row([
        ...wordSprm(0x9601, wordU16(720)),
        ...wordSprm(0x9602, wordU16(120)),
      ]),
    );
    final row =
        (parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable)
            .rows
            .single;
    expect((row.originTwips, row.halfGapTwips), (600, 120));
    expect(row.cells.single.formatting.margins, {
      LegacyWordBorderSide.top: 0,
      LegacyWordBorderSide.left: 108,
      LegacyWordBorderSide.bottom: 0,
      LegacyWordBorderSide.right: 108,
    });
    final margins = _cellXml(
      convertLegacyWordToStructuredDocx(bytes).bytes,
    ).getElement('w:tcMar')!;
    expect(margins.getElement('w:left')!.getAttribute('w:w'), '108');
    expect(margins.getElement('w:right')!.getAttribute('w:w'), '108');
    expect(margins.getElement('w:top')!.getAttribute('w:w'), '0');
  });

  test('inserting a cell shifts existing shading and margin overrides', () {
    final bytes = tableFixture([
      const TableFixtureParagraph('New\x07', depth: 1, cell: true),
      const TableFixtureParagraph('Original\x07', depth: 1, cell: true),
      TableFixtureParagraph(
        '\x07',
        depth: 1,
        row: true,
        widths: const [1800],
        extra: [
          ..._margin(0xd632, 0, 1, 8, 240),
          ...wordSprm(0xd612, [10, ...wordU32(0xff000000), 255, 0, 0, 0, 0, 0]),
          ...wordSprm(0x7621, [0, 1, ...wordU16(900)]),
        ],
      ),
    ]);
    final cells =
        (parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable)
            .rows
            .single
            .cells;
    expect(cells.map((c) => c.widthTwips), [900, 1800]);
    expect(cells.map((c) => c.formatting.margins[LegacyWordBorderSide.right]), [
      108,
      240,
    ]);
    expect(cells.map((c) => c.shading?.backgroundHex), [null, 'FF0000']);
  });

  test('per-side row defaults and zero/nil cell overrides remain distinct', () {
    final bytes = tableFixture(
      _row([
        ..._margin(0xd634, 0, 1, 10, 240),
        ..._margin(0xd632, 0, 1, 2, 0),
        ..._margin(0xd632, 0, 1, 4, 0, unit: 0),
      ]),
    );
    final cell =
        (parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable)
            .rows
            .single
            .cells
            .single;
    expect(cell.formatting.margins[LegacyWordBorderSide.right], 240);
    expect(cell.formatting.margins[LegacyWordBorderSide.left], 0);
    expect(
      cell.formatting.margins.containsKey(LegacyWordBorderSide.bottom),
      true,
    );
    expect(cell.formatting.margins[LegacyWordBorderSide.bottom], null);
    final margins = _cellXml(
      convertLegacyWordToStructuredDocx(bytes).bytes,
    ).getElement('w:tcMar')!;
    expect(margins.getElement('w:left')!.getAttribute('w:type'), 'dxa');
    expect(margins.getElement('w:bottom')!.getAttribute('w:type'), 'nil');
  });

  test('TC80 borders survive as actual editable cell borders', () {
    final operand = [
      1,
      ...wordU16(-108),
      ...wordU16(1692),
      ...wordU16(2 << 7),
      ...wordU16(0),
      for (var side = 0; side < 4; side++) ...[4, 1, 6, 0],
    ];
    final bytes = tableFixture(
      _row(wordSprm(0xd608, [...wordU16(operand.length + 1), ...operand])),
    );
    final cell =
        (parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable)
            .rows
            .single
            .cells
            .single;
    expect(cell.formatting.verticalAlignment, LegacyWordCellAlignment.bottom);
    expect(cell.formatting.borders, hasLength(4));
    expect(
      cell.formatting.borders.values.map(
        (b) => (b.style, b.widthEighthPoints, b.colorHex),
      ),
      List.filled(4, ('single', 4, 'FF0000')),
    );
    final xml = _cellXml(convertLegacyWordToStructuredDocx(bytes).bytes);
    expect(
      xml
          .getElement('w:tcBorders')!
          .childElements
          .map((e) => e.getAttribute('w:sz')),
      List.filled(4, '4'),
    );
    expect(xml.childElements.map((e) => e.name.local), [
      'tcW',
      'tcBorders',
      'noWrap',
      'tcMar',
      'vAlign',
    ]);
  });

  test(
    'cell border updates apply in order and nil remains an explicit reset',
    () {
      final bytes = tableFixture(
        _row([
          ...wordSprm(0xd62f, [11, 0, 1, 1, 0, 0, 255, 0, 8, 1, 0, 0]),
          ...wordSprm(0xd620, [7, 0, 1, 2, ...wordU32(0xffffffff)]),
        ]),
      );
      final cell =
          (parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable)
              .rows
              .single
              .cells
              .single;
      expect(
        cell
            .formatting
            .borders[LegacyWordTableBorderSide.top]!
            .widthEighthPoints,
        8,
      );
      expect(
        cell.formatting.borders[LegacyWordTableBorderSide.left]!.style,
        'nil',
      );
      final borders = _cellXml(
        convertLegacyWordToStructuredDocx(bytes).bytes,
      ).getElement('w:tcBorders')!;
      expect(borders.getElement('w:top')!.getAttribute('w:color'), '0000FF');
      expect(borders.getElement('w:left')!.getAttribute('w:val'), 'nil');
    },
  );

  for (final (label, operand) in [
    ('percent margin', _margin(0xd632, 0, 1, 2, 100, unit: 2)),
    ('oversized margin', _margin(0xd632, 0, 1, 2, 31681)),
    ('invalid sides', _margin(0xd632, 0, 1, 16, 120)),
    ('invalid default range', _margin(0xd634, 1, 2, 2, 120)),
    ('nonzero nil', _margin(0xd632, 0, 1, 2, 1, unit: 0)),
  ]) {
    test(
      'rejects $label',
      () => expect(
        () => parseLegacyWordDocument(tableFixture(_row(operand))),
        throwsFormatException,
      ),
    );
  }
}
