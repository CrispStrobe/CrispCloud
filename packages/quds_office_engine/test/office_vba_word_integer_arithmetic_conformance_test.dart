import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

void main() {
  final suite = VbaConformanceSuite.parse(
    File('test/fixtures/vba_conformance/word_integer_arithmetic_v1.json')
        .readAsStringSync(),
  );
  for (final fixture in suite.cases) {
    test('${fixture.feature}: ${fixture.id}', () {
      expect(runVbaConformanceCase(fixture)['actual'], fixture.expected);
    });
  }
  test('the arithmetic corpus records its bounded source provenance', () {
    expect(suite.id, 'vba-word-integer-arithmetic');
    expect(suite.dialect, 'vba-word');
    expect(suite.cases, hasLength(54));
    expect(
      suite.cases.where((fixture) => fixture.expected.containsKey('steps')),
      hasLength(44),
    );
    expect(suite.cases.map((fixture) => fixture.provenance['kind']).toSet(), {
      'spec-derived',
      'dialect-contract',
    });
    expect(
      suite.cases.where((fixture) => fixture.provenance.containsKey('host')),
      isEmpty,
    );
    final receipt = runVbaConformanceSuite(suite);
    expect(receipt['caseCount'], 54);
  });
}
