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

XmlDocument _xml(Uint8List bytes) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content,
  ),
);

List<String> _markers(XmlDocument xml) => [
  for (final element in xml.findAllElements('fldChar', namespace: _w))
    element.getAttribute('fldCharType', namespace: _w)!,
];

String _text(XmlDocument xml) => xml
    .findAllElements('t', namespace: _w)
    .map((element) => element.innerText)
    .join();

LegacyWordDocument _overrideFieldTypes(
  String source,
  Map<String, String> overrides,
) {
  final parsed = parseLegacyWordDocument(storyWordFixture(main: source));
  return LegacyWordDocument(
    blocks: parsed.blocks,
    sections: parsed.sections,
    plainText: parsed.plainText,
    safeHtml: parsed.safeHtml,
    fields: [
      for (final field in parsed.fields)
        LegacyWordField(
          id: field.id,
          storyId: field.storyId,
          startCp: field.startCp,
          endCp: field.endCp,
          instruction: field.instruction,
          storedResult: field.storedResult,
          type: overrides[field.type] ?? field.type,
          separatorCp: field.separatorCp,
          parentId: field.parentId,
        ),
    ],
  );
}

// Independently project complex-field XML: text is visible only after every
// enclosing field's separator. No instruction or field evaluation is involved.
String _visibleText(XmlDocument xml) {
  final result = StringBuffer();
  final results = <bool>[];
  for (final run in xml.findAllElements('r', namespace: _w)) {
    final marker = run.getElement('fldChar', namespace: _w);
    if (marker != null) {
      switch (marker.getAttribute('fldCharType', namespace: _w)) {
        case 'begin':
          results.add(false);
        case 'separate':
          expect(results, isNotEmpty);
          results[results.length - 1] = true;
        case 'end':
          expect(results, isNotEmpty);
          results.removeLast();
      }
    } else if (results.every((value) => value)) {
      for (final text in run.findElements('t', namespace: _w)) {
        result.write(text.innerText);
      }
    }
  }
  expect(results, isEmpty);
  return result.toString();
}

void main() {
  test('public model field types cannot authorize a different instruction', () {
    final result = convertLegacyWordDocument(
      _overrideFieldTypes('A\x13 DDEAUTO server topic item \x14Cached\x15Z\r', {
        'DDEAUTO': 'PAGE',
      }),
    );
    final xml = _xml(result.bytes);
    expect(_markers(xml), isEmpty);
    expect(xml.findAllElements('instrText', namespace: _w), isEmpty);
    expect(_visibleText(xml), 'ACachedZ');
    expect(
      result.limitations,
      contains(LegacyWordConversionLimitation.fieldsLists),
    );
  });

  test('a mislabeled nested instruction keeps the containing field inert', () {
    final result = convertLegacyWordDocument(
      _overrideFieldTypes(
        'A\x13 REF \x13 INCLUDETEXT "https://invalid.test/" '
        '\x14Cached\x15 \x14Outer\x15Z\r',
        {'INCLUDETEXT': 'PAGE'},
      ),
    );
    final xml = _xml(result.bytes);
    expect(_markers(xml), isEmpty);
    expect(xml.findAllElements('instrText', namespace: _w), isEmpty);
    expect(_visibleText(xml), 'AOuterZ');
  });

  test('matching public field keywords remain case insensitive', () {
    final result = convertLegacyWordDocument(
      _overrideFieldTypes('A\x13\tpage \x142\x15Z\r', {'PAGE': 'page'}),
    );
    final xml = _xml(result.bytes);
    expect(_markers(xml), ['begin', 'separate', 'end']);
    expect(_visibleText(xml), 'A2Z');
    expect(result.preservedCounts['fields'], 1);
  });

  test('nested cached results stay inside the enclosing field instruction', () {
    final bytes = nestedFieldFixture('nested-results');
    final original = Uint8List.fromList(bytes);
    final document = parseLegacyWordDocument(bytes);
    expect(
      document.fields.singleWhere((field) => field.type == 'REF').storedResult,
      'pre2post',
    );
    final converted = convertLegacyWordDocument(document);
    final xml = _xml(converted.bytes);
    expect(_markers(xml), [
      'begin',
      'begin',
      'separate',
      'begin',
      'separate',
      'end',
      'end',
      'separate',
      'end',
    ]);
    expect(_text(xml), 'Apre2postVisibleZ');
    expect(_visibleText(xml), 'AVisibleZ');
    expect(converted.preservedCounts['fields'], 3);
    expect(bytes, orderedEquals(original));
  });

  test(
    'private results do not emit nested instruction text or field markers',
    () {
      final converted = convertLegacyWordToStructuredDocx(
        nestedFieldFixture('private-result'),
      );
      final xml = _xml(converted.bytes);
      expect(_markers(xml), ['begin', 'separate', 'end']);
      expect(_text(xml), 'AZ');
      expect(xml.toXmlString(), isNot(contains('Private')));
      expect(converted.preservedCounts['fields'], 1);
    },
  );

  test(
    'private nested instruction results remain empty across deeper fields',
    () {
      final converted = convertLegacyWordToStructuredDocx(
        nestedFieldFixture('private-instruction-result'),
      );
      final xml = _xml(converted.bytes);
      expect(_markers(xml), [
        'begin',
        'begin',
        'separate',
        'end',
        'separate',
        'end',
      ]);
      expect(_text(xml), 'AVisibleZ');
      expect(_visibleText(xml), 'AVisibleZ');
      expect(xml.toXmlString(), isNot(contains('Private')));
      expect(converted.preservedCounts['fields'], 2);
    },
  );

  test(
    'unsupported nested result fields retain only cached text and evidence',
    () {
      final converted = convertLegacyWordToStructuredDocx(
        nestedFieldFixture('unsupported-result'),
      );
      final xml = _xml(converted.bytes);
      expect(_markers(xml), [
        'begin',
        'begin',
        'separate',
        'end',
        'separate',
        'end',
      ]);
      expect(_text(xml), 'AprecachedpostVisibleZ');
      expect(_visibleText(xml), 'AVisibleZ');
      expect(xml.toXmlString(), isNot(contains('INCLUDETEXT')));
      expect(converted.preservedCounts['fields'], 2);
      expect(
        converted.limitations,
        contains(LegacyWordConversionLimitation.fieldsLists),
      );
      final manifest = utf8.decode(
        ZipDecoder()
            .decodeBytes(converted.bytes)
            .findFile('word/evidence/manifest.json')!
            .content,
      );
      expect(manifest, contains('INCLUDETEXT'));
    },
  );
}
