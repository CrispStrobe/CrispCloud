@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/office_macro_cli.dart';

const _example = 'example/macros/procedural_report.bas';

const _lateFailure = '''
Sub Main()
  WriteValue Worksheets(1), "Must not publish"
  Call WriteValue(Worksheets("Missing"), "Must not publish either")
End Sub
Sub WriteValue(ByVal sheet As Worksheet, ByVal text As String)
  sheet.Range("A1").Value2 = text
End Sub
''';

Uint8List _workbook() {
  final builder = XlsxWorkbookBuilder();
  builder.addSheet('Summary').addRow(<Object?>['original']);
  return builder.build();
}

OfficeMacro _compile(String source, {String entryPoint = 'Main'}) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-excel',
        format: OfficeMacroFormat.xlsx,
        moduleName: 'Procedures',
        entryPoint: entryPoint,
        source: source,
      ),
    );

OfficeMacroSession _session({OfficeMacroPolicy? policy}) => OfficeMacroSession(
  _workbook(),
  format: OfficeMacroFormat.xlsx,
  policy: policy,
);

Map<String, Object?> _json(String source) =>
    jsonDecode(source) as Map<String, Object?>;

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

TypeMatcher<OfficeMacroException> _error(String code) =>
    isA<OfficeMacroException>().having((error) => error.code, 'code', code);

Future<ProcessResult> _run(List<String> args) => runOfficeMacroCli(args);

void main() {
  registerOfficeMacroCliCleanup();
  group('VBA helpers through the atomic runtime', () {
    test(
      'committed report compiles, round trips, validates, and runs',
      () async {
        final macro = _compile(File(_example).readAsStringSync());
        expect(macro.steps, hasLength(46));
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

        final run = await session.run(saved);
        expect(run.revision, 1);
        final sheet = SheetDeserializer()
            .readBytes(session.bytes)
            .sheets
            .single;
        expect(sheet.cellA1('A1').value, 'Item');
        expect(sheet.cellA1('A1').fontBold, isTrue);
        expect(sheet.cellA1('A1').fillRgb, '1F4E79');
        expect(sheet.cellA1('A1').fontRgb, 'FFFFFF');
        expect(sheet.cellA1('A7').value, 'Item 6');
        expect(sheet.cellA1('B7').value, 30);
        expect(sheet.cellA1('C7').value, 27.5);
        final net = <num>[75, 157.5, 270, 382.5, 531.25, 701.25];
        for (var index = 0; index < net.length; index++) {
          expect(
            sheet.cellA1('D${index + 2}').value,
            closeTo(net[index], 1e-9),
          );
        }
        expect(sheet.cellA1('D8').formula, 'SUM(D2:D7)');
        expect(sheet.cellA1('D8').value, closeTo(2117.5, 1e-9));
        expect(sheet.cellA1('D8').fontBold, isTrue);
      },
    );

    test(
      'a late failure inside a helper rolls back all helper writes',
      () async {
        final session = _session();
        final original = session.bytes;
        final macro = _compile(_lateFailure);
        expect(macro.steps, hasLength(2));
        final failure = _error('operation_failed')
            .having((error) => error.stepIndex, 'stepIndex', 1)
            .having((error) => error.tool, 'tool', 'xlsx.cellValue');
        await expectLater(session.validate(macro), throwsA(failure));
        expect(session.bytes, original);
        expect(session.revision, 0);
        await expectLater(session.run(macro), throwsA(failure));
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );

    test(
      'helper-generated plans retain every host policy restriction',
      () async {
        final macro = _compile(File(_example).readAsStringSync());
        for (final (policy, code) in <(OfficeMacroPolicy, String)>[
          (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
          (
            OfficeMacroPolicy(allowedTools: <String>{'xlsx.cellValue'}),
            'permission_denied',
          ),
          (OfficeMacroPolicy(maxSteps: 45), 'limit_exceeded'),
        ]) {
          final session = _session(policy: policy);
          final original = session.bytes;
          await expectLater(session.run(macro), throwsA(_error(code)));
          expect(session.bytes, original);
          expect(session.revision, 0);
        }
      },
    );

    test(
      'function side effects are ordinary ordered native operations',
      () async {
        final macro = _compile('''
Sub Main()
  Worksheets(1).Range("B1").Value2 = RecordValue(21) * 2
End Sub
Function RecordValue(ByVal value As Long) As Long
  Worksheets(1).Range("A1").Value2 = value
  RecordValue = value
End Function
''');
        expect(macro.steps.map((step) => step.arguments['cell']), <String>[
          'A1',
          'B1',
        ]);
        final session = _session();
        await session.run(macro);
        final sheet = SheetDeserializer()
            .readBytes(session.bytes)
            .sheets
            .single;
        expect(sheet.cellA1('A1').value, 21);
        expect(sheet.cellA1('B1').value, 42);
      },
    );
  });

  group('VBA helpers through MCP', () {
    test(
      'MCP compilation, validation, and playback accept helper modules',
      () async {
        final session = _session();
        final original = session.bytes;
        final adapter = OfficeMacroMcp(session);
        final compile = await adapter.callTool(
          'office_macro_compile',
          <String, Object?>{
            'source': <String, Object?>{
              'language': 'vba-excel',
              'format': 'xlsx',
              'moduleName': 'ReusableReport',
              'source': File(_example).readAsStringSync(),
            },
          },
        );
        expect(compile['isError'], isFalse, reason: '$compile');
        expect(session.bytes, original);
        final macro = _structured(compile)['macro'];
        final validate = await adapter.callTool(
          'office_macro_validate',
          <String, Object?>{'macro': macro},
        );
        expect(validate['isError'], isFalse, reason: '$validate');
        expect(_structured(validate)['validatedOnly'], isTrue);
        expect(session.bytes, original);
        expect(session.revision, 0);
        final run = await adapter.callTool(
          'office_macro_run',
          <String, Object?>{'macro': macro},
        );
        expect(run['isError'], isFalse, reason: '$run');
        expect(_structured(run)['completedSteps'], 46);
        expect(session.revision, 1);
        expect(
          SheetDeserializer()
              .readBytes(session.bytes)
              .sheets
              .single
              .cellA1('D8')
              .value,
          closeTo(2117.5, 1e-9),
        );
      },
    );

    test(
      'an unsupported unused helper produces structured MCP diagnostics',
      () async {
        final session = _session();
        final original = session.bytes;
        final result = await OfficeMacroMcp(session).callTool(
          'office_macro_compile',
          <String, Object?>{
            'source': <String, Object?>{
              'language': 'vba-excel',
              'format': 'xlsx',
              'moduleName': 'RejectedHelper',
              'source':
                  'Sub Main()\nEnd Sub\nSub Unsafe(ByRef value As Long)\nEnd Sub',
            },
          },
        );
        expect(result['isError'], isTrue);
        final error = _structured(result)['error']! as Map<String, Object?>;
        expect(error['code'], 'vba_unsupported');
        expect(error['moduleName'], 'RejectedHelper');
        expect(error['entryPoint'], 'Main');
        expect(error['line'], 3);
        expect(error['column'], greaterThan(0));
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );
  });

  group('VBA helpers through actual CLI processes', () {
    late Directory temporary;
    setUp(
      () => temporary = Directory.systemTemp.createTempSync('vba-procedures-'),
    );
    tearDown(() => temporary.deleteSync(recursive: true));

    test('BAS and saved native plans produce the same report', () async {
      final original = _workbook();
      final input = File('${temporary.path}/input.xlsx')
        ..writeAsBytesSync(original);
      final plan = File('${temporary.path}/report.json');
      final compiled = await _run(<String>['compile-vba', _example, plan.path]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      expect(OfficeMacro.parse(plan.readAsStringSync()).steps, hasLength(46));
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
      expect(_json(basRun.stdout as String)['completedSteps'], 46);
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

    test('custom entry selection can invoke parameterized helpers', () async {
      final input = File('${temporary.path}/input.xlsx')
        ..writeAsBytesSync(_workbook());
      final source = File('${temporary.path}/Selected.bas')
        ..writeAsStringSync('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = "not selected"
End Sub
Sub Build()
  Call PutValue(42)
End Sub
Sub PutValue(ByVal value As Long)
  Worksheets(1).Range("A1").Value2 = value
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
      'late helper failure preserves existing input and output files',
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
        expect(error['stepIndex'], 1);
        expect(input.readAsBytesSync(), original);
        expect(output.readAsBytesSync(), <int>[4, 3, 2, 1]);
        expect(temporary.listSync().whereType<Directory>(), isEmpty);
      },
    );

    test(
      'recursive source leaves a previously compiled output untouched',
      () async {
        final source = File('${temporary.path}/Recursive.bas')
          ..writeAsStringSync('''
Sub Main()
End Sub
Sub Hidden()
  Call Hidden()
End Sub
''');
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
        expect(error['code'], 'vba_unsupported');
        expect(error['moduleName'], 'Recursive');
        expect(error['line'], greaterThan(0));
        expect(output.readAsStringSync(), 'existing plan');
        expect(temporary.listSync().whereType<Directory>(), isEmpty);
      },
    );
  });
}
