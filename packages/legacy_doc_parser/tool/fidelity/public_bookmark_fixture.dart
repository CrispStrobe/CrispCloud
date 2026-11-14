// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/public_bookmark_fixture.dart';
import '../public_bookmark_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  verifyPublicBookmarkWebAcceptance();
  final cases = <Map<String, Object?>>[];
  for (final hidden in [false, true]) {
    final mutations = hidden
        ? publicBookmarkHiddenValidCases
        : publicBookmarkValidCases;
    for (final mutation in mutations) {
      final name = '${hidden ? 'hidden' : 'visible'}-$mutation';
      final document = publicBookmarkDocument(mutation, hidden: hidden);
      final model = publicBookmarkSourceMetadata(document);
      File(
        '${output.path}/$name.docx',
      ).writeAsBytesSync(convertLegacyWordDocument(document).bytes);
      cases.add({
        'name': name,
        'inputKind': 'public-model',
        'mutation': mutation,
        'hidden': hidden,
        'model': model,
        'expectedActivePart': hidden
            ? null
            : publicBookmarkOutputPart(mutation),
        'expectedInertEvidence': hidden,
        'output': '$name.docx',
      });
    }
  }
  File(
    '${output.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}
