// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import 'structured_word_fixture.dart';

/// MS-DOC 2.6.4, XAS_nonNeg and YAS_nonNeg, independently of integer storage.
const sectionGeometryProperties = [
  SectionGeometryProperty('width', 0xb01f, 144, 31680, 'pgSz', 'w'),
  SectionGeometryProperty('height', 0xb020, 144, 31680, 'pgSz', 'h'),
  SectionGeometryProperty('top', 0x9023, -31665, 31665, 'pgMar', 'top'),
  SectionGeometryProperty('bottom', 0x9024, -31665, 31665, 'pgMar', 'bottom'),
  SectionGeometryProperty('left', 0xb021, 0, 31680, 'pgMar', 'left'),
  SectionGeometryProperty('right', 0xb022, 0, 31680, 'pgMar', 'right'),
  SectionGeometryProperty('header', 0xb017, 0, 31680, 'pgMar', 'header'),
  SectionGeometryProperty('footer', 0xb018, 0, 31680, 'pgMar', 'footer'),
  SectionGeometryProperty('columns', 0x900c, 0, 31680, 'cols', 'space'),
  SectionGeometryProperty('gutter', 0xb025, 0, 65535, 'pgMar', 'gutter'),
];

class SectionGeometryProperty {
  const SectionGeometryProperty(
    this.name,
    this.opcode,
    this.minimum,
    this.maximum,
    this.xmlTag,
    this.xmlAttribute,
  );

  final String name, xmlTag, xmlAttribute;
  final int opcode, minimum, maximum;

  List<int> get validValues => {
    minimum,
    maximum,
    if (minimum <= 0) 0,
    if (name == 'gutter') ...[31680, 31681],
  }.toList();

  List<int> get invalidValues => {
    minimum - 1,
    maximum + 1,
    if (minimum > 0) 0,
    if (minimum < 0) ...[-32768, 32767],
    if (minimum >= 0 && maximum < 65535) 65535,
  }.toList();

  bool encodable(int value) => minimum < 0
      ? value >= -32768 && value <= 32767
      : value >= 0 && value <= 65535;

  bool nativeRepresentable(int value) => name != 'gutter' || value <= 31680;

  int? read(LegacyWordSection section) => switch (name) {
    'width' => section.pageWidthTwips,
    'height' => section.pageHeightTwips,
    'top' => section.marginTopTwips,
    'bottom' => section.marginBottomTwips,
    'left' => section.marginLeftTwips,
    'right' => section.marginRightTwips,
    'header' => section.headerDistanceTwips,
    'footer' => section.footerDistanceTwips,
    'columns' => section.columnsSpaceTwips,
    'gutter' => section.gutterTwips,
    _ => throw StateError('Unknown section geometry property'),
  };

  LegacyWordSection section(int? value) => LegacyWordSection(
    startCp: 0,
    endCp: 2,
    pageWidthTwips: name == 'width' ? value : null,
    pageHeightTwips: name == 'height' ? value : null,
    marginTopTwips: name == 'top' ? value : null,
    marginBottomTwips: name == 'bottom' ? value : null,
    marginLeftTwips: name == 'left' ? value : null,
    marginRightTwips: name == 'right' ? value : null,
    headerDistanceTwips: name == 'header' ? value : null,
    footerDistanceTwips: name == 'footer' ? value : null,
    columnsSpaceTwips: name == 'columns' ? value : null,
    gutterTwips: name == 'gutter' ? value : null,
  );
}

LegacyWordDocument sectionGeometryDocument(
  SectionGeometryProperty property,
  int? value, {
  bool historical = false,
}) {
  final section = property.section(value);
  return LegacyWordDocument(
    blocks: const [
      LegacyWordParagraph(
        startCp: 0,
        endCp: 2,
        runs: [LegacyWordRun(startCp: 0, endCp: 1, text: 'A')],
      ),
    ],
    sections: [
      if (historical)
        LegacyWordSection(
          startCp: 0,
          endCp: 2,
          formattingRevision: LegacyWordSectionFormattingRevision(
            previousSection: section,
          ),
        )
      else
        section,
    ],
    plainText: 'A',
    safeHtml: '',
  );
}

Uint8List sectionGeometryFixture(
  SectionGeometryProperty property,
  int value, {
  bool historical = false,
}) => StructuredWordFixture(
  pieces: const [WordFixturePiece('A\r')],
  sections: [
    WordFixtureSection(2, [
      ...wordSprm(property.opcode, wordU16(value)),
      if (historical) ...[
        ...wordSprm(0x3239, [1]),
        ...wordSprm(property.opcode, wordU16(property.minimum)),
      ],
    ]),
  ],
).build();
