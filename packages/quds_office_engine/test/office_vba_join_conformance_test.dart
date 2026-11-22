import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

void main() {
  final suite = VbaConformanceSuite.parse(
    File('test/fixtures/vba_conformance/word_join_v1.json').readAsStringSync(),
  );
  for (final fixture in suite.cases) {
    test('${fixture.feature}: ${fixture.id}', () {
      expect(runVbaConformanceCase(fixture)['actual'], fixture.expected);
    });
  }
  test(
    'Join corpus distinguishes specification and bounded-dialect evidence',
    () {
      expect(suite.id, 'vba-word-join');
      expect(suite.dialect, 'vba-word');
      expect(suite.cases, hasLength(25));
      expect(suite.cases.map((fixture) => fixture.provenance['kind']).toSet(), {
        'spec-derived',
        'dialect-contract',
      });
      expect(
        suite.cases.where((fixture) => fixture.provenance.containsKey('host')),
        isEmpty,
      );
      final receipt = runVbaConformanceSuite(suite);
      expect(receipt['caseCount'], 25);
      expect(
        canonicalVbaConformanceJson(receipt),
        canonicalVbaConformanceJson(runVbaConformanceSuite(suite)),
      );
    },
  );
}
