import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_proofing_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_proofing_controls.bas';
const _range = 'ActiveDocument.Paragraphs(1).Range';

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'committed BAS validates, records, replays and preserves DOCM',
    () async {
      final result = await portable.runWordProofingExample(
        File(_example).readAsStringSync(),
      );
      expect(result['operations'], 9);
      expect(result['revision'], 1);
      expect(result['recordedSteps'], 9);
      expect(result['additionalReopens'], 2);
      expect(result['opaqueVbaPreserved'], isTrue);
    },
  );

  test(
    'late missing paragraph rolls back all three setters and recording',
    () async {
      final input = portable.wordProofingInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Successful operations only');
      final plan = portable.wordProofingPlan('''
$_range.NoProofing = False
$_range.ParagraphFormat.Hyphenation = True
$_range.Font.Kerning = 12.5
ActiveDocument.Paragraphs(99).Range.NoProofing = False
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(
            isA<OfficeMacroException>()
                .having((e) => e.stepIndex, 'step', 3)
                .having((e) => e.tool, 'tool', 'docx.runFormat'),
          ),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  for (final policy in [
    OfficeMacroPolicy(allowMutation: false),
    OfficeMacroPolicy(allowedTools: {'docx.runFormat'}),
    OfficeMacroPolicy(allowedTools: {'docx.paragraphFormat'}),
    OfficeMacroPolicy(maxSteps: 2),
  ]) {
    test(
      'ordinary mutation policy applies to proofing controls: $policy',
      () async {
        final input = portable.wordProofingInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
          policy: policy,
        );
        final plan = portable.wordProofingPlan('''
$_range.NoProofing = False
$_range.ParagraphFormat.Hyphenation = True
$_range.Font.Kerning = 12
''');
        await expectLater(
          session.run(plan),
          throwsA(isA<OfficeMacroException>()),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      },
    );
  }

  test(
    'compiled Hyphenation controls actual layout without changing text or settings',
    () async {
      final document = WmlDocument.empty(text: 'Silbentrennung')
        ..proofingLanguage = 'de-DE'
        ..autoHyphenation = true;
      document.sections.single.pageSize = const WmlPageSize(
        width: 80,
        height: 180,
      );
      document.sections.single.margins = const WmlPageMargins(
        left: 10,
        right: 10,
        top: 10,
        bottom: 10,
      );
      final session = OfficeMacroSession(
        WordSerializer().writeBytes(document),
        format: OfficeMacroFormat.docx,
      );
      for (final allowed in [false, true, false]) {
        await session.run(
          portable.wordProofingPlan(
            '$_range.ParagraphFormat.Hyphenation = ${allowed ? 'True' : 'False'}',
          ),
        );
        final reopened = WordDeserializer().readBytes(session.bytes);
        expect(reopened.autoHyphenation, isTrue);
        expect(reopened.paragraphs.single.text, 'Silbentrennung');
        final glyphs = WordLayoutEngine(font: null)
            .layout(reopened)
            .pages
            .expand((p) => p.lines)
            .expand((line) => line.glyphs);
        expect(glyphs.any((g) => g.glyph.isDiscretionaryHyphen), allowed);
      }
    },
  );

  test(
    'run controls refuse empty text without setting paragraph insertion format',
    () async {
      final input = WordSerializer().writeBytes(WmlDocument.empty());
      for (final write in ['NoProofing = True', 'Font.Kerning = 12']) {
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await expectLater(
          session.run(portable.wordProofingPlan('$_range.$write')),
          throwsA(isA<OfficeMacroException>()),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
    },
  );

  test(
    'MCP compiles and executes the committed BAS through existing tools',
    () async {
      final input = portable.wordProofingInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final adapter = OfficeMacroMcp(session);
      final compiled = await adapter.callTool('office_macro_compile', {
        'source': {
          'language': 'vba-word',
          'format': 'docx',
          'moduleName': 'WordProofingControls',
          'source': File(_example).readAsStringSync(),
        },
      });
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
      expect(session.bytes, input);
      final executed = await adapter.callTool('office_macro_run', arguments);
      expect(executed['isError'], isFalse, reason: '$executed');
      expect(_structured(executed)['completedSteps'], 9);
      expect(portable.wordProofingState(session.bytes).first['noProof'], [
        false,
      ]);
    },
  );

  test(
    'CLI validates and runs BAS while retaining its original DOCM',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'word-proofing-cli-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordProofingInput());
      final original = input.readAsBytesSync();
      final source = File(_example).absolute.path;
      final validate = await runOfficeMacroCli([
        'validate-word-vba',
        input.path,
        source,
      ]);
      expect(
        validate.exitCode,
        0,
        reason: '${validate.stdout}\n${validate.stderr}',
      );
      expect(input.readAsBytesSync(), original);
      final output = File('${directory.path}/output.docm');
      final run = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source,
        output.path,
      ]);
      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
      expect(input.readAsBytesSync(), original);
      expect(
        portable
            .wordProofingState(output.readAsBytesSync())
            .first['kerningHalfPoints'],
        [25],
      );
      final guard = (await WordPackagePreservation.capture(
        original,
        input.path,
      ))!;
      await guard.validateSaved(output.readAsBytesSync());
    },
    timeout: officeMacroCliTestTimeout,
  );
}
