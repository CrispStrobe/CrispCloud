import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

void main() {
  final suite = VbaConformanceSuite.parse(
    File(
      'test/fixtures/vba_conformance/word_font_position_v1.json',
    ).readAsStringSync(),
  );
  for (final fixture in suite.cases) {
    test('${fixture.feature}: ${fixture.id}', () {
      expect(runVbaConformanceCase(fixture)['actual'], fixture.expected);
    });
  }
  test(
    'position corpus records specification and dialect evidence separately',
    () {
      expect(suite.dialect, 'vba-word');
      expect(suite.cases.map((fixture) => fixture.provenance['kind']).toSet(), {
        'spec-derived',
        'dialect-contract',
      });
      expect(
        suite.cases.where((fixture) => fixture.provenance.containsKey('host')),
        isEmpty,
      );
      expect(
        canonicalVbaConformanceJson(runVbaConformanceSuite(suite)),
        canonicalVbaConformanceJson(runVbaConformanceSuite(suite)),
      );
    },
  );
}
