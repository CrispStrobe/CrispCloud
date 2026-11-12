// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'structured_word_fixture.dart';
import 'table_word_fixture.dart';
import 'textbox_boundary_fixture.dart';

/// Independently assembled PAPX records place a table in a separate textbox
/// story. The shape's anchor can move into a body/header table without changing
/// a single character or table property in that textbox story.
Uint8List textboxTableFixture({
  bool header = false,
  bool anchorInTable = true,
  int? marginTwips,
  bool nested = false,
}) {
  List<int> properties(TableFixtureParagraph paragraph) => [
    if (paragraph.depth > 0) ...[
      ...wordSprm(0x2416, [1]),
      ...wordSprm(0x6649, wordU32(paragraph.depth)),
    ],
    if (paragraph.depth > 1 && paragraph.cell) ...wordSprm(0x244b, [1]),
    if (paragraph.row) ...[
      ...wordSprm(paragraph.depth > 1 ? 0x244c : 0x2417, [1]),
      if (paragraph.widths.isNotEmpty)
        ...tableFixtureDefinition(paragraph.widths),
    ],
    ...paragraph.extra,
  ];

  List<int> rowProperties(int origin, int? margin) => [
    ...tableFixtureDefinition([2400], origin: origin),
    if (margin != null)
      ...wordSprm(0xd632, [6, 0, 1, 2, 3, ...wordU16(margin)]),
  ];

  final anchor = anchorInTable
      ? [
          TableFixtureParagraph(
            nested ? 'M\x08\x07' : 'M\x08\r',
            depth: 1,
            cell: nested,
          ),
          if (!nested) ...[
            const TableFixtureParagraph(
              'ANCHOR_NESTED\r',
              depth: 2,
              cell: true,
            ),
            TableFixtureParagraph(
              '\r',
              depth: 2,
              row: true,
              extra: rowProperties(360, 120),
            ),
            const TableFixtureParagraph('\x07', depth: 1, cell: true),
          ],
          TableFixtureParagraph(
            '\x07',
            depth: 1,
            row: true,
            extra: rowProperties(720, 240),
          ),
          const TableFixtureParagraph('AFTER_ANCHOR\r'),
        ]
      : [const TableFixtureParagraph('M\x08\r')];
  final box = [
    const TableFixtureParagraph('BOX\r'),
    TableFixtureParagraph(
      nested ? 'CELL\r' : 'CELL\x07',
      depth: 1,
      cell: !nested,
    ),
    if (nested) ...[
      const TableFixtureParagraph('INNER\r', depth: 2, cell: true),
      TableFixtureParagraph(
        '\r',
        depth: 2,
        row: true,
        extra: rowProperties(240, 120),
      ),
      const TableFixtureParagraph('\x07', depth: 1, cell: true),
    ],
    TableFixtureParagraph(
      '\x07',
      depth: 1,
      row: true,
      extra: rowProperties(480, marginTwips),
    ),
    const TableFixtureParagraph('AFTER_BOX\r'),
    const TableFixtureParagraph('\r'), // FTXBXS separator, outside content.
  ];
  final paragraphs = <WordFixtureFkpRun>[];
  void addStory(int offset, List<TableFixtureParagraph> content) {
    for (final paragraph in content) {
      final end = offset + paragraph.text.length * 2;
      paragraphs.add(
        WordFixtureFkpRun(offset, end, properties: properties(paragraph)),
      );
      offset = end;
    }
  }

  addStory(header ? 20480 : 16384, anchor);
  addStory(header ? 24576 : 12288, box);
  paragraphs.sort((a, b) => a.startFc.compareTo(b.startFc));
  final runs = <WordFixtureFkpRun>[];
  var previous = 8192;
  for (final paragraph in paragraphs) {
    if (paragraph.startFc > previous) {
      runs.add(WordFixtureFkpRun(previous, paragraph.startFc));
    }
    runs.add(paragraph);
    previous = paragraph.endFc;
  }
  if (previous < 28672) runs.add(WordFixtureFkpRun(previous, 28672));
  return textboxBoundaryFixture(
    [box.map((paragraph) => paragraph.text).join()],
    header: header,
    anchorText: anchor.map((paragraph) => paragraph.text).join(),
    paragraphRuns: runs,
  );
}
