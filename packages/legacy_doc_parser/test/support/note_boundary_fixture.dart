// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';
import 'table_word_fixture.dart';

/// Literal note text and expected top-level block kinds. CRs inside each PLC
/// range are content; the one outside the range belongs to the story boundary.
const noteBoundaryCases = <String, (String, List<String>)>{
  'plain': ('\x02NOTE\r', ['p']),
  'empty': ('\x02\r', ['p']),
  'trailing-blank': ('\x02NOTE\r\r', ['p', 'p']),
  'two-trailing-blanks': ('\x02NOTE\r\r\r', ['p', 'p', 'p']),
  'table': ('\x02NOTE\rCell\x07\x07', ['p', 'tbl']),
  'table-blank': ('\x02NOTE\rCell\x07\x07\r', ['p', 'tbl', 'p']),
  'table-two-blanks': ('\x02NOTE\rCell\x07\x07\r\r', ['p', 'tbl', 'p', 'p']),
  'table-text': ('\x02NOTE\rCell\x07\x07TAIL\r', ['p', 'tbl', 'p']),
};

Uint8List noteBoundaryFixture(
  String text, {
  bool endnote = false,
  bool closeRow = true,
  String storyGuard = '\r',
}) {
  const main = 'BODY\x02\r';
  final offset = endnote ? 22528 : 8192;
  final cellEnd = text.indexOf('\x07');
  final paragraphRuns = <WordFixtureFkpRun>[];
  if (cellEnd != -1) {
    final cellStart = text.lastIndexOf('\r', cellEnd) + 1;
    final cellStartFc = offset + cellStart * 2;
    final rowStartFc = offset + (cellEnd + 1) * 2;
    final tableEndFc = rowStartFc + 2;
    paragraphRuns.addAll([
      WordFixtureFkpRun(8192, cellStartFc),
      WordFixtureFkpRun(
        cellStartFc,
        rowStartFc,
        properties: wordSprm(0x2416, [1]),
      ),
      WordFixtureFkpRun(
        rowStartFc,
        tableEndFc,
        properties: [
          ...wordSprm(0x2416, [1]),
          if (closeRow) ...wordSprm(0x2417, [1]),
          ...tableFixtureDefinition([2400]),
        ],
      ),
      WordFixtureFkpRun(tableEndFc, 28672),
    ]);
  }
  return storyWordFixture(
    main: main,
    footnotes: endnote ? '' : '$text$storyGuard',
    endnotes: endnote ? '$text$storyGuard' : '',
    tablePairs: {
      endnote ? 46 : 2: storyPlc([4, main.length], wordU16(1)),
      endnote ? 47 : 3: storyPlc([0, text.length, 0xffffffff]),
    },
    paragraphRuns: paragraphRuns,
  );
}
