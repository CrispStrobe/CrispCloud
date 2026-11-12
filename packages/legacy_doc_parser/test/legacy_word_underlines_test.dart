// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/src/legacy_word_document.dart';
import 'package:test/test.dart';

import 'support/structured_word_fixture.dart';

LegacyWordDocument _document(List<int> operations) => parseLegacyWordDocument(
  StructuredWordFixture(
    pieces: const [WordFixturePiece('Text\r')],
    characterRuns: [WordFixtureFkpRun(8192, 8197, properties: operations)],
  ).build(),
);

void main() {
  test('maps every defined Kul value to its exact underline name', () {
    const values = <int, String>{
      0: 'none',
      1: 'single',
      2: 'words',
      3: 'double',
      4: 'dotted',
      6: 'thick',
      7: 'dash',
      9: 'dotDash',
      10: 'dotDotDash',
      11: 'wave',
      20: 'dottedHeavy',
      23: 'dashedHeavy',
      25: 'dashDotHeavy',
      26: 'dashDotDotHeavy',
      27: 'wavyHeavy',
      39: 'dashLong',
      43: 'wavyDouble',
      55: 'dashLongHeavy',
    };
    for (final entry in values.entries) {
      final document = _document(wordSprm(0x2a3e, [entry.key]));
      final style =
          (document.blocks.single as LegacyWordParagraph).runs.single.style;
      expect(style.underline, entry.key != 0, reason: 'Kul ${entry.key}');
      expect(style.underlineStyle, entry.value, reason: 'Kul ${entry.key}');
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.unsupportedFormatting)),
      );
    }
  });

  test(
    'invalid Kul gaps are rejected rather than treated as single underline',
    () {
      for (final value in [
        5,
        8,
        12,
        19,
        21,
        22,
        24,
        28,
        38,
        40,
        42,
        44,
        54,
        56,
        255,
      ]) {
        expect(
          () => _document(wordSprm(0x2a3e, [value])),
          throwsFormatException,
          reason: 'Kul $value',
        );
      }
    },
  );

  test('underline variants stay separate when adjacent runs are coalesced', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('AB\r')],
        characterRuns: [
          WordFixtureFkpRun(8192, 8193, properties: wordSprm(0x2a3e, [3])),
          WordFixtureFkpRun(8193, 8195, properties: wordSprm(0x2a3e, [4])),
        ],
      ).build(),
    );
    final runs = (document.blocks.single as LegacyWordParagraph).runs;
    expect(runs.map((run) => run.text), ['A', 'B']);
    expect(runs.map((run) => run.style.underlineStyle), ['double', 'dotted']);
  });

  test(
    'CPlain resets the underline kind to the underlying paragraph style',
    () {
      final document = parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: const [WordFixturePiece('A\r')],
          styles: {
            0: WordFixtureStyle(
              name: 'Normal',
              builtinId: 0,
              characterProperties: wordSprm(0x2a3e, [3]),
            ),
            20: WordFixtureStyle(
              name: 'Wavy',
              character: true,
              characterProperties: wordSprm(0x2a3e, [11]),
            ),
          },
          characterRuns: [
            WordFixtureFkpRun(
              8192,
              8194,
              properties: [
                ...wordSprm(0x4a30, wordU16(20)),
                ...wordSprm(0x2a33, [0]),
              ],
            ),
          ],
        ).build(),
      );
      final style =
          (document.blocks.single as LegacyWordParagraph).runs.single.style;
      expect(style.underline, isTrue);
      expect(style.underlineStyle, 'double');
    },
  );
}
