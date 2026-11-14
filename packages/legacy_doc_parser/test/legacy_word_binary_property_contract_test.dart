// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../tool/binary_property_contract_web_acceptance.dart';
import 'support/binary_property_contract_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

LegacyWordParagraph _paragraph(LegacyWordDocument value) =>
    value.blocks.single as LegacyWordParagraph;

XmlDocument _xml(LegacyWordDocument value) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder()
        .decodeBytes(convertLegacyWordDocument(value).bytes)
        .findFile('word/document.xml')!
        .content,
  ),
);

void main() {
  test('shared binary property acceptance passes on the VM', () {
    expect(verifyBinaryPropertyContractWebAcceptance(), {
      'booleanCases': 4,
      'invalidBooleansRejected': 10,
      'headingCases': 48,
      'indirectCases': 5,
      'invalidIndirectRejected': 2,
      'convertedPackages': 57,
      'sourceBytesUnchanged': true,
    });
  });
  for (final piece in [false, true]) {
    for (final value in [2, 0x7f, 0x80, 0x81, 0xff]) {
      test('CFObj rejects non-Bool8 $value (piece=$piece)', () {
        expect(
          () => parseLegacyWordDocument(
            binaryObjectFlagFixture(value, pieceProperty: piece),
          ),
          throwsFormatException,
        );
      });
    }
    test('CFObj true preserves its referenced EMBED object (piece=$piece)', () {
      final document = parseLegacyWordDocument(
        binaryObjectFlagFixture(1, pieceProperty: piece),
      );
      expect(document.media.embeddedObjects, hasLength(1));
      expect(document.media.embeddedObjects.single.cp, 6);
      expect(document.fields.single.type, 'EMBED');
    });
    test('CFObj false leaves ordinary text unchanged (piece=$piece)', () {
      final source = binaryObjectFalseFlagFixture(pieceProperty: piece);
      final document = parseLegacyWordDocument(source);
      expect(document.plainText, 'A');
      expect(document.media.embeddedObjects, isEmpty);
    });
  }

  for (var heading = 1; heading <= 9; heading++) {
    for (final outline in [0, 9]) {
      for (final piece in [false, true]) {
        test('Heading $heading ignores POutLvl $outline (piece=$piece)', () {
          final document = parseLegacyWordDocument(
            binaryHeadingOutlineFixture(heading, outline, pieceProperty: piece),
          );
          expect(_paragraph(document).style.headingLevel, heading);
          final outlineElement = _xml(
            document,
          ).findAllElements('outlineLvl', namespace: _w).single;
          expect(
            outlineElement.getAttribute('val', namespace: _w),
            '${heading - 1}',
          );
        });
      }
    }
    test(
      'historical Heading $heading ignores POutLvl before a Normal reset',
      () {
        final document = parseLegacyWordDocument(
          binaryHeadingOutlineFixture(heading, 9, historical: true),
        );
        final paragraph = _paragraph(document);
        expect(paragraph.style.headingLevel, isNull);
        expect(paragraph.style.styleIndex, 0);
        expect(
          paragraph.formattingRevision!.previousStyle!.headingLevel,
          heading,
        );
        final old = _xml(
          document,
        ).findAllElements('pPrChange', namespace: _w).single;
        expect(
          old
              .findAllElements('outlineLvl', namespace: _w)
              .single
              .getAttribute('val', namespace: _w),
          '${heading - 1}',
        );
      },
    );
  }
  for (final outline in [0, 8, 9]) {
    test('Normal still applies explicit POutLvl $outline', () {
      final document = parseLegacyWordDocument(
        binaryHeadingOutlineFixture(0, outline),
      );
      expect(
        _paragraph(document).style.headingLevel,
        outline == 9 ? null : outline + 1,
      );
    });
  }

  for (final name in binaryIndirectPositiveCases) {
    test('indirect properties: $name', () {
      final document = parseLegacyWordDocument(
        binaryIndirectPropertyFixture(name),
      );
      final style = _paragraph(document).style;
      expect(style.spaceBeforeTwips, 120);
      expect(style.spaceAfterTwips, name == 'huge-minimum-size' ? 0 : 240);
      if (name != 'huge-nonfirst-ignored' &&
          name != 'huge-nonfirst-cycle-ignored') {
        expect(style.keepTogether, isTrue);
      }
      expect(document.plainText, 'A');
    });
  }
  for (final name in ['huge-short-data', 'huge-first-cycle']) {
    test('indirect properties reject $name', () {
      expect(
        () => parseLegacyWordDocument(binaryIndirectPropertyFixture(name)),
        throwsFormatException,
      );
    });
  }
}
