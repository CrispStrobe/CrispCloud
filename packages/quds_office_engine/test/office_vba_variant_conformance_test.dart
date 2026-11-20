import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

void main() {
  for (final path in const <String>[
    'test/fixtures/vba_conformance/variant_conversions_v1.json',
    'test/fixtures/vba_conformance/variant_composition_v1.json',
  ]) {
    final suite = VbaConformanceSuite.parse(File(path).readAsStringSync());

    group('version 1 canonical ${suite.id} corpus', () {
      for (final fixture in suite.cases) {
        test('${fixture.feature}: ${fixture.id}', () {
          final receipt = runVbaConformanceCase(fixture);
          expect(receipt['id'], fixture.id);
          expect(receipt['actual'], fixture.expected);
        });
      }

      test('records specification or dialect evidence without host claims', () {
        final kinds = suite.cases
            .map((fixture) => fixture.provenance['kind'])
            .toSet();
        expect(
          kinds,
          everyElement(isIn(<String>['spec-derived', 'dialect-contract'])),
        );
        expect(
          suite.cases.where(
            (fixture) => fixture.provenance.containsKey('host'),
          ),
          isEmpty,
        );
      });

      test(
        'complete receipts are deterministic and account for every case',
        () {
          final first = canonicalVbaConformanceJson(
            runVbaConformanceSuite(suite),
          );
          final second = canonicalVbaConformanceJson(
            runVbaConformanceSuite(suite),
          );
          expect(second, first);
          final decoded = jsonDecode(first) as Map<String, Object?>;
          expect(decoded['caseCount'], suite.cases.length);
          expect(decoded['suite'], suite.id);
        },
      );
    });
  }
}
