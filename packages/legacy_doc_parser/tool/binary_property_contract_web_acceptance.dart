// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/binary_property_contract_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

Map<String, Object?> verifyBinaryPropertyContractWebAcceptance() {
  var booleanCases = 0, invalidBooleans = 0, headings = 0, indirect = 0;
  for (final piece in [false, true]) {
    for (final value in [2, 0x7f, 0x80, 0x81, 0xff]) {
      _reject(binaryObjectFlagFixture(value, pieceProperty: piece));
      invalidBooleans++;
    }
    final (object, objectXml) = _convert(
      binaryObjectFlagFixture(1, pieceProperty: piece),
    );
    _require(
      object.media.embeddedObjects.length == 1 &&
          object.media.embeddedObjects.single.cp == 6 &&
          object.fields.single.type == 'EMBED' &&
          objectXml
                  .findAllElements(
                    'OLEObject',
                    namespace: 'urn:schemas-microsoft-com:office:office',
                  )
                  .length ==
              1,
      'True CFObj lost its referenced object.',
    );
    final (text, _) = _convert(
      binaryObjectFalseFlagFixture(pieceProperty: piece),
    );
    _require(
      text.plainText == 'A' && text.media.embeddedObjects.isEmpty,
      'False CFObj changed ordinary text.',
    );
    booleanCases += 2;
  }

  for (var heading = 1; heading <= 9; heading++) {
    for (final outline in [0, 9]) {
      for (final piece in [false, true]) {
        final (document, xml) = _convert(
          binaryHeadingOutlineFixture(heading, outline, pieceProperty: piece),
        );
        _require(
          _paragraph(document).style.headingLevel == heading &&
              _currentProperties(xml)
                      .getElement('outlineLvl', namespace: _w)!
                      .getAttribute('val', namespace: _w) ==
                  '${heading - 1}',
          'Fixed heading style lost its outline precedence.',
        );
        headings++;
      }
    }
    final (document, xml) = _convert(
      binaryHeadingOutlineFixture(heading, 9, historical: true),
    );
    final paragraph = _paragraph(document);
    final previous = xml.findAllElements('pPrChange', namespace: _w).single;
    _require(
      paragraph.style.headingLevel == null &&
          paragraph.style.styleIndex == 0 &&
          paragraph.formattingRevision!.previousStyle!.headingLevel ==
              heading &&
          _currentProperties(xml)
                  .getElement('outlineLvl', namespace: _w)!
                  .getAttribute('val', namespace: _w) ==
              '9' &&
          previous
                  .findAllElements('outlineLvl', namespace: _w)
                  .single
                  .getAttribute('val', namespace: _w) ==
              '${heading - 1}',
      'Heading history or the current Normal reset changed.',
    );
    headings++;
  }
  for (final outline in [0, 8, 9]) {
    final (document, xml) = _convert(binaryHeadingOutlineFixture(0, outline));
    _require(
      _paragraph(document).style.headingLevel ==
              (outline == 9 ? null : outline + 1) &&
          _currentProperties(xml)
                  .getElement('outlineLvl', namespace: _w)!
                  .getAttribute('val', namespace: _w) ==
              '$outline',
      'Normal style failed to apply its explicit outline level.',
    );
    headings++;
  }

  for (final name in binaryIndirectPositiveCases) {
    final (document, xml) = _convert(binaryIndirectPropertyFixture(name));
    final style = _paragraph(document).style;
    final minimum = name == 'huge-minimum-size';
    final ignored =
        name == 'huge-nonfirst-ignored' ||
        name == 'huge-nonfirst-cycle-ignored';
    final properties = _currentProperties(xml);
    final spacing = properties.getElement('spacing', namespace: _w)!;
    _require(
      document.plainText == 'A' &&
          style.spaceBeforeTwips == 120 &&
          style.spaceAfterTwips == (minimum ? 0 : 240) &&
          style.keepTogether == !ignored &&
          style.keepNext == minimum &&
          spacing.getAttribute('before', namespace: _w) == '120' &&
          spacing.getAttribute('after', namespace: _w) ==
              (minimum ? '0' : '240') &&
          properties
                  .getElement('keepLines', namespace: _w)!
                  .getAttribute('val', namespace: _w) ==
              (ignored ? '0' : '1'),
      'Indirect paragraph properties changed: $name',
    );
    indirect++;
  }
  for (final name in ['huge-short-data', 'huge-first-cycle']) {
    _reject(binaryIndirectPropertyFixture(name));
  }
  return {
    'booleanCases': booleanCases,
    'invalidBooleansRejected': invalidBooleans,
    'headingCases': headings,
    'indirectCases': indirect,
    'invalidIndirectRejected': 2,
    'convertedPackages': booleanCases + headings + indirect,
    'sourceBytesUnchanged': true,
  };
}

LegacyWordParagraph _paragraph(LegacyWordDocument document) =>
    document.blocks.single as LegacyWordParagraph;

XmlElement _currentProperties(XmlDocument xml) => xml
    .findAllElements('p', namespace: _w)
    .first
    .getElement('pPr', namespace: _w)!;

(LegacyWordDocument, XmlDocument) _convert(Uint8List bytes) {
  final original = Uint8List.fromList(bytes);
  final document = parseLegacyWordDocument(bytes);
  final output = convertLegacyWordDocument(document).bytes;
  _unchanged(bytes, original);
  final xml = XmlDocument.parse(
    utf8.decode(
      ZipDecoder().decodeBytes(output).findFile('word/document.xml')!.content,
    ),
  );
  return (document, xml);
}

void _reject(Uint8List bytes) {
  final original = Uint8List.fromList(bytes);
  try {
    parseLegacyWordDocument(bytes);
  } on FormatException {
    _unchanged(bytes, original);
    return;
  }
  throw StateError('Malformed binary property contract was accepted.');
}

void _unchanged(Uint8List bytes, Uint8List original) {
  _require(bytes.length == original.length, 'Source size changed.');
  for (var index = 0; index < bytes.length; index++) {
    _require(bytes[index] == original[index], 'Source bytes changed.');
  }
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
