import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-powerpoint',
    format: OfficeMacroFormat.pptx,
    moduleName: 'PortablePresentation',
    source: source,
  ),
);

Uint8List _deck({bool groupedSecondSlide = false}) =>
    SlideSerializer().writeBytes(
      PmlPresentation(
        slides: <PmlSlide>[
          PmlSlide(
            id: 256,
            shapes: <PmlShape>[
              PmlShape(id: 2, name: 'Title', text: 'Original'),
              PmlShape(id: 3, name: 'Body', text: 'Keep this body'),
            ],
          ),
          PmlSlide(
            id: 257,
            shapes: <PmlShape>[
              PmlShape(
                id: 2,
                name: 'Title',
                text: 'Second slide',
                groupId: groupedSecondSlide ? 7 : null,
              ),
              if (groupedSecondSlide)
                PmlShape(id: 3, name: 'Group child', text: 'Child', groupId: 7),
            ],
          ),
        ],
      ),
    );

List<XmlElement> _elements(XmlElement root, String name) => <XmlElement>[
  for (final child in root.childElements) ...<XmlElement>[
    if (child.localName == name && child.namespaceUri == OfficeNamespaces.a)
      child,
    ..._elements(child, name),
  ],
];

Future<void> _expectFailure(
  Future<Object?> Function() run,
  String code, {
  int? step,
}) async {
  try {
    await run();
  } on OfficeMacroException catch (error) {
    if (error.code != code || (step != null && error.stepIndex != step)) {
      rethrow;
    }
    return;
  }
  throw StateError('Expected $code, but the presentation operation succeeded');
}

/// Execute real PPTX transactions on the VM or compiled JavaScript.
Future<void> main() async {
  final original = _deck();
  final originalBytes = base64Encode(original);
  final session = OfficeMacroSession(original, format: OfficeMacroFormat.pptx);
  final plan = _compile('''
Option Explicit
Sub Caption(ByVal target As Shape, ByVal label As String)
  target.TextFrame.TextRange.Text = label
End Sub
Sub Main()
  Dim values(1 To 2) As Variant, target As Shape
  values(1) = "2.5"
  Set target = Application.ActivePresentation.Slides.Item(1).Shapes.Item("Title")
  Call Caption(target, "Total " & CStr(CLng(values(1))) & " 😀")
  With target.TextFrame.TextRange
    .Font.Name = "Aptos"
    .Font.Size = 24.25
    .Font.Bold = msoTrue
    .Font.Italic = msoTrue
    .Font.Italic = msoFalse
    .Font.Underline = msoTrue
    .Font.Color.RGB = RGB(17, 34, 51)
    .ParagraphFormat.Alignment = ppAlignCenter
  End With
  target.Left = 24.5
  target.Top = 12
  target.Width = 240
  target.Height = 72
  target.Rotation = -15
  If IsEmpty(values(2)) Then
    ActivePresentation.Slides(2).Shapes(1).TextFrame.TextRange.Text = "Empty slot"
  End If
End Sub
''');
  if (plan.steps.length != 15 || plan.format != OfficeMacroFormat.pptx) {
    throw StateError('Unexpected native PowerPoint plan');
  }
  session.startRecording('Portable PowerPoint transaction');
  await session.validate(plan);
  if (base64Encode(session.bytes) != originalBytes || session.revision != 0) {
    throw StateError('PowerPoint validation published a document');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  final deck = SlideDeserializer().readBytes(session.bytes);
  final title = deck.slides.first.shapes.first;
  if (session.revision != 1 ||
      title.text != 'Total 2 😀' ||
      title.fontSizePt != 24.25 ||
      title.textColor != '112233' ||
      title.textAlign != PmlTextAlign.center ||
      title.transform.xPoints != 24.5 ||
      title.transform.yPoints != 12 ||
      title.transform.widthPoints != 240 ||
      title.transform.heightPoints != 72 ||
      title.transform.rotationDegrees != -15 ||
      deck.slides.first.shapes[1].text != 'Keep this body' ||
      deck.slides[1].shapes.first.text != 'Empty slot') {
    throw StateError('PowerPoint text, formatting or geometry did not survive');
  }
  final runs = title.resolvedRichText
      .expand((paragraph) => paragraph.runs)
      .toList();
  if (runs.isEmpty ||
      runs.any(
        (run) =>
            run.fontFamily != 'Aptos' ||
            !run.bold ||
            run.italic ||
            !run.underline,
      )) {
    throw StateError('PowerPoint font flags or explicit false were lost');
  }
  // Read serialized units directly, independently of the shape model reader.
  final xml = XmlDocument.parse(
    OpcPackage.openBytes(
      session.bytes,
    ).getPart('/ppt/slides/slide1.xml')!.readText(),
  ).root!;
  final properties = _elements(xml, 'rPr').first;
  if (properties.getAttribute('sz') != '2425' ||
      properties.getAttribute('b') != '1' ||
      properties.getAttribute('i') != '0' ||
      properties.getAttribute('u') != 'sng' ||
      _elements(properties, 'latin').single.getAttribute('typeface') !=
          'Aptos' ||
      _elements(xml, 'off').first.getAttribute('x') != '311150') {
    throw StateError('PowerPoint output XML changed the requested values');
  }

  final beforeFailure = base64Encode(session.bytes);
  final failing = _compile('''
Sub Main()
  ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text = "Discard me"
  ActivePresentation.Slides(2).Shapes("Missing").TextFrame.TextRange.Font.Bold = True
End Sub
''');
  await _expectFailure(
    () => session.validate(failing),
    'operation_failed',
    step: 1,
  );
  await _expectFailure(() => session.run(failing), 'operation_failed', step: 1);
  if (base64Encode(session.bytes) != beforeFailure ||
      session.revision != 1 ||
      session.stopRecording().steps.isNotEmpty) {
    throw StateError('Failed PowerPoint runs changed bytes or recording');
  }

  final grouped = OfficeMacroSession(
    _deck(groupedSecondSlide: true),
    format: OfficeMacroFormat.pptx,
  );
  final groupedBytes = base64Encode(grouped.bytes);
  final unsafeIndex = _compile('''
Sub Main()
  ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text = "Discard me"
  ActivePresentation.Slides(2).Shapes(1).TextFrame.TextRange.Text = "Group index"
End Sub
''');
  await _expectFailure(
    () => grouped.run(unsafeIndex),
    'operation_failed',
    step: 1,
  );
  if (base64Encode(grouped.bytes) != groupedBytes || grouped.revision != 0) {
    throw StateError('A grouped-shape selector published partial changes');
  }

  final readOnly = OfficeMacroSession(
    original,
    format: OfficeMacroFormat.pptx,
    policy: OfficeMacroPolicy(allowMutation: false),
  );
  await _expectFailure(() => readOnly.run(plan), 'permission_denied');
  if (base64Encode(readOnly.bytes) != originalBytes || readOnly.revision != 0) {
    throw StateError('Read-only PowerPoint session changed');
  }
  final mcp = OfficeMacroMcp(session);
  final compiled = await mcp.callTool('office_macro_compile', {
    'source': {
      'language': 'vba-powerpoint',
      'format': 'pptx',
      'source': '''
Sub Main()
  ActivePresentation.Slides(2).Shapes("Title").TextFrame.TextRange.Text = "MCP complete"
End Sub
''',
    },
  });
  if (compiled['isError'] != false || session.revision != 1) {
    throw StateError('PowerPoint MCP compilation failed or mutated the deck');
  }
  final content = compiled['structuredContent']! as Map<String, Object?>;
  final executed = await mcp.callTool('office_macro_run', {
    'macro': content['macro'],
  });
  final finalDeck = SlideDeserializer().readBytes(session.bytes);
  if (executed['isError'] != false ||
      session.revision != 2 ||
      finalDeck.slides[1].shapes.first.text != 'MCP complete') {
    throw StateError('PowerPoint MCP execution failed');
  }
  print(
    jsonEncode({
      'language': 'vba-powerpoint',
      'steps': plan.steps.length,
      'slides': finalDeck.slides.length,
      'title': title.text,
      'fontSize': title.fontSizePt,
      'rgb': title.textColor,
      'left': title.transform.xPoints,
      // Report the exact integer units so VM/JS JSON numeric spelling agrees.
      'rotationNativeUnits': title.transform.rot,
      'mcpText': finalDeck.slides[1].shapes.first.text,
      'revision': session.revision,
      'immutableValidation': true,
      'explicitFalsePreserved': true,
      'lateFailurePreservedBytesAndRecording': true,
      'groupSelectorRollback': true,
      'readOnlyPolicy': true,
      'mcpCompileAndRun': true,
    }),
  );
}
