// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/nested_field_fixture.dart';
import 'support/story_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

XmlDocument _part(Uint8List bytes, String name) => XmlDocument.parse(
  utf8.decode(ZipDecoder().decodeBytes(bytes).findFile(name)!.content),
);

void main() {
  test('formula fields retain locked syntax and stale cached values', () {
    final source = nestedFieldFixture('formula');
    final original = Uint8List.fromList(source);
    final document = parseLegacyWordDocument(source);
    final field = document.fields.single;
    expect(field.type, '=');
    expect(field.instruction, ' = 1 + 1 ');
    expect(field.storedResult, '999');
    expect(document.plainText, 'A999Z');

    final result = convertLegacyWordDocument(document);
    final xml = _part(result.bytes, 'word/document.xml');
    expect(
      xml.findAllElements('instrText', namespace: _w).single.innerText,
      field.instruction,
    );
    final markers = xml.findAllElements('fldChar', namespace: _w).toList();
    expect(
      markers.map(
        (marker) => marker.getAttribute('fldCharType', namespace: _w),
      ),
      ['begin', 'separate', 'end'],
    );
    expect(markers.first.getAttribute('fldLock', namespace: _w), '1');
    expect(markers.first.getAttribute('dirty', namespace: _w), '0');
    expect(
      xml
          .findAllElements('t', namespace: _w)
          .map((text) => text.innerText)
          .join(),
      'A999Z',
    );
    final settings = _part(result.bytes, 'word/settings.xml');
    expect(
      settings
          .findAllElements('updateFields', namespace: _w)
          .single
          .getAttribute('val', namespace: _w),
      'false',
    );
    expect(result.preservedCounts['fields'], 1);
    expect(
      result.limitations,
      isNot(contains(LegacyWordConversionLimitation.fieldsLists)),
    );
    expect(source, orderedEquals(original));
  });

  test('formula recognition allows leading tabs and adjacent operands', () {
    for (final instruction in ['\t= SUM(ABOVE) ', '=1+1']) {
      final document = parseLegacyWordDocument(
        storyWordFixture(main: 'A\x13$instruction\x1442\x15Z\r'),
      );
      expect(document.fields.single.type, '=');
      expect(document.fields.single.storedResult, '42');
      final result = convertLegacyWordDocument(document);
      final xml = _part(result.bytes, 'word/document.xml');
      expect(
        xml.findAllElements('instrText', namespace: _w).single.innerText,
        instruction,
      );
      expect(result.preservedCounts['fields'], 1);
    }
  });

  test('a formula nested in an instruction keeps its own cached result', () {
    final document = parseLegacyWordDocument(
      storyWordFixture(
        main:
            'A\x13 IF \x13 = 1 + 1 \x14999\x15 = 999 "Y" "N" '
            '\x14Y\x15Z\r',
      ),
    );
    expect(document.fields.map((field) => field.type), ['=', 'IF']);
    expect(document.plainText, 'AYZ');
    final result = convertLegacyWordDocument(document);
    final xml = _part(result.bytes, 'word/document.xml');
    expect(
      xml
          .findAllElements('instrText', namespace: _w)
          .map((text) => text.innerText),
      [' IF ', ' = 1 + 1 ', ' = 999 "Y" "N" '],
    );
    expect(result.preservedCounts['fields'], 2);
  });

  test('unsupported nested instructions keep a formula inert', () {
    final result = convertLegacyWordToStructuredDocx(
      storyWordFixture(
        main:
            'A\x13 = \x13 DDEAUTO server topic item \x14Hidden\x15 + 1 '
            '\x14999\x15Z\r',
      ),
    );
    final xml = _part(result.bytes, 'word/document.xml');
    expect(xml.findAllElements('fldChar', namespace: _w), isEmpty);
    expect(xml.findAllElements('instrText', namespace: _w), isEmpty);
    expect(
      xml
          .findAllElements('t', namespace: _w)
          .map((text) => text.innerText)
          .join(),
      'A999Z',
    );
    expect(
      result.limitations,
      contains(LegacyWordConversionLimitation.fieldsLists),
    );
  });

  test('malformed nested formula markers remain rejected', () {
    expect(
      () => parseLegacyWordDocument(
        storyWordFixture(main: 'A\x13 = \x13 PAGE \x142\x15 + 1\r'),
      ),
      throwsFormatException,
    );
  });
}
