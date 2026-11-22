import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

void main() {
  final suite = VbaConformanceSuite.parse(
    File(
      'test/fixtures/vba_conformance/word_text_selectors_v1.json',
    ).readAsStringSync(),
  );

  for (final fixture in suite.cases) {
    test('${fixture.feature}: ${fixture.id}', () {
      expect(runVbaConformanceCase(fixture)['actual'], fixture.expected);
    });
  }

  test('corpus separates source contracts from installed-host evidence', () {
    expect(suite.id, 'vba-word-text-selectors');
    expect(suite.dialect, 'vba-word');
    expect(suite.cases, hasLength(64));
    expect(
      suite.cases.where((value) => value.expected.containsKey('steps')),
      hasLength(34),
    );
    expect(
      suite.cases.where((value) => value.expected.containsKey('diagnostic')),
      hasLength(30),
    );
    expect(suite.cases.map((value) => value.provenance['kind']).toSet(), {
      'spec-derived',
      'dialect-contract',
    });
    expect(
      suite.cases.any((value) => value.provenance.containsKey('host')),
      isFalse,
    );
  });
}
