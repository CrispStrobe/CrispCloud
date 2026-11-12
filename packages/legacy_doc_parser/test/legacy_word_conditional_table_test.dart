// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

List<int> _shading(int value) => [
  ...wordU32(0xffffffff),
  value,
  value,
  value,
  0,
  0,
  0,
];
List<int> _shade(int value) => wordSprm(0xd687, [10, ..._shading(value)]);
List<int> _condition(int mask, List<int> properties) =>
    wordSprm(0xd66a, [properties.length + 2, ...wordU16(mask), ...properties]);

Uint8List _fixture(
  List<int> style, {
  int rows = 3,
  int columns = 3,
  int options = 0x1e0,
  List<int> rowExtra = const [],
  bool descriptors = false,
  Map<int, WordFixtureStyle> extraStyles = const {},
  int parent = 0xfff,
}) => tableFixture(
  [
    for (var r = 0; r < rows; r++) ...[
      for (var c = 0; c < columns; c++)
        TableFixtureParagraph('$r,$c\x07', depth: 1, cell: true),
      TableFixtureParagraph(
        '\x07',
        depth: 1,
        row: true,
        widths: descriptors ? List.filled(columns, 1000) : const [],
        extra: [
          ...wordSprm(0x563a, wordU16(20)),
          ...wordSprm(0x740a, [...wordU16(0), ...wordU16(options)]),
          if (!descriptors) ...wordSprm(0x7621, [0, columns, ...wordU16(1000)]),
          ...rowExtra,
        ],
      ),
    ],
  ],
  styles: {
    0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
    ...extraStyles,
    20: WordFixtureStyle(
      name: 'Conditional cells',
      table: true,
      parentIndex: parent,
      tableProperties: style,
    ),
  },
);

List<List<String?>> _colors(LegacyWordDocument doc) =>
    (doc.blocks.single as LegacyWordTable).rows
        .map((r) => r.cells.map((c) => c.shading?.backgroundHex).toList())
        .toList();

void main() {
  test(
    'all twelve native conditions retain identity and cascade into cells',
    () {
      final bytes = _fixture([
        ..._shade(240),
        for (var i = 0; i < 12; i++) ..._condition(1 << i, _shade(i + 1)),
      ]);
      final doc = parseLegacyWordDocument(bytes);
      expect(doc.tableStyles.single.conditions, hasLength(12));
      // Horizontal bands < vertical bands < edge columns < edge rows < corners.
      expect(_colors(doc), [
        ['0A0A0A', '010101', '090909'],
        ['030303', '050505', '040404'],
        ['0C0C0C', '020202', '0B0B0B'],
      ]);
      final archive = ZipDecoder().decodeBytes(
        convertLegacyWordToStructuredDocx(bytes).bytes,
      );
      final styles = XmlDocument.parse(
        utf8.decode(archive.findFile('word/styles.xml')!.content),
      );
      final tableStyle = styles
          .findAllElements('w:style')
          .singleWhere((e) => e.getAttribute('w:type') == 'table');
      expect(tableStyle.getAttribute('w:styleId'), 'LegacyTable20');
      expect(
        tableStyle
            .findAllElements('w:tblStylePr')
            .map((e) => e.getAttribute('w:type'))
            .toSet(),
        LegacyWordTableCondition.values.map((e) => e.name).toSet(),
      );
      final main = XmlDocument.parse(
        utf8.decode(archive.findFile('word/document.xml')!.content),
      );
      expect(
        main.findAllElements('w:tblStyle').single.getAttribute('w:val'),
        'LegacyTable20',
      );
      expect(
        main.findAllElements('w:tblLook').single.getAttribute('w:firstRow'),
        '1',
      );
      expect(main.findAllElements('w:shd'), hasLength(9));
    },
  );

  test('band sizes and disabled bands are applied independently', () {
    final style = [
      ..._shade(240),
      ...wordSprm(0x3489, [2]),
      ..._condition(0x10, _shade(1)),
      ..._condition(0x20, _shade(2)),
    ];
    var doc = parseLegacyWordDocument(
      _fixture(style, rows: 1, columns: 5, options: 0x200),
    );
    expect(_colors(doc).single, [
      '010101',
      '010101',
      '020202',
      '020202',
      '010101',
    ]);
    doc = parseLegacyWordDocument(
      _fixture(style, rows: 1, columns: 5, options: 0x600),
    );
    expect(_colors(doc).single, List.filled(5, 'F0F0F0'));
  });

  test('single-row single-column first and northwest conditions win', () {
    final doc = parseLegacyWordDocument(
      _fixture(
        [for (var i = 0; i < 12; i++) ..._condition(1 << i, _shade(i + 1))],
        rows: 1,
        columns: 1,
      ),
    );
    expect(_colors(doc), [
      ['0A0A0A'],
    ]);
  });

  test(
    'base inheritance retains condition differences and direct shading wins',
    () {
      final doc = parseLegacyWordDocument(
        _fixture(
          [..._condition(1, _shade(3))],
          rows: 1,
          columns: 1,
          parent: 19,
          extraStyles: {
            19: WordFixtureStyle(
              name: 'Base',
              table: true,
              tableProperties: [..._shade(1), ..._condition(1, _shade(2))],
            ),
          },
          rowExtra: wordSprm(0xd670, [10, ..._shading(4)]),
        ),
      );
      expect(_colors(doc), [
        ['040404'],
      ]);
      expect(doc.tableStyles.singleWhere((s) => s.id == 20).basedOn, 19);
    },
  );

  test('raw nil inherits a conditional shade, raw clear overrides it', () {
    var doc = parseLegacyWordDocument(
      _fixture(
        _condition(1, _shade(5)),
        rows: 1,
        columns: 1,
        rowExtra: wordSprm(0xd670, [
          10,
          ...wordU32(0xffffffff),
          ...wordU32(0xffffffff),
          ...wordU16(0xffff),
        ]),
      ),
    );
    expect(_colors(doc), [
      ['050505'],
    ]);
    doc = parseLegacyWordDocument(
      _fixture(
        _condition(1, _shade(5)),
        rows: 1,
        columns: 1,
        rowExtra: wordSprm(0xd670, [
          10,
          ...wordU32(0xff000000),
          ...wordU32(0xff000000),
          ...wordU16(0),
        ]),
      ),
    );
    expect(_colors(doc), [
      [null],
    ]);
    expect(
      (doc.blocks.single as LegacyWordTable)
          .rows
          .single
          .cells
          .single
          .shading!
          .pattern,
      'clear',
    );
  });

  test('native cell alignment and border rules are emitted', () {
    final border = [0, 0, 255, 0, 12, 1, 0, 0];
    final bytes = _fixture(
      _condition(1, [
        ...wordSprm(0x347c, [2]),
        ...wordSprm(0x347d, [1]),
        ...wordSprm(0xd47f, [8, ...border]),
      ]),
      rows: 1,
      columns: 1,
    );
    final cell =
        (parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable)
            .rows
            .single
            .cells
            .single;
    expect(cell.formatting.verticalAlignment, LegacyWordCellAlignment.bottom);
    expect(cell.formatting.noWrap, true);
    expect(
      cell.formatting.borders[LegacyWordTableBorderSide.top]!.colorHex,
      '0000FF',
    );
    final archive = ZipDecoder().decodeBytes(
      convertLegacyWordToStructuredDocx(bytes).bytes,
    );
    final main = XmlDocument.parse(
      utf8.decode(archive.findFile('word/document.xml')!.content),
    );
    expect(
      main
          .findAllElements('w:tcPr')
          .single
          .findElements('w:vAlign')
          .single
          .getAttribute('w:val'),
      'bottom',
    );
    expect(
      main
          .findAllElements('w:tcBorders')
          .single
          .findElements('w:top')
          .single
          .getAttribute('w:sz'),
      '12',
    );
  });

  for (final (name, style) in [
    ('combined condition', _condition(3, _shade(1))),
    ('nested condition', _condition(1, _condition(2, _shade(1)))),
    ('zero band', wordSprm(0x3488, [0])),
    ('invalid alignment', wordSprm(0x347c, [3])),
  ]) {
    test(
      'rejects $name',
      () => expect(
        () => parseLegacyWordDocument(_fixture(style, rows: 1, columns: 1)),
        throwsFormatException,
      ),
    );
  }

  test('table style inheritance cycles are rejected', () {
    expect(
      () => parseLegacyWordDocument(
        _fixture(
          [],
          rows: 1,
          columns: 1,
          parent: 19,
          extraStyles: {
            19: const WordFixtureStyle(
              name: 'Cycle',
              table: true,
              parentIndex: 20,
            ),
          },
        ),
      ),
      throwsFormatException,
    );
  });
}
