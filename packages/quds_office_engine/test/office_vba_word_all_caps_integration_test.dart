import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_all_caps_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_all_caps.bas';
const _range = 'ActiveDocument.Paragraphs(1).Range';

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'actual BAS validates, records, replays and preserves authored DOCM text',
    () async {
      final result = await portable.runWordAllCapsExample(
        File(_example).readAsStringSync(),
      );
      expect(result['operations'], 7);
      expect(result['revision'], 1);
      expect(result['recordedSteps'], 7);
      expect(result['additionalReopens'], 2);
      expect(result['opaqueVbaPreserved'], isTrue);
      expect(result['nativePartSha256'], hasLength(3));
    },
  );

  test(
    'late missing selector rolls back capital changes and recording',
    () async {
      final input = portable.wordAllCapsInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('No failed capitals');
      final plan = portable.wordAllCapsPlan('''
$_range.Font.AllCaps = True
$_range.Font.SmallCaps = True
ActiveDocument.Paragraphs(99).Range.Font.AllCaps = False
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(
            isA<OfficeMacroException>()
                .having((e) => e.stepIndex, 'step', 2)
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
    OfficeMacroPolicy(allowedTools: {'docx.paragraphFormat'}),
    OfficeMacroPolicy(maxSteps: 1),
  ]) {
    test('capital formatting retains ordinary macro policy: $policy', () async {
      final input = portable.wordAllCapsInput();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      await expectLater(
        session.run(
          portable.wordAllCapsPlan('''
$_range.Font.AllCaps = True
$_range.Font.SmallCaps = True
'''),
        ),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    });
  }

  test(
    'empty text refuses AllCaps without establishing insertion formatting',
    () async {
      final input = WordSerializer().writeBytes(WmlDocument.empty());
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await expectLater(
        session.run(portable.wordAllCapsPlan('$_range.Font.AllCaps = True')),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test(
    'insertion before AllCaps formats current text and preserves its case',
    () async {
      final input = WordSerializer().writeBytes(WmlDocument.empty());
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(
        portable.wordAllCapsPlan('''
$_range.InsertBefore "Straße 😀"
$_range.Font.AllCaps = True
'''),
      );
      final paragraph = WordDeserializer()
          .readBytes(session.bytes)
          .paragraphs
          .single;
      expect(paragraph.text, 'Straße 😀');
      expect(
        paragraph.inlines.whereType<WmlRun>().every(
          (r) => r.properties.allCaps,
        ),
        isTrue,
      );
    },
  );

  test(
    'a linked header is refused without publishing prior body formatting',
    () async {
      WmlParagraph paragraph(String text) =>
          WmlParagraph(inlines: [WmlRun(text: text)]);
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [paragraph('First')],
            header: [paragraph('Header')],
            linkToPrevious: false,
          ),
          WmlSection(blocks: [paragraph('Second')], linkToPrevious: true),
        ],
      );
      final input = WordSerializer().writeBytes(document);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await expectLater(
        session.run(
          portable.wordAllCapsPlan('''
$_range.Font.AllCaps = True
ThisDocument.Sections(2).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range.Font.AllCaps = True
'''),
        ),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test('pre-cancelled capitalization cannot publish edits', () async {
    final input = portable.wordAllCapsInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    await expectLater(
      session.run(
        portable.wordAllCapsSource(File(_example).readAsStringSync()),
        cancellation: OfficeMacroCancellation()..cancel(),
      ),
      throwsA(
        isA<OfficeMacroException>().having((e) => e.code, 'code', 'cancelled'),
      ),
    );
    expect(session.bytes, input);
    expect(session.revision, 0);
  });

  test('source AllCaps executes through existing MCP envelopes', () async {
    final input = portable.wordAllCapsInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    final adapter = OfficeMacroMcp(session);
    final compiled = await adapter.callTool('office_macro_compile', {
      'source': {
        'language': 'vba-word',
        'format': 'docx',
        'moduleName': 'WordAllCaps',
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
    expect(_structured(executed)['completedSteps'], 7);
    final state = portable.wordAllCapsState(session.bytes);
    expect(state.first['text'], 'Straße ﬃ 😀');
    expect((state.first['runs']! as List<Object?>).single, {
      'text': 'Straße ﬃ 😀',
      'allCaps': true,
      'smallCaps': false,
      'size': 24,
      'color': '2468AC',
      'language': 'de-DE',
    });
  });

  test(
    'CLI compiles, validates, runs and preserves output on late failure',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'word-all-caps-cli-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordAllCapsInput());
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
      expect(plan.steps.first.arguments['allCaps'], isTrue);
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
      expect(input.readAsBytesSync(), original);
      final saved = output.readAsBytesSync();
      final state = portable.wordAllCapsState(saved);
      expect(state.last['text'], 'État العربية');
      expect((state.last['runs']! as List<Object?>).single, {
        'text': 'État العربية',
        'allCaps': true,
        'smallCaps': false,
        'size': 24,
        'color': '2468AC',
        'language': 'de-DE',
      });
      final guard = (await WordPackagePreservation.capture(
        original,
        input.path,
      ))!;
      await guard.validateSaved(saved);
      final invalid = File('${directory.path}/late-failure.bas')
        ..writeAsStringSync('''
Sub Main()
  $_range.Font.AllCaps = True
  ActiveDocument.Paragraphs(99).Range.Font.AllCaps = False
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
