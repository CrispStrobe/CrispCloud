import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_text_selectors_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_text_selectors.bas';

Map<String, Object?> _json(Object? value) =>
    jsonDecode(value! as String) as Map<String, Object?>;

Map<String, Object?> _failure(ProcessResult result) {
  expect(
    result.exitCode,
    1,
    reason: result.stdout.toString() + result.stderr.toString(),
  );
  return _json(result.stderr)['error']! as Map<String, Object?>;
}

void main() {
  registerOfficeMacroCliCleanup();
  test(
    'actual BAS CLI compile/validate/run/replay and failure output preservation',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'word-text-selectors-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final root = directory.path;
      final input = File('$root/input.docm')
        ..writeAsBytesSync(portable.wordTextSelectorsInput());
      final original = input.readAsBytesSync();
      final source = File(_example).absolute.path;
      final plan = File('$root/labels.qudsmacro.json');
      final compiled = await runOfficeMacroCli([
        'compile-word-vba',
        source,
        plan.path,
      ]);
      expect(compiled.exitCode, 0, reason: compiled.stderr.toString());
      portable.assertWordTextSelectorsPlan(
        OfficeMacro.parse(plan.readAsStringSync()),
      );
      final originalPlan = plan.readAsBytesSync();

      final validated = await runOfficeMacroCli([
        'validate-word-vba',
        input.path,
        source,
      ]);
      expect(validated.exitCode, 0, reason: validated.stderr.toString());
      expect(_json(validated.stdout)['validatedOnly'], isTrue);
      expect(_json(validated.stdout)['completedSteps'], 5);
      expect(input.readAsBytesSync(), original);

      final output = File('$root/output.docm');
      final executed = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source,
        output.path,
      ]);
      expect(executed.exitCode, 0, reason: executed.stderr.toString());
      expect(_json(executed.stdout)['completedSteps'], 5);
      final saved = output.readAsBytesSync();
      portable.assertWordTextSelectorsExample(saved);
      final guard = (await WordPackagePreservation.capture(
        original,
        input.path,
      ))!;
      await guard.validateSaved(saved);

      final replay = File('$root/replay.docm');
      final replayed = await runOfficeMacroCli([
        'run',
        input.path,
        plan.path,
        replay.path,
      ]);
      expect(replayed.exitCode, 0, reason: replayed.stderr.toString());
      expect(
        portable.wordTextSelectorsState(replay.readAsBytesSync()),
        portable.wordTextSelectorsState(saved),
      );

      final missing = File('$root/missing.bas')
        ..writeAsStringSync('''
Sub Main()
  ActiveDocument.Paragraphs(Index:=1).Range.InsertBefore Left("Discard", 3)
  ActiveDocument.Sections(Index:=2).Footers(Index:=3).Range.Paragraphs(Index:=99).Range.InsertBefore "Missing"
End Sub
''');
      for (final command in ['validate-word-vba', 'run-word-vba']) {
        final failure = _failure(
          await runOfficeMacroCli([
            command,
            input.path,
            missing.path,
            if (command == 'run-word-vba') output.path,
          ]),
        );
        expect(failure['stepIndex'], 1);
        expect(failure['tool'], 'docx.replaceText');
        expect(output.readAsBytesSync(), saved);
        expect(input.readAsBytesSync(), original);
      }

      final malformed = File('$root/malformed.bas')
        ..writeAsStringSync('''
Sub Main()
  ActiveDocument.Paragraphs(Index:=1).Range.InsertBefore "Discard"
  ActiveDocument.Sections(Number:=2).Headers(Index:=1).Range.Paragraphs(Index:=1).Range.InsertBefore "Invalid"
End Sub
''');
      final compileFailure = _failure(
        await runOfficeMacroCli([
          'compile-word-vba',
          malformed.path,
          plan.path,
        ]),
      );
      expect(compileFailure['code'], 'vba_name_error');
      expect(compileFailure['line'], 3);
      expect(plan.readAsBytesSync(), originalPlan);
      final runFailure = _failure(
        await runOfficeMacroCli([
          'run-word-vba',
          input.path,
          malformed.path,
          output.path,
        ]),
      );
      expect(runFailure['code'], 'vba_name_error');
      expect(runFailure['line'], 3);
      expect(output.readAsBytesSync(), saved);
      expect(input.readAsBytesSync(), original);
    },
    timeout: officeMacroCliTestTimeout,
  );
}
