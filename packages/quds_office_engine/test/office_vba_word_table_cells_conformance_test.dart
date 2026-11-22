import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

void main() {
  final suite = VbaConformanceSuite.parse(
    File(
      'test/fixtures/vba_conformance/word_table_cells_v1.json',
    ).readAsStringSync(),
  );
  group('version 1 Word table-cell conformance corpus', () {
    for (final fixture in suite.cases) {
      test('${fixture.feature}: ${fixture.id}', () {
        expect(runVbaConformanceCase(fixture)['actual'], fixture.expected);
      });
    }
    test('preserves the independently authored specification provenance', () {
      expect(suite.id, 'vba-word-table-cells');
      expect(suite.dialect, 'vba-word');
      expect(suite.cases.map((fixture) => fixture.feature).toSet(), {
        'Table selection',
        'Cell text',
        'Object aliases',
        'Source composition',
      });
      for (final fixture in suite.cases) {
        expect(fixture.provenance['kind'], 'spec-derived');
        expect(fixture.provenance.containsKey('host'), isFalse);
      }
    });
  });
}
