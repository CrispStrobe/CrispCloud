// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/list_word_fixture.dart';
import 'support/structured_word_fixture.dart';

Uint8List _fixture(List<int> ids, {bool overridden = false}) {
  final texts = [for (var i = 0; i < ids.length; i++) 'Item $i\r'];
  var fc = 8192;
  return StructuredWordFixture(
    pieces: [WordFixturePiece(texts.join())],
    paragraphRuns: [
      for (var i = 0; i < ids.length; i++)
        WordFixtureFkpRun(
          fc,
          fc += texts[i].length,
          properties: wordSprm(0x460b, wordU16(ids[i])),
        ),
    ],
    extraTablePairs: {
      73: listFixtureDefinitions([listFixtureLevel()]),
      74: [
        ...wordU32(2),
        for (var i = 0; i < 2; i++) ...[
          ...wordU32(42),
          ...wordU32(0),
          ...wordU32(0),
          overridden && i == 1 ? 1 : 0,
          0,
          0,
          0,
        ],
        ...wordU32(0xffffffff),
        ...wordU32(0xffffffff),
        if (overridden) ...[...wordU32(5), ...wordU32(0x10)],
      ],
    },
  ).build(
    mutate: (word, table) {
      word.setUint32(158 + 73 * 8, 30, Endian.little);
    },
  );
}

XmlDocument _xml(Archive archive, String path) =>
    XmlDocument.parse(utf8.decode(archive.findFile(path)!.content));

void main() {
  test(
    'shared lsid continues across alternating ilfo without losing source ids',
    () {
      final bytes = _fixture([1, 2, 1, -2]);
      final source = bytes.toList();
      final document = parseLegacyWordDocument(bytes);
      expect(document.numbering.map((n) => n.id), [1, 2]);
      expect(document.numbering.map((n) => n.continuationOf), [null, 1]);
      expect(
        document.blocks.cast<LegacyWordParagraph>().map((p) => p.style.listId),
        [1, 2, 1, -2],
      );
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.numberingNotReconstructed)),
      );
      final html = XmlDocument.parse(document.safeHtml);
      expect(
        html
            .findAllElements('span')
            .where((s) => s.getAttribute('data-word-list-label') == 'true')
            .map((s) => s.innerText.trim()),
        ['1.', '2.', '3.', '4.'],
      );
      final archive = ZipDecoder().decodeBytes(
        convertLegacyWordToStructuredDocx(bytes).bytes,
      );
      final main = _xml(archive, 'word/document.xml');
      final numbering = _xml(archive, 'word/numbering.xml');
      expect(
        main.findAllElements('w:numId').map((e) => e.getAttribute('w:val')),
        List.filled(4, '1'),
      );
      expect(numbering.findAllElements('w:num'), hasLength(1));
      expect(numbering.findAllElements('w:abstractNum'), hasLength(1));
      expect(bytes, source);
    },
  );

  test('continuation works if the later instance is encountered first', () {
    final document = parseLegacyWordDocument(_fixture([2, 1, 2]));
    final html = XmlDocument.parse(document.safeHtml);
    expect(
      html
          .findAllElements('span')
          .where((s) => s.getAttribute('data-word-list-label') == 'true')
          .map((s) => s.innerText.trim()),
      ['1.', '2.', '3.'],
    );
  });

  test('an override in the shared source group is not silently coalesced', () {
    final bytes = _fixture([1, 2, 1], overridden: true);
    final document = parseLegacyWordDocument(bytes);
    expect(document.numbering.map((n) => n.continuationOf), [null, null]);
    expect(document.numbering.last.levels.single.startAt, 5);
    expect(
      document.warnings,
      contains(LegacyWordWarning.numberingNotReconstructed),
    );
    final archive = ZipDecoder().decodeBytes(
      convertLegacyWordToStructuredDocx(bytes).bytes,
    );
    expect(
      _xml(archive, 'word/numbering.xml').findAllElements('w:num'),
      hasLength(2),
    );
  });

  test('public model rejects a missing continuation target', () {
    final document = LegacyWordDocument(
      blocks: const [],
      sections: const [],
      plainText: '',
      safeHtml: '',
      numbering: const [
        LegacyWordNumberingDefinition(
          id: 2,
          sourceListId: 42,
          continuationOf: 1,
          levels: [
            LegacyWordNumberingLevel(level: 0, format: 'decimal', text: '%1.'),
          ],
        ),
      ],
    );
    expect(() => convertLegacyWordDocument(document), throwsFormatException);
  });
}
