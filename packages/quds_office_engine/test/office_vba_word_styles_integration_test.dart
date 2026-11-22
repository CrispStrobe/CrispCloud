import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_styles_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_styles.bas';

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'committed BAS preserves formatting, opaque DOCM and repeated reopens',
    () async {
      final result = await portable.runWordStylesExample(
        File(_example).readAsStringSync(),
      );
      expect(result, {
        'operations': 5,
        'revision': 2,
        'additionalReopens': 2,
        'opaquePayloadsPreserved': true,
      });
    },
  );

  test(
    'late missing style rolls back execution, validation and recording',
    () async {
      expect(await portable.runWordStylesRollback(), {
        'failedStep': 1,
        'validateAndRunRollback': true,
      });
    },
  );

  test('native style recording excludes failed calls and replays', () async {
    expect(await portable.runWordStylesRecording(), {
      'recordedSteps': 2,
      'failedCallExcluded': true,
      'replayRevision': 1,
    });
  });

  test('style permissions, allowlists and step limits remain atomic', () async {
    expect(await portable.runWordStylesPolicy(), {
      'atomicDenials': 6,
      'allowedSteps': 2,
    });
  });

  test('helper rebinding retains the caller header selector', () async {
    final input = portable.wordStylesInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    final macro = portable.wordStylesSource('''
Sub Configure(ByVal target As Range)
  target.Style = wdStyleCaption
  Set target = ActiveDocument.Paragraphs(1).Range
  target.Style = wdStyleHeading1
End Sub
Sub Main()
  Dim head As Range
  Set head = ThisDocument.Sections(1).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range
  Configure target:=head
  head.Style = "Report Body"
End Sub
''');
    await session.validate(macro);
    expect(session.bytes, input);
    await session.run(macro);
    var document = WordDeserializer().readBytes(session.bytes);
    for (var cycle = 0; cycle < 2; cycle++) {
      expect(
        document.sections.first.header.single.properties.styleId,
        'BodyCustom',
      );
      expect(document.paragraphs.first.properties.styleId, 'HeadingNative');
      expect(document.paragraphs.elementAt(1).properties.styleId, isNull);
      expect(document.paragraphs.elementAt(2).properties.styleId, isNull);
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
    }
  });

  test(
    'later missing header keeps earlier committed bytes and revision',
    () async {
      final session = OfficeMacroSession(
        portable.wordStylesInput(),
        format: OfficeMacroFormat.docx,
      );
      await session.callTool('docx.paragraphStyle', {
        'paragraph': 1,
        'name': 'Report Body',
      });
      final before = session.bytes;
      final macro = portable.wordStylesPlan('''
ActiveDocument.Paragraphs(1).Style = wdStyleHeading1
ActiveDocument.Sections(2).Headers(1).Range.Paragraphs(1).Style = wdStyleCaption
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(macro),
          throwsA(
            isA<OfficeMacroException>().having(
              (error) => error.stepIndex,
              'failed step',
              1,
            ),
          ),
        );
        expect(session.bytes, before);
        expect(session.revision, 1);
      }
    },
  );

  test('MCP compiles, validates and runs the same style source', () async {
    final input = portable.wordStylesInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    final adapter = OfficeMacroMcp(session);
    final compiled = await adapter.callTool('office_macro_compile', {
      'source': {
        'language': 'vba-word',
        'format': 'docx',
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
    expect(_structured(validation)['completedSteps'], 5);
    expect(session.bytes, input);
    expect(session.revision, 0);
    final result = await adapter.callTool('office_macro_run', arguments);
    expect(result['isError'], isFalse, reason: '$result');
    portable.assertWordStylesExample(session.bytes);
    expect(session.revision, 1);
  });

  test('CLI executes committed BAS without mutating its input', () async {
    final directory = Directory.systemTemp.createTempSync('quds-style-cli-');
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
    expect(input.readAsBytesSync(), before);
    portable.assertWordStylesExample(output.readAsBytesSync());
  }, timeout: officeMacroCliTestTimeout);

  test('CLI late style failure creates no output file', () async {
    final directory = Directory.systemTemp.createTempSync('quds-style-fail-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final input = File('${directory.path}/input.docm')
      ..writeAsBytesSync(portable.wordStylesInput());
    final before = input.readAsBytesSync();
    final source = File('${directory.path}/missing.bas')
      ..writeAsStringSync('''
Sub Main()
  ActiveDocument.Paragraphs(1).Style = wdStyleHeading1
  ActiveDocument.Paragraphs(2).Style = "No such style"
End Sub
''');
    final output = File('${directory.path}/output.docm');
    final result = await runOfficeMacroCli([
      'run-word-vba',
      input.path,
      source.path,
      output.path,
    ]);
    expect(result.exitCode, isNot(0));
    final report = jsonDecode(result.stderr as String) as Map<String, Object?>;
    final error = report['error']! as Map<String, Object?>;
    expect(error['code'], 'operation_failed');
    expect(error['stepIndex'], 1);
    expect(error['tool'], 'docx.paragraphStyle');
    expect(input.readAsBytesSync(), before);
    expect(output.existsSync(), isFalse);
  }, timeout: officeMacroCliTestTimeout);
}
