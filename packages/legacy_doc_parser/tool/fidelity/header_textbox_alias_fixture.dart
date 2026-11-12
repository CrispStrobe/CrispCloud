// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/header_textbox_alias_fixture.dart';
import '../../test/support/textbox_boundary_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError(
      'Usage: header_textbox_alias_fixture.dart NEW_DIRECTORY',
    );
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  final cases = <Map<String, Object>>[];
  for (final entry in textboxBoundaryCases.entries) {
    final id = 'header-alias-${entry.key}';
    final (raw, expected) = entry.value;
    final source = headerTextboxAliasFixture(rawText: raw);
    File('${output.path}/$id.doc').writeAsBytesSync(source);
    File(
      '${output.path}/$id.docx',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(source).bytes);
    cases.add({
      'id': id,
      'rawRangeCodeUnits': raw.codeUnits,
      'expectedParagraphsPerOccurrence': expected,
      'expectedChainLength': 1,
      'sourceShapeIds': [1025, 1026],
      'expectedStoredHeaderTypes': ['normal', 'first'],
    });
  }
  File(
    '${output.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}
