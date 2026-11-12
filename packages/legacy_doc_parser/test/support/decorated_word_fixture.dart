// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'structured_word_fixture.dart';

Uint8List paragraphDecorationFixture(
  List<int> properties, {
  List<int> inherited = const [],
  int? defaultTabStopTwips,
}) {
  final dop = Uint8List(84);
  if (defaultTabStopTwips != null) {
    ByteData.sublistView(dop).setUint16(10, defaultTabStopTwips, Endian.little);
  }
  return StructuredWordFixture(
    pieces: const [WordFixturePiece('Left\tRight\r')],
    styles: {
      0: WordFixtureStyle(
        name: 'Normal',
        builtinId: 0,
        paragraphProperties: inherited,
      ),
    },
    paragraphRuns: [WordFixtureFkpRun(8192, 8203, properties: properties)],
    extraTablePairs: {if (defaultTabStopTwips != null) 31: dop},
  ).build();
}

List<int> wordTabChange({
  List<int> deleted = const [],
  List<int>? distances,
  List<(int, int, int)> added = const [],
  bool close = false,
  bool extended = false,
}) {
  final data = [
    deleted.length,
    for (final position in deleted) ...wordU16(position),
    if (close)
      for (var i = 0; i < deleted.length; i++) ...wordU16(distances?[i] ?? 25),
    added.length,
    for (final tab in added) ...wordU16(tab.$1),
    for (final tab in added) tab.$2 | (tab.$3 << 3),
  ];
  return wordSprm(close ? 0xc615 : 0xc60d, [
    extended ? 255 : data.length,
    ...data,
  ]);
}

List<int> wordShading({
  int foreground = 0x00332211,
  int background = 0x00ccbbaa,
  int pattern = 0,
}) => [...wordU32(foreground), ...wordU32(background), ...wordU16(pattern)];

List<int> wordParagraphShading({
  int foreground = 0x00332211,
  int background = 0x00ccbbaa,
  int pattern = 0,
}) => wordSprm(0xc64d, [
  10,
  ...wordShading(
    foreground: foreground,
    background: background,
    pattern: pattern,
  ),
]);

List<int> wordParagraphBorder(
  int side, {
  bool old = false,
  int color = 0x00332211,
  int width = 8,
  int type = 1,
  int spacing = 0,
  bool shadow = false,
  bool frame = false,
  int unused = 0,
}) {
  final flags = spacing | (shadow ? 32 : 0) | (frame ? 64 : 0);
  return wordSprm(
    old ? (side == 5 ? 0x6629 : 0x6424 + side) : 0xc64e + side,
    old
        ? [width, type, color, flags | unused]
        : [8, ...wordU32(color), width, type, flags, unused],
  );
}

Uint8List tableDecorationFixture(List<int> shading, {int cells = 2}) {
  final text =
      '${[for (var i = 0; i < cells; i++) 'C$i\x07'].join()}\x07After\r';
  final rowEnd = 8192 + text.length - 6;
  final definition = [
    cells,
    for (var i = 0; i <= cells; i++) ...wordU16(i * 360),
  ];
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text)],
    paragraphRuns: [
      WordFixtureFkpRun(8192, rowEnd - 1, properties: wordSprm(0x2416, [1])),
      WordFixtureFkpRun(
        rowEnd - 1,
        rowEnd,
        properties: [
          ...wordSprm(0x2416, [1]),
          ...wordSprm(0x2417, [1]),
          ...wordSprm(0xd608, [
            ...wordU16(definition.length + 1),
            ...definition,
          ]),
          ...shading,
        ],
      ),
      WordFixtureFkpRun(rowEnd, 8192 + text.length),
    ],
  ).build();
}
