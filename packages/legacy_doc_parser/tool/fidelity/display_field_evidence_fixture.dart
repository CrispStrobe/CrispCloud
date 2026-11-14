// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/display_field_evidence_fixture.dart';
import '../display_field_evidence_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1 &&
      !(arguments.length == 2 && arguments[1] == '--unchecked')) {
    throw ArgumentError(
      'Supply a new output directory, optionally --unchecked to retain a failing baseline.',
    );
  }
  final out = Directory(arguments.first);
  if (out.existsSync()) throw ArgumentError('Output already exists.');
  out.createSync(recursive: true);
  final unchecked = arguments.length == 2;
  final cases = <Map<String, Object?>>[];
  for (final name in displayFieldEvidenceCases) {
    for (final raw in [false, true]) {
      for (final mode in LegacyWordFieldMode.values) {
        final file = '$name-${raw ? 'record' : 'public'}-${mode.name}.docx';
        final model = displayFieldEvidenceDocument(name, sourceRecord: raw);
        final field = model.fields.singleWhere(
          (f) => f.displayRevision != null,
        );
        final converted = unchecked
            ? convertLegacyWordDocument(model, fieldMode: mode)
            : verifyDisplayFieldEvidenceCase(
                name,
                sourceRecord: raw,
                mode: mode,
              );
        File('${out.path}/$file').writeAsBytesSync(converted.bytes);
        cases.add({
          'name': file.substring(0, file.length - 5),
          'case': name,
          'sourceRecord': raw,
          'mode': mode.name,
          'output': file,
          'fieldId': field.id,
          'expectedOriginalCodeUnits':
              field.displayRevision!.original.codeUnits,
          'expectedNativeHistory': displayFieldNativeHistoryExpected(
            name,
            mode,
          ),
        });
      }
    }
  }
  for (final mode in LegacyWordFieldMode.values) {
    final file = 'no-history-${mode.name}.docx';
    final model = displayFieldEvidenceDocument(
      'active',
      sourceRecord: false,
      includeRevision: false,
    );
    File(
      '${out.path}/$file',
    ).writeAsBytesSync(convertLegacyWordDocument(model, fieldMode: mode).bytes);
    cases.add({
      'name': file.substring(0, file.length - 5),
      'case': 'no-history',
      'mode': mode.name,
      'output': file,
    });
  }
  File('${out.path}/cases.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'uncheckedBaseline': unchecked, 'cases': cases})}\n',
  );
}
