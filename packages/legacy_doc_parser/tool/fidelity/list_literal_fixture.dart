// SPDX-License-Identifier: MPL-2.0
// Literal labels for independent schema validation and native import probes.

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/list_literal_fixture.dart';

export '../../test/support/list_literal_fixture.dart' show listLiteralCases;

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply an output directory.');
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  final manifest = <Map<String, Object?>>[];
  for (final fixture in listLiteralCases) {
    final source = fixture.build();
    final document = parseLegacyWordDocument(source);
    final result = convertLegacyWordDocument(document);
    File('${output.path}/${fixture.name}.doc').writeAsBytesSync(source);
    File('${output.path}/${fixture.name}.docx').writeAsBytesSync(result.bytes);
    File(
      '${output.path}/${fixture.name}.html',
    ).writeAsStringSync(document.safeHtml);
    manifest.add({
      'name': fixture.name,
      'source': '${fixture.name}.doc',
      'output': '${fixture.name}.docx',
      'label': fixture.label,
      'suffix': document.numbering.single.levels.single.suffix.name,
      'automaticRenumbering': false,
      'limitations': result.limitations.map((v) => v.name).toList(),
    });
  }
  File('${output.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'schema': 'legacy-doc-parser/list-literal-fixtures', 'version': 1, 'source': 'independently authored LVLF/Xst strings and offsets', 'nativeAppearanceVerified': false, 'cases': manifest})}\n',
  );
}
