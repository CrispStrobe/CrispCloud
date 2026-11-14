// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/scalar_sprm_fixture.dart';
import '../scalar_sprm_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  final summary = verifyScalarSprmWebAcceptance();
  final cases = <Map<String, Object?>>[];
  for (final property in scalarSprmProperties) {
    for (final scope in property.scopes) {
      for (final valid in [false, true]) {
        final values = valid ? property.validValues : property.invalidValues;
        for (final value in values) {
          final name = '${property.name}-$scope-$value';
          final source = scalarSprmFixture(property, value, scope);
          File('${output.path}/$name.doc').writeAsBytesSync(source);
          if (valid) {
            File('${output.path}/$name.docx').writeAsBytesSync(
              convertLegacyWordDocument(parseLegacyWordDocument(source)).bytes,
            );
          }
          cases.add({
            'name': name,
            'scope': scope,
            'opcode': '0x${property.opcode.toRadixString(16)}',
            'operandBytes': property.operand(value),
            'property': property.property,
            'value': value,
            'lineSpacingMultiple': property.multiple,
            'validSource': valid,
            'source': '$name.doc',
            if (valid) 'output': '$name.docx',
          });
        }
      }
    }
  }
  File('${output.path}/cases.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'summary': summary, 'cases': cases})}\n',
  );
}
