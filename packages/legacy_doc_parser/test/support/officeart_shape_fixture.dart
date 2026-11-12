// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'media_word_fixture.dart';
import 'structured_word_fixture.dart';

Uint8List shapePropertyRecord({
  Map<int, int> values = const {},
  Map<int, Uint8List> complex = const {},
  Map<int, int> complexLengths = const {},
}) => officeArtRecord(
  0xf00b,
  [
    for (final property in values.entries) ...[
      ...wordU16(property.key),
      ...wordU32(property.value),
    ],
    for (final property in complex.entries) ...[
      ...wordU16(property.key | 0x8000),
      ...wordU32(complexLengths[property.key] ?? property.value.length),
    ],
    for (final data in complex.values) ...data,
  ],
  version: 3,
  instance: values.length + complex.length,
);

Uint8List shapeArray(int size, List<List<int>> records, {int? allocated}) =>
    Uint8List.fromList([
      ...wordU16(records.length),
      ...wordU16(allocated ?? records.length),
      ...wordU16(size),
      for (final record in records) ...record,
    ]);

Uint8List shapeVertices(List<(int, int)> points) => shapeArray(8, [
  for (final point in points) [...wordU32(point.$1), ...wordU32(point.$2)],
]);

Uint8List shapeSegments(List<int> segments) =>
    shapeArray(2, [for (final segment in segments) wordU16(segment)]);

Uint8List officeArtShapeWordFixture({
  int type = 1,
  int flags = 0x0a00,
  Map<int, int> values = const {},
  Map<int, Uint8List> complex = const {},
  Map<int, int> defaults = const {},
  List<Uint8List> additionalProperties = const [],
  List<int> characterProperties = const [],
  Uint8List? rawPropertyRecord,
  (int, int, int, int) anchorBounds = (120, 240, 1560, 960),
  Map<int, List<int>> extraTablePairs = const {},
}) {
  final shape = officeArtRecord(0xf004, [
    ...officeArtRecord(
      0xf00a,
      [...wordU32(1025), ...wordU32(flags)],
      version: 2,
      instance: type,
    ),
    ...rawPropertyRecord ??
        shapePropertyRecord(values: values, complex: complex),
    for (final record in additionalProperties) ...record,
  ], version: 15);
  final drawings = Uint8List.fromList([
    ...officeArtRecord(
      0xf000,
      defaults.isEmpty ? const [] : shapePropertyRecord(values: defaults),
      version: 15,
    ),
    0,
    ...officeArtRecord(
      0xf002,
      officeArtRecord(0xf003, shape, version: 15),
      version: 15,
    ),
  ]);
  return StructuredWordFixture(
    pieces: const [WordFixturePiece('A\x08B\r')],
    extraTablePairs: {
      ...extraTablePairs,
      40: drawingAnchor(
        left: anchorBounds.$1,
        top: anchorBounds.$2,
        right: anchorBounds.$3,
        bottom: anchorBounds.$4,
      ),
      50: drawings,
    },
    characterRuns: [
      WordFixtureFkpRun(
        8192,
        8196,
        properties: [
          ...wordSprm(0x0855, [1]),
          ...characterProperties,
        ],
      ),
    ],
  ).build();
}
