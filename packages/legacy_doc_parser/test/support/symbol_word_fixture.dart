// SPDX-License-Identifier: MPL-2.0
// Independently authored MS-DOC glyph/property controls; no parser output.
import 'dart:typed_data';
import 'structured_word_fixture.dart';

const symbolFixtureFontNames = ['Ordinary Face', 'Symbol', 'Wingdings'];

List<int> _fonts(List<String> names) => [
  ...wordU16(names.length),
  ...wordU16(0),
  for (final name in names) ...[
    41 + name.length * 2,
    ...List.filled(39, 0),
    for (final unit in name.codeUnits) ...wordU16(unit),
    ...wordU16(0),
  ],
];

List<int> symbolOperands({int font = 1, int code = 0xf061}) =>
    wordSprm(0x6a09, [...wordU16(font), ...wordU16(code)]);

Uint8List symbolWordFixture({
  String text = 'A(B\r',
  int start = 1,
  int end = 2,
  List<int>? operations,
  List<int> inherited = const [],
  List<String> fonts = symbolFixtureFontNames,
  Map<int, List<int>> pairs = const {},
}) => StructuredWordFixture(
  pieces: [WordFixturePiece(text, compressed: false)],
  styles: {
    0: WordFixtureStyle(
      name: 'Normal',
      builtinId: 0,
      characterProperties: [...wordSprm(0x4a4f, wordU16(0)), ...inherited],
    ),
  },
  characterRuns: [
    if (start > 0) WordFixtureFkpRun(8192, 8192 + start * 2),
    WordFixtureFkpRun(
      8192 + start * 2,
      8192 + end * 2,
      properties: operations ?? symbolOperands(),
    ),
    WordFixtureFkpRun(8192 + end * 2, 8192 + text.length * 2),
  ],
  extraTablePairs: {15: _fonts(fonts), ...pairs},
).build();
