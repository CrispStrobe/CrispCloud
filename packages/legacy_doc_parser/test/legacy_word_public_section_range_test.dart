// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/section_geometry_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _paragraphs = [
  LegacyWordParagraph(
    startCp: 0,
    endCp: 2,
    runs: [LegacyWordRun(startCp: 0, endCp: 1, text: 'A')],
  ),
  LegacyWordParagraph(
    startCp: 2,
    endCp: 4,
    runs: [LegacyWordRun(startCp: 2, endCp: 3, text: 'B')],
  ),
];

LegacyWordDocument _document(
  List<LegacyWordSection> sections, {
  int paragraphCount = 1,
}) => LegacyWordDocument(
  blocks: _paragraphs.take(paragraphCount).toList(),
  sections: sections,
  plainText: 'AB'.substring(0, paragraphCount),
  safeHtml: '',
);

XmlDocument _xml(LegacyWordStructuredConversion result) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder()
        .decodeBytes(result.bytes)
        .findFile('word/document.xml')!
        .content,
  ),
);

void main() {
  final invalidRanges = <String, List<LegacyWordSection>>{
    'missing initial coverage': const [LegacyWordSection(startCp: 1, endCp: 2)],
    'terminal overrun': const [LegacyWordSection(startCp: 0, endCp: 3)],
    'terminal underrun': const [LegacyWordSection(startCp: 0, endCp: 1)],
    'unconsumed intermediate boundary': const [
      LegacyWordSection(startCp: 0, endCp: 3),
      LegacyWordSection(startCp: 3, endCp: 4),
    ],
    'unconsumed malformed section': const [
      LegacyWordSection(startCp: 0, endCp: 3, marginLeftTwips: -1),
      LegacyWordSection(startCp: 3, endCp: 4),
    ],
  };
  for (final entry in invalidRanges.entries) {
    test('public section rejects ${entry.key}', () {
      expect(
        () => convertLegacyWordDocument(_document(entry.value)),
        throwsFormatException,
      );
    });
  }

  for (final emptyInitial in [false, true]) {
    test('empty body cannot silently drop a section ($emptyInitial)', () {
      final boundary = emptyInitial ? 0 : 1;
      final document = _document([
        LegacyWordSection(startCp: 0, endCp: boundary),
        LegacyWordSection(startCp: boundary, endCp: 2),
      ], paragraphCount: 0);
      expect(() => convertLegacyWordDocument(document), throwsFormatException);
    });
  }

  test(
    'two sections keep their distinct geometry and paragraph boundaries',
    () {
      final result = convertLegacyWordDocument(
        _document(const [
          LegacyWordSection(
            startCp: 0,
            endCp: 2,
            pageWidthTwips: 10000,
            marginLeftTwips: 100,
          ),
          LegacyWordSection(
            startCp: 2,
            endCp: 4,
            pageWidthTwips: 12000,
            marginLeftTwips: 200,
          ),
        ], paragraphCount: 2),
      );
      final xml = _xml(result);
      final sections = xml.findAllElements('sectPr', namespace: _w).toList();
      expect(result.preservedCounts['sections'], 2);
      expect(sections, hasLength(2));
      expect(
        sections.map(
          (section) => section
              .getElement('pgSz', namespace: _w)!
              .getAttribute('w', namespace: _w),
        ),
        ['10000', '12000'],
      );
      expect(
        sections.map(
          (section) => section
              .getElement('pgMar', namespace: _w)!
              .getAttribute('left', namespace: _w),
        ),
        ['100', '200'],
      );
      expect(sections.first.parentElement!.name.local, 'pPr');
      expect(sections.last.parentElement!.name.local, 'body');
      expect(
        xml.findAllElements('t', namespace: _w).map((text) => text.innerText),
        ['A', 'B'],
      );
    },
  );

  test('empty initial section remains a distinct emitted section', () {
    final result = convertLegacyWordDocument(
      _document(const [
        LegacyWordSection(startCp: 0, endCp: 0, pageWidthTwips: 10000),
        LegacyWordSection(startCp: 0, endCp: 2, pageWidthTwips: 12000),
      ]),
    );
    expect(result.preservedCounts['sections'], 2);
    expect(
      _xml(result)
          .findAllElements('pgSz', namespace: _w)
          .map((size) => size.getAttribute('w', namespace: _w)),
      ['10000', '12000'],
    );
  });

  test('empty body with one section retains its page settings', () {
    final result = convertLegacyWordDocument(
      _document(const [
        LegacyWordSection(startCp: 0, endCp: 1, pageWidthTwips: 12000),
      ], paragraphCount: 0),
    );
    expect(result.preservedCounts['sections'], 1);
    expect(
      _xml(result)
          .findAllElements('pgSz', namespace: _w)
          .single
          .getAttribute('w', namespace: _w),
      '12000',
    );
  });

  for (final property in sectionGeometryProperties) {
    test(
      'inactive historical ${property.name} still validates its source domain',
      () {
        final document = _document([
          LegacyWordSection(
            startCp: 0,
            endCp: 2,
            formattingRevision: LegacyWordSectionFormattingRevision(
              marked: false,
              previousSection: property.section(property.minimum - 1),
            ),
          ),
        ]);
        expect(
          () => convertLegacyWordDocument(document),
          throwsFormatException,
        );
      },
    );
  }

  test('inactive binary-valid large gutter does not become active OOXML', () {
    final document = _document(const [
      LegacyWordSection(
        startCp: 0,
        endCp: 2,
        marginLeftTwips: 100,
        formattingRevision: LegacyWordSectionFormattingRevision(
          marked: false,
          previousSection: LegacyWordSection(
            startCp: 0,
            endCp: 2,
            gutterTwips: 65535,
          ),
        ),
      ),
    ]);
    final xml = _xml(convertLegacyWordDocument(document));
    expect(xml.findAllElements('sectPrChange', namespace: _w), isEmpty);
    final margins = xml.findAllElements('pgMar', namespace: _w).single;
    expect(margins.getAttribute('left', namespace: _w), '100');
    expect(margins.getAttribute('gutter', namespace: _w), '0');
  });
}
