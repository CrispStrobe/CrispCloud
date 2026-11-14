// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'list_word_fixture.dart';
import 'structured_word_fixture.dart';

const listBooleanStyleCases = [
  'native-mark-absent',
  'native-mark-0',
  'native-mark-1',
  'native-style-80',
  'native-style-81',
  'literal-mark-absent',
  'literal-mark-0',
  'literal-mark-1',
  'literal-style-80',
  'literal-style-81',
];

Uint8List listBooleanStyleFixture(String name) {
  if (!listBooleanStyleCases.contains(name)) throw ArgumentError.value(name);
  final literal = name.startsWith('literal-');
  final operand = name.endsWith('-absent')
      ? -1
      : int.parse(name.split('-').last, radix: 16);
  final fromStyle = operand >= 0x80;
  final on = [
    for (final code in [0x0835, 0x0836]) ...wordSprm(code, [1]),
  ];
  final off = [
    for (final code in [0x0835, 0x0836]) ...wordSprm(code, [0]),
  ];
  return StructuredWordFixture(
    pieces: [WordFixturePiece('Body\r')],
    styles: {
      0: WordFixtureStyle(
        name: 'Normal',
        builtinId: 0,
        characterProperties: fromStyle ? on : const [],
      ),
    },
    characterRuns: [
      WordFixtureFkpRun(8192, 8196, properties: off),
      WordFixtureFkpRun(8196, 8197, properties: fromStyle ? const [] : on),
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
          text: literal ? '%1' : '\x00.',
          placeholders: literal ? [] : [1],
          character: operand < 0
              ? []
              : [
                  for (final code in [0x0835, 0x0836])
                    ...wordSprm(code, [operand]),
                ],
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
