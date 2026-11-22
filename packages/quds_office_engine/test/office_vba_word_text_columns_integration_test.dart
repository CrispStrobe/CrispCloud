import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_page_setup_smoke.dart' as fixture;
import '../tool/macros/web_vba_word_text_columns_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_text_columns.bas';
const _first = 'ActiveDocument.Sections(1).PageSetup.TextColumns';
const _second = 'ActiveDocument.Sections(2).PageSetup.TextColumns';

Matcher _failure({required int step}) => isA<OfficeMacroException>()
    .having((error) => error.code, 'code', 'operation_failed')
    .having((error) => error.stepIndex, 'step', step)
    .having((error) => error.tool, 'tool', 'docx.textColumns');

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _sourceArguments(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'TextColumnsIntegration',
    'source': source,
  },
};

void main() {
  registerOfficeMacroCliCleanup();

  test('committed BAS preserves selected sections, DOCM and reopens', () async {
    final result = await portable.runWordTextColumnsExample(
      File(_example).readAsStringSync(),
    );
    expect(result['operations'], 6);
    expect(result['firstRunRevision'], 1);
    expect(result['repeatedRevision'], 2);
    expect(result['additionalReopens'], 2);
    expect(result['opaquePayloadsPreserved'], isTrue);
  });

  test(
    'ByVal TextColumns rebinding leaves the caller selector intact',
    () async {
      final input = portable.wordTextColumnsInput();
      final original = fixture.wordPageSetupState(input);
      final plan = portable.wordTextColumnsSource('''
Sub Change(ByVal target As TextColumns)
  target.Spacing = 12.05
  Set target = Application.ActiveDocument.Sections(2).PageSetup.TextColumns
  target.LineBetween = True
End Sub
Sub Main()
  Dim columns As TextColumns
  Set columns = ThisDocument.Sections.Item(1).PageSetup.TextColumns
  Change target:=columns
  Call columns.SetCount(NumColumns:=3)
End Sub
''');
      expect(plan.steps.map((step) => step.arguments['section']), [0, 1, 0]);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.validate(plan);
      expect(session.bytes, input);
      await session.run(plan);
      expect(fixture.wordPageSetupState(session.bytes), [
        {...original[0], 'columnSpace': 12.05, 'columnCount': 3},
        {...original[1], 'columnSep': true},
        original[2],
      ]);
      final reopened = WordSerializer().writeBytes(
        WordDeserializer().readBytes(session.bytes),
      );
      expect(
        fixture.wordPageSetupState(reopened),
        fixture.wordPageSetupState(session.bytes),
      );
      fixture.assertWordPageSetupPackage(reopened);
      expect(session.revision, 1);
    },
  );

  test(
    'column geometry observes earlier setters in the same transaction',
    () async {
      final input = portable.wordTextColumnsInput();
      // 30 columns fit after removing the gap; the imported 12pt gap leaves
      // less than the native minimum width when the setters are reversed.
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final valid = portable.wordTextColumnsPlan('''
$_first.Spacing = 0
$_first.SetCount 30
''');
      await session.validate(valid);
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(valid);
      final state = fixture.wordPageSetupState(session.bytes);
      expect(state.first['columnCount'], 30);
      expect(state.first['columnSpace'], 0);
      expect(state.skip(1), fixture.wordPageSetupState(input).skip(1));
      final reversed = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
      );
      final invalid = portable.wordTextColumnsPlan('''
$_first.SetCount 30
$_first.Spacing = 0
''');
      for (final action in [reversed.validate, reversed.run]) {
        await expectLater(action(invalid), throwsA(_failure(step: 0)));
        expect(reversed.bytes, input);
        expect(reversed.revision, 0);
      }
    },
  );

  test(
    'later gap failure discards earlier count and separator setters',
    () async {
      final input = portable.wordTextColumnsInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordTextColumnsPlan('''
$_first.SetCount 3
$_second.LineBetween = True
$_first.Spacing = 468
''');
      session.startRecording('Rejected column geometry');
      for (final action in [session.validate, session.run]) {
        await expectLater(action(plan), throwsA(_failure(step: 2)));
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  test(
    'missing later section rolls back dry-run, execution and recording',
    () async {
      final result = await portable.runWordTextColumnsRollback();
      expect(result['failedStep'], 1);
      expect(result['validateAndRunRollback'], isTrue);
    },
  );

  test(
    'a custom-column refusal retains an earlier accepted revision',
    () async {
      final session = OfficeMacroSession(
        portable.wordTextColumnsInput(),
        format: OfficeMacroFormat.docx,
      );
      session.startRecording('Earlier accepted column change');
      await session.callTool('docx.textColumns', {'section': 0, 'spacing': 18});
      final before = session.bytes;
      final plan = portable.wordTextColumnsPlan('''
$_second.SetCount 2
ActiveDocument.Sections(3).PageSetup.TextColumns.SetCount 2
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(action(plan), throwsA(_failure(step: 1)));
        expect(session.bytes, before);
        expect(session.revision, 1);
      }
      final recording = session.stopRecording();
      expect(recording.steps, hasLength(1));
      expect(recording.steps.single.arguments, {'section': 0, 'spacing': 18});
    },
  );

  test('permissions and native step budgets apply before publishing', () async {
    final result = await portable.runWordTextColumnsPolicy();
    expect(result['atomicDenials'], 6);
    expect(result['allowedSteps'], 3);
  });

  test(
    'recorded native edits replay while failed calls are excluded',
    () async {
      final result = await portable.runWordTextColumnsRecording();
      expect(result['recordedSteps'], 3);
      expect(result['failedCallExcluded'], isTrue);
      expect(result['replayRevision'], 1);
    },
  );

  test('MCP compiles, validates and runs the committed BAS', () async {
    final input = portable.wordTextColumnsInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    final adapter = OfficeMacroMcp(session);
    final compiled = await adapter.callTool(
      'office_macro_compile',
      _sourceArguments(File(_example).readAsStringSync()),
    );
    expect(compiled['isError'], isFalse, reason: '$compiled');
    final arguments = <String, Object?>{
      'macro': _structured(compiled)['macro'],
    };
    final validation = await adapter.callTool(
      'office_macro_validate',
      arguments,
    );
    expect(validation['isError'], isFalse, reason: '$validation');
    expect(_structured(validation)['completedSteps'], 6);
    expect(_structured(validation)['validatedOnly'], isTrue);
    expect(session.bytes, input);
    expect(session.revision, 0);
    final run = await adapter.callTool('office_macro_run', arguments);
    expect(run['isError'], isFalse, reason: '$run');
    expect(_structured(run)['completedSteps'], 6);
    expect(session.revision, 1);
    portable.assertWordTextColumnsExample(session.bytes);
  });

  test('MCP unsupported column Add publishes no prefix plan', () async {
    final input = portable.wordTextColumnsInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    final result = await OfficeMacroMcp(session).callTool(
      'office_macro_compile',
      _sourceArguments('''
Sub Main()
  $_first.SetCount 2
  $_first.Add Width:=100, Spacing:=18
End Sub
'''),
    );
    expect(result['isError'], isTrue);
    expect(_structured(result).containsKey('macro'), isFalse);
    final error = _structured(result)['error']! as Map<String, Object?>;
    expect(error['moduleName'], 'TextColumnsIntegration');
    expect(error['line'], greaterThan(0));
    expect(session.bytes, input);
    expect(session.revision, 0);
  });

  test(
    'CLI runs the actual BAS and preserves its DOCM input and opaque payloads',
    () async {
      final directory = Directory.systemTemp.createTempSync('quds-columns-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordTextColumnsInput());
      final before = input.readAsBytesSync();
      final output = File('${directory.path}/output.docm');
      final result = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        File(_example).absolute.path,
        output.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final report =
          jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(report['language'], 'vba-word');
      expect(input.readAsBytesSync(), before);
      final saved = output.readAsBytesSync();
      final guard = (await WordPackagePreservation.capture(
        before,
        input.path,
      ))!;
      await guard.validateSaved(saved);
      portable.assertWordTextColumnsExample(saved);
    },
    timeout: officeMacroCliTestTimeout,
  );

  test(
    'CLI late invalid geometry leaves input untouched and creates no output',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'quds-columns-fail-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordTextColumnsInput());
      final before = input.readAsBytesSync();
      final source = File('${directory.path}/invalid.bas')
        ..writeAsStringSync('''
Sub Main()
  $_first.SetCount 3
  $_first.Spacing = 468
End Sub
''');
      final output = File('${directory.path}/output.docm');
      final result = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source.path,
        output.path,
      ]);
      expect(result.exitCode, isNot(0));
      final report =
          jsonDecode(result.stderr as String) as Map<String, Object?>;
      final error = report['error']! as Map<String, Object?>;
      expect(error['code'], 'operation_failed');
      expect(error['stepIndex'], 1);
      expect(error['tool'], 'docx.textColumns');
      expect(input.readAsBytesSync(), before);
      expect(output.existsSync(), isFalse);
    },
    timeout: officeMacroCliTestTimeout,
  );
}
