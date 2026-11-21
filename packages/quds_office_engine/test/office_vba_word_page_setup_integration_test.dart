import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_page_setup_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_page_setup.bas';
const _first = 'ActiveDocument.Sections(1).PageSetup';
const _second = 'ActiveDocument.Sections(2).PageSetup';
const _w = OfficeNamespaces.w;

Uint8List _editInput(String Function(String) transform) {
  final package = OpcPackage.openBytes(portable.wordPageSetupInput());
  final part = package.getPart('/word/document.xml')!;
  final before = part.readText();
  final after = transform(before);
  expect(after, isNot(before), reason: 'Fixture must change its intended XML');
  part.writeText(after);
  return package.save();
}

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _sourceArguments(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'PageSetupIntegration',
    'source': source,
  },
};

Matcher _failure({int? step, String code = 'operation_failed'}) {
  var matcher = isA<OfficeMacroException>().having(
    (error) => error.code,
    'code',
    code,
  );
  if (step != null) {
    matcher = matcher
        .having((error) => error.stepIndex, 'step', step)
        .having((error) => error.tool, 'tool', 'docx.pageSetup');
  }
  return matcher;
}

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'actual BAS edits selected sections and preserves DOCM through reopens',
    () async {
      final result = await portable.runWordPageSetupExample(
        File(_example).readAsStringSync(),
      );
      expect(result['operations'], 10);
      expect(result['firstRunRevision'], 1);
      expect(result['repeatedRevision'], 2);
      expect(result['additionalReopens'], 2);
      expect(result['opaquePayloadsPreserved'], isTrue);
    },
  );

  test(
    'ByVal rebinding preserves caller Section and PageSetup selectors',
    () async {
      final plan = portable.wordPageSetupSource('''
Sub Edit(ByVal section As Section, ByVal page As PageSetup)
  section.PageSetup.LeftMargin = 40
  Set section = ActiveDocument.Sections(3)
  page.RightMargin = 41
  Set page = section.PageSetup
  page.HeaderDistance = 42
End Sub
Sub Main()
  Dim first As Section
  Dim page As PageSetup
  Set first = ThisDocument.Sections.Item(1)
  Set page = Application.ActiveDocument.Sections(2).PageSetup
  Edit page:=page, section:=first
  first.PageSetup.TopMargin = 43
  page.FooterDistance = 44
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
        portable.wordPageSetupInput(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(plan);
      final state = portable.wordPageSetupState(session.bytes);
      expect(state[0]['left'], 40);
      expect(state[0]['top'], 43);
      expect(state[1]['right'], 41);
      expect(state[1]['footer'], 44);
      expect(state[2]['header'], 42);
      expect(session.revision, 1);
    },
  );

  test(
    'same-value margin owns only its attribute and preserves omitted defaults',
    () async {
      final input = _editInput(
        (xml) => xml
            .replaceFirst(' w:bottom="1440"', '')
            .replaceFirst(' w:header="720"', ''),
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(portable.wordPageSetupPlan('$_first.LeftMargin = 72'));
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final section = portable.wordPageSetupSection(saved, 0);
        final margins = section.firstChild('pgMar', namespaceUri: _w)!;
        final size = section.firstChild('pgSz', namespaceUri: _w)!;
        expect(margins.getAttribute('left', namespaceUri: _w), '1440');
        expect(margins.getAttribute('bottom', namespaceUri: _w), isNull);
        expect(margins.getAttribute('header', namespaceUri: _w), isNull);
        expect(margins.getAttribute('gutter', namespaceUri: _w), '0');
        expect(
          margins.getAttribute(
            'left',
            namespaceUri: 'urn:word-page-setup-example',
          ),
          'foreign-left',
        );
        expect(size.getAttribute('code', namespaceUri: _w), '9');
        expect(size.getAttribute('orient', namespaceUri: _w), 'portrait');
        final state = portable.wordPageSetupState(saved).first;
        expect(state['bottom'], 72);
        expect(state['header'], 36);
        portable.assertWordPageSetupPackage(saved);
        if (cycle < 2) {
          saved = WordSerializer().writeBytes(
            WordDeserializer().readBytes(saved),
          );
        }
      }
    },
  );

  test(
    'same-value dimensions clear paper code and retain orientation metadata',
    () async {
      for (final statement in ['PageWidth = 612', 'PageHeight = 792']) {
        final input = portable.wordPageSetupInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await session.run(portable.wordPageSetupPlan('$_first.$statement'));
        final size = portable
            .wordPageSetupSection(session.bytes, 0)
            .firstChild('pgSz', namespaceUri: _w)!;
        expect(size.getAttribute('w', namespaceUri: _w), '12240');
        expect(size.getAttribute('h', namespaceUri: _w), '15840');
        expect(size.getAttribute('code', namespaceUri: _w), isNull);
        expect(size.getAttribute('orient', namespaceUri: _w), 'portrait');
        expect(
          portable.wordPageSetupState(session.bytes),
          portable.wordPageSetupState(input),
        );
      }
    },
  );

  test(
    'geometry checks observe earlier detached edits and reject invalid order',
    () async {
      final input = portable.wordPageSetupInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final valid = portable.wordPageSetupPlan('''
$_second.LeftMargin = 0
$_second.RightMargin = 0
$_second.PageWidth = 1
''');
      await session.validate(valid);
      expect(session.bytes, input);
      await session.run(valid);
      expect(portable.wordPageSetupState(session.bytes)[1]['width'], 1);
      expect(portable.wordPageSetupState(session.bytes)[1]['left'], 0);
      expect(portable.wordPageSetupState(session.bytes)[1]['right'], 0);
      final invalidOrder = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
      );
      await expectLater(
        invalidOrder.run(
          portable.wordPageSetupPlan('''
$_second.PageWidth = 1
$_second.LeftMargin = 0
$_second.RightMargin = 0
'''),
        ),
        throwsA(_failure(step: 0)),
      );
      expect(invalidOrder.bytes, input);
      expect(invalidOrder.revision, 0);
    },
  );

  test('late geometry failure rolls back validation and execution', () async {
    final result = await portable.runWordPageSetupRollback();
    expect(result['failedStep'], 1);
    expect(result['validateAndRunRollback'], isTrue);
  });

  test(
    'late missing section preserves earlier revision and native recording',
    () async {
      final session = OfficeMacroSession(
        portable.wordPageSetupInput(),
        format: OfficeMacroFormat.docx,
      );
      session.startRecording('Earlier accepted edit');
      await session.callTool('docx.pageSetup', {
        'section': 0,
        'property': 'left',
        'points': 54,
      });
      final before = session.bytes;
      final plan = portable.wordPageSetupPlan('''
$_first.PageWidth = 648
ActiveDocument.Sections(99).PageSetup.HeaderDistance = 12
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(action(plan), throwsA(_failure(step: 1)));
        expect(session.bytes, before);
        expect(session.revision, 1);
      }
      final recording = session.stopRecording();
      expect(recording.steps, hasLength(1));
      expect(recording.steps.single.arguments['property'], 'left');
    },
  );

  test(
    'cancellation after the first edit rolls back and leaves session usable',
    () async {
      final input = portable.wordPageSetupInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final cancellation = OfficeMacroCancellation();
      final plan = portable.wordPageSetupPlan('''
$_first.PageWidth = 648
$_second.TopMargin = 45
''');
      final pending = session.run(plan, cancellation: cancellation);
      Timer.run(cancellation.cancel);
      await expectLater(pending, throwsA(_failure(step: 1, code: 'cancelled')));
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      expect(session.revision, 1);
    },
  );

  test(
    'mutation policy, allowlists and native step budgets still apply',
    () async {
      final input = portable.wordPageSetupInput();
      final plan = portable.wordPageSetupPlan('''
$_first.LeftMargin = 54
$_second.RightMargin = 36
''');
      for (final (policy, code) in <(OfficeMacroPolicy, String)>[
        (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
        (
          OfficeMacroPolicy(allowedTools: {'docx.paragraphFormat'}),
          'permission_denied',
        ),
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
          allowedTools: {'docx.pageSetup'},
          maxSteps: 2,
        ),
      );
      expect((await allowed.run(plan)).completedSteps, 2);
      expect(allowed.revision, 1);
    },
  );

  test(
    'native recording excludes failures and replay retains section selectors',
    () async {
      final result = await portable.runWordPageSetupRecording();
      expect(result['recordedSteps'], 2);
      expect(result['failedCallExcluded'], isTrue);
      expect(result['replayRevision'], 1);
    },
  );

  test(
    'positive body width is insufficient when uniform columns have no width',
    () async {
      final input = portable.wordPageSetupInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      // Two columns need positive space after their 18-point intercolumn gap.
      final plan = portable.wordPageSetupPlan('''
$_second.HeaderDistance = 12
$_first.PageWidth = 162
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(action(plan), throwsA(_failure(step: 1)));
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
    },
  );

  test(
    'MCP compiles actual BAS and validates/runs the identical native plan',
    () async {
      final input = portable.wordPageSetupInput();
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
      portable.assertWordPageSetupExample(session.bytes);
    },
  );

  test(
    'MCP unsupported paper size returns no prefix plan or document edit',
    () async {
      final input = portable.wordPageSetupInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final result = await OfficeMacroMcp(session).callTool(
        'office_macro_compile',
        _sourceArguments('''
Sub Main()
  $_first.LeftMargin = 54
  $_first.PaperSize = 0
End Sub
'''),
      );
      expect(result['isError'], isTrue);
      expect(_structured(result).containsKey('macro'), isFalse);
      final error = _structured(result)['error']! as Map<String, Object?>;
      expect(error['moduleName'], 'PageSetupIntegration');
      expect(error['line'], greaterThan(0));
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test(
    'CLI runs the committed BAS and preserves the input and opaque DOCM parts',
    () async {
      final directory = Directory.systemTemp.createTempSync('quds-page-setup-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordPageSetupInput());
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
      portable.assertWordPageSetupExample(saved);
    },
    timeout: officeMacroCliTestTimeout,
  );

  test(
    'CLI invalid late geometry never creates output or alters input',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'quds-page-setup-fail-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordPageSetupInput());
      final before = input.readAsBytesSync();
      final source = File('${directory.path}/invalid.bas')
        ..writeAsStringSync('''
Sub Main()
  $_first.RightMargin = 36
  $_second.PageWidth = 1
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
