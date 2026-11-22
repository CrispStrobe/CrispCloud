import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

void main() {
  final suite = VbaConformanceSuite.parse(
    File(
      'test/fixtures/vba_conformance/word_numeric_intrinsics_v1.json',
    ).readAsStringSync(),
  );

  group('version 1 Word numeric conformance corpus', () {
    for (final fixture in suite.cases) {
      test('${fixture.feature}: ${fixture.id}', () {
        expect(runVbaConformanceCase(fixture)['actual'], fixture.expected);
      });
    }

    test('keeps specification and bounded dialect evidence distinct', () {
      expect(suite.id, 'vba-word-numeric-intrinsics');
      expect(suite.dialect, 'vba-word');
      expect(suite.cases.map((fixture) => fixture.feature).toSet(), {
        'Abs',
        'Int',
        'Fix',
        'Sgn',
        'Numeric composition',
      });
      expect(suite.cases.map((fixture) => fixture.provenance['kind']).toSet(), {
        'spec-derived',
        'dialect-contract',
      });
      for (final fixture in suite.cases) {
        expect(fixture.provenance.containsKey('host'), isFalse);
        if (fixture.expected.containsKey('diagnostic')) {
          expect(fixture.provenance['kind'], 'dialect-contract');
        }
      }
    });
  });
}
