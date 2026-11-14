// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import '../../test/support/cached_field_structure_fixture.dart';
import '../cached_field_structure_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final out = Directory(arguments.single);
  if (out.existsSync()) throw ArgumentError('Output already exists.');
  out.createSync(recursive: true);
  final summary = verifyCachedFieldStructureWebAcceptance();
  final cases = <Map<String, Object?>>[];
  for (final scope in cachedStructureScopes) {
    for (final revision in cachedStructureRevisions) {
      for (final privateResult in [false, true]) {
        final name =
            '$scope-$revision-${privateResult ? 'private' : 'display'}';
        final converted = verifyCachedFieldStructureCase(
          scope,
          revision,
          privateResult: privateResult,
        );
        File('${out.path}/$name.docx').writeAsBytesSync(converted.bytes);
        cases.add({
          'name': name,
          'scope': scope,
          'revision': revision,
          'privateResult': privateResult,
          'inputKind': 'authored-public-model',
          'expectedParagraphRevisionText': privateResult ? 'AZ' : 'ACacheZ',
          'output': '$name.docx',
        });
      }
    }
  }
  File('${out.path}/cases.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'summary': summary, 'cases': cases})}\n',
  );
}
