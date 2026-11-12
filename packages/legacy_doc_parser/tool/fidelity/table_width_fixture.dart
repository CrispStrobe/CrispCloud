// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/table_width_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply an output directory.');
  final directory = Directory(arguments.single)..createSync(recursive: true);
  for (final item in tableWidthCases) {
    final source = tableWidthFixture(item);
    File('${directory.path}/${item.name}.doc').writeAsBytesSync(source);
    File(
      '${directory.path}/${item.name}-converted.docx',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(source).bytes);
  }
  File('${directory.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert([
      for (final item in tableWidthCases) {
          'name': item.name,
          'unit': item.unit,
          'preferredWidth': item.value,
          'range': item.range,
          'style': item.tableStyle,
          'initialUnit': item.initialUnit,
          'initialValue': item.initialValue,
          'secondPreferredWidth': item.secondValue,
          'gridWidths': item.gridWidths ?? [2400, 2400],
          'noWrapPreference': !item.resetNoWrap,
        },
    ])}\n',
  );
}
