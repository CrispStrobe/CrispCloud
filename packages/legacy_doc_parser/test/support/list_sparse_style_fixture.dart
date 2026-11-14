// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'list_word_fixture.dart';
import 'structured_word_fixture.dart';

/// Each property has an enabled paragraph mark, an explicitly reset body,
/// and an independent absent/reset/set LVL override.
const listSparseStyleProperties = {
  'allCaps': (0x083b, [1], [0], 'caps', '1', '0', 'text-transform:uppercase'),
  'smallCaps': (
    0x083a,
    [1],
    [0],
    'smallCaps',
    '1',
    '0',
    'font-variant:small-caps',
  ),
  'strike': (
    0x0837,
    [1],
    [0],
    'strike',
    '1',
    '0',
    'text-decoration:line-through',
  ),
  'doubleStrike': (
    0x2a53,
    [1],
    [0],
    'dstrike',
    '1',
    '0',
    'text-decoration-style:double',
  ),
  'hidden': (0x083c, [1], [0], 'vanish', '1', '0', ''),
  'underline': (
    0x2a3e,
    [3],
    [0],
    'u',
    'double',
    'none',
    'text-decoration-style:double',
  ),
  'verticalAlign': (
    0x2a48,
    [2],
    [0],
    'vertAlign',
    'subscript',
    'baseline',
    'vertical-align:sub',
  ),
  'kerning': (0x484b, [8, 0], [0, 0], 'kern', '8', '0', 'font-kerning:normal'),
};

final listSparseStyleCases = List<String>.unmodifiable([
  for (final kind in ['native', 'literal'])
    for (final property in listSparseStyleProperties.keys)
      for (final state in ['absent', 'reset', 'set'])
        '$kind-sparse-$property-$state',
]);

Uint8List listSparseStyleFixture(String name) {
  if (!listSparseStyleCases.contains(name)) throw ArgumentError.value(name);
  final parts = name.split('-');
  final literal = parts[0] == 'literal', state = parts[3];
  final property = listSparseStyleProperties[parts[2]]!;
  final enabled = wordSprm(property.$1, property.$2);
  final reset = wordSprm(property.$1, property.$3);
  return StructuredWordFixture(
    pieces: [WordFixturePiece('Body\r')],
    characterRuns: [
      WordFixtureFkpRun(8192, 8196, properties: reset),
      WordFixtureFkpRun(
        8196,
        8197,
        properties: [...enabled, ...wordSprm(0x4a43, wordU16(32))],
      ),
    ],
    paragraphRuns: [
      WordFixtureFkpRun(
        8192,
        8197,
        properties: [
          ...wordSprm(0x460b, wordU16(1)),
          ...wordSprm(0x260a, [0]),
        ],
      ),
    ],
    extraTablePairs: {
      73: listFixtureDefinitions([
        listFixtureLevel(
          start: 7,
          text: literal ? '%1 abc' : '\x00 abc',
          placeholders: literal ? [] : [1],
          character: state == 'absent'
              ? []
              : state == 'reset'
              ? reset
              : enabled,
          paragraph: [
            ...wordSprm(0x845e, wordU16(720)),
            ...wordSprm(0x8460, wordU16(0xfe98)),
          ],
        ),
      ]),
      74: listFixtureInstances(),
    },
  ).build(mutate: (word, _) => word.setUint32(158 + 73 * 8, 30, Endian.little));
}
