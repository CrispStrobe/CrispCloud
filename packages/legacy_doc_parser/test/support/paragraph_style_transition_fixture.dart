// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'structured_word_fixture.dart';
import 'table_word_fixture.dart';

const paragraphTransientStyleKinds = <String, int>{
  'empty': 30,
  'missing': 99,
  'character': 21,
  'table': 40,
};

/// Independently authored MS-DOC 2.6.2 PIstd sequences. An intermediate
/// missing/empty/wrong-kind selection resets paragraph formatting to document
/// defaults; a later selection must leave a real paragraph style in force.
/// The stylesheet deliberately makes Normal, table, and final styles distinct.
Uint8List paragraphStyleTransitionFixture(
  String temporary, {
  String path = 'papx',
  bool historical = false,
  bool finalSelection = true,
}) {
  final index = paragraphTransientStyleKinds[temporary]!;
  const date = 30 | (9 << 6) | (14 << 11) | (11 << 16) | (126 << 20);
  final initial = wordSprm(0x4600, wordU16(index));
  final tail = <int>[
    if (historical) ...wordSprm(0x2664, [1]),
    if (finalSelection) ...wordSprm(0x4600, wordU16(20)),
    if (historical)
      ...wordSprm(0xc66f, [7, 1, ...wordU16(0), ...wordU32(date)]),
  ];
  final properties = [...initial, ...tail];
  final styles = <int, WordFixtureStyle>{
    0: WordFixtureStyle(
      name: 'Normal',
      builtinId: 0,
      paragraphProperties: [
        ...wordSprm(0xa413, wordU16(120)),
        ...wordSprm(0x840f, wordU16(720)),
        ...wordSprm(0x2403, [2]),
      ],
      characterProperties: wordSprm(0x0835, [1]),
    ),
    20: WordFixtureStyle(
      name: 'Final paragraph',
      paragraphProperties: [
        ...wordSprm(0xa413, wordU16(480)),
        ...wordSprm(0x840f, wordU16(360)),
        ...wordSprm(0x2403, [1]),
      ],
      characterProperties: wordSprm(0x0836, [1]),
    ),
    21: WordFixtureStyle(
      name: 'Character style',
      character: true,
      characterProperties: wordSprm(0x0835, [1]),
    ),
    40: WordFixtureStyle(
      name: 'Table context',
      table: true,
      paragraphProperties: [
        ...wordSprm(0xa413, wordU16(840)),
        ...wordSprm(0x840f, wordU16(1200)),
      ],
    ),
  };
  final metadata = <int, List<int>>{
    if (historical)
      51: [
        ...wordU16(0xffff),
        ...wordU16(1),
        ...wordU16(0),
        ...wordU16(5),
        for (final unit in 'Audit'.codeUnits) ...wordU16(unit),
      ],
  };
  if (path == 'table') {
    return tableFixture(
      [
        TableFixtureParagraph(
          'A\x07',
          depth: 1,
          extra: [...wordSprm(0x563a, wordU16(40)), ...properties],
        ),
        TableFixtureParagraph(
          '\x07',
          depth: 1,
          row: true,
          widths: const [2400],
          extra: wordSprm(0x563a, wordU16(40)),
        ),
      ],
      styles: styles,
      extraTablePairs: metadata,
    );
  }
  const text = 'A😀 style\r';
  final split = path == 'split-prm';
  final indirect = <int>[
    // PHugePapx requires at least ten referenced property bytes.
    ...wordSprm(0xa414, wordU16(240)),
    ...properties,
  ];
  return StructuredWordFixture(
    pieces: split
        ? const [
            WordFixturePiece('A', offset: 12288),
            WordFixturePiece('😀 style', compressed: false),
            WordFixturePiece('\r', offset: 14336, prm: 1),
          ]
        : [
            WordFixturePiece(
              text,
              compressed: false,
              prm: path == 'prm' ? 1 : 0,
            ),
          ],
    paragraphRuns: [
      WordFixtureFkpRun(
        8192,
        split ? 14337 : 8192 + text.length * 2,
        properties: switch (path) {
          'prm' => const [],
          'split-prm' => initial,
          'indirect' => wordSprm(0x6646, wordU32(0)),
          _ => properties,
        },
      ),
    ],
    prcs: [if (path == 'prm') properties, if (split) tail],
    styles: styles,
    extraTablePairs: metadata,
    extraStreams: {
      if (path == 'indirect')
        'Data': Uint8List.fromList([...wordU16(indirect.length), ...indirect]),
    },
  ).build();
}
