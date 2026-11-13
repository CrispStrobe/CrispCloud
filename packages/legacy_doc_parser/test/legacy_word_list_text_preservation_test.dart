// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/list_metadata_fixture.dart';
import 'support/list_sequence_fixture.dart';
import 'support/list_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

List<String> _labels(String html) => XmlDocument.parse(html)
    .findAllElements('span')
    .where((node) => node.getAttribute('data-word-list-label') == 'true')
    .map((node) => node.innerText)
    .toList();

XmlDocument _numbering(LegacyWordDocument document) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder()
        .decodeBytes(convertLegacyWordDocument(document).bytes)
        .findFile('word/numbering.xml')!
        .content,
  ),
);

void main() {
  for (final (name, labels) in [
    ('uncommon-format-literal', ['Appendix']),
    ('uncommon-format-ancestor', ['3.', '3 Appendix']),
    ('uncommon-format-legal', ['7.']),
  ]) {
    test('resolves only the number formats actually used by $name', () {
      final source = listMetadataFixture(name);
      final before = source.toList();
      final document = parseLegacyWordDocument(source);
      expect(_labels(document.safeHtml), labels);
      expect(document.safeHtml, isNot(contains('data-word-numbering=')));
      expect(
        _numbering(document)
            .findAllElements('numFmt', namespace: _w)
            .map((node) => node.getAttribute('val', namespace: _w)),
        contains('hebrew1'),
      );
      expect(source, before);
    });
  }

  test('literal label does not depend on any available numeric formatter', () {
    // All other formats are either prohibited in LVLF or separately tested
    // bullet/none levels. No placeholder uses the numeric format here.
    for (var format = 0; format < 60; format++) {
      if (const {8, 9, 15, 19, 23}.contains(format)) continue;
      final document = parseLegacyWordDocument(
        listWordFixture(
          levels: [
            listFixtureLevel(
              format: format,
              text: 'Appendix',
              placeholders: [],
            ),
          ],
        ),
      );
      expect(_labels(document.safeHtml), ['Appendix'], reason: '$format');
      expect(
        document.safeHtml,
        isNot(contains('data-word-numbering=')),
        reason: '$format',
      );
    }
  });

  test('unavailable self-number format stays explicitly unsupported', () {
    final document = parseLegacyWordDocument(
      listWordFixture(levels: [listFixtureLevel(format: 45)]),
    );
    expect(_labels(document.safeHtml), isEmpty);
    expect(document.safeHtml, contains('data-word-numbering="unsupported"'));
    final native = _numbering(document);
    expect(
      native
          .findAllElements('numFmt', namespace: _w)
          .single
          .getAttribute('val', namespace: _w),
      'hebrew1',
    );
    expect(
      native
          .findAllElements('lvlText', namespace: _w)
          .single
          .getAttribute('val', namespace: _w),
      '%1.',
    );
  });

  test('unavailable ancestor never leaves a partially rendered label', () {
    final document = parseLegacyWordDocument(
      listSequenceFixture(
        [(1, 0), (1, 1)],
        levels: [
          listFixtureLevel(format: 45),
          listFixtureLevel(
            level: 1,
            text: 'Chapter \x00.\x01',
            placeholders: [9, 11],
          ),
          for (var level = 2; level < 9; level++)
            listFixtureLevel(level: level),
        ],
      ),
    );
    expect(_labels(document.safeHtml), isEmpty);
    expect(
      XmlDocument.parse(document.safeHtml)
          .findAllElements('p')
          .where(
            (node) => node.getAttribute('data-word-numbering') == 'unsupported',
          ),
      hasLength(2),
    );
  });

  for (final (name, text) in [
    ('literal-label-tab', 'A\tB'),
    ('tab-before-placeholder', 'A\t%1'),
    ('none-label-tab', 'A\tB'),
  ]) {
    test('preserves source TAB through numbering XML attributes: $name', () {
      final source = listMetadataFixture(name);
      final before = source.toList();
      final document = parseLegacyWordDocument(source);
      expect(document.numbering.single.levels.single.text, text);
      final native = _numbering(document);
      expect(
        native
            .findAllElements('lvlText', namespace: _w)
            .single
            .getAttribute('val', namespace: _w),
        text,
      );
      expect(source, before);
    });
  }

  test(
    'literal label still rejects forbidden controls and malformed Unicode',
    () {
      for (final text in ['A\x01B', 'A\nB', 'A\rB', 'A\ud800B']) {
        expect(
          () => parseLegacyWordDocument(
            listWordFixture(
              levels: [listFixtureLevel(text: text, placeholders: [])],
            ),
          ),
          throwsFormatException,
          reason: text.codeUnits.toString(),
        );
      }
    },
  );
}
