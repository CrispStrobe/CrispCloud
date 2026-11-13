// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';

void main() {
  for (final compressed in [false, true]) {
    test('text extraction respects cbMac (compressed=$compressed)', () {
      const text = 'Private\r';
      final source =
          StructuredWordFixture(
            pieces: [WordFixturePiece(text, compressed: compressed)],
          ).build(
            mutate: (word, _) => word.setUint32(
              64,
              8192 + text.length * (compressed ? 1 : 2) - 1,
              Endian.little,
            ),
          );
      final original = Uint8List.fromList(source);
      expect(() => parseLegacyWordDocument(source), throwsFormatException);
      expect(() => extractLegacyWordText(source), throwsFormatException);
      expect(() => convertLegacyWordToDocx(source), throwsFormatException);
      expect(source, original);
    });

    test('rejects reserved text offset bit (compressed=$compressed)', () {
      final source =
          StructuredWordFixture(
            pieces: [WordFixturePiece('Text\r', compressed: compressed)],
          ).build(
            mutate: (word, table) {
              final clx = word.getUint32(154 + 33 * 8, Endian.little);
              // One PCD: its FcCompressed follows Pcdt, two CPs and two flags.
              final offset = clx + 5 + 8 + 2;
              final data = ByteData.sublistView(table);
              data.setUint32(
                offset,
                data.getUint32(offset, Endian.little) | 0x80000000,
                Endian.little,
              );
            },
          );
      expect(() => parseLegacyWordDocument(source), throwsFormatException);
      expect(() => extractLegacyWordText(source), throwsFormatException);
    });
  }

  for (final extent in [68, 32769]) {
    test('rejects an invalid declared WordDocument extent $extent', () {
      final source = StructuredWordFixture(
        pieces: const [WordFixturePiece('Text\r')],
      ).build(mutate: (word, _) => word.setUint32(64, extent, Endian.little));
      expect(() => parseLegacyWordDocument(source), throwsFormatException);
      expect(() => extractLegacyWordText(source), throwsFormatException);
    });
  }

  for (final extent in [0, 8197]) {
    test('retains valid text with declared extent $extent', () {
      final source = StructuredWordFixture(
        pieces: const [WordFixturePiece('Text\r')],
        flags: 0, // Select 0Table; the fixture also contains a decoy 1Table.
      ).build(mutate: (word, _) => word.setUint32(64, extent, Endian.little));
      expect(extractLegacyWordText(source), 'Text');
      expect(parseLegacyWordDocument(source).plainText, 'Text');
    });
  }

  test('column breaks separate text and text-only DOCX paragraphs', () {
    final source = StructuredWordFixture(
      pieces: const [WordFixturePiece('Left\x0eRight\r')],
    ).build();
    expect(extractLegacyWordText(source), 'Left\nRight');
    final archive = ZipDecoder().decodeBytes(convertLegacyWordToDocx(source));
    final document = XmlDocument.parse(
      utf8.decode(archive.findFile('word/document.xml')!.content as List<int>),
    );
    expect(
      document.findAllElements('w:p').map((paragraph) => paragraph.innerText),
      ['Left', 'Right'],
    );
  });

  test(
    'reads CP order and preserves surrogate pairs across Unicode pieces',
    () {
      final source = StructuredWordFixture(
        pieces: const [
          WordFixturePiece('First ', offset: 12288),
          WordFixturePiece('\ud83d', offset: 8192, compressed: false),
          WordFixturePiece('\ude00\r', offset: 16384, compressed: false),
        ],
      ).build();
      expect(extractLegacyWordText(source), 'First 😀');
      expect(extractLegacyWordText(source), isNot(contains('UNREFERENCED')));
    },
  );
}
