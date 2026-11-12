// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';
import 'support/textbox_boundary_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

List<XmlElement> _boxes(LegacyWordDocument document) {
  final zip = ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  );
  return [
    for (final file in zip.files.where(
      (file) => file.name.startsWith('word/') && file.name.endsWith('.xml'),
    ))
      ...XmlDocument.parse(
        utf8.decode(file.content),
      ).findAllElements('txbxContent', namespace: _w),
  ];
}

List<String> _paragraphTexts(XmlElement box) => [
  for (final paragraph in box.findElements('p', namespace: _w))
    paragraph
        .findAllElements('t', namespace: _w)
        .map((text) => text.innerText)
        .join(),
];

void main() {
  for (final header in [false, true]) {
    for (final entry in textboxBoundaryCases.entries) {
      test('${header ? 'header' : 'main'} textbox preserves ${entry.key}', () {
        final (raw, expected) = entry.value;
        final document = parseLegacyWordDocument(
          textboxBoundaryFixture([raw], header: header),
        );
        final story = document.stories.singleWhere(
          (story) =>
              story.kind ==
              (header
                  ? LegacyWordStoryKind.headerTextbox
                  : LegacyWordStoryKind.textbox),
        );
        expect(story.blocks, hasLength(expected.length));
        expect(story.plainText, expected.join('\n'));
        expect(story.endCp - story.startCp, raw.length - 1);
        expect(story.blocks.last.endCp, story.endCp);
        expect(_paragraphTexts(_boxes(document).single), expected);
      });
    }
  }

  test(
    'adjacent and reusable ranges do not enter either neighboring story',
    () {
      final document = parseLegacyWordDocument(
        textboxBoundaryFixture(
          ['FIRST\r\r', '\r', '\r\r', 'LAST\r\r\r'],
          reusable: {1},
        ),
      );
      final stories = document.stories;
      expect(stories.map((story) => story.plainText), ['FIRST', '', 'LAST\n']);
      expect(document.textboxReferences.map((reference) => reference.id), [
        1,
        3,
        4,
      ]);
      expect(stories[1].startCp - stories[0].endCp, 2);
      expect(stories[2].startCp - stories[1].endCp, 1);
      expect(_boxes(document).map(_paragraphTexts), [
        ['FIRST'],
        [''],
        ['LAST', ''],
      ]);
    },
  );

  test(
    'linked frames share one bounded story including an intentional blank',
    () {
      final document = parseLegacyWordDocument(
        textboxBoundaryFixture(['FIRST\r\rLAST\r\r'], chainLength: 2),
      );
      expect(document.stories.single.plainText, 'FIRST\n\nLAST');
      expect(document.textboxReferences.single.chainLength, 2);
      final boxes = _boxes(document);
      expect(boxes, hasLength(2));
      expect(_paragraphTexts(boxes.first), ['FIRST', '', 'LAST']);
      expect(_paragraphTexts(boxes.last), ['']);
    },
  );

  test(
    'content paragraph mark formatting is retained; separator formatting is not a paragraph',
    () {
      const offset = 12288;
      final document = parseLegacyWordDocument(
        textboxBoundaryFixture(
          ['A\r\r'],
          characterRuns: [
            const WordFixtureFkpRun(8192, offset + 2),
            WordFixtureFkpRun(
              offset + 2,
              offset + 4,
              properties: wordSprm(0x0835, [1]),
            ),
            WordFixtureFkpRun(
              offset + 4,
              offset + 6,
              properties: wordSprm(0x0836, [1]),
            ),
            const WordFixtureFkpRun(offset + 6, 16386),
            WordFixtureFkpRun(16386, 16388, properties: wordSprm(0x0855, [1])),
            const WordFixtureFkpRun(16388, 28672),
          ],
          paragraphRuns: [
            WordFixtureFkpRun(
              8192,
              offset + 4,
              properties: wordSprm(0xa414, wordU16(120)),
            ),
            WordFixtureFkpRun(
              offset + 4,
              offset + 6,
              properties: wordSprm(0xa414, wordU16(2400)),
            ),
            const WordFixtureFkpRun(offset + 6, 28672),
          ],
        ),
      );
      final paragraph =
          document.stories.single.blocks.single as LegacyWordParagraph;
      expect(paragraph.mark!.style.bold, isTrue);
      expect(paragraph.mark!.style.italic, isFalse);
      expect(paragraph.style.spaceAfterTwips, 120);
    },
  );

  for (final invalid in ['\r', 'A\rX', 'ABC']) {
    test('rejects an invalid literal textbox range ${jsonEncode(invalid)}', () {
      expect(
        () => parseLegacyWordDocument(textboxBoundaryFixture([invalid])),
        throwsFormatException,
      );
    });
  }

  test('a field cannot be repaired by borrowing the next textbox range', () {
    expect(
      () => parseLegacyWordDocument(
        textboxBoundaryFixture(['A\x13 PAGE \x141\r\r', 'B\x15\r\r']),
      ),
      throwsFormatException,
    );
  });

  test('Word14 six native ranges contain one content paragraph apiece', () {
    final document = parseLegacyWordDocument(
      File(
        'test/fixtures/word_native/word14-margin-origin.doc',
      ).readAsBytesSync(),
    );
    final stories = document.stories
        .where((story) => story.kind == LegacyWordStoryKind.textbox)
        .toList();
    expect(stories, hasLength(6));
    for (final story in stories) {
      expect(story.blocks, hasLength(1));
      expect(story.plainText, isNot(endsWith('\n')));
    }
    final boxes = _boxes(document);
    expect(boxes, hasLength(6));
    for (final box in boxes) {
      expect(_paragraphTexts(box), hasLength(1));
    }
  });
}
