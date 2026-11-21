@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/office_macro_cli.dart';

const _example = 'example/macros/control_flow_report.bas';

const _lateFailure = '''
Sub Main()
  Dim row As Long
  row = 1
  Do
    Select Case row
      Case 1, 2
        Worksheets(1).Cells(row, 1).Value2 = "pending"
      Case Else
        Worksheets("Missing").Range("A1").Value2 = "never published"
    End Select
    row = row + 1
  Loop Until row > 3
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
    moduleName: 'ControlFlow',
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
    runOfficeMacroCli(arguments);

void main() {
  registerOfficeMacroCliCleanup();
  group('conditional control flow through the atomic runtime', () {
    test(
      'committed report compiles, round trips, validates, and runs',
      () async {
        final macro = _compile(File(_example).readAsStringSync());
        expect(macro.steps, hasLength(35));
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
        final sheet = SheetDeserializer()
            .readBytes(session.bytes)
            .sheets
            .single;
        expect(sheet.cellA1('A1').value, 'Batch');
        expect(sheet.cellA1('A1').fontBold, isTrue);
        expect(sheet.cellA1('A1').fillRgb, '1F4E79');
        expect(sheet.cellA1('A1').fontRgb, 'FFFFFF');
        const bands = <String>[
          'Small',
          'Standard',
          'Standard',
          'Large',
          'Large',
          'Review',
        ];
        for (var index = 0; index < bands.length; index++) {
          expect(sheet.cellA1('A${index + 2}').value, 'Batch ${index + 1}');
          expect(sheet.cellA1('B${index + 2}').value, (index + 1) * 75);
          expect(sheet.cellA1('C${index + 2}').value, bands[index]);
        }
        expect(sheet.cellA1('A8').value, 'Total');
        expect(sheet.cellA1('B8').formula, 'SUM(B2:B7)');
        expect(sheet.cellA1('B8').value, 1575);
        for (final column in <String>['A', 'B', 'C']) {
          expect(sheet.cellA1('${column}8').fontBold, isTrue);
        }
      },
    );

    test(
      'a failure in a later selected case rolls back every loop write',
      () async {
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
      },
    );

    test('loop and case plans retain host policy restrictions', () async {
      final macro = _compile(File(_example).readAsStringSync());
      for (final (policy, code) in <(OfficeMacroPolicy, String)>[
        (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
        (
          OfficeMacroPolicy(allowedTools: <String>{'xlsx.cellValue'}),
          'permission_denied',
        ),
        (OfficeMacroPolicy(maxSteps: 34), 'limit_exceeded'),
      ]) {
        final session = _session(policy: policy);
        final original = session.bytes;
        await expectLater(session.run(macro), throwsA(_error(code)));
        expect(session.bytes, original);
        expect(session.revision, 0);
      }
    });
  });

  group('conditional control flow through MCP', () {
    test(
      'compilation, validation, and saved-plan playback share the new dialect',
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
              'moduleName': 'ConditionalReport',
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
        expect(_structured(run)['completedSteps'], 35);
        expect(session.revision, 1);
        expect(
          SheetDeserializer()
              .readBytes(session.bytes)
              .sheets
              .single
              .cellA1('B8')
              .value,
          1575,
        );
      },
    );

    test(
      'nonterminating source produces structured bounded diagnostics',
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
              'moduleName': 'EndlessLoop',
              'source': 'Sub Main()\nDo\nLoop\nEnd Sub',
            },
          },
        );
        expect(result['isError'], isTrue);
        final error = _structured(result)['error']! as Map<String, Object?>;
        expect(error['code'], 'vba_limit_exceeded');
        expect(error['moduleName'], 'EndlessLoop');
        expect(error['entryPoint'], 'Main');
        expect(error['line'], 2);
        expect(error['column'], greaterThan(0));
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );
  });

  group('conditional control flow through actual CLI processes', () {
    late Directory temporary;
    setUp(
      () =>
          temporary = Directory.systemTemp.createTempSync('vba-control-flow-'),
    );
    tearDown(() => temporary.deleteSync(recursive: true));

    test('BAS and saved native plans produce the same report', () async {
      final original = _workbook();
      final input = File('${temporary.path}/input.xlsx')
        ..writeAsBytesSync(original);
      final plan = File('${temporary.path}/report.json');
      final compiled = await _run(<String>['compile-vba', _example, plan.path]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      expect(OfficeMacro.parse(plan.readAsStringSync()).steps, hasLength(35));
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
      expect(_json(basRun.stdout as String)['completedSteps'], 35);
      final bas = OfficeMacroSession(
        basOutput.readAsBytesSync(),
        format: OfficeMacroFormat.xlsx,
      );
      final native = OfficeMacroSession(
        nativeOutput.readAsBytesSync(),
        format: OfficeMacroFormat.xlsx,
      );
      expect(bas.inspect(), native.inspect());
      expect(input.readAsBytesSync(), original);
      expect(temporary.listSync().whereType<Directory>(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a custom entry invokes loops and cases in helpers', () async {
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
  Do While True
    Select Case 42
      Case 1 To 50
        Worksheets(1).Range("A1").Value2 = 42
        Exit Do
    End Select
  Loop
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
      'late selected-case failure preserves existing input and output files',
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

    test('a compile work limit preserves a previously saved plan', () async {
      final source = File('${temporary.path}/Unbounded.bas')
        ..writeAsStringSync('Sub Main()\nWhile True\nWend\nEnd Sub');
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
      expect(error['moduleName'], 'Unbounded');
      expect(output.readAsStringSync(), 'existing plan');
      expect(temporary.listSync().whereType<Directory>(), isEmpty);
    });
  });
}
