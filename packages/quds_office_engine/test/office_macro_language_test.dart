import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

Matcher _error(String code) =>
    isA<OfficeMacroException>().having((error) => error.code, 'code', code);

Map<String, Object?> _json({Object? value = 'literal'}) => <String, Object?>{
  'version': 1,
  'name': 'Portable macro',
  'format': 'xlsx',
  'steps': <Object?>[
    <String, Object?>{
      'tool': 'xlsx.cellValue',
      'arguments': <String, Object?>{'cell': 'A1', 'value': value},
    },
  ],
};

/// Test dialect that lowers text to real workbook operations. It receives no
/// document or session, and its output still requires ordinary authorization.
class _TextCompiler implements OfficeMacroLanguage {
  const _TextCompiler();

  @override
  String get id => 'test-text';

  @override
  OfficeMacro compile(OfficeMacroSource source) => OfficeMacro(
    name: '${source.moduleName}.${source.entryPoint}',
    format: OfficeMacroFormat.xlsx,
    steps: <OfficeMacroStep>[
      OfficeMacroStep(
        tool: 'xlsx.cellValue',
        arguments: <String, Object?>{'cell': 'A1', 'value': source.source},
      ),
      OfficeMacroStep(
        tool: 'xlsx.cellFormat',
        arguments: <String, Object?>{'cell': 'A1', 'bold': true},
      ),
    ],
  );
}

class _FailingCompiler implements OfficeMacroLanguage {
  const _FailingCompiler(this.id);

  @override
  final String id;

  @override
  OfficeMacro compile(OfficeMacroSource source) =>
      throw StateError('Syntax rejected');
}

void main() {
  group('native macro format', () {
    test('JSON round-trip preserves parameters, literal values, and calls', () {
      final input = _json(value: <String, Object?>{r'$parameter': 'title'});
      input['parameters'] = <String, Object?>{
        'title': <String, Object?>{'type': 'string'},
      };
      final macro = OfficeMacro.parse(jsonEncode(input));
      expect(macro.version, 1);
      expect(macro.parameters['title']!.type, OfficeMacroParameterType.string);
      expect(OfficeMacro.parse(macro.encode()).toJson(), input);
      expect(() => macro.steps.clear(), throwsUnsupportedError);
      expect(() => macro.parameters.clear(), throwsUnsupportedError);
    });

    test('rejects unsupported versions rather than guessing compatibility', () {
      for (final version in <int>[0, 2, 100]) {
        final input = _json()..['version'] = version;
        expect(
          () => OfficeMacro.parse(jsonEncode(input)),
          throwsA(_error('unsupported_version')),
        );
      }
      for (final version in <Object?>['1', 1.0, null]) {
        final input = _json()..['version'] = version;
        expect(
          () => OfficeMacro.fromJson(input),
          throwsA(_error('invalid_macro')),
        );
      }
    });

    test(
      'strictly rejects malformed JSON, unknown schema fields, and bad identifiers',
      () {
        for (final source in <String>['{', '[]', 'null', '42']) {
          expect(
            () => OfficeMacro.parse(source),
            throwsA(_error('invalid_macro')),
          );
        }
        for (final input in <Map<String, Object?>>[
          _json()..['permissions'] = <String>['all'],
          _json()..['format'] = 'xlsm',
          _json()..['name'] = '   ',
          _json()
            ..['steps'] = <Object?>[
              <String, Object?>{
                'tool': 'shell.exec',
                'arguments': <String, Object?>{},
              },
            ],
          _json()
            ..['parameters'] = <String, Object?>{
              'bad-name': <String, Object?>{'type': 'string'},
            },
          _json()
            ..['parameters'] = <String, Object?>{
              'value': <String, Object?>{'type': 'integer', 'default': 1},
            },
          _json()
            ..['parameters'] = <String, Object?>{
              'value': <String, Object?>{'type': 'object'},
            },
        ]) {
          expect(
            () => OfficeMacro.fromJson(input),
            throwsA(_error('invalid_macro')),
          );
        }
      },
    );

    test(
      'host-supplied cycles and excessive depth fail with bounded domain errors',
      () {
        final cyclicMap = <String, Object?>{};
        cyclicMap['again'] = cyclicMap;
        final cyclicList = <Object?>[];
        cyclicList.add(cyclicList);
        Object? deep = 'leaf';
        for (var depth = 0; depth < 34; depth++) {
          deep = <String, Object?>{'next': deep};
        }
        for (final value in <Object?>[cyclicMap, cyclicList, deep]) {
          expect(
            () => OfficeMacro.fromJson(_json(value: value)),
            throwsA(_error('limit_exceeded')),
          );
        }
      },
    );

    test('rejects non-JSON host values and non-finite numbers', () {
      for (final value in <Object?>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        DateTime.utc(2026),
        <String>{'set'},
        <Object?, Object?>{1: 'non-string key'},
      ]) {
        expect(
          () => OfficeMacro.fromJson(_json(value: value)),
          throwsA(_error('invalid_macro')),
        );
      }
    });

    test(
      'enforces serialized bytes, JSON nodes, steps, and parameter count limits',
      () {
        final oversized = List<String>.filled(1024 * 1024 + 1, ' ').join();
        expect(
          () => OfficeMacro.parse(oversized),
          throwsA(_error('limit_exceeded')),
        );
        expect(
          () => OfficeMacro.fromJson(
            _json(value: List<Object?>.filled(100001, null)),
          ),
          throwsA(_error('limit_exceeded')),
        );
        final step = OfficeMacroStep(
          tool: 'xlsx.cellValue',
          arguments: <String, Object?>{'cell': 'A1', 'value': 1},
        );
        expect(
          () => OfficeMacro(
            name: 'Too many steps',
            format: OfficeMacroFormat.xlsx,
            steps: List<OfficeMacroStep>.filled(10001, step),
          ),
          throwsA(_error('limit_exceeded')),
        );
        expect(
          () => OfficeMacro(
            name: 'Too many parameters',
            format: OfficeMacroFormat.xlsx,
            steps: const [],
            parameters: <String, OfficeMacroParameter>{
              for (var index = 0; index < 257; index++)
                'p$index': const OfficeMacroParameter(
                  OfficeMacroParameterType.string,
                ),
            },
          ),
          throwsA(_error('limit_exceeded')),
        );
      },
    );
  });

  group('language extensions', () {
    test('native JSON and the Excel subset are installed without full VBA', () {
      final languages = OfficeMacroLanguages();
      expect(languages.ids, <String>['quds-json', 'vba-excel']);
      final plan = languages.compile(
        OfficeMacroSource(
          language: 'quds-json',
          source: jsonEncode(_json()),
          format: OfficeMacroFormat.xlsx,
        ),
      );
      expect(plan.steps.single.tool, 'xlsx.cellValue');
      expect(
        () => languages.compile(
          OfficeMacroSource(
            language: 'vba',
            source: 'Sub Main()\nEnd Sub',
            format: OfficeMacroFormat.xlsx,
          ),
        ),
        throwsA(_error('unsupported_language')),
      );
      expect(languages.ids, <String>['quds-json', 'vba-excel']);
    });

    test(
      'registered compiler emits real operations through the transactional runtime',
      () async {
        final languages = OfficeMacroLanguages()
          ..register(const _TextCompiler());
        final source = OfficeMacroSource.fromJson(<String, Object?>{
          'language': 'test-text',
          'source': 'Created by a registered compiler',
          'format': 'xlsx',
          'moduleName': 'Report',
          'entryPoint': 'Build',
        });
        final plan = languages.compile(source);
        expect(plan.name, 'Report.Build');
        final builder = XlsxWorkbookBuilder();
        builder.addSheet('Data').addRow(<Object?>['before']);
        final session = OfficeMacroSession(
          builder.build(),
          format: OfficeMacroFormat.xlsx,
        );
        await session.run(plan);
        final cell = SheetDeserializer()
            .readBytes(session.bytes)
            .sheets
            .single
            .cellA1('A1');
        expect(cell.value, source.source);
        expect(cell.fontBold, isTrue);
        expect(session.revision, 1);
      },
    );

    test(
      'compiled plans retain host tool permissions and do not partially publish',
      () async {
        final languages = OfficeMacroLanguages()
          ..register(const _TextCompiler());
        final plan = languages.compile(
          OfficeMacroSource(
            language: 'test-text',
            source: 'Denied formatting',
            format: OfficeMacroFormat.xlsx,
          ),
        );
        final builder = XlsxWorkbookBuilder();
        builder.addSheet('Data').addRow(<Object?>['before']);
        final session = OfficeMacroSession(
          builder.build(),
          format: OfficeMacroFormat.xlsx,
          policy: OfficeMacroPolicy(allowedTools: <String>{'xlsx.cellValue'}),
        );
        final before = session.bytes;
        await expectLater(
          session.run(plan),
          throwsA(_error('permission_denied')),
        );
        expect(session.bytes, before);
        expect(session.revision, 0);
      },
    );

    test(
      'compiler format mismatches and failures return actionable domain errors',
      () {
        final languages = OfficeMacroLanguages()
          ..register(const _TextCompiler())
          ..register(const _FailingCompiler('broken'));
        expect(
          () => languages.compile(
            OfficeMacroSource(
              language: 'test-text',
              source: 'text',
              format: OfficeMacroFormat.docx,
            ),
          ),
          throwsA(_error('format_mismatch')),
        );
        expect(
          () => languages.compile(
            OfficeMacroSource(
              language: 'quds-json',
              source: jsonEncode(_json()),
              format: OfficeMacroFormat.pptx,
            ),
          ),
          throwsA(_error('format_mismatch')),
        );
        expect(
          () => languages.compile(
            OfficeMacroSource(
              language: 'broken',
              source: 'broken source',
              format: OfficeMacroFormat.xlsx,
              moduleName: 'Report',
              entryPoint: 'Build',
            ),
          ),
          throwsA(
            isA<OfficeMacroException>()
                .having((error) => error.code, 'code', 'compile_failed')
                .having(
                  (error) => error.message,
                  'message',
                  contains('Report.Build'),
                ),
          ),
        );
      },
    );

    test(
      'language registration and source metadata are strict and bounded',
      () {
        final languages = OfficeMacroLanguages()
          ..register(const _TextCompiler());
        expect(
          () => languages.register(const _TextCompiler()),
          throwsA(_error('duplicate_language')),
        );
        expect(
          () => languages.register(const _FailingCompiler('Bad Language')),
          throwsArgumentError,
        );
        expect(
          () => OfficeMacroSource(
            language: 'VBA',
            source: '',
            format: OfficeMacroFormat.xlsx,
          ),
          throwsA(_error('invalid_source')),
        );
        expect(
          () => OfficeMacroSource(
            language: 'vba',
            source: '',
            format: OfficeMacroFormat.xlsx,
            entryPoint: '',
          ),
          throwsA(_error('invalid_source')),
        );
        expect(
          () => OfficeMacroSource(
            language: 'vba',
            source: List<String>.filled(1024 * 1024 + 1, 'x').join(),
            format: OfficeMacroFormat.xlsx,
          ),
          throwsA(_error('limit_exceeded')),
        );
        expect(
          () => OfficeMacroSource.fromJson(<String, Object?>{
            'language': 'vba',
            'source': '',
            'format': 'xlsx',
            'allowFileAccess': true,
          }),
          throwsA(_error('invalid_macro')),
        );
      },
    );
  });
}
