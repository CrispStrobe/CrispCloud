// SPDX-License-Identifier: MPL-2.0
// Binary list metadata controls for independent Open XML SDK validation.

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/list_metadata_fixture.dart';

export '../../test/support/list_metadata_fixture.dart' show listMetadataCases;

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply an output directory.');
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  final manifest = <Map<String, String>>[];
  for (final name in listMetadataCases) {
    final source = listMetadataFixture(name);
    final document = parseLegacyWordDocument(source);
    File('${output.path}/$name.doc').writeAsBytesSync(source);
    File(
      '${output.path}/$name.docx',
    ).writeAsBytesSync(convertLegacyWordDocument(document).bytes);
    File('${output.path}/$name.html').writeAsStringSync(document.safeHtml);
    manifest.add({'name': name, 'source': '$name.doc', 'output': '$name.docx'});
  }
  File('${output.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'schema': 'legacy-doc-parser/list-metadata-fixtures', 'version': 1, 'source': 'independently authored LVLF/Xst list bytes', 'nativeAppearanceVerified': false, 'cases': manifest})}\n',
  );
}
