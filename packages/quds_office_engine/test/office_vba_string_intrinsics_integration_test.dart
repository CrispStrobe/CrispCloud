@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/office_macro_cli.dart';

const _example = 'example/macros/string_report.bas';
const _reportSteps = 28;
const _invalidCount = r'''Sub Main()
  Worksheets(1).Range("A1").Value2 = Left$("pending", 4)
  Worksheets(1).Range("A2").Value2 = Mid$("invalid", 0)
End Sub''';
const _lateFailure = r'''Sub Main()
  Worksheets("Summary").Range("A1").Value2 = Right$("pending", 4)
  Worksheets(Mid$("xMissing", 2)).Range("A1").Value2 = Len("fail")
End Sub''';
const _invalidUnicode = r'''Sub Main()
  Worksheets(1).Range("A1").Value2 = "pending"
  Worksheets(1).Range("A2").Value2 = Left$("😀", 1)
End Sub''';

Uint8List _workbook() {
  final builder = XlsxWorkbookBuilder();
  builder.addSheet('Summary').addRow(<Object?>['original']);
  return builder.build();
}

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    moduleName: 'StringReport',
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
    runOfficeMacroCli(arguments);

Map<String, Object?> _source(String text, {String module = 'StringReport'}) =>
    <String, Object?>{
      'source': <String, Object?>{
        'language': 'vba-excel',
        'format': 'xlsx',
        'moduleName': module,
        'source': text,
      },
    };

void _expectReport(Uint8List bytes) {
  final sheet = SheetDeserializer().readBytes(bytes).sheets.single;
  const expected = <String, Object>{
    'A1': 'Record code',
    'B1': 'Item',
    'C1': 'ID suffix',
    'D1': 'Item units',
    'A2': 'INV-1042',
    'B2': 'Paper',
    'C2': '1042',
    'D2': 5,
    'A3': 'INV-2088',
    'B3': 'Ink',
    'C3': '2088',
    'D3': 3,
    'A4': 'INV-3099',
    'B4': 'Labels',
    'C4': '3099',
    'D4': 6,
    'A5': 'Worksheet total',
    'D5': 14,
    'F1': 'Source total',
    'F2': 14,
    'F3': 'UTF-16 units',
    'F4': 4,
    'G3': 'Emoji',
    'G4': '😀',
  };
  for (final entry in expected.entries) {
    expect(sheet.cellA1(entry.key).value, entry.value, reason: entry.key);
  }
  for (final cell in <String>['A1', 'B1', 'C1', 'D1']) {
    expect(sheet.cellA1(cell).fontBold, isTrue);
  }
  expect(sheet.cellA1('D5').formula, 'SUM(D2:D4)');
}

void main() {
  registerOfficeMacroCliCleanup();
  group('string intrinsic plans through the document runtime', () {
    test(
      'internal surrogate halves recombine without workbook data loss',
      () async {
        final macro = _compile(r'''Sub Main()
  Dim high As String, low As String
  high = Left$("😀", 1)
  low = Right$("😀", 1)
  Worksheets(1).Range("A1").Value2 = high & low
  Worksheets(1).Range("B1").Value2 = Len(high)
  Worksheets(1).Range("C1").Value2 = Len(low)
End Sub''');
        final session = _session();
        final original = session.bytes;
        await session.validate(macro);
        expect(session.bytes, original);
        expect(session.revision, 0);
        await session.run(OfficeMacro.parse(macro.encode()));
        final sheet = SheetDeserializer()
            .readBytes(session.bytes)
            .sheets
            .single;
        expect((sheet.cellA1('A1').value! as String).codeUnits, <int>[
          0xD83D,
          0xDE00,
        ]);
        expect(sheet.cellA1('B1').value, 1);
        expect(sheet.cellA1('C1').value, 1);
        expect(session.revision, 1);
      },
    );

    test('example validates, round-trips and publishes one revision', () async {
      final macro = _compile(File(_example).readAsStringSync());
      expect(macro.steps, hasLength(_reportSteps));
      final saved = OfficeMacro.parse(macro.encode());
      expect(saved.toJson(), macro.toJson());
      final session = _session();
      final original = session.bytes;
      final validation = await session.validate(saved);
      expect(validation.validatedOnly, isTrue);
      expect(session.bytes, original);
      expect(session.revision, 0);
      final result = await session.run(saved);
      expect(result.completedSteps, _reportSteps);
      expect(session.revision, 1);
      _expectReport(session.bytes);
    });

    test(
      'late missing-sheet failure rolls back earlier substring writes',
      () async {
        final macro = _compile(_lateFailure);
        expect(macro.steps, hasLength(2));
        final session = _session();
        final original = session.bytes;
        final failure = _error('operation_failed')
            .having((error) => error.stepIndex, 'step', 1)
            .having((error) => error.tool, 'tool', 'xlsx.cellValue');
        await expectLater(session.validate(macro), throwsA(failure));
        await expectLater(session.run(macro), throwsA(failure));
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );

    test(
      'computed strings retain native mutation, tool and step policies',
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

  group('string intrinsics through MCP', () {
    test('malformed UTF-16 never returns a partial publishable plan', () async {
      for (final statement in <String>[
        r'Worksheets(1).Range("A2").Value2 = Left$("😀", 1)',
        r'Worksheets(1).Range("A2").Formula = "=" & Right$("😀", 1)',
        r'Worksheets(Left$("😀", 1)).Range("A1").ClearContents',
        r'Worksheets(Right$("😀", 1)).Range("A1").Font.Bold = True',
      ]) {
        final session = _session();
        final original = session.bytes;
        final result = await OfficeMacroMcp(session).callTool(
          'office_macro_compile',
          _source(
            'Sub Main()\n  Worksheets(1).Range("A1").Value2 = "pending"\n  $statement\nEnd Sub',
            module: 'UnicodeBoundary',
          ),
        );
        expect(result['isError'], isTrue, reason: statement);
        final content = _structured(result);
        expect(content.containsKey('macro'), isFalse);
        final error = content['error']! as Map<String, Object?>;
        expect(error['code'], 'vba_type_error');
        expect(error['moduleName'], 'UnicodeBoundary');
        expect(error['line'], 3);
        expect(error['column'], greaterThan(0));
        expect(session.bytes, original);
        expect(session.revision, 0);
      }
    });

    test(
      'compiled plan validates and runs through the shared transaction',
      () async {
        final session = _session();
        final original = session.bytes;
        final adapter = OfficeMacroMcp(session);
        final result = await adapter.callTool(
          'office_macro_compile',
          _source(File(_example).readAsStringSync()),
        );
        expect(result['isError'], isFalse, reason: '$result');
        expect(session.bytes, original);
        final arguments = <String, Object?>{
          'macro': _structured(result)['macro'],
        };
        final validation = await adapter.callTool(
          'office_macro_validate',
          arguments,
        );
        expect(validation['isError'], isFalse, reason: '$validation');
        expect(_structured(validation)['validatedOnly'], isTrue);
        expect(session.bytes, original);
        expect(session.revision, 0);
        final run = await adapter.callTool('office_macro_run', arguments);
        expect(run['isError'], isFalse, reason: '$run');
        expect(_structured(run)['completedSteps'], _reportSteps);
        expect(session.revision, 1);
        _expectReport(session.bytes);
      },
    );

    test(
      'bad Mid start reports source position without a partial plan',
      () async {
        final session = _session();
        final original = session.bytes;
        final result = await OfficeMacroMcp(session).callTool(
          'office_macro_compile',
          _source(_invalidCount, module: 'BadString'),
        );
        expect(result['isError'], isTrue);
        final content = _structured(result);
        expect(content.containsKey('macro'), isFalse);
        final error = content['error']! as Map<String, Object?>;
        expect(error['code'], 'vba_type_error');
        expect(error['moduleName'], 'BadString');
        expect(error['entryPoint'], 'Main');
        expect(error['line'], 3);
        expect(error['column'], greaterThan(0));
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );

    test(
      'read-only hosts may compile but cannot publish a string plan',
      () async {
        final session = _session(
          policy: OfficeMacroPolicy(allowMutation: false),
        );
        final original = session.bytes;
        final adapter = OfficeMacroMcp(session);
        final compiled = await adapter.callTool(
          'office_macro_compile',
          _source(File(_example).readAsStringSync()),
        );
        expect(compiled['isError'], isFalse);
        final result = await adapter.callTool(
          'office_macro_run',
          <String, Object?>{'macro': _structured(compiled)['macro']},
        );
        expect(result['isError'], isTrue);
        final error = _structured(result)['error']! as Map<String, Object?>;
        expect(error['code'], 'permission_denied');
        expect(session.bytes, original);
        expect(session.revision, 0);
      },
    );
  });

  group('string intrinsics through actual CLI processes', () {
    late Directory temporary;
    setUp(
      () => temporary = Directory.systemTemp.createTempSync('vba-strings-'),
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
      final validation = await _run(<String>[
        'validate-vba',
        input.path,
        _example,
      ]);
      expect(validation.exitCode, 0, reason: '${validation.stderr}');
      expect(_json(validation.stdout)['validatedOnly'], isTrue);
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
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'compile and late runtime failures preserve existing workbooks',
      () async {
        final original = _workbook();
        final input = File('${temporary.path}/input.xlsx')
          ..writeAsBytesSync(original);
        for (final (text, code) in <(String, String)>[
          (_invalidCount, 'vba_type_error'),
          (_invalidUnicode, 'vba_type_error'),
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
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'copy-work exhaustion leaves a previously saved plan untouched',
      () async {
        final text = List<String>.filled(8000, 'x').join();
        final source = File('${temporary.path}/StringBudget.bas')
          ..writeAsStringSync(
            'Sub Main()\nDim text As String, index As Long\ntext = "$text"\n'
            'Worksheets(1).Range("A1").Value2 = 42\nFor index = 1 To 20\n'
            r'text = Left$(text, 8000)'
            '\nNext index\nEnd Sub',
          );
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
        expect(error['moduleName'], 'StringBudget');
        expect(output.readAsStringSync(), 'existing plan');
        expect(temporary.listSync().whereType<Directory>(), isEmpty);
      },
    );
  });
}
