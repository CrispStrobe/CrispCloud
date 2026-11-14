// SPDX-License-Identifier: MPL-2.0
// Independently authored binary LVL strings, offsets, and expected labels.

import 'dart:typed_data';

import 'list_word_fixture.dart';

class ListLiteralFixtureCase {
  const ListLiteralFixtureCase({
    required this.name,
    required this.sourceText,
    required this.text,
    required this.label,
    this.sourceOffsets = const [],
    this.offsets = const [],
    this.format = 0,
    this.start = 7,
    this.suffix = 0,
    this.flags = 0,
  });
  final String name, sourceText, text, label;
  final List<int> sourceOffsets, offsets;
  final int format, start, suffix, flags;

  Uint8List build() => listWordFixture(
    levels: [
      listFixtureLevel(
        text: sourceText,
        placeholders: sourceOffsets,
        format: format,
        start: start,
        suffix: suffix,
        flags: flags,
      ),
    ],
  );
}

final listLiteralCases = <ListLiteralFixtureCase>[
  for (var number = 1; number <= 9; number++)
    ListLiteralFixtureCase(
      name: 'literal-$number',
      sourceText: '%$number',
      text: '%$number',
      label: '%$number',
    ),
  const ListLiteralFixtureCase(
    name: 'mixed-decimal',
    sourceText: '%1 [\x00] %9',
    sourceOffsets: [5],
    text: '%1 [%1] %9',
    offsets: [4],
    label: '%1 [7] %9',
  ),
  const ListLiteralFixtureCase(
    name: 'adjacent-placeholder',
    sourceText: '\x00%1',
    sourceOffsets: [1],
    text: '%1%1',
    offsets: [0],
    label: '7%1',
  ),
  const ListLiteralFixtureCase(
    name: 'percent-before-placeholder',
    sourceText: '%\x00%1',
    sourceOffsets: [2],
    text: '%%1%1',
    offsets: [1],
    label: '%7%1',
  ),
  const ListLiteralFixtureCase(
    name: 'supplementary-before-placeholder',
    sourceText: '\u{1f600}%1 \x00',
    sourceOffsets: [6],
    text: '\u{1f600}%1 %1',
    offsets: [5],
    label: '\u{1f600}%1 7',
  ),
  const ListLiteralFixtureCase(
    name: 'xml-and-tab',
    sourceText: '<&"%1>\t\x00',
    sourceOffsets: [8],
    text: '<&"%1>\t%1',
    offsets: [7],
    label: '<&"%1>\t7',
  ),
  const ListLiteralFixtureCase(
    name: 'upper-roman',
    format: 1,
    sourceText: '%1 (\x00)',
    sourceOffsets: [5],
    text: '%1 (%1)',
    offsets: [4],
    label: '%1 (VII)',
  ),
  const ListLiteralFixtureCase(
    name: 'lower-roman',
    format: 2,
    sourceText: '%1 (\x00)',
    sourceOffsets: [5],
    text: '%1 (%1)',
    offsets: [4],
    label: '%1 (vii)',
  ),
  const ListLiteralFixtureCase(
    name: 'upper-letter',
    format: 3,
    start: 27,
    sourceText: '%1 (\x00)',
    sourceOffsets: [5],
    text: '%1 (%1)',
    offsets: [4],
    label: '%1 (AA)',
  ),
  const ListLiteralFixtureCase(
    name: 'lower-letter',
    format: 4,
    start: 28,
    sourceText: '%1 (\x00)',
    sourceOffsets: [5],
    text: '%1 (%1)',
    offsets: [4],
    label: '%1 (bb)',
  ),
  const ListLiteralFixtureCase(
    name: 'decimal-zero-legal',
    format: 22,
    start: 3,
    flags: 4,
    sourceText: '%1 (\x00)',
    sourceOffsets: [5],
    text: '%1 (%1)',
    offsets: [4],
    label: '%1 (03)',
  ),
  const ListLiteralFixtureCase(
    name: 'hebrew-legal-decimal',
    format: 45,
    flags: 4,
    sourceText: '%1 (\x00)',
    sourceOffsets: [5],
    text: '%1 (%1)',
    offsets: [4],
    label: '%1 (7)',
  ),
  const ListLiteralFixtureCase(
    name: 'hebrew-literal-only',
    format: 45,
    sourceText: '%1',
    text: '%1',
    label: '%1',
  ),
  const ListLiteralFixtureCase(
    name: 'none-with-placeholder',
    format: 255,
    sourceText: '%1-\x00',
    sourceOffsets: [4],
    text: '%1-%1',
    offsets: [3],
    label: '%1-',
  ),
  const ListLiteralFixtureCase(
    name: 'space-suffix',
    suffix: 1,
    sourceText: '%1',
    text: '%1',
    label: '%1',
  ),
  const ListLiteralFixtureCase(
    name: 'nothing-suffix',
    suffix: 2,
    sourceText: '%1',
    text: '%1',
    label: '%1',
  ),
];

/// Concatenating literal fragments must never change which character is the
/// binary placeholder. The expectations use fixed, hand-checked numerals;
/// no production formatter or converter generates the expected label.
final listLiteralMetamorphicCases = <ListLiteralFixtureCase>[
  for (final (format, start, numeral) in const [
    (0, 7, '7'),
    (22, 3, '03'),
    (1, 7, 'VII'),
    (2, 7, 'vii'),
    (3, 27, 'AA'),
    (4, 28, 'bb'),
  ])
    for (final (leftIndex, left) in const [
      '%1',
      '%9',
      '%%1',
      '%10',
      '\u{1f600}%3',
      '<%4>&',
      '\t%5',
      '%8%2',
    ].indexed)
      for (final (rightIndex, right) in const [
        '',
        '%1',
        '%9',
        '%1%2',
        '%10',
        '\u{1f600}',
        '\t',
        '<&"',
      ].indexed)
        ListLiteralFixtureCase(
          name: 'metamorphic-$format-$leftIndex-$rightIndex',
          sourceText: '$left\x00$right',
          sourceOffsets: [left.length + 1],
          text: '$left%1$right',
          offsets: [left.length],
          label: '$left$numeral$right',
          format: format,
          start: start,
        ),
];
