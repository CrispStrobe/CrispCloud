// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'structured_word_fixture.dart';

List<int> listFixtureLevel({
  int level = 0,
  int format = 0,
  int start = 1,
  String? text,
  List<int>? placeholders,
  int flags = 0,
  int restart = 0,
  int suffix = 0,
  List<int> paragraph = const [],
  List<int> character = const [],
}) {
  final template = text ?? '${String.fromCharCode(level)}.';
  final positions = placeholders ?? [1];
  return [
    ...wordU32(start),
    format,
    flags,
    ...positions,
    ...List.filled(9 - positions.length, 0),
    suffix,
    ...wordU32(0),
    ...wordU32(0),
    character.length,
    paragraph.length,
    restart,
    0,
    ...paragraph,
    ...character,
    ...wordU16(template.length),
    for (final unit in template.codeUnits) ...wordU16(unit),
  ];
}

List<int> listFixtureDefinitions(
  List<List<int>> levels, {
  int sourceId = 42,
  int style = 0x0fff,
}) => [
  ...wordU16(1),
  ...wordU32(sourceId),
  ...wordU32(0),
  for (var i = 0; i < 9; i++) ...wordU16(style),
  levels.length == 1 ? 1 : 0,
  0,
  for (final level in levels) ...level,
];

List<int> listFixtureInstances({
  int sourceId = 42,
  List<List<int>> overrides = const [],
}) => [
  ...wordU32(1),
  ...wordU32(sourceId),
  ...wordU32(0),
  ...wordU32(0),
  overrides.length,
  0,
  0,
  0,
  ...wordU32(0xffffffff),
  for (final value in overrides) ...value,
];

Uint8List listWordFixture({
  String text = 'Item\r',
  List<List<int>>? levels,
  List<int>? instances,
  List<int>? paragraph,
  Map<int, WordFixtureStyle> styles = const {
    0: WordFixtureStyle(name: 'Normal', builtinId: 0),
  },
  int listStyle = 0x0fff,
  Map<int, List<int>> extraTablePairs = const {},
}) {
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text)],
    styles: styles,
    paragraphRuns: [
      WordFixtureFkpRun(
        8192,
        8192 + text.length,
        properties:
            paragraph ??
            [
              ...wordSprm(0x460b, wordU16(1)),
              ...wordSprm(0x260a, [0]),
            ],
      ),
    ],
    extraTablePairs: {
      ...extraTablePairs,
      73: listFixtureDefinitions(
        levels ?? [listFixtureLevel()],
        style: listStyle,
      ),
      74: instances ?? listFixtureInstances(),
    },
  ).build(
    mutate: (word, table) {
      // The FIB count excludes the LVL array physically following PlfLst.
      word.setUint32(158 + 73 * 8, 30, Endian.little);
    },
  );
}
