import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _example = 'example/macros/variant_report.bas';
const _reportSteps = 38;
const _nullWrite = '''Sub Main()
  Worksheets(1).Range("A1").Value2 = "pending"
  Worksheets(1).Range("A2").Value2 = Null
End Sub''';
const _badConversion = '''Sub Main()
  Worksheets(1).Range("A1").Value2 = Empty
  Worksheets(1).Range("A2").Value2 = CDbl("1,25")
End Sub''';
const _lateFailure = '''Sub Main()
  Worksheets("Summary").Range("C3").Value2 = Empty
  Worksheets("Summary").Range("A1").Value2 = CLng("2.5")
  Worksheets("Missing").Range("A1").Value2 = CStr(Empty)
End Sub''';

Uint8List _workbook() {
  final builder = XlsxWorkbookBuilder();
  builder.addSheet('Summary').addRow(<Object?>['original']);
  final book = SheetDeserializer().readBytes(builder.build());
  for (final address in <String>['C3', 'D3', 'C4', 'D4']) {
    book.sheets.single.cellA1(address)
      ..value = 2
      ..formula = '1+1'
      ..fontBold = true;
  }
  return SheetSerializer().writeBytes(book);
}

OfficeMacro _compile(String text) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    moduleName: 'VariantReport',
    source: text,
  ),
);

OfficeMacroSession _session({OfficeMacroPolicy? policy}) => OfficeMacroSession(
  _workbook(),
  format: OfficeMacroFormat.xlsx,
  policy: policy,
);

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _json(Object? value) =>
    jsonDecode(value! as String) as Map<String, Object?>;

Map<String, Object?> _source(String text) => <String, Object?>{
  'source': <String, Object?>{
    'language': 'vba-excel',
    'format': 'xlsx',
    'moduleName': 'VariantReport',
    'source': text,
  },
};

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
  const expected = <String, Object>{
    'A1': 'Record',
    'B1': 'State',
    'C1': 'Amount',
    'D1': 'Rounded',
    'A2': 1,
    'B2': 'Ready',
    'C2': 125.5,
    'D2': 126,
    'A3': 2,
    'B3': 'Missing',
    'A4': 3,
    'B4': 'Unassigned',
    'A5': 4,
    'B5': 'Ready',
    'C5': 250.25,
    'D5': 250,
    'B7': 'Source total',
    'C7': 375.75,
    'B8': 'Worksheet total',
    'C8': 375.75,
    'B10': 'Has accepted rows',
    'C10': true,
    'B11': 'Invariant total text',
    'C11': '375.75',
    'B12': 'Reallocated Empty',
    'C12': true,
  };
  for (final entry in expected.entries) {
    expect(sheet.cellA1(entry.key).value, entry.value, reason: entry.key);
  }
  expect(sheet.cellA1('C8').formula, 'SUM(C2:C5)');
  for (final address in <String>['C3', 'D3', 'C4', 'D4']) {
    final cell = sheet.cellA1(address);
    expect(cell.value, isNull, reason: address);
    expect(cell.formula, isNull, reason: address);
    expect(cell.fontBold, isTrue, reason: 'Existing formatting at $address');
  }
  for (final address in <String>[
    'A1',
    'B1',
    'C1',
    'D1',
    'B7',
    'C7',
    'B8',
    'C8',
  ]) {
    expect(sheet.cellA1(address).fontBold, isTrue, reason: address);
  }
}

void main() {
  group('Variant conversion plans through the document runtime', () {
    test(
      'example clears Empty cells, preserves styles and publishes once',
      () async {
        final macro = _compile(File(_example).readAsStringSync());
        expect(macro.steps, hasLength(_reportSteps));
        final saved = OfficeMacro.parse(macro.encode());
        expect(saved.toJson(), macro.toJson());
        expect(
          saved.steps.where(
            (step) =>
                step.arguments.containsKey('value') &&
                step.arguments['value'] == null,
          ),
          hasLength(4),
        );
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
      },
    );

    test(
      'late failure rolls back earlier clears and converted writes',
      () async {
        final session = _session();
        final original = session.bytes;
        final macro = _compile(_lateFailure);
        final failure = _error('operation_failed')
            .having((error) => error.stepIndex, 'step', 2)
            .having((error) => error.tool, 'tool', 'xlsx.cellValue');
        session.startRecording('unchanged');
        await expectLater(session.validate(macro), throwsA(failure));
        await expectLater(session.run(macro), throwsA(failure));
        expect(session.bytes, original);
        expect(session.revision, 0);
        expect(session.stopRecording().steps, isEmpty);
      },
    );

    test('Empty clears retain mutation, tool and step policies', () async {
      final macro = _compile(File(_example).readAsStringSync());
      for (final (policy, code) in <(OfficeMacroPolicy, String)>[
        (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
        (
          OfficeMacroPolicy(allowedTools: <String>{'xlsx.cellFormat'}),
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

  group('Variant conversions through MCP', () {
    test(
      'compile, detached validate and run share the native transaction',
      () async {
        final session = _session();
        final original = session.bytes;
        final adapter = OfficeMacroMcp(session);
        final compiled = await adapter.callTool(
          'office_macro_compile',
          _source(File(_example).readAsStringSync()),
        );
        expect(compiled['isError'], isFalse, reason: '$compiled');
        expect(session.bytes, original);
        final arguments = <String, Object?>{
          'macro': _structured(compiled)['macro'],
        };
        final validation = await adapter.callTool(
          'office_macro_validate',
          arguments,
        );
        expect(validation['isError'], isFalse, reason: '$validation');
        expect(_structured(validation)['validatedOnly'], isTrue);
        expect(session.bytes, original);
        expect(session.revision, 0);
        final result = await adapter.callTool('office_macro_run', arguments);
        expect(result['isError'], isFalse, reason: '$result');
        expect(_structured(result)['completedSteps'], _reportSteps);
        expect(session.revision, 1);
        _expectReport(session.bytes);
      },
    );

    for (final (source, code) in <(String, String)>[
      (_nullWrite, 'vba_invalid_use_of_null'),
      (_badConversion, 'vba_type_error'),
    ]) {
      test('$code returns a source diagnostic and no partial plan', () async {
        final session = _session();
        final original = session.bytes;
        session.startRecording('unchanged');
        final result = await OfficeMacroMcp(
          session,
        ).callTool('office_macro_compile', _source(source));
        expect(result['isError'], isTrue);
        final content = _structured(result);
        expect(content.containsKey('macro'), isFalse);
        final error = content['error']! as Map<String, Object?>;
        expect(error['code'], code);
        expect(error['moduleName'], 'VariantReport');
        expect(error['entryPoint'], 'Main');
        expect(error['line'], 3);
        expect(error['column'], greaterThan(0));
        expect(session.bytes, original);
        expect(session.revision, 0);
        expect(session.stopRecording().steps, isEmpty);
      });
    }
  });

  group('Variant conversions through actual CLI processes', () {
    late Directory temporary;
    setUp(
      () => temporary = Directory.systemTemp.createTempSync('vba-variants-'),
    );
    tearDown(() => temporary.deleteSync(recursive: true));

    test('BAS and persisted native plan produce the same workbook', () async {
      final original = _workbook();
      final input = File('${temporary.path}/input.xlsx')
        ..writeAsBytesSync(original);
      final plan = File('${temporary.path}/plan.json');
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
      expect(_json(validation.stdout)['validatedOnly'], isTrue);
      for (final (command, source) in <(String, String)>[
        ('run-vba', _example),
        ('run', plan.path),
      ]) {
        final output = File('${temporary.path}/$command.xlsx');
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
      expect(input.readAsBytesSync(), original);
      expect(temporary.listSync().whereType<Directory>(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'compile and runtime failures preserve existing output files',
      () async {
        final original = _workbook();
        final input = File('${temporary.path}/input.xlsx')
          ..writeAsBytesSync(original);
        for (final (text, code) in <(String, String)>[
          (_nullWrite, 'vba_invalid_use_of_null'),
          (_badConversion, 'vba_type_error'),
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

    test('Null conversion cannot overwrite a previously saved plan', () async {
      final source = File('${temporary.path}/NullResult.bas')
        ..writeAsStringSync(
          'Sub Main()\nWorksheets(1).Range("A1").Value2 = CStr(Null)\nEnd Sub',
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
      expect(error['code'], 'vba_invalid_use_of_null');
      expect(output.readAsStringSync(), 'existing plan');
      expect(temporary.listSync().whereType<Directory>(), isEmpty);
    });
  });
}
