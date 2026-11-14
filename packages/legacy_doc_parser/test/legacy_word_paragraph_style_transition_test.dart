// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/paragraph_style_transition_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

LegacyWordParagraph _paragraph(LegacyWordDocument document) {
  final first = document.blocks.first;
  if (first is LegacyWordParagraph) return first;
  return (first as LegacyWordTable).rows.single.cells.single.blocks.first
      as LegacyWordParagraph;
}

XmlDocument _xml(LegacyWordDocument document) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder()
        .decodeBytes(convertLegacyWordDocument(document).bytes)
        .findFile('word/document.xml')!
        .content,
  ),
);

void main() {
  for (final kind in paragraphTransientStyleKinds.keys) {
    for (final path in ['papx', 'prm', 'split-prm', 'indirect']) {
      test('$path permits temporary $kind paragraph style then resets', () {
        final document = parseLegacyWordDocument(
          paragraphStyleTransitionFixture(kind, path: path),
        );
        final paragraph = _paragraph(document);
        expect(paragraph.runs.map((run) => run.text).join(), 'A😀 style');
        expect(paragraph.style.styleIndex, 20);
        expect(paragraph.style.styleName, 'Final paragraph');
        expect(paragraph.style.spaceBeforeTwips, 480);
        expect(paragraph.style.leftIndentTwips, 360);
        expect(paragraph.style.alignment, LegacyWordAlignment.center);
        expect(paragraph.runs.every((run) => run.style.italic), isTrue);
        expect(paragraph.runs.any((run) => run.style.bold), isFalse);
        final xml = _xml(document);
        expect(
          xml
              .findAllElements('t', namespace: _w)
              .map((e) => e.innerText)
              .join(),
          'A😀 style',
        );
      });
    }
    for (final path in ['papx', 'table']) {
      test('$path captures document defaults for temporary $kind style', () {
        final document = parseLegacyWordDocument(
          paragraphStyleTransitionFixture(kind, path: path, historical: true),
        );
        final paragraph = _paragraph(document);
        final previous = paragraph.formattingRevision!.previousStyle!;
        expect(previous.styleIndex, paragraphTransientStyleKinds[kind]);
        expect(previous.spaceBeforeTwips, 0);
        expect(previous.leftIndentTwips, 0);
        expect(previous.alignment, LegacyWordAlignment.left);
        expect(paragraph.style.styleIndex, 20);
        expect(paragraph.style.spaceBeforeTwips, 480);
        expect(paragraph.style.leftIndentTwips, 360);
        expect(paragraph.style.alignment, LegacyWordAlignment.center);
        if (path == 'table') {
          expect(document.blocks, hasLength(1));
          expect(document.blocks.single, isA<LegacyWordTable>());
        }
        final revision = _xml(
          document,
        ).findAllElements('pPrChange', namespace: _w).single;
        final old = revision.getElement('pPr', namespace: _w)!;
        expect(
          old
              .getElement('jc', namespace: _w)
              ?.getAttribute('val', namespace: _w),
          'left',
        );
      });
    }
    test('the final $kind paragraph style is still rejected', () {
      expect(
        () => parseLegacyWordDocument(
          paragraphStyleTransitionFixture(kind, finalSelection: false),
        ),
        throwsFormatException,
      );
    });
  }
}
