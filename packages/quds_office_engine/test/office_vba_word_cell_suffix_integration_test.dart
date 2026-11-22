import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_cell_suffix_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_table_suffix.bas';
const _cell = 'ActiveDocument.Tables(1).Cell(1, 1).Range';
const _tool = 'docx.tableCellRangeInsertAfter';

Map<String, Object?> _structured(Map<String, Object?> response) =>
    response['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _source(String text) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'CellSuffixIntegration',
    'source': text,
  },
};

void main() {
  registerOfficeMacroCliCleanup();

  for (final macroEnabled in [false, true]) {
    test(
      '${macroEnabled ? 'DOCM' : 'DOCX'} BAS preserves rich text, reopens, replays and rolls back',
      () async {
        final result = await portable.runWordCellSuffixExample(
          File(_example).readAsStringSync(),
          macroEnabled: macroEnabled,
        );
        expect(result['operations'], 6);
        expect(result['revision'], 1);
        expect(result['recordedSteps'], 6);
        expect(result['additionalReopens'], 2);
        expect(result['untouchedLayoutAndParts'], isTrue);
        expect(result['opaqueVbaPreserved'], macroEnabled);
        expect(result['lateRollback'], isTrue);
      },
    );
  }

  test('the actual BAS emits ordered direct cell suffixes', () {
    final macro = portable.wordCellSuffixSource(
      File(_example).readAsStringSync(),
    );
    expect(macro.steps.map((step) => step.tool), [
      _tool,
      _tool,
      _tool,
      'docx.runFormat',
      _tool,
      _tool,
    ]);
    expect(macro.steps.map((step) => step.arguments), [
      {'table': 0, 'row': 0, 'column': 0, 'text': '\tReady'},
      {'table': 0, 'row': 0, 'column': 1, 'text': '\tPeer'},
      {'table': 0, 'row': 0, 'column': 0, 'text': '\tReviewed'},
      {
        'paragraph': 0,
        'story': 'tableCell',
        'table': 0,
        'row': 0,
        'column': 0,
        'bold': true,
      },
      {'table': 0, 'row': 0, 'column': 1, 'text': '\tOwner'},
      {'table': 0, 'row': 1, 'column': 0, 'text': 'New\tReady'},
    ]);
  });

  test(
    'repeated runs suffix current text and keep neighboring cells',
    () async {
      final input = portable.wordCellSuffixInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordCellSuffixPlan('''
$_cell.InsertAfter Text:="first: "
$_cell.InsertAfter Text:="second: "
''');
      await session.run(plan);
      await session.run(plan);
      final state = portable.wordCellSuffixState(session.bytes);
      expect(state.first['text'], 'first 0/0first: second: first: second: ');
      expect(state.skip(1), portable.wordCellSuffixState(input).skip(1));
      expect(session.revision, 2);
      expect(
        portable.wordCellSuffixUntouched(session.bytes),
        portable.wordCellSuffixUntouched(input),
      );
    },
  );

  for (final (name, policy) in <(String, OfficeMacroPolicy)>[
    ('read-only host', OfficeMacroPolicy(allowMutation: false)),
    ('tool allowlist', OfficeMacroPolicy(allowedTools: {'docx.runFormat'})),
    ('step limit', OfficeMacroPolicy(maxSteps: 5)),
  ]) {
    test('$name refuses the BAS without publication or recording', () async {
      final input = portable.wordCellSuffixInput();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      if (policy.allowMutation) {
        session.startRecording('Denied suffixes');
      } else {
        expect(
          () => session.startRecording('Denied suffixes'),
          throwsA(
            isA<OfficeMacroException>().having(
              (error) => error.code,
              'code',
              'permission_denied',
            ),
          ),
        );
      }
      await expectLater(
        session.run(
          portable.wordCellSuffixSource(File(_example).readAsStringSync()),
        ),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
      if (policy.allowMutation) {
        expect(session.stopRecording().steps, isEmpty);
      } else {
        expect(session.isRecording, isFalse);
      }
    });
  }

  test('a cancelled BAS cannot publish a suffix or recording', () async {
    final input = portable.wordCellSuffixInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx)
      ..startRecording('Cancelled suffixes');
    await expectLater(
      session.run(
        portable.wordCellSuffixSource(File(_example).readAsStringSync()),
        cancellation: OfficeMacroCancellation()..cancel(),
      ),
      throwsA(isA<OfficeMacroException>()),
    );
    expect(session.bytes, input);
    expect(session.revision, 0);
    expect(session.stopRecording().steps, isEmpty);
  });

  test(
    'MCP advertises the scoped tool and honors its capability policy',
    () async {
      final input = portable.wordCellSuffixInput();
      final allowed = OfficeMacroMcp(
        OfficeMacroSession(input, format: OfficeMacroFormat.docx),
      );
      final tools = allowed.listTools()['tools']! as List<Map<String, Object?>>;
      final suffix = tools.singleWhere((tool) => tool['name'] == _tool);
      final schema = suffix['inputSchema']! as Map<String, Object?>;
      expect((schema['properties']! as Map<String, Object?>).keys, [
        'table',
        'row',
        'column',
        'text',
      ]);
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: OfficeMacroPolicy(allowedTools: {'docx.runFormat'}),
      );
      final denied = OfficeMacroMcp(session);
      final visible =
          denied.listTools()['tools']! as List<Map<String, Object?>>;
      expect(visible.any((tool) => tool['name'] == _tool), isFalse);
      await expectLater(
        denied.callTool(_tool, {
          'table': 0,
          'row': 0,
          'column': 0,
          'text': 'Denied: ',
        }),
        throwsA(
          isA<OfficeMacroMcpProtocolException>().having(
            (error) => error.code,
            'code',
            -32602,
          ),
        ),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test('MCP compiles, previews and runs the actual BAS', () async {
    final input = portable.wordCellSuffixInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    final adapter = OfficeMacroMcp(session);
    final compiled = await adapter.callTool(
      'office_macro_compile',
      _source(File(_example).readAsStringSync()),
    );
    expect(compiled['isError'], isFalse, reason: '$compiled');
    final arguments = <String, Object?>{
      'macro': _structured(compiled)['macro'],
    };
    final preview = await adapter.callTool('office_macro_validate', arguments);
    expect(preview['isError'], isFalse, reason: '$preview');
    expect(_structured(preview)['validatedOnly'], isTrue);
    expect(_structured(preview)['completedSteps'], 6);
    expect(session.bytes, input);
    expect(session.revision, 0);
    final executed = await adapter.callTool('office_macro_run', arguments);
    expect(executed['isError'], isFalse, reason: '$executed');
    expect(_structured(executed)['completedSteps'], 6);
    expect(session.revision, 1);
    portable.assertWordCellSuffixExample(session.bytes);
    expect(
      portable.wordCellSuffixUntouched(session.bytes),
      portable.wordCellSuffixUntouched(input),
    );
  });

  test('MCP late invalid cell keeps the earlier saved revision', () async {
    final session = OfficeMacroSession(
      portable.wordCellSuffixInput(),
      format: OfficeMacroFormat.docx,
    );
    await session.run(
      portable.wordCellSuffixPlan('$_cell.InsertAfter Text:="Saved: "'),
    );
    final saved = session.bytes;
    final adapter = OfficeMacroMcp(session);
    final compiled = await adapter.callTool(
      'office_macro_compile',
      _source('''
Sub Main()
  $_cell.InsertAfter Text:="Discard: "
  ActiveDocument.Tables(2).Cell(2, 1).Range.InsertAfter Text:="Missing: "
End Sub
'''),
    );
    expect(compiled['isError'], isFalse, reason: '$compiled');
    for (final tool in ['office_macro_validate', 'office_macro_run']) {
      final failed = await adapter.callTool(tool, {
        'macro': _structured(compiled)['macro'],
      });
      expect(failed['isError'], isTrue);
      final error = _structured(failed)['error']! as Map<String, Object?>;
      expect(error['stepIndex'], 1);
      expect(error['tool'], _tool);
      expect(session.bytes, saved);
      expect(session.revision, 1);
    }
  });

  test('MCP unknown named argument rejects the complete source', () async {
    final input = portable.wordCellSuffixInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    final response = await OfficeMacroMcp(session).callTool(
      'office_macro_compile',
      _source('''
Sub Main()
  $_cell.InsertAfter Text:="Discard: "
  If False Then
    $_cell.InsertAfter Value:="unknown"
  End If
End Sub
'''),
    );
    expect(response['isError'], isTrue);
    expect(_structured(response).containsKey('macro'), isFalse);
    final error = _structured(response)['error']! as Map<String, Object?>;
    expect(error['code'], 'vba_name_error');
    expect(error['moduleName'], 'CellSuffixIntegration');
    expect(error['line'], 4);
    expect(session.bytes, input);
    expect(session.revision, 0);
  });

  for (final extension in ['docx', 'docm']) {
    test(
      'CLI $extension compiles, previews, executes and preserves failed outputs',
      () async {
        final directory = Directory.systemTemp.createTempSync('cell-suffix-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final input = File('${directory.path}/input.$extension')
          ..writeAsBytesSync(
            portable.wordCellSuffixInput(macroEnabled: extension == 'docm'),
          );
        final original = input.readAsBytesSync();
        final source = File(_example).absolute.path;
        final planFile = File('${directory.path}/suffix.qudsmacro.json');
        final compiled = await runOfficeMacroCli([
          'compile-word-vba',
          source,
          planFile.path,
        ]);
        expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
        expect(
          OfficeMacro.parse(planFile.readAsStringSync()).steps,
          hasLength(6),
        );
        final validated = await runOfficeMacroCli([
          'validate-word-vba',
          input.path,
          source,
        ]);
        expect(validated.exitCode, 0, reason: '${validated.stderr}');
        expect(input.readAsBytesSync(), original);
        final output = File('${directory.path}/output.$extension');
        final executed = await runOfficeMacroCli([
          'run-word-vba',
          input.path,
          source,
          output.path,
        ]);
        expect(executed.exitCode, 0, reason: '${executed.stderr}');
        final saved = output.readAsBytesSync();
        portable.assertWordCellSuffixExample(saved);
        expect(
          portable.wordCellSuffixUntouched(saved),
          portable.wordCellSuffixUntouched(original),
        );
        final guard = (await WordPackagePreservation.capture(
          original,
          input.path,
        ))!;
        await guard.validateSaved(saved);
        for (final failing in [
          'ActiveDocument.Tables(2).Cell(2, 1).Range.InsertAfter Text:="Missing: "',
          '$_cell.InsertAfter Value:="unknown"',
        ]) {
          final invalid = File('${directory.path}/invalid.bas')
            ..writeAsStringSync(
              'Sub Main()\n$_cell.InsertAfter Text:="Discard: "\n$failing\nEnd Sub',
            );
          final failed = await runOfficeMacroCli([
            'run-word-vba',
            input.path,
            invalid.path,
            output.path,
          ]);
          expect(failed.exitCode, isNot(0));
          expect(output.readAsBytesSync(), saved);
          expect(input.readAsBytesSync(), original);
        }
      },
      timeout: officeMacroCliTestTimeout,
    );
  }
}
