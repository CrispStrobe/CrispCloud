// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/list_sequence_fixture.dart';
import '../../test/support/list_word_fixture.dart';
import '../../test/support/structured_word_fixture.dart';

const listSequenceCaseNames = [
  'shared-counter',
  'explicit-start',
  'format-continue',
  'same-instance-ancestor',
  'never-restart',
  'legal-decimal-zero',
  'hidden-marker',
];

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply an output directory.');
  final output = Directory(arguments.single)..createSync(recursive: true);
  final sequence = [(1, 0), (1, 0), (2, 0), (2, 0), (1, 0)];
  final multilevel = [(1, 0), (1, 1), (2, 1), (2, 0), (1, 1)];
  List<List<int>> levels({bool never = false, bool legalZero = false}) => [
    for (var level = 0; level < 9; level++)
      listFixtureLevel(
        level: level,
        format: legalZero && level == 0 ? 22 : 0,
        text: level == 1 ? '\x00.\x01)' : null,
        placeholders: level == 1 ? [1, 3] : null,
        flags: level == 1
            ? (never
                  ? 8
                  : legalZero
                  ? 4
                  : 0)
            : 0,
        restart: 0,
      ),
  ];
  final sources = {
    'shared-counter': listSequenceFixture(sequence),
    'explicit-start': listSequenceFixture(
      [...sequence, (2, 0)],
      overrides: [
        [],
        [
          [...wordU32(7), ...wordU32(0x10)],
        ],
      ],
    ),
    'format-continue': listSequenceFixture(
      sequence,
      overrides: [
        [],
        [
          [
            ...wordU32(0xffffffff),
            ...wordU32(0x20),
            ...listFixtureLevel(format: 1),
          ],
        ],
      ],
    ),
    'same-instance-ancestor': listSequenceFixture(multilevel, levels: levels()),
    'never-restart': listSequenceFixture(
      multilevel,
      levels: levels(never: true),
    ),
    'legal-decimal-zero': listSequenceFixture([
      (1, 0),
      (1, 1),
    ], levels: levels(legalZero: true)),
    'hidden-marker': listSequenceFixture(
      [(1, 0)],
      levels: [
        listFixtureLevel(
          format: 23,
          text: 'X',
          placeholders: [],
          character: wordSprm(0x083c, [1]),
        ),
      ],
    ),
  };
  if (sources.keys.join(',') != listSequenceCaseNames.join(',')) {
    throw StateError('List sequence fixture inventory changed.');
  }
  for (final entry in sources.entries) {
    File('${output.path}/${entry.key}.doc').writeAsBytesSync(entry.value);
    File(
      '${output.path}/${entry.key}-converted.docx',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(entry.value).bytes);
  }
  File('${output.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(listSequenceCaseNames.map((name) => {'name': name}).toList())}\n',
  );
}
