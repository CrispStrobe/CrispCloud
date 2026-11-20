import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

void main() {
  final suite = VbaConformanceSuite.parse(
    File(
      'test/fixtures/vba_conformance/word_paragraphs_v1.json',
    ).readAsStringSync(),
  );

  group('version 1 canonical Word paragraph corpus', () {
    for (final fixture in suite.cases) {
      test('${fixture.feature}: ${fixture.id}', () {
        final receipt = runVbaConformanceCase(fixture);
        expect(receipt['id'], fixture.id);
        expect(receipt['actual'], fixture.expected);
      });
    }

    test('records independent specification and dialect evidence', () {
      expect(suite.dialect, 'vba-word');
      expect(suite.cases, hasLength(44));
      expect(suite.cases.map((fixture) => fixture.provenance['kind']).toSet(), {
        'spec-derived',
        'dialect-contract',
      });
      expect(
        suite.cases.where((fixture) => fixture.provenance.containsKey('host')),
        isEmpty,
      );
    });

    test('Word receipts are deterministic and retain every case in order', () {
      final first = canonicalVbaConformanceJson(runVbaConformanceSuite(suite));
      final second = canonicalVbaConformanceJson(runVbaConformanceSuite(suite));
      expect(second, first);
      final receipt = jsonDecode(first) as Map<String, Object?>;
      expect(receipt['schemaVersion'], 1);
      expect(receipt['dialect'], 'vba-word');
      expect(receipt['suite'], suite.id);
      expect(receipt['caseCount'], 44);
      expect(
        (receipt['cases']! as List<Object?>).map(
          (value) => (value! as Map<String, Object?>)['id'],
        ),
        suite.cases.map((fixture) => fixture.id),
      );
    });
  });
}
