@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_line_spacing_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _target = 'ActiveDocument.Paragraphs(1).Format';
const _example = 'example/macros/word_line_spacing.bas';
const _w = OfficeNamespaces.w;

List<WmlParagraph> _paragraphs(Uint8List bytes) =>
    WordDeserializer().readBytes(bytes).paragraphs.toList();

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _sourceArguments(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'LineSpacing',
    'source': source,
  },
};

Future<ProcessResult> _cli(List<String> arguments) =>
    runOfficeMacroCli(arguments);

void main() {
  registerOfficeMacroCliCleanup();
  test(
    'actual spacing BAS publishes once and preserves DOCM through reopens',
    () async {
      final result = await portable.runWordLineSpacingExample(
        File(_example).readAsStringSync(),
      );
      expect(result['operations'], 6);
      expect(result['revision'], 1);
      expect(result['additionalReopens'], 2);
      expect(result['opaqueVbaPreserved'], isTrue);
    },
  );

  test('actual spacing BAS is repeatable on its own saved output', () async {
    final result = await portable.runWordLineSpacingExampleReplay(
      File(_example).readAsStringSync(),
    );
    expect(result['operationsPerRun'], 6);
    expect(result['revision'], 2);
    expect(result['sameSavedState'], isTrue);
  });

  test(
    'ordinary 1.15-line conversions retain exact twips through reopens',
    () async {
      final result = await portable.runWordLineSpacingDecimalConversions();
      expect(result['linesToPoints'], 13.8);
      expect(result['pointsToLines'], 1.15);
      expect(result['nativeLines'], ['276', '276', '23']);
      expect(result['savedMultiple'], 1.15);
      expect(result['additionalReopens'], 2);
    },
  );

  for (final scenario in portable.wordLineSpacingPresetGuardCases) {
    test(
      '${scenario.$1} refuses validation, execution and native recording',
      () async {
        await portable.assertWordLineSpacingPresetGuard(scenario);
      },
    );
  }

  for (final (constant, points, rule, amount, nativeLine, nativeRule) in [
    (
      'wdLineSpaceExactly',
      14.25,
      WmlLineSpacingRule.exact,
      14.25,
      '285',
      'exact',
    ),
    (
      'wdLineSpaceAtLeast',
      18.0,
      WmlLineSpacingRule.atLeast,
      18.0,
      '360',
      'atLeast',
    ),
    ('wdLineSpaceMultiple', 21.0, WmlLineSpacingRule.auto, 1.75, '420', 'auto'),
  ]) {
    test(
      '$constant pair resolves and preserves native unrelated spacing',
      () async {
        final input = portable.wordLineSpacingInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        final originalStates = portable.wordLineSpacingState(input);
        final plan = portable.wordLineSpacingPlan('''
With $_target
  .LineSpacingRule = $constant
  .LineSpacing = $points
End With
''');
        expect(plan.steps, hasLength(1));
        expect(plan.steps.single.tool, 'docx.lineSpacing');
        final validated = await session.validate(plan);
        expect(validated.validatedOnly, isTrue);
        expect(validated.completedSteps, 1);
        expect(session.bytes, input);
        expect(session.revision, 0);
        await session.run(OfficeMacro.parse(plan.encode()));
        expect(session.revision, 1);
        var saved = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          final paragraph = _paragraphs(saved).first;
          expect(paragraph.properties.lineSpacingRule, rule);
          expect(paragraph.properties.lineSpacing, amount);
          expect(paragraph.properties.keepTogether, isTrue);
          expect(paragraph.properties.justification, WmlJustification.right);
          expect(paragraph.properties.tabs.single.position, 72);
          expect(paragraph.properties.indent.right, 8);
          expect(
            paragraph.inlines.whereType<WmlRun>().single.properties.bold,
            isTrue,
          );
          final spacing = portable.wordLineSpacingXml(saved, 0);
          expect(spacing.getAttribute('line', namespaceUri: _w), nativeLine);
          expect(
            spacing.getAttribute('lineRule', namespaceUri: _w),
            nativeRule,
          );
          for (final entry in const {
            'before': '120',
            'after': '180',
            'beforeLines': '10',
            'afterLines': '20',
            'beforeAutospacing': '1',
            'afterAutospacing': '0',
          }.entries) {
            expect(
              spacing.getAttribute(entry.key, namespaceUri: _w),
              entry.value,
            );
          }
          expect(
            spacing.getAttribute(
              'line',
              namespaceUri: 'urn:line-spacing-example',
            ),
            'foreign-line',
          );
          expect(
            portable.wordLineSpacingState(saved).skip(1),
            originalStates.skip(1),
          );
          if (cycle < 2) {
            saved = WordSerializer().writeBytes(
              WordDeserializer().readBytes(saved),
            );
          }
        }
      },
    );
  }

  test(
    'paired selector survives alias rebinding and a ByVal helper boundary',
    () async {
      final input = portable.wordLineSpacingInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordLineSpacingSource('''
Sub Complete(ByVal target As ParagraphFormat, ByVal amount As Double)
  target.LineSpacing = amount
  Set target = ActiveDocument.Paragraphs(3).Format
End Sub
Sub Main()
  Dim target As ParagraphFormat
  Dim original As ParagraphFormat
  Dim points As Double
  Set target = ActiveDocument.Paragraphs(1).Range.ParagraphFormat
  Set original = target
  target.LineSpacingRule = wdLineSpaceExactly
  Set target = ActiveDocument.Paragraphs(2).Format
  points = Application.LinesToPoints(1.5)
  Complete amount:=points, target:=original
  target.LineSpacingRule = wdLineSpaceAtLeast
  target.LineSpacing = 15
End Sub
''');
      expect(plan.steps, hasLength(2));
      expect(plan.steps[0].arguments, {
        'paragraph': 0,
        'rule': 'exact',
        'points': 18.0,
      });
      expect(plan.steps[1].arguments, {
        'paragraph': 1,
        'rule': 'atLeast',
        'points': 15.0,
      });
      await session.run(plan);
      final state = portable.wordLineSpacingState(session.bytes);
      expect(state[0]['nativeLine'], '360');
      expect(state[0]['nativeRule'], 'exact');
      expect(state[1]['nativeLine'], '300');
      expect(state[1]['nativeRule'], 'atLeast');
      expect(state[2], portable.wordLineSpacingState(input)[2]);
      expect(state[3], portable.wordLineSpacingState(input)[3]);
    },
  );

  for (final (statement, multiple, line) in [
    ('Space1', 1.0, '240'),
    ('Call target.Space15', 1.5, '360'),
    ('Call target.Space2()', 2.0, '480'),
  ]) {
    test(
      '$statement replaces an earlier custom rule in operation order',
      () async {
        final input = portable.wordLineSpacingInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        final method = statement.startsWith('Call ')
            ? statement
            : 'target.$statement';
        final plan = portable.wordLineSpacingPlan('''
Dim target As ParagraphFormat
Set target = $_target
target.LineSpacingRule = wdLineSpaceAtLeast
target.LineSpacing = 18
$method
''');
        expect(plan.steps, hasLength(2));
        await session.run(plan);
        final first = _paragraphs(session.bytes).first;
        expect(first.properties.lineSpacing, multiple);
        expect(first.properties.lineSpacingRule, WmlLineSpacingRule.auto);
        final spacing = portable.wordLineSpacingXml(session.bytes, 0);
        expect(spacing.getAttribute('line', namespaceUri: _w), line);
        expect(spacing.getAttribute('lineRule', namespaceUri: _w), 'auto');
        expect(spacing.getAttribute('before', namespaceUri: _w), '120');
        expect(spacing.getAttribute('after', namespaceUri: _w), '180');
      },
    );
  }

  test(
    'same-value multiple write owns the line while styles retain spacing',
    () async {
      final session = OfficeMacroSession(
        portable.wordLineSpacingInput(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        portable.wordLineSpacingPlan('''
With ActiveDocument.Paragraphs(2).Format
  .LineSpacingRule = wdLineSpaceMultiple
  .LineSpacing = LinesToPoints(2)
End With
'''),
      );
      var spacing = portable.wordLineSpacingXml(session.bytes, 1);
      expect(spacing.getAttribute('line', namespaceUri: _w), '480');
      expect(spacing.getAttribute('before', namespaceUri: _w), isNull);
      expect(spacing.getAttribute('after', namespaceUri: _w), isNull);
      final package = OpcPackage.openBytes(session.bytes);
      final styles = package.getPart('/word/styles.xml')!;
      styles.writeText(
        styles
            .readText()
            .replaceAll('w:before="180"', 'w:before="400"')
            .replaceAll('w:after="240"', 'w:after="600"')
            .replaceAll('w:line="480"', 'w:line="240"'),
      );
      var saved = package.save();
      for (var cycle = 0; cycle < 3; cycle++) {
        final document = WordDeserializer().readBytes(saved);
        final paragraph = document.paragraphs.elementAt(1);
        expect(paragraph.properties.lineSpacing, 2);
        expect(paragraph.properties.lineSpacingRule, WmlLineSpacingRule.auto);
        expect(paragraph.properties.spacingBefore, 20);
        expect(paragraph.properties.spacingAfter, 30);
        spacing = portable.wordLineSpacingXml(saved, 1);
        expect(spacing.getAttribute('before', namespaceUri: _w), isNull);
        expect(spacing.getAttribute('after', namespaceUri: _w), isNull);
        if (cycle < 2) saved = WordSerializer().writeBytes(document);
      }
    },
  );

  test(
    'source custom pairs preserve policy and the native tool allowlist',
    () async {
      final result = await portable.runWordLineSpacingPolicies();
      expect(result['refusedPolicies'], 3);
      expect(result['completeAllowlistRevision'], 1);
    },
  );

  test(
    'one custom pair is one native step under the session step limit',
    () async {
      final input = portable.wordLineSpacingInput();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: OfficeMacroPolicy(
          maxSteps: 1,
          allowedTools: {'docx.lineSpacing'},
        ),
      );
      final plan = portable.wordLineSpacingPlan('''
$_target.LineSpacingRule = wdLineSpaceExactly
$_target.LineSpacing = 14.25
''');
      final result = await session.run(plan);
      expect(result.completedSteps, 1);
      expect(session.revision, 1);
      expect(
        portable.wordLineSpacingState(session.bytes).first['nativeLine'],
        '285',
      );
      await portable.assertWordLineSpacingRefusal(
        input,
        portable.wordLineSpacingPlan('$_target.Space1'),
        policy: OfficeMacroPolicy(allowedTools: {'docx.lineSpacing'}),
        code: 'permission_denied',
      );
    },
  );

  test(
    'late missing paragraph rolls back custom spacing and earlier formatting',
    () async {
      final result = await portable.runWordLineSpacingRollback();
      expect(result['failedStep'], 2);
      expect(result['validateAndRunRollback'], isTrue);
    },
  );

  test(
    'failed later plan preserves an already published revision and recording',
    () async {
      final session = OfficeMacroSession(
        portable.wordLineSpacingInput(),
        format: OfficeMacroFormat.docx,
      );
      session.startRecording('Successful previous revision');
      await session.callTool('docx.lineSpacing', {
        'paragraph': 0,
        'rule': 'exact',
        'points': 14.25,
      });
      final saved = session.bytes;
      final bad = portable.wordLineSpacingPlan('''
With $_target
  .LineSpacingRule = wdLineSpaceMultiple
  .LineSpacing = LinesToPoints(3)
End With
ActiveDocument.Paragraphs(99).Format.Space1
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(bad),
          throwsA(
            isA<OfficeMacroException>()
                .having((error) => error.stepIndex, 'step', 1)
                .having((error) => error.tool, 'tool', 'docx.paragraphFormat'),
          ),
        );
        expect(session.bytes, saved);
        expect(session.revision, 1);
      }
      final recorded = session.stopRecording();
      expect(recorded.steps, hasLength(1));
      expect(recorded.steps.single.arguments['points'], 14.25);
    },
  );

  test(
    'native recording preserves all modes and excludes a failed call',
    () async {
      final result = await portable.runWordLineSpacingRecording();
      expect(result['recordedSteps'], 3);
      expect(result['failedCallExcluded'], isTrue);
      expect(result['replayRevision'], 1);
    },
  );

  test(
    'MCP compiles the exact example then validates and runs the same plan',
    () async {
      final input = portable.wordLineSpacingInput();
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
      expect(_structured(validation)['completedSteps'], 6);
      expect(_structured(validation)['validatedOnly'], isTrue);
      expect(session.bytes, input);
      expect(session.revision, 0);
      final result = await adapter.callTool('office_macro_run', arguments);
      expect(result['isError'], isFalse, reason: '$result');
      expect(_structured(result)['completedSteps'], 6);
      expect(session.revision, 1);
      expect(
        portable
            .wordLineSpacingState(session.bytes)
            .take(3)
            .map((state) => [state['nativeLine'], state['nativeRule']]),
        [
          ['285', 'exact'],
          ['360', 'atLeast'],
          ['420', 'auto'],
        ],
      );
    },
  );

  test(
    'MCP unresolved custom rule returns no prefix plan or session edits',
    () async {
      final input = portable.wordLineSpacingInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final adapter = OfficeMacroMcp(session);
      final result = await adapter.callTool(
        'office_macro_compile',
        _sourceArguments('''
Sub Main()
  ActiveDocument.Paragraphs(1).Range.Font.Bold = True
  $_target.LineSpacingRule = wdLineSpaceExactly
End Sub
'''),
      );
      expect(result['isError'], isTrue);
      expect(_structured(result).containsKey('macro'), isFalse);
      final error = _structured(result)['error']! as Map<String, Object?>;
      expect(error['moduleName'], 'LineSpacing');
      expect(error['line'], greaterThan(0));
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test(
    'actual CLI executes committed spacing BAS into a preserved DOCM',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'quds-line-spacing-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordLineSpacingInput());
      final before = input.readAsBytesSync();
      final output = File('${directory.path}/result.docm');
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
      final states = portable.wordLineSpacingState(output.readAsBytesSync());
      expect(states.take(3).map((state) => state['amount']), [
        14.25,
        18.0,
        1.75,
      ]);
      expect(states.last, portable.wordLineSpacingState(before).last);
    },
  );
}
