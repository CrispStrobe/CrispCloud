import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_position_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_font_position.bas';
const _font = 'ActiveDocument.Paragraphs(1).Range.Font';

Map<String, Object?> _structured(Map<String, Object?> value) =>
    value['structuredContent']! as Map<String, Object?>;

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'actual BAS validates, replays, rolls back and retains inert DOCM parts',
    () async {
      final result = await portable.runWordPositionExample(
        File(_example).readAsStringSync(),
      );
      expect(result['operations'], 5);
      expect(result['revision'], 2);
      expect(result['recordedSteps'], 5);
      expect(result['additionalReopens'], 2);
      expect(result['opaquePartsPreserved'], isTrue);
      expect(result['lateRollback'], isTrue);
      expect(result['policyRefusals'], 3);
    },
  );

  test(
    'position never invents paragraph-mark formatting in empty text',
    () async {
      final input = WordSerializer().writeBytes(WmlDocument.empty());
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await expectLater(
        session.run(portable.wordPositionPlan('$_font.Position = 1')),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test(
    'MCP compiles and executes Font.Position through the existing catalog',
    () async {
      final input = portable.wordPositionInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final adapter = OfficeMacroMcp(session);
      final compiled = await adapter.callTool('office_macro_compile', {
        'source': {
          'language': 'vba-word',
          'format': 'docx',
          'moduleName': 'WordFontPosition',
          'source': File(_example).readAsStringSync(),
        },
      });
      expect(compiled['isError'], isFalse, reason: '$compiled');
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
      final reopened = WordDeserializer().readBytes(session.bytes);
      expect(
        reopened.paragraphs.first.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .positionHalfPoints,
        6,
      );
    },
  );

  test(
    'CLI validates, compiles and runs BAS without modifying its input',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'word-position-cli-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordPositionInput());
      final original = input.readAsBytesSync();
      final source = File(_example).absolute.path;
      final compiled = File('${directory.path}/position.qudsmacro.json');
      final compile = await runOfficeMacroCli([
        'compile-word-vba',
        source,
        compiled.path,
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '${compile.stdout}\n${compile.stderr}',
      );
      expect(
        OfficeMacro.parse(compiled.readAsStringSync()).steps,
        hasLength(5),
      );
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
      final output = File('${directory.path}/output.docm');
      final run = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source,
        output.path,
      ]);
      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
      expect(input.readAsBytesSync(), original);
      final guard = (await WordPackagePreservation.capture(
        original,
        input.path,
      ))!;
      await guard.validateSaved(output.readAsBytesSync());
      final saved = output.readAsBytesSync();
      final invalid = File('${directory.path}/invalid.bas')
        ..writeAsStringSync(
          'Sub Main()\n$_font.Position = 1\nActiveDocument.Paragraphs(99).Range.Font.Position = -2\nEnd Sub',
        );
      final failure = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        invalid.path,
        output.path,
      ]);
      expect(failure.exitCode, isNot(0));
      expect(output.readAsBytesSync(), saved);
      expect(input.readAsBytesSync(), original);
    },
    timeout: officeMacroCliTestTimeout,
  );
}
