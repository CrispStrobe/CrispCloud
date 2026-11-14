// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/public_formatting_fixture.dart';

Map<String, Object?> verifyPublicFormattingWebAcceptance() {
  var invalid = 0, valid = 0;
  for (final scope in publicCharacterScopes) {
    for (final entry in invalidPublicCharacters.entries) {
      _reject(
        publicFormattingDocument(scope: scope, character: entry.value),
        '$scope/${entry.key}',
      );
      invalid++;
    }
    for (final entry in validPublicCharacters.entries) {
      final style = entry.value;
      final xml = _convert(
        publicFormattingDocument(scope: scope, character: style),
      );
      _attribute(
        xml,
        'sz',
        'val',
        style.fontSizeHalfPoints,
        '$scope/${entry.key}',
      );
      // Numbering currently emits the documented marker font subset. Values
      // not emitted by that path are still checked against the source domain.
      if (scope != 'list-marker') {
        _attribute(
          xml,
          'position',
          'val',
          style.positionHalfPoints,
          '$scope/${entry.key}',
        );
        _attribute(
          xml,
          'spacing',
          'val',
          style.spacingTwips,
          '$scope/${entry.key}',
        );
      }
      valid++;
    }
  }
  for (final scope in publicParagraphScopes) {
    for (final entry in invalidPublicParagraphs.entries) {
      _reject(
        publicFormattingDocument(scope: scope, paragraph: entry.value),
        '$scope/${entry.key}',
      );
      invalid++;
    }
    for (final entry in validPublicParagraphs.entries) {
      final style = entry.value;
      final xml = _convert(
        publicFormattingDocument(scope: scope, paragraph: style),
      );
      _attribute(
        xml,
        'ind',
        'left',
        style.leftIndentTwips,
        '$scope/${entry.key}',
      );
      _attribute(
        xml,
        'ind',
        'right',
        style.rightIndentTwips,
        '$scope/${entry.key}',
      );
      _attribute(
        xml,
        'ind',
        style.firstLineIndentTwips < 0 ? 'hanging' : 'firstLine',
        style.firstLineIndentTwips.abs(),
        '$scope/${entry.key}',
      );
      if (scope != 'list-marker') {
        _attribute(
          xml,
          'outlineLvl',
          'val',
          style.headingLevel == null ? 9 : style.headingLevel! - 1,
          '$scope/${entry.key}',
        );
        _attribute(
          xml,
          'spacing',
          'before',
          style.spaceBeforeTwips,
          '$scope/${entry.key}',
        );
        _attribute(
          xml,
          'spacing',
          'after',
          style.spaceAfterTwips,
          '$scope/${entry.key}',
        );
        _attribute(
          xml,
          'spacing',
          'line',
          style.lineSpacingValue?.abs(),
          '$scope/${entry.key}',
        );
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
            '$scope/${entry.key}',
          );
        }
      }
      valid++;
    }
  }
  return {'invalidStylesRejected': invalid, 'validStylesPreserved': valid};
}

void _reject(LegacyWordDocument document, String name) {
  try {
    convertLegacyWordDocument(document);
  } on FormatException {
    return;
  }
  throw StateError('$name did not reject invalid source-domain formatting');
}

List<XmlDocument> _convert(LegacyWordDocument document) {
  final archive = ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  );
  final main = XmlDocument.parse(
    utf8.decode(archive.findFile('word/document.xml')!.content),
  );
  if (main.findAllElements('w:t').map((e) => e.innerText).join() != 'Body') {
    throw StateError('Formatting changed body text');
  }
  return [
    for (final file in archive.files)
      if (file.name.endsWith('.xml'))
        XmlDocument.parse(utf8.decode(file.content)),
  ];
}

void _attribute(
  List<XmlDocument> xml,
  String element,
  String attribute,
  Object? value,
  String name,
) {
  if (value == null) return;
  final found = xml
      .expand((d) => d.findAllElements('w:$element'))
      .any((e) => e.getAttribute('w:$attribute') == '$value');
  if (!found) throw StateError('$name lost $element/@$attribute=$value');
}
