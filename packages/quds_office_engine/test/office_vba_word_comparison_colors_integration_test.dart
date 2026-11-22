import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_comparison_colors_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_comparison_colors.bas';
const _first = 'ActiveDocument.Paragraphs(1).Range.Font';

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _sourceArguments(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'WordComparisonColors',
    'source': source,
  },
};

List<List<String>> _bodyColors(Uint8List bytes) => [
  for (final paragraph
      in WordDeserializer()
          .readBytes(bytes)
          .sections
          .single
          .blocks
          .whereType<WmlParagraph>())
    [
      for (final run in paragraph.inlines.whereType<WmlRun>())
        run.properties.color,
    ],
];

void main() {
  registerOfficeMacroCliCleanup();

  test('actual BAS preserves DOCM, native colors and transactions', () async {
    final result = await portable.runWordComparisonColorsExample(
      File(_example).readAsStringSync(),
    );
    expect(result['operations'], 9);
    expect(result['revision'], 2);
    expect(result['recordedSteps'], 9);
    expect(result['additionalReopens'], 2);
    expect(result['opaquePartsPreserved'], isTrue);
    expect(result['colorMetadataPreserved'], isTrue);
    expect(result['lateRollback'], isTrue);
    expect(result['policyRefusals'], 3);
    expect(result['colors'], ['008000', '800000', 'auto', '000080', 'auto']);
    expect(result['cellText'], ['0', '-1']);
    expect(result['nativePartSha256'], hasLength(3));
  });

  test(
    'DOCX executes the same BAS without acquiring an embedded project',
    () async {
      final input = portable.wordComparisonColorsInput(macroEnabled: false);
      final plan = portable.wordComparisonColorsSource(
        File(_example).readAsStringSync(),
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.validate(plan);
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      portable.assertWordComparisonColorsOutput(
        session.bytes,
        macroEnabled: false,
      );
      final reopened = WordSerializer().writeBytes(
        WordDeserializer().readBytes(session.bytes),
      );
      portable.assertWordComparisonColorsOutput(reopened, macroEnabled: false);
    },
  );

  test('ByVal Font rebinding does not replace the caller alias', () async {
    final input = portable.wordComparisonColorsInput();
    final plan = portable.wordComparisonColorsSource('''
Sub Paint(ByVal target As Font)
  target.ColorIndex = wdRed
  Set target = ActiveDocument.Paragraphs(2).Range.Font
  target.ColorIndex = wdBlue
End Sub
Sub Main()
  Dim selected As Font
  Set selected = Application.ActiveDocument.Paragraphs.Item(1).Range.Font
  Paint target:=selected
  selected.ColorIndex = wdGreen
End Sub
''');
    expect(plan.steps.map((step) => step.arguments['paragraph']), [0, 1, 0]);
    expect(plan.steps.map((step) => step.arguments['color']), [
      'FF0000',
      '0000FF',
      '008000',
    ]);
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    await session.run(plan);
    expect(_bodyColors(session.bytes), [
      ['008000', '008000'],
      ['0000FF'],
      _bodyColors(input)[2],
    ]);
  });

  test(
    'Null comparison stays explicit and Empty selects a known branch',
    () async {
      final plan = portable.wordComparisonColorsPlan('''
Dim comparison As Variant
comparison = StrComp(Null, "Ready")
If IsNull(comparison) Then
  $_first.ColorIndex = wdAuto
End If
If StrComp(Empty, "", vbBinaryCompare) = 0 Then
  ActiveDocument.Paragraphs(2).Range.Font.ColorIndex = wdGray25
End If
''');
      expect(plan.steps.map((step) => step.arguments['color']), [
        'auto',
        'C0C0C0',
      ]);
      final session = OfficeMacroSession(
        portable.wordComparisonColorsInput(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(plan);
      expect(_bodyColors(session.bytes).take(2), [
        ['auto', 'auto'],
        ['C0C0C0'],
      ]);
    },
  );

  test('automatic and explicit black remain distinct native writes', () async {
    final input = portable.wordComparisonColorsInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    final plan = portable.wordComparisonColorsPlan('''
$_first.ColorIndex = wdAuto
$_first.ColorIndex = wdBlack
ActiveDocument.Paragraphs(2).Range.Font.Color = wdColorAutomatic
''');
    expect(plan.steps.map((step) => step.arguments['color']), [
      'auto',
      '000000',
      'auto',
    ]);
    await session.run(OfficeMacro.parse(plan.encode()));
    final reopened = WordSerializer().writeBytes(
      WordDeserializer().readBytes(session.bytes),
    );
    expect(_bodyColors(reopened).take(2), [
      ['000000', '000000'],
      ['auto'],
    ]);
  });

  test(
    'a later invalid target rolls back colors and leaves recording empty',
    () async {
      final input = portable.wordComparisonColorsInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Refused color workflow');
      final plan = portable.wordComparisonColorsPlan('''
$_first.ColorIndex = wdGreen
ActiveDocument.Paragraphs(99).Range.Font.Color = wdColorAutomatic
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
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
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  test(
    'an unsupported merged cell rolls back an earlier font change',
    () async {
      final document = WordDeserializer().readBytes(
        portable.wordComparisonColorsInput(),
      );
      final table = document.sections.single.blocks
          .whereType<WmlTable>()
          .single;
      table.rows.single.cells.first.gridSpan = 2;
      table.rows.single.cells.removeLast();
      final input = WordSerializer().writeBytes(document);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordComparisonColorsPlan('''
$_first.ColorIndex = wdBlue
ActiveDocument.Tables(1).Cell(1, 1).Range.Text = CStr(StrComp("A", "a"))
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(action(plan), throwsA(isA<OfficeMacroException>()));
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
    },
  );

  test(
    'MCP compiles, validates and runs the actual comparison/color BAS',
    () async {
      final input = portable.wordComparisonColorsInput();
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
      expect(_structured(run)['completedSteps'], 9);
      expect(session.revision, 1);
      portable.assertWordComparisonColorsOutput(session.bytes);
    },
  );

  test(
    'MCP refuses an invalid comparison before any source plan is published',
    () async {
      final input = portable.wordComparisonColorsInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final adapter = OfficeMacroMcp(session);
      final rejected = await adapter.callTool(
        'office_macro_compile',
        _sourceArguments('''
Sub Main()
  $_first.ColorIndex = wdGreen
  Dim result As Variant
  result = StrComp(Null, "Ready", vbTextCompare)
End Sub
'''),
      );
      expect(rejected['isError'], isTrue);
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test(
    'CLI compiles/runs the actual BAS and retains prior output on refusals',
    () async {
      final directory = Directory.systemTemp.createTempSync('word-colors-cli-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordComparisonColorsInput());
      final original = input.readAsBytesSync();
      final source = File(_example).absolute.path;
      final compiled = File('${directory.path}/report.qudsmacro.json');
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
        hasLength(9),
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
      portable.assertWordComparisonColorsOutput(output.readAsBytesSync());
      final saved = output.readAsBytesSync();
      for (final (name, statement) in [
        (
          'compare',
          'Dim result As Variant\nresult = StrComp("A", "a", vbTextCompare)',
        ),
        ('palette', '$_first.ColorIndex = -1'),
        (
          'target',
          'ActiveDocument.Paragraphs(99).Range.Font.ColorIndex = wdBlue',
        ),
      ]) {
        final invalid = File('${directory.path}/$name.bas')
          ..writeAsStringSync(
            'Sub Main()\n$_first.ColorIndex = wdAuto\n$statement\nEnd Sub',
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
