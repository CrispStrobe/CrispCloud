import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

const _fixture = 'test/fixtures/vba_conformance/powerpoint_shapes_v1.json';

void main() {
  final source = File(_fixture).readAsStringSync();
  final suite = VbaConformanceSuite.parse(source);

  group('version 1 canonical PowerPoint shape corpus', () {
    for (final fixture in suite.cases) {
      test('${fixture.feature}: ${fixture.id}', () {
        final receipt = runVbaConformanceCase(fixture);
        expect(receipt['id'], fixture.id);
        expect(receipt['actual'], fixture.expected);
      });
    }

    test('specification and dialect provenance remain distinct', () {
      expect(suite.dialect, 'vba-powerpoint');
      expect(suite.cases, hasLength(20));
      expect(suite.cases.map((fixture) => fixture.provenance['kind']).toSet(), {
        'spec-derived',
        'dialect-contract',
      });
      expect(
        suite.cases.where((fixture) => fixture.provenance.containsKey('host')),
        isEmpty,
      );
      expect(
        suite.cases.where((fixture) => fixture.expected.containsKey('steps')),
        hasLength(10),
      );
      expect(
        suite.cases.where(
          (fixture) => fixture.expected.containsKey('diagnostic'),
        ),
        hasLength(10),
      );
    });

    test('receipts are deterministic and preserve all case identities', () {
      final first = canonicalVbaConformanceJson(runVbaConformanceSuite(suite));
      final second = canonicalVbaConformanceJson(runVbaConformanceSuite(suite));
      expect(second, first);
      final receipt = jsonDecode(first) as Map<String, Object?>;
      expect(receipt['schemaVersion'], 1);
      expect(receipt['dialect'], 'vba-powerpoint');
      expect(receipt['suite'], 'vba-powerpoint-shapes');
      expect(receipt['caseCount'], 20);
      expect(
        (receipt['cases']! as List<Object?>).map(
          (value) => (value! as Map<String, Object?>)['id'],
        ),
        suite.cases.map((fixture) => fixture.id),
      );
    });

    for (final otherHost in <String>['docx.replaceText', 'xlsx.cellValue']) {
      test('PowerPoint expectations refuse $otherHost', () {
        final input = jsonDecode(source) as Map<String, Object?>;
        final first =
            (input['cases']! as List<Object?>).first! as Map<String, Object?>;
        final expected = first['expected']! as Map<String, Object?>;
        final step =
            (expected['steps']! as List<Object?>).first!
                as Map<String, Object?>;
        step['tool'] = otherHost;
        expect(
          () => VbaConformanceSuite.parse(jsonEncode(input)),
          throwsFormatException,
        );
      });
    }
  });
}
