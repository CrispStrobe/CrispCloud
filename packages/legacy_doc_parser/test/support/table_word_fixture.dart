// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'structured_word_fixture.dart';

/// Literal MS-DOC PAPX/TC80 records. This builder never invokes production
/// table, style, or numbering code. Each input ends at one paragraph mark.
class TableFixtureParagraph {
  const TableFixtureParagraph(
    this.text, {
    this.depth = 0,
    this.row = false,
    this.cell = false,
    this.widths = const [],
    this.extra = const [],
    this.character = const [],
  });
  final String text;
  final int depth;
  final bool row;
  final bool cell;
  final List<int> widths;
  final List<int> extra;
  final List<int> character;
}

List<int> tableFixtureDefinition(
  List<int> widths, {
  List<int>? flags,
  int origin = 0,
}) {
  var edge = origin;
  final body = <int>[
    widths.length,
    ...wordU16(origin),
    for (final width in widths) ...wordU16(edge += width),
    for (var i = 0; i < widths.length; i++) ...[
      ...wordU16(flags?[i] ?? 0),
      ...List<int>.filled(18, 0),
    ],
  ];
  return wordSprm(0xd608, [...wordU16(body.length + 1), ...body]);
}

Uint8List tableFixture(
  List<TableFixtureParagraph> paragraphs, {
  Map<int, WordFixtureStyle> styles = const {
    0: WordFixtureStyle(name: 'Normal', builtinId: 0),
  },
  List<WordFixtureSection> sections = const [],
  Map<int, List<int>> extraTablePairs = const {},
}) {
  var offset = 8192;
  final paragraphRuns = <WordFixtureFkpRun>[];
  final characterRuns = <WordFixtureFkpRun>[];
  for (final paragraph in paragraphs) {
    final end = offset + paragraph.text.length;
    paragraphRuns.add(
      WordFixtureFkpRun(
        offset,
        end,
        properties: [
          if (paragraph.depth > 0) ...[
            ...wordSprm(0x2416, [1]),
            ...wordSprm(0x6649, wordU32(paragraph.depth)),
          ],
          if (paragraph.depth > 1 && paragraph.cell) ...wordSprm(0x244b, [1]),
          if (paragraph.row) ...[
            ...wordSprm(paragraph.depth > 1 ? 0x244c : 0x2417, [1]),
            ...tableFixtureDefinition(paragraph.widths),
          ],
          ...paragraph.extra,
        ],
      ),
    );
    characterRuns.add(
      WordFixtureFkpRun(offset, end, properties: paragraph.character),
    );
    offset = end;
  }
  return StructuredWordFixture(
    pieces: [WordFixturePiece(paragraphs.map((p) => p.text).join())],
    paragraphRuns: paragraphRuns,
    characterRuns: characterRuns,
    styles: styles,
    sections: sections,
    extraTablePairs: extraTablePairs,
  ).build();
}
