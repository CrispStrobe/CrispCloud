// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

/// Convert the four retained, independently authored native controls. Their
/// original OOXML, DOC bridge, renderer identity and byte hashes are versioned
/// with the native boundary evidence; no Office installation is needed here.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Usage: header_table_fixture.dart NEW_DIRECTORY');
  }
  final root = Directory(arguments.single).absolute;
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  final repository = File.fromUri(Platform.script).parent.parent.parent;
  final manifest = <Map<String, Object>>[];
  for (final role in ['header', 'footer']) {
    for (final ending in ['table', 'paragraph']) {
      final name = '$role-ending-$ending';
      final file = File(
        '${repository.path}/test/fixtures/word_native/$name.doc',
      );
      final bytes = file.readAsBytesSync();
      File('${root.path}/$name.doc').writeAsBytesSync(bytes);
      File(
        '${root.path}/$name.docx',
      ).writeAsBytesSync(convertLegacyWordToStructuredDocx(bytes).bytes);
      manifest.add({
        'id': name,
        'role': role,
        'ending': ending,
        'expectedStoryText':
            'STORY\nCELL${ending == 'paragraph' ? '\nAFTER' : ''}',
        'requiresBoundaryRecovery': ending == 'table',
      });
    }
  }
  File('${root.path}/cases.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
}
