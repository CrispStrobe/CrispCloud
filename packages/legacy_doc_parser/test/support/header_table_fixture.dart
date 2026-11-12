// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';
import 'table_word_fixture.dart';

/// Literal PlcfHdd/PAPX boundaries. The last content character is a closed
/// table-row marker; the following guard belongs to no editable paragraph.
Uint8List headerTableFixture({
  int slot = 1,
  bool trailingParagraph = false,
  bool tableProperties = true,
  bool closeRow = true,
  bool followingStory = false,
  String guard = '\r',
  String finalContent = '\x07',
}) {
  if (slot < 0 || slot > 5 || (slot == 5 && followingStory)) {
    throw ArgumentError('A header/footer slot and optional following slot.');
  }
  final rows = <(String, List<int>)>[
    ('STORY\r', const []),
    (
      'CELL\x07',
      tableProperties
          ? [
              ...wordSprm(0x2416, [1]),
              ...wordSprm(0x6649, wordU32(1)),
            ]
          : const [],
    ),
    (
      finalContent,
      tableProperties
          ? [
              ...wordSprm(0x2416, [1]),
              ...wordSprm(0x6649, wordU32(1)),
              if (closeRow) ...[
                ...wordSprm(0x2417, [1]),
                ...tableFixtureDefinition([2400]),
              ],
            ]
          : const [],
    ),
    if (trailingParagraph) ('AFTER\r', const []),
    (guard, const []),
    if (followingStory) ('NEIGHBOR\r\r', const []),
  ];
  final content = rows.map((row) => row.$1).join();
  final rangeLength =
      content.length - (followingStory ? 'NEIGHBOR\r\r'.length : 0);
  final cps = [0];
  var cp = 0;
  for (var index = 0; index < 12; index++) {
    if (index == slot + 6) cp += rangeLength;
    if (followingStory && index == slot + 7) cp += 'NEIGHBOR\r\r'.length;
    cps.add(cp);
  }
  var fc = 20480;
  final paragraphs = <WordFixtureFkpRun>[const WordFixtureFkpRun(8192, 20480)];
  for (final (text, properties) in rows) {
    if (text.isEmpty) continue;
    final end = fc + text.length * 2;
    paragraphs.add(WordFixtureFkpRun(fc, end, properties: properties));
    fc = end;
  }
  paragraphs.add(WordFixtureFkpRun(fc, 28672));
  return storyWordFixture(
    main: 'BODY\r',
    headers: '$content\r',
    paragraphRuns: paragraphs,
    tablePairs: {
      11: storyPlc([...cps, 0xffffffff]),
    },
  );
}
