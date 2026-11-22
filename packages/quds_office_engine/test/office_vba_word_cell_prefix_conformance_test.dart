import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

void main() {
  final suite = VbaConformanceSuite.parse(
    File(
      'test/fixtures/vba_conformance/word_cell_prefix_v1.json',
    ).readAsStringSync(),
  );
  for (final fixture in suite.cases) {
    test('${fixture.feature}: ${fixture.id}', () {
      expect(runVbaConformanceCase(fixture)['actual'], fixture.expected);
    });
  }
  test('cell prefix corpus records independent bounded evidence', () {
    expect(suite.id, 'vba-word-cell-prefix');
    expect(suite.dialect, 'vba-word');
    expect(suite.cases, hasLength(78));
    expect(
      suite.cases.where((fixture) => fixture.expected.containsKey('steps')),
      hasLength(34),
    );
    expect(
      suite.cases.where(
        (fixture) => fixture.expected.containsKey('diagnostic'),
      ),
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
    expect(receipt['caseCount'], 78);
    expect(
      canonicalVbaConformanceJson(receipt),
      canonicalVbaConformanceJson(runVbaConformanceSuite(suite)),
    );
  });
}
