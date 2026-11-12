// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'structured_word_fixture.dart';
import 'table_word_fixture.dart';

/// Literal TC80/FtsWWidth_TablePart inputs. This module has no dependency on
/// the production table model or parser and is also used by native probes.
class TableWidthCase {
  const TableWidthCase(
    this.name,
    this.unit,
    this.value, {
    this.range = false,
    this.initialUnit,
    this.initialValue,
    this.resetNoWrap = false,
    this.tableStyle = false,
    this.secondValue,
    this.gridWidths,
  });
  final String name;
  final int unit, value;
  final bool range, resetNoWrap, tableStyle;
  final int? initialUnit, initialValue;
  final int? secondValue;
  final List<int>? gridWidths;
}

const tableWidthCases = [
  TableWidthCase('tc80-nil', 0, 0),
  TableWidthCase('range-nil', 0, 0, range: true),
  TableWidthCase('tc80-auto', 1, 0),
  TableWidthCase('range-auto', 1, 0, range: true),
  TableWidthCase('tc80-percent', 2, 2500),
  TableWidthCase('range-percent', 2, 2500, range: true),
  TableWidthCase('tc80-dxa', 3, 2400),
  TableWidthCase('range-dxa', 3, 2400, range: true),
  TableWidthCase('tc80-narrow', 3, 1200),
  TableWidthCase('range-narrow', 3, 1200, range: true),
  TableWidthCase('dxa-to-auto', 1, 0, initialUnit: 3, initialValue: 2400),
  TableWidthCase('auto-to-dxa', 3, 2400, initialUnit: 1, initialValue: 0),
  TableWidthCase('range-reset', 1, 0, range: true, resetNoWrap: true),
  TableWidthCase('style-auto', 1, 0, tableStyle: true),
  TableWidthCase('style-dxa', 3, 2400, tableStyle: true),
  TableWidthCase('tc80-asymmetric', 3, 1200, secondValue: 3600),
  TableWidthCase('range-asymmetric', 3, 1200, range: true, secondValue: 3600),
  TableWidthCase(
    'grid-asymmetric-control',
    3,
    1200,
    secondValue: 3600,
    gridWidths: [1200, 3600],
  ),
];

List<int> tableWidthDefinition({
  int unit = 0,
  int value = 0,
  bool noWrap = false,
  int cells = 2,
  int width = 2400,
  int moreFlags = 0,
  int? secondValue,
  List<int>? widths,
}) {
  final actual = widths ?? List.filled(cells, width);
  var edge = 0;
  final body = [
    cells,
    ...wordU16(0),
    for (final width in actual) ...wordU16(edge += width),
    for (var i = 0; i < cells; i++) ...[
      ...wordU16((unit << 9) | (noWrap ? 0x2000 : 0) | moreFlags),
      ...wordU16(i == 1 ? secondValue ?? value : value),
      ...List<int>.filled(16, 0),
    ],
  ];
  return wordSprm(0xd608, [...wordU16(body.length + 1), ...body]);
}

List<int> tablePreferredWidth(int first, int limit, int unit, int width) =>
    wordSprm(0xd635, [5, first, limit, unit, ...wordU16(width)]);

Uint8List tableWidthFixture(
  TableWidthCase item, {
  List<int> extra = const [],
  bool conditional = false,
}) {
  final properties = <int>[];
  if (item.tableStyle) {
    properties.addAll([
      ...wordSprm(0x563a, wordU16(15)),
      if (conditional) ...wordSprm(0x740a, [...wordU16(0), ...wordU16(0x20)]),
      ...wordSprm(0x7621, [0, 2, ...wordU16(2400)]),
      ...tablePreferredWidth(0, 2, item.unit, item.value),
    ]);
  } else {
    properties.addAll(
      tableWidthDefinition(
        unit: item.initialUnit ?? (item.range ? 0 : item.unit),
        value: item.initialValue ?? (item.range ? 0 : item.value),
        noWrap: !item.range,
        secondValue: item.range ? null : item.secondValue,
        widths: item.gridWidths,
      ),
    );
    if (item.range) properties.addAll(wordSprm(0xd639, [3, 0, 2, 1]));
    if (item.range || item.initialUnit != null) {
      properties.addAll(tablePreferredWidth(0, 2, item.unit, item.value));
      if (item.secondValue != null) {
        properties.addAll(
          tablePreferredWidth(1, 2, item.unit, item.secondValue!),
        );
      }
    }
    if (item.resetNoWrap) properties.addAll(wordSprm(0xd639, [3, 0, 2, 0]));
  }
  final paragraphs = [
    const TableFixtureParagraph('BODY\r'),
    const TableFixtureParagraph(
      'ALPHA BETA GAMMA DELTA EPSILON ZETA\x07',
      depth: 1,
    ),
    const TableFixtureParagraph('SECOND\x07', depth: 1),
    TableFixtureParagraph(
      '\x07',
      depth: 1,
      row: true,
      extra: [
        ...properties,
        ...wordSprm(0x3615, [1]),
        ...wordSprm(0xf614, [3, ...wordU16(4800)]),
        ...wordSprm(0xd634, [6, 0, 1, 10, 3, ...wordU16(108)]),
        ...extra,
      ],
    ),
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
          ...wordSprm(0x2431, [0]),
          ...wordSprm(0x2405, [0]),
          ...wordSprm(0x2406, [0]),
        ],
        characterProperties: [
          ...wordSprm(0x4a4f, wordU16(0)),
          ...wordSprm(0x4a43, wordU16(24)),
        ],
      ),
      if (item.tableStyle)
        15: WordFixtureStyle(
          name: 'No wrap',
          table: true,
          tableProperties: conditional
              ? wordSprm(0xd66a, [
                  5,
                  ...wordU16(1),
                  ...wordSprm(0x347d, [1]),
                ])
              : wordSprm(0x347d, [1]),
        ),
    },
    extraTablePairs: {
      15: [...wordU16(1), ...wordU16(0), ...font],
    },
    sections: [
      WordFixtureSection(paragraphs.fold(0, (sum, p) => sum + p.text.length), [
        ...wordSprm(0xb01f, wordU16(12240)),
        ...wordSprm(0xb020, wordU16(15840)),
        ...wordSprm(0xb021, wordU16(1440)),
        ...wordSprm(0xb022, wordU16(1440)),
        ...wordSprm(0x9023, wordU16(1440)),
        ...wordSprm(0x9024, wordU16(1440)),
      ]),
    ],
  );
}
