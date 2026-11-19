import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _summarySource = '''
Option Explicit
Sub Main()
  Dim row As Long
  With ThisWorkbook.Worksheets("sUmMaRy")
    .Range("A1:B1").Value2 = "Revenue"
    .Range("A1:B1").Font.Bold = True
    .Range("A1:B1").Font.Color = RGB(23, 55, 89)
    .Range("A1:B1").Interior.Color = RGB(230, 240, 250)
    .Range("A1:B1").Font.Size = 14
    For row = 2 To 4
      .Cells(row, 1).Value2 = row * 10
    Next row
    .Range("B2").Formula = "=SUM(A2:A4)"
    .Range("D1").Font.Bold = True
    .Range("D1").Formula = "=1+1"
    .Range("D1").ClearContents
  End With
End Sub
''';

const _lateFailureSource = '''
Sub Main()
  Worksheets(1).Range("A1").Value2 = "Must not publish"
  Worksheets("Missing sheet").Range("A1").Value2 = 99
End Sub
''';

Uint8List _workbook() {
  final builder = XlsxWorkbookBuilder();
  builder.addSheet('Data').addRow(<Object?>['unchanged']);
  builder.addSheet('Summary').addRow(<Object?>['old summary']);
  return builder.build();
}

OfficeMacro _compile(String source, {String entryPoint = 'Main'}) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-excel',
        source: source,
        format: OfficeMacroFormat.xlsx,
        moduleName: 'IntegrationModule',
        entryPoint: entryPoint,
      ),
    );

OfficeMacroSession _session({OfficeMacroPolicy? policy}) => OfficeMacroSession(
  _workbook(),
  format: OfficeMacroFormat.xlsx,
  policy: policy,
);

TypeMatcher<OfficeMacroException> _error(String code) =>
    isA<OfficeMacroException>().having((error) => error.code, 'code', code);

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _json(Object? value) =>
    jsonDecode(value! as String) as Map<String, Object?>;

Future<ProcessResult> _run(List<String> args) =>
    Process.run(Platform.resolvedExecutable, <String>[
      if (Platform.packageConfig case final String packages)
        '--packages=$packages',
      'tool/macros/office_macro.dart',
      ...args,
    ]);

void main() {
  group('compiled Excel VBA transactions', () {
    test(
      'validate and run use real named sheets, formulas, styles, and clearing',
      () async {
        final session = _session();
        final original = session.bytes;
        final macro = _compile(_summarySource);
        expect(session.bytes, original);
        expect(session.revision, 0);

        final validation = await session.validate(macro);
        expect(validation.validatedOnly, isTrue);
        expect(validation.revision, 0);
        expect(session.bytes, original);
        expect(session.revision, 0);

        final receipt = await session.run(macro);
        expect(receipt.validatedOnly, isFalse);
        expect(receipt.revision, 1);
        final book = SheetDeserializer().readBytes(session.bytes);
        expect(book.sheets.first.cellA1('A1').value, 'unchanged');
        final summary = book.sheets[1];
        for (final address in <String>['A1', 'B1']) {
          final cell = summary.cellA1(address);
          expect(cell.value, 'Revenue');
          expect(cell.fontBold, isTrue);
          expect(cell.fontSize, 14);
          expect(cell.fontRgb, '173759');
          expect(cell.fillRgb, 'E6F0FA');
        }
        expect(summary.cellA1('A2').value, 20);
        expect(summary.cellA1('A3').value, 30);
        expect(summary.cellA1('A4').value, 40);
        expect(summary.cellA1('B2').formula, 'SUM(A2:A4)');
        expect(summary.cellA1('B2').value, 90);
        expect(summary.cellA1('D1').value, isNull);
        expect(summary.cellA1('D1').formula, isNull);
        expect(summary.cellA1('D1').fontBold, isTrue);
      },
    );

    test('late worksheet lookup failure rolls back every prior edit', () async {
      final session = _session();
      final original = session.bytes;
      final macro = _compile(_lateFailureSource);
      final failure = _error('operation_failed')
          .having((error) => error.stepIndex, 'stepIndex', 1)
          .having((error) => error.tool, 'tool', 'xlsx.cellValue');
      await expectLater(session.validate(macro), throwsA(failure));
      expect(session.bytes, original);
      expect(session.revision, 0);
      await expectLater(session.run(macro), throwsA(failure));
      expect(session.bytes, original);
      expect(session.revision, 0);
    });

    test(
      'compiled plans retain host permissions and operation limits',
      () async {
        final macro = _compile('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = "Changed"
  Worksheets(1).Range("A1").Font.Bold = True
End Sub
''');
        for (final policy in <OfficeMacroPolicy>[
          OfficeMacroPolicy(allowMutation: false),
          OfficeMacroPolicy(allowedTools: <String>{'xlsx.cellValue'}),
        ]) {
          final session = _session(policy: policy);
          final original = session.bytes;
          await expectLater(
            session.run(macro),
            throwsA(_error('permission_denied')),
          );
          expect(session.bytes, original);
          expect(session.revision, 0);
        }
        final session = _session(policy: OfficeMacroPolicy(maxSteps: 1));
        final original = session.bytes;
        await expectLater(
          session.run(macro),
          throwsA(_error('limit_exceeded')),
        );
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );

    test(
      'named worksheets use the same native and MCP operation path',
      () async {
        final direct = _session();
        await direct.callTool('xlsx.cellValue', <String, Object?>{
          'sheet': 'sUmMaRy',
          'cell': 'C3',
          'value': 42,
        });
        final compiled = _session();
        await compiled.run(
          _compile('''
Sub Main()
  Worksheets("Summary").Cells(3, 3).Value2 = 42
End Sub
'''),
        );
        final remote = _session();
        final result = await OfficeMacroMcp(remote).callTool(
          'xlsx.cellValue',
          <String, Object?>{'sheet': 'SUMMARY', 'cell': 'C3', 'value': 42},
        );
        expect(result['isError'], isFalse);
        expect(compiled.inspect(), direct.inspect());
        expect(remote.inspect(), direct.inspect());
      },
    );

    test(
      'VBA compilation keeps embedded project bytes inert and intact',
      () async {
        const workbookType =
            'application/vnd.ms-excel.sheet.macroEnabled.main+xml';
        const vbaType = 'application/vnd.ms-office.vbaProject';
        const relationshipType =
            'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
        final package = OpcPackage.openBytes(_workbook());
        package.getPart('/xl/workbook.xml')!.contentType = workbookType;
        package.contentTypes.setOverride('/xl/workbook.xml', workbookType);
        final opaque = Uint8List.fromList(<int>[0, 1, 127, 128, 254, 255]);
        package.createPart('/xl/vbaProject.bin', vbaType, opaque);
        package
            .relationshipsFor('/xl/workbook.xml')
            .add(type: relationshipType, target: 'vbaProject.bin');
        final session = OfficeMacroSession(
          package.save(),
          format: OfficeMacroFormat.xlsx,
        );
        await session.run(
          _compile('''
Sub Main()
  Worksheets(2).Range("A1").Value2 = "Explicit source only"
End Sub
'''),
        );
        final output = OpcPackage.openBytes(session.bytes);
        expect(output.getPart('/xl/vbaProject.bin')!.readBytes(), opaque);
        expect(output.getPart('/xl/vbaProject.bin')!.contentType, vbaType);
        expect(output.getPart('/xl/workbook.xml')!.contentType, workbookType);
        expect(
          output
              .relationshipsFor('/xl/workbook.xml')
              .firstByType(relationshipType)!
              .target,
          'vbaProject.bin',
        );
        expect(
          SheetDeserializer().read(output).sheets[1].cellA1('A1').value,
          'Explicit source only',
        );
      },
    );
  });

  group('VBA through MCP', () {
    test(
      'default compiler advertises, compiles, validates, and runs VBA',
      () async {
        final session = _session();
        final original = session.bytes;
        final adapter = OfficeMacroMcp(session);
        final tools =
            adapter.listTools()['tools']! as List<Map<String, Object?>>;
        final compiler = tools.singleWhere(
          (tool) => tool['name'] == 'office_macro_compile',
        );
        final input = compiler['inputSchema']! as Map<String, Object?>;
        final properties = input['properties']! as Map<String, Object?>;
        final source = properties['source']! as Map<String, Object?>;
        final fields = source['properties']! as Map<String, Object?>;
        final language = fields['language']! as Map<String, Object?>;
        expect(language['enum'], contains('vba-excel'));

        final compile = await adapter.callTool(
          'office_macro_compile',
          <String, Object?>{
            'source': <String, Object?>{
              'language': 'vba-excel',
              'format': 'xlsx',
              'source': _summarySource,
              'moduleName': 'Summary',
              'entryPoint': 'Main',
            },
          },
        );
        expect(compile['isError'], isFalse, reason: '$compile');
        expect(session.bytes, original);
        expect(session.revision, 0);
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
        expect(session.revision, 1);
        expect(
          SheetDeserializer()
              .readBytes(session.bytes)
              .sheets[1]
              .cellA1('B2')
              .value,
          90,
        );
      },
    );

    test(
      'compiler source diagnostics reach MCP clients without mutation',
      () async {
        final session = _session();
        final original = session.bytes;
        final result = await OfficeMacroMcp(session).callTool(
          'office_macro_compile',
          <String, Object?>{
            'source': <String, Object?>{
              'language': 'vba-excel',
              'format': 'xlsx',
              'source': 'Sub Main()\n  Shell "not invoked"\nEnd Sub',
              'moduleName': 'AuditModule',
              'entryPoint': 'Main',
            },
          },
        );
        expect(result['isError'], isTrue);
        final error = _structured(result)['error']! as Map<String, Object?>;
        expect(error['code'], 'vba_unsupported');
        expect(error['moduleName'], 'AuditModule');
        expect(error['entryPoint'], 'Main');
        expect(error['line'], 2);
        expect(error['column'], greaterThan(0));
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );
  });

  group('VBA command line', () {
    late Directory temporary;
    setUp(() {
      temporary = Directory.current.createTempSync('vba-cli-test-');
    });
    tearDown(() => temporary.deleteSync(recursive: true));

    test(
      'committed BAS monthly example calculates the complete report',
      () async {
        final output = File('${temporary.path}/monthly.xlsx');
        final result = await _run(<String>[
          'run-vba',
          'test/fixtures/fidelity/native.xlsx',
          'example/macros/monthly_totals.bas',
          output.path,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stderr, isEmpty);
        expect(_json(result.stdout)['completedSteps'], 76);
        final sheet = SheetDeserializer()
            .readBytes(output.readAsBytesSync())
            .sheets
            .first;
        expect(sheet.cellA1('A1').value, 'Month');
        expect(sheet.cellA1('A1').fontBold, isTrue);
        expect(sheet.cellA1('A1').fillRgb, '1F4E79');
        expect(sheet.cellA1('A13').value, 'Month 12');
        expect(sheet.cellA1('B14').value, 153000);
        expect(sheet.cellA1('C14').value, 85200);
        expect(sheet.cellA1('D14').value, 67800);
        expect(sheet.cellA1('D14').fontBold, isTrue);
      },
    );

    test(
      'raw BAS compilation and explicit entry point run the same plan',
      () async {
        final original = _workbook();
        final input = File('${temporary.path}/input.xlsx')
          ..writeAsBytesSync(original);
        final source = File('${temporary.path}/Report.bas')
          ..writeAsStringSync('''
Option Explicit
Sub BuildReport()
  Worksheets("Summary").Range("A1").Value2 = 42
  Worksheets("Summary").Range("B1").Formula = "=A1*2"
End Sub
''');
        final plan = File('${temporary.path}/compiled.json');
        final compile = await _run(<String>[
          'compile-vba',
          source.path,
          plan.path,
          'BuildReport',
        ]);
        expect(compile.exitCode, 0, reason: '${compile.stderr}');
        expect(compile.stderr, isEmpty);
        final macro = OfficeMacro.parse(plan.readAsStringSync());
        expect(macro.format, OfficeMacroFormat.xlsx);
        expect(macro.steps, hasLength(2));
        expect(input.readAsBytesSync(), original);

        final nativeOutput = File('${temporary.path}/native.xlsx');
        final native = await _run(<String>[
          'run',
          input.path,
          plan.path,
          nativeOutput.path,
        ]);
        expect(native.exitCode, 0, reason: '${native.stderr}');

        final validation = await _run(<String>[
          'validate-vba',
          input.path,
          source.path,
          'BuildReport',
        ]);
        expect(validation.exitCode, 0, reason: '${validation.stderr}');
        expect(_json(validation.stdout)['validatedOnly'], isTrue);
        expect(_json(validation.stdout)['revision'], 0);
        expect(input.readAsBytesSync(), original);

        final output = File('${temporary.path}/result.xlsx');
        final run = await _run(<String>[
          'run-vba',
          input.path,
          source.path,
          output.path,
          'BuildReport',
        ]);
        expect(run.exitCode, 0, reason: '${run.stderr}');
        expect(run.stderr, isEmpty);
        expect(_json(run.stdout)['revision'], 1);
        final result = OfficeMacroSession(
          output.readAsBytesSync(),
          format: OfficeMacroFormat.xlsx,
        );
        final nativeResult = OfficeMacroSession(
          nativeOutput.readAsBytesSync(),
          format: OfficeMacroFormat.xlsx,
        );
        expect(result.inspect(), nativeResult.inspect());
        final sheet = SheetDeserializer().readBytes(result.bytes).sheets[1];
        expect(sheet.cellA1('A1').value, 42);
        expect(sheet.cellA1('B1').formula, 'A1*2');
        expect(sheet.cellA1('B1').value, 84);
        expect(input.readAsBytesSync(), original);
        expect(temporary.listSync().whereType<Directory>(), isEmpty);
      },
      // Four fresh Dart CLI processes each load the engine before executing.
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'failed raw BAS execution preserves existing input and output',
      () async {
        final original = _workbook();
        final input = File('${temporary.path}/input.xlsx')
          ..writeAsBytesSync(original);
        final source = File('${temporary.path}/Fail.bas')
          ..writeAsStringSync(_lateFailureSource);
        final output = File('${temporary.path}/output.xlsx')
          ..writeAsBytesSync(<int>[4, 3, 2, 1]);
        final run = await _run(<String>[
          'run-vba',
          input.path,
          source.path,
          output.path,
        ]);
        expect(run.exitCode, 1);
        expect(run.stdout, isEmpty);
        final error = _json(run.stderr)['error']! as Map<String, Object?>;
        expect(error['code'], 'operation_failed');
        expect(error['stepIndex'], 1);
        expect(error['tool'], 'xlsx.cellValue');
        expect(input.readAsBytesSync(), original);
        expect(output.readAsBytesSync(), <int>[4, 3, 2, 1]);
        expect(temporary.listSync().whereType<Directory>(), isEmpty);
      },
    );

    test('unsupported BAS preserves an existing compiled output', () async {
      final source = File('${temporary.path}/Bad.bas')
        ..writeAsStringSync('Sub Main()\nShell "not invoked"\nEnd Sub');
      final output = File('${temporary.path}/compiled.json')
        ..writeAsStringSync('existing plan');
      final compile = await _run(<String>[
        'compile-vba',
        source.path,
        output.path,
      ]);
      expect(compile.exitCode, 1);
      expect(compile.stdout, isEmpty);
      final error = _json(compile.stderr)['error']! as Map<String, Object?>;
      expect(error['code'], 'vba_unsupported');
      expect(error['line'], 2);
      expect(error['column'], greaterThan(0));
      expect(output.readAsStringSync(), 'existing plan');
      expect(temporary.listSync().whereType<Directory>(), isEmpty);
    });

    test('Excel BAS cannot publish over a Word document', () async {
      final original = (DocxDocumentBuilder()..paragraph('original')).build();
      final input = File('${temporary.path}/input.docx')
        ..writeAsBytesSync(original);
      final output = File('${temporary.path}/output.docx')
        ..writeAsBytesSync(<int>[4, 3, 2, 1]);
      final source = File('${temporary.path}/Excel.bas')
        ..writeAsStringSync('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = "Only Excel"
End Sub
''');
      final run = await _run(<String>[
        'run-vba',
        input.path,
        source.path,
        output.path,
      ]);
      expect(run.exitCode, 1);
      expect(run.stdout, isEmpty);
      final error = _json(run.stderr)['error']! as Map<String, Object?>;
      expect(error['code'], 'format_mismatch');
      expect(input.readAsBytesSync(), original);
      expect(output.readAsBytesSync(), <int>[4, 3, 2, 1]);
      expect(temporary.listSync().whereType<Directory>(), isEmpty);
    });
  });
}
