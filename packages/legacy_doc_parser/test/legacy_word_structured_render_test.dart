// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/src/legacy_word_structured_model.dart';
import 'package:legacy_doc_parser/src/legacy_word_structured_render.dart';
import 'package:test/test.dart';

LegacyWordParagraph _paragraph(
  String text, {
  LegacyWordCharacterStyle style = const LegacyWordCharacterStyle(),
}) => LegacyWordParagraph(
  startCp: 0,
  endCp: text.length + 1,
  runs: [
    LegacyWordRun(startCp: 0, endCp: text.length, text: text, style: style),
  ],
);

void main() {
  test('escapes text and treats a hostile font name only as a CSS string', () {
    final html = renderLegacyWordHtml([
      _paragraph(
        '<img src="https://invalid.test/">& text',
        style: const LegacyWordCharacterStyle(
          fontName: "X';background-image:url(https://invalid.test/);x:'",
          colorHex: 'red;display:none',
        ),
      ),
    ]);
    expect(html, contains('&lt;img src="https://invalid.test/"&gt;&amp; text'));
    expect(html, isNot(contains('<img')));
    expect(html, isNot(contains('url(')));
    expect(html, isNot(contains('background-image:')));
    expect(html, isNot(contains('display:none')));
    expect(html, contains("font-family:'\\58 "));
  });

  test('retains visible revisions and formatting while hiding hidden runs', () {
    final html = renderLegacyWordHtml([
      const LegacyWordParagraph(
        startCp: 0,
        endCp: 9,
        runs: [
          LegacyWordRun(
            startCp: 0,
            endCp: 3,
            text: 'old',
            deleted: true,
            style: LegacyWordCharacterStyle(bold: true, colorHex: '112233'),
          ),
          LegacyWordRun(
            startCp: 3,
            endCp: 6,
            text: 'new',
            inserted: true,
            style: LegacyWordCharacterStyle(italic: true, underline: true),
          ),
          LegacyWordRun(
            startCp: 6,
            endCp: 8,
            text: 'hidden-value',
            style: LegacyWordCharacterStyle(hidden: true),
          ),
        ],
      ),
    ]);
    expect(html, contains('<del'));
    expect(html, contains('<ins'));
    expect(html, contains('old'));
    expect(html, contains('new'));
    expect(html, contains('font-weight:bold'));
    expect(html, contains('color:#112233'));
    expect(html, contains('font-style:italic'));
    expect(html, isNot(contains('hidden-value')));
  });

  test('keeps higher heading levels, paragraph layout and manual breaks', () {
    final html = renderLegacyWordHtml([
      const LegacyWordParagraph(
        startCp: 0,
        endCp: 5,
        style: LegacyWordParagraphStyle(
          headingLevel: 7,
          alignment: LegacyWordAlignment.right,
          leftIndentTwips: 720,
          firstLineIndentTwips: -360,
          spaceAfterTwips: 120,
          lineSpacingMultiple: true,
          lineSpacingValue: 360,
          keepTogether: true,
        ),
        runs: [LegacyWordRun(startCp: 0, endCp: 4, text: 'A\nB\f')],
      ),
    ]);
    expect(html, contains('role="heading" aria-level="7"'));
    expect(html, contains('text-align:right'));
    expect(html, contains('margin-left:36.0pt'));
    expect(html, contains('text-indent:-18.0pt'));
    expect(html, contains('margin-bottom:6.0pt'));
    expect(html, contains('line-height:1.5'));
    expect(html, contains('break-inside:avoid'));
    expect(html, contains('A<br>B<br style="break-after:page;">'));
  });

  test(
    'horizontal merges retain continuation paragraphs without a fake header',
    () {
      final html = renderLegacyWordHtml([
        LegacyWordTable(
          startCp: 0,
          endCp: 5,
          rows: [
            LegacyWordTableRow(
              cells: [
                LegacyWordTableCell(
                  paragraphs: [_paragraph('first')],
                  widthTwips: 1440,
                  mergeStart: true,
                ),
                LegacyWordTableCell(
                  paragraphs: [_paragraph('continuation')],
                  widthTwips: 720,
                  mergeContinue: true,
                ),
              ],
            ),
          ],
        ),
      ]);
      expect(html, contains('<td colspan="2"'));
      expect(html, contains('width:108.0pt'));
      expect(html, contains('first'));
      expect(html, contains('continuation'));
      expect(html, isNot(contains('<th')));
      expect(RegExp('<td[ >]').allMatches(html), hasLength(1));
    },
  );

  test('vertical merges retain continuation text and render orphan cells', () {
    final html = renderLegacyWordHtml([
      LegacyWordTable(
        startCp: 0,
        endCp: 12,
        rows: [
          LegacyWordTableRow(
            isHeader: true,
            cells: [
              LegacyWordTableCell(
                paragraphs: [_paragraph('head')],
                verticalMergeStart: true,
              ),
              LegacyWordTableCell(paragraphs: [_paragraph('other')]),
            ],
          ),
          LegacyWordTableRow(
            cells: [
              LegacyWordTableCell(
                paragraphs: [_paragraph('continued')],
                verticalMergeContinue: true,
              ),
              LegacyWordTableCell(
                paragraphs: [_paragraph('orphan')],
                verticalMergeContinue: true,
              ),
            ],
          ),
        ],
      ),
    ]);
    expect(html, contains('<th scope="col" rowspan="2"'));
    for (final text in ['head', 'other', 'continued', 'orphan']) {
      expect(RegExp('>$text<').allMatches(html), hasLength(1));
    }
    expect(RegExp('<td[ >]').allMatches(html), hasLength(1));
  });

  test('counts escaped UTF-8 output against the preview size budget', () {
    final paragraph = _paragraph('&' * 256);
    expect(
      () => renderLegacyWordHtml(List.filled(25000, paragraph)),
      throwsFormatException,
    );
  });

  test(
    'does not split a Unicode surrogate pair at the escaping chunk boundary',
    () {
      final html = renderLegacyWordHtml([_paragraph('${'a' * 4095}😀z')]);
      expect(html, contains('😀z'));
      expect(html, isNot(contains('�')));
    },
  );
}
