import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _example = 'example/macros/dynamic_array_report.bas';
const _reportSteps = 24;

const _lateFailure = '''
Option Explicit
Option Base 1
Sub Main()
  Dim names() As String, name As Variant
  ReDim names(1)
  names(1) = "Summary"
  ReDim Preserve names(2)
  names(2) = "Missing"
  For Each name In names
    Worksheets(name).Range("A1").Value2 = "pending"
  Next name
  Erase names
End Sub
''';

const _badPreserve = '''
Sub Main()
  Dim data() As Long
  ReDim data(1 To 2)
  Worksheets(1).Range("A1").Value2 = "must not publish"
  ReDim Preserve data(0 To 2)
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
    moduleName: 'DynamicReport',
    source: source,
  ),
);

OfficeMacroSession _session({OfficeMacroPolicy? policy}) => OfficeMacroSession(
  _workbook(),
  format: OfficeMacroFormat.xlsx,
  policy: policy,
);

Map<String, Object?> _json(Object? value) =>
    jsonDecode(value! as String) as Map<String, Object?>;

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
  expect(sheet.cellA1('D3').value, 'Reallocated default');
  expect(sheet.cellA1('D4').value, 0);
  expect(sheet.cellA1('B7').value, isNull);
}

void main() {
  group('dynamic array plans through the document runtime', () {
    test('report validates without publication and saved plan runs', () async {
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
      final validated = await session.validate(saved);
      expect(validated.validatedOnly, isTrue);
      expect(session.bytes, original);
      expect(session.revision, 0);
      final result = await session.run(saved);
      expect(result.completedSteps, _reportSteps);
      expect(session.revision, 1);
      _expectReport(session.bytes);
    });

    test('macro-enabled workbook keeps opaque VBA bytes and links', () async {
      const workbookType =
          'application/vnd.ms-excel.sheet.macroEnabled.main+xml';
      const vbaType = 'application/vnd.ms-office.vbaProject';
      const relationshipType =
          'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
      final package = OpcPackage.openBytes(_workbook());
      package.getPart('/xl/workbook.xml')!.contentType = workbookType;
      package.contentTypes.setOverride('/xl/workbook.xml', workbookType);
      final opaque = Uint8List.fromList(<int>[0, 1, 127, 128, 253, 254, 255]);
      package.createPart('/xl/vbaProject.bin', vbaType, opaque);
      final relationship = package
          .relationshipsFor('/xl/workbook.xml')
          .add(type: relationshipType, target: 'vbaProject.bin');
      final session = OfficeMacroSession(
        package.save(),
        format: OfficeMacroFormat.xlsx,
      );
      await session.run(_compile(File(_example).readAsStringSync()));
      _expectReport(session.bytes);
      final output = OpcPackage.openBytes(session.bytes);
      expect(output.getPart('/xl/vbaProject.bin')!.readBytes(), opaque);
      expect(output.getPart('/xl/vbaProject.bin')!.contentType, vbaType);
      expect(output.getPart('/xl/workbook.xml')!.contentType, workbookType);
      final saved = output
          .relationshipsFor('/xl/workbook.xml')
          .firstByType(relationshipType)!;
      expect(saved.id, relationship.id);
      expect(saved.target, relationship.target);
      expect(saved.targetMode, relationship.targetMode);
    });

    test('late sheet failure rolls back prior dynamic-array writes', () async {
      final macro = _compile(_lateFailure);
      expect(macro.steps, hasLength(2));
      final session = _session();
      final original = session.bytes;
      final failure = _error('operation_failed')
          .having((error) => error.stepIndex, 'step', 1)
          .having((error) => error.tool, 'tool', 'xlsx.cellValue');
      await expectLater(session.validate(macro), throwsA(failure));
      expect(session.bytes, original);
      await expectLater(session.run(macro), throwsA(failure));
      expect(session.bytes, original);
      expect(session.revision, 0);
    });

    test(
      'resized arrays cannot raise host permissions or step limits',
      () async {
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
      },
    );
  });

  group('dynamic array source through MCP', () {
    test('compile, validate, and run share the native transaction', () async {
      final session = _session();
      final original = session.bytes;
      final adapter = OfficeMacroMcp(session);
      final compiled = await adapter.callTool(
        'office_macro_compile',
        <String, Object?>{
          'source': <String, Object?>{
            'language': 'vba-excel',
            'format': 'xlsx',
            'moduleName': 'DynamicReport',
            'source': File(_example).readAsStringSync(),
          },
        },
      );
      expect(compiled['isError'], isFalse, reason: '$compiled');
      expect(session.bytes, original);
      final macro = _structured(compiled)['macro'];
      final validation = await adapter.callTool(
        'office_macro_validate',
        <String, Object?>{'macro': macro},
      );
      expect(validation['isError'], isFalse, reason: '$validation');
      expect(_structured(validation)['validatedOnly'], isTrue);
      expect(session.bytes, original);
      expect(session.revision, 0);
      final result = await adapter.callTool(
        'office_macro_run',
        <String, Object?>{'macro': macro},
      );
      expect(result['isError'], isFalse, reason: '$result');
      expect(_structured(result)['completedSteps'], _reportSteps);
      expect(session.revision, 1);
      _expectReport(session.bytes);
    });

    test(
      'compile is allowed read-only but execution still needs authority',
      () async {
        final session = _session(
          policy: OfficeMacroPolicy(allowMutation: false),
        );
        final original = session.bytes;
        final adapter = OfficeMacroMcp(session);
        final result = await adapter.callTool(
          'office_macro_compile',
          <String, Object?>{
            'source': <String, Object?>{
              'language': 'vba-excel',
              'format': 'xlsx',
              'source': File(_example).readAsStringSync(),
            },
          },
        );
        expect(result['isError'], isFalse, reason: '$result');
        final execution = await adapter.callTool(
          'office_macro_run',
          <String, Object?>{'macro': _structured(result)['macro']},
        );
        expect(execution['isError'], isTrue);
        final error = _structured(execution)['error']! as Map<String, Object?>;
        expect(error['code'], 'permission_denied');
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );

    test(
      'Preserve errors return source diagnostics without partial plan',
      () async {
        final session = _session();
        final original = session.bytes;
        final result = await OfficeMacroMcp(session).callTool(
          'office_macro_compile',
          <String, Object?>{
            'source': <String, Object?>{
              'language': 'vba-excel',
              'format': 'xlsx',
              'moduleName': 'BadPreserve',
              'source': _badPreserve,
            },
          },
        );
        expect(result['isError'], isTrue);
        final content = _structured(result);
        expect(content.containsKey('macro'), isFalse);
        final error = content['error']! as Map<String, Object?>;
        expect(error['code'], 'vba_subscript_out_of_range');
        expect(error['moduleName'], 'BadPreserve');
        expect(error['entryPoint'], 'Main');
        expect(error['line'], 5);
        expect(error['column'], greaterThan(0));
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );
  });

  group('dynamic array source through actual CLI processes', () {
    late Directory temporary;
    setUp(
      () => temporary = Directory.systemTemp.createTempSync(
        'vba-dynamic-arrays-',
      ),
    );
    tearDown(() => temporary.deleteSync(recursive: true));

    test('BAS and saved plan produce the same report', () async {
      final original = _workbook();
      final input = File('${temporary.path}/input.xlsx')
        ..writeAsBytesSync(original);
      final saved = File('${temporary.path}/plan.json');
      final compiled = await _run(<String>[
        'compile-vba',
        _example,
        saved.path,
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      expect(
        OfficeMacro.parse(saved.readAsStringSync()).steps,
        hasLength(_reportSteps),
      );
      final validated = await _run(<String>[
        'validate-vba',
        input.path,
        _example,
      ]);
      expect(validated.exitCode, 0, reason: '${validated.stderr}');
      expect(_json(validated.stdout)['validatedOnly'], isTrue);
      expect(input.readAsBytesSync(), original);
      final bas = File('${temporary.path}/bas.xlsx');
      final native = File('${temporary.path}/native.xlsx');
      for (final (command, source, output) in <(String, String, File)>[
        ('run-vba', _example, bas),
        ('run', saved.path, native),
      ]) {
        final result = await _run(<String>[
          command,
          input.path,
          source,
          output.path,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(_json(result.stdout)['completedSteps'], _reportSteps);
        _expectReport(output.readAsBytesSync());
      }
      expect(
        OfficeMacroSession(
          bas.readAsBytesSync(),
          format: OfficeMacroFormat.xlsx,
        ).inspect(),
        OfficeMacroSession(
          native.readAsBytesSync(),
          format: OfficeMacroFormat.xlsx,
        ).inspect(),
      );
      expect(input.readAsBytesSync(), original);
      expect(temporary.listSync().whereType<Directory>(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('selected entry can resize and erase local helper arrays', () async {
      final input = File('${temporary.path}/input.xlsx')
        ..writeAsBytesSync(_workbook());
      final source = File('${temporary.path}/Selected.bas')
        ..writeAsStringSync('''
Option Base 1
Sub Main()
  Worksheets(1).Range("A1").Value2 = "not selected"
End Sub
Sub Build()
  Call Helper()
End Sub
Sub Helper()
  Dim data() As Long
  ReDim data(1)
  data(1) = 42
  ReDim Preserve data(2)
  Worksheets(1).Range("A1").Value2 = data(1) + data(2)
  Erase data
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
      'compile and late runtime failures preserve existing outputs',
      () async {
        final original = _workbook();
        final input = File('${temporary.path}/input.xlsx')
          ..writeAsBytesSync(original);
        for (final (text, code) in <(String, String)>[
          (_badPreserve, 'vba_subscript_out_of_range'),
          (_lateFailure, 'operation_failed'),
        ]) {
          final source = File('${temporary.path}/Failure.bas')
            ..writeAsStringSync(text);
          final output = File('${temporary.path}/output.xlsx')
            ..writeAsBytesSync(<int>[7, 8, 9]);
          final result = await _run(<String>[
            'run-vba',
            input.path,
            source.path,
            output.path,
          ]);
          expect(result.exitCode, 1);
          final error = _json(result.stderr)['error']! as Map<String, Object?>;
          expect(error['code'], code);
          expect(input.readAsBytesSync(), original);
          expect(output.readAsBytesSync(), <int>[7, 8, 9]);
          expect(temporary.listSync().whereType<Directory>(), isEmpty);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'resize quota failure leaves a previously saved plan untouched',
      () async {
        final source = File('${temporary.path}/Oversized.bas')
          ..writeAsStringSync('''
Sub Main()
  Dim data() As Long
  ReDim data(0)
  Worksheets(1).Range("A1").Value2 = 42
  ReDim Preserve data(4096)
End Sub
''');
        final output = File('${temporary.path}/plan.json')
          ..writeAsStringSync('existing plan');
        final result = await _run(<String>[
          'compile-vba',
          source.path,
          output.path,
        ]);
        expect(result.exitCode, 1);
        final error = _json(result.stderr)['error']! as Map<String, Object?>;
        expect(error['code'], 'vba_limit_exceeded');
        expect(error['moduleName'], 'Oversized');
        expect(output.readAsStringSync(), 'existing plan');
        expect(temporary.listSync().whereType<Directory>(), isEmpty);
      },
    );
  });
}
