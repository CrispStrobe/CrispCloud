// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/table_review_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  final manifest = <Map<String, String>>[];
  for (final kind in tableReviewCases) {
    for (final state in ['review', 'accepted', 'rejected']) {
      final name = 'table-review-$kind-$state';
      final source = tableReviewControl(kind, state);
      File('${root.path}/$name.doc').writeAsBytesSync(source);
      File(
        '${root.path}/$name.docx',
      ).writeAsBytesSync(convertLegacyWordToStructuredDocx(source).bytes);
      manifest.add({'name': name, 'kind': kind, 'state': state});
    }
  }
  File('${root.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
}
