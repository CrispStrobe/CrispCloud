// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import '../../test/support/field_marker_formatting_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply a new directory.');
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  final cases = <Map<String, Object>>[];
  void write(String name, Uint8List bytes) {
    final model = parseLegacyWordDocument(bytes);
    File('${root.path}/$name.doc').writeAsBytesSync(bytes);
    File(
      '${root.path}/$name.docx',
    ).writeAsBytesSync(convertLegacyWordDocument(model).bytes);
    cases.add({
      'name': name,
      'source': '$name.doc',
      'output': '$name.docx',
      'fields': [
        for (final field in model.fields)
          {
            'startCp': field.startCp,
            'beginHidden': field.beginHidden,
            'separatorHidden': field.separatorHidden,
            'endHidden': field.endHidden,
            'instructionHiddenRanges': [
              for (final (start, end) in field.instructionHiddenRanges)
                [start, end],
            ],
          },
      ],
    });
  }

  for (var mask = 0; mask < 8; mask++) {
    write(
      'marker-$mask-mixed-result',
      fieldMarkerFormattingFixture(markerMask: mask, resultMask: 1),
    );
  }
  for (final fixture in fieldInstructionFormattingCases()) {
    write('instruction-${fixture.name}', fixture.bytes());
  }
  File('${root.path}/cases.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'cases': cases})}\n',
  );
}
