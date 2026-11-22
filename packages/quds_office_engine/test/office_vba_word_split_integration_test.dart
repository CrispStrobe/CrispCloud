import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_split_smoke.dart' as portable;

const _example = 'example/macros/word_split_report.bas';
const _first = 'ActiveDocument.Tables(Index:=1).Cell(Row:=1, Column:=1).Range';

Map<String, Object?> _structured(Map<String, Object?> response) =>
    response['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _source(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'WordSplitReport',
    'source': source,
  },
};

List<String> _tableText(Uint8List bytes) => [
  for (final section in WordDeserializer().readBytes(bytes).sections)
    for (final table in section.blocks.whereType<WmlTable>())
      for (final row in table.rows)
        for (final cell in row.cells) (cell.blocks.single as WmlParagraph).text,
];

void main() {
  test(
    'committed Split BAS has seven independently specified native edits',
    () {
      final plan = portable.wordSplitSource(File(_example).readAsStringSync());
      expect(
        plan.steps.map((step) => step.toJson()),
        portable.wordSplitExpectedSteps,
      );
      expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
    },
  );

  for (final macroEnabled in [false, true]) {
    test(
      '${macroEnabled ? 'DOCM' : 'DOCX'} actual Split report validates, saves and replays',
      () async {
        final receipt = await portable.runWordSplitExample(
          File(_example).readAsStringSync(),
          macroEnabled: macroEnabled,
        );
        expect(receipt['format'], macroEnabled ? 'docm' : 'docx');
        expect(receipt['operations'], 7);
        expect(receipt['firstRunRevision'], 1);
        expect(receipt['repeatedRevision'], 2);
        expect(receipt['additionalReopens'], 2);
        expect(receipt['recordedSteps'], 7);
        for (final field in [
          'immutableValidation',
          'opaquePartsPreserved',
          'nativeRecordingAndReplay',
          'mcpCompileValidateRun',
        ]) {
          expect(receipt[field], isTrue, reason: field);
        }
      },
    );
  }

  test(
    'Split arrays feed helper aliases, For Each, bounds and Join into native cells',
    () async {
      final input = portable.wordSplitInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordSplitSource('''
Option Explicit
Option Base 1
Sub Main()
  Dim values() As String
  Dim item As Variant
  Dim column As Long
  values = Split("Résumé|مرحبا 😀", "|")
  column = 1
  For Each item In values
    PutText value:=CStr(item), target:=ActiveDocument.Tables(Index:=1).Cell(Row:=2, Column:=column).Range
    column = column + 1
  Next item
  Let values = Split("", "|")
  $_first.Text = "empty:" & CStr(LBound(values)) & ":" & CStr(UBound(values)) & ":" & Join(values, "|")
  values = Split("left|right|tail", "|", 2)
  ActiveDocument.Tables(1).Cell(1, 2).Range.Text = Join(values, " / ")
End Sub
Sub PutText(ByVal target As Range, ByVal value As String)
  target.Text = value
End Sub
''');
      expect(plan.steps, hasLength(4));
      await session.run(plan);
      var saved = session.bytes;
      for (var generation = 0; generation < 3; generation++) {
        expect(_tableText(saved), [
          'empty:0:-1:',
          'left / right|tail',
          'Résumé',
          'مرحبا 😀',
          'second 0/0',
        ]);
        final document = WordDeserializer().readBytes(saved);
        expect(document.sections.first.header.single.text, 'Untouched header');
        if (generation < 2) saved = WordSerializer().writeBytes(document);
      }
      final guard = (await WordPackagePreservation.capture(
        input,
        'helpers.docm',
      ))!;
      await guard.validateSaved(saved);
    },
  );

  test(
    'Split-produced late missing cell rolls back bytes, revision and recording',
    () async {
      final session = OfficeMacroSession(
        portable.wordSplitInput(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        portable.wordSplitSource(File(_example).readAsStringSync()),
      );
      final before = session.bytes;
      final plan = portable.wordSplitPlan('''
Dim fields() As String
fields = Split("not published|missing row", "|")
$_first.Text = fields(0)
ActiveDocument.Tables(Index:=1).Cell(Row:=3, Column:=1).Range.Text = fields(1)
''');
      session.startRecording('Rejected delimited report');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(
            isA<OfficeMacroException>()
                .having((error) => error.code, 'code', 'operation_failed')
                .having((error) => error.stepIndex, 'failed step', 1)
                .having(
                  (error) => error.tool,
                  'tool',
                  'docx.tableCellRangeText',
                ),
          ),
        );
        expect(session.bytes, before);
        expect(session.revision, 1);
      }
      final rejected = await OfficeMacroMcp(
        session,
      ).callTool('office_macro_run', {'macro': plan.toJson()});
      expect(rejected['isError'], isTrue);
      expect(
        (_structured(rejected)['error']! as Map<String, Object?>)['stepIndex'],
        1,
      );
      expect(session.bytes, before);
      expect(session.revision, 1);
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  for (final (failure, code) in [
    ('Split(Null, "|")', 'vba_invalid_use_of_null'),
    ('Split("a|b", "|", -2)', 'vba_type_error'),
  ]) {
    test(
      'MCP refuses $failure without publishing an earlier compiled edit',
      () async {
        final input = portable.wordSplitInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        )..startRecording('Rejected Split source');
        final rejected = await OfficeMacroMcp(session).callTool(
          'office_macro_compile',
          _source('''
Sub Main()
  Dim fields() As String
  $_first.Text = "discard"
  fields = $failure
End Sub
'''),
        );
        expect(rejected['isError'], isTrue);
        final structured = _structured(rejected);
        expect(structured.containsKey('macro'), isFalse);
        final error = structured['error']! as Map<String, Object?>;
        expect(error['code'], code);
        expect(error['line'], 4);
        expect(session.bytes, input);
        expect(session.revision, 0);
        expect(session.stopRecording().steps, isEmpty);
      },
    );
  }

  test(
    'Split retains native policy, cancellation and plain-cell boundaries',
    () async {
      final input = portable.wordSplitInput();
      final plan = portable.wordSplitSource(File(_example).readAsStringSync());
      for (final policy in [
        OfficeMacroPolicy(allowMutation: false),
        OfficeMacroPolicy(allowedTools: {'docx.tableCellRangeText'}),
        OfficeMacroPolicy(maxSteps: 6),
      ]) {
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
          policy: policy,
        );
        await expectLater(
          session.run(plan),
          throwsA(isA<OfficeMacroException>()),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
      final cancelled = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
      );
      await expectLater(
        cancelled.run(plan, cancellation: OfficeMacroCancellation()..cancel()),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(cancelled.bytes, input);
      expect(cancelled.revision, 0);

      final document = WordDeserializer().readBytes(input);
      final table = document.sections.first.blocks.whereType<WmlTable>().single;
      table.rows.last.cells.first.blocks.add(
        WmlParagraph(inlines: [WmlRun(text: 'Protected neighbor')]),
      );
      final richInput = WordSerializer().writeBytes(document);
      final rich = OfficeMacroSession(
        richInput,
        format: OfficeMacroFormat.docx,
      );
      await expectLater(
        rich.run(plan),
        throwsA(
          isA<OfficeMacroException>().having(
            (error) => error.stepIndex,
            'late unsupported cell',
            4,
          ),
        ),
      );
      expect(rich.bytes, richInput);
      expect(rich.revision, 0);
    },
  );
}
