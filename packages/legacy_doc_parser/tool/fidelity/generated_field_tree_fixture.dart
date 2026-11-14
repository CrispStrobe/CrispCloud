// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/generated_field_tree_fixture.dart';
import '../generated_field_tree_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  final cases = <Map<String, Object?>>[];
  for (var seed = 1; seed <= 96; seed++) {
    final fixture = GeneratedFieldTreeCase(seed);
    verifyGeneratedFieldTreeCase(seed);
    final name = 'generated-field-${seed.toString().padLeft(3, '0')}';
    for (final split in [false, true]) {
      File(
        '${output.path}/$name-${split ? 'pieces' : 'single'}.doc',
      ).writeAsBytesSync(fixture.bytes(splitPieces: split));
    }
    File('${output.path}/$name.docx').writeAsBytesSync(
      convertLegacyWordToStructuredDocx(fixture.bytes()).bytes,
    );
    cases.add({
      'name': name,
      'seed': seed,
      'sources': ['$name-single.doc', '$name-pieces.doc'],
      'output': '$name.docx',
      'rawText': fixture.source,
      'expectedVisibleText': fixture.expected,
      'expectedFields': [
        for (final field in fixture.fields)
          {
            'id': field.id,
            'parentId': field.parent,
            'startCp': field.start,
            'separatorCp': field.separator,
            'endCp': field.end,
            'type': field.type,
            'instruction': field.instruction,
            'storedResult': field.result,
            'privateResult': field.privateResult,
          },
      ],
      'fieldEvaluationClaimed': false,
      'nativeRenderingClaimed': false,
    });
  }
  File(
    '${output.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}
