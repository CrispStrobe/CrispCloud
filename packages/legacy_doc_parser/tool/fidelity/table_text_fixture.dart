// SPDX-License-Identifier: MPL-2.0
// Authored MS-DOC records for external validation of native table style XML.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/structured_word_fixture.dart';
import '../../test/support/table_word_fixture.dart';

List<int> _condition(int code, int mask, List<int> properties) =>
    wordSprm(code, [properties.length + 2, ...wordU16(mask), ...properties]);

List<int> _paragraph(bool reset) => [
  ...wordSprm(0x2403, [reset ? 0 : 1]),
  for (final code in [0x2405, 0x2406, 0x2407])
    ...wordSprm(code, [reset ? 0 : 1]),
  ...wordSprm(0x845e, wordU16(reset ? 0 : 240)),
  ...wordSprm(0x845d, wordU16(reset ? 0 : 180)),
  ...wordSprm(0x8460, wordU16(reset ? 0 : -120)),
  ...wordSprm(0xa413, wordU16(reset ? 0 : 80)),
  ...wordSprm(0xa414, wordU16(reset ? 0 : 100)),
  ...wordSprm(0x6412, [
    ...wordU16(reset ? 240 : -280),
    ...wordU16(reset ? 1 : 0),
  ]),
  ...wordSprm(0x2640, [reset ? 9 : 2]),
  for (final code in [
    0x240c,
    0x242a,
    0x2431,
    0x2433,
    0x2434,
    0x2435,
    0x2437,
    0x2438,
    0x2441,
    0x245b,
    0x245c,
    0x246d,
    0x2470,
  ])
    ...wordSprm(code, [reset ? 0 : 1]),
  for (final code in [0xc64e, 0xc64f, 0xc650, 0xc651, 0xc652])
    ...wordSprm(code, [
      8,
      ...wordU32(0x00402080),
      reset ? 0 : 4,
      reset ? 0 : 1,
      0,
      0,
    ]),
  ...wordSprm(0xc64d, [
    10,
    ...wordU32(0xff000000),
    ...wordU32(reset ? 0xff000000 : 0x00e0e0ff),
    0,
    0,
  ]),
];

List<int> _character(bool reset) => [
  for (final code in [0x0835, 0x0836, 0x0837, 0x083a, 0x083b, 0x083c, 0x2a53])
    ...wordSprm(code, [reset ? 0 : 1]),
  ...wordSprm(0x4a4f, wordU16(0)),
  ...wordSprm(0x4a43, wordU16(reset ? 20 : 28)),
  ...wordSprm(0x6870, wordU32(reset ? 0xff000000 : 0x00402080)),
  ...wordSprm(0x2a0c, [reset ? 0 : 7]),
  ...wordSprm(0x2a3e, [reset ? 0 : 9]),
  ...wordSprm(0x2a48, [reset ? 0 : 1]),
  ...wordSprm(0x4845, wordU16(reset ? 0 : 2)),
  ...wordSprm(0x8840, wordU16(reset ? 0 : 10)),
];

List<int> _fonts() {
  final name = 'Liberation Serif'.codeUnits;
  final record = [
    ...List<int>.filled(40, 0),
    for (final unit in name) ...wordU16(unit),
    ...wordU16(0),
  ];
  record[0] = record.length - 1;
  return [...wordU16(1), ...wordU16(0), ...record];
}

Uint8List _binary({required bool relative}) {
  final text = StringBuffer();
  final runs = <WordFixtureFkpRun>[];
  var cp = 0;
  void add(String value, List<int> properties) {
    text.write(value);
    runs.add(
      WordFixtureFkpRun(
        8192 + cp,
        8192 + cp + value.length,
        properties: properties,
      ),
    );
    cp += value.length;
  }

  for (var row = 0; row < 2; row++) {
    for (var column = 0; column < 2; column++) {
      add('R${row + 1}C${column + 1}\x07', wordSprm(0x2416, [1]));
    }
    add('\x07', [
      ...wordSprm(0x2416, [1]),
      ...wordSprm(0x2417, [1]),
      ...tableFixtureDefinition(const []),
      ...wordSprm(0x563a, wordU16(20)),
      ...wordSprm(0x740a, [...wordU16(0), ...wordU16(0x1e0)]),
      ...wordSprm(0x7621, [0, 2, ...wordU16(2400)]),
    ]);
  }
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text.toString())],
    paragraphRuns: runs,
    extraTablePairs: {15: _fonts()},
    styles: {
      0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
      19: WordFixtureStyle(
        name: 'Table text base',
        table: true,
        tableProperties: wordSprm(0x347d, [1]),
        paragraphProperties: _paragraph(false),
        characterProperties: _character(false),
      ),
      20: WordFixtureStyle(
        name: 'Table conditional text',
        table: true,
        parentIndex: 19,
        tableProperties: [
          ...wordSprm(0x3488, [2]),
          ...wordSprm(0x3489, [2]),
          for (var bit = 0; bit < 12; bit++)
            ..._condition(
              0xd66a,
              1 << bit,
              wordSprm(0x347d, [bit.isEven ? 0 : 1]),
            ),
        ],
        paragraphProperties: [
          for (var bit = 0; bit < 12; bit++)
            ..._condition(0xc666, 1 << bit, _paragraph(bit.isEven)),
        ],
        characterProperties: [
          for (var bit = 0; bit < 12; bit++)
            ..._condition(0xca85, 1 << bit, [
              ..._character(bit.isEven),
              if (relative) ...wordSprm(0x0835, [bit.isEven ? 0x80 : 0x81]),
            ]),
        ],
      ),
    },
  ).build(
    mutate: (data, _) {
      // Table styles are a Word 2002 feature. Reserve the complete FIB offset
      // array for that version; its additional unused offsets remain zero.
      data.setUint16(2, 0x0101, Endian.little);
      data.setUint16(152, 136, Endian.little);
    },
  );
}

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply an output directory.');
  final root = Directory(arguments.single)..createSync(recursive: true);
  for (final relative in [false, true]) {
    final name = relative
        ? 'table-text-relative-toggles'
        : 'table-text-conditions';
    final source = _binary(relative: relative);
    final converted = convertLegacyWordToStructuredDocx(source);
    File('${root.path}/$name.doc').writeAsBytesSync(source);
    File('${root.path}/$name.docx').writeAsBytesSync(converted.bytes);
    File('${root.path}/$name.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'preservedCounts': converted.preservedCounts, 'limitations': converted.limitations.map((l) => l.name).toList(), 'source': 'Independently assembled MS-DOC SPRMs; no production writer used for input.', 'scope': 'All twelve native table conditions, table inheritance, partial '
          'paragraph/character properties, explicit resets, noWrap on/off.', 'nonconformingProbe': 'Source style highlight deliberately exercises recovery: retain the '
          'resolved run value and diagnostic, omit forbidden native style child.'})}\n',
    );
  }
}
