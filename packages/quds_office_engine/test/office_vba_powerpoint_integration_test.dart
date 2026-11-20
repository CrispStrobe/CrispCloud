import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _source = '''
Option Explicit
Sub StyleTitle(ByVal target As Shape, ByVal label As String)
    target.TextFrame.TextRange.Text = label
    With target.TextFrame.TextRange
        .Font.Name = "Arial"
        .Font.Size = 28.5
        .Font.Bold = msoTrue
        .Font.Italic = False
        .Font.Underline = msoTrue
        .Font.Color.RGB = RGB(10, 20, 30)
        .ParagraphFormat.Alignment = ppAlignCenter
    End With
    target.Left = 24
    target.Top = 36
    target.Width = 400
    target.Height = 72
    target.Rotation = 15
End Sub
Sub Main()
    Dim title As Shape
    Set title = ActivePresentation.Slides(1).Shapes("Title")
    Call StyleTitle(title, "Quarterly 😀 report")
End Sub
''';

Uint8List _deck() => SlideSerializer().writeBytes(
  PmlPresentation(
    slides: <PmlSlide>[
      PmlSlide(
        id: 256,
        shapes: <PmlShape>[
          PmlShape(
            id: 2,
            name: 'Title',
            text: 'Original title',
            fontSizePt: 18,
            textColor: '333333',
            transform: const PmlTransform(
              x: 152400,
              y: 190500,
              cx: 3810000,
              cy: 762000,
            ),
          ),
          PmlShape(id: 3, name: 'Body', text: 'Untouched body'),
        ],
      ),
      PmlSlide(
        id: 257,
        shapes: <PmlShape>[
          PmlShape(id: 2, name: 'Title', text: 'Other slide title'),
        ],
      ),
    ],
  ),
);

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-powerpoint',
    format: OfficeMacroFormat.pptx,
    moduleName: 'DeckReport',
    source: source,
  ),
);

OfficeMacroSession _session({OfficeMacroPolicy? policy}) =>
    OfficeMacroSession(_deck(), format: OfficeMacroFormat.pptx, policy: policy);

TypeMatcher<OfficeMacroException> _error(String code) =>
    isA<OfficeMacroException>().having((error) => error.code, 'code', code);

List<XmlElement> _elements(XmlElement root, String name) => <XmlElement>[
  for (final child in root.childElements) ...<XmlElement>[
    if (child.localName == name && child.namespaceUri == OfficeNamespaces.a)
      child,
    ..._elements(child, name),
  ],
];

void main() {
  test(
    'PowerPoint source validates privately and saves actual text, styles and geometry',
    () async {
      final session = _session();
      final original = session.bytes;
      final plan = _compile(_source);
      session.startRecording('Playback is not a direct tool recording');
      final validation = await session.validate(plan);
      expect(validation.validatedOnly, isTrue);
      expect(session.bytes, original);
      expect(session.revision, 0);

      await session.run(plan);
      expect(session.revision, 1);
      final deck = SlideDeserializer().readBytes(session.bytes);
      final title = deck.slides.first.shapes.first;
      expect(title.text, 'Quarterly 😀 report');
      expect(title.fontSizePt, 28.5);
      expect(title.textColor, '0A141E');
      expect(title.textAlign, PmlTextAlign.center);
      expect(title.transform.xPoints, 24);
      expect(title.transform.yPoints, 36);
      expect(title.transform.widthPoints, 400);
      expect(title.transform.heightPoints, 72);
      expect(title.transform.rotationDegrees, 15);
      final runs = title.resolvedRichText.expand((paragraph) => paragraph.runs);
      expect(runs, isNotEmpty);
      for (final run in runs) {
        expect(run.fontFamily, 'Arial');
        expect(run.bold, isTrue);
        expect(run.italic, isFalse);
        expect(run.underline, isTrue);
      }
      expect(deck.slides.first.shapes[1].text, 'Untouched body');
      expect(deck.slides[1].shapes.first.text, 'Other slide title');
      expect(session.stopRecording().steps, isEmpty);

      // Inspect emitted XML independently of the engine's property reader.
      final root = XmlDocument.parse(
        OpcPackage.openBytes(
          session.bytes,
        ).getPart('/ppt/slides/slide1.xml')!.readText(),
      ).root!;
      final titleText = _elements(root, 't').first;
      expect(titleText.text, 'Quarterly 😀 report');
      final properties = _elements(root, 'rPr').first;
      expect(properties.getAttribute('sz'), '2850');
      expect(properties.getAttribute('b'), '1');
      expect(properties.getAttribute('i'), '0');
      expect(properties.getAttribute('u'), 'sng');
      expect(
        _elements(properties, 'latin').single.getAttribute('typeface'),
        'Arial',
      );
      expect(
        _elements(properties, 'srgbClr').single.getAttribute('val'),
        '0A141E',
      );
      expect(_elements(root, 'off').first.getAttribute('x'), '304800');
      expect(_elements(root, 'ext').first.getAttribute('cx'), '5080000');
    },
  );

  for (final failingTarget in <String>[
    'ActivePresentation.Slides(99).Shapes(1)',
    'ActivePresentation.Slides(1).Shapes(99)',
    'ActivePresentation.Slides(1).Shapes("Missing")',
  ]) {
    test(
      'late selector failure rolls back all writes: $failingTarget',
      () async {
        final session = _session();
        final before = session.bytes;
        final plan = _compile('''
Sub Main()
    ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text = "Do not publish"
    $failingTarget.TextFrame.TextRange.Font.Bold = True
End Sub
''');
        final failure = _error(
          'operation_failed',
        ).having((error) => error.stepIndex, 'step', 1);
        await expectLater(session.validate(plan), throwsA(failure));
        await expectLater(session.run(plan), throwsA(failure));
        expect(session.bytes, before);
        expect(session.revision, 0);
      },
    );
  }

  test(
    'PowerPoint compiler cannot grant write, operation or step permissions',
    () async {
      final plan = _compile(_source);
      for (final policy in <OfficeMacroPolicy>[
        OfficeMacroPolicy(allowMutation: false),
        OfficeMacroPolicy(allowedTools: <String>{'pptx.shapeText'}),
      ]) {
        final session = _session(policy: policy);
        final before = session.bytes;
        await expectLater(
          session.run(plan),
          throwsA(_error('permission_denied')),
        );
        expect(session.bytes, before);
        expect(session.revision, 0);
      }
      final limited = _session(policy: OfficeMacroPolicy(maxSteps: 1));
      final before = limited.bytes;
      await expectLater(limited.run(plan), throwsA(_error('limit_exceeded')));
      expect(limited.bytes, before);
    },
  );

  test(
    'MCP advertises PowerPoint, compiles read-only, and uses the same transaction',
    () async {
      final session = _session();
      final mcp = OfficeMacroMcp(session);
      final tools = mcp.listTools()['tools']! as List<Map<String, Object?>>;
      final compileTool = tools.singleWhere(
        (tool) => tool['name'] == 'office_macro_compile',
      );
      final schema = compileTool['inputSchema']! as Map<String, Object?>;
      final fields = schema['properties']! as Map<String, Object?>;
      final sourceSchema = fields['source']! as Map<String, Object?>;
      final sourceFields = sourceSchema['properties']! as Map<String, Object?>;
      final language = sourceFields['language']! as Map<String, Object?>;
      expect(language['enum'], contains('vba-powerpoint'));
      final compiled = await mcp.callTool(
        'office_macro_compile',
        <String, Object?>{
          'source': <String, Object?>{
            'language': 'vba-powerpoint',
            'format': 'pptx',
            'source': _source,
          },
        },
      );
      expect(compiled['isError'], isFalse);
      expect(session.revision, 0);
      final content = compiled['structuredContent']! as Map<String, Object?>;
      final executed = await mcp.callTool('office_macro_run', <String, Object?>{
        'macro': content['macro'],
      });
      expect(executed['isError'], isFalse);
      expect(session.revision, 1);
      expect(
        SlideDeserializer()
            .readBytes(session.bytes)
            .slides
            .first
            .shapes
            .first
            .text,
        'Quarterly 😀 report',
      );
    },
  );

  test(
    'PPTM project bytes, package type and relationship survive repeated explicit runs',
    () async {
      const mainType =
          'application/vnd.ms-powerpoint.presentation.macroEnabled.main+xml';
      const vbaType = 'application/vnd.ms-office.vbaProject';
      const relationType =
          'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
      final original = OpcPackage.openBytes(_deck());
      original.getPart('/ppt/presentation.xml')!.contentType = mainType;
      original.contentTypes.setOverride('/ppt/presentation.xml', mainType);
      final opaque = Uint8List.fromList(<int>[0, 1, 127, 128, 254, 255]);
      original.createPart('/ppt/vbaProject.bin', vbaType, opaque);
      final relation = original
          .relationshipsFor('/ppt/presentation.xml')
          .add(type: relationType, target: 'vbaProject.bin');
      final session = OfficeMacroSession(
        original.save(),
        format: OfficeMacroFormat.pptx,
      );
      final plan = _compile(_source);
      for (var cycle = 0; cycle < 2; cycle++) {
        final before = session.bytes;
        await session.validate(plan);
        expect(session.bytes, before);
        await session.run(plan);
        final saved = OpcPackage.openBytes(session.bytes);
        expect(saved.getPart('/ppt/presentation.xml')!.contentType, mainType);
        expect(
          saved.contentTypes.contentTypeFor('/ppt/presentation.xml'),
          mainType,
        );
        expect(saved.getPart('/ppt/vbaProject.bin')!.readBytes(), opaque);
        expect(saved.getPart('/ppt/vbaProject.bin')!.contentType, vbaType);
        final retained = saved
            .relationshipsFor('/ppt/presentation.xml')
            .firstByType(relationType)!;
        expect(retained.id, relation.id);
        expect(retained.target, relation.target);
      }
    },
  );
}
