// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/structured_word_fixture.dart';

void main() {
  test('reports the isolated nonconforming cb0 PAPX orphan-byte recovery', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('Kept\r')],
        paragraphRuns: [
          WordFixtureFkpRun(
            8192,
            8197,
            properties: [
              ...wordSprm(0x2403, [1]),
              0x45,
            ],
          ),
        ],
      ).build(),
    );
    expect(document.plainText, 'Kept');
    expect(
      (document.blocks.single as LegacyWordParagraph).style.alignment,
      LegacyWordAlignment.center,
    );
    expect(
      document.warnings,
      contains(LegacyWordWarning.recoveredNonconformingProperties),
    );
  });

  test('still rejects a PAPX whose last opcode has a truncated operand', () {
    final bytes = StructuredWordFixture(
      pieces: const [WordFixturePiece('Kept\r')],
      paragraphRuns: const [
        WordFixtureFkpRun(8192, 8197, properties: [0x03, 0x24]),
      ],
    ).build();
    expect(() => parseLegacyWordDocument(bytes), throwsFormatException);
  });

  test('does not apply paragraph recovery to a character-property stream', () {
    final bytes = StructuredWordFixture(
      pieces: const [WordFixturePiece('Kept\r')],
      characterRuns: [
        WordFixtureFkpRun(
          8192,
          8197,
          properties: [
            ...wordSprm(0x0835, [1]),
            0x45,
          ],
        ),
      ],
    ).build();
    expect(() => parseLegacyWordDocument(bytes), throwsFormatException);
  });
}
