import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_table_navigation_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_table_navigation.bas';
const _first = 'ActiveDocument.Tables(1).Rows(1).Cells(1).Range';

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
      '$extension portable table navigation, preservation and MCP',
      () async {
        final result = await portable.runWordTableNavigationExample(
          File(_example).readAsStringSync(),
          macroEnabled: extension == 'docm',
        );
        expect(result['operations'], 10);
        expect(result['revision'], 1);
        expect(result['additionalReopens'], 2);
        expect(result['opaqueVbaPreserved'], extension == 'docm');
        for (final key in [
          'untouchedGeometryAndParts',
          'immutableValidation',
          'lateRollbackAndRecording',
          'mcpCompileValidateRun',
          'inactiveNamedArgumentRejected',
          'readOnlyPolicy',
        ]) {
          expect(result[key], isTrue, reason: key);
        }
      },
    );

    test(
      'CLI $extension compiles, validates, saves and refuses partial outputs',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'word-table-navigation-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final input = File('${directory.path}/input.$extension')
          ..writeAsBytesSync(
            portable.wordTableNavigationInput(
              macroEnabled: extension == 'docm',
            ),
          );
        final original = input.readAsBytesSync();
        final source = File(_example).absolute.path;
        final plan = File('${directory.path}/navigation.qudsmacro.json');
        final compiled = await runOfficeMacroCli([
          'compile-word-vba',
          source,
          plan.path,
        ]);
        expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
        expect(OfficeMacro.parse(plan.readAsStringSync()).steps, hasLength(10));
        final planBefore = plan.readAsBytesSync();
        final validated = await runOfficeMacroCli([
          'validate-word-vba',
          input.path,
          source,
        ]);
        expect(validated.exitCode, 0, reason: '${validated.stderr}');
        expect(_json(validated.stdout)['validatedOnly'], isTrue);
        expect(_json(validated.stdout)['completedSteps'], 10);
        expect(input.readAsBytesSync(), original);
        final output = File('${directory.path}/output.$extension');
        final executed = await runOfficeMacroCli([
          'run-word-vba',
          input.path,
          source,
          output.path,
        ]);
        expect(executed.exitCode, 0, reason: '${executed.stderr}');
        expect(_json(executed.stdout)['completedSteps'], 10);
        final saved = output.readAsBytesSync();
        portable.assertWordTableNavigationExample(saved);
        expect(
          portable.wordTableNavigationUntouched(saved),
          portable.wordTableNavigationUntouched(original),
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
          portable.wordTableNavigationState(replay.readAsBytesSync()),
          portable.wordTableNavigationState(saved),
        );
        for (final missing in [
          'ActiveDocument.Tables(2).Columns(1).Cells(2).Range',
          'ActiveDocument.Tables(2).Rows(1).Cells(2).Range',
        ]) {
          final invalid = File('${directory.path}/missing.bas')
            ..writeAsStringSync('''
Sub Main()
  $_first.Text = "Discard"
  $missing.Text = "Missing cell"
End Sub
''');
          for (final command in ['validate-word-vba', 'run-word-vba']) {
            final failed = await runOfficeMacroCli([
              command,
              input.path,
              invalid.path,
              if (command == 'run-word-vba') output.path,
            ]);
            final error = _failure(failed);
            expect(error['stepIndex'], 1);
            expect(error['tool'], 'docx.tableCellRangeText');
            expect(output.readAsBytesSync(), saved);
            expect(input.readAsBytesSync(), original);
          }
        }
        for (final selector in [
          'ActiveDocument.Tables(1).Rows(Row:=1).Cells(1)',
          'ActiveDocument.Tables(1).Cell(Row:=1, Row:=2)',
        ]) {
          final invalid = File('${directory.path}/malformed.bas')
            ..writeAsStringSync('''
Sub Main()
  $_first.Text = "Discard"
  $selector.Range.Text = "Invalid"
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
          expect(compilation['line'], 3);
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
          expect(execution['line'], 3);
          expect(output.readAsBytesSync(), saved);
          expect(input.readAsBytesSync(), original);
        }
      },
      timeout: officeMacroCliTestTimeout,
    );
  }
}
