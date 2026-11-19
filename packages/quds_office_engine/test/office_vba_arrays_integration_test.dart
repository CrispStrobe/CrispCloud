import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _example = 'example/macros/array_report.bas';
const _reportSteps = 24;

const _lateFailure = '''
Option Explicit
Sub Main()
  Dim targets(1 To 3) As String, name As Variant
  targets(1) = "Summary"
  targets(2) = "Summary"
  targets(3) = "Missing"
  For Each name In targets
    Worksheets(name).Range("A1").Value2 = "pending"
  Next name
End Sub
''';

const _badIndex = '''
Sub Main()
  Dim amounts(1 To 2) As Long
  Worksheets(1).Range("A1").Value2 = "not published"
  amounts(3) = 42
End Sub
''';

const _oversizedArray = '''
Sub Main()
  Dim amounts(0 To 4096) As Long
End Sub
''';

Uint8List _workbook() {
  final builder = XlsxWorkbookBuilder();
  builder.addSheet('Summary').addRow(<Object?>['original']);
  return builder.build();
}

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    moduleName: 'ArrayReport',
    source: source,
  ),
);

OfficeMacroSession _session({OfficeMacroPolicy? policy}) => OfficeMacroSession(
  _workbook(),
  format: OfficeMacroFormat.xlsx,
  policy: policy,
);

Map<String, Object?> _json(String value) =>
    jsonDecode(value) as Map<String, Object?>;

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

TypeMatcher<OfficeMacroException> _error(String code) =>
    isA<OfficeMacroException>().having((error) => error.code, 'code', code);

Future<ProcessResult> _run(List<String> arguments) =>
    Process.run(Platform.resolvedExecutable, <String>[
      if (Platform.packageConfig case final String packages)
        '--packages=$packages',
      'tool/macros/office_macro.dart',
      ...arguments,
    ]);

void _expectReport(Uint8List bytes) {
  final sheet = SheetDeserializer().readBytes(bytes).sheets.single;
  expect(sheet.cellA1('A1').value, 'Item');
  expect(sheet.cellA1('B1').value, 'Amount');
  for (final column in <String>['A', 'B']) {
    expect(sheet.cellA1('${column}1').fontBold, isTrue);
    expect(sheet.cellA1('${column}1').fillRgb, '1F4E79');
    expect(sheet.cellA1('${column}1').fontRgb, 'FFFFFF');
    expect(sheet.cellA1('${column}6').fontBold, isTrue);
    expect(sheet.cellA1('${column}6').fillRgb, 'E6F0FA');
  }
  const rows = <(String, int)>[
    ('Paper', 75),
    ('Ink', 125),
    ('Labels', 250),
    ('Folders', 400),
  ];
  for (var index = 0; index < rows.length; index++) {
    expect(sheet.cellA1('A${index + 2}').value, rows[index].$1);
    expect(sheet.cellA1('B${index + 2}').value, rows[index].$2);
  }
  expect(sheet.cellA1('D1').value, 'Source total');
  expect(sheet.cellA1('D2').value, 850);
  expect(sheet.cellA1('A6').value, 'Worksheet total');
  expect(sheet.cellA1('B6').formula, 'SUM(B2:B5)');
  expect(sheet.cellA1('B6').value, 850);
}

void main() {
  group('array and For Each plans through the atomic runtime', () {
    test('committed report round trips, validates, and runs', () async {
      final macro = _compile(File(_example).readAsStringSync());
      expect(macro.steps, hasLength(_reportSteps));
      expect(macro.steps.map((step) => step.tool).toSet(), <String>{
        'xlsx.cellValue',
        'xlsx.cellFormula',
        'xlsx.cellFormat',
      });
      final saved = OfficeMacro.parse(macro.encode());
      expect(saved.toJson(), macro.toJson());
      final session = _session();
      final original = session.bytes;
      final validation = await session.validate(saved);
      expect(validation.validatedOnly, isTrue);
      expect(session.bytes, original);
      expect(session.revision, 0);
      await session.run(saved);
      expect(session.revision, 1);
      _expectReport(session.bytes);
    });

    test('a late array-selected sheet failure rolls back all writes', () async {
      final session = _session();
      final original = session.bytes;
      final macro = _compile(_lateFailure);
      expect(macro.steps, hasLength(3));
      final failure = _error('operation_failed')
          .having((error) => error.stepIndex, 'stepIndex', 2)
          .having((error) => error.tool, 'tool', 'xlsx.cellValue');
      await expectLater(session.validate(macro), throwsA(failure));
      expect(session.bytes, original);
      expect(session.revision, 0);
      await expectLater(session.run(macro), throwsA(failure));
      expect(session.bytes, original);
      expect(session.revision, 0);
    });

    test('array and range expansion retain host policy restrictions', () async {
      final macro = _compile(File(_example).readAsStringSync());
      for (final (policy, code) in <(OfficeMacroPolicy, String)>[
        (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
        (
          OfficeMacroPolicy(allowedTools: <String>{'xlsx.cellValue'}),
          'permission_denied',
        ),
        (OfficeMacroPolicy(maxSteps: _reportSteps - 1), 'limit_exceeded'),
      ]) {
        final session = _session(policy: policy);
        final original = session.bytes;
        await expectLater(session.run(macro), throwsA(_error(code)));
        expect(session.bytes, original);
        expect(session.revision, 0);
      }
    });
  });

  group('array and For Each source through MCP', () {
    test(
      'compile, validate, and saved-plan playback share the dialect',
      () async {
        final session = _session();
        final original = session.bytes;
        final adapter = OfficeMacroMcp(session);
        final compiled = await adapter.callTool(
          'office_macro_compile',
          <String, Object?>{
            'source': <String, Object?>{
              'language': 'vba-excel',
              'format': 'xlsx',
              'moduleName': 'ArrayReport',
              'source': File(_example).readAsStringSync(),
            },
          },
        );
        expect(compiled['isError'], isFalse, reason: '$compiled');
        expect(session.bytes, original);
        final macro = _structured(compiled)['macro'];
        final validated = await adapter.callTool(
          'office_macro_validate',
          <String, Object?>{'macro': macro},
        );
        expect(validated['isError'], isFalse, reason: '$validated');
        expect(_structured(validated)['validatedOnly'], isTrue);
        expect(session.bytes, original);
        expect(session.revision, 0);
        final run = await adapter.callTool(
          'office_macro_run',
          <String, Object?>{'macro': macro},
        );
        expect(run['isError'], isFalse, reason: '$run');
        expect(_structured(run)['completedSteps'], _reportSteps);
        expect(session.revision, 1);
        _expectReport(session.bytes);
      },
    );

    test(
      'array bounds failures retain structured source diagnostics',
      () async {
        final session = _session(
          policy: OfficeMacroPolicy(allowMutation: false),
        );
        final original = session.bytes;
        final result = await OfficeMacroMcp(session).callTool(
          'office_macro_compile',
          <String, Object?>{
            'source': <String, Object?>{
              'language': 'vba-excel',
              'format': 'xlsx',
              'moduleName': 'IndexFailure',
              'source': _badIndex,
            },
          },
        );
        expect(result['isError'], isTrue);
        final error = _structured(result)['error']! as Map<String, Object?>;
        expect(error['code'], 'vba_subscript_out_of_range');
        expect(error['moduleName'], 'IndexFailure');
        expect(error['entryPoint'], 'Main');
        expect(error['line'], 4);
        expect(error['column'], greaterThan(0));
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );

    test(
      'oversized arrays fail before a partial native plan is returned',
      () async {
        final session = _session();
        final original = session.bytes;
        final result = await OfficeMacroMcp(session).callTool(
          'office_macro_compile',
          <String, Object?>{
            'source': <String, Object?>{
              'language': 'vba-excel',
              'format': 'xlsx',
              'source': _oversizedArray,
            },
          },
        );
        expect(result['isError'], isTrue);
        final content = _structured(result);
        final error = content['error']! as Map<String, Object?>;
        expect(error['code'], 'vba_limit_exceeded');
        expect(content.containsKey('macro'), isFalse);
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );
  });

  group('array and For Each source through actual CLI processes', () {
    late Directory temporary;
    setUp(() => temporary = Directory.systemTemp.createTempSync('vba-arrays-'));
    tearDown(() => temporary.deleteSync(recursive: true));

    test('BAS and saved native plans produce the same report', () async {
      final original = _workbook();
      final input = File('${temporary.path}/input.xlsx')
        ..writeAsBytesSync(original);
      final plan = File('${temporary.path}/report.json');
      final compiled = await _run(<String>['compile-vba', _example, plan.path]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      expect(
        OfficeMacro.parse(plan.readAsStringSync()).steps,
        hasLength(_reportSteps),
      );
      final validation = await _run(<String>[
        'validate-vba',
        input.path,
        _example,
      ]);
      expect(validation.exitCode, 0, reason: '${validation.stderr}');
      expect(_json(validation.stdout as String)['validatedOnly'], isTrue);
      expect(input.readAsBytesSync(), original);
      final basOutput = File('${temporary.path}/bas.xlsx');
      final nativeOutput = File('${temporary.path}/native.xlsx');
      final basRun = await _run(<String>[
        'run-vba',
        input.path,
        _example,
        basOutput.path,
      ]);
      final nativeRun = await _run(<String>[
        'run',
        input.path,
        plan.path,
        nativeOutput.path,
      ]);
      expect(basRun.exitCode, 0, reason: '${basRun.stderr}');
      expect(nativeRun.exitCode, 0, reason: '${nativeRun.stderr}');
      expect(_json(basRun.stdout as String)['completedSteps'], _reportSteps);
      final basBytes = basOutput.readAsBytesSync();
      final nativeBytes = nativeOutput.readAsBytesSync();
      _expectReport(basBytes);
      _expectReport(nativeBytes);
      final bas = OfficeMacroSession(basBytes, format: OfficeMacroFormat.xlsx);
      final native = OfficeMacroSession(
        nativeBytes,
        format: OfficeMacroFormat.xlsx,
      );
      expect(bas.inspect(), native.inspect());
      expect(input.readAsBytesSync(), original);
      expect(temporary.listSync().whereType<Directory>(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a custom entry can use local arrays in reusable helpers', () async {
      final input = File('${temporary.path}/input.xlsx')
        ..writeAsBytesSync(_workbook());
      final source = File('${temporary.path}/Selected.bas')
        ..writeAsStringSync('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = "not selected"
End Sub
Sub Build()
  Call WriteSelected()
End Sub
Sub WriteSelected()
  Dim values(2) As Long, item As Variant, total As Long
  values(0) = 10
  values(1) = 12
  values(2) = 20
  For Each item In values
    total = total + item
  Next item
  Worksheets(1).Range("A1").Value2 = total
End Sub
''');
      final output = File('${temporary.path}/selected.xlsx');
      final result = await _run(<String>[
        'run-vba',
        input.path,
        source.path,
        output.path,
        'bUiLd',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        SheetDeserializer()
            .readBytes(output.readAsBytesSync())
            .sheets
            .single
            .cellA1('A1')
            .value,
        42,
      );
    });

    test(
      'late sheet failure preserves existing input and output files',
      () async {
        final original = _workbook();
        final input = File('${temporary.path}/input.xlsx')
          ..writeAsBytesSync(original);
        final source = File('${temporary.path}/Failure.bas')
          ..writeAsStringSync(_lateFailure);
        final output = File('${temporary.path}/output.xlsx')
          ..writeAsBytesSync(<int>[4, 3, 2, 1]);
        final result = await _run(<String>[
          'run-vba',
          input.path,
          source.path,
          output.path,
        ]);
        expect(result.exitCode, 1);
        final error =
            _json(result.stderr as String)['error']! as Map<String, Object?>;
        expect(error['code'], 'operation_failed');
        expect(error['stepIndex'], 2);
        expect(input.readAsBytesSync(), original);
        expect(output.readAsBytesSync(), <int>[4, 3, 2, 1]);
        expect(temporary.listSync().whereType<Directory>(), isEmpty);
      },
    );

    test('an indexed-write compile failure preserves workbook files', () async {
      final original = _workbook();
      final input = File('${temporary.path}/input.xlsx')
        ..writeAsBytesSync(original);
      final source = File('${temporary.path}/BadIndex.bas')
        ..writeAsStringSync(_badIndex);
      final output = File('${temporary.path}/output.xlsx')
        ..writeAsBytesSync(<int>[7, 8, 9]);
      final result = await _run(<String>[
        'run-vba',
        input.path,
        source.path,
        output.path,
      ]);
      expect(result.exitCode, 1);
      final error =
          _json(result.stderr as String)['error']! as Map<String, Object?>;
      expect(error['code'], 'vba_subscript_out_of_range');
      expect(error['moduleName'], 'BadIndex');
      expect(input.readAsBytesSync(), original);
      expect(output.readAsBytesSync(), <int>[7, 8, 9]);
      expect(temporary.listSync().whereType<Directory>(), isEmpty);
    });

    test(
      'an array allocation limit preserves a previously saved plan',
      () async {
        final source = File('${temporary.path}/Oversized.bas')
          ..writeAsStringSync(_oversizedArray);
        final output = File('${temporary.path}/report.json')
          ..writeAsStringSync('existing plan');
        final result = await _run(<String>[
          'compile-vba',
          source.path,
          output.path,
        ]);
        expect(result.exitCode, 1);
        final error =
            _json(result.stderr as String)['error']! as Map<String, Object?>;
        expect(error['code'], 'vba_limit_exceeded');
        expect(error['moduleName'], 'Oversized');
        expect(output.readAsStringSync(), 'existing plan');
        expect(temporary.listSync().whereType<Directory>(), isEmpty);
      },
    );
  });
}
