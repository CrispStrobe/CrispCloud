// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import 'structured_word_fixture.dart';

/// Operand domains are taken from MS-DOC 2.6.1, 2.6.2, 2.9.146 (LSPD), and
/// 2.9.349 (XAS), independently of the parser's integer readers.
const scalarSprmProperties = [
  ScalarSprmProperty('character-spacing', 0x8840, 'spacing', character: true),
  ScalarSprmProperty('left-97', 0x840f, 'left'),
  ScalarSprmProperty('left', 0x845e, 'left'),
  ScalarSprmProperty('right-97', 0x840e, 'right'),
  ScalarSprmProperty('right', 0x845d, 'right'),
  ScalarSprmProperty('first-97', 0x8411, 'first'),
  ScalarSprmProperty('first', 0x8460, 'first'),
  ScalarSprmProperty('before', 0xa413, 'before', unsigned: true),
  ScalarSprmProperty('after', 0xa414, 'after', unsigned: true),
  ScalarSprmProperty('line-absolute', 0x6412, 'line', multiple: false),
  ScalarSprmProperty('line-multiple', 0x6412, 'line', multiple: true),
];

class ScalarSprmProperty {
  const ScalarSprmProperty(
    this.name,
    this.opcode,
    this.property, {
    this.character = false,
    this.unsigned = false,
    this.multiple,
  });

  final String name, property;
  final int opcode;
  final bool character, unsigned;
  final bool? multiple;

  List<String> get scopes => [
    'direct',
    'paragraph-style',
    'piece-prm',
    if (character) 'character-style',
  ];

  List<int> get validValues => unsigned
      ? [0, 1, 31679, 31680]
      : [-31680, -31679, -1, 0, 1, 31679, 31680];

  List<int> get invalidValues =>
      unsigned ? [31681, 32767, 32768, 65535] : [-32768, -31681, 31681, 32767];

  List<int> operand(int value) => [
    ...wordU16(value),
    if (multiple != null) ...wordU16(multiple! ? 1 : 0),
  ];

  int? read(LegacyWordParagraph paragraph) => switch (property) {
    'spacing' => paragraph.runs.single.style.spacingTwips,
    'left' => paragraph.style.leftIndentTwips,
    'right' => paragraph.style.rightIndentTwips,
    'first' => paragraph.style.firstLineIndentTwips,
    'before' => paragraph.style.spaceBeforeTwips,
    'after' => paragraph.style.spaceAfterTwips,
    'line' => paragraph.style.lineSpacingValue,
    _ => throw StateError('Unknown scalar fixture property $property'),
  };
}

Uint8List scalarSprmFixture(
  ScalarSprmProperty property,
  int value,
  String scope,
) {
  final bytes = wordSprm(property.opcode, property.operand(value));
  return StructuredWordFixture(
    pieces: [WordFixturePiece('AB\r', prm: scope == 'piece-prm' ? 1 : 0)],
    prcs: [if (scope == 'piece-prm') bytes],
    characterRuns: [
      if (scope == 'direct' && property.character)
        WordFixtureFkpRun(8192, 8195, properties: bytes),
      if (scope == 'character-style')
        WordFixtureFkpRun(
          8192,
          8195,
          properties: wordSprm(0x4a30, wordU16(20)),
        ),
    ],
    paragraphRuns: [
      if (scope == 'direct' && !property.character)
        WordFixtureFkpRun(8192, 8195, properties: bytes),
    ],
    styles: {
      0: WordFixtureStyle(
        name: 'Normal',
        builtinId: 0,
        characterProperties: scope == 'paragraph-style' && property.character
            ? bytes
            : const [],
        paragraphProperties: scope == 'paragraph-style' && !property.character
            ? bytes
            : const [],
      ),
      if (scope == 'character-style')
        20: WordFixtureStyle(
          name: 'Boundary',
          character: true,
          characterProperties: bytes,
        ),
    },
  ).build();
}
