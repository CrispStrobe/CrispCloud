// SPDX-License-Identifier: MPL-2.0
// Literal DOP/SEPX international note formats for independent schema checks.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/note_format_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  final sources = <String, Uint8List>{
    for (final entry in noteFormatSchemaCases.entries)
      entry.key: entry.value.$3
          ? noteFormatFixture(
              dopFootnoteFormat: entry.value.$1,
              dopEndnoteFormat: entry.value.$2,
            )
          : noteFormatFixture(
              sectionProperties: noteFormatSection(
                entry.value.$1,
                entry.value.$2,
              ),
              fibNewVersion: 0x101,
            ),
    'note-formats-revision': noteFormatRevisionFixture(),
  };
  final manifest = <Map<String, Object>>[];
  for (final entry in sources.entries) {
    final source = '${entry.key}.doc', output = '${entry.key}.docx';
    File('${root.path}/$source').writeAsBytesSync(entry.value);
    File(
      '${root.path}/$output',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(entry.value).bytes);
    manifest.add({'name': entry.key, 'source': source, 'output': output});
  }
  File('${root.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'schema': 'legacy-doc-parser/note-format-fixtures', 'version': 1, 'source': 'independently authored DOP/SEPX and note PLC bytes', 'nativeAppearanceVerified': false, 'cases': manifest})}\n',
  );
}
