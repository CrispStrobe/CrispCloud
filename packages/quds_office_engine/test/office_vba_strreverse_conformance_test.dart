import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

void main() {
  final suite = VbaConformanceSuite.parse(
    File(
      'test/fixtures/vba_conformance/strreverse_v1.json',
    ).readAsStringSync(),
  );

  group('canonical StrReverse conformance corpus', () {
    for (final fixture in suite.cases) {
      test(fixture.id, () {
        final receipt = runVbaConformanceCase(fixture);
        expect(receipt['id'], fixture.id);
        expect(receipt['actual'], fixture.expected);
      });
    }

    test('separates specification and deterministic dialect expectations', () {
      expect(suite.id, 'vba-strreverse');
      expect(suite.dialect, 'vba-word');
      expect(suite.cases, hasLength(26));
      expect(
        suite.cases.map((fixture) => fixture.provenance['kind']),
        everyElement(isIn(<String>['spec-derived', 'dialect-contract'])),
      );
      for (final fixture in suite.cases) {
        expect(fixture.provenance.containsKey('host'), isFalse);
      }
    });
  });
}
