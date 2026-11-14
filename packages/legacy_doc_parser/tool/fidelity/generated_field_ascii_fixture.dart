// SPDX-License-Identifier: MPL-2.0
// The same seeded tree grammar with ASCII text isolates field import behavior
// from PDF glyph ordering, bidirectional text and discretionary hyphen display.
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/generated_field_tree_fixture.dart';
import '../cached_field_web_acceptance.dart';
import '../generated_field_tree_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  final cases = <Map<String, Object?>>[];
  final native = {
    for (final mode in LegacyWordFieldMode.values)
      mode: <Map<String, Object?>>[],
  };
  for (var seed = 1; seed <= 96; seed++) {
    final fixture = GeneratedFieldTreeCase(seed, ascii: true);
    verifyGeneratedFieldTreeCase(seed, ascii: true);
    final stem = 'ascii-field-${seed.toString().padLeft(3, '0')}';
    final source = fixture.bytes();
    File('${root.path}/$stem.doc').writeAsBytesSync(source);
    for (final mode in LegacyWordFieldMode.values) {
      final name = '$stem-${mode.name}';
      final result = mode == LegacyWordFieldMode.cachedResults
          ? verifyCachedFieldSource(source, fixture.expected)
          : convertLegacyWord(source, fieldMode: mode);
      File('${root.path}/$name.docx').writeAsBytesSync(result.bytes);
      cases.add({
        'name': name,
        'seed': seed,
        'source': '$stem.doc',
        'output': '$name.docx',
        'expectedVisibleText': fixture.expected,
        'fieldMode': mode.name,
        'fieldCount': fixture.fields.length,
        'fieldEvaluationClaimed': false,
      });
      native[mode]!.add({
        'name': name,
        'input': '$name.docx',
        'expectedText': fixture.expected,
      });
    }
  }
  File(
    '${root.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
  for (final entry in native.entries) {
    File('${root.path}/native-${entry.key.name}.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'cases': entry.value})}\n',
    );
  }
}
