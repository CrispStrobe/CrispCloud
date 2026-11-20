import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_paragraph_controls_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _target = 'ActiveDocument.Paragraphs(1)';
const _example = 'example/macros/word_paragraph_controls.bas';
const _w = OfficeNamespaces.w;

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _sourceArguments(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'ParagraphControls',
    'source': source,
  },
};

Future<ProcessResult> _cli(List<String> arguments) =>
    runOfficeMacroCli(arguments);

Uint8List _changePart(String path, String Function(String) transform) {
  final package = OpcPackage.openBytes(portable.wordParagraphControlsInput());
  final part = package.getPart(path)!;
  final source = part.readText();
  final changed = transform(source);
  expect(
    changed,
    isNot(source),
    reason: 'Fixture must alter its intended part',
  );
  part.writeText(changed);
  return package.save();
}

Uint8List _beforeAttribute(String attribute) => _changePart(
  '/word/document.xml',
  (source) => source.replaceFirst('w:before="120"', attribute),
);

void main() {
  registerOfficeMacroCliCleanup();
  test('actual BAS publishes once and preserves DOCM across reopens', () async {
    final result = await portable.runWordParagraphControlsExample(
      File(_example).readAsStringSync(),
    );
    expect(result['operations'], 10);
    expect(result['revision'], 1);
    expect(result['additionalReopens'], 2);
    expect(result['opaqueVbaPreserved'], isTrue);
  });

  test('actual BAS is repeatable on its own saved output', () async {
    final result = await portable.runWordParagraphControlsExampleReplay(
      File(_example).readAsStringSync(),
    );
    expect(result['operationsPerRun'], 10);
    expect(result['revision'], 2);
    expect(result['sameSavedState'], isTrue);
  });

  for (final receiver in [_target, '$_target.Range.ParagraphFormat']) {
    for (final (method, action, expected) in [
      ('OpenUp', 'open', 12),
      ('CloseUp', 'close', 0),
      ('OpenOrCloseUp', 'toggle', 0),
    ]) {
      test(
        '$receiver.$method resolves before spacing and preserves XML',
        () async {
          final input = portable.wordParagraphControlsInput();
          final untouched = portable.wordParagraphControlsState(input).skip(1);
          final plan = portable.wordParagraphControlsPlan(
            'Call $receiver.$method()',
          );
          expect(plan.steps, hasLength(1));
          expect(plan.steps.single.tool, 'docx.paragraphSpaceBefore');
          expect(plan.steps.single.arguments, {
            'paragraph': 0,
            'action': action,
          });
          final session = OfficeMacroSession(
            input,
            format: OfficeMacroFormat.docx,
          );
          final dryRun = await session.validate(plan);
          expect(dryRun.validatedOnly, isTrue);
          expect(dryRun.completedSteps, 1);
          expect(session.bytes, input);
          expect(session.revision, 0);
          await session.run(OfficeMacro.parse(plan.encode()));
          expect(session.revision, 1);
          var saved = session.bytes;
          for (var cycle = 0; cycle < 3; cycle++) {
            final document = WordDeserializer().readBytes(saved);
            final paragraph = document.paragraphs.first;
            final spacing = portable.wordParagraphControlsSpacing(saved, 0);
            expect(paragraph.properties.spacingBefore, expected);
            expect(
              spacing.getAttribute('before', namespaceUri: _w),
              '${expected * 20}',
            );
            expect(paragraph.properties.spacingAfter, 9);
            expect(paragraph.properties.lineSpacing, 15);
            expect(
              paragraph.properties.lineSpacingRule,
              WmlLineSpacingRule.exact,
            );
            expect(paragraph.properties.keepTogether, isTrue);
            expect(paragraph.properties.justification, WmlJustification.right);
            expect(paragraph.properties.indent.right, 8);
            expect(paragraph.properties.tabs.single.position, 72);
            expect(
              paragraph.inlines.whereType<WmlRun>().single.properties.bold,
              isTrue,
            );
            for (final entry in const {
              'after': '180',
              'afterLines': '20',
              'afterAutospacing': '1',
              'line': '300',
              'lineRule': 'exact',
            }.entries) {
              expect(
                spacing.getAttribute(entry.key, namespaceUri: _w),
                entry.value,
              );
            }
            expect(
              spacing.getAttribute('beforeAutospacing', namespaceUri: _w),
              isIn([null, '0', 'false', 'off']),
            );
            expect(
              spacing.getAttribute(
                'before',
                namespaceUri: 'urn:paragraph-controls-example',
              ),
              'foreign-before',
            );
            expect(
              portable.wordParagraphControlsState(saved).skip(1),
              untouched,
            );
            portable.assertWordParagraphControlsMacroParts(saved);
            if (cycle < 2) saved = WordSerializer().writeBytes(document);
          }
        },
      );
    }
  }

  test(
    'two toggles and earlier writes read detached execution state',
    () async {
      final result = await portable.runWordParagraphControlsSequentialToggles();
      expect(result['operations'], 6);
      expect(result['before'], [12, 12, 0]);
      expect(result['revision'], 1);
    },
  );

  test(
    'same-value open owns before while later style edits retain inheritance',
    () async {
      final result = await portable.runWordParagraphControlsStyleOwnership();
      expect(result['before'], 12);
      expect(result['after'], 30);
      expect(result['line'], 2);
      expect(result['untouchedBefore'], 20);
      expect(result['additionalReopens'], 2);
    },
  );

  test(
    'ByVal aliases and helper rebinding retain their selected paragraph',
    () async {
      final plan = portable.wordParagraphControlsSource('''
Sub Edit(ByVal target As Paragraph, ByVal format As ParagraphFormat)
  target.CloseUp
  Set target = ActiveDocument.Paragraphs(3)
  format.OpenUp
  Set format = target.Format
  format.OpenOrCloseUp
End Sub
Sub Main()
  Dim first As Paragraph
  Dim format As ParagraphFormat
  Set first = ActiveDocument.Paragraphs(1)
  Set format = ActiveDocument.Paragraphs(2).Format
  Call Edit(format:=format, target:=first)
  first.OpenUp
  format.CloseUp
End Sub
''');
      expect(plan.steps.map((step) => step.arguments['paragraph']), [
        0,
        1,
        2,
        0,
        1,
      ]);
      final session = OfficeMacroSession(
        portable.wordParagraphControlsInput(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(plan);
      expect(
        portable
            .wordParagraphControlsState(session.bytes)
            .take(3)
            .map((state) => state['before']),
        [12, 0, 12],
      );
      expect(session.revision, 1);
    },
  );

  test('native policies, allowlists and step limits remain enforced', () async {
    final result = await portable.runWordParagraphControlsPolicies();
    expect(result['refusedPolicies'], 3);
    expect(result['completeAllowlistRevision'], 1);
  });

  test('one source toggle counts as exactly one native step', () async {
    final session = OfficeMacroSession(
      portable.wordParagraphControlsInput(),
      format: OfficeMacroFormat.docx,
      policy: OfficeMacroPolicy(
        maxSteps: 1,
        allowedTools: {'docx.paragraphSpaceBefore'},
      ),
    );
    final result = await session.run(
      portable.wordParagraphControlsPlan('$_target.OpenOrCloseUp'),
    );
    expect(result.completedSteps, 1);
    expect(session.revision, 1);
    expect(
      portable.wordParagraphControlsState(session.bytes).first['before'],
      0,
    );
  });

  test(
    'late missing paragraph rolls back earlier controls and formatting',
    () async {
      final result = await portable.runWordParagraphControlsRollback();
      expect(result['failedStep'], 2);
      expect(result['validateAndRunRollback'], isTrue);
    },
  );

  test('late failure preserves an earlier revision and recording', () async {
    final session = OfficeMacroSession(
      portable.wordParagraphControlsInput(),
      format: OfficeMacroFormat.docx,
    );
    session.startRecording('Previous successful revision');
    await session.callTool('docx.paragraphSpaceBefore', {
      'paragraph': 0,
      'action': 'open',
    });
    final saved = session.bytes;
    final bad = portable.wordParagraphControlsPlan('''
$_target.CloseUp
ActiveDocument.Paragraphs(99).Format.OpenUp
''');
    for (final action in [session.validate, session.run]) {
      await expectLater(
        action(bad),
        throwsA(
          isA<OfficeMacroException>()
              .having((error) => error.stepIndex, 'step', 1)
              .having(
                (error) => error.tool,
                'tool',
                'docx.paragraphSpaceBefore',
              ),
        ),
      );
      expect(session.bytes, saved);
      expect(session.revision, 1);
    }
    final recorded = session.stopRecording();
    expect(recorded.steps, hasLength(1));
    expect(recorded.steps.single.arguments['action'], 'open');
  });

  test(
    'recording excludes failure and replay resolves toggle against its target',
    () async {
      final result = await portable.runWordParagraphControlsRecording();
      expect(result['recordedSteps'], 3);
      expect(result['failedCallExcluded'], isTrue);
      expect(result['replayRevision'], 1);
      expect(result['toggleReadsReplayTarget'], isTrue);
    },
  );

  for (final (name, attribute) in const [
    ('line-unit before', 'w:before="120" w:beforeLines="10"'),
    ('negative before', 'w:before="-1"'),
    ('fractional before', 'w:before="1.5"'),
    ('non-numeric before', 'w:before="bad"'),
    ('overflow before', 'w:before="2147483648"'),
  ]) {
    test('$name refuses validation/run before publication', () async {
      await portable.assertWordParagraphControlsRefusal(
        _beforeAttribute(attribute),
        portable.wordParagraphControlsPlan('''
ActiveDocument.Paragraphs(2).Range.Font.Bold = True
$_target.OpenOrCloseUp
'''),
        stepIndex: 1,
        tool: 'docx.paragraphSpaceBefore',
      );
    });
  }

  for (final value in ['1', 'true', 'on', 'unknown']) {
    test(
      'automatic before $value refuses source controls atomically',
      () async {
        final input = _changePart(
          '/word/document.xml',
          (source) => source.replaceFirst(
            'w:beforeAutospacing="0"',
            'w:beforeAutospacing="$value"',
          ),
        );
        await portable.assertWordParagraphControlsRefusal(
          input,
          portable.wordParagraphControlsPlan('$_target.OpenUp'),
          stepIndex: 0,
          tool: 'docx.paragraphSpaceBefore',
        );
      },
    );
  }

  for (final (name, path, before, after) in const [
    (
      'inherited beforeLines',
      '/word/styles.xml',
      'w:before="240"',
      'w:before="240" w:beforeLines="10"',
    ),
    (
      'inherited automatic before',
      '/word/styles.xml',
      'w:before="240"',
      'w:before="240" w:beforeAutospacing="1"',
    ),
    (
      'duplicate direct spacing',
      '/word/document.xml',
      '<w:tabs>',
      '<w:spacing w:before="0"/><w:tabs>',
    ),
    (
      'unbalanced field in another paragraph',
      '/word/document.xml',
      '<w:t>Untouched paragraph</w:t>',
      '<w:fldChar w:fldCharType="begin"/><w:instrText>PAGE</w:instrText>'
          '<w:t>Untouched paragraph</w:t>',
    ),
    (
      'markup compatibility spacing alternative',
      '/word/document.xml',
      '</w:pPr>',
      '<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">'
          '<mc:Choice Requires="x"><w:spacing w:before="0"/></mc:Choice>'
          '<mc:Fallback><w:spacing w:before="240"/></mc:Fallback>'
          '</mc:AlternateContent></w:pPr>',
    ),
  ]) {
    test('$name refuses source playback and native recording', () async {
      final input = _changePart(
        path,
        (source) => source.replaceFirst(before, after),
      );
      await portable.assertWordParagraphControlsRefusal(
        input,
        portable.wordParagraphControlsPlan('$_target.CloseUp'),
        stepIndex: 0,
        tool: 'docx.paragraphSpaceBefore',
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Rejected controls');
      await expectLater(
        session.callTool('docx.paragraphSpaceBefore', {
          'paragraph': 0,
          'action': 'close',
        }),
        throwsA(
          isA<OfficeMacroException>().having(
            (error) => error.code,
            'code',
            'operation_failed',
          ),
        ),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
      expect(session.stopRecording().steps, isEmpty);
    });
  }

  test('MCP compiles exact BAS and validates/runs the same plan', () async {
    final input = portable.wordParagraphControlsInput();
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
    final validation = await adapter.callTool(
      'office_macro_validate',
      arguments,
    );
    expect(validation['isError'], isFalse, reason: '$validation');
    expect(_structured(validation)['completedSteps'], 10);
    expect(_structured(validation)['validatedOnly'], isTrue);
    expect(session.bytes, input);
    expect(session.revision, 0);
    final result = await adapter.callTool('office_macro_run', arguments);
    expect(result['isError'], isFalse, reason: '$result');
    expect(_structured(result)['completedSteps'], 10);
    expect(session.revision, 1);
    expect(
      portable
          .wordParagraphControlsState(session.bytes)
          .take(3)
          .map((state) => state['before']),
      [12, 0, 12],
    );
  });

  test(
    'MCP rejected method arguments return no prefix plan or document edit',
    () async {
      final input = portable.wordParagraphControlsInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final adapter = OfficeMacroMcp(session);
      final result = await adapter.callTool(
        'office_macro_compile',
        _sourceArguments('''
Sub Main()
  $_target.Range.Font.Bold = True
  $_target.OpenUp 12
End Sub
'''),
      );
      expect(result['isError'], isTrue);
      expect(_structured(result).containsKey('macro'), isFalse);
      final error = _structured(result)['error']! as Map<String, Object?>;
      expect(error['moduleName'], 'ParagraphControls');
      expect(error['line'], greaterThan(0));
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test(
    'actual CLI runs committed BAS and preserves opaque DOCM parts',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'quds-paragraph-controls-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordParagraphControlsInput());
      final before = input.readAsBytesSync();
      final output = File('${directory.path}/output.docm');
      final result = await _cli([
        'run-word-vba',
        input.path,
        File(_example).absolute.path,
        output.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final report =
          jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(report['language'], 'vba-word');
      expect(input.readAsBytesSync(), before);
      final guard = (await WordPackagePreservation.capture(
        before,
        input.path,
      ))!;
      await guard.validateSaved(output.readAsBytesSync());
      portable.assertWordParagraphControlsMacroParts(output.readAsBytesSync());
      final states = portable.wordParagraphControlsState(
        output.readAsBytesSync(),
      );
      expect(states.take(3).map((state) => state['before']), [12, 0, 12]);
      expect(states.last, portable.wordParagraphControlsState(before).last);
    },
    timeout: officeMacroCliTestTimeout,
  );

  test('CLI native refusal preserves input and never creates output', () async {
    final directory = Directory.systemTemp.createTempSync(
      'quds-paragraph-controls-refusal-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final input = File('${directory.path}/input.docm')
      ..writeAsBytesSync(_beforeAttribute('w:before="120" w:beforeLines="10"'));
    final original = input.readAsBytesSync();
    final output = File('${directory.path}/output.docm');
    final result = await _cli([
      'run-word-vba',
      input.path,
      File(_example).absolute.path,
      output.path,
    ]);
    expect(result.exitCode, isNot(0));
    expect(input.readAsBytesSync(), original);
    expect(output.existsSync(), isFalse);
  }, timeout: officeMacroCliTestTimeout);
}
