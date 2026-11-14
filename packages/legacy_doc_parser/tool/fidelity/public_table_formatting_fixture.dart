// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/public_cell_shading_fixture.dart';
import '../../test/support/public_formatting_fixture.dart';
import '../../test/support/public_table_formatting_fixture.dart';
import '../public_cell_shading_web_acceptance.dart';
import '../public_table_formatting_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  verifyPublicTableFormattingWebAcceptance();
  verifyPublicCellShadingWebAcceptance();
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
  for (final item in publicCellShadingCases) {
    final name = 'cell-shading-${item.name}';
    File(
      '${output.path}/$name.docx',
    ).writeAsBytesSync(convertLegacyWordDocument(item.document()).bytes);
    cases.add({
      'name': name,
      'inputKind': 'public-model',
      'scope': 'direct-cell-shading',
      'legacyShading': _describeShading(item.legacy),
      'formattingShading': _describeShading(item.formatting),
      'expectedShading': _describeShading(item.expected),
      'expectedPreviewColor': item.previewColor,
      'approximatePreview': item.approximatePreview,
      'output': '$name.docx',
    });
  }
  File(
    '${output.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}

Map<String, Object?>? _describeShading(LegacyWordShading? shading) =>
    shading == null
    ? null
    : {
        'pattern': shading.pattern,
        'rawPattern': shading.rawPattern,
        'foregroundHex': shading.foregroundHex,
        'backgroundHex': shading.backgroundHex,
      };
