// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/section_geometry_fixture.dart';
import '../section_geometry_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  verifySectionGeometryWebAcceptance();
  final cases = <Map<String, Object?>>[];
  for (final property in sectionGeometryProperties) {
    for (final historical in [false, true]) {
      final scope = historical ? 'historical' : 'current';
      for (final value in property.validValues) {
        if (!property.nativeRepresentable(value)) continue;
        final name = '${property.name}-$scope-$value';
        File('${output.path}/$name.docx').writeAsBytesSync(
          convertLegacyWordDocument(
            sectionGeometryDocument(property, value, historical: historical),
          ).bytes,
        );
        cases.add({
          'name': name,
          'inputKind': 'public-model',
          'scope': scope,
          'property': property.name,
          'value': value,
          'output': '$name.docx',
        });
      }
    }
  }
  File(
    '${output.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}
