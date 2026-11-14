// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/public_formatting_fixture.dart';
import '../public_formatting_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  verifyPublicFormattingWebAcceptance();
  final cases = <Map<String, Object?>>[];
  for (final scope in publicCharacterScopes) {
    for (final entry in validPublicCharacters.entries) {
      final name = 'character-$scope-${entry.key}';
      File('${output.path}/$name.docx').writeAsBytesSync(
        convertLegacyWordDocument(
          publicFormattingDocument(scope: scope, character: entry.value),
        ).bytes,
      );
      cases.add({
        'name': name,
        'scope': scope,
        'inputKind': 'public-model',
        'fontSizeHalfPoints': entry.value.fontSizeHalfPoints,
        'positionHalfPoints': entry.value.positionHalfPoints,
        'spacingTwips': entry.value.spacingTwips,
        'output': '$name.docx',
      });
    }
  }
  for (final scope in publicParagraphScopes) {
    for (final entry in validPublicParagraphs.entries) {
      final name = 'paragraph-$scope-${entry.key}';
      File('${output.path}/$name.docx').writeAsBytesSync(
        convertLegacyWordDocument(
          publicFormattingDocument(scope: scope, paragraph: entry.value),
        ).bytes,
      );
      cases.add({
        'name': name,
        'scope': scope,
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
