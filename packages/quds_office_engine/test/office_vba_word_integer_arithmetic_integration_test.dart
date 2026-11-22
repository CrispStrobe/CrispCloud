import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_cell_suffix_smoke.dart' as fixture;
import '../tool/macros/web_vba_word_integer_arithmetic_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_grouped_report.bas';

void main() {
  registerOfficeMacroCliCleanup();

  for (final macroEnabled in [false, true]) {
    test(
      '${macroEnabled ? 'DOCM' : 'DOCX'} grouped BAS previews, saves, reopens, replays and rolls back',
      () async {
        final result = await portable.runGroupedReport(
          File(_example).readAsStringSync(),
          macroEnabled: macroEnabled,
        );
        expect(result['operations'], 12);
        expect(result['revision'], 1);
        expect(result['recordedSteps'], 12);
        expect(result['additionalReopens'], 2);
        expect(result['untouchedLayoutAndParts'], isTrue);
        expect(result['opaqueVbaPreserved'], macroEnabled);
        expect(result['lateRollback'], isTrue);
      },
    );
  }

  test('grouped preservation excludes exactly four selected cells', () async {
    final input = fixture.wordCellSuffixInput();
    final untouched = fixture.wordCellSuffixUntouched(
      input,
      selectedCellCount: 4,
    );
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    await session.run(
      portable.groupedReportSource(File(_example).readAsStringSync()),
    );
    expect(
      fixture.wordCellSuffixUntouched(session.bytes, selectedCellCount: 4),
      untouched,
    );
    expect(
      fixture.wordCellSuffixUntouched(session.bytes),
      isNot(fixture.wordCellSuffixUntouched(input)),
      reason: 'The suffix default must still protect the fourth cell',
    );
    await session.callTool('docx.tableCellRangeText', {
      'table': 1,
      'row': 0,
      'column': 0,
      'text': 'Unexpected neighboring table edit',
    });
    expect(
      fixture.wordCellSuffixUntouched(session.bytes, selectedCellCount: 4),
      isNot(untouched),
      reason: 'The grouped report must still protect the fifth cell',
    );
  });

  for (final change in ['paragraph properties', 'table geometry']) {
    test('grouped preservation detects selected-cell $change changes', () {
      final input = fixture.wordCellSuffixInput();
      final document = WordDeserializer().readBytes(input);
      final table = document.sections.first.blocks.whereType<WmlTable>().first;
      if (change == 'paragraph properties') {
        final paragraph =
            table.rows.first.cells.first.blocks.single as WmlParagraph;
        paragraph.properties.spacingAfter = 9;
      } else {
        table.grid[0] += 1;
      }
      expect(
        fixture.wordCellSuffixUntouched(
          WordSerializer().writeBytes(document),
          selectedCellCount: 4,
        ),
        isNot(fixture.wordCellSuffixUntouched(input, selectedCellCount: 4)),
      );
    });
  }

  for (final partUri in ['/customXml/table.xml', '/word/vbaProject.bin']) {
    test('grouped preservation detects opaque $partUri changes', () {
      final input = fixture.wordCellSuffixInput();
      final package = OpcPackage.openBytes(input);
      final part = package.getPart(partUri)!;
      final changed = part.readBytes();
      changed[0] ^= 1;
      part.writeBytes(changed);
      expect(
        fixture.wordCellSuffixUntouched(package.save(), selectedCellCount: 4),
        isNot(fixture.wordCellSuffixUntouched(input, selectedCellCount: 4)),
      );
    });
  }

  test(
    'grouping expressions preserve row/column order and Boolean formatting',
    () {
      final plan = portable.groupedReportSource(
        File(_example).readAsStringSync(),
      );
      for (var index = 0; index < 4; index++) {
        final writes = plan.steps.skip(index * 3).take(3).toList();
        expect(writes.map((step) => step.tool), [
          'docx.tableCellRangeText',
          'docx.tableCellRangeInsertAfter',
          'docx.runFormat',
        ]);
        for (final step in writes) {
          expect(step.arguments['table'], 0);
          expect(step.arguments['row'], index ~/ 2);
          expect(step.arguments['column'], index % 2);
        }
        expect(writes[2].arguments['bold'], index.isEven);
      }
    },
  );

  for (final expression in [r'1 \ 0', '10 Mod 0.5', r'-2147483648 \ -1']) {
    test(
      'MCP refuses $expression before earlier source writes can publish',
      () async {
        final input = fixture.wordCellSuffixInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        )..startRecording('Refused arithmetic');
        final source = portable.appendGroupedReportStatement(
          File(_example).readAsStringSync(),
          'ActiveDocument.Tables(1).Cell(1, 1).Range.Text = CStr($expression)',
        );
        final result = await OfficeMacroMcp(session).callTool(
          'office_macro_compile',
          {
            'source': {
              'language': 'vba-word',
              'format': 'docx',
              'moduleName': 'GroupedReport',
              'source': source,
            },
          },
        );
        expect(result['isError'], isTrue, reason: '$result');
        expect(session.bytes, input);
        expect(session.revision, 0);
        expect(session.stopRecording().steps, isEmpty);
      },
    );
  }

  for (final (name, policy) in [
    ('read-only host', OfficeMacroPolicy(allowMutation: false)),
    (
      'tool allowlist',
      OfficeMacroPolicy(allowedTools: {'docx.tableCellRangeText'}),
    ),
    ('step budget', OfficeMacroPolicy(maxSteps: 11)),
  ]) {
    test('grouped report honors $name', () async {
      final input = fixture.wordCellSuffixInput();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      await expectLater(
        session.run(
          portable.groupedReportSource(File(_example).readAsStringSync()),
        ),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    });
  }

  test(
    'CLI runs actual grouped BAS and protects existing output on arithmetic failure',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'word-grouped-report-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(fixture.wordCellSuffixInput());
      final source = File(_example).absolute.path;
      final plan = File('${directory.path}/plan.json');
      final output = File('${directory.path}/output.docm');
      for (final arguments in [
        ['compile-word-vba', source, plan.path],
        ['validate-word-vba', input.path, source],
        ['run-word-vba', input.path, source, output.path],
      ]) {
        final result = await runOfficeMacroCli(arguments);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }
      expect(OfficeMacro.parse(plan.readAsStringSync()).steps, hasLength(12));
      final saved = output.readAsBytesSync();
      expect(
        fixture.wordCellSuffixState(saved).map((cell) => cell['text']),
        portable.groupedReportText,
      );
      final invalid = File('${directory.path}/invalid.bas')
        ..writeAsStringSync(
          portable.appendGroupedReportStatement(
            File(_example).readAsStringSync(),
            r'ActiveDocument.Tables(1).Cell(1, 1).Range.Text = CStr(1 \ 0)',
          ),
        );
      final result = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        invalid.path,
        output.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(output.readAsBytesSync(), saved);
    },
  );
}
