// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/list_marker_style_fixture.dart';

export '../../test/support/list_marker_style_fixture.dart'
    show listMarkerStyleCases;

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  final cases = <Map<String, Object?>>[];
  for (final name in listMarkerStyleCases) {
    final source = listMarkerStyleFixture(name);
    final document = parseLegacyWordDocument(source);
    final result = convertLegacyWordDocument(document);
    File('${output.path}/$name.doc').writeAsBytesSync(source);
    File('${output.path}/$name.docx').writeAsBytesSync(result.bytes);
    File('${output.path}/$name.html').writeAsStringSync(document.safeHtml);
    cases.add({
      'name': name,
      'source': '$name.doc',
      'output': '$name.docx',
      'sourceKind': 'independently authored binary LVL, CHPX and style records',
      'materialized': !name.startsWith('native-'),
      'label':
          name == 'native-hidden' ||
              name.contains('-sparse-hidden-') && !name.endsWith('-reset')
          ? ''
          : name.contains('-sparse-')
          ? '${name.startsWith('native-') ? '7' : '%1'} abc'
          : name.startsWith('native-')
          ? '7.'
          : '%1',
      'suffix': 'tab',
      'limitations': result.limitations.map((v) => v.name).toList(),
    });
  }
  File('${output.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'schema': 'legacy-doc-parser/list-marker-style-fixtures', 'version': 1, 'nativeAppearanceVerified': false, 'cases': cases})}\n',
  );
}
