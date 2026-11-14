// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../test/support/field_visibility_fixture.dart';
import '../../test/support/generated_field_tree_fixture.dart';
import '../cached_field_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  final cases = <Map<String, Object?>>[];
  final native = <Map<String, Object?>>[];
  void emit(
    String name,
    Uint8List source,
    String expected, {
    String? nativeExpected,
  }) {
    final result = verifyCachedFieldSource(source, expected);
    File('${root.path}/$name.doc').writeAsBytesSync(source);
    File('${root.path}/$name.docx').writeAsBytesSync(result.bytes);
    cases.add({
      'name': name,
      'source': '$name.doc',
      'output': '$name.docx',
      'expectedVisibleText': expected,
      'fieldMode': result.fieldMode.name,
      'preservedCounts': result.preservedCounts,
      'limitations': result.limitations.map((value) => value.name).toList(),
    });
    if (nativeExpected != null) {
      native.add({
        'name': name,
        'input': '$name.docx',
        'expectedText': nativeExpected,
      });
    }
  }

  for (final name in fieldVisibilityCases) {
    emit(
      name,
      fieldVisibilityFixture(name),
      fieldVisibilityExpectedText[name]!,
      nativeExpected: name == 'cached-controls'
          ? 'Aco\u2011operate\nnextZ'
          : fieldVisibilityExpectedText[name]!,
    );
  }
  for (var seed = 1; seed <= 96; seed++) {
    final fixture = GeneratedFieldTreeCase(seed);
    emit(
      'generated-field-${seed.toString().padLeft(3, '0')}',
      fixture.bytes(),
      fixture.expected,
    );
  }
  File(
    '${root.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
  File('${root.path}/native-converted.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'cases': native})}\n',
  );
}
