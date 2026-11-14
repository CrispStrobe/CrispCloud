// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import 'public_formatting_fixture.dart';

LegacyWordDocument publicTableFormattingDocument({
  required bool conditional,
  LegacyWordCharacterStyle? character,
  LegacyWordParagraphStyle? paragraph,
}) {
  final base = publicFormattingDocument(scope: 'paragraph');
  final text = LegacyWordTableTextFormat(
    character: character ?? const LegacyWordCharacterStyle(),
    paragraph: paragraph ?? const LegacyWordParagraphStyle(),
    characterProperties: character == null
        ? const {}
        : const {
            LegacyWordTableCharacterProperty.fontSize,
            LegacyWordTableCharacterProperty.position,
            LegacyWordTableCharacterProperty.spacing,
          },
    paragraphProperties: paragraph == null
        ? const {}
        : const {
            LegacyWordTableParagraphProperty.outline,
            LegacyWordTableParagraphProperty.before,
            LegacyWordTableParagraphProperty.after,
            LegacyWordTableParagraphProperty.leftIndent,
            LegacyWordTableParagraphProperty.rightIndent,
            LegacyWordTableParagraphProperty.firstIndent,
            LegacyWordTableParagraphProperty.lineSpacing,
          },
  );
  return LegacyWordDocument(
    blocks: base.blocks,
    sections: base.sections,
    plainText: base.plainText,
    safeHtml: '',
    tableStyles: [
      LegacyWordTableStyle(
        id: 1,
        name: 'Authored table style',
        text: conditional ? const LegacyWordTableTextFormat() : text,
        textConditions: conditional
            ? {LegacyWordTableCondition.firstRow: text}
            : const {},
      ),
    ],
  );
}
