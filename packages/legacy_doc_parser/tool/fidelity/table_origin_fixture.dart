// SPDX-License-Identifier: MPL-2.0
// Literal binary fixtures for independent DOC/DOCX table-origin comparisons.
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/structured_word_fixture.dart';
import '../../test/support/table_word_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply an output directory.');
  final root = Directory(arguments.single)..createSync(recursive: true);
  final manifest = <Map<String, Object>>[];
  for (final values in [
    ('default', 0, 108, 0, 1, false),
    ('zero-margin', 0, 0, 0, 1, false),
    ('wide-margin', 0, 240, 0, 1, false),
    ('negative-origin', -108, 108, 0, 1, false),
    ('positive-origin', 720, 240, 0, 1, false),
    ('independent-gap', 480, 240, 300, 1, false),
    ('cell-margin', 0, 240, 0, 1, true),
    ('nested', 0, 108, 0, 2, false),
    ('nested-wide', 240, 240, 0, 2, false),
  ]) {
    final (name, origin, margin, gap, depth, perCell) = values;
    final bytes = tableFixture([
      const TableFixtureParagraph('BODY\r'),
      if (depth == 2) const TableFixtureParagraph('OUTER\r', depth: 1),
      TableFixtureParagraph(
        depth == 1 ? 'CELL\x07' : 'CELL\r',
        depth: depth,
        cell: true,
      ),
      TableFixtureParagraph(
        depth == 1 ? '\x07' : '\r',
        depth: depth,
        row: true,
        extra: [
          ...wordSprm(0x9602, wordU16(gap)),
          ...tableFixtureDefinition([2400], origin: origin),
          ...wordSprm(perCell ? 0xd632 : 0xd634, [
            6,
            0,
            1,
            10,
            3,
            ...wordU16(margin),
          ]),
        ],
      ),
      if (depth == 2) ...[
        const TableFixtureParagraph('\x07', depth: 1, cell: true),
        TableFixtureParagraph(
          '\x07',
          depth: 1,
          row: true,
          widths: const [4800],
          extra: wordSprm(0xd634, [6, 0, 1, 10, 3, ...wordU16(108)]),
        ),
      ],
      const TableFixtureParagraph('AFTER\r'),
    ]);
    File('${root.path}/$name.doc').writeAsBytesSync(bytes);
    File(
      '${root.path}/$name-converted.docx',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(bytes).bytes);
    manifest.add({
      'name': name,
      'originTwips': origin,
      'marginTwips': margin,
      'halfGapTwips': gap,
      'depth': depth,
      'perCellMargin': perCell,
    });
  }
  File('${root.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
}
