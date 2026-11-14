// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/binary_property_contract_fixture.dart';
import '../binary_property_contract_web_acceptance.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  final summary = verifyBinaryPropertyContractWebAcceptance();
  final cases = <Map<String, Object?>>[];
  void record(
    String name,
    Uint8List source, {
    bool valid = true,
    Map<String, Object?> details = const {},
  }) {
    File('${output.path}/$name.doc').writeAsBytesSync(source);
    if (valid) {
      File('${output.path}/$name.docx').writeAsBytesSync(
        convertLegacyWordDocument(parseLegacyWordDocument(source)).bytes,
      );
    } else {
      var rejected = false;
      try {
        parseLegacyWordDocument(source);
      } on FormatException {
        rejected = true;
      }
      if (!rejected) throw StateError('Malformed source was accepted: $name');
    }
    cases.add({
      'name': name,
      'inputKind': 'binary-doc',
      ...details,
      'validSource': valid,
      'source': '$name.doc',
      if (valid) 'output': '$name.docx',
    });
  }

  for (final piece in [false, true]) {
    final scope = piece ? 'piece' : 'fkp';
    record(
      'bool8-$scope-false',
      binaryObjectFalseFlagFixture(pieceProperty: piece),
      details: {'scope': scope, 'objectFlag': 0, 'expectedObjects': 0},
    );
    record(
      'bool8-$scope-true',
      binaryObjectFlagFixture(1, pieceProperty: piece),
      details: {'scope': scope, 'objectFlag': 1, 'expectedObjects': 1},
    );
    for (final value in [2, 0x7f, 0x80, 0x81, 0xff]) {
      record(
        'bool8-$scope-invalid-$value',
        binaryObjectFlagFixture(value, pieceProperty: piece),
        valid: false,
        details: {'scope': scope, 'objectFlag': value},
      );
    }
  }
  for (var heading = 1; heading <= 9; heading++) {
    for (final outline in [0, 9]) {
      for (final piece in [false, true]) {
        final scope = piece ? 'piece' : 'fkp';
        record(
          'heading-$heading-$scope-outline-$outline',
          binaryHeadingOutlineFixture(heading, outline, pieceProperty: piece),
          details: {
            'scope': scope,
            'sourceStyleIndex': heading,
            'sourceOutline': outline,
            'expectedHeading': heading,
          },
        );
      }
    }
    record(
      'heading-$heading-historical-outline-9',
      binaryHeadingOutlineFixture(heading, 9, historical: true),
      details: {
        'scope': 'historical',
        'sourceStyleIndex': heading,
        'sourceOutline': 9,
        'expectedHeading': null,
        'expectedPreviousHeading': heading,
      },
    );
  }
  for (final outline in [0, 8, 9]) {
    record(
      'normal-outline-$outline',
      binaryHeadingOutlineFixture(0, outline),
      details: {
        'sourceStyleIndex': 0,
        'sourceOutline': outline,
        'expectedHeading': outline == 9 ? null : outline + 1,
      },
    );
  }
  for (final name in [
    ...binaryIndirectPositiveCases,
    'huge-short-data',
    'huge-first-cycle',
  ]) {
    final valid = binaryIndirectPositiveCases.contains(name);
    record(
      'indirect-$name',
      binaryIndirectPropertyFixture(name),
      valid: valid,
      details: {
        'scope': 'indirect',
        if (valid) 'expectedBeforeTwips': 120,
        if (valid) 'expectedAfterTwips': name == 'huge-minimum-size' ? 0 : 240,
      },
    );
  }
  File('${output.path}/cases.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'summary': summary, 'cases': cases})}\n',
  );
}
