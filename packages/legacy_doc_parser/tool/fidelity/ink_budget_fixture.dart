// SPDX-License-Identifier: MPL-2.0
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/ink_budget_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  final source = inkBudgetWordFixture([
    for (final count in [60000, 60000, 40000, 1]) inkBudgetIsf([count]),
  ]);
  File('${root.path}/aggregate.doc').writeAsBytesSync(source);
  File(
    '${root.path}/aggregate.docx',
  ).writeAsBytesSync(convertLegacyWordToStructuredDocx(source).bytes);
}
