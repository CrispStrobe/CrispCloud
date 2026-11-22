import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_numeric_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_numeric_report.bas';
const _first = 'ActiveDocument.Paragraphs(1).Range';

Map<String, Object?> _structured(Map<String, Object?> value) =>
    value['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _sourceArguments(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'WordNumericReport',
    'source': source,
  },
};

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'actual BAS replays on DOCM, preserves rich parts and obeys transactions',
    () async {
      final result = await portable.runWordNumericExample(
        File(_example).readAsStringSync(),
      );
      expect(result['operations'], 9);
      expect(result['revision'], 2);
      expect(result['recordedSteps'], 9);
      expect(result['additionalReopens'], 2);
      expect(result['opaquePartsPreserved'], isTrue);
      expect(result['richFormattingPreserved'], isTrue);
      expect(result['nativeXmlUnitsVerified'], isTrue);
      expect(result['lateRollback'], isTrue);
      expect(result['policyRefusals'], 3);
      expect(result['sharedDialects'], {
        'excelValues': [8.25, -9, -8, -1],
        'powerPointText': '8.25/-9/-8/-1',
        'powerPointLeftPoints': 12.5,
      });
    },
  );

  test(
    'the same numeric BAS runs on DOCX without creating a VBA project',
    () async {
      final input = portable.wordNumericInput(macroEnabled: false);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordNumericSource(
        File(_example).readAsStringSync(),
      );
      final validation = await session.validate(plan);
      expect(validation.validatedOnly, isTrue);
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      portable.assertWordNumericOutput(session.bytes, macroEnabled: false);
      final reopened = WordSerializer().writeBytes(
        WordDeserializer().readBytes(session.bytes),
      );
      portable.assertWordNumericOutput(reopened, macroEnabled: false);
    },
  );

  test('source helper arguments execute once in their written order', () async {
    final input = portable.wordNumericInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    final plan = portable.wordNumericSource('''
Function Probe(ByVal label As String, ByVal value As Double) As Double
  $_first.InsertBefore label
  Probe = value
End Function
Sub Main()
  $_first.InsertBefore CStr(Abs(Probe("abs>", -1.25))) & "/" & CStr(Int(Probe("int>", -1.25))) & "/" & CStr(Fix(Probe("fix>", -1.25))) & "/" & CStr(Sgn(Probe("sgn>", -1.25)))
End Sub
''');
    expect(plan.steps, hasLength(5));
    await session.run(plan);
    expect(
      WordDeserializer().readBytes(session.bytes).paragraphs.first.text,
      '1.25/-2/-1/-1sgn>fix>int>abs>body one',
    );
  });

  test(
    'numeric arrays drive Word targets and distinguish floor from truncation',
    () async {
      final session = OfficeMacroSession(
        portable.wordNumericInput(),
        format: OfficeMacroFormat.docx,
      );
      final plan = portable.wordNumericPlan('''
Dim amounts(1 To 3) As Double
Dim i As Long
amounts(1) = -1.25
amounts(2) = 0.75
amounts(3) = -0.25
For i = 1 To 3
  ActiveDocument.Paragraphs(i).Range.InsertBefore CStr(Int(amounts(i))) & "/" & CStr(Fix(amounts(i))) & "/" & CStr(Sgn(amounts(i))) & ": "
  ActiveDocument.Paragraphs(i).Range.Font.Size = Abs(Int(amounts(i))) + 10
Next i
''');
      expect(plan.steps, hasLength(6));
      await session.run(plan);
      final document = WordDeserializer().readBytes(session.bytes);
      expect(document.paragraphs.map((paragraph) => paragraph.text), [
        '-2/-1/-1: body one',
        '0/0/1: body two',
        '-1/0/-1: body three',
      ]);
      for (final (index, paragraph) in document.paragraphs.indexed) {
        expect(
          paragraph.inlines.whereType<WmlRun>().map(
            (run) => run.properties.fontSizeHalfPoints,
          ),
          everyElement([24, 20, 22][index]),
        );
      }
    },
  );

  test(
    'Empty and Null stay distinguishable through the Word report path',
    () async {
      final session = OfficeMacroSession(
        portable.wordNumericInput(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        portable.wordNumericPlan('''
Dim absent As Variant, unset As Variant
absent = CVar(Null)
$_first.InsertBefore CStr(Abs(unset)) & "/" & CStr(Int(unset)) & "/" & CStr(Fix(unset)) & "/" & CStr(Sgn(unset)) & ": "
If IsNull(Abs(absent)) And IsNull(Int(absent)) And IsNull(Fix(absent)) Then
  $_first.InsertBefore "Null retained; "
End If
'''),
      );
      expect(
        WordDeserializer().readBytes(session.bytes).paragraphs.first.text,
        'Null retained; 0/0/0/0: body one',
      );
    },
  );

  test(
    'portable boundary results reach DOCX text without narrowing to Long',
    () async {
      final session = OfficeMacroSession(
        portable.wordNumericInput(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        portable.wordNumericPlan('''
$_first.InsertBefore CStr(Abs(-9007199254740991)) & "/" & CStr(Int(-0.25)) & "/" & CStr(Fix(-0.25)) & "/" & CStr(Sgn(CDbl("-5e-324"))) & ": "
'''),
      );
      expect(
        WordDeserializer().readBytes(session.bytes).paragraphs.first.text,
        '9007199254740991/-1/0/-1: body one',
      );
    },
  );

  test(
    'MCP compilation and validation are private before numeric execution',
    () async {
      final input = portable.wordNumericInput();
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
      portable.assertWordNumericOutput(session.bytes);
    },
  );

  for (final expression in <String>[
    'Sgn(Null)',
    'Abs("8.25")',
    'Fix(True)',
    'Int(9007199254740992)',
  ]) {
    test(
      'MCP refuses $expression after an earlier write without publication',
      () async {
        final input = portable.wordNumericInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        final adapter = OfficeMacroMcp(session);
        final compiled = await adapter.callTool(
          'office_macro_compile',
          _sourceArguments('''
Sub Main()
  $_first.InsertBefore "not published"
  $_first.InsertBefore CStr($expression)
End Sub
'''),
        );
        expect(compiled['isError'], isTrue, reason: '$compiled');
        expect(session.bytes, input);
        expect(session.revision, 0);
      },
    );
  }

  test(
    'CLI compiles and runs the actual BAS and retains prior output on failure',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'word-numeric-cli-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordNumericInput());
      final original = input.readAsBytesSync();
      final source = File(_example).absolute.path;
      final compiled = File('${directory.path}/numeric.qudsmacro.json');
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
      portable.assertWordNumericOutput(output.readAsBytesSync());
      final guard = (await WordPackagePreservation.capture(
        original,
        input.path,
      ))!;
      await guard.validateSaved(output.readAsBytesSync());
      final saved = output.readAsBytesSync();
      for (final (name, body) in [
        ('compile', '$_first.InsertBefore CStr(Sgn(Null))'),
        (
          'target',
          'ActiveDocument.Paragraphs(Int(99.5)).Range.InsertBefore CStr(Abs(-3))',
        ),
      ]) {
        final invalid = File('${directory.path}/$name.bas')
          ..writeAsStringSync('''
Sub Main()
  $_first.InsertBefore CStr(Abs(-7))
  $body
End Sub
''');
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
