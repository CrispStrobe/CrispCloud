import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_table_cells_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_table_report.bas';
const _cell = 'ActiveDocument.Tables(1).Cell(1, 1).Range';

Map<String, Object?> _structured(Map<String, Object?> value) =>
    value['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _sourceArguments(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'WordTableReport',
    'source': source,
  },
};

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'actual BAS preserves DOCM structure, formatting and transactions',
    () async {
      final result = await portable.runWordTableExample(
        File(_example).readAsStringSync(),
      );
      expect(result['operations'], 5);
      expect(result['revision'], 2);
      expect(result['recordedSteps'], 5);
      expect(result['additionalReopens'], 2);
      expect(result['opaquePartsPreserved'], isTrue);
      expect(result['formattingPreserved'], isTrue);
      expect(result['lateRollback'], isTrue);
      expect(result['policyRefusals'], 3);
      expect(result['text'], [
        'Item',
        'Quds report',
        'Total',
        '42',
        'Prepared ✓',
      ]);
    },
  );

  test(
    'the same table BAS runs on DOCX without creating a VBA project',
    () async {
      final input = portable.wordTableInput(macroEnabled: false);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordTableSource(File(_example).readAsStringSync());
      final validation = await session.validate(plan);
      expect(validation.validatedOnly, isTrue);
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      portable.assertWordTableOutput(session.bytes, macroEnabled: false);
      final reopened = WordSerializer().writeBytes(
        WordDeserializer().readBytes(session.bytes),
      );
      portable.assertWordTableOutput(reopened, macroEnabled: false);
    },
  );

  test(
    'empty replacement, tabs and supplementary Unicode survive reopening',
    () async {
      final session = OfficeMacroSession(
        portable.wordTableInput(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(portable.wordTablePlan('$_cell.Text = ""'));
      expect(portable.wordTableText(session.bytes).first, '');
      await session.run(
        portable.wordTablePlan('$_cell.Text = "A" & ChrW(9) & "😀 & <B>"'),
      );
      expect(portable.wordTableText(session.bytes).first, 'A\t😀 & <B>');
      final reopened = WordSerializer().writeBytes(
        WordDeserializer().readBytes(session.bytes),
      );
      expect(portable.wordTableText(reopened).first, 'A\t😀 & <B>');
    },
  );

  test('MCP compiles, validates and runs the actual table BAS', () async {
    final input = portable.wordTableInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    final adapter = OfficeMacroMcp(session);
    final compiled = await adapter.callTool(
      'office_macro_compile',
      _sourceArguments(File(_example).readAsStringSync()),
    );
    expect(compiled['isError'], isFalse, reason: '$compiled');
    expect(session.bytes, input);
    expect(session.revision, 0);
    final arguments = <String, Object?>{
      'macro': _structured(compiled)['macro'],
    };
    final validation = await adapter.callTool(
      'office_macro_validate',
      arguments,
    );
    expect(validation['isError'], isFalse, reason: '$validation');
    expect(session.bytes, input);
    final run = await adapter.callTool('office_macro_run', arguments);
    expect(run['isError'], isFalse, reason: '$run');
    expect(_structured(run)['completedSteps'], 5);
    expect(session.revision, 1);
    portable.assertWordTableOutput(session.bytes);
  });

  test(
    'MCP and native JSON both retain bytes on a later missing cell',
    () async {
      final input = portable.wordTableInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordTablePlan('''
$_cell.Text = "not published"
ActiveDocument.Tables(2).Cell(9, 1).Range.Text = "missing"
''');
      final adapter = OfficeMacroMcp(session);
      final failed = await adapter.callTool('office_macro_run', {
        'macro': plan.toJson(),
      });
      expect(failed['isError'], isTrue);
      expect(session.bytes, input);
      expect(session.revision, 0);
      final restored = OfficeMacro.parse(plan.encode());
      await expectLater(
        session.run(restored),
        throwsA(
          isA<OfficeMacroException>().having(
            (error) => error.stepIndex,
            'failed step',
            1,
          ),
        ),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test(
    'runtime refuses merged cell text after an earlier body write',
    () async {
      final document = WordDeserializer().readBytes(portable.wordTableInput());
      final table = document.sections.first.blocks.whereType<WmlTable>().single;
      table.rows.first.cells.first.gridSpan = 2;
      table.rows.first.cells.removeLast();
      final input = WordSerializer().writeBytes(document);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordTablePlan('''
ActiveDocument.Paragraphs(1).Range.InsertBefore "not published"
$_cell.Text = "ambiguous merged cell"
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(action(plan), throwsA(isA<OfficeMacroException>()));
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
    },
  );

  test(
    'CLI compiles and runs table BAS, preserving prior output on failure',
    () async {
      final directory = Directory.systemTemp.createTempSync('word-table-cli-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordTableInput());
      final original = input.readAsBytesSync();
      final source = File(_example).absolute.path;
      final compiled = File('${directory.path}/table.qudsmacro.json');
      final compilation = await runOfficeMacroCli([
        'compile-word-vba',
        source,
        compiled.path,
      ]);
      expect(
        compilation.exitCode,
        0,
        reason: '${compilation.stdout}\n${compilation.stderr}',
      );
      expect(
        OfficeMacro.parse(compiled.readAsStringSync()).steps,
        hasLength(5),
      );
      final validation = await runOfficeMacroCli([
        'validate-word-vba',
        input.path,
        source,
      ]);
      expect(
        validation.exitCode,
        0,
        reason: '${validation.stdout}\n${validation.stderr}',
      );
      expect(input.readAsBytesSync(), original);
      final output = File('${directory.path}/output.docm');
      final execution = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source,
        output.path,
      ]);
      expect(
        execution.exitCode,
        0,
        reason: '${execution.stdout}\n${execution.stderr}',
      );
      expect(input.readAsBytesSync(), original);
      portable.assertWordTableOutput(output.readAsBytesSync());
      final guard = (await WordPackagePreservation.capture(
        original,
        input.path,
      ))!;
      await guard.validateSaved(output.readAsBytesSync());
      final saved = output.readAsBytesSync();
      for (final (name, body) in [
        ('compile', 'ActiveDocument.Tables(0).Cell(1, 1).Range.Text = "bad"'),
        (
          'target',
          'ActiveDocument.Tables(2).Cell(9, 1).Range.Text = "missing"',
        ),
      ]) {
        final invalid = File('${directory.path}/$name.bas')
          ..writeAsStringSync(
            'Sub Main()\n$_cell.Text = "not published"\n$body\nEnd Sub',
          );
        final failure = await runOfficeMacroCli([
          'run-word-vba',
          input.path,
          invalid.path,
          output.path,
        ]);
        expect(failure.exitCode, isNot(0), reason: name);
        expect(output.readAsBytesSync(), saved, reason: name);
        expect(input.readAsBytesSync(), original, reason: name);
      }
    },
    timeout: officeMacroCliTestTimeout,
  );
}
