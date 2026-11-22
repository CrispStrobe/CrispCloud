import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_language_controls_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_language_controls.bas';
const _range = 'ActiveDocument.Paragraphs(1).Range';

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'actual BAS validates, records, replays and preserves native DOCM slots',
    () async {
      final result = await portable.runWordLanguageExample(
        File(_example).readAsStringSync(),
      );
      expect(result['operations'], 7);
      expect(result['revision'], 1);
      expect(result['recordedSteps'], 7);
      expect(result['additionalReopens'], 2);
      expect(result['opaqueVbaPreserved'], isTrue);
      expect(result['nativePartSha256'], hasLength(3));
    },
  );

  test(
    'late missing selector rolls back language, complex font and recording',
    () async {
      final input = portable.wordLanguageInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('No failed edits');
      final plan = portable.wordLanguagePlan('''
$_range.LanguageID = wdGerman
$_range.Font.NameBi = "Amiri"
ActiveDocument.Paragraphs(99).Range.LanguageIDOther = wdFrench
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(
            isA<OfficeMacroException>()
                .having((e) => e.stepIndex, 'step', 2)
                .having((e) => e.tool, 'tool', 'docx.runFormat'),
          ),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  for (final policy in [
    OfficeMacroPolicy(allowMutation: false),
    OfficeMacroPolicy(allowedTools: {'docx.paragraphFormat'}),
    OfficeMacroPolicy(maxSteps: 1),
  ]) {
    test(
      'language controls retain ordinary mutation policy: $policy',
      () async {
        final input = portable.wordLanguageInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
          policy: policy,
        );
        await expectLater(
          session.run(
            portable.wordLanguagePlan('''
$_range.LanguageID = wdGerman
$_range.Font.NameBi = "Amiri"
'''),
          ),
          throwsA(isA<OfficeMacroException>()),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      },
    );
  }

  for (final write in [
    'LanguageID = wdFrench',
    'LanguageIDOther = wdGerman',
    'Font.NameBi = "Amiri"',
  ]) {
    test(
      'empty paragraph refuses $write without setting insertion formatting',
      () async {
        final input = WordSerializer().writeBytes(WmlDocument.empty());
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await expectLater(
          session.run(portable.wordLanguagePlan('$_range.$write')),
          throwsA(isA<OfficeMacroException>()),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      },
    );
  }

  test('pre-cancelled language transaction cannot publish edits', () async {
    final input = portable.wordLanguageInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    await expectLater(
      session.run(
        portable.wordLanguageSource(File(_example).readAsStringSync()),
        cancellation: OfficeMacroCancellation()..cancel(),
      ),
      throwsA(
        isA<OfficeMacroException>().having((e) => e.code, 'code', 'cancelled'),
      ),
    );
    expect(session.bytes, input);
    expect(session.revision, 0);
  });

  test(
    'source language controls execute through existing MCP envelopes',
    () async {
      final input = portable.wordLanguageInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final adapter = OfficeMacroMcp(session);
      final compiled = await adapter.callTool('office_macro_compile', {
        'source': {
          'language': 'vba-word',
          'format': 'docx',
          'moduleName': 'WordLanguageControls',
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
      expect(_structured(executed)['completedSteps'], 7);
      final state = portable.wordLanguageState(session.bytes);
      expect((state.first['runs']! as List<Object?>).single, {
        'language': 'de-DE',
        'complexLanguage': 'ar-SA',
        'font': 'Latin Original',
        'csFont': 'Complex Original',
        'noProof': false,
      });
    },
  );

  test(
    'CLI compiles, validates, runs and atomically refuses a late failure',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'word-language-cli-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordLanguageInput());
      final original = input.readAsBytesSync();
      final source = File(_example).absolute.path;
      final compiledPath = '${directory.path}/plan.qudsmacro.json';
      final compiled = await runOfficeMacroCli([
        'compile-word-vba',
        source,
        compiledPath,
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      final plan = OfficeMacro.parse(File(compiledPath).readAsStringSync());
      expect(plan.steps, hasLength(7));
      expect(plan.steps.first.arguments['language'], 'de-DE');
      final validated = await runOfficeMacroCli([
        'validate-word-vba',
        input.path,
        source,
      ]);
      expect(
        validated.exitCode,
        0,
        reason: '${validated.stdout}\n${validated.stderr}',
      );
      expect(input.readAsBytesSync(), original);
      final output = File('${directory.path}/output.docm');
      final executed = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source,
        output.path,
      ]);
      expect(
        executed.exitCode,
        0,
        reason: '${executed.stdout}\n${executed.stderr}',
      );
      expect(input.readAsBytesSync(), original);
      final saved = output.readAsBytesSync();
      final state = portable.wordLanguageState(saved);
      expect((state.last['runs']! as List<Object?>).single, {
        'language': 'fr-FR',
        'complexLanguage': 'ar-SA',
        'font': 'Calibri',
        'csFont': 'Noto Naskh Arabic',
        'noProof': true,
      });
      final guard = (await WordPackagePreservation.capture(
        original,
        input.path,
      ))!;
      await guard.validateSaved(saved);
      final invalid = File('${directory.path}/late-failure.bas')
        ..writeAsStringSync('''
Sub Main()
  $_range.LanguageID = wdFrench
  ActiveDocument.Paragraphs(99).Range.Font.NameBi = "Amiri"
End Sub
''');
      final failed = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        invalid.path,
        output.path,
      ]);
      expect(failed.exitCode, isNot(0));
      expect(output.readAsBytesSync(), saved);
      expect(input.readAsBytesSync(), original);
    },
    timeout: officeMacroCliTestTimeout,
  );
}
