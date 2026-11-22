import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_text_selectors_smoke.dart' as portable;

const _example = 'example/macros/word_text_selectors.bas';

void main() {
  test(
    'the committed BAS has the independently specified five-operation plan',
    () {
      final source = File(_example).readAsStringSync();
      final plan = portable.wordTextSelectorsSource(source);
      expect(
        plan.steps.map((step) => step.toJson()),
        portable.wordTextSelectorsExpectedSteps,
      );
      expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
    },
  );

  test(
    'the actual BAS preserves every other story and native boundary',
    () async {
      final receipt = await portable.runWordTextSelectorsExample(
        File(_example).readAsStringSync(),
      );
      expect(receipt['fixtureFormat'], 'docm');
      expect(receipt['operations'], 5);
      expect(receipt['firstRunRevision'], 1);
      expect(receipt['repeatedRevision'], 2);
      expect(receipt['additionalReopens'], 2);
      expect(receipt['recordedSteps'], 5);
      expect(receipt['untouchedStoryParagraphs'], 33);
      expect(receipt['untouchedBodyParagraphs'], 2);
      for (final field in [
        'opaquePayloadsPreserved',
        'immutableValidation',
        'nativeRecordingAndReplay',
        'lateRollbackAndRecording',
        'mcpCompileValidateRun',
        'inactiveNamedArgumentRejected',
        'hostPolicyGuards',
      ]) {
        expect(receipt[field], isTrue, reason: field);
      }
    },
  );

  test(
    'ByVal collection rebinding leaves its caller in the original story',
    () async {
      final plan = portable.wordTextSelectorsSource('''
Option Explicit
Sub Main()
  Dim targets As Paragraphs
  Set targets = ActiveDocument.Sections(Index:=2).Headers(Index:=1).Range.Paragraphs
  AddLabel items:=targets
  targets.Item(Index:=2).Range.InsertBefore Text:=Right("Ready", 2) & ": "
End Sub
Sub AddLabel(ByVal items As Paragraphs)
  items.Item(Index:=1).Range.InsertBefore Text:=Left("Template", 4) & ": "
  Set items = ActiveDocument.Paragraphs
  items.Item(Index:=1).Range.InsertBefore Text:=Mid("Body", 2) & ": "
End Sub
''');
      final session = OfficeMacroSession(
        portable.wordTextSelectorsInput(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(plan);
      final document = WordDeserializer().readBytes(session.bytes);
      expect(document.sections[1].header.map((paragraph) => paragraph.text), [
        'Temp: S2 header 1',
        'dy: S2 header 2',
      ]);
      expect(document.paragraphs.map((paragraph) => paragraph.text), [
        'ody: Body 1',
        'Body 2',
        'Body 3',
      ]);
      expect(document.sections[0].header.first.text, 'S1 header 1');
      expect(document.sections[2].header.first.text, 'S3 header 1');
    },
  );

  test(
    'Null and malformed-text source failures publish no partial MCP plan',
    () async {
      for (final expression in [
        'Mid(Null, 1)',
        'Left("😀", 1)',
        'Mid(Null, 0)',
      ]) {
        final input = portable.wordTextSelectorsInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        )..startRecording('Rejected text');
        final response = await OfficeMacroMcp(session).callTool(
          'office_macro_compile',
          {
            'source': {
              'language': 'vba-word',
              'format': 'docx',
              'moduleName': 'RejectedText',
              'source':
                  '''
Sub Main()
  ActiveDocument.Paragraphs(Index:=1).Range.InsertBefore "Discard"
  ActiveDocument.Sections(Index:=2).Headers(Index:=1).Range.Paragraphs(Index:=1).Range.InsertBefore $expression
End Sub
''',
            },
          },
        );
        expect(response['isError'], isTrue);
        final structured =
            response['structuredContent']! as Map<String, Object?>;
        expect(structured.containsKey('macro'), isFalse);
        final error = structured['error']! as Map<String, Object?>;
        expect(error['code'], 'vba_type_error');
        expect(error['line'], 3);
        expect(session.bytes, input);
        expect(session.revision, 0);
        expect(session.stopRecording().steps, isEmpty);
      }
    },
  );
}
