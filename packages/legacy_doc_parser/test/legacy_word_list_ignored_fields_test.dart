// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/list_word_fixture.dart';
import 'support/structured_word_fixture.dart';

String _numberingXml(LegacyWordDocument document) => utf8.decode(
  ZipDecoder()
      .decodeBytes(convertLegacyWordDocument(document).bytes)
      .findFile('word/numbering.xml')!
      .content,
);

void main() {
  // MS-DOC 2.9.150 LVLF: fNoRestart and ilvlRestartLim are ignored when
  // nfc is 0x17 (bullet) or 0xFF (no number sequence).
  for (final (format, name, label) in [
    (23, 'bullet', '\u2022'),
    (255, 'none', ''),
  ]) {
    for (final restart in [0, 255]) {
      test('$name ignores restart metadata with threshold $restart', () {
        final baseline = parseLegacyWordDocument(
          listWordFixture(
            levels: [
              listFixtureLevel(format: format, text: label, placeholders: []),
            ],
          ),
        );
        final document = parseLegacyWordDocument(
          listWordFixture(
            levels: [
              listFixtureLevel(
                format: format,
                text: label,
                placeholders: [],
                start: 0xffffffff,
                flags: 8,
                restart: restart,
              ),
            ],
          ),
        );
        final level = document.numbering.single.levels.single;
        expect((level.format, level.text, level.startAt), (name, label, 1));
        expect(level.restartAfterLevel, isNull);
        expect(document.safeHtml, baseline.safeHtml);
        expect(_numberingXml(document), _numberingXml(baseline));
        expect(
          document.warnings,
          isNot(contains(LegacyWordWarning.numberingNotReconstructed)),
        );
      });
    }

    test('$name formatting override ignores restart metadata', () {
      final document = parseLegacyWordDocument(
        listWordFixture(
          instances: listFixtureInstances(
            overrides: [
              [
                ...wordU32(0xffffffff),
                ...wordU32(0x20),
                ...listFixtureLevel(
                  format: format,
                  text: label,
                  placeholders: [],
                  start: 0xffffffff,
                  flags: 8,
                  restart: 255,
                ),
              ],
            ],
          ),
        ),
      );
      final level = document.numbering.single.levels.single;
      expect(
        (level.format, level.text, level.restartAfterLevel),
        (name, label, null),
      );
      expect(_numberingXml(document), isNot(contains('<w:lvlRestart')));
    });
  }

  test('numbered level still rejects an active out-of-range threshold', () {
    for (final restart in [1, 255]) {
      expect(
        () => parseLegacyWordDocument(
          listWordFixture(
            levels: [listFixtureLevel(flags: 8, restart: restart)],
          ),
        ),
        throwsFormatException,
      );
    }
  });

  test('numbered level preserves its valid explicit restart threshold', () {
    final document = parseLegacyWordDocument(
      listWordFixture(levels: [listFixtureLevel(flags: 8)]),
    );
    expect(document.numbering.single.levels.single.restartAfterLevel, 0);
    expect(_numberingXml(document), contains('<w:lvlRestart w:val="0"'));
  });

  test('numbered level ignores restart threshold when its flag is clear', () {
    final document = parseLegacyWordDocument(
      listWordFixture(levels: [listFixtureLevel(restart: 255)]),
    );
    expect(document.numbering.single.levels.single.restartAfterLevel, isNull);
    expect(_numberingXml(document), isNot(contains('<w:lvlRestart')));
  });
}
