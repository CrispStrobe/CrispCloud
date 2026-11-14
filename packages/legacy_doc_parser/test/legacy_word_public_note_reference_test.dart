// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import '../tool/public_note_reference_web_acceptance.dart';
import 'support/public_note_reference_fixture.dart';

void main() {
  for (final endnote in [false, true]) {
    for (final mutation in publicNoteInvalidCases) {
      test('${endnote ? 'endnote' : 'footnote'} rejects $mutation', () {
        expect(
          () => convertLegacyWordDocument(
            publicNoteReferenceDocument(mutation, endnote),
          ),
          throwsFormatException,
        );
      });
    }
  }
  test('public note ownership shared VM/JavaScript acceptance', () {
    final result = verifyPublicNoteReferenceWebAcceptance();
    expect(result['rejectedCases'], 16);
    expect(result['validCases'], 6);
  });
}
