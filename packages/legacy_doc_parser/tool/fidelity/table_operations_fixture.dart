// SPDX-License-Identifier: MPL-2.0
// Literal binary table operations for the independent schema gate.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/decorated_word_fixture.dart';
import '../../test/support/structured_word_fixture.dart';
import '../../test/support/table_word_fixture.dart';

const tableOperationsCaseNames = [
  'delete-resize',
  'merge',
  'split',
  'rtl-physical-left',
  'rtl-physical-center',
  'rtl-physical-right',
  'rtl-logical-left',
  'rtl-logical-center',
  'rtl-logical-right',
  'row-exceptions',
  'style-identities',
  'indirect-cache',
];

Uint8List _row(List<int> operations) => tableFixture([
  const TableFixtureParagraph('BODY\r'),
  const TableFixtureParagraph('FIRST\x07', depth: 1),
  const TableFixtureParagraph('SECOND\x07', depth: 1),
  TableFixtureParagraph(
    '\x07',
    depth: 1,
    row: true,
    widths: const [1440, 1440],
    extra: operations,
  ),
  const TableFixtureParagraph('AFTER\r'),
]);

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply an output directory.');
  final output = Directory(arguments.single)..createSync(recursive: true);
  final sources = <String, Uint8List>{
    'delete-resize': _row([
      ...wordSprm(0xd632, [6, 1, 2, 2, 3, ...wordU16(360)]),
      ...wordSprm(0xd62c, [3, 1, 2, 2]),
      ...wordSprm(0xd62f, [11, 1, 2, 1, ...wordU32(0xff), 8, 1, 0, 0]),
      ...wordSprm(0xd670, [
        20,
        ...wordShading(background: 0),
        ...wordShading(background: 0x00332211),
      ]),
      ...wordSprm(0x7621, [0, 1, ...wordU16(720)]),
      ...wordSprm(0x5622, [1, 2]),
      ...wordSprm(0x7623, [0, 1, ...wordU16(1080)]),
    ]),
    'merge': _row(wordSprm(0x5624, [0, 2])),
    'split': _row([
      ...wordSprm(0x5624, [0, 2]),
      ...wordSprm(0x5625, [0, 2]),
    ]),
    for (final kind in ['physical', 'logical'])
      for (var value = 0; value < 3; value++)
        'rtl-$kind-${['left', 'center', 'right'][value]}': _row([
          ...wordSprm(0x560b, wordU16(1)),
          ...wordSprm(kind == 'physical' ? 0x5400 : 0x548a, wordU16(value)),
        ]),
    'row-exceptions': tableFixture([
      const TableFixtureParagraph('FIRST\x07', depth: 1),
      TableFixtureParagraph(
        '\x07',
        depth: 1,
        row: true,
        widths: const [1440],
        extra: [
          ...wordSprm(0x548a, wordU16(1)),
          ...wordSprm(0x3615, [1]),
        ],
      ),
      const TableFixtureParagraph('SECOND\x07', depth: 1),
      const TableFixtureParagraph('\x07', depth: 1, row: true, widths: [1440]),
    ]),
    'style-identities': tableFixture(
      [
        for (final id in [15, 16]) ...[
          TableFixtureParagraph('Style$id\x07', depth: 1),
          TableFixtureParagraph(
            '\x07',
            depth: 1,
            row: true,
            widths: const [1440],
            extra: wordSprm(0x563a, wordU16(id)),
          ),
        ],
      ],
      styles: {
        0: const WordFixtureStyle(name: 'Normal'),
        15: WordFixtureStyle(
          name: 'Bold',
          table: true,
          characterProperties: wordSprm(0x0835, [1]),
        ),
        16: WordFixtureStyle(
          name: 'Italic',
          table: true,
          characterProperties: wordSprm(0x0836, [1]),
        ),
      },
    ),
  };
  final modern = [
    ...wordSprm(0x7621, [0, 2, ...wordU16(1440)]),
    ...wordSprm(0x7623, [0, 1, ...wordU16(720)]),
  ];
  sources['indirect-cache'] = StructuredWordFixture(
    pieces: const [WordFixturePiece('A\x07B\x07\x07C\x07D\x07\x07')],
    paragraphRuns: [
      for (var row = 0; row < 2; row++) ...[
        WordFixtureFkpRun(
          8192 + row * 5,
          8196 + row * 5,
          properties: wordSprm(0x2416, [1]),
        ),
        WordFixtureFkpRun(
          8196 + row * 5,
          8197 + row * 5,
          properties: [
            ...wordSprm(0x2416, [1]), ...wordSprm(0x2417, [1]),
            ...wordSprm(0x646b, wordU32(0)),
            ...tableFixtureDefinition([300, 400, 500]),
            0x35, 0x08, // Unreachable legacy tail after PTableProps.
          ],
        ),
      ],
    ],
    extraStreams: {
      'Data': Uint8List.fromList([...wordU16(modern.length), ...modern]),
    },
  ).build();
  if (sources.keys.join(',') != tableOperationsCaseNames.join(',')) {
    throw StateError('Table operation fixture inventory changed.');
  }
  for (final entry in sources.entries) {
    File('${output.path}/${entry.key}.doc').writeAsBytesSync(entry.value);
    File(
      '${output.path}/${entry.key}-converted.docx',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(entry.value).bytes);
  }
  File('${output.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(tableOperationsCaseNames.map((name) => {'name': name}).toList())}\n',
  );
}
