// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/table_border_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply an output directory.');
  final output = Directory(arguments.single)..createSync(recursive: true);
  for (final value in tableBorderCases) {
    final source = tableBorderFixture(value);
    File('${output.path}/${value.name}.doc').writeAsBytesSync(source);
    File(
      '${output.path}/${value.name}-converted.docx',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(source).bytes);
  }
  File('${output.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(tableBorderCases.map((v) => {'name': v.name}).toList())}\n',
  );
}
