import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_page_setup_smoke.dart' as fixture;
import '../tool/macros/web_vba_word_sections_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_sections.bas';
const _first = 'ActiveDocument.Sections(1).PageSetup';
const _second = 'ActiveDocument.Sections(2).PageSetup';
const _w = OfficeNamespaces.w;

Uint8List _editInput(String Function(String) transform) {
  final package = OpcPackage.openBytes(fixture.wordPageSetupInput());
  final part = package.getPart('/word/document.xml')!;
  final before = part.readText();
  final after = transform(before);
  expect(after, isNot(before), reason: 'Fixture must alter its intended XML');
  part.writeText(after);
  return package.save();
}

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _sourceArguments(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'WordSectionsIntegration',
    'source': source,
  },
};

Matcher _failure({int? step, String? tool, String code = 'operation_failed'}) {
  var matcher = isA<OfficeMacroException>().having(
    (error) => error.code,
    'code',
    code,
  );
  if (step != null) {
    matcher = matcher.having((error) => error.stepIndex, 'step', step);
  }
  if (tool != null) {
    matcher = matcher.having((error) => error.tool, 'tool', tool);
  }
  return matcher;
}

void main() {
  registerOfficeMacroCliCleanup();

  test('native fractional geometry stays stable and fails atomically', () {
    final result = portable.runWordSectionsPrecision();
    expect(result['cases'], hasLength(3));
    expect(result['atomicRoundedBodyFailures'], 2);
  });

  test(
    'actual BAS preserves selected sections and DOCM across reopens',
    () async {
      final result = await portable.runWordSectionsExample(
        File(_example).readAsStringSync(),
      );
      expect(result['operations'], 7);
      expect(result['firstRunRevision'], 1);
      expect(result['repeatedRevision'], 2);
      expect(result['additionalReopens'], 2);
      expect(result['opaquePayloadsPreserved'], isTrue);
    },
  );

  test(
    'ByVal rebinding retains caller Section and PageSetup selectors',
    () async {
      final plan = portable.wordSectionsSource('''
Sub Edit(ByVal section As Section, ByVal page As PageSetup)
  section.PageSetup.Orientation = wdOrientLandscape
  Set section = ActiveDocument.Sections(3)
  page.SectionStart = wdSectionEvenPage
  Set page = section.PageSetup
  page.Orientation = wdOrientLandscape
End Sub
Sub Main()
  Dim first As Section
  Dim page As PageSetup
  Set first = ThisDocument.Sections.Item(1)
  Set page = Application.ActiveDocument.Sections(2).PageSetup
  Edit page:=page, section:=first
  first.PageSetup.SectionStart = wdSectionOddPage
  page.TogglePortrait
End Sub
''');
      expect(plan.steps.map((step) => step.arguments['section']), [
        0,
        1,
        2,
        0,
        1,
      ]);
      final session = OfficeMacroSession(
        fixture.wordPageSetupInput(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(plan);
      final state = fixture.wordPageSetupState(session.bytes);
      expect(state.map((section) => section['width']), [792, 800, 900]);
      expect(state.map((section) => section['height']), [612, 600, 700]);
      expect(state.map((section) => section['break']), [
        'oddPage',
        'evenPage',
        'nextPage',
      ]);
      expect(session.revision, 1);
      fixture.assertWordPageSetupPackage(session.bytes);
    },
  );

  for (final (constant, kind) in [
    ('wdSectionContinuous', 'continuous'),
    ('wdSectionNewPage', 'nextPage'),
    ('wdSectionEvenPage', 'evenPage'),
    ('wdSectionOddPage', 'oddPage'),
  ]) {
    test(
      '$constant persists its native break without changing geometry',
      () async {
        final input = fixture.wordPageSetupInput();
        final original = fixture.wordPageSetupState(input);
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await session.run(
          portable.wordSectionsPlan('$_second.SectionStart = $constant'),
        );
        var saved = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(fixture.wordPageSetupState(saved), [
            original[0],
            {...original[1], 'break': kind},
            original[2],
          ]);
          expect(
            fixture
                .wordPageSetupSection(saved, 1)
                .firstChild('type', namespaceUri: _w)!
                .getAttribute('val', namespaceUri: _w),
            kind,
          );
          fixture.assertWordPageSetupPackage(saved);
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
    'orientation setters and successive toggles observe detached state',
    () async {
      final input = fixture.wordPageSetupInput();
      final original = fixture.wordPageSetupState(input);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(
        portable.wordSectionsPlan('''
$_first.Orientation = wdOrientLandscape
Call $_first.TogglePortrait()
$_first.TogglePortrait
$_second.SectionStart = wdSectionOddPage
$_second.SectionStart = wdSectionContinuous
'''),
      );
      expect(fixture.wordPageSetupState(session.bytes), [
        {...original[0], 'width': 792, 'height': 612},
        original[1],
        original[2],
      ]);
      expect(session.revision, 1);
      final first = fixture
          .wordPageSetupSection(session.bytes, 0)
          .firstChild('pgSz', namespaceUri: _w)!;
      expect(first.getAttribute('orient', namespaceUri: _w), 'landscape');
      expect(first.getAttribute('code', namespaceUri: _w), '9');
      fixture.assertWordPageSetupPackage(session.bytes);
    },
  );

  test('square orientation survives save and guides a later toggle', () async {
    final input = _editInput(
      (xml) => xml
          .replaceFirst('w:h="15840"', 'w:h="12240"')
          .replaceFirst('w:orient="portrait"', 'w:orient="landscape"'),
    );
    final firstRun = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    await firstRun.run(
      portable.wordSectionsPlan('$_first.Orientation = wdOrientPortrait'),
    );
    final saved = WordSerializer().writeBytes(
      WordDeserializer().readBytes(firstRun.bytes),
    );
    final portrait = fixture
        .wordPageSetupSection(saved, 0)
        .firstChild('pgSz', namespaceUri: _w)!;
    expect(portrait.getAttribute('orient', namespaceUri: _w), 'portrait');
    expect(portrait.getAttribute('w', namespaceUri: _w), '12240');
    expect(portrait.getAttribute('h', namespaceUri: _w), '12240');
    final reopened = OfficeMacroSession(saved, format: OfficeMacroFormat.docx);
    await reopened.run(portable.wordSectionsPlan('$_first.TogglePortrait'));
    final landscape = fixture
        .wordPageSetupSection(reopened.bytes, 0)
        .firstChild('pgSz', namespaceUri: _w)!;
    expect(landscape.getAttribute('orient', namespaceUri: _w), 'landscape');
    expect(
      fixture.wordPageSetupState(reopened.bytes),
      fixture.wordPageSetupState(input),
    );
    fixture.assertWordPageSetupPackage(reopened.bytes);
  });

  test(
    'same-value orientation retains dimensions and native paper identity',
    () async {
      final input = fixture.wordPageSetupInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(
        portable.wordSectionsPlan('$_first.Orientation = wdOrientPortrait'),
      );
      expect(
        fixture.wordPageSetupState(session.bytes),
        fixture.wordPageSetupState(input),
      );
      final size = fixture
          .wordPageSetupSection(session.bytes, 0)
          .firstChild('pgSz', namespaceUri: _w)!;
      expect(size.getAttribute('code', namespaceUri: _w), '9');
      expect(size.getAttribute('orient', namespaceUri: _w), 'portrait');
      expect(
        size.getAttribute('w', namespaceUri: 'urn:word-page-setup-example'),
        'foreign-width',
      );
      fixture.assertWordPageSetupPackage(session.bytes);
    },
  );

  test(
    'late missing section rolls back dry-run, execution and recording',
    () async {
      final result = await portable.runWordSectionsRollback();
      expect(result['failedStep'], 1);
      expect(result['validateAndRunRollback'], isTrue);
    },
  );

  test(
    'landscape that exhausts body height rolls back an earlier break edit',
    () async {
      final input = _editInput(
        (xml) => xml.replaceFirst(
          'w:top="1440" w:bottom="1440"',
          'w:top="7000" w:bottom="7000"',
        ),
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordSectionsPlan('''
$_second.SectionStart = wdSectionOddPage
$_first.Orientation = wdOrientLandscape
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(_failure(step: 1, tool: 'docx.pageOrientation')),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
    },
  );

  for (final (label, attribute) in [
    ('unknown orientation', 'w:orient="diagonal"'),
    ('duplicate orientation', 'w:orient="portrait" w:orient="landscape"'),
    ('non-square orientation mismatch', 'w:orient="landscape"'),
  ]) {
    test('$label declines the entire detached source plan', () async {
      final input = _editInput(
        (xml) => xml.replaceFirst('w:orient="portrait"', attribute),
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordSectionsPlan('''
$_second.SectionStart = wdSectionOddPage
$_first.Orientation = wdOrientLandscape
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(_failure(step: 1, tool: 'docx.pageOrientation')),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
    });
  }

  test(
    'duplicate section break rolls back a preceding orientation change',
    () async {
      final input = _editInput(
        (xml) => xml.replaceFirst(
          '<w:pgSz ',
          '<w:type w:val="continuous"/><w:type w:val="oddPage"/><w:pgSz ',
        ),
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordSectionsPlan('''
$_second.Orientation = wdOrientLandscape
$_first.SectionStart = wdSectionNewPage
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(_failure(step: 1, tool: 'docx.sectionStart')),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
    },
  );

  test(
    'failure retains a previously accepted revision and recording',
    () async {
      final session = OfficeMacroSession(
        fixture.wordPageSetupInput(),
        format: OfficeMacroFormat.docx,
      );
      session.startRecording('Accepted orientation');
      await session.callTool('docx.pageOrientation', {
        'section': 0,
        'orientation': 'landscape',
      });
      final before = session.bytes;
      final plan = portable.wordSectionsPlan('''
$_first.SectionStart = wdSectionOddPage
ActiveDocument.Sections(99).PageSetup.SectionStart = wdSectionEvenPage
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(_failure(step: 1, tool: 'docx.sectionStart')),
        );
        expect(session.bytes, before);
        expect(session.revision, 1);
      }
      final recording = session.stopRecording();
      expect(recording.steps, hasLength(1));
      expect(recording.steps.single.tool, 'docx.pageOrientation');
    },
  );

  test(
    'cancellation after orientation rolls back and leaves session usable',
    () async {
      final input = fixture.wordPageSetupInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final cancellation = OfficeMacroCancellation();
      final plan = portable.wordSectionsPlan('''
$_first.Orientation = wdOrientLandscape
$_second.SectionStart = wdSectionEvenPage
''');
      final pending = session.run(plan, cancellation: cancellation);
      Timer.run(cancellation.cancel);
      await expectLater(
        pending,
        throwsA(
          _failure(step: 1, tool: 'docx.sectionStart', code: 'cancelled'),
        ),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      expect(session.revision, 1);
    },
  );

  test('both new native operation allowlists govern source playback', () async {
    final result = await portable.runWordSectionsPolicy();
    expect(result['bothNativeAllowlistsEnforced'], isTrue);
    expect(result['denialsPublishNothing'], isTrue);
  });

  test(
    'mutation permission and step budget govern validation and execution',
    () async {
      final input = fixture.wordPageSetupInput();
      final plan = portable.wordSectionsPlan('''
$_first.Orientation = wdOrientLandscape
$_second.SectionStart = wdSectionEvenPage
''');
      for (final (policy, code) in <(OfficeMacroPolicy, String)>[
        (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
        (OfficeMacroPolicy(maxSteps: 1), 'limit_exceeded'),
      ]) {
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
          policy: policy,
        );
        for (final action in [session.validate, session.run]) {
          await expectLater(action(plan), throwsA(_failure(code: code)));
          expect(session.bytes, input);
          expect(session.revision, 0);
        }
      }
      final allowed = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: OfficeMacroPolicy(
          allowedTools: {'docx.pageOrientation', 'docx.sectionStart'},
          maxSteps: 2,
        ),
      );
      final dryRun = await allowed.validate(plan);
      expect(dryRun.validatedOnly, isTrue);
      expect(allowed.bytes, input);
      expect((await allowed.run(plan)).completedSteps, 2);
      expect(allowed.revision, 1);
    },
  );

  test(
    'native recording excludes failures and replays exact selectors',
    () async {
      final result = await portable.runWordSectionsRecording();
      expect(result['recordedSteps'], 2);
      expect(result['failedCallExcluded'], isTrue);
      expect(result['replayRevision'], 1);
    },
  );

  test(
    'MCP compiles the actual BAS and validates/runs the same native plan',
    () async {
      final input = fixture.wordPageSetupInput();
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
      expect(_structured(validated)['completedSteps'], 7);
      expect(_structured(validated)['validatedOnly'], isTrue);
      expect(session.bytes, input);
      expect(session.revision, 0);
      final result = await adapter.callTool('office_macro_run', arguments);
      expect(result['isError'], isFalse, reason: '$result');
      expect(_structured(result)['completedSteps'], 7);
      expect(session.revision, 1);
      portable.assertWordSectionsExample(session.bytes);
    },
  );

  for (final statement in [
    'Orientation = 2',
    'SectionStart = wdSectionNewColumn',
    'TogglePortrait True',
  ]) {
    test('MCP rejects $statement without publishing a prefix plan', () async {
      final input = fixture.wordPageSetupInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final result = await OfficeMacroMcp(session).callTool(
        'office_macro_compile',
        _sourceArguments('''
Sub Main()
  $_first.Orientation = wdOrientLandscape
  $_second.$statement
End Sub
'''),
      );
      expect(result['isError'], isTrue);
      expect(_structured(result).containsKey('macro'), isFalse);
      final error = _structured(result)['error']! as Map<String, Object?>;
      expect(error['moduleName'], 'WordSectionsIntegration');
      expect(error['line'], greaterThan(0));
      expect(error['column'], greaterThan(0));
      expect(session.bytes, input);
      expect(session.revision, 0);
    });
  }

  test(
    'CLI runs the committed BAS and preserves input and opaque DOCM data',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'quds-word-sections-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(fixture.wordPageSetupInput());
      final before = input.readAsBytesSync();
      final output = File('${directory.path}/output.docm');
      final result = await runOfficeMacroCli([
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
      final saved = output.readAsBytesSync();
      final guard = (await WordPackagePreservation.capture(
        before,
        input.path,
      ))!;
      await guard.validateSaved(saved);
      portable.assertWordSectionsExample(saved);
    },
    timeout: officeMacroCliTestTimeout,
  );

  test(
    'CLI late missing section creates no output and leaves input unchanged',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'quds-sections-failure-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(fixture.wordPageSetupInput());
      final before = input.readAsBytesSync();
      final source = File('${directory.path}/invalid.bas')
        ..writeAsStringSync('''
Sub Main()
  $_first.Orientation = wdOrientLandscape
  ActiveDocument.Sections(99).PageSetup.SectionStart = wdSectionNewPage
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
      expect(input.readAsBytesSync(), before);
      expect(output.existsSync(), isFalse);
    },
    timeout: officeMacroCliTestTimeout,
  );
}
