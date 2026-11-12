// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/textbox_table_fixture.dart';

/// Produce independent binary controls and the converted packages for native
/// inspection and the Open XML schema corpus. No expected value comes from
/// reading the converted package.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Usage: textbox_table_fixture.dart NEW_DIRECTORY');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  final cases = <Map<String, Object>>[];
  for (final header in [false, true]) {
    for (final (marginName, margin) in [
      ('default', null),
      ('zero', 0),
      ('wide', 240),
    ]) {
      for (final nested in [false, true]) {
        for (final anchored in [false, true]) {
          final id =
              'textbox-${header ? 'header' : 'main'}-$marginName-'
              '${nested ? 'nested' : 'flat'}-${anchored ? 'table' : 'paragraph'}';
          final source = textboxTableFixture(
            header: header,
            anchorInTable: anchored,
            marginTwips: margin,
            nested: nested,
          );
          File('${output.path}/$id.doc').writeAsBytesSync(source);
          File(
            '${output.path}/$id.docx',
          ).writeAsBytesSync(convertLegacyWordToStructuredDocx(source).bytes);
          cases.add({
            'id': id,
            'header': header,
            'anchorInTable': anchored,
            'sourceOriginTwips': 480,
            'effectiveMarginTwips': margin ?? 108,
            'expectedTextboxIndentsTwips': [
              480 + (margin ?? 108),
              if (nested) 240,
            ],
            'expectedAnchorIndentsTwips': [
              if (anchored) ...[960, if (!nested) 360],
            ],
            'nestedTextboxTable': nested,
          });
        }
      }
    }
  }
  File(
    '${output.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}
