import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_cell_text_controls_smoke.dart' as fixture;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_join_report.bas';
const _labels = [
  'Quds monthly report',
  'SKU-2026-042',
  'Prêt 😀',
  'Review / complete',
];

String _source() => File(_example).readAsStringSync();

String _appendToMain(String statement) {
  final source = _source();
  final end = source.lastIndexOf('End Sub');
  return '${source.substring(0, end)}$statement\n${source.substring(end)}';
}

void _assertReport(Uint8List bytes) {
  final cells = fixture.wordCellTextControlState(bytes);
  expect(cells, hasLength(5));
  expect(cells.take(4).map((cell) => cell['text']), _labels);
  const languages = ['en-US', 'en-US', 'fr-FR', 'en-US'];
  const highlights = <String?>[null, null, '00FF00', 'FFFF00'];
  for (var index = 0; index < 4; index++) {
    final runs = cells[index]['runs']! as List<Map<String, Object?>>;
    expect(runs, isNotEmpty);
    for (final run in runs) {
      expect(run['language'], languages[index]);
      expect(run['highlight'], highlights[index]);
      expect(run['noProof'], index == 1);
      expect(run['bold'], isTrue);
      expect(run['font'], 'Courier New');
      expect(run['size'], 24);
      expect(run['color'], '1F4E79');
    }
  }
}

void main() {
  registerOfficeMacroCliCleanup();

  for (final macroEnabled in [false, true]) {
    test(
      '${macroEnabled ? 'DOCM' : 'DOCX'} actual Join report previews, saves, reopens and replays',
      () async {
        final input = fixture.wordCellTextControlInput(
          macroEnabled: macroEnabled,
        );
        final untouched = fixture.wordCellTextControlUntouched(input);
        final plan = fixture.wordCellTextControlSource(_source());
        expect(plan.steps, hasLength(17));
        expect(
          plan.steps
              .where((step) => step.tool == 'docx.tableCellRangeText')
              .map((step) => step.arguments['text']),
          _labels,
        );
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        final preview = await session.validate(plan);
        expect(preview.validatedOnly, isTrue);
        expect(preview.completedSteps, 17);
        expect(session.bytes, input);
        expect(session.revision, 0);
        await session.run(OfficeMacro.parse(plan.encode()));
        expect(session.revision, 1);
        var saved = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          _assertReport(saved);
          expect(fixture.wordCellTextControlUntouched(saved), untouched);
          if (cycle < 2) {
            saved = WordSerializer().writeBytes(
              WordDeserializer().readBytes(saved),
            );
          }
        }
        final recorder = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        recorder.startRecording('Joined multilingual table');
        for (final step in plan.steps) {
          await recorder.callTool(step.tool, step.arguments);
        }
        final recorded = recorder.stopRecording();
        expect(recorded.steps, hasLength(17));
        final replay = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await replay.run(OfficeMacro.parse(recorded.encode()));
        expect(
          fixture.wordCellTextControlState(replay.bytes),
          fixture.wordCellTextControlState(saved),
        );
        expect(fixture.wordCellTextControlUntouched(replay.bytes), untouched);
      },
    );
  }

  test(
    'late missing cell rolls back the complete joined report and recording',
    () async {
      final input = fixture.wordCellTextControlInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = fixture.wordCellTextControlSource(
        _appendToMain(
          'ActiveDocument.Tables(99).Cell(1, 1).Range.HighlightColorIndex = wdYellow',
        ),
      );
      expect(plan.steps, hasLength(18));
      session.startRecording('Refused joined report');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(
            isA<OfficeMacroException>().having(
              (error) => error.stepIndex,
              'step',
              17,
            ),
          ),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  test(
    'MCP Join compilation failure cannot publish earlier source writes',
    () async {
      final input = fixture.wordCellTextControlInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Refused unallocated Join');
      final result = await OfficeMacroMcp(session)
          .callTool('office_macro_compile', {
            'source': {
              'language': 'vba-word',
              'format': 'docx',
              'moduleName': 'JoinedReport',
              'source': _appendToMain('''
Dim unallocated() As String
ActiveDocument.Tables(1).Cell(1, 1).Range.Text = Join(unallocated)
'''),
            },
          });
      expect(result['isError'], isTrue, reason: '$result');
      expect(session.bytes, input);
      expect(session.revision, 0);
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  test('CLI runs the actual Join report and preserves existing output after late failure', () async {
    final directory = Directory.systemTemp.createTempSync(
      'word-join-report-cli-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final input = File('${directory.path}/input.docm')
      ..writeAsBytesSync(fixture.wordCellTextControlInput());
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
    expect(
      OfficeMacro.parse(File(compiledPath).readAsStringSync()).steps,
      hasLength(17),
    );
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
    final saved = output.readAsBytesSync();
    _assertReport(saved);
    expect(
      fixture.wordCellTextControlUntouched(saved),
      fixture.wordCellTextControlUntouched(original),
    );
    final invalid = File('${directory.path}/late-failure.bas')
      ..writeAsStringSync(
        _appendToMain(
          'ActiveDocument.Tables(99).Cell(1, 1).Range.NoProofing = True',
        ),
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
  }, timeout: officeMacroCliTestTimeout);
}
