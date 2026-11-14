// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/public_textbox_reference_fixture.dart';
import '../public_textbox_reference_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  verifyPublicTextboxReferenceWebAcceptance();
  final cases = <Map<String, Object?>>[];
  for (final hidden in [false, true]) {
    final mutations = hidden
        ? publicTextboxHiddenValidCases
        : publicTextboxValidCases;
    for (final mutation in mutations) {
      final name = '${hidden ? 'hidden' : 'visible'}-$mutation';
      final document = publicTextboxReferenceDocument(mutation, hidden: hidden);
      final model = publicTextboxSourceMetadata(document);
      final inert = hidden || mutation == 'unresolved-chain';
      File(
        '${output.path}/$name.docx',
      ).writeAsBytesSync(convertLegacyWordDocument(document).bytes);
      cases.add({
        'name': name,
        'inputKind': 'public-model',
        'mutation': mutation,
        'hidden': hidden,
        'model': model,
        'expectedActivePart': inert ? null : publicTextboxOutputPart(mutation),
        'expectedInertEvidence': inert,
        'output': '$name.docx',
      });
    }
  }
  File(
    '${output.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}
