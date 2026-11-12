// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'structured_word_fixture.dart';
import 'table_word_fixture.dart';

class TableBorderCase {
  const TableBorderCase(
    this.name, {
    this.old = false,
    this.beforeDefinition = false,
    this.cellBorder = 'none',
    this.rangeBorder,
    this.coloredEdges = false,
    this.reset = false,
  });
  final String name;
  final bool old;
  final bool beforeDefinition;
  final String cellBorder;
  final String? rangeBorder;
  final bool coloredEdges;
  final bool reset;
}

const tableBorderCases = [
  TableBorderCase('old-after', old: true),
  TableBorderCase('old-before', old: true, beforeDefinition: true),
  TableBorderCase('old-nil', old: true, cellBorder: 'nil'),
  TableBorderCase('old-explicit', old: true, cellBorder: 'explicit'),
  TableBorderCase('modern-after'),
  TableBorderCase('modern-before', beforeDefinition: true),
  TableBorderCase('modern-nil', cellBorder: 'nil'),
  TableBorderCase('modern-explicit', cellBorder: 'explicit'),
  TableBorderCase('range-nil', rangeBorder: 'nil'),
  TableBorderCase('range-none', cellBorder: 'explicit', rangeBorder: 'none'),
  TableBorderCase('interior-colors', coloredEdges: true),
  TableBorderCase('row-reset', reset: true),
];

List<int> tableBorderDefinition(String mode) {
  final body = [
    2,
    ...wordU16(0),
    ...wordU16(2000),
    ...wordU16(4000),
    for (var i = 0; i < 2; i++) ...[
      ...wordU16(0),
      ...wordU16(0),
      for (var side = 0; side < 4; side++)
        ...(mode == 'nil'
            ? [255, 255, 255, 255]
            : mode == 'explicit' && side == 0
            ? [16, 3, 11, 0]
            : [0, 0, 0, 0]),
    ],
  ];
  return wordSprm(0xd608, [...wordU16(body.length + 1), ...body]);
}

List<int> tableBorderProperties({
  bool old = false,
  bool colors = false,
  bool reset = false,
}) => wordSprm(old ? 0xd605 : 0xd613, [
  old ? 24 : 48,
  for (var side = 0; side < 6; side++)
    ...(old
        ? [
            reset ? 0 : (colors ? (side + 1) * 8 : 8),
            reset ? 0 : 1,
            colors ? [6, 4, 2, 7, 5, 3][side] : 6,
            0,
          ]
        : [
            ...const [
              [255, 0, 0],
              [0, 255, 0],
              [0, 0, 255],
              [255, 255, 0],
              [255, 0, 255],
              [0, 255, 255],
            ][colors ? side : 0],
            0,
            reset ? 0 : (colors ? (side + 1) * 8 : 8),
            reset ? 0 : 1,
            0,
            0,
          ]),
]);

Uint8List tableBorderFixture(TableBorderCase value) {
  final paragraphs = <TableFixtureParagraph>[
    const TableFixtureParagraph('BODY\r'),
    for (var row = 0; row < (value.reset ? 1 : 2); row++) ...[
      TableFixtureParagraph('R${row}A\x07', depth: 1, cell: true),
      TableFixtureParagraph('R${row}B\x07', depth: 1, cell: true),
      TableFixtureParagraph(
        '\x07',
        depth: 1,
        row: true,
        extra: [
          if (value.beforeDefinition)
            ...tableBorderProperties(
              old: value.old,
              colors: value.coloredEdges,
            ),
          ...tableBorderDefinition(value.cellBorder),
          if (!value.beforeDefinition)
            ...tableBorderProperties(
              old: value.old,
              colors: value.coloredEdges,
            ),
          if (value.rangeBorder != null)
            ...wordSprm(0xd620, [
              7,
              0,
              2,
              1,
              ...List.filled(4, value.rangeBorder == 'nil' ? 255 : 0),
            ]),
          if (value.reset) ...tableBorderProperties(reset: true),
          ...wordSprm(0xd634, [6, 0, 1, 10, 3, ...wordU16(108)]),
          ...wordSprm(0x9407, wordU16(960)),
        ],
      ),
    ],
    const TableFixtureParagraph('AFTER\r'),
  ];
  final font = [
    ...List<int>.filled(40, 0),
    for (final unit in 'Liberation Serif'.codeUnits) ...wordU16(unit),
    ...wordU16(0),
  ];
  font[0] = font.length - 1;
  return tableFixture(
    paragraphs,
    styles: {
      0: WordFixtureStyle(
        name: 'Normal',
        builtinId: 0,
        paragraphProperties: [
          ...wordSprm(0x6412, [...wordU16(-240), ...wordU16(0)]),
          ...wordSprm(0xa413, wordU16(0)),
          ...wordSprm(0xa414, wordU16(0)),
        ],
        characterProperties: [
          ...wordSprm(0x4a4f, wordU16(0)),
          ...wordSprm(0x4a43, wordU16(24)),
        ],
      ),
    },
    extraTablePairs: {
      15: [...wordU16(1), ...wordU16(0), ...font],
    },
    sections: [
      WordFixtureSection(paragraphs.fold(0, (n, p) => n + p.text.length), [
        ...wordSprm(0xb01f, wordU16(7200)),
        ...wordSprm(0xb020, wordU16(6000)),
        ...wordSprm(0xb021, wordU16(720)),
        ...wordSprm(0xb022, wordU16(720)),
        ...wordSprm(0x9023, wordU16(720)),
        ...wordSprm(0x9024, wordU16(720)),
      ]),
    ],
  );
}
