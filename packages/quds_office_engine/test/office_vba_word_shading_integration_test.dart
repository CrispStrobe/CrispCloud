import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_shading_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_shading.bas';
const _first = 'ActiveDocument.Paragraphs(1).Shading';
const _second = 'ActiveDocument.Paragraphs(2).Range.Shading';

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _sourceArguments(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'WordShadingIntegration',
    'source': source,
  },
};

Matcher _failure(int step) => isA<OfficeMacroException>()
    .having((error) => error.stepIndex, 'step', step)
    .having((error) => error.tool, 'tool', 'docx.paragraphShading');

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'committed BAS validates, records, replays and preserves DOCM',
    () async {
      final result = await portable.runWordShadingExample(
        File(_example).readAsStringSync(),
      );
      expect(result['operations'], 7);
      expect(result['revision'], 1);
      expect(result['repeatedRevision'], 2);
      expect(result['recordedSteps'], 7);
      expect(result['additionalReopens'], 2);
      expect(result['opaquePayloadsPreserved'], isTrue);
      expect(result['nativePartSha256'], hasLength(5));
    },
  );

  test(
    'ByVal Shading rebinding retains the caller and optional color',
    () async {
      final input = portable.wordShadingInput();
      final original = portable.wordShadingState(input);
      final plan = portable.wordShadingSource('''
Sub Shade(ByVal target As Shading, Optional ByVal tone As Long = 255)
  target.BackgroundPatternColor = tone
  Set target = ThisDocument.Paragraphs(2).Range.Shading
  target.BackgroundPatternColorIndex = wdBlue
End Sub
Sub Main()
  Dim target As Shading
  Set target = Application.ActiveDocument.Paragraphs.Item(1).Shading
  Shade target:=target
  target.BackgroundPatternColorIndex = wdGreen
End Sub
''');
      expect(plan.steps.map((step) => step.arguments['paragraph']), [0, 1, 0]);
      expect(plan.steps.map((step) => step.arguments['color']), [
        'FF0000',
        '0000FF',
        '008000',
      ]);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.validate(plan);
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      final expected = [
        {...original[0], 'fill': '008000'},
        {...original[1], 'fill': '0000FF'},
        ...original.skip(2),
      ];
      expect(portable.wordShadingState(session.bytes), expected);
      final reopened = WordSerializer().writeBytes(
        WordDeserializer().readBytes(session.bytes),
      );
      expect(portable.wordShadingState(reopened), expected);
      portable.assertWordShadingPackage(reopened);
    },
  );

  test(
    'missing later paragraph rolls back validation, run and recording',
    () async {
      expect(await portable.runWordShadingRollback(), {
        'failedStep': 1,
        'validateAndRunRollback': true,
      });
    },
  );

  test(
    'patterned source shading refuses without publishing any transaction',
    () async {
      final package = OpcPackage.openBytes(portable.wordShadingInput());
      final part = package.getPart('/word/document.xml')!;
      const original = '<w:shd w:val="clear" w:fill="DDEEFF"/>';
      expect(part.readText(), contains(original));
      part.writeText(
        part.readText().replaceFirst(
          original,
          '<w:shd w:val="pct25" w:color="111111" w:fill="DDEEFF"/>',
        ),
      );
      final input = package.save();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Rejected patterned shading');
      final plan = portable.wordShadingPlan('''
$_first.BackgroundPatternColorIndex = wdRed
$_second.BackgroundPatternColorIndex = wdYellow
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(
            isA<OfficeMacroException>().having(
              (error) => error.tool,
              'tool',
              'docx.paragraphShading',
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
    'recording excludes a failed native call and retains an earlier revision',
    () async {
      final input = portable.wordShadingInput();
      final original = portable.wordShadingState(input);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Native paragraph shading');
      await session.callTool('docx.paragraphShading', {
        'paragraph': 0,
        'color': '010203',
      });
      final saved = session.bytes;
      expect(session.revision, 1);
      final rejected = portable.wordShadingPlan('''
$_second.BackgroundPatternColorIndex = wdYellow
ActiveDocument.Paragraphs(99).Shading.BackgroundPatternColor = wdColorAutomatic
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(action(rejected), throwsA(_failure(1)));
        expect(session.bytes, saved);
        expect(session.revision, 1);
      }
      await expectLater(
        session.callTool('docx.paragraphShading', {
          'paragraph': 99,
          'color': 'FFFFFF',
        }),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, saved);
      final recording = session.stopRecording();
      expect(recording.steps, hasLength(1));
      expect(recording.steps.single.arguments, {
        'paragraph': 0,
        'color': '010203',
      });
      final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await replay.run(OfficeMacro.parse(recording.encode()));
      expect(portable.wordShadingState(replay.bytes), [
        {...original[0], 'fill': '010203'},
        ...original.skip(1),
      ]);
      expect(replay.revision, 1);
      portable.assertWordShadingPackage(replay.bytes);
    },
  );

  test(
    'permissions and native step budgets apply before publication',
    () async {
      expect(await portable.runWordShadingPolicy(), {
        'atomicDenials': 6,
        'allowedSteps': 2,
      });
    },
  );

  test(
    'an empty paragraph can be shaded without adding text or runs',
    () async {
      final input = portable.wordShadingInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(
        portable.wordShadingPlan('''
ActiveDocument.Paragraphs(3).Range.Shading.BackgroundPatternColor = RGB(1, 2, 3)
'''),
      );
      final paragraph = WordDeserializer()
          .readBytes(session.bytes)
          .paragraphs
          .elementAt(2);
      expect(paragraph.text, isEmpty);
      expect(paragraph.properties.shadingFill, '010203');
      expect(paragraph.inlines.whereType<WmlRun>(), isEmpty);
      expect(
        portable.wordShadingState(session.bytes).take(2),
        portable.wordShadingState(input).take(2),
      );
    },
  );

  test(
    'a linked header refuses without publishing earlier body shading',
    () async {
      WmlParagraph paragraph(String text) =>
          WmlParagraph(inlines: [WmlRun(text: text)]);
      final input = WordSerializer().writeBytes(
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [paragraph('First')],
              header: [paragraph('Header')],
              linkToPrevious: false,
            ),
            WmlSection(blocks: [paragraph('Second')], linkToPrevious: true),
          ],
        ),
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordShadingPlan('''
$_first.BackgroundPatternColorIndex = wdYellow
ThisDocument.Sections(2).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Shading.BackgroundPatternColorIndex = wdRed
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(action(plan), throwsA(_failure(1)));
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
    },
  );

  test('pre-cancelled shading publishes no edit', () async {
    final input = portable.wordShadingInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    await expectLater(
      session.run(
        portable.wordShadingSource(File(_example).readAsStringSync()),
        cancellation: OfficeMacroCancellation()..cancel(),
      ),
      throwsA(
        isA<OfficeMacroException>().having(
          (error) => error.code,
          'code',
          'cancelled',
        ),
      ),
    );
    expect(session.bytes, input);
    expect(session.revision, 0);
  });

  test('MCP compiles, validates and runs the committed shading BAS', () async {
    final input = portable.wordShadingInput();
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
    expect(_structured(validated)['validatedOnly'], isTrue);
    expect(_structured(validated)['completedSteps'], 7);
    expect(session.bytes, input);
    expect(session.revision, 0);
    final executed = await adapter.callTool('office_macro_run', arguments);
    expect(executed['isError'], isFalse, reason: '$executed');
    expect(_structured(executed)['completedSteps'], 7);
    expect(session.revision, 1);
    portable.assertWordShadingExample(session.bytes);
  });

  test('MCP unsupported texture publishes no prefix macro', () async {
    final input = portable.wordShadingInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    final result = await OfficeMacroMcp(session).callTool(
      'office_macro_compile',
      _sourceArguments('''
Sub Main()
  $_first.BackgroundPatternColorIndex = wdYellow
  $_first.Texture = 0
End Sub
'''),
    );
    expect(result['isError'], isTrue);
    expect(_structured(result).containsKey('macro'), isFalse);
    final error = _structured(result)['error']! as Map<String, Object?>;
    expect(error['moduleName'], 'WordShadingIntegration');
    expect(error['line'], greaterThan(0));
    expect(session.bytes, input);
    expect(session.revision, 0);
  });

  test(
    'CLI compiles, validates, runs and preserves an existing output on failure',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'word-shading-cli-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordShadingInput());
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
      final plan = OfficeMacro.parse(File(compiledPath).readAsStringSync());
      expect(plan.steps, hasLength(7));
      expect(plan.steps.first.tool, 'docx.paragraphShading');
      expect(plan.steps.first.arguments['color'], '123456');
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
      expect(input.readAsBytesSync(), original);
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
      portable.assertWordShadingExample(saved);
      final guard = (await WordPackagePreservation.capture(
        original,
        input.path,
      ))!;
      await guard.validateSaved(saved);
      final invalid = File('${directory.path}/late-failure.bas')
        ..writeAsStringSync('''
Sub Main()
  $_first.BackgroundPatternColorIndex = wdYellow
  ActiveDocument.Paragraphs(99).Shading.BackgroundPatternColorIndex = wdRed
End Sub
''');
      final failed = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        invalid.path,
        output.path,
      ]);
      expect(failed.exitCode, isNot(0));
      expect(output.readAsBytesSync(), saved);
      expect(input.readAsBytesSync(), original);
    },
    timeout: officeMacroCliTestTimeout,
  );
}
