// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

XmlDocument _xml(LegacyWordDocument document) {
  final archive = ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  );
  return XmlDocument.parse(
    utf8.decode(archive.findFile('word/document.xml')!.content),
  );
}

void main() {
  for (final name in ['list-continue', 'list-restart']) {
    test('$name contains no source page-size or margin declaration', () {
      final bytes = File('test/fixtures/word_native/$name.doc').readAsBytesSync();
      // Independent FIB inspection: these authored sparse DOCs contain no
      // PlcfSed. A renderer's chosen A4 default is not a stored source size.
      final word = ByteData.sublistView(
        CfbfFile.fromBytes(bytes).readStream('WordDocument')!,
      );
      expect(word.getUint32(202, Endian.little), 0);
      expect(word.getUint32(206, Endian.little), 0);
      expect(word.getUint16(6, Endian.little), 1033);
      final document = parseLegacyWordDocument(bytes);
      final section = document.sections.single;
      expect(section.pageWidthTwips, isNull);
      expect(section.pageHeightTwips, isNull);
      expect(section.marginLeftTwips, isNull);
      expect(section.marginRightTwips, isNull);
      expect(section.marginTopTwips, isNull);
      expect(section.marginBottomTwips, isNull);
      expect(_xml(document).findAllElements('pgSz', namespace: _w), isEmpty);
    });
  }

  test('an explicit empty SEPX does not invent an A4 page declaration', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('A\r')],
        sections: const [WordFixtureSection(2, [])],
      ).build(),
    );
    expect(document.sections.single.pageWidthTwips, isNull);
    expect(document.sections.single.pageHeightTwips, isNull);
    expect(_xml(document).findAllElements('pgSz', namespace: _w), isEmpty);
  });

  for (final (name, width, height, orientation) in [
    ('A4 portrait', 11906, 16838, 1),
    ('Letter portrait', 12240, 15840, 1),
    ('A4 landscape', 16838, 11906, 2),
  ]) {
    test('preserves independently authored $name section properties', () {
      final document = parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: const [WordFixturePiece('A\r')],
          sections: [
            WordFixtureSection(2, [
              ...wordSprm(0xb01f, wordU16(width)),
              ...wordSprm(0xb020, wordU16(height)),
              ...wordSprm(0x301d, [orientation]),
              ...wordSprm(0xb021, wordU16(1440)),
              ...wordSprm(0xb022, wordU16(1440)),
              ...wordSprm(0x9023, wordU16(1440)),
              ...wordSprm(0x9024, wordU16(1440)),
            ]),
          ],
        ).build(),
      );
      expect(document.sections.single.pageWidthTwips, width);
      expect(document.sections.single.pageHeightTwips, height);
      final size = _xml(document).findAllElements('pgSz', namespace: _w).single;
      expect(size.getAttribute('w', namespace: _w), '$width');
      expect(size.getAttribute('h', namespace: _w), '$height');
      expect(
        size.getAttribute('orient', namespace: _w),
        orientation == 2 ? 'landscape' : 'portrait',
      );
    });
  }
}
