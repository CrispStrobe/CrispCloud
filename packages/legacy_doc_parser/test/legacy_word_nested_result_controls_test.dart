// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/story_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

XmlDocument _xml(Uint8List bytes) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content,
  ),
);

Iterable<XmlElement> _elements(XmlNode node, String name) =>
    node.findAllElements(name, namespace: _w);

void main() {
  for (final (control, normalized, element, type) in [
    ('\t', '\t', 'tab', null),
    ('\n', '\n', 'br', null),
    ('\r', '\n', 'br', null),
    ('\x07', '\t', 'tab', null),
    ('\x0b', '\n', 'br', null),
    ('\x0c', '\x0c', 'br', 'page'),
    ('\x0e', '\x0e', 'br', 'column'),
    ('\x1e', '\u2011', null, null),
    ('\x1f', '\u00ad', null, null),
  ]) {
    test('retains nested cached result control ${jsonEncode(control)}', () {
      final source = storyWordFixture(
        main:
            'A\x13 IF \x13 QUOTE "text" \x14left${control}right\x15 '
            '= "comparison" "yes" "no" \x14Visible\x15Z\r',
      );
      final original = Uint8List.fromList(source);
      final parsed = parseLegacyWordDocument(source);
      final converted = convertLegacyWordDocument(parsed);
      final xml = _xml(converted.bytes);
      expect(
        parsed.fields.singleWhere((f) => f.type == 'QUOTE').storedResult,
        'left${normalized}right',
      );
      expect(
        _elements(
          xml,
          'fldChar',
        ).map((e) => e.getAttribute('fldCharType', namespace: _w)),
        ['begin', 'begin', 'separate', 'end', 'separate', 'end'],
      );
      expect(_elements(xml, 'instrText').map((e) => e.innerText), [
        ' IF ',
        ' QUOTE "text" ',
        ' = "comparison" "yes" "no" ',
      ]);
      expect(
        _elements(xml, 't').map((e) => e.innerText).join(),
        'Aleft${element == null ? normalized : ''}rightVisibleZ',
      );
      if (element != null) {
        expect(_elements(xml, element), hasLength(1));
        expect(
          _elements(xml, element).single.getAttribute('type', namespace: _w),
          type,
        );
      }
      expect(converted.preservedCounts['fields'], 2);
      expect(source, orderedEquals(original));
    });
  }

  for (final control in ['\x07', '\x0b', '\x0c', '\x0e', '\x1e', '\x1f']) {
    test('keeps literal instruction control ${jsonEncode(control)} inert', () {
      final converted = convertLegacyWordToStructuredDocx(
        storyWordFixture(
          main:
              'A\x13 IF \x13 QUOTE "left${control}right" \x14Child\x15 '
              '= "comparison" "yes" "no" \x14Visible\x15Z\r',
        ),
      );
      final xml = _xml(converted.bytes);
      expect(_elements(xml, 'fldChar'), isEmpty);
      expect(_elements(xml, 'instrText'), isEmpty);
      expect(_elements(xml, 't').map((e) => e.innerText).join(), 'AVisibleZ');
      expect(
        converted.limitations,
        contains(LegacyWordConversionLimitation.fieldsLists),
      );
    });
  }
}
