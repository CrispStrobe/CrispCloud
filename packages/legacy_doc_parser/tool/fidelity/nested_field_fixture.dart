// SPDX-License-Identifier: MPL-2.0
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/nested_field_fixture.dart';

export '../../test/support/nested_field_fixture.dart' show nestedFieldCases;

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  for (final name in nestedFieldCases) {
    final source = nestedFieldFixture(name);
    File('${root.path}/$name.doc').writeAsBytesSync(source);
    File(
      '${root.path}/$name.docx',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(source).bytes);
  }
}
