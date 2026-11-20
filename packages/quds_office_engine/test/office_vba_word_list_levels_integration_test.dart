import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_list_levels_smoke.dart' as portable;

const _target = 'ActiveDocument.Paragraphs(1).Range.ListFormat';

List<WmlParagraph> _paragraphs(Uint8List bytes) =>
    WordDeserializer().readBytes(bytes).paragraphs.toList();

void main() {
  test(
    'actual outline BAS publishes once and preserves DOCM through two reopens',
    () async {
      final source = File(
        'example/macros/word_list_levels.bas',
      ).readAsStringSync();
      final result = await portable.runWordListLevelExample(source);
      expect(result['operations'], 13);
      expect(result['revision'], 1);
      expect(result['additionalReopens'], 2);
      expect(result['opaqueVbaPreserved'], isTrue);
    },
  );

  test(
    'actual outline BAS can run on its own output with the same saved state',
    () async {
      final source = File(
        'example/macros/word_list_levels.bas',
      ).readAsStringSync();
      final result = await portable.runWordListLevelExampleReplay(source);
      expect(result['operationsPerRun'], 13);
      expect(result['revision'], 2);
      expect(result['sameSavedState'], isTrue);
    },
  );

  test(
    'all nine levels, relative moves and outline toggles retain their contract',
    () async {
      final result = await portable.runWordListLevelTransitions();
      expect(result['absoluteLevels'], 9);
      expect(result['relativeLevels'], [7, 8]);
      expect(result['retainedListIdentity'], isTrue);
      expect(result['toggleOffRetainsIndent'], isTrue);
      expect(result['toggleOnLevel'], 0);
      expect(result['revision'], 14);
    },
  );

  for (final bullet in [false, true]) {
    final kind = bullet ? 'bullet' : 'numbered';
    test(
      'raw imported $kind nodes and IDs survive serialization and reopens',
      () async {
        final result = await portable.runWordListLevelRawImport(bullet: bullet);
        expect(result['retainedNumId'], 37);
        expect(result['existingNodesPreserved'], isTrue);
        expect(result['additionalReopens'], 2);
      },
    );
    for (var level = 0; level < 9; level++) {
      test(
        'setting imported $kind level ${level + 1} retains identity and definitions',
        () async {
          final input = portable.wordListLevelImportedInput(
            level: level == 0 ? 1 : 0,
            bullet: bullet,
          );
          final definitions = portable.wordListLevelNumbering(input);
          final untouched = portable.wordListLevelState(input).last;
          final guard = (await WordPackagePreservation.capture(
            input,
            'imported-levels.docm',
          ))!;
          final session = OfficeMacroSession(
            input,
            format: OfficeMacroFormat.docx,
          );
          final plan = portable.wordListLevelPlan('''
Dim target As ListFormat
Set target = ActiveDocument.Paragraphs(1).Range.ListFormat
With target
  .ListLevelNumber = ${level + 1}
End With
''');
          final validated = await session.validate(plan);
          expect(validated.validatedOnly, isTrue);
          expect(validated.completedSteps, 1);
          expect(session.revision, 0);
          expect(session.bytes, input);
          await session.run(OfficeMacro.parse(plan.encode()));
          expect(session.revision, 1);
          var saved = session.bytes;
          for (var cycle = 0; cycle < 3; cycle++) {
            await guard.validateSaved(saved);
            final state = portable.wordListLevelState(saved);
            expect(state.first['numId'], 37);
            expect(state.first['level'], level);
            expect(state.first['format'], bullet ? 'bullet' : 'decimal');
            expect(state.first['label'], bullet ? '•' : '[%${level + 1}]');
            expect(state.first['leftTwips'], 600 + level * 240);
            expect(state.first['rightTwips'], 140);
            expect(state.first['firstLineTwips'], 0);
            expect(state.first['hangingTwips'], 120 + level * 20);
            expect(state.first['suppressed'], isFalse);
            expect(state.last, untouched);
            expect(portable.wordListLevelNumbering(saved), definitions);
            final paragraph = _paragraphs(saved).first;
            expect(paragraph.text, 'Imported selected item');
            expect(paragraph.properties.keepTogether, isTrue);
            expect(paragraph.properties.spacingBefore, 6);
            expect(
              paragraph.inlines.whereType<WmlRun>().first.properties.bold,
              isTrue,
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

    for (final (method, initial, finalLevel) in [
      ('ListIndent', 0, 1),
      ('ListOutdent', 8, 7),
    ]) {
      test(
        '$method uses imported $kind target geometry without replacing it',
        () async {
          final input = portable.wordListLevelImportedInput(
            level: initial,
            bullet: bullet,
          );
          final definitions = portable.wordListLevelNumbering(input);
          final untouched = portable.wordListLevelState(input).last;
          final session = OfficeMacroSession(
            input,
            format: OfficeMacroFormat.docx,
          );
          await session.run(
            portable.wordListLevelPlan('Call $_target.$method()'),
          );
          final state = portable.wordListLevelState(session.bytes);
          expect(state.first['numId'], 37);
          expect(state.first['level'], finalLevel);
          expect(state.first['leftTwips'], 600 + finalLevel * 240);
          expect(state.first['rightTwips'], 140);
          expect(state.first['hangingTwips'], 120 + finalLevel * 20);
          expect(state.last, untouched);
          expect(portable.wordListLevelNumbering(session.bytes), definitions);
        },
      );
    }
  }

  for (final method in ['ApplyBulletDefault', 'ApplyNumberDefault']) {
    test(
      'outline application replaces $method with a navigable outline',
      () async {
        final input = portable.wordListLevelInput();
        final untouched = portable.wordListLevelState(input).last;
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await session.run(
          portable.wordListLevelPlan('''
$_target.$method
$_target.ApplyOutlineNumberDefault DefaultListBehavior:=wdWord8ListBehavior
$_target.ListLevelNumber = 9
'''),
        );
        var saved = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          final state = portable.wordListLevelState(saved);
          expect(state.first['level'], 8);
          expect(state.first['format'], 'decimal');
          expect(state.first['definedLevels'], 9);
          expect(state.first['label'], '%1.%2.%3.%4.%5.%6.%7.%8.%9.');
          expect(state.first['leftTwips'], 3240);
          expect(state.first['rightTwips'], 240);
          expect(state.first['hangingTwips'], 180);
          expect(state.last, untouched);
          if (cycle < 2) {
            saved = WordSerializer().writeBytes(
              WordDeserializer().readBytes(saved),
            );
          }
        }
      },
    );
  }

  for (final operation in [
    'ListLevelNumber = 2',
    'ListIndent',
    'ListOutdent',
  ]) {
    test(
      '$operation refuses an unnumbered paragraph without publication',
      () async {
        await portable.assertWordListLevelRefusal(
          portable.wordListLevelInput(),
          portable.wordListLevelPlan('$_target.$operation'),
          stepIndex: 0,
          tool: 'docx.listLevel',
        );
      },
    );
  }

  for (final (level, method) in [(0, 'ListOutdent'), (8, 'ListIndent')]) {
    test(
      '$method refuses the level ${level + 1} boundary atomically',
      () async {
        await portable.assertWordListLevelRefusal(
          portable.wordListLevelImportedInput(level: level),
          portable.wordListLevelPlan('$_target.$method'),
          stepIndex: 0,
          tool: 'docx.listLevel',
        );
      },
    );
  }

  for (final operation in ['ListLevelNumber = 2', 'ListIndent']) {
    test(
      '$operation refuses a missing target and rolls back earlier formatting',
      () async {
        await portable.assertWordListLevelRefusal(
          portable.wordListLevelImportedInput(omitLevel: 1),
          portable.wordListLevelPlan('''
ActiveDocument.Paragraphs(2).Range.ParagraphFormat.SpaceAfter = 12
$_target.$operation
'''),
          stepIndex: 1,
          tool: 'docx.listLevel',
        );
      },
    );
  }

  test(
    'late missing paragraph rolls back outline creation and level change',
    () async {
      await portable.assertWordListLevelRefusal(
        portable.wordListLevelInput(),
        portable.wordListLevelPlan('''
$_target.ApplyOutlineNumberDefault
$_target.ListLevelNumber = 4
ActiveDocument.Paragraphs(99).Range.ListFormat.ListIndent
'''),
        stepIndex: 2,
        tool: 'docx.listLevel',
      );
    },
  );

  test(
    'level change following a pending native restart refuses the whole plan',
    () async {
      final sourceStep = portable
          .wordListLevelPlan('$_target.ListIndent')
          .steps
          .single;
      await portable.assertWordListLevelRefusal(
        portable.wordListLevelImportedInput(),
        OfficeMacro(
          name: 'Pending restart',
          format: OfficeMacroFormat.docx,
          steps: [
            OfficeMacroStep(
              tool: 'docx.listRestart',
              arguments: {'paragraph': 0, 'at': 4},
            ),
            sourceStep,
          ],
        ),
        stepIndex: 1,
        tool: 'docx.listLevel',
      );
    },
  );

  for (final (label, policy, code) in <(String, OfficeMacroPolicy, String)>[
    ('read-only', OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
    (
      'outline-only',
      OfficeMacroPolicy(allowedTools: {'docx.listOutlineDefault'}),
      'permission_denied',
    ),
    (
      'level-only',
      OfficeMacroPolicy(allowedTools: {'docx.listLevel'}),
      'permission_denied',
    ),
    ('step-limit', OfficeMacroPolicy(maxSteps: 1), 'limit_exceeded'),
  ]) {
    test('outline source preserves the $label policy restriction', () async {
      await portable.assertWordListLevelRefusal(
        portable.wordListLevelInput(),
        portable.wordListLevelPlan('''
$_target.ApplyOutlineNumberDefault
$_target.ListLevelNumber = 3
'''),
        policy: policy,
        code: code,
      );
    });
  }

  test(
    'both new tools can be allowlisted without permitting other mutations',
    () async {
      final input = portable.wordListLevelInput();
      final policy = OfficeMacroPolicy(
        allowedTools: {'docx.listOutlineDefault', 'docx.listLevel'},
      );
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      final plan = portable.wordListLevelPlan('''
$_target.ApplyOutlineNumberDefault
$_target.ListLevelNumber = 3
''');
      final validated = await session.validate(plan);
      expect(validated.validatedOnly, isTrue);
      expect(validated.completedSteps, 2);
      expect(session.revision, 0);
      expect(session.bytes, input);
      await session.run(plan);
      expect(session.revision, 1);
      expect(portable.wordListLevelState(session.bytes).first['level'], 2);
      await portable.assertWordListLevelRefusal(
        input,
        portable.wordListLevelPlan(
          'ActiveDocument.Paragraphs(1).Range.ParagraphFormat.SpaceAfter = 12',
        ),
        policy: policy,
        code: 'permission_denied',
      );
    },
  );

  test(
    'recording retains successful native calls and excludes a failed move',
    () async {
      final result = await portable.runWordListLevelRecording();
      expect(result['recordedSteps'], 2);
      expect(result['failedCallExcluded'], isTrue);
      expect(result['replayRevision'], 1);
    },
  );
}
