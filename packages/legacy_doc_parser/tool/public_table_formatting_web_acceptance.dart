// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/public_formatting_fixture.dart';
import '../test/support/public_table_formatting_fixture.dart';

Map<String, Object?> verifyPublicTableFormattingWebAcceptance() {
  var invalid = 0, valid = 0;
  for (final conditional in [false, true]) {
    for (final entry in invalidPublicCharacters.entries) {
      _reject(
        publicTableFormattingDocument(
          conditional: conditional,
          character: entry.value,
        ),
      );
      invalid++;
    }
    for (final entry in invalidPublicParagraphs.entries) {
      _reject(
        publicTableFormattingDocument(
          conditional: conditional,
          paragraph: entry.value,
        ),
      );
      invalid++;
    }
    for (final entry in validPublicCharacters.entries) {
      final style = entry.value;
      final xml = _style(
        publicTableFormattingDocument(
          conditional: conditional,
          character: style,
        ),
        conditional,
      );
      _attribute(xml, 'sz', 'val', style.fontSizeHalfPoints);
      _attribute(xml, 'position', 'val', style.positionHalfPoints ?? 0);
      _attribute(xml, 'spacing', 'val', style.spacingTwips ?? 0);
      valid++;
    }
    for (final entry in validPublicParagraphs.entries) {
      final style = entry.value;
      final xml = _style(
        publicTableFormattingDocument(
          conditional: conditional,
          paragraph: style,
        ),
        conditional,
      );
      _attribute(
        xml,
        'outlineLvl',
        'val',
        style.headingLevel == null ? 9 : style.headingLevel! - 1,
      );
      _attribute(xml, 'spacing', 'before', style.spaceBeforeTwips);
      _attribute(xml, 'spacing', 'after', style.spaceAfterTwips);
      _attribute(xml, 'spacing', 'line', style.lineSpacingValue?.abs());
      final line = style.lineSpacingValue;
      if (line != null) {
        _attribute(
          xml,
          'spacing',
          'lineRule',
          line < 0
              ? 'exact'
              : style.lineSpacingMultiple
              ? 'auto'
              : 'atLeast',
        );
      }
      _attribute(xml, 'ind', 'left', style.leftIndentTwips);
      _attribute(xml, 'ind', 'right', style.rightIndentTwips);
      _attribute(
        xml,
        'ind',
        style.firstLineIndentTwips < 0 ? 'hanging' : 'firstLine',
        style.firstLineIndentTwips.abs(),
      );
      valid++;
    }
  }
  return {'invalidStylesRejected': invalid, 'validStylesPreserved': valid};
}

void _reject(LegacyWordDocument document) {
  try {
    convertLegacyWordDocument(document);
  } on FormatException {
    return;
  }
  throw StateError('Invalid table scalar was accepted');
}

XmlElement _style(LegacyWordDocument document, bool conditional) {
  final zip = ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  );
  final xml = XmlDocument.parse(
    utf8.decode(zip.findFile('word/styles.xml')!.content),
  );
  final style = xml
      .findAllElements('w:style')
      .singleWhere((e) => e.getAttribute('w:styleId') == 'LegacyTable1');
  return conditional ? style.findAllElements('w:tblStylePr').single : style;
}

void _attribute(XmlElement xml, String tag, String attribute, Object? value) {
  if (value == null) return;
  if (!xml
      .findAllElements('w:$tag')
      .any((e) => e.getAttribute('w:$attribute') == '$value')) {
    throw StateError('Table style lost $tag/@$attribute=$value');
  }
}
