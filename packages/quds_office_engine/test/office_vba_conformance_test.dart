import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/vba_conformance.dart';

Map<String, Object?> _minimalSuite() => <String, Object?>{
  'schemaVersion': 1,
  'suite': 'schema-validation',
  'dialect': 'vba-excel',
  'cases': <Object?>[
    <String, Object?>{
      'id': 'empty-module',
      'feature': 'schema',
      'source': 'Sub Main()\nEnd Sub',
      'expected': <String, Object?>{'steps': <Object?>[]},
      'provenance': <String, Object?>{
        'kind': 'dialect-contract',
        'references': <Object?>[
          'https://github.com/CrispStrobe/quds_office_suite/blob/main/docs/VBA_MACROS.md',
        ],
        'note': 'Synthetic input used only to test fixture-schema validation.',
      },
    },
  ],
};

Map<String, Object?> _first(Map<String, Object?> suite) =>
    (suite['cases']! as List<Object?>).first! as Map<String, Object?>;

Map<String, Object?> _provenance(Map<String, Object?> suite) =>
    _first(suite)['provenance']! as Map<String, Object?>;

Map<String, Object?> _diagnostic() => <String, Object?>{
  'code': 'vba_type_error',
  'line': 1,
  'column': 1,
};

void main() {
  final suite = VbaConformanceSuite.parse(
    File(
      'test/fixtures/vba_conformance/string_intrinsics_v1.json',
    ).readAsStringSync(),
  );

  group('version 1 canonical string conformance corpus', () {
    for (final fixture in suite.cases) {
      test('${fixture.feature}: ${fixture.id}', () {
        final receipt = runVbaConformanceCase(fixture);
        expect(receipt['id'], fixture.id);
        expect(receipt['actual'], fixture.expected);
      });
    }

    test('does not claim observations from an unavailable Office host', () {
      expect(suite.cases, isNotEmpty);
      expect(
        suite.cases.map((fixture) => fixture.provenance['kind']),
        everyElement(isIn(<String>['spec-derived', 'dialect-contract'])),
      );
    });
  });

  group('conformance fixture schema', () {
    void invalid(String name, void Function(Map<String, Object?>) mutate) {
      test(name, () {
        final input = _minimalSuite();
        mutate(input);
        expect(
          () => VbaConformanceSuite.parse(jsonEncode(input)),
          throwsFormatException,
        );
      });
    }

    test('rejects malformed JSON and non-object roots', () {
      for (final source in <String>['{', '[]', 'null', '1']) {
        expect(() => VbaConformanceSuite.parse(source), throwsFormatException);
      }
    });
    invalid('rejects future schema versions', (s) => s['schemaVersion'] = 2);
    invalid('rejects text schema versions', (s) => s['schemaVersion'] = '1');
    invalid('rejects unknown suite fields', (s) => s['extra'] = true);
    invalid(
      'rejects missing required fields',
      (s) => s.remove('schemaVersion'),
    );
    invalid('rejects another dialect', (s) => s['dialect'] = 'native');
    invalid('rejects empty case collections', (s) => s['cases'] = <Object?>[]);
    invalid('rejects non-array cases', (s) => s['cases'] = 'case');
    invalid('rejects non-object cases', (s) => s['cases'] = <Object?>[null]);
    invalid('rejects duplicate ids', (s) {
      (s['cases']! as List<Object?>).add(Map<String, Object?>.of(_first(s)));
    });
    invalid('rejects unstable ids', (s) => _first(s)['id'] = 'Has spaces');
    invalid('rejects blank features', (s) => _first(s)['feature'] = ' ');
    invalid('rejects blank source', (s) => _first(s)['source'] = '\n');
    invalid('rejects non-text source', (s) => _first(s)['source'] = 42);
    invalid(
      'rejects unknown case fields',
      (s) => _first(s)['comment'] = 'unknown',
    );
    invalid(
      'rejects missing expected results',
      (s) => _first(s).remove('expected'),
    );
    invalid('rejects ambiguous expected results', (s) {
      _first(s)['expected'] = <String, Object?>{
        'steps': <Object?>[],
        'diagnostic': _diagnostic(),
      };
    });
    invalid('rejects an unknown result kind', (s) {
      _first(s)['expected'] = <String, Object?>{'values': <Object?>[]};
    });
    invalid('rejects non-array native steps', (s) {
      _first(s)['expected'] = <String, Object?>{'steps': false};
    });
    invalid('rejects a malformed native step', (s) {
      _first(s)['expected'] = <String, Object?>{
        'steps': <Object?>[
          <String, Object?>{'tool': 'xlsx.cellValue'},
        ],
      };
    });
    invalid('rejects malformed native arguments', (s) {
      _first(s)['expected'] = <String, Object?>{
        'steps': <Object?>[
          <String, Object?>{'tool': 'xlsx.cellValue', 'arguments': 1},
        ],
      };
    });
    invalid('rejects a non-spreadsheet native operation', (s) {
      _first(s)['expected'] = <String, Object?>{
        'steps': <Object?>[
          <String, Object?>{
            'tool': 'docx.replaceText',
            'arguments': <String, Object?>{},
          },
        ],
      };
    });
    for (final entry in <String, Object?>{
      'zero line': <String, Object?>{'line': 0},
      'fractional column': <String, Object?>{'column': 1.5},
      'negative column': <String, Object?>{'column': -1},
      'text line': <String, Object?>{'line': '1'},
      'line outside source': <String, Object?>{'line': 3},
      'column outside source': <String, Object?>{'column': 999},
      'unstable code': <String, Object?>{'code': 'English exception text'},
      'extra diagnostic field': <String, Object?>{'message': 'not stable'},
    }.entries) {
      invalid('rejects ${entry.key}', (s) {
        _first(s)['expected'] = <String, Object?>{
          'diagnostic': <String, Object?>{
            ..._diagnostic(),
            ...entry.value! as Map<String, Object?>,
          },
        };
      });
    }
    invalid(
      'rejects unknown provenance kinds',
      (s) => _provenance(s)['kind'] = 'guess',
    );
    invalid(
      'rejects missing reference links',
      (s) => _provenance(s)['references'] = <Object?>[],
    );
    invalid(
      'rejects non-array reference links',
      (s) => _provenance(s)['references'] = 'https://example.com',
    );
    invalid(
      'rejects relative reference links',
      (s) => _provenance(s)['references'] = <Object?>['../reference'],
    );
    invalid(
      'rejects credential-bearing links',
      (s) => _provenance(s)['references'] = <Object?>[
        'https://user:password@example.com/',
      ],
    );
    invalid(
      'rejects missing provenance notes',
      (s) => _provenance(s).remove('note'),
    );
    invalid(
      'rejects an unqualified host claim',
      (s) => _provenance(s)['kind'] = 'office-host',
    );
    invalid(
      'rejects host metadata on spec-derived evidence',
      (s) => _provenance(s)['host'] = <String, Object?>{},
    );

    test(
      'preserves explicitly qualified host provenance without inventing it',
      () {
        final input = _minimalSuite();
        final provenance = _provenance(input);
        provenance['kind'] = 'office-host';
        provenance['host'] = <String, Object?>{
          'application': 'Synthetic schema-test application',
          'version': 'test-version',
          'platform': 'test-platform',
          'observedAt': '2026-01-01T00:00:00Z',
          'evidence': 'https://example.com/synthetic-schema-test-only.json',
        };
        final parsed = VbaConformanceSuite.parse(jsonEncode(input));
        expect(parsed.cases.single.provenance, provenance);
        final host = provenance['host']! as Map<String, Object?>;
        host['observedAt'] = '2026-01-01';
        expect(
          () => VbaConformanceSuite.parse(jsonEncode(input)),
          throwsFormatException,
        );
        for (final invalid in <String>[
          '2026-02-30T00:00:00Z',
          '2026-01-01T24:00:00Z',
          '2026-01-01T00:00:00+01:99',
        ]) {
          host['observedAt'] = invalid;
          expect(
            () => VbaConformanceSuite.parse(jsonEncode(input)),
            throwsFormatException,
          );
        }
        host['observedAt'] = '2026-01-01T00:00:00Z';
        host.remove('version');
        expect(
          () => VbaConformanceSuite.parse(jsonEncode(input)),
          throwsFormatException,
        );
      },
    );

    test('canonical JSON is independent of map insertion order', () {
      expect(
        canonicalVbaConformanceJson(<String, Object?>{
          'b': 2.0,
          'a': <Object?>[1.0, '1'],
        }),
        '{"a":[1,"1"],"b":2}',
      );
    });

    test('empty native plan produces a deterministic receipt', () {
      final parsed = VbaConformanceSuite.parse(jsonEncode(_minimalSuite()));
      final first = canonicalVbaConformanceJson(runVbaConformanceSuite(parsed));
      expect(
        canonicalVbaConformanceJson(runVbaConformanceSuite(parsed)),
        first,
      );
      expect((jsonDecode(first) as Map<String, Object?>)['caseCount'], 1);
    });

    test('runner fails rather than recording a mismatched expected plan', () {
      final input = _minimalSuite();
      _first(input)['expected'] = <String, Object?>{
        'steps': <Object?>[
          <String, Object?>{
            'tool': 'xlsx.cellValue',
            'arguments': <String, Object?>{
              'sheet': 0,
              'cell': 'A1',
              'value': 'unexpected',
            },
          },
        ],
      };
      final parsed = VbaConformanceSuite.parse(jsonEncode(input));
      expect(() => runVbaConformanceSuite(parsed), throwsStateError);
    });

    test('runner fails rather than accepting an expected compile failure', () {
      final input = _minimalSuite();
      _first(input)['expected'] = <String, Object?>{
        'diagnostic': _diagnostic(),
      };
      final parsed = VbaConformanceSuite.parse(jsonEncode(input));
      expect(() => runVbaConformanceSuite(parsed), throwsStateError);
    });
  });
}
