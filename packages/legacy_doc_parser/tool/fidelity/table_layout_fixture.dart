// SPDX-License-Identifier: MPL-2.0
// Independently authored MS-DOC records for row and cell layout oracles.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/structured_word_fixture.dart';
import '../../test/support/table_word_fixture.dart';

List<int> _fontTable() {
  final name = 'Liberation Serif'.codeUnits;
  final record = [
    ...List<int>.filled(40, 0),
    for (final unit in name) ...wordU16(unit),
    ...wordU16(0),
  ];
  record[0] = record.length - 1;
  return [...wordU16(1), ...wordU16(0), ...record];
}

Uint8List _document(List<(String, List<int>)> paragraphs) {
  var cp = 0;
  final runs = <WordFixtureFkpRun>[];
  for (final (text, properties) in paragraphs) {
    runs.add(
      WordFixtureFkpRun(
        8192 + cp,
        8192 + cp + text.length,
        properties: properties,
      ),
    );
    cp += text.length;
  }
  return StructuredWordFixture(
    pieces: [WordFixturePiece(paragraphs.map((p) => p.$1).join())],
    paragraphRuns: runs,
    extraTablePairs: {15: _fontTable()},
    styles: {
      0: WordFixtureStyle(
        name: 'Normal',
        builtinId: 0,
        paragraphProperties: [
          ...wordSprm(0x6412, [...wordU16(-240), ...wordU16(0)]),
          ...wordSprm(0xa413, wordU16(0)),
          ...wordSprm(0xa414, wordU16(0)),
          ...wordSprm(0x2431, [0]),
          ...wordSprm(0x2405, [0]),
          ...wordSprm(0x2406, [0]),
        ],
        characterProperties: [
          ...wordSprm(0x4a4f, wordU16(0)),
          ...wordSprm(0x4a43, wordU16(24)),
        ],
      ),
    },
    sections: [
      WordFixtureSection(cp, [
        ...wordSprm(0xb01f, wordU16(7200)),
        ...wordSprm(0xb020, wordU16(4320)),
        ...wordSprm(0xb021, wordU16(720)),
        ...wordSprm(0xb022, wordU16(720)),
        ...wordSprm(0x9023, wordU16(720)),
        ...wordSprm(0x9024, wordU16(720)),
      ]),
    ],
  ).build(
    mutate: (data, _) {
      // Word 2002 admits the current row split flag alongside the legacy flag.
      data.setUint16(2, 0x0101, Endian.little);
      data.setUint16(152, 136, Endian.little);
    },
  );
}

List<int> _cell() => wordSprm(0x2416, [1]);
List<int> _row(int height, {bool? cantSplit, List<int>? flags}) => [
  ...wordSprm(0x2416, [1]),
  ...wordSprm(0x2417, [1]),
  ...tableFixtureDefinition(
    flags == null ? [4320] : List.filled(flags.length, 864),
    flags: flags,
  ),
  ...wordSprm(0x9407, wordU16(height)),
  ...wordSprm(0xd634, [6, 0, 1, 10, 3, ...wordU16(108)]),
  if (cantSplit != null) ...[
    ...wordSprm(0x3403, [cantSplit ? 1 : 0]),
    ...wordSprm(0x3466, [cantSplit ? 1 : 0]),
  ],
];

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply an output directory.');
  final output = Directory(arguments.single)..createSync(recursive: true);
  final cases = <Map<String, Object?>>[];
  void emit(
    String name,
    List<(String, List<int>)> paragraphs, {
    required String kind,
    int? height,
    bool? cantSplit,
  }) {
    final source = _document(paragraphs);
    File('${output.path}/$name.doc').writeAsBytesSync(source);
    File(
      '${output.path}/$name-converted.docx',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(source).bytes);
    cases.add({
      'name': name,
      'kind': kind,
      'heightTwips': height,
      'cantSplit': cantSplit,
    });
  }

  for (final (name, height, multiline) in [
    ('auto', 0, true),
    ('minimum-short', 960, false),
    ('minimum-content', 240, true),
    ('exact-short', -960, false),
    ('exact-content', -240, true),
  ]) {
    emit(
      name,
      [
        ('BODY\r', []),
        (multiline ? 'CELL\x0bLINE2\x0bLINE3\x07' : 'CELL\x07', _cell()),
        ('\x07', _row(height)),
        ('NEXT\x07', _cell()),
        ('\x07', _row(0)),
        ('AFTER\r', []),
      ],
      kind: 'height',
      height: height,
    );
  }
  for (final cantSplit in [false, true]) {
    emit(
      cantSplit ? 'keep-row' : 'split-row',
      [
        ('BODY\r', []),
        ('PREFIX\x07', _cell()),
        ('\x07', _row(1800)),
        ('ROW2A\x0bROW2B\x0bROW2C\x0bROW2D\x0bROW2E\x0bROW2F\x07', _cell()),
        ('\x07', _row(0, cantSplit: cantSplit)),
        ('AFTER\r', []),
      ],
      kind: 'split',
      cantSplit: cantSplit,
    );
  }
  emit('cell-layout', [
    ('BODY\r', []),
    for (final flow in [0, 1, 3, 4, 5]) ('DIR$flow\x07', _cell()),
    (
      '\x07',
      _row(
        -1440,
        flags: [
          for (final flow in [0, 1, 3, 4, 5])
            (flow << 2) | (flow.isOdd ? 0x1000 : 0) | (flow == 0 ? 0x4000 : 0),
        ],
      ),
    ),
    ('AFTER\r', []),
  ], kind: 'cell');
  File(
    '${output.path}/manifest.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}
