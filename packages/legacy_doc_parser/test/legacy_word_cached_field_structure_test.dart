// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import '../tool/cached_field_structure_web_acceptance.dart';
import 'support/cached_field_structure_fixture.dart';

void main() {
  for (final scope in cachedStructureScopes) {
    for (final revision in cachedStructureRevisions) {
      for (final privateResult in [false, true]) {
        test(
          'cached $scope $revision private=$privateResult retains structure',
          () {
            verifyCachedFieldStructureCase(
              scope,
              revision,
              privateResult: privateResult,
            );
          },
        );
      }
    }
  }
  for (final mode in LegacyWordFieldMode.values) {
    for (final depth in [64, 65]) {
      test('$mode enforces global field depth $depth', () {
        expect(
          () => convertLegacyWordDocument(
            cachedFieldDepthDocument(depth),
            fieldMode: mode,
          ),
          depth == 64
              ? returnsNormally
              : throwsA(isA<LegacyWordConversionException>()),
        );
      });
    }
    for (final bad in [
      'instruction',
      'cross-instruction',
      'private-result',
      'hidden-private',
    ]) {
      test('$mode rejects contradictory normalized run in $bad', () {
        expect(
          () => convertLegacyWordDocument(
            cachedStructureDocument(
              'body',
              'ordinary',
              privateResult: bad.contains('private'),
              contradictoryRun: bad,
            ),
            fieldMode: mode,
          ),
          throwsFormatException,
        );
      });
    }
    test('$mode allows an empty run in an instruction range', () {
      expect(
        () => convertLegacyWordDocument(
          cachedStructureDocument(
            'body',
            'ordinary',
            contradictoryRun: 'empty-instruction',
          ),
          fieldMode: mode,
        ),
        returnsNormally,
      );
    });
  }
  test('cached structure shared gate validates all scopes', () {
    expect(verifyCachedFieldStructureWebAcceptance(), {
      'structureVariants': 88,
      'contradictoryRunsRejected': 8,
      'excessiveDepthRejected': 2,
      'maximumDepthAccepted': 64,
      'activeFields': 0,
      'fieldEvidenceExact': true,
    });
  });
}
