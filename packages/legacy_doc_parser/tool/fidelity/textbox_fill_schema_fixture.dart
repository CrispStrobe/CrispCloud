// SPDX-License-Identifier: MPL-2.0
// Literal source operands exercise qualified and guarded VML fill output.
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/textbox_fill_fixture.dart';

const names = [
  'gradient-hundred',
  'gradient-axial',
  'gradient-alpha',
  'picture',
  'texture',
  'pattern',
  'unknown-gradient',
  'unknown-bitmap',
];

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError(
      'Usage: textbox_fill_schema_fixture.dart NEW_DIRECTORY',
    );
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  final cases = <Map<String, Object>>[];
  for (final name in names) {
    final source = textboxFillFixture(name);
    final parsed = parseLegacyWordDocument(source);
    final shape = parsed.media.drawings.single.shape!;
    final unknown = name.startsWith('unknown-');
    if (shape.fill?.type != textboxFillCases[name]![0x0180] ||
        unknown == shape.unsupportedProperties.isEmpty ||
        parsed.stories
                .singleWhere(
                  (story) => story.kind == LegacyWordStoryKind.textbox,
                )
                .plainText
                .trim() !=
            'FILL') {
      throw StateError('The literal source control changed: $name.');
    }
    File('${output.path}/$name.doc').writeAsBytesSync(source);
    File(
      '${output.path}/$name.docx',
    ).writeAsBytesSync(convertLegacyWordDocument(parsed).bytes);
    cases.add({
      'id': name,
      'sourcePropertyOperands': {
        '181': 0x00cc9966,
        '1cb': 25400,
        for (final entry in textboxFillCases[name]!.entries)
          entry.key.toRadixString(16): entry.value,
      },
      'guardedFill': unknown,
      'expectedFillType': switch (name) {
        'picture' => 'frame',
        'texture' => 'tile',
        'pattern' => 'pattern',
        'unknown-gradient' || 'unknown-bitmap' => 'omitted',
        _ => 'gradient',
      },
      if (name == 'pattern' || name == 'unknown-bitmap')
        'sourceDibHeight': name == 'unknown-bitmap' ? 7 : 8,
      'expectedText': 'FILL',
    });
  }
  File(
    '${output.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}
