import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

void main() {
  final suite = VbaConformanceSuite.parse(
    File(
      'test/fixtures/vba_conformance/text_intrinsics_v1.json',
    ).readAsStringSync(),
  );

  group('version 1 canonical text conformance corpus', () {
    for (final fixture in suite.cases) {
      test('${fixture.feature}: ${fixture.id}', () {
        final receipt = runVbaConformanceCase(fixture);
        expect(receipt['id'], fixture.id);
        expect(receipt['actual'], fixture.expected);
      });
    }

    test('records spec-derived values and explicit dialect refusals', () {
      expect(suite.id, 'vba-text-intrinsics');
      expect(suite.dialect, 'vba-excel');
      expect(
        suite.cases.map((fixture) => fixture.provenance['kind']),
        everyElement(isIn(<String>['spec-derived', 'dialect-contract'])),
      );
      for (final fixture in suite.cases) {
        expect(fixture.provenance.containsKey('host'), isFalse);
        if (fixture.expected.containsKey('diagnostic')) {
          expect(fixture.provenance['kind'], 'dialect-contract');
        }
      }
    });
  });
}
