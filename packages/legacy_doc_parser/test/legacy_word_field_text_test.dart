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
  for (final whitespace in ['\t', '\r', '\n', '\r\n']) {
    test('retains instruction whitespace ${jsonEncode(whitespace)}', () {
      final instruction = ' QUOTE "one${whitespace}two & <three> 😀" ';
      final bytes = storyWordFixture(
        main: 'A\x13$instruction\x14Cached\x15Z\r',
      );
      final original = Uint8List.fromList(bytes);
      final parsed = parseLegacyWordDocument(bytes);
      final converted = convertLegacyWordDocument(parsed);
      final xml = _xml(converted.bytes);
      expect(parsed.fields.single.instruction, instruction);
      expect(
        _elements(xml, 'instrText').map((e) => e.innerText).join(),
        instruction,
      );
      expect(_elements(xml, 't').map((e) => e.innerText).join(), 'ACachedZ');
      expect(converted.preservedCounts['fields'], 1);
      expect(bytes, orderedEquals(original));
    });
  }

  test('retains whitespace in nested instruction slices', () {
    const child = ' QUOTE "one\ttwo" ';
    const before = ' IF "before\tafter" = "before\tafter" ';
    const after = ' "no\r\nyes" ';
    final source = storyWordFixture(
      main: 'A\x13$before\x13$child\x14Child\x15$after\x14Visible\x15Z\r',
    );
    final converted = convertLegacyWordToStructuredDocx(source);
    final xml = _xml(converted.bytes);
    expect(_elements(xml, 'instrText').map((e) => e.innerText), [
      before,
      child,
      after,
    ]);
    expect(converted.preservedCounts['fields'], 2);
  });

  test('cached field metadata retains supported Word text controls', () {
    final source = storyWordFixture(
      main: 'A\x13 QUOTE "cached" \x14co\x1eop\x1ferate\x0enext\x15Z\r',
    );
    final parsed = parseLegacyWordDocument(source);
    expect(parsed.fields.single.storedResult, 'co\u2011op\u00aderate\x0enext');
    final xml = _xml(convertLegacyWordDocument(parsed).bytes);
    expect(
      _elements(xml, 't').map((e) => e.innerText).join(),
      'Aco\u2011op\u00aderatenextZ',
    );
    expect(
      _elements(xml, 'br').single.getAttribute('type', namespace: _w),
      'column',
    );
  });

  test(
    'rejects invalid XML controls and unpaired surrogates in public text',
    () {
      for (final text in [
        '\x00',
        '\x01',
        '\x0b',
        '\x1e',
        '\ufffe',
        '\uffff',
        '\ud800',
        '\udc00',
      ]) {
        final document = LegacyWordDocument(
          blocks: [
            LegacyWordParagraph(
              startCp: 0,
              endCp: text.length + 1,
              runs: [LegacyWordRun(startCp: 0, endCp: text.length, text: text)],
            ),
          ],
          sections: const [],
          plainText: text,
          safeHtml: '',
        );
        expect(
          () => convertLegacyWordDocument(document),
          throwsA(
            isA<LegacyWordConversionException>().having(
              (e) => e.issue,
              'issue',
              LegacyWordConversionIssue.invalidText,
            ),
          ),
          reason: jsonEncode(text),
        );
      }
    },
  );
}
