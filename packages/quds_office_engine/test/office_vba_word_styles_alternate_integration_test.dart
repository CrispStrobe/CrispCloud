import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_styles_alternate_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_styles.bas';

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _sourceArguments(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'WordStylesIntegration',
    'source': source,
  },
};

Matcher _failure({required int step}) => isA<OfficeMacroException>()
    .having((error) => error.code, 'code', 'operation_failed')
    .having((error) => error.stepIndex, 'step', step)
    .having((error) => error.tool, 'tool', 'docx.paragraphStyle');

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'committed BAS applies native styles, preserves DOCM and reopens',
    () async {
      final result = await portable.runWordStylesExample(
        File(_example).readAsStringSync(),
      );
      expect(result['operations'], 5);
      expect(result['firstRunRevision'], 1);
      expect(result['repeatedRevision'], 2);
      expect(result['additionalReopens'], 2);
      expect(result['opaquePayloadsPreserved'], isTrue);
    },
  );

  test(
    'pending text and direct formatting survive repeated style changes',
    () async {
      final input = portable.wordStylesInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordStylesPlan('''
With ActiveDocument.Paragraphs(1).Range
  .InsertBefore "Revised "
  .Font.Bold = False
  .ParagraphFormat.SpaceBefore = 7
  .Style = wdStyleHeading1
  .Style = "Report Body"
  .ParagraphFormat.SpaceAfter = 8
End With
''');
      await session.validate(plan);
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      final document = WordDeserializer().readBytes(session.bytes);
      final first = document.paragraphs.first;
      expect(first.text, 'Revised Report title');
      expect(first.properties.styleId, 'ReportBody');
      expect(first.properties.spacingBefore, 7);
      expect(first.properties.spacingAfter, 8);
      expect(
        first.inlines.whereType<WmlRun>().every((run) => !run.properties.bold),
        isTrue,
      );
      final reopened = WordSerializer().writeBytes(document);
      expect(
        portable.wordStylesState(reopened),
        portable.wordStylesState(session.bytes),
      );
      expect(session.revision, 1);
    },
  );

  test(
    'ByVal paragraph and Range aliases retain their caller selectors',
    () async {
      final session = OfficeMacroSession(
        portable.wordStylesInput(),
        format: OfficeMacroFormat.docx,
      );
      final plan = portable.wordStylesSource('''
Sub Change(ByVal para As Paragraph, ByVal target As Range)
  para.Style = "Report Body"
  target.Style = wdStyleHeading1
  Set para = ActiveDocument.Paragraphs(3)
  Set target = ActiveDocument.Paragraphs(4).Range
  para.Style = wdStyleCaption
  target.Style = wdStyleNormal
End Sub
Sub Main()
  Dim p As Paragraph
  Dim r As Range
  Set p = ActiveDocument.Paragraphs(1)
  Set r = ActiveDocument.Paragraphs(2).Range
  Change target:=r, para:=p
  p.Style = wdStyleHeading1
  r.Style = "Report Body"
End Sub
''');
      await session.run(plan);
      expect(
        WordDeserializer()
            .readBytes(session.bytes)
            .paragraphs
            .map((paragraph) => paragraph.properties.styleId),
        ['ReportHeadingOne', 'ReportBody', 'CaptionStyle', 'Normal'],
      );
    },
  );

  test(
    'late failure rolls back native styles, direct edits and recording',
    () async {
      final result = await portable.runWordStylesRollback();
      expect(result['failedStep'], 2);
      expect(result['validateAndRunRollback'], isTrue);
    },
  );

  test(
    'a failed later transaction retains the previous accepted revision',
    () async {
      final session = OfficeMacroSession(
        portable.wordStylesInput(),
        format: OfficeMacroFormat.docx,
      );
      session.startRecording('Accepted style plus rejected transaction');
      await session.callTool('docx.paragraphStyle', {
        'paragraph': 0,
        'builtin': -2,
      });
      final before = session.bytes;
      final plan = portable.wordStylesPlan('''
ActiveDocument.Paragraphs(2).Style = "Report Body"
ActiveDocument.Paragraphs(3).Style = "Does not exist"
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(action(plan), throwsA(_failure(step: 1)));
        expect(session.bytes, before);
        expect(session.revision, 1);
      }
      final recording = session.stopRecording();
      expect(recording.steps, hasLength(1));
      expect(recording.steps.single.arguments, {'paragraph': 0, 'builtin': -2});
    },
  );

  test(
    'style calls record and replay without recording failed calls',
    () async {
      final result = await portable.runWordStylesRecording();
      expect(result['recordedSteps'], 2);
      expect(result['failedCallExcluded'], isTrue);
      expect(result['replayRevision'], 1);
    },
  );

  test('mutation permissions and native step budgets remain atomic', () async {
    final result = await portable.runWordStylesPolicy();
    expect(result['atomicDenials'], 6);
    expect(result['allowedSteps'], 2);
  });

  test(
    'MCP exposes paragraphStyle and compiles, validates and runs BAS',
    () async {
      final input = portable.wordStylesInput();
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
      final validated = await adapter.callTool(
        'office_macro_validate',
        arguments,
      );
      expect(validated['isError'], isFalse, reason: '$validated');
      expect(_structured(validated)['completedSteps'], 5);
      expect(_structured(validated)['validatedOnly'], isTrue);
      expect(session.bytes, input);
      expect(session.revision, 0);
      final run = await adapter.callTool('office_macro_run', arguments);
      expect(run['isError'], isFalse, reason: '$run');
      expect(_structured(run)['completedSteps'], 5);
      expect(session.revision, 1);
      portable.assertWordStylesExample(session.bytes);
    },
  );

  test(
    'MCP unsupported Style reads expose no prefix plan or mutation',
    () async {
      final input = portable.wordStylesInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final result = await OfficeMacroMcp(session).callTool(
        'office_macro_compile',
        _sourceArguments('''
Sub Main()
  ActiveDocument.Paragraphs(1).Style = wdStyleHeading1
  Dim name As Variant
  name = ActiveDocument.Paragraphs(2).Style
End Sub
'''),
      );
      expect(result['isError'], isTrue);
      expect(_structured(result).containsKey('macro'), isFalse);
      final error = _structured(result)['error']! as Map<String, Object?>;
      expect(error['moduleName'], 'WordStylesIntegration');
      expect(error['line'], greaterThan(0));
      expect(error['column'], greaterThan(0));
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test(
    'CLI executes actual BAS without changing input or opaque DOCM parts',
    () async {
      final directory = Directory.systemTemp.createTempSync('quds-styles-cli-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordStylesInput());
      final before = input.readAsBytesSync();
      final output = File('${directory.path}/output.docm');
      final result = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        File(_example).absolute.path,
        output.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        (jsonDecode(result.stdout as String) as Map)['language'],
        'vba-word',
      );
      expect(input.readAsBytesSync(), before);
      final saved = output.readAsBytesSync();
      portable.assertWordStylesExample(saved);
      final guard = (await WordPackagePreservation.capture(
        before,
        input.path,
      ))!;
      await guard.validateSaved(saved);
    },
    timeout: officeMacroCliTestTimeout,
  );

  test(
    'CLI missing later style retains input and existing output bytes',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'quds-styles-fail-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordStylesInput());
      final before = input.readAsBytesSync();
      final output = File('${directory.path}/output.docm')
        ..writeAsStringSync('Keep existing output');
      final source = File('${directory.path}/invalid.bas')
        ..writeAsStringSync('''
Sub Main()
  ActiveDocument.Paragraphs(1).Style = wdStyleHeading1
  ActiveDocument.Paragraphs(2).Style = "Missing style"
End Sub
''');
      final result = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source.path,
        output.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(input.readAsBytesSync(), before);
      expect(output.readAsStringSync(), 'Keep existing output');
    },
    timeout: officeMacroCliTestTimeout,
  );
}
