import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_mid_assignment_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_fixed_width_labels.bas';

Map<String, Object?> _json(Object? value) =>
    jsonDecode(value! as String) as Map<String, Object?>;

Map<String, Object?> _failure(ProcessResult result) {
  expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
  return _json(result.stderr)['error']! as Map<String, Object?>;
}

void main() {
  registerOfficeMacroCliCleanup();

  for (final extension in ['docx', 'docm']) {
    test(
      'CLI $extension exact BAS validates, publishes, replays and retains outputs on failure',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'word-mid-assignment-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final input = File('${directory.path}/input.$extension')
          ..writeAsBytesSync(
            portable.wordMidAssignmentInput(macroEnabled: extension == 'docm'),
          );
        final original = input.readAsBytesSync();
        final source = File(_example).absolute.path;
        final plan = File('${directory.path}/labels.qudsmacro.json');
        final compiled = await runOfficeMacroCli([
          'compile-word-vba',
          source,
          plan.path,
        ]);
        expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
        expect(OfficeMacro.parse(plan.readAsStringSync()).steps, hasLength(8));
        final planBefore = plan.readAsBytesSync();
        final validated = await runOfficeMacroCli([
          'validate-word-vba',
          input.path,
          source,
        ]);
        expect(validated.exitCode, 0, reason: '${validated.stderr}');
        expect(_json(validated.stdout)['validatedOnly'], isTrue);
        expect(_json(validated.stdout)['completedSteps'], 8);
        expect(input.readAsBytesSync(), original);
        final output = File('${directory.path}/output.$extension');
        final executed = await runOfficeMacroCli([
          'run-word-vba',
          input.path,
          source,
          output.path,
        ]);
        expect(executed.exitCode, 0, reason: '${executed.stderr}');
        expect(_json(executed.stdout)['completedSteps'], 8);
        final saved = output.readAsBytesSync();
        portable.assertWordMidAssignmentExample(saved);
        expect(
          portable.wordMidAssignmentUntouched(saved),
          portable.wordMidAssignmentUntouched(original),
        );
        final guard = (await WordPackagePreservation.capture(
          original,
          input.path,
        ))!;
        await guard.validateSaved(saved);
        final replay = File('${directory.path}/replay.$extension');
        final replayed = await runOfficeMacroCli([
          'run',
          input.path,
          plan.path,
          replay.path,
        ]);
        expect(replayed.exitCode, 0, reason: '${replayed.stderr}');
        expect(
          portable.wordMidAssignmentState(replay.readAsBytesSync()),
          portable.wordMidAssignmentState(saved),
        );
        final missing = File('${directory.path}/missing.bas')
          ..writeAsStringSync(r'''
Sub Main()
  Dim label As String
  label = "0000"
  Mid$(label, 1, 4) = "0042"
  ActiveDocument.Tables(1).Cell(1, 1).Range.Text = label
  ActiveDocument.Tables(2).Cell(2, 1).Range.Text = label
End Sub
''');
        for (final command in ['validate-word-vba', 'run-word-vba']) {
          final error = _failure(
            await runOfficeMacroCli([
              command,
              input.path,
              missing.path,
              if (command == 'run-word-vba') output.path,
            ]),
          );
          expect(error['stepIndex'], 1);
          expect(error['tool'], 'docx.tableCellRangeText');
          expect(output.readAsBytesSync(), saved);
          expect(input.readAsBytesSync(), original);
        }
        for (final invalidStatement in [
          r'Mid$(label, 0, 1) = "X"',
          r'Mid$(ActiveDocument.Tables(1).Cell(1, 1).Range.Text, 1, 1) = "X"',
        ]) {
          final invalid = File('${directory.path}/invalid.bas')
            ..writeAsStringSync('''
Sub Main()
  Dim label As String
  label = "0000"
  ActiveDocument.Tables(1).Cell(1, 1).Range.Text = "Discard"
  $invalidStatement
End Sub
''');
          final compilation = _failure(
            await runOfficeMacroCli([
              'compile-word-vba',
              invalid.path,
              plan.path,
            ]),
          );
          expect(compilation['code'], startsWith('vba_'));
          expect(compilation['line'], 5);
          expect(compilation['column'], greaterThan(0));
          expect(plan.readAsBytesSync(), planBefore);
          final execution = _failure(
            await runOfficeMacroCli([
              'run-word-vba',
              input.path,
              invalid.path,
              output.path,
            ]),
          );
          expect(execution['code'], compilation['code']);
          expect(execution['line'], 5);
          expect(output.readAsBytesSync(), saved);
          expect(input.readAsBytesSync(), original);
        }
      },
      timeout: officeMacroCliTestTimeout,
    );
  }
}
