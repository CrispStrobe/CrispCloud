// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'list_word_fixture.dart';
import 'structured_word_fixture.dart';

/// Independent binary LST/LFO/PAPX records, without the production converter.
Uint8List listSequenceFixture(
  List<(int instance, int level)> paragraphs, {
  List<List<int>>? levels,
  List<List<List<int>>> overrides = const [[], []],
  List<int>? sourceIds,
}) {
  final ids = sourceIds ?? List.filled(overrides.length, 42);
  if (ids.length != overrides.length) throw ArgumentError('Instance count');
  final base = levels ?? [listFixtureLevel()];
  final sources = ids.toSet().toList();
  final definitions = [
    for (final id in sources) listFixtureDefinitions(base, sourceId: id),
  ];
  final text = StringBuffer();
  final runs = <WordFixtureFkpRun>[];
  var fc = 8192;
  for (var index = 0; index < paragraphs.length; index++) {
    final value = 'P${index + 1}\r';
    text.write(value);
    runs.add(
      WordFixtureFkpRun(
        fc,
        fc + value.length,
        properties: [
          ...wordSprm(0x460b, wordU16(paragraphs[index].$1)),
          ...wordSprm(0x260a, [paragraphs[index].$2]),
        ],
      ),
    );
    fc += value.length;
  }
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text.toString())],
    paragraphRuns: runs,
    reuseFormattingRecords: true,
    extraTablePairs: {
      73: [
        ...wordU16(sources.length),
        for (final definition in definitions) ...definition.sublist(2, 30),
        for (final definition in definitions) ...definition.sublist(30),
      ],
      74: [
        ...wordU32(overrides.length),
        for (var i = 0; i < overrides.length; i++) ...[
          ...wordU32(ids[i]),
          ...wordU32(0),
          ...wordU32(0),
          overrides[i].length,
          0,
          0,
          0,
        ],
        for (final values in overrides) ...[
          ...wordU32(0xffffffff),
          for (final value in values) ...value,
        ],
      ],
    },
  ).build(
    mutate: (word, _) {
      word.setUint32(158 + 73 * 8, 2 + sources.length * 28, Endian.little);
    },
  );
}
