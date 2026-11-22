import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_cell_paragraphs_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_table_paragraphs.bas';
const _first = 'ActiveDocument.Tables(1).Cell(1, 1).Range.Paragraphs(1)';
const _second = 'ActiveDocument.Tables(1).Cell(1, 2).Range.Paragraphs.Item(1)';
const _w = OfficeNamespaces.w;

Map<String, Object?> _structured(Map<String, Object?> response) =>
    response['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _source(String text) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'CellParagraphIntegration',
    'source': text,
  },
};

Future<void> _unchangedOnFailure(
  OfficeMacroSession session,
  OfficeMacro macro, {
  required int step,
  required String tool,
}) async {
  final bytes = session.bytes;
  final revision = session.revision;
  session.startRecording('Rejected table paragraph formatting');
  for (final action in [session.validate, session.run]) {
    await expectLater(
      action(macro),
      throwsA(
        isA<OfficeMacroException>()
            .having((error) => error.stepIndex, 'step', step)
            .having((error) => error.tool, 'tool', tool),
      ),
    );
    expect(session.bytes, bytes);
    expect(session.revision, revision);
  }
  expect(session.stopRecording().steps, isEmpty);
}

Uint8List _changed(void Function(WmlDocument) edit) {
  final document = WordDeserializer().readBytes(
    portable.wordCellParagraphInput(),
  );
  edit(document);
  return WordSerializer().writeBytes(document);
}

void main() {
  registerOfficeMacroCliCleanup();

  for (final macroEnabled in [false, true]) {
    test(
      '${macroEnabled ? 'DOCM' : 'DOCX'} table paragraph example validates, reopens and replays',
      () async {
        final result = await portable.runWordCellParagraphExample(
          File(_example).readAsStringSync(),
          macroEnabled: macroEnabled,
        );
        expect(result['operations'], 8);
        expect(result['revision'], 2);
        expect(result['recordedSteps'], 8);
        expect(result['additionalReopens'], 2);
        expect(result['untouchedLayoutAndParts'], isTrue);
        expect(result['opaqueVbaPreserved'], macroEnabled);
      },
    );
  }

  test(
    'ByVal paragraph rebinding preserves the original cell and its range alias',
    () async {
      final input = portable.wordCellParagraphInput();
      final plan = portable.wordCellParagraphSource('''
Sub Decorate(ByVal target As Paragraph)
  target.Style = "Report Label"
  Set target = $_second
  target.Shading.BackgroundPatternColorIndex = wdBlue
End Sub
Sub Main()
  Dim selected As Paragraph
  Dim selectedText As Range
  Set selected = $_first
  Set selectedText = selected.Range
  Decorate target:=selected
  selectedText.Shading.BackgroundPatternColorIndex = wdGreen
  selected.Style = wdStyleNormal
End Sub
''');
      expect(plan.steps.map((step) => step.arguments['column']), [0, 1, 0, 0]);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(plan);
      final cells = portable.wordCellParagraphState(session.bytes);
      expect(cells[0]['style'], 'NormalNative');
      expect(cells[0]['shading'], '008000');
      expect(cells[1]['shading'], '0000FF');
      expect(cells.skip(2), portable.wordCellParagraphState(input).skip(2));
      final reopened = WordSerializer().writeBytes(
        WordDeserializer().readBytes(session.bytes),
      );
      expect(portable.wordCellParagraphState(reopened), cells);
    },
  );

  for (final (label, source, tool) in <(String, String, String)>[
    (
      'missing later style',
      '''
$_first.Shading.BackgroundPatternColorIndex = wdYellow
$_second.Style = "Missing template style"
''',
      'docx.paragraphStyle',
    ),
    (
      'missing later cell',
      '''
$_first.Style = "Report Label"
ActiveDocument.Tables(2).Cell(2, 1).Range.Paragraphs(1).Shading.BackgroundPatternColorIndex = wdRed
''',
      'docx.paragraphShading',
    ),
  ]) {
    test(
      '$label rolls back validation, execution and recording after a saved revision',
      () async {
        final session = OfficeMacroSession(
          portable.wordCellParagraphInput(),
          format: OfficeMacroFormat.docx,
        );
        await session.run(
          portable.wordCellParagraphPlan('$_first.Style = wdStyleHeading1'),
        );
        expect(session.revision, 1);
        await _unchangedOnFailure(
          session,
          portable.wordCellParagraphPlan(source),
          step: 1,
          tool: tool,
        );
      },
    );
  }

  test(
    'unsupported second-cell shading refuses the complete source plan',
    () async {
      final package = OpcPackage.openBytes(portable.wordCellParagraphInput());
      final part = package.getPart('/word/document.xml')!;
      final xml = XmlDocument.parse(part.readText());
      final table = xml.root!
          .firstChild('body', namespaceUri: _w)!
          .childrenNamed('tbl', namespaceUri: _w)
          .first;
      final second = table
          .childrenNamed('tr', namespaceUri: _w)
          .first
          .childrenNamed('tc', namespaceUri: _w)
          .elementAt(1);
      final props = second
          .firstChild('p', namespaceUri: _w)!
          .firstChild('pPr', namespaceUri: _w)!;
      props.addChild(
        XmlDocument.parse(
          '<w:shd xmlns:w="$_w" w:val="pct25" w:color="111111" w:fill="DDEEFF"/>',
        ).root!,
      );
      part.writeText(xml.toXmlString());
      final session = OfficeMacroSession(
        package.save(),
        format: OfficeMacroFormat.docx,
      );
      await _unchangedOnFailure(
        session,
        portable.wordCellParagraphPlan('''
$_first.Style = "Report Label"
$_second.Shading.BackgroundPatternColorIndex = wdYellow
'''),
        step: 1,
        tool: 'docx.paragraphShading',
      );
    },
  );

  for (final (label, edit) in <(String, void Function(WmlDocument))>[
    ('restricted document', (document) => document.restrictEditing = true),
    ('change-tracked document', (document) => document.trackRevisions = true),
    (
      'multiple cell paragraphs',
      (document) {
        document.sections.first.blocks
            .whereType<WmlTable>()
            .first
            .rows
            .first
            .cells
            .first
            .blocks
            .add(
              WmlParagraph(inlines: [WmlRun(text: 'Second cell paragraph')]),
            );
      },
    ),
    (
      'merged table grid',
      (document) {
        document.sections.first.blocks
                .whereType<WmlTable>()
                .first
                .rows
                .first
                .cells
                .first
                .gridSpan =
            2;
      },
    ),
  ]) {
    test(
      '$label retains native cell guards and discards earlier body changes',
      () async {
        final session = OfficeMacroSession(
          _changed(edit),
          format: OfficeMacroFormat.docx,
        );
        final input = session.bytes;
        final plan = portable.wordCellParagraphPlan('''
ActiveDocument.Paragraphs(1).Range.Font.ColorIndex = wdRed
$_first.Style = "Report Label"
$_first.Shading.BackgroundPatternColorIndex = wdYellow
''');
        for (final action in [session.validate, session.run]) {
          await expectLater(action(plan), throwsA(isA<OfficeMacroException>()));
          expect(session.bytes, input);
          expect(session.revision, 0);
        }
      },
    );
  }

  for (final (label, policy) in [
    ('mutation denied', OfficeMacroPolicy(allowMutation: false)),
    (
      'tool allowlist',
      OfficeMacroPolicy(allowedTools: {'docx.paragraphStyle'}),
    ),
    ('native step budget', OfficeMacroPolicy(maxSteps: 1)),
  ]) {
    test('$label applies before cell paragraph publication', () async {
      final input = portable.wordCellParagraphInput();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      await expectLater(
        session.run(
          portable.wordCellParagraphSource(File(_example).readAsStringSync()),
        ),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    });
  }

  test('pre-cancelled cell paragraph formatting cannot publish', () async {
    final input = portable.wordCellParagraphInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    await expectLater(
      session.run(
        portable.wordCellParagraphPlan('$_first.Style = wdStyleNormal'),
        cancellation: OfficeMacroCancellation()..cancel(),
      ),
      throwsA(isA<OfficeMacroException>()),
    );
    expect(session.bytes, input);
    expect(session.revision, 0);
  });

  test(
    'MCP compiles the actual BAS, validates without edits and executes cell-scoped operations',
    () async {
      final input = portable.wordCellParagraphInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final adapter = OfficeMacroMcp(session);
      final compiled = await adapter.callTool(
        'office_macro_compile',
        _source(File(_example).readAsStringSync()),
      );
      expect(compiled['isError'], isFalse, reason: '$compiled');
      final macro = _structured(compiled)['macro'];
      final arguments = <String, Object?>{'macro': macro};
      final preview = await adapter.callTool(
        'office_macro_validate',
        arguments,
      );
      expect(preview['isError'], isFalse, reason: '$preview');
      expect(_structured(preview)['validatedOnly'], isTrue);
      expect(_structured(preview)['completedSteps'], 8);
      expect(session.bytes, input);
      expect(session.revision, 0);
      final result = await adapter.callTool('office_macro_run', arguments);
      expect(result['isError'], isFalse, reason: '$result');
      expect(_structured(result)['completedSteps'], 8);
      expect(session.revision, 1);
      portable.assertWordCellParagraphExample(session.bytes);
      expect(
        portable.wordCellParagraphUntouched(session.bytes),
        portable.wordCellParagraphUntouched(input),
      );
    },
  );

  test(
    'MCP source refusal publishes neither a prefix plan nor a document mutation',
    () async {
      final input = portable.wordCellParagraphInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final result = await OfficeMacroMcp(session).callTool(
        'office_macro_compile',
        _source('''
Sub Main()
  $_first.Style = "Report Label"
  $_second.Range.InsertAfter "unsupported"
End Sub
'''),
      );
      expect(result['isError'], isTrue);
      expect(_structured(result).containsKey('macro'), isFalse);
      final error = _structured(result)['error']! as Map<String, Object?>;
      expect(error['moduleName'], 'CellParagraphIntegration');
      expect(error['line'], greaterThan(0));
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test(
    'CLI compiles, previews, executes and preserves output for source and native failures',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'word-cell-paragraph-cli-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordCellParagraphInput());
      final original = input.readAsBytesSync();
      final source = File(_example).absolute.path;
      final planFile = File('${directory.path}/report.qudsmacro.json');
      final compiled = await runOfficeMacroCli([
        'compile-word-vba',
        source,
        planFile.path,
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      final plan = OfficeMacro.parse(planFile.readAsStringSync());
      expect(plan.steps, hasLength(8));
      expect(plan.steps.first.tool, 'docx.paragraphStyle');
      expect(plan.steps.first.arguments, {
        'paragraph': 0,
        'story': 'tableCell',
        'table': 0,
        'row': 0,
        'column': 0,
        'name': 'Report Label',
      });
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
      portable.assertWordCellParagraphExample(saved);
      expect(
        portable.wordCellParagraphUntouched(saved),
        portable.wordCellParagraphUntouched(original),
      );
      final guard = (await WordPackagePreservation.capture(
        original,
        input.path,
      ))!;
      await guard.validateSaved(saved);
      for (final source in <String>[
        '''
Sub Main()
  $_first.Style = "Report Label"
  $_second.Style = "Missing template style"
End Sub
''',
        '''
Sub Main()
  $_first.Style = "Report Label"
  $_second.Range.InsertAfter "unsupported"
End Sub
''',
      ]) {
        final invalid = File('${directory.path}/invalid.bas')
          ..writeAsStringSync(source);
        final failed = await runOfficeMacroCli([
          'run-word-vba',
          input.path,
          invalid.path,
          output.path,
        ]);
        expect(failed.exitCode, isNot(0));
        expect(output.readAsBytesSync(), saved);
        expect(input.readAsBytesSync(), original);
      }
    },
    timeout: officeMacroCliTestTimeout,
  );
}
