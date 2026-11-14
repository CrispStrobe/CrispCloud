// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/public_formatting_fixture.dart';
import '../../test/support/public_table_formatting_fixture.dart';
import '../public_table_formatting_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  verifyPublicTableFormattingWebAcceptance();
  final cases = <Map<String, Object?>>[];
  for (final conditional in [false, true]) {
    for (final entry in validPublicCharacters.entries) {
      final name =
          'character-${conditional ? 'conditional' : 'base'}-${entry.key}';
      File('${output.path}/$name.docx').writeAsBytesSync(
        convertLegacyWordDocument(
          publicTableFormattingDocument(
            conditional: conditional,
            character: entry.value,
          ),
        ).bytes,
      );
      cases.add({
        'name': name,
        'conditional': conditional,
        'inputKind': 'public-model',
        'fontSizeHalfPoints': entry.value.fontSizeHalfPoints,
        'positionHalfPoints': entry.value.positionHalfPoints,
        'spacingTwips': entry.value.spacingTwips,
        'output': '$name.docx',
      });
    }
    for (final entry in validPublicParagraphs.entries) {
      final name =
          'paragraph-${conditional ? 'conditional' : 'base'}-${entry.key}';
      File('${output.path}/$name.docx').writeAsBytesSync(
        convertLegacyWordDocument(
          publicTableFormattingDocument(
            conditional: conditional,
            paragraph: entry.value,
          ),
        ).bytes,
      );
      cases.add({
        'name': name,
        'conditional': conditional,
        'inputKind': 'public-model',
        'headingLevel': entry.value.headingLevel,
        'spaceBeforeTwips': entry.value.spaceBeforeTwips,
        'spaceAfterTwips': entry.value.spaceAfterTwips,
        'leftIndentTwips': entry.value.leftIndentTwips,
        'rightIndentTwips': entry.value.rightIndentTwips,
        'firstLineIndentTwips': entry.value.firstLineIndentTwips,
        'lineSpacingValue': entry.value.lineSpacingValue,
        'lineSpacingMultiple': entry.value.lineSpacingMultiple,
        'output': '$name.docx',
      });
    }
  }
  File(
    '${output.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}
