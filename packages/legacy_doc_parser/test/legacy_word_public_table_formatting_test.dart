// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import '../tool/public_table_formatting_web_acceptance.dart';
import 'support/public_formatting_fixture.dart';
import 'support/public_table_formatting_fixture.dart';

void main() {
  for (final conditional in [false, true]) {
    for (final invalid in [true, false]) {
      final characters = invalid
          ? invalidPublicCharacters
          : validPublicCharacters;
      for (final entry in characters.entries) {
        test('table character conditional=$conditional ${entry.key}', () {
          expect(
            () => convertLegacyWordDocument(
              publicTableFormattingDocument(
                conditional: conditional,
                character: entry.value,
              ),
            ),
            invalid ? throwsFormatException : returnsNormally,
          );
        });
      }
      final paragraphs = invalid
          ? invalidPublicParagraphs
          : validPublicParagraphs;
      for (final entry in paragraphs.entries) {
        test('table paragraph conditional=$conditional ${entry.key}', () {
          expect(
            () => convertLegacyWordDocument(
              publicTableFormattingDocument(
                conditional: conditional,
                paragraph: entry.value,
              ),
            ),
            invalid ? throwsFormatException : returnsNormally,
          );
        });
      }
    }
  }
  test(
    'table-style scalar VM/JavaScript acceptance preserves exact values',
    () {
      expect(verifyPublicTableFormattingWebAcceptance(), {
        'invalidStylesRejected': 90,
        'validStylesPreserved': 44,
      });
    },
  );
}
