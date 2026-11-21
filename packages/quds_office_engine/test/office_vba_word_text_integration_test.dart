@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_text_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_text_report.bas';
const _range = 'ActiveDocument.Paragraphs(1).Range';

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'committed text report preserves rich body/header text and DOCM',
    () async {
      final receipt = await portable.runWordTextExample(
        File(_example).readAsStringSync(),
      );
      expect(receipt['operations'], 6);
      expect(receipt['revision'], 1);
      expect(receipt['recordedSteps'], 6);
      expect(receipt['additionalReopens'], 2);
      expect(receipt['opaqueVbaPreserved'], isTrue);
      expect(receipt['richFormattingPreserved'], isTrue);
      expect(receipt['text'], portable.wordTextExpected);
    },
  );

  test(
    'late missing target rolls back prepared text and all formatting',
    () async {
      final input = portable.wordTextInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Successful publications only');
      final plan = portable.wordTextPlan('''
$_range.InsertBefore Trim\$(Replace("  DRAFT_one  ", "DRAFT", "FINAL"))
$_range.Font.Bold = True
ActiveDocument.Paragraphs(99).Range.InsertBefore "Missing target"
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(
            isA<OfficeMacroException>()
                .having((e) => e.stepIndex, 'step', 2)
                .having((e) => e.tool, 'tool', 'docx.replaceText'),
          ),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  for (final expression in [
    'Replace("a", "a", "b", 1, -1, vbTextCompare)',
    'InStrRev("a", "a", 0)',
    'Trim\$(Null)',
  ]) {
    test(
      'source failure cannot publish an earlier insertion: $expression',
      () async {
        final input = portable.wordTextInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        final adapter = OfficeMacroMcp(session);
        final result = await adapter.callTool('office_macro_compile', {
          'source': {
            'language': 'vba-word',
            'format': 'docx',
            'source':
                'Sub Main()\n$_range.InsertBefore "Unpublished"\n'
                '$_range.InsertBefore CStr($expression)\nEnd Sub',
          },
        });
        expect(result['isError'], isTrue, reason: '$result');
        expect(session.bytes, input);
        expect(session.revision, 0);
      },
    );
  }

  for (final policy in [
    OfficeMacroPolicy(allowMutation: false),
    OfficeMacroPolicy(allowedTools: {'docx.runFormat'}),
    OfficeMacroPolicy(maxSteps: 5),
  ]) {
    test('prepared text retains native mutation policy: $policy', () async {
      final input = portable.wordTextInput();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      final plan = portable.wordTextSource(File(_example).readAsStringSync());
      await expectLater(
        session.run(plan),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    });
  }

  test('MCP compiles, validates and runs the complete text report', () async {
    final input = portable.wordTextInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    final adapter = OfficeMacroMcp(session);
    final compiled = await adapter.callTool('office_macro_compile', {
      'source': {
        'language': 'vba-word',
        'format': 'docx',
        'moduleName': 'WordTextReport',
        'source': File(_example).readAsStringSync(),
      },
    });
    expect(compiled['isError'], isFalse, reason: '$compiled');
    final arguments = <String, Object?>{
      'macro': _structured(compiled)['macro'],
    };
    final validated = await adapter.callTool(
      'office_macro_validate',
      arguments,
    );
    expect(validated['isError'], isFalse, reason: '$validated');
    expect(_structured(validated)['validatedOnly'], isTrue);
    expect(session.bytes, input);
    final executed = await adapter.callTool('office_macro_run', arguments);
    expect(executed['isError'], isFalse, reason: '$executed');
    expect(_structured(executed)['completedSteps'], 6);
    expect(portable.wordTextState(session.bytes), portable.wordTextExpected);
  });

  test(
    'CLI compiles and publishes the report with original input intact',
    () async {
      final directory = Directory.systemTemp.createTempSync('word-text-cli-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordTextInput());
      final before = input.readAsBytesSync();
      final source = File(_example).absolute.path;
      final compiled = File('${directory.path}/plan.json');
      final compile = await runOfficeMacroCli([
        'compile-word-vba',
        source,
        compiled.path,
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '${compile.stdout}\n${compile.stderr}',
      );
      expect(
        OfficeMacro.parse(compiled.readAsStringSync()).steps,
        hasLength(6),
      );
      final validate = await runOfficeMacroCli([
        'validate-word-vba',
        input.path,
        source,
      ]);
      expect(
        validate.exitCode,
        0,
        reason: '${validate.stdout}\n${validate.stderr}',
      );
      expect(input.readAsBytesSync(), before);
      final output = File('${directory.path}/output.docm');
      final run = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source,
        output.path,
      ]);
      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
      expect(input.readAsBytesSync(), before);
      expect(
        portable.wordTextState(output.readAsBytesSync()),
        portable.wordTextExpected,
      );
      final guard = (await WordPackagePreservation.capture(
        before,
        input.path,
      ))!;
      await guard.validateSaved(output.readAsBytesSync());
    },
    timeout: officeMacroCliTestTimeout,
  );

  test('CLI text diagnostic preserves an existing output file', () async {
    final directory = Directory.systemTemp.createTempSync('word-text-refusal-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final input = File('${directory.path}/input.docm')
      ..writeAsBytesSync(portable.wordTextInput());
    final source = File('${directory.path}/invalid.bas')
      ..writeAsStringSync('''
Sub Main()
$_range.InsertBefore "Do not publish this prefix"
$_range.InsertBefore Replace("a", "a", "b", 1, -2)
End Sub
''');
    final output = File('${directory.path}/output.docm')
      ..writeAsStringSync('previous output');
    final beforeInput = input.readAsBytesSync();
    final beforeOutput = output.readAsBytesSync();
    final run = await runOfficeMacroCli([
      'run-word-vba',
      input.path,
      source.path,
      output.path,
    ]);
    expect(run.exitCode, 1, reason: '${run.stdout}\n${run.stderr}');
    expect('${run.stderr}', contains('vba_type_error'));
    expect(input.readAsBytesSync(), beforeInput);
    expect(output.readAsBytesSync(), beforeOutput);
  }, timeout: officeMacroCliTestTimeout);
}
