// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/list_word_fixture.dart';
import 'support/structured_word_fixture.dart';

void main() {
  test(
    'reads appended LVLs outside lcbPlfLst and applies marker-only CHPX',
    () {
      final document = parseLegacyWordDocument(
        listWordFixture(
          levels: [
            listFixtureLevel(
              start: 3,
              paragraph: [
                ...wordSprm(0x840f, wordU16(720)),
                ...wordSprm(0x8411, wordU16(0xfe98)),
              ],
              character: wordSprm(0x0835, [1]),
            ),
          ],
        ),
      );
      final definition = document.numbering.single;
      final level = definition.levels.single;
      expect(
        (
          definition.id,
          definition.sourceListId,
          level.startAt,
          level.text,
          level.format,
        ),
        (1, 42, 3, '%1.', 'decimal'),
      );
      expect(level.characterStyle.bold, isTrue);
      final paragraph = document.blocks.single as LegacyWordParagraph;
      expect(
        (paragraph.style.leftIndentTwips, paragraph.style.firstLineIndentTwips),
        (720, -360),
      );
      expect(paragraph.runs.single.style.bold, isFalse);
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.numberingNotReconstructed)),
      );
    },
  );
  test(
    'per-level placeholders, legal numbering and restart thresholds remain distinct',
    () {
      final levels = [
        listFixtureLevel(format: 1),
        listFixtureLevel(
          level: 1,
          format: 4,
          text: '\x00.\x01)',
          placeholders: [1, 3],
          flags: 0x0d,
          restart: 0,
        ),
        for (var i = 2; i < 9; i++) listFixtureLevel(level: i),
      ];
      final document = parseLegacyWordDocument(
        listWordFixture(
          levels: levels,
          paragraph: [
            ...wordSprm(0x460b, wordU16(1)),
            ...wordSprm(0x260a, [1]),
          ],
        ),
      );
      final definition = document.numbering.single;
      expect(definition.levels.first.format, 'upperRoman');
      final level = definition.levels[1];
      expect(
        (
          level.format,
          level.text,
          level.legal,
          level.restartAfterLevel,
          level.markerAlignment,
        ),
        ('lowerLetter', '%1.%2)', true, 0, LegacyWordAlignment.center),
      );
    },
  );
  test(
    'LFO start override and formatting override use their specified source',
    () {
      final startOverride = [...wordU32(7), ...wordU32(0x10)];
      var document = parseLegacyWordDocument(
        listWordFixture(
          instances: listFixtureInstances(overrides: [startOverride]),
        ),
      );
      expect(document.numbering.single.levels.single.startAt, 7);
      final formattingOverride = [
        ...wordU32(0xffffffff),
        ...wordU32(0x30),
        ...listFixtureLevel(format: 2, start: 9, text: '\x00)', suffix: 1),
      ];
      document = parseLegacyWordDocument(
        listWordFixture(
          instances: listFixtureInstances(overrides: [formattingOverride]),
        ),
      );
      final level = document.numbering.single.levels.single;
      expect(
        (level.startAt, level.format, level.text, level.suffix),
        (9, 'lowerRoman', '%1)', LegacyWordListSuffix.space),
      );
    },
  );
  test(
    'negative ilfo preserves direct indentation while positive ilfo applies list PAPX last',
    () {
      final levels = [
        listFixtureLevel(
          paragraph: [
            ...wordSprm(0x840f, wordU16(720)),
            ...wordSprm(0x8411, wordU16(0xfe98)),
          ],
        ),
      ];
      for (final id in [1, 0xffff]) {
        final document = parseLegacyWordDocument(
          listWordFixture(
            levels: levels,
            paragraph: [
              ...wordSprm(0x460b, wordU16(id)),
              ...wordSprm(0x840f, wordU16(120)),
              ...wordSprm(0x8411, wordU16(60)),
            ],
          ),
        );
        final style = (document.blocks.single as LegacyWordParagraph).style;
        expect((
          style.leftIndentTwips,
          style.firstLineIndentTwips,
        ), id == 1 ? (720, -360) : (120, 60));
      }
    },
  );
  test('skip level and no-list sentinel do not become invented numbering', () {
    for (final properties in [
      [
        ...wordSprm(0x460b, wordU16(1)),
        ...wordSprm(0x260a, [12]),
      ],
      wordSprm(0x460b, wordU16(0xf801)),
    ]) {
      final document = parseLegacyWordDocument(
        listWordFixture(paragraph: properties),
      );
      expect((document.blocks.single as LegacyWordParagraph).style.listId, 0);
    }
  });
  test(
    'literal bullet and its font properties are not replaced with a guessed glyph',
    () {
      final document = parseLegacyWordDocument(
        listWordFixture(
          levels: [
            listFixtureLevel(
              format: 23,
              start: 0xffffffff,
              text: '\uf0a7',
              placeholders: [],
              suffix: 2,
            ),
          ],
        ),
      );
      final level = document.numbering.single.levels.single;
      expect(
        (level.format, level.text, level.suffix),
        ('bullet', '\uf0a7', LegacyWordListSuffix.nothing),
      );
    },
  );
  test('list paragraph style also supplies resolved run properties', () {
    final document = parseLegacyWordDocument(
      listWordFixture(
        listStyle: 20,
        styles: {
          0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
          20: WordFixtureStyle(
            name: 'List',
            parentIndex: 0,
            characterProperties: wordSprm(0x0836, [1]),
          ),
        },
      ),
    );
    expect(
      (document.blocks.single as LegacyWordParagraph).runs.single.style.italic,
      isTrue,
    );
  });
  test('rejects foreign list IDs and repeated override indices', () {
    expect(
      () => parseLegacyWordDocument(
        listWordFixture(instances: listFixtureInstances(sourceId: 99)),
      ),
      throwsFormatException,
    );
    expect(
      () => parseLegacyWordDocument(
        listWordFixture(
          instances: listFixtureInstances(
            overrides: [
              [...wordU32(2), ...wordU32(0x10)],
              [...wordU32(3), ...wordU32(0x10)],
            ],
          ),
        ),
      ),
      throwsFormatException,
    );
  });
  test(
    'rejects invalid level placeholders and prohibited numbering formats',
    () {
      expect(
        () => parseLegacyWordDocument(
          listWordFixture(levels: [listFixtureLevel(text: '\x01.')]),
        ),
        throwsFormatException,
      );
      expect(
        () => parseLegacyWordDocument(
          listWordFixture(levels: [listFixtureLevel(format: 8)]),
        ),
        throwsFormatException,
      );
    },
  );
}
