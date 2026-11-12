import 'package:crisp_cloud/services/legacy_word_document.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/structured_word_fixture.dart';

LegacyWordParagraph _paragraph(LegacyWordDocument document) =>
    document.blocks.whereType<LegacyWordParagraph>().single;

void main() {
  test('CPlain resets a selected character style to paragraph formatting', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('Reset\r')],
        styles: {
          0: WordFixtureStyle(
            name: 'Normal',
            builtinId: 0,
            characterProperties: wordSprm(0x4a43, wordU16(20)),
          ),
          20: WordFixtureStyle(
            name: 'Emphasis',
            character: true,
            characterProperties: [
              ...wordSprm(0x0835, [1]),
              ...wordSprm(0x4a43, wordU16(32)),
            ],
          ),
        },
        characterRuns: [
          WordFixtureFkpRun(
            8192,
            8198,
            properties: [
              ...wordSprm(0x4a30, wordU16(20)),
              ...wordSprm(0x2a33, [0]),
            ],
          ),
        ],
      ).build(),
    );
    final run = _paragraph(document).runs.single;
    expect(run.text, 'Reset');
    expect(run.style.bold, isFalse);
    expect(run.style.fontSizeHalfPoints, 20);
  });

  test('CIstd resets earlier direct formatting but preserves later formatting and exemptions', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('AB\r')],
        styles: {
          0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
          20: WordFixtureStyle(
            name: 'Emphasis',
            character: true,
            characterProperties: [
              ...wordSprm(0x0836, [1]),
              ...wordSprm(0x4a43, wordU16(32)),
            ],
          ),
        },
        characterRuns: [
          WordFixtureFkpRun(
            8192,
            8193,
            properties: [
              ...wordSprm(0x0835, [1]),
              ...wordSprm(0x4a43, wordU16(40)),
              ...wordSprm(0x2a0c, [7]),
              ...wordSprm(0x0800, [1]),
              ...wordSprm(0x4a30, wordU16(20)),
            ],
          ),
          WordFixtureFkpRun(
            8193,
            8195,
            properties: [
              ...wordSprm(0x4a30, wordU16(20)),
              ...wordSprm(0x0835, [1]),
            ],
          ),
        ],
      ).build(),
    );
    final runs = _paragraph(document).runs;
    final first = runs.singleWhere((run) => run.text == 'A');
    expect(first.style.bold, isFalse);
    expect(first.style.italic, isTrue);
    expect(first.style.fontSizeHalfPoints, 32);
    expect(first.style.highlightHex, 'FFFF00');
    expect(first.deleted, isTrue);
    final second = runs.singleWhere((run) => run.text == 'B');
    expect(second.style.bold, isTrue);
    expect(second.style.italic, isTrue);
  });

  test('double strikethrough toggles resolve against the underlying style', () {
    for (final enabled in [false, true]) {
      for (final value in [0x80, 0x81]) {
        final document = parseLegacyWordDocument(
          StructuredWordFixture(
            pieces: const [WordFixturePiece('A\r')],
            styles: {
              0: WordFixtureStyle(
                name: 'Normal',
                builtinId: 0,
                characterProperties: wordSprm(0x2a53, [enabled ? 1 : 0]),
              ),
            },
            characterRuns: [
              WordFixtureFkpRun(
                8192,
                8194,
                properties: [
                  ...wordSprm(0x2a53, [value]),
                  ...wordSprm(0x0855, [0x80]),
                ],
              ),
            ],
          ).build(),
        );
        expect(
          _paragraph(document).runs.single.style.doubleStrike,
          value == 0x80 ? enabled : !enabled,
          reason: 'style=$enabled operand=$value',
        );
      }
    }
  });

  test(
    'special-character toggles accept inherited field marker properties',
    () {
      final document = parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: const [WordFixturePiece('\x13CODE\x14RESULT\x15\r')],
          characterRuns: [
            for (final cp in [0, 5, 12])
              WordFixtureFkpRun(
                8192 + cp,
                8193 + cp,
                properties: wordSprm(0x0855, [0x81]),
              ),
            const WordFixtureFkpRun(8205, 8206),
          ],
        ).build(),
      );
      expect(document.plainText, 'RESULT');
      expect(
        document.warnings,
        contains(LegacyWordWarning.fieldsUseStoredResults),
      );
      expect(document.safeHtml, isNot(contains('CODE')));
    },
  );

  test('plain-format reset retains highlight and revision state', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('Highlighted\r')],
        characterRuns: [
          WordFixtureFkpRun(
            8192,
            8204,
            properties: [
              ...wordSprm(0x0835, [1]),
              ...wordSprm(0x2a0c, [7]),
              ...wordSprm(0x0800, [1]),
              ...wordSprm(0x2a33, [0]),
            ],
          ),
        ],
      ).build(),
    );
    final run = _paragraph(document).runs.single;
    expect(run.text, 'Highlighted');
    expect(run.style.bold, isFalse);
    expect(run.style.highlightHex, 'FFFF00');
    expect(run.deleted, isTrue);
  });

  test('table definitions ignore excess complete TC80 records', () {
    final definition = [
      1,
      ...wordU16(0),
      ...wordU16(1440),
      ...List<int>.filled(20, 0),
      // An excess descriptor must not become a second cell or affect the first.
      ...wordU16(2),
      ...List<int>.filled(18, 0),
    ];
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('Cell\x07\x07After\r')],
        paragraphRuns: [
          WordFixtureFkpRun(8192, 8197, properties: wordSprm(0x2416, [1])),
          WordFixtureFkpRun(
            8197,
            8198,
            properties: [
              ...wordSprm(0x2416, [1]),
              ...wordSprm(0x2417, [1]),
              ...wordSprm(0xd608, [
                ...wordU16(definition.length + 1),
                ...definition,
              ]),
            ],
          ),
          const WordFixtureFkpRun(8198, 8204),
        ],
      ).build(),
    );
    final table = document.blocks.whereType<LegacyWordTable>().single;
    final cell = table.rows.single.cells.single;
    expect(cell.widthTwips, 1440);
    expect(cell.mergeStart, isFalse);
    expect(cell.mergeContinue, isFalse);
    expect(cell.paragraphs.single.runs.single.text, 'Cell');
    expect(document.plainText, 'Cell\nAfter');
  });
}
