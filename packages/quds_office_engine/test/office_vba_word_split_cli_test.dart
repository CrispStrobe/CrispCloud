import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_split_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

Map<String, Object?> _json(Object? value) =>
    jsonDecode(value! as String) as Map<String, Object?>;

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'Split BAS CLI compile, validate, run and replay preserve outputs on failure',
    () async {
      final directory = Directory.systemTemp.createTempSync('word-split-cli-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordSplitInput());
      final original = input.readAsBytesSync();
      final source = File('example/macros/word_split_report.bas').absolute.path;
      final plan = File('${directory.path}/report.qudsmacro.json');
      final compilation = await runOfficeMacroCli([
        'compile-word-vba',
        source,
        plan.path,
      ]);
      expect(compilation.exitCode, 0, reason: compilation.stderr.toString());
      portable.assertWordSplitPlan(OfficeMacro.parse(plan.readAsStringSync()));
      final compiledBytes = plan.readAsBytesSync();

      final validation = await runOfficeMacroCli([
        'validate-word-vba',
        input.path,
        source,
      ]);
      expect(validation.exitCode, 0, reason: validation.stderr.toString());
      expect(_json(validation.stdout)['validatedOnly'], isTrue);
      expect(_json(validation.stdout)['completedSteps'], 7);
      expect(input.readAsBytesSync(), original);

      final output = File('${directory.path}/output.docm');
      final execution = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source,
        output.path,
      ]);
      expect(execution.exitCode, 0, reason: execution.stderr.toString());
      expect(_json(execution.stdout)['completedSteps'], 7);
      final saved = output.readAsBytesSync();
      portable.assertWordSplitOutput(saved, original);
      final guard = (await WordPackagePreservation.capture(
        original,
        input.path,
      ))!;
      await guard.validateSaved(saved);

      final replay = File('${directory.path}/replay.docm');
      final replayed = await runOfficeMacroCli([
        'run',
        input.path,
        plan.path,
        replay.path,
      ]);
      expect(replayed.exitCode, 0, reason: replayed.stderr.toString());
      portable.assertWordSplitOutput(replay.readAsBytesSync(), original);

      final missing = File('${directory.path}/missing.bas')
        ..writeAsStringSync('''
Sub Main()
  Dim values() As String
  values = Split("discard|missing", "|")
  ActiveDocument.Tables(1).Cell(1, 1).Range.Text = values(0)
  ActiveDocument.Tables(1).Cell(3, 1).Range.Text = values(1)
End Sub
''');
      for (final command in ['validate-word-vba', 'run-word-vba']) {
        final result = await runOfficeMacroCli([
          command,
          input.path,
          missing.path,
          if (command == 'run-word-vba') output.path,
        ]);
        expect(
          result.exitCode,
          1,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final error = _json(result.stderr)['error']! as Map<String, Object?>;
        expect(error['stepIndex'], 1);
        expect(error['tool'], 'docx.tableCellRangeText');
        expect(output.readAsBytesSync(), saved);
        expect(input.readAsBytesSync(), original);
      }

      final malformed = File('${directory.path}/malformed.bas')
        ..writeAsStringSync('''
Sub Main()
  Dim values() As String
  ActiveDocument.Tables(1).Cell(1, 1).Range.Text = "discard"
  values = Split(Null, "|")
End Sub
''');
      for (final command in ['compile-word-vba', 'run-word-vba']) {
        final result = await runOfficeMacroCli(
          command == 'compile-word-vba'
              ? [command, malformed.path, plan.path]
              : [command, input.path, malformed.path, output.path],
        );
        expect(
          result.exitCode,
          1,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final error = _json(result.stderr)['error']! as Map<String, Object?>;
        expect(error['code'], 'vba_invalid_use_of_null');
        expect(error['line'], 4);
        expect(plan.readAsBytesSync(), compiledBytes);
        expect(output.readAsBytesSync(), saved);
        expect(input.readAsBytesSync(), original);
      }
    },
    timeout: officeMacroCliTestTimeout,
  );
}
