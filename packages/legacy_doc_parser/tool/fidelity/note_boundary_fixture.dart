// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/note_boundary_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Usage: note_boundary_fixture.dart NEW_DIRECTORY');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  final cases = <Map<String, Object>>[];
  for (final endnote in [false, true]) {
    for (final entry in noteBoundaryCases.entries) {
      final id = '${endnote ? 'endnote' : 'footnote'}-${entry.key}';
      final (text, expected) = entry.value;
      final source = noteBoundaryFixture(text, endnote: endnote);
      File('${output.path}/$id.doc').writeAsBytesSync(source);
      final converted = convertLegacyWord(source);
      File('${output.path}/$id.docx').writeAsBytesSync(converted.bytes);
      cases.add({
        'id': id,
        'rawRangeCodeUnits': text.codeUnits,
        'expectedContentLength': text.length,
        'expectedBlocks': expected,
      });
    }
  }
  File(
    '${output.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}
