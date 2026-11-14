// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

const _red = LegacyWordShading(pattern: 'clear', backgroundHex: 'FF0000');
const _blue = LegacyWordShading(pattern: 'clear', backgroundHex: '0000FF');
const _solid = LegacyWordShading(
  pattern: 'solid',
  foregroundHex: '00FF00',
  backgroundHex: 'FF0000',
);
const _nil = LegacyWordShading(pattern: 'nil');
const _unmapped = LegacyWordShading(
  pattern: null,
  rawPattern: 63,
  foregroundHex: '00FF00',
  backgroundHex: 'FFFF00',
);

/// Independently specified expected shading for both public input locations.
const publicCellShadingCases = [
  PublicCellShadingCase('absent'),
  PublicCellShadingCase(
    'formatting-clear',
    formatting: _red,
    expected: _red,
    previewColor: 'FF0000',
  ),
  PublicCellShadingCase(
    'formatting-solid',
    formatting: _solid,
    expected: _solid,
    previewColor: '00FF00',
  ),
  PublicCellShadingCase(
    'legacy-only',
    legacy: _blue,
    expected: _blue,
    previewColor: '0000FF',
  ),
  PublicCellShadingCase(
    'both-equal',
    legacy: _red,
    formatting: _red,
    expected: _red,
    previewColor: 'FF0000',
  ),
  PublicCellShadingCase(
    'legacy-override',
    legacy: _blue,
    formatting: _red,
    expected: _blue,
    previewColor: '0000FF',
  ),
  PublicCellShadingCase(
    'legacy-nil-override',
    legacy: _nil,
    formatting: _red,
    expected: _nil,
  ),
  PublicCellShadingCase(
    'legacy-unmapped-override',
    legacy: _unmapped,
    formatting: _red,
    expected: _unmapped,
    previewColor: 'FFFF00',
    approximatePreview: true,
  ),
  PublicCellShadingCase(
    'formatting-unmapped',
    formatting: _unmapped,
    expected: _unmapped,
    previewColor: 'FFFF00',
    approximatePreview: true,
  ),
];

class PublicCellShadingCase {
  const PublicCellShadingCase(
    this.name, {
    this.legacy,
    this.formatting,
    this.expected,
    this.previewColor,
    this.approximatePreview = false,
  });

  final String name;
  final LegacyWordShading? legacy, formatting, expected;
  final String? previewColor;
  final bool approximatePreview;

  LegacyWordDocument document() =>
      publicCellShadingDocument(legacy: legacy, formatting: formatting);
}

LegacyWordDocument publicCellShadingDocument({
  LegacyWordShading? legacy,
  LegacyWordShading? formatting,
}) => LegacyWordDocument(
  blocks: [
    LegacyWordTable(
      startCp: 0,
      endCp: 3,
      rows: [
        LegacyWordTableRow(
          cells: [
            LegacyWordTableCell(
              widthTwips: 1800,
              paragraphs: const [
                LegacyWordParagraph(
                  startCp: 0,
                  endCp: 2,
                  runs: [LegacyWordRun(startCp: 0, endCp: 1, text: 'A')],
                ),
              ],
              shading: legacy,
              formatting: LegacyWordTableCellFormat(shading: formatting),
            ),
          ],
        ),
      ],
    ),
  ],
  sections: const [LegacyWordSection(startCp: 0, endCp: 3)],
  plainText: 'A',
  safeHtml: '',
);
