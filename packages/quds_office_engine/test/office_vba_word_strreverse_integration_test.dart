@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_split_smoke.dart' as report;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_reverse_import.bas';
const _cell = 'ThisDocument.Tables(1).Cell(1, 1).Range.Text';

OfficeMacro _plan(String body) => report.wordSplitPlan(body);

void main() {
  registerOfficeMacroCliCleanup();

  for (final macroEnabled in [false, true]) {
    test('restores report and document ownership: $macroEnabled', () async {
      // The existing report oracle checks every native step, all body/story/
      // table neighbors, formatting, opaque parts, DOCM type, validation,
      // repeated save/reopen, native recording/replay and MCP compilation/run.
      // The new BAS reaches that independently authored report through
      // StrReverse, local arrays, typed helpers and computed cell selectors.
      final receipt = await report.runWordSplitExample(
        File(_example).readAsStringSync(),
        macroEnabled: macroEnabled,
      );
      expect(receipt['operations'], 7);
      expect(receipt['firstRunRevision'], 1);
      expect(receipt['repeatedRevision'], 2);
      expect(receipt['additionalReopens'], 2);
      expect(receipt['recordedSteps'], 7);
      expect(receipt['immutableValidation'], isTrue);
      expect(receipt['opaquePartsPreserved'], isTrue);
      expect(receipt['nativeRecordingAndReplay'], isTrue);
      expect(receipt['mcpCompileValidateRun'], isTrue);
    });
  }

  test('late missing table rolls back prepared reversed text', () async {
    final input = report.wordSplitInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx)
      ..startRecording('Only complete publications');
    final plan = _plan('''
$_cell = StrReverse("dehsilbupnU")
ThisDocument.Tables(99).Cell(1, 1).Range.Text = StrReverse("gnissiM")
''');
    for (final action in [session.validate, session.run]) {
      await expectLater(
        action(plan),
        throwsA(
          isA<OfficeMacroException>()
              .having((error) => error.stepIndex, 'step', 1)
              .having((error) => error.tool, 'tool', 'docx.tableCellRangeText'),
        ),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    }
    expect(session.stopRecording().steps, isEmpty);
  });

  for (final expression in [
    'StrReverse(Null)',
    'StrReverse("😀")',
    'StrReverse(ChrW(13))',
  ]) {
    test('source failure leaves document intact: $expression', () async {
      final input = report.wordSplitInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx)
        ..startRecording('Only complete publications');
      final result = await OfficeMacroMcp(session).callTool(
        'office_macro_compile',
        {
          'source': {
            'language': 'vba-word',
            'format': 'docx',
            'moduleName': 'ReverseImport',
            'source': '''
Sub Main()
$_cell = "Earlier but unpublished"
$_cell = $expression
End Sub
''',
          },
        },
      );
      expect(result['isError'], isTrue, reason: '$result');
      expect(session.bytes, input);
      expect(session.revision, 0);
      expect(session.stopRecording().steps, isEmpty);
    });
  }

  for (final policy in [
    OfficeMacroPolicy(allowMutation: false),
    OfficeMacroPolicy(allowedTools: {'docx.runFormat'}),
    OfficeMacroPolicy(maxSteps: 6),
  ]) {
    test('restored source text retains native policy: $policy', () async {
      final input = report.wordSplitInput();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      final plan = report.wordSplitSource(File(_example).readAsStringSync());
      await expectLater(
        session.run(plan),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    });
  }

  test(
    'CLI compiles, validates and publishes the restored report',
    () async {
      final directory = Directory.systemTemp.createTempSync('word-reverse-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File.fromUri(directory.uri.resolve('input.docm'))
        ..writeAsBytesSync(report.wordSplitInput());
      final before = input.readAsBytesSync();
      final source = File(_example).absolute.path;
      final compiled = File.fromUri(directory.uri.resolve('plan.json'));
      final compile = await runOfficeMacroCli([
        'compile-word-vba',
        source,
        compiled.path,
      ]);
      expect(compile.exitCode, 0, reason: compile.stderr.toString());
      report.assertWordSplitPlan(
        OfficeMacro.parse(compiled.readAsStringSync()),
      );
      final validate = await runOfficeMacroCli([
        'validate-word-vba',
        input.path,
        source,
      ]);
      expect(validate.exitCode, 0, reason: validate.stderr.toString());
      expect(input.readAsBytesSync(), before);
      final output = File.fromUri(directory.uri.resolve('output.docm'));
      final run = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source,
        output.path,
      ]);
      expect(run.exitCode, 0, reason: run.stderr.toString());
      expect(input.readAsBytesSync(), before);
      report.assertWordSplitOutput(output.readAsBytesSync(), before);
    },
    timeout: officeMacroCliTestTimeout,
  );

  test(
    'CLI source refusal retains an existing output file',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'word-reverse-error-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File.fromUri(directory.uri.resolve('input.docm'))
        ..writeAsBytesSync(report.wordSplitInput());
      final before = input.readAsBytesSync();
      final source = File.fromUri(directory.uri.resolve('invalid.bas'))
        ..writeAsStringSync('''
Sub Main()
$_cell = "Earlier but unpublished"
$_cell = StrReverse(Null)
End Sub
''');
      final output = File.fromUri(directory.uri.resolve('output.docm'))
        ..writeAsStringSync('previous output');
      final run = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source.path,
        output.path,
      ]);
      expect(run.exitCode, 1, reason: run.stderr.toString());
      expect(run.stderr.toString(), contains('vba_invalid_use_of_null'));
      expect(input.readAsBytesSync(), before);
      expect(output.readAsStringSync(), 'previous output');
    },
    timeout: officeMacroCliTestTimeout,
  );
}
