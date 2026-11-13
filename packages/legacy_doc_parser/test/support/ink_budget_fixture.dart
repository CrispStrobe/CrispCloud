// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'media_word_fixture.dart';
import 'officeart_shape_fixture.dart';
import 'structured_word_fixture.dart';

List<int> _unsigned(int value) {
  final result = <int>[];
  do {
    final low = value & 127;
    value ~/= 128;
    result.add(low | (value == 0 ? 0 : 128));
  } while (value != 0);
  return result;
}

List<int> _sized(List<int> bytes) => [..._unsigned(bytes.length), ...bytes];
Uint8List _frame(List<int> body) => Uint8List.fromList([0, ..._sized(body)]);

// Independently declared ISF Huffman-table-0 zero deltas. Each X/Y point is
// encoded by one zero bit; no production encoder supplies expected counts.
Uint8List inkBudgetIsf(List<int> counts, {List<int> tail = const []}) =>
    _frame([
      for (final count in counts) ...[
        10,
        ..._sized([
          ..._unsigned(count),
          0x80,
          ...List.filled((count + 7) ~/ 8, 0),
          0x80,
          ...List.filled((count + 7) ~/ 8, 0),
        ]),
      ],
      ...tail,
    ]);

Uint8List _envelope(Uint8List data) => Uint8List.fromList([
  0x34,
  0x1a,
  0x7c,
  0x93,
  0x1d,
  0x15,
  0x10,
  0x46,
  0x9c,
  0xa6,
  0xa8,
  0xcc,
  0x9b,
  0xdb,
  0x5d,
  0x83,
  ...wordU32(data.length),
  ...data,
]);

Uint8List inkBudgetWordFixture(List<Uint8List> payloads) {
  final count = payloads.length;
  final shapes = [
    for (var index = 0; index < count; index++)
      ...officeArtRecord(0xf004, [
        ...officeArtRecord(
          0xf00a,
          [...wordU32(1025 + index), ...wordU32(0x0a00)],
          version: 2,
          instance: 1,
        ),
        ...shapePropertyRecord(
          values: {0x073f: 0x00090009},
          complex: {0x0700: _envelope(payloads[index])},
        ),
      ], version: 15),
  ];
  return StructuredWordFixture(
    pieces: [WordFixturePiece('${List.filled(count, '\x08').join()}\r')],
    characterRuns: [
      WordFixtureFkpRun(
        8192,
        8192 + count + 1,
        properties: wordSprm(0x0855, [1]),
      ),
    ],
    extraTablePairs: {
      40: [
        for (var index = 0; index < count; index++) ...wordU32(index),
        ...wordU32(count + 1),
        for (var index = 0; index < count; index++) ...[
          ...wordU32(1025 + index),
          ...wordU32(120),
          ...wordU32(240),
          ...wordU32(1560),
          ...wordU32(960),
          ...wordU16(0),
          ...wordU32(0),
        ],
      ],
      50: drawingContent(shape: Uint8List.fromList(shapes)),
    },
  ).build();
}
