import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_headers_footers_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

const _example = 'example/macros/word_headers_footers.bas';
const _header =
    'ThisDocument.Sections(1).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range';
const _footer =
    'ThisDocument.Sections(2).Footers(wdHeaderFooterEvenPages).Range.Paragraphs(2).Range';
const _w = OfficeNamespaces.w;
const _r = OfficeNamespaces.r;

Matcher _failure({int? step, String? tool, String code = 'operation_failed'}) {
  var matcher = isA<OfficeMacroException>().having((e) => e.code, 'code', code);
  if (step != null) matcher = matcher.having((e) => e.stepIndex, 'step', step);
  if (tool != null) matcher = matcher.having((e) => e.tool, 'tool', tool);
  return matcher;
}

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _sourceArguments(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'WordHeadersFootersIntegration',
    'source': source,
  },
};

WmlParagraph _paragraph(
  Uint8List bytes,
  int section,
  String story,
  int paragraph,
) => portable.wordHeaderFooterParagraphs(
  WordDeserializer().readBytes(bytes).sections[section],
  story,
)[paragraph];

Iterable<XmlElement> _descendants(XmlElement parent, String name) sync* {
  for (final child in parent.childElements) {
    if (child.namespaceUri == _w && child.localName == name) yield child;
    yield* _descendants(child, name);
  }
}

XmlElement _reference(XmlElement section, String name, String type) => section
    .childrenNamed(name, namespaceUri: _w)
    .singleWhere((e) => e.getAttribute('type', namespaceUri: _w) == type);

Uint8List _unsafeStoryInput(String kind) {
  final package = OpcPackage.openBytes(portable.wordHeadersFootersInput());
  final main = package.getPart('/word/document.xml')!;
  final xml = XmlDocument.parse(main.readText());
  final sections = _descendants(xml.root!, 'sectPr').toList();
  expect(sections, hasLength(3));
  final selected = _reference(sections[1], 'headerReference', 'default');
  switch (kind) {
    case 'inherited selected story':
      sections[1].children.remove(selected);
    case 'shared part':
      final first = _reference(sections[0], 'headerReference', 'default');
      selected.setAttribute(
        'id',
        first.getAttribute('id', namespaceUri: _r)!,
        prefix: 'r',
        namespaceUri: _r,
      );
    case 'later implicit inheritance':
      sections[2].children.remove(
        _reference(sections[2], 'headerReference', 'default'),
      );
    case 'opaque table story':
      final relations = package.relationshipsFor('/word/document.xml');
      final relation = relations.byId(
        selected.getAttribute('id', namespaceUri: _r)!,
      )!;
      package.getPart(relations.resolve(relation))!.writeText('''
<w:hdr xmlns:w="$_w"><w:tbl><w:tr><w:tc><w:p><w:r><w:t>Opaque table</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:hdr>
''');
    default:
      throw ArgumentError.value(kind);
  }
  main.writeText(xml.toXmlString());
  return package.save();
}

void main() {
  registerOfficeMacroCliCleanup();

  test(
    'committed BAS routes all six variants and preserves DOCM through reopens',
    () async {
      final receipt = await portable.runWordHeadersFootersExample(
        File(_example).readAsStringSync(),
      );
      expect(receipt['operations'], 11);
      expect(receipt['addressedStoryVariants'], 6);
      expect(receipt['firstRunRevision'], 1);
      expect(receipt['repeatedRevision'], 2);
      expect(receipt['additionalReopens'], 2);
      expect(receipt['opaquePayloadsPreserved'], isTrue);
    },
  );

  test(
    'typed HeaderFooter, story Range and paragraph aliases retain identity across ByVal helpers',
    () async {
      final input = portable.wordHeadersFootersInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = portable.wordHeadersFootersSource('''
Sub Edit(ByVal story As HeaderFooter, ByVal target As Range)
  story.Range.Paragraphs(1).Range.InsertBefore "A: "
  Set story = ThisDocument.Sections(2).Footers(wdHeaderFooterEvenPages)
  target.Paragraphs(2).Range.InsertBefore "B: "
  story.Range.Paragraphs(2).Range.Font.Bold = True
End Sub
Sub Main()
  Dim story As HeaderFooter
  Dim target As Range
  Dim line As Paragraph
  Set story = ActiveDocument.Sections(1).Headers(wdHeaderFooterFirstPage)
  Set target = story.Range
  Set line = target.Paragraphs.Item(2)
  Edit target:=target, story:=story
  story.Range.Paragraphs(1).Range.Font.Italic = True
  line.Format.SpaceAfter = 4
End Sub
''');
      await session.run(plan);
      expect(
        _paragraph(session.bytes, 0, 'firstHeader', 0).text,
        'A: S1 firstHeader 1',
      );
      expect(
        _paragraph(
          session.bytes,
          0,
          'firstHeader',
          0,
        ).inlines.whereType<WmlRun>().every((r) => r.properties.italic),
        isTrue,
      );
      expect(
        _paragraph(session.bytes, 0, 'firstHeader', 1).text,
        'B: S1 firstHeader 2',
      );
      expect(
        _paragraph(session.bytes, 0, 'firstHeader', 1).properties.spacingAfter,
        4,
      );
      expect(
        _paragraph(
          session.bytes,
          1,
          'evenFooter',
          1,
        ).inlines.whereType<WmlRun>().every((r) => r.properties.bold),
        isTrue,
      );
      expect(
        WordDeserializer()
            .readBytes(session.bytes)
            .paragraphs
            .map((p) => p.text),
        ['Body 1', 'Body 2', 'Body 3'],
      );
      portable.assertWordHeadersFootersPackage(session.bytes);
    },
  );

  test(
    'ordered prefix edits, font reset, custom spacing and tab clearing resolve the selected story',
    () async {
      final input = portable.wordHeadersFootersInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(
        portable.wordHeadersFootersPlan('''
$_header.InsertBefore "A"
$_header.InsertBefore "B"
$_header.Font.Bold = True
$_header.Font.Bold = False
With $_footer.ParagraphFormat
  .LineSpacingRule = wdLineSpaceExactly
  .LineSpacing = 14
  .TabStops.Add Position:=72, Alignment:=wdAlignTabRight
  .TabStops.ClearAll
End With
'''),
      );
      final header = _paragraph(session.bytes, 0, 'header', 0);
      final footer = _paragraph(session.bytes, 1, 'evenFooter', 1);
      expect(header.text, 'BAS1 header 1');
      expect(
        header.inlines.whereType<WmlRun>().every((r) => !r.properties.bold),
        isTrue,
      );
      expect(footer.properties.lineSpacingRule, WmlLineSpacingRule.exact);
      expect(footer.properties.lineSpacing, 14);
      expect(footer.properties.tabs, isEmpty);
      expect(
        _paragraph(
          session.bytes,
          1,
          'evenFooter',
          0,
        ).properties.lineSpacingRule,
        WmlLineSpacingRule.auto,
      );
      expect(session.revision, 1);
    },
  );

  test(
    'missing story paragraph rolls back preceding body edits and recording',
    () async {
      final receipt = await portable.runWordHeadersFootersRollback();
      expect(receipt['failedStep'], 1);
      expect(receipt['validateAndRunRollback'], isTrue);
      expect(receipt['recordingUnchanged'], isTrue);
    },
  );

  for (final kind in [
    'inherited selected story',
    'shared part',
    'later implicit inheritance',
    'opaque table story',
  ]) {
    test(
      '$kind refuses complete source transaction without touching body',
      () async {
        final input = _unsafeStoryInput(kind);
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        session.startRecording('Declined story');
        final plan = portable.wordHeadersFootersPlan('''
ThisDocument.Paragraphs(1).Range.InsertBefore "Temporary: "
ThisDocument.Sections(2).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range.Font.Bold = True
''');
        for (final action in [session.validate, session.run]) {
          await expectLater(
            action(plan),
            throwsA(_failure(step: 1, tool: 'docx.runFormat')),
          );
          expect(session.bytes, input);
          expect(session.revision, 0);
        }
        expect(session.stopRecording().steps, isEmpty);
      },
    );
  }

  test(
    'late missing section preserves an accepted revision and recording',
    () async {
      final session = OfficeMacroSession(
        portable.wordHeadersFootersInput(),
        format: OfficeMacroFormat.docx,
      );
      session.startRecording('Accepted header');
      await session.callTool('docx.runFormat', {
        'story': 'header',
        'section': 0,
        'paragraph': 0,
        'bold': true,
      });
      final accepted = session.bytes;
      final plan = portable.wordHeadersFootersPlan('''
$_footer.InsertBefore "Temporary: "
ThisDocument.Sections(99).Footers(wdHeaderFooterFirstPage).Range.Paragraphs(1).Range.Font.Italic = True
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(_failure(step: 1, tool: 'docx.runFormat')),
        );
        expect(session.bytes, accepted);
        expect(session.revision, 1);
      }
      final recorded = session.stopRecording();
      expect(recorded.steps, hasLength(1));
      expect(recorded.steps.single.arguments, {
        'story': 'header',
        'section': 0,
        'paragraph': 0,
        'bold': true,
      });
      final replay = OfficeMacroSession(
        portable.wordHeadersFootersInput(),
        format: OfficeMacroFormat.docx,
      );
      await replay.run(OfficeMacro.parse(recorded.encode()));
      expect(
        portable.wordHeadersFootersState(replay.bytes),
        portable.wordHeadersFootersState(accepted),
      );
    },
  );

  test(
    'permissions, allowlists and step limits govern story validation and playback',
    () async {
      final input = portable.wordHeadersFootersInput();
      final plan = portable.wordHeadersFootersPlan('''
$_header.InsertBefore "Prefix: "
$_footer.Font.Italic = True
''');
      for (final (policy, code) in <(OfficeMacroPolicy, String)>[
        (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
        (
          OfficeMacroPolicy(allowedTools: {'docx.replaceText'}),
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
          allowedTools: {'docx.replaceText', 'docx.runFormat'},
          maxSteps: 2,
        ),
      );
      expect((await allowed.validate(plan)).validatedOnly, isTrue);
      expect(allowed.bytes, input);
      expect((await allowed.run(plan)).completedSteps, 2);
      expect(allowed.revision, 1);
    },
  );

  test(
    'cancellation between story operations rolls back and allows a later run',
    () async {
      final input = portable.wordHeadersFootersInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final cancellation = OfficeMacroCancellation();
      final plan = portable.wordHeadersFootersPlan('''
$_header.InsertBefore "Prefix: "
$_footer.Font.Italic = True
''');
      final pending = session.run(plan, cancellation: cancellation);
      Timer.run(cancellation.cancel);
      await expectLater(
        pending,
        throwsA(_failure(step: 1, tool: 'docx.runFormat', code: 'cancelled')),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      expect(session.revision, 1);
    },
  );

  test(
    'MCP source envelope compiles and validates/runs the actual BAS',
    () async {
      final input = portable.wordHeadersFootersInput();
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
      expect(_structured(validated)['completedSteps'], 11);
      expect(_structured(validated)['validatedOnly'], isTrue);
      expect(session.bytes, input);
      expect(session.revision, 0);
      final result = await adapter.callTool('office_macro_run', arguments);
      expect(result['isError'], isFalse, reason: '$result');
      expect(_structured(result)['completedSteps'], 11);
      portable.assertWordHeadersFootersExample(session.bytes);
    },
  );

  test(
    'MCP reports whole-story writes with source positions and no partial macro',
    () async {
      final input = portable.wordHeadersFootersInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final result = await OfficeMacroMcp(session).callTool(
        'office_macro_compile',
        _sourceArguments('''
Sub Main()
  $_header.Font.Bold = True
  ThisDocument.Sections(1).Headers(wdHeaderFooterPrimary).Range.InsertBefore "Unsupported"
End Sub
'''),
      );
      expect(result['isError'], isTrue);
      expect(_structured(result).containsKey('macro'), isFalse);
      final error = _structured(result)['error']! as Map<String, Object?>;
      expect(error['moduleName'], 'WordHeadersFootersIntegration');
      expect(error['line'], greaterThan(0));
      expect(error['column'], greaterThan(0));
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test(
    'CLI validates and runs committed BAS without modifying its DOCM input',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'quds-word-stories-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordHeadersFootersInput());
      final original = input.readAsBytesSync();
      final source = File(_example).absolute.path;
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
      final result = await runOfficeMacroCli([
        'run-word-vba',
        input.path,
        source,
        output.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final report =
          jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(report['language'], 'vba-word');
      expect(input.readAsBytesSync(), original);
      portable.assertWordHeadersFootersExample(output.readAsBytesSync());
      final guard = (await WordPackagePreservation.capture(
        original,
        input.path,
      ))!;
      await guard.validateSaved(output.readAsBytesSync());
    },
    timeout: officeMacroCliTestTimeout,
  );

  test(
    'CLI late missing story paragraph creates no output or input mutation',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'quds-word-stories-failure-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final input = File('${directory.path}/input.docm')
        ..writeAsBytesSync(portable.wordHeadersFootersInput());
      final original = input.readAsBytesSync();
      final source = File('${directory.path}/invalid.bas')
        ..writeAsStringSync('''
Sub Main()
  $_header.InsertBefore "Temporary: "
  ThisDocument.Sections(2).Footers(wdHeaderFooterEvenPages).Range.Paragraphs(99).Range.Font.Italic = True
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
      expect(input.readAsBytesSync(), original);
      expect(output.existsSync(), isFalse);
    },
    timeout: officeMacroCliTestTimeout,
  );
}
