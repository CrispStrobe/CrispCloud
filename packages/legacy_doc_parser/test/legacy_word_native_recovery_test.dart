// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';
import 'support/structured_word_fixture.dart';
import 'support/story_word_fixture.dart';

void main() {
  test(
    'body references and note markers keep separate source character styles',
    () {
      const note = '\x02Note\r';
      final document = parseLegacyWordDocument(
        storyWordFixture(
          main: 'A\x02\r',
          footnotes: '$note\r',
          tablePairs: {
            2: storyPlc([1, 3], wordU16(1)),
            3: storyPlc([0, note.length, 0xffffffff]),
          },
          characterRuns: [
            WordFixtureFkpRun(
              8192,
              8194,
              properties: wordSprm(0x4a43, wordU16(22)),
            ),
            const WordFixtureFkpRun(8194, 16386),
            WordFixtureFkpRun(
              16386,
              16388,
              properties: [
                ...wordSprm(0x4a43, wordU16(15)),
                ...wordSprm(0x2a48, [1]),
              ],
            ),
            const WordFixtureFkpRun(16388, 28672),
          ],
        ),
      );
      final reference = document.noteReferences.single;
      expect(reference.referenceStyle!.fontSizeHalfPoints, 15);
      expect(reference.markerStyle!.fontSizeHalfPoints, 22);
      final files = ZipDecoder().decodeBytes(
        convertLegacyWordDocument(document).bytes,
      );
      const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
      for (final (part, tag, expected) in [
        ('word/document.xml', 'footnoteReference', '15'),
        ('word/footnotes.xml', 'footnoteRef', '22'),
      ]) {
        final xml = XmlDocument.parse(
          utf8.decode(files.findFile(part)!.content),
        );
        final run = xml
            .findAllElements(tag, namespace: w)
            .single
            .parentElement!;
        expect(
          run
              .findAllElements('sz', namespace: w)
              .single
              .getAttribute('val', namespace: w),
          expected,
        );
      }
    },
  );
  test('binary object markers in field code retain stored results inertly', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [
          WordFixturePiece('A\x13 HYPERLINK \x01 \x14Visible link\x15\r'),
        ],
      ).build(),
    );
    final result = convertLegacyWordDocument(document);
    final files = ZipDecoder().decodeBytes(result.bytes);
    final xml = utf8.decode(files.findFile('word/document.xml')!.content);
    expect(xml, contains('Visible link'));
    expect(xml, isNot(contains('instrText')));
    expect(xml, isNot(contains('fldChar')));
    final evidence = utf8.decode(
      files.findFile('word/evidence/manifest.json')!.content,
    );
    expect(evidence, contains('HYPERLINK'));
    expect(evidence, contains(r'\u0001'));
    expect(
      result.limitations,
      contains(LegacyWordConversionLimitation.fieldsLists),
    );
    XmlDocument.parse(xml);
  });

  test('native zero-length first section retains distinct layout identity', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('Text\r')],
        sections: [
          WordFixtureSection(0, wordSprm(0xb01f, wordU16(10000))),
          WordFixtureSection(5, wordSprm(0xb01f, wordU16(12000))),
        ],
      ).build(),
    );
    expect(document.sections.map((s) => (s.startCp, s.endCp)), [
      (0, 0),
      (0, 5),
    ]);
    expect(
      document.warnings,
      contains(LegacyWordWarning.recoveredEmptySection),
    );
    final result = convertLegacyWordDocument(document);
    final files = ZipDecoder().decodeBytes(result.bytes);
    final xml = XmlDocument.parse(
      utf8.decode(files.findFile('word/document.xml')!.content),
    );
    const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    expect(
      xml
          .findAllElements('pgSz', namespace: w)
          .map((e) => e.getAttribute('w', namespace: w)),
      ['10000', '12000'],
    );
    expect(xml.findAllElements('t', namespace: w).map((e) => e.innerText), [
      'Text',
    ]);
    expect(result.preservedCounts['sections'], 2);
  });

  test('does not recover decreasing or arbitrary duplicate section ranges', () {
    for (final ends in [
      [0, 0, 5],
      [3, 2, 5],
    ]) {
      expect(
        () => parseLegacyWordDocument(
          StructuredWordFixture(
            pieces: const [WordFixturePiece('AB\x0cC\r')],
            sections: [
              for (final end in ends) WordFixtureSection(end, const []),
            ],
          ).build(),
        ),
        throwsFormatException,
      );
    }
  });
}
