import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_cell_paragraphs_smoke.dart' as fixture;
import '../tool/macros/web_vba_word_mid_assignment_smoke.dart' as portable;

const _example = 'example/macros/word_fixed_width_labels.bas';

List<String> _texts(OfficeMacroSession session) => [
  for (final cell in fixture.wordCellParagraphs(
    WordDeserializer().readBytes(session.bytes),
  ))
    cell.text,
];

void main() {
  test('the checked-in BAS produces exactly the independent label plan', () {
    final plan = portable.wordMidAssignmentSource(
      File(_example).readAsStringSync(),
    );
    const labels = [
      'Item: Widget',
      'State: Ready  ',
      'Code: 0042',
      'OPEN/DONE',
    ];
    expect(plan.steps.map((step) => step.toJson()), [
      for (var index = 0; index < labels.length; index++) ...[
        {
          'tool': 'docx.tableCellRangeText',
          'arguments': {
            'table': 0,
            'row': index ~/ 2,
            'column': index % 2,
            'text': labels[index],
          },
        },
        {
          'tool': 'docx.runFormat',
          'arguments': {
            'paragraph': 0,
            'story': 'tableCell',
            'table': 0,
            'row': index ~/ 2,
            'column': index % 2,
            'bold': index < 2,
          },
        },
      ],
    ]);
    expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
  });

  for (final macroEnabled in [false, true]) {
    test(
      '${macroEnabled ? 'DOCM' : 'DOCX'} exact BAS preserves packages and native transaction boundaries',
      () async {
        final result = await portable.runWordMidAssignmentExample(
          File(_example).readAsStringSync(),
          macroEnabled: macroEnabled,
        );
        expect(result['operations'], 8);
        expect(result['revision'], 1);
        expect(result['recordedSteps'], 8);
        expect(result['additionalReopens'], 2);
        expect(result['opaqueVbaPreserved'], macroEnabled);
        for (final key in [
          'untouchedGeometryAndParts',
          'immutableValidation',
          'lateRollbackAndRecording',
          'mcpCompileValidateRun',
          'sourceFailureNoPublication',
          'readOnlyPolicy',
        ]) {
          expect(result[key], isTrue, reason: key);
        }
      },
    );
  }

  test(
    'ByVal strings and scalar function results produce distinct document values',
    () async {
      final plan = portable.wordMidAssignmentSource(r'''
Option Explicit
Sub Main()
  Dim label As String
  label = "id:0000"
  ActiveDocument.Tables(1).Cell(1, 1).Range.Text = Patch(label)
  ActiveDocument.Tables(1).Cell(1, 2).Range.Text = label
End Sub
Function Patch(ByVal value As String) As String
  Mid(value, 4, 4) = "0042"
  Patch = value
  Mid$(Patch, 1, 2) = "ID"
End Function
''');
      final input = portable.wordMidAssignmentInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(plan);
      expect(_texts(session), [
        'ID:0042',
        'id:0000',
        '',
        'first 1/1',
        'second 0/0',
      ]);
      expect(
        portable.wordMidAssignmentUntouched(session.bytes),
        portable.wordMidAssignmentUntouched(input),
      );
    },
  );

  test(
    'UTF-16 offsets build multilingual labels that survive Word serialization',
    () async {
      final plan = portable.wordMidAssignmentPlan(r'''
Dim label As String
label = "A😀B----"
Mid$(label, 2, 2) = "🚀"
Mid(label, 5, 4) = "سالم"
ActiveDocument.Tables(1).Cell(1, 1).Range.Text = label
''');
      expect(plan.steps.single.arguments['text'], 'A🚀Bسالم');
      final input = portable.wordMidAssignmentInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(plan);
      expect(_texts(session).first, 'A🚀Bسالم');
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(
          WordDeserializer().readBytes(session.bytes),
        ),
      );
      expect(fixture.wordCellParagraphs(reopened).first.text, 'A🚀Bسالم');
      expect(
        portable.wordMidAssignmentUntouched(session.bytes),
        portable.wordMidAssignmentUntouched(input),
      );
    },
  );

  test(
    'self-overlapping and truncated replacements are resolved before document writes',
    () async {
      final plan = portable.wordMidAssignmentPlan(r'''
Dim labels(1 To 2) As String
labels(1) = "abcde"
Mid$(labels(1), 2, 3) = labels(1)
labels(2) = "ABCD"
Mid(labels(2), 4, 20) = "XYZ"
ActiveDocument.Tables(1).Cell(1, 1).Range.Text = labels(1)
ActiveDocument.Tables(1).Cell(1, 2).Range.Text = labels(2)
''');
      final session = OfficeMacroSession(
        portable.wordMidAssignmentInput(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(plan);
      expect(_texts(session).take(2), ['aabce', 'ABCX']);
    },
  );

  test(
    'Mid-generated paragraph controls refuse source publication atomically',
    () async {
      final input = portable.wordMidAssignmentInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx)
        ..startRecording('Rejected control');
      final mcp = OfficeMacroMcp(session);
      final response = await mcp.callTool('office_macro_compile', {
        'source': {
          'language': 'vba-word',
          'format': 'docx',
          'moduleName': 'MidGeneratedControl',
          'source': r'''
Sub Main()
  Dim label As String
  label = "----"
  Mid$(label, 2, 1) = vbCr
  ActiveDocument.Tables(1).Cell(1, 1).Range.Text = "Discard"
  ActiveDocument.Tables(1).Cell(1, 2).Range.Text = label
End Sub
''',
        },
      });
      expect(response['isError'], isTrue);
      final content = response['structuredContent']! as Map<String, Object?>;
      expect(content.containsKey('macro'), isFalse);
      final error = content['error']! as Map<String, Object?>;
      expect(error['code'], 'vba_type_error');
      expect(error['line'], 6);
      expect(session.bytes, input);
      expect(session.revision, 0);
      expect(session.stopRecording().steps, isEmpty);
    },
  );
}
