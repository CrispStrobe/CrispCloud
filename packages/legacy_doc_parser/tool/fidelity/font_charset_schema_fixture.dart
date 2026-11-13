// SPDX-License-Identifier: MPL-2.0
import 'dart:io';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import '../../test/support/font_charset_fixture.dart';

const fontCharsetSchemaCases = {
  'symbol': [('Wingdings', 2)],
  'default': [('Wingdings', 1)],
  'default-symbol-alias': [('Wingdings', 1), ('Wingdings', 2)],
  'conflict': [('Wingdings', 0), ('Wingdings', 2)],
  'unknown': [('Wingdings', 9)],
  'empty-name': [('', 1)],
};

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Expected a new output directory');
  }
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists');
  root.createSync(recursive: true);
  for (final entry in fontCharsetSchemaCases.entries) {
    final source = fontCharsetWordFixture(entry.value);
    File('${root.path}/${entry.key}.doc').writeAsBytesSync(source);
    File(
      '${root.path}/${entry.key}.docx',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(source).bytes);
  }
}
