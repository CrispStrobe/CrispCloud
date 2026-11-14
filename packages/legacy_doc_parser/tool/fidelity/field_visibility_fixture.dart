// SPDX-License-Identifier: MPL-2.0
// Binary sources and converted packages for separate native-import checks.

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/field_visibility_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  final cases = <Map<String, Object>>[];
  final nativeSources = <Map<String, Object>>[];
  final nativeConverted = <Map<String, Object>>[];
  for (final name in fieldVisibilityCases) {
    final source = fieldVisibilityFixture(name);
    File('${root.path}/$name.doc').writeAsBytesSync(source);
    File(
      '${root.path}/$name.docx',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(source).bytes);
    cases.add({
      'name': name,
      'inputKind': 'binary-doc',
      'source': '$name.doc',
      'output': '$name.docx',
      'expectedVisibleText': fieldVisibilityExpectedText[name]!,
      'expectedActiveFields': fieldVisibilityExpectedFields[name]!,
      'ordinaryHiddenCharacterResult': name == 'character-hidden-result',
      'projectionControls':
          'tab=U+0009; line=U+000A; page=U+000C; column=U+000E',
      'nativeRenderingClaimed': false,
    });
    // The compact cached-controls line has no discretionary line wrapping:
    // its soft hyphen is not painted, and its column break is whitespace in
    // extracted PDF text. Keep this separately specified rendering expectation
    // distinct from the exact cached-text projection above.
    final nativeExpectedText = name == 'cached-controls'
        ? 'Aco\u2011operate\nnextZ'
        : fieldVisibilityExpectedText[name]!;
    nativeSources.add({
      'name': name,
      'input': '$name.doc',
      'expectedText': nativeExpectedText,
    });
    nativeConverted.add({
      'name': name,
      'input': '$name.docx',
      'expectedText': nativeExpectedText,
    });
  }
  File(
    '${root.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
  for (final entry in {
    'native-source.json': nativeSources,
    'native-converted.json': nativeConverted,
  }.entries) {
    File('${root.path}/${entry.key}').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'cases': entry.value})}\n',
    );
  }
}
