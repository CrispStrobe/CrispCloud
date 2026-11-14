// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/list_visibility_fixture.dart';

export '../../test/support/list_visibility_fixture.dart'
    show listVisibilityCases;

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply a new directory.');
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  final cases = <Map<String, Object?>>[];
  for (final name in listVisibilityCases) {
    final source = listVisibilityFixture(name);
    final document = parseLegacyWordDocument(source);
    final result = convertLegacyWordDocument(
      document,
      fieldMode: LegacyWordFieldMode.cachedResults,
    );
    File('${output.path}/$name.doc').writeAsBytesSync(source);
    File('${output.path}/$name.docx').writeAsBytesSync(result.bytes);
    File('${output.path}/$name.html').writeAsStringSync(document.safeHtml);
    final labels = listVisibilityExpectedLabels(name);
    final bodies = listVisibilityExpectedBodies(name);
    cases.add({
      'name': name,
      'source': '$name.doc',
      'output': '$name.docx',
      'fieldMode': 'cachedResults',
      'paragraphLabels': labels,
      'paragraphBodies': bodies,
      'expectedText': [
        for (var i = 0; i < labels.length; i++) '${labels[i]}${bodies[i]}',
      ].join(),
      'suppressedLabels': listVisibilitySuppressedLabels(name),
      'limitations': result.limitations.map((value) => value.name).toList(),
    });
  }
  final encoder = const JsonEncoder.withIndent('  ');
  File('${output.path}/manifest.json').writeAsStringSync(
    '${encoder.convert({'schema': 'legacy-doc-parser/list-visibility-fixtures', 'version': 1, 'scope': 'Source paragraph CPs and counters retained; hidden field labels '
        'suppressed. Native import may merge hidden paragraphs, recalculate '
        'private fields or ignore numbering vanish; no Word fidelity claim.', 'cases': cases})}\n',
  );
  for (final suffix in ['doc', 'docx']) {
    File('${output.path}/$suffix-manifest.json').writeAsStringSync(
      '${encoder.convert({
        'cases': [
          for (final item in cases) {'name': item['name'], 'input': '${item['name']}.$suffix', 'expectedText': item['expectedText']},
        ],
      })}\n',
    );
  }
}
