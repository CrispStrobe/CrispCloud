// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

Uint8List _source(
  List<int> modern, {
  int rows = 1,
  List<int> tail = const [],
  List<int>? data,
  WordFixtureStyle? style,
}) => StructuredWordFixture(
  pieces: [WordFixturePiece(List.filled(rows, 'A\x07B\x07\x07').join())],
  paragraphRuns: [
    for (var row = 0; row < rows; row++) ...[
      WordFixtureFkpRun(
        8192 + row * 5,
        8194 + row * 5,
        properties: wordSprm(0x2416, [1]),
      ),
      WordFixtureFkpRun(
        8194 + row * 5,
        8196 + row * 5,
        properties: wordSprm(0x2416, [1]),
      ),
      WordFixtureFkpRun(
        8196 + row * 5,
        8197 + row * 5,
        properties: [
          ...wordSprm(0x2416, [1]),
          ...wordSprm(0x2417, [1]),
          ...wordSprm(0x646b, wordU32(0)),
          ...tail,
        ],
      ),
    ],
  ],
  extraStreams: {
    'Data': Uint8List.fromList(data ?? [...wordU16(modern.length), ...modern]),
  },
  styles: {
    0: const WordFixtureStyle(name: 'Normal'),
    15:
        style ??
        WordFixtureStyle(
          name: 'Modern',
          table: true,
          characterProperties: wordSprm(0x0835, [1]),
        ),
  },
).build();

void main() {
  final modern = [
    ...wordSprm(0x563a, wordU16(15)),
    ...wordSprm(0x7621, [0, 2, ...wordU16(1440)]),
  ];
  for (final rows in [1, 2]) {
    test('PTableProps stops the legacy tail for $rows referenced rows', () {
      final source = _source(
        modern,
        rows: rows,
        tail: [
          ...tableFixtureDefinition([100, 200, 300]),
          // The obsolete tail cannot be decoded as a complete modern Prl.
          // It is unreachable after PTableProps, including on a cache hit.
          0x35, 0x08,
        ],
      );
      final original = Uint8List.fromList(source);
      final document = parseLegacyWordDocument(source);
      final table = document.blocks.single as LegacyWordTable;
      expect(table.rows.length, rows);
      for (final row in table.rows) {
        expect(row.cells.map((cell) => cell.widthTwips), [1440, 1440]);
        expect(
          row.cells.first.paragraphs.single.runs.single.style.bold,
          isTrue,
        );
      }
      expect(source, original);
    });
  }

  test('PTableProps rejects records shorter than the required ten bytes', () {
    expect(
      () => parseLegacyWordDocument(_source(List.filled(9, 0))),
      throwsFormatException,
    );
  });

  test('PTableProps rejects a self-reference before consulting cache', () {
    final cyclic = [...wordSprm(0x646b, wordU32(0)), 0, 0, 0, 0];
    expect(
      () => parseLegacyWordDocument(_source(cyclic)),
      throwsFormatException,
    );
  });

  test('PTableProps rejects a mutually recursive replacement chain', () {
    final first = [...wordSprm(0x646b, wordU32(12)), 0, 0, 0, 0];
    final second = [...wordSprm(0x646b, wordU32(0)), 0, 0, 0, 0];
    expect(
      () => parseLegacyWordDocument(
        _source(
          [],
          data: [
            ...wordU16(first.length),
            ...first,
            ...wordU16(second.length),
            ...second,
          ],
        ),
      ),
      throwsFormatException,
    );
  });

  test('PTableProps follows a bounded terminating replacement chain', () {
    final first = [...wordSprm(0x646b, wordU32(12)), 0, 0, 0, 0];
    final table =
        parseLegacyWordDocument(
              _source(
                [],
                data: [
                  ...wordU16(first.length),
                  ...first,
                  ...wordU16(modern.length),
                  ...modern,
                ],
              ),
            ).blocks.single
            as LegacyWordTable;
    expect(table.rows.single.cells.map((cell) => cell.widthTwips), [
      1440,
      1440,
    ]);
  });

  for (final entry in <String, WordFixtureStyle>{
    'table structure in TAPX': WordFixtureStyle(
      name: 'Bad',
      table: true,
      tableProperties: tableFixtureDefinition([1440]),
    ),
    'character property in TAPX': WordFixtureStyle(
      name: 'Bad',
      table: true,
      tableProperties: wordSprm(0x0835, [1]),
    ),
    'table property in PAPX': WordFixtureStyle(
      name: 'Bad',
      table: true,
      paragraphProperties: wordSprm(0x3615, [1]),
    ),
    'paragraph property in CHPX': WordFixtureStyle(
      name: 'Bad',
      table: true,
      characterProperties: wordSprm(0x2403, [1]),
    ),
    'Data indirection in PAPX': WordFixtureStyle(
      name: 'Bad',
      table: true,
      paragraphProperties: wordSprm(0x646b, wordU32(0xffffffff)),
    ),
    'Data indirection in a paragraph condition': WordFixtureStyle(
      name: 'Bad',
      table: true,
      paragraphProperties: wordSprm(0xc666, [
        8,
        1,
        0,
        ...wordSprm(0x646b, wordU32(0xffffffff)),
      ]),
    ),
    'cell deletion in a table condition': WordFixtureStyle(
      name: 'Bad',
      table: true,
      tableProperties: wordSprm(0xd66a, [
        6,
        1,
        0,
        ...wordSprm(0x5622, [0, 1]),
      ]),
    ),
  }.entries) {
    test('rejects ${entry.key} before table-style application', () {
      expect(
        () => parseLegacyWordDocument(_source(modern, style: entry.value)),
        throwsFormatException,
      );
    });
  }
}
