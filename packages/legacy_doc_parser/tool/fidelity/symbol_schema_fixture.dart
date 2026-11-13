// SPDX-License-Identifier: MPL-2.0
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/structured_word_fixture.dart';
import '../../test/support/symbol_word_fixture.dart';

const symbolSchemaCases = ['plain', 'deleted'];

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Expected a new output directory');
  }
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists');
  root.createSync(recursive: true);
  for (final name in symbolSchemaCases) {
    final source = symbolWordFixture(
      operations: [
        ...symbolOperands(),
        if (name == 'deleted') ...wordSprm(0x0800, [1]),
      ],
    );
    File('${root.path}/$name.doc').writeAsBytesSync(source);
    File(
      '${root.path}/$name.docx',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(source).bytes);
  }
}
