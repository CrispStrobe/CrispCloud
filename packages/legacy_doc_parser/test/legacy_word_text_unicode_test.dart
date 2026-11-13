// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import '../tool/text_unicode_web_acceptance.dart';
import 'support/text_unicode_fixture.dart';

void main() {
  for (final name in invalidTextUnicodeCases) {
    for (final (apiName, api) in <(String, Object? Function(Uint8List))>[
      ('structured parser', parseLegacyWordDocument),
      ('text extraction', extractLegacyWordText),
      ('text-only DOCX', convertLegacyWordToDocx),
    ]) {
      test('$apiName rejects invalid body Unicode: $name', () {
        final source = textUnicodeFixture(name);
        final before = Uint8List.fromList(source);
        expect(() => api(source), throwsFormatException);
        expect(source, before);
      });
    }
  }

  test('shared VM and JavaScript text-Unicode acceptance', () {
    final result = verifyTextUnicodeWebAcceptance();
    expect(result['invalidMainBodiesRejected'], invalidTextUnicodeCases.length);
    expect(result['supportedCases'], 3);
  });
}
