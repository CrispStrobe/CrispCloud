// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import '../tool/public_formatting_web_acceptance.dart';
import 'support/public_formatting_fixture.dart';

void main() {
  for (final scope in publicCharacterScopes) {
    for (final invalid in [true, false]) {
      final values = invalid ? invalidPublicCharacters : validPublicCharacters;
      for (final entry in values.entries) {
        test(
          'character $scope ${entry.key} ${invalid ? 'rejects' : 'retains'}',
          () {
            final document = publicFormattingDocument(
              scope: scope,
              character: entry.value,
            );
            expect(
              () => convertLegacyWordDocument(document),
              invalid ? throwsFormatException : returnsNormally,
            );
          },
        );
      }
    }
  }
  for (final scope in publicParagraphScopes) {
    for (final invalid in [true, false]) {
      final values = invalid ? invalidPublicParagraphs : validPublicParagraphs;
      for (final entry in values.entries) {
        test(
          'paragraph $scope ${entry.key} ${invalid ? 'rejects' : 'retains'}',
          () {
            final document = publicFormattingDocument(
              scope: scope,
              paragraph: entry.value,
            );
            expect(
              () => convertLegacyWordDocument(document),
              invalid ? throwsFormatException : returnsNormally,
            );
          },
        );
      }
    }
  }
  test('shared formatting gate verifies exact emitted scalar values', () {
    expect(verifyPublicFormattingWebAcceptance(), {
      'invalidStylesRejected': 179,
      'validStylesPreserved': 106,
    });
  });
}
