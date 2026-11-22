import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_cell_text_controls_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_table_text_controls.bas';
const _cell = 'ActiveDocument.Tables(1).Cell(1, 1).Range';
const _w = OfficeNamespaces.w;
const _x = 'urn:cell-control-metadata';

WmlParagraph _paragraph(WmlDocument document, {int column = 0}) =>
    document.sections.first.blocks
            .whereType<WmlTable>()
            .first
            .rows
            .first
            .cells[column]
            .blocks
            .single
        as WmlParagraph;

Uint8List _changed(void Function(WmlDocument) change) {
  final document = WordDeserializer().readBytes(
    portable.wordCellTextControlInput(),
  );
  change(document);
  return WordSerializer().writeBytes(document);
}

List<XmlElement> _elements(XmlElement root, String name) => [
  for (final child in root.childElements) ...[
    if (child.localName == name && child.namespaceUri == _w) child,
    ..._elements(child, name),
  ],
];

XmlElement _root(Uint8List bytes) => XmlDocument.parse(
  OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
).root!;

Uint8List _nativeInput({bool inherited = false}) {
  final package = OpcPackage.openBytes(portable.wordCellTextControlInput());
  final runProperties = inherited
      ? ''
      : '''
<w:rPr><w:i/><w:color w:val="112233"/><w:sz w:val="20"/>
<w:lang w:val="de-DE" w:bidi="ar-SA" w:eastAsia="ja-JP" x:keep="language"/>
<w:noProof w:val="0" x:keep="proofing"/><w:highlight w:val="none"/></w:rPr>
''';
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="$_w" xmlns:x="$_x"><w:body>
<w:p><w:r><w:t>Untouched body</w:t></w:r></w:p>
<w:tbl><w:tblPr><w:tblStyle w:val="CellControlBase"/></w:tblPr>
<w:tblGrid><w:gridCol w:w="2400"/><w:gridCol w:w="2400"/></w:tblGrid>
<w:tr><w:tc><w:p><w:pPr><w:rPr><w:noProof/><w:lang w:val="en-GB"/>
<w:highlight w:val="magenta"/></w:rPr></w:pPr>
<w:r>$runProperties<w:t xml:space="preserve">First </w:t></w:r>
<w:r><w:rPr><w:color w:val="445566"/><w:sz w:val="28"/></w:rPr>
<w:t>second 😀</w:t></w:r></w:p></w:tc>
<w:tc><w:p><w:r><w:t>Neighbor</w:t></w:r></w:p></w:tc></w:tr>
</w:tbl><w:sectPr/></w:body></w:document>
''');
  package.getPart('/word/styles.xml')!.writeText('''
<w:styles xmlns:w="$_w"><w:style w:type="table" w:styleId="CellControlBase">
<w:rPr><w:noProof/><w:highlight w:val="yellow"/>
<w:lang w:val="en-US" w:bidi="ar-SA"/></w:rPr>
</w:style></w:styles>
''');
  // Record the serializer's ordinary control-save state before testing macro
  // preservation. Raw authored styles gain an XML declaration on any save.
  return WordSerializer().writeBytes(
    WordDeserializer().readBytes(package.save()),
  );
}

Future<void> _refused(Uint8List input, OfficeMacro plan) async {
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Refused cell controls');
  for (final action in [session.validate, session.run]) {
    await expectLater(action(plan), throwsA(isA<OfficeMacroException>()));
    expect(session.bytes, input);
    expect(session.revision, 0);
  }
  expect(session.stopRecording().steps, isEmpty);
}

void main() {
  registerOfficeMacroCliCleanup();

  for (final macroEnabled in [false, true]) {
    test(
      '${macroEnabled ? 'DOCM' : 'DOCX'} multilingual table example round-trips and replays',
      () async {
        final result = await portable.runWordCellTextControlsExample(
          File(_example).readAsStringSync(),
          macroEnabled: macroEnabled,
        );
        expect(result['operations'], 17);
        expect(result['revision'], 2);
        expect(result['recordedSteps'], 17);
        expect(result['additionalReopens'], 2);
        expect(result['untouchedLayoutAndParts'], isTrue);
        expect(result['lateRollback'], isTrue);
        expect(result['opaqueVbaPreserved'], macroEnabled);
      },
    );
  }

  for (final inherited in [false, true]) {
    test(
      '${inherited ? 'inherited' : 'direct'} properties preserve rich text, language slots and paragraph marks',
      () async {
        final input = _nativeInput(inherited: inherited);
        final original = WordDeserializer().readBytes(input);
        final originalRuns = _paragraph(original).inlines
            .whereType<WmlRun>()
            .toList();
        final initial = [
          for (final run in originalRuns)
            (
              run.text,
              run.properties.italic,
              run.properties.color,
              run.properties.fontSizeHalfPoints,
            ),
        ];
        final beforeMark = _paragraph(original)
            .properties
            .importedParagraphMark!;
        final package = OpcPackage.openBytes(input);
        final vba = package.getPart('/word/vbaProject.bin')!.readBytes();
        final styles = package.getPart('/word/styles.xml')!.readBytes();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        // The direct first run already has these values: even equal assignments
        // must retain an explicit override of the contrasting table style.
        final plan = portable.wordCellTextControlPlan('''
$_cell.NoProofing = False
$_cell.HighlightColorIndex = wdNoHighlight
$_cell.LanguageIDOther = wdGerman
''');
        await session.run(plan);
        var saved = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          final document = WordDeserializer().readBytes(saved);
          final target = _paragraph(document);
          final runs = target.inlines.whereType<WmlRun>().toList();
          expect([
            for (final run in runs)
              (
                run.text,
                run.properties.italic,
                run.properties.color,
                run.properties.fontSizeHalfPoints,
              ),
          ], initial);
          for (final run in runs) {
            expect(run.properties.noProof, isFalse);
            expect(run.properties.highlight, isNull);
            expect(run.properties.proofingLanguage, 'de-DE');
            expect(run.properties.complexScriptLanguage, 'ar-SA');
          }
          final mark = target.properties.importedParagraphMark!;
          expect(mark.noProof, beforeMark.noProof);
          expect(mark.proofingLanguage, beforeMark.proofingLanguage);
          expect(mark.highlight, beforeMark.highlight);
          final neighbor = _paragraph(
            document,
            column: 1,
          ).inlines.whereType<WmlRun>().single;
          expect(neighbor.properties.noProof, isTrue);
          expect(neighbor.properties.highlight, 'FFFF00');
          expect(neighbor.properties.proofingLanguage, 'en-US');
          final nativeRun = _elements(
            _elements(_root(saved), 'tc').first,
            'r',
          ).first;
          if (!inherited) {
            final language = _elements(nativeRun, 'lang').single;
            expect(
              language.getAttribute('eastAsia', namespaceUri: _w),
              'ja-JP',
            );
            expect(language.getAttribute('bidi', namespaceUri: _w), 'ar-SA');
            expect(language.getAttribute('keep', namespaceUri: _x), 'language');
            expect(
              _elements(
                nativeRun,
                'noProof',
              ).single.getAttribute('keep', namespaceUri: _x),
              'proofing',
            );
          }
          final reopenedPackage = OpcPackage.openBytes(saved);
          expect(
            reopenedPackage.getPart('/word/vbaProject.bin')!.readBytes(),
            vba,
          );
          expect(
            reopenedPackage.getPart('/word/styles.xml')!.readBytes(),
            styles,
          );
          if (cycle < 2) saved = WordSerializer().writeBytes(document);
        }
      },
    );
  }

  test(
    'in-memory shared run properties remain confined to the selected cell',
    () {
      final document = WordDeserializer().readBytes(
        portable.wordCellTextControlInput(),
      );
      final shared = WmlRunProps(
        noProof: true,
        proofingLanguage: 'en-US',
        highlight: 'FFFF00',
      );
      final selected = _paragraph(document).inlines.single as WmlRun;
      final neighbor = _paragraph(document, column: 1).inlines.single as WmlRun;
      selected.properties = shared;
      neighbor.properties = shared;
      final plan = portable.wordCellTextControlPlan('''
$_cell.NoProofing = False
$_cell.LanguageID = wdFrench
$_cell.HighlightColorIndex = wdNoHighlight
''');
      for (final step in plan.steps) {
        OfficeOperationCatalog.apply(document, step.tool, step.arguments);
      }
      final result = (_paragraph(document).inlines.single as WmlRun).properties;
      expect(result, isNot(same(shared)));
      expect(
        (result.noProof, result.proofingLanguage, result.highlight),
        (false, 'fr-FR', null),
      );
      expect(neighbor.properties, same(shared));
      expect(
        (shared.noProof, shared.proofingLanguage, shared.highlight),
        (true, 'en-US', 'FFFF00'),
      );
    },
  );

  for (final write in [
    'NoProofing = True',
    'LanguageID = wdGerman',
    'LanguageIDOther = wdFrench',
    'HighlightColorIndex = wdYellow',
  ]) {
    test('empty cells refuse $write without insertion formatting', () async {
      final input = _changed(
        (document) => _paragraph(document).inlines.clear(),
      );
      await _refused(
        input,
        portable.wordCellTextControlPlan('''
ActiveDocument.Paragraphs(1).Range.Font.ColorIndex = wdRed
$_cell.$write
'''),
      );
    });
  }

  for (final (label, change) in <(String, void Function(WmlDocument))>[
    ('edit restriction', (document) => document.restrictEditing = true),
    ('revision tracking', (document) => document.trackRevisions = true),
    (
      'multiple paragraphs',
      (document) => document.sections.first.blocks
          .whereType<WmlTable>()
          .first
          .rows
          .first
          .cells
          .first
          .blocks
          .add(WmlParagraph(inlines: [WmlRun(text: 'Extra')])),
    ),
    (
      'hyperlink',
      (document) => (_paragraph(document).inlines.first as WmlRun).hyperlink =
          const WmlHyperlink(url: 'https://example.com'),
    ),
    (
      'merged cell',
      (document) =>
          document.sections.first.blocks
                  .whereType<WmlTable>()
                  .first
                  .rows
                  .first
                  .cells
                  .first
                  .gridSpan =
              2,
    ),
  ]) {
    test('$label refuses cell controls and earlier edits atomically', () async {
      await _refused(
        _changed(change),
        portable.wordCellTextControlPlan('''
ActiveDocument.Paragraphs(1).Range.Font.ColorIndex = wdRed
$_cell.NoProofing = False
$_cell.LanguageID = wdGerman
$_cell.HighlightColorIndex = wdYellow
'''),
      );
    });
  }

  for (final policy in [
    OfficeMacroPolicy(allowMutation: false),
    OfficeMacroPolicy(allowedTools: {'docx.tableCellRangeText'}),
    OfficeMacroPolicy(maxSteps: 1),
  ]) {
    test('cell controls retain policy boundaries: $policy', () async {
      final input = portable.wordCellTextControlInput();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      await expectLater(
        session.run(
          portable.wordCellTextControlSource(File(_example).readAsStringSync()),
        ),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    });
  }

  test('pre-cancelled cell controls cannot publish', () async {
    final input = portable.wordCellTextControlInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    await expectLater(
      session.run(
        portable.wordCellTextControlPlan('$_cell.NoProofing = True'),
        cancellation: OfficeMacroCancellation()..cancel(),
      ),
      throwsA(isA<OfficeMacroException>()),
    );
    expect(session.bytes, input);
    expect(session.revision, 0);
  });

  test(
    'MCP compilation, preview and execution retain the table selector',
    () async {
      final input = portable.wordCellTextControlInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final adapter = OfficeMacroMcp(session);
      final compiled = await adapter.callTool('office_macro_compile', {
        'source': {
          'language': 'vba-word',
          'format': 'docx',
          'moduleName': 'CellControls',
          'source': File(_example).readAsStringSync(),
        },
      });
      expect(compiled['isError'], isFalse, reason: '$compiled');
      final arguments = <String, Object?>{
        'macro':
            (compiled['structuredContent']! as Map<String, Object?>)['macro'],
      };
      final validated = await adapter.callTool(
        'office_macro_validate',
        arguments,
      );
      expect(validated['isError'], isFalse, reason: '$validated');
      expect(session.bytes, input);
      expect(session.revision, 0);
      final result = await adapter.callTool('office_macro_run', arguments);
      expect(result['isError'], isFalse, reason: '$result');
      expect(session.revision, 1);
      final cells = portable.wordCellTextControlState(session.bytes);
      expect(
        (cells[2]['runs']! as List<Object?>).single,
        containsPair('noProof', true),
      );
      expect(
        (cells[3]['runs']! as List<Object?>).single,
        containsPair('language', 'fr-FR'),
      );
    },
  );

  test(
    'CLI compiles, validates, runs and preserves output on late failure',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'word-cell-text-cli-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordCellTextControlInput());
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
      expect(
        OfficeMacro.parse(File(compiledPath).readAsStringSync()).steps,
        hasLength(17),
      );
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
      expect(
        portable.wordCellTextControlUntouched(saved),
        portable.wordCellTextControlUntouched(original),
      );
      final failedSource = File('${directory.path}/late-failure.bas')
        ..writeAsStringSync('''
Sub Main()
  $_cell.NoProofing = True
  ActiveDocument.Tables(99).Cell(1, 1).Range.LanguageID = wdFrench
End Sub
''');
      final failed = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        failedSource.path,
        output.path,
      ]);
      expect(failed.exitCode, isNot(0));
      expect(output.readAsBytesSync(), saved);
      expect(input.readAsBytesSync(), original);
    },
    timeout: officeMacroCliTestTimeout,
  );
}
