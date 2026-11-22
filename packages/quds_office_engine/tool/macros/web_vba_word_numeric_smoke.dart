import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _example = String.fromEnvironment('WORD_NUMERIC_BAS_BASE64');
const _project = <int>[0, 17, 42, 128, 255];
const _custom = '<numeric-proof xmlns="urn:quds:test">retained</numeric-proof>';
const _macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
const _vbaRelationship =
    'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
const _prefixes = <String>[
  'Abs=8.25; Int=-9; Fix=-8; Sgn=-1: ',
  'Abs=8.25; Int=8; Fix=8; Sgn=1: ',
  'Missing; empty=0: ',
  'Magnitude 8: ',
];
const _suffixes = <String>[
  'body one',
  'body two',
  'body three',
  'report header',
];

OfficeMacro wordNumericSource(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordNumericReport',
    source: source,
  ),
);

OfficeMacro wordNumericPlan(String body) =>
    wordNumericSource('Sub Main()\n$body\nEnd Sub');

Uint8List wordNumericInput({bool macroEnabled = true}) {
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(
            inlines: [
              WmlRun(
                text: 'body ',
                properties: WmlRunProps(
                  italic: true,
                  asciiFont: 'Courier New',
                  fontSizeHalfPoints: 24,
                ),
              ),
              WmlRun(
                text: 'one',
                properties: WmlRunProps(color: '9C0006'),
              ),
            ],
          ),
          WmlParagraph(
            inlines: [
              WmlRun(
                text: 'body two',
                properties: WmlRunProps(bold: true, color: '1F4E79'),
              ),
            ],
          ),
          WmlParagraph(inlines: [WmlRun(text: 'body three')]),
        ],
        header: [
          WmlParagraph(
            inlines: [
              WmlRun(
                text: 'report header',
                properties: WmlRunProps(
                  italic: true,
                  fontSizeHalfPoints: 22,
                  positionHalfPoints: 4,
                ),
              ),
            ],
          ),
        ],
        footer: [
          WmlParagraph(inlines: [WmlRun(text: 'Untouched footer')]),
        ],
        linkToPrevious: false,
      ),
    ],
  );
  final package = OpcPackage.openBytes(WordSerializer().writeBytes(document));
  if (macroEnabled) {
    package.getPart('/word/document.xml')!.contentType = _macroType;
    package.contentTypes.setOverride('/word/document.xml', _macroType);
    package.createPart(
      '/word/vbaProject.bin',
      'application/vnd.ms-office.vbaProject',
      Uint8List.fromList(_project),
    );
    package
        .relationshipsFor('/word/document.xml')
        .add(
          type: _vbaRelationship,
          target: 'vbaProject.bin',
          id: 'rIdNumericProject',
        );
  }
  package.createPart(
    '/customXml/numeric.xml',
    'application/xml',
    Uint8List.fromList(utf8.encode(_custom)),
  );
  return package.save();
}

List<String> wordNumericText(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  return [
    for (final paragraph
        in document.sections.single.blocks.whereType<WmlParagraph>())
      paragraph.text,
    document.sections.single.header.single.text,
    document.sections.single.footer.single.text,
  ];
}

List<XmlElement> _elements(XmlElement root, String name) => [
  for (final child in root.childElements) ...[
    if (child.localName == name && child.namespaceUri == OfficeNamespaces.w)
      child,
    ..._elements(child, name),
  ],
];

void assertWordNumericOutput(
  Uint8List bytes, {
  int repetitions = 1,
  bool macroEnabled = true,
}) {
  final expected = <String>[
    for (var i = 0; i < _prefixes.length; i++)
      '${List<String>.filled(repetitions, _prefixes[i]).join()}${_suffixes[i]}',
    'Untouched footer',
  ];
  if (jsonEncode(wordNumericText(bytes)) != jsonEncode(expected)) {
    throw StateError('Numeric report text or unselected footer changed');
  }
  final document = WordDeserializer().readBytes(bytes);
  final paragraphs = document.sections.single.blocks
      .whereType<WmlParagraph>()
      .toList();
  final firstRuns = paragraphs[0].inlines.whereType<WmlRun>().toList();
  if (!firstRuns.every((run) => run.properties.bold) ||
      !firstRuns.any(
        (run) =>
            run.text.contains('body ') &&
            run.properties.italic &&
            run.properties.asciiFont == 'Courier New' &&
            run.properties.fontSizeHalfPoints == 24,
      ) ||
      !firstRuns.any(
        (run) => run.text.contains('one') && run.properties.color == '9C0006',
      ) ||
      paragraphs[0].properties.indent.left != 8 ||
      paragraphs[1].properties.indent.left != 8 ||
      !paragraphs[1].inlines.whereType<WmlRun>().every(
        (run) => !run.properties.bold && run.properties.color == '1F4E79',
      ) ||
      !document.sections.single.header.single.inlines.whereType<WmlRun>().every(
        (run) =>
            run.properties.positionHalfPoints == -2 &&
            run.properties.italic &&
            run.properties.fontSizeHalfPoints == 22,
      )) {
    throw StateError('Numeric formatting or unrelated rich properties changed');
  }
  final package = OpcPackage.openBytes(bytes);
  if (package.getPart('/customXml/numeric.xml')!.readText() != _custom) {
    throw StateError('Numeric report changed unrelated custom XML');
  }
  if (macroEnabled) {
    final relationship = package
        .relationshipsFor('/word/document.xml')
        .byId('rIdNumericProject');
    if (package.getPart('/word/document.xml')!.contentType != _macroType ||
        base64Encode(package.getPart('/word/vbaProject.bin')!.readBytes()) !=
            base64Encode(_project) ||
        relationship?.type != _vbaRelationship ||
        relationship?.target != 'vbaProject.bin') {
      throw StateError(
        'Numeric report changed inert VBA content or relationships',
      );
    }
  } else if (package.getPart('/word/vbaProject.bin') != null ||
      package.getPart('/word/document.xml')!.contentType == _macroType) {
    throw StateError('Numeric report invented a VBA project');
  }

  // Read OOXML independently of the native property reader: 8 points = 160 twips.
  final body = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!;
  final indents = _elements(body, 'ind');
  final leftTwips = indents
      .map(
        (element) =>
            element.getAttribute('left', namespaceUri: OfficeNamespaces.w),
      )
      .toList();
  if (jsonEncode(leftTwips) != jsonEncode(['160', '160', '0'])) {
    throw StateError('Numeric indentation emitted incorrect OOXML units');
  }
  final bodyText = _elements(body, 'p')
      .map(
        (paragraph) =>
            _elements(paragraph, 't').map((text) => text.text).join(),
      )
      .toList();
  if (jsonEncode(bodyText) != jsonEncode(expected.take(3).toList())) {
    throw StateError('Numeric report emitted incorrect OOXML text');
  }
  final header = package.parts.singleWhere(
    (part) =>
        part.contentType ==
        'application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml',
  );
  final positions = _elements(
    XmlDocument.parse(package.getPart(header.uri)!.readText()).root!,
    'position',
  );
  if (positions.isEmpty ||
      !positions.every(
        (element) =>
            element.getAttribute('val', namespaceUri: OfficeNamespaces.w) ==
            '-2',
      )) {
    throw StateError('Numeric header position emitted incorrect half-points');
  }
}

Future<Map<String, Object?>> runSharedNumericExamples() async {
  final workbook = XlsxWorkbookBuilder();
  workbook.addSheet('Numbers').addRow(<Object?>['Before']);
  final excel = OfficeMacroSession(
    workbook.build(),
    format: OfficeMacroFormat.xlsx,
  );
  final excelPlan = OfficeMacroLanguages().compile(
    OfficeMacroSource(
      language: 'vba-excel',
      format: OfficeMacroFormat.xlsx,
      source: '''
Sub Main()
  Worksheets(1).Range("A1").Value2 = Abs(CVar(-8.25))
  Worksheets(1).Range("A2").Value2 = Int(-8.25)
  Worksheets(1).Range("A3").Value2 = Fix(-8.25)
  Worksheets(1).Range("A4").Value2 = Sgn(-8.25)
End Sub
''',
    ),
  );
  await excel.run(excelPlan);
  final sheet = SheetDeserializer().readBytes(excel.bytes).sheets.single;
  const expected = <num>[8.25, -9, -8, -1];
  for (var i = 0; i < expected.length; i++) {
    if (sheet.cellA1('A${i + 1}').value != expected[i]) {
      throw StateError('Shared numeric function changed the Excel result');
    }
  }
  final deck = OfficeMacroSession(
    SlideSerializer().writeBytes(
      PmlPresentation(
        slides: [
          PmlSlide(
            id: 256,
            shapes: [PmlShape(id: 2, name: 'Title', text: 'Before')],
          ),
        ],
      ),
    ),
    format: OfficeMacroFormat.pptx,
  );
  await deck.run(
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-powerpoint',
        format: OfficeMacroFormat.pptx,
        source: '''
Sub Main()
  With ActivePresentation.Slides(1).Shapes(1)
    .TextFrame.TextRange.Text = CStr(Abs(-8.25)) & "/" & CStr(Int(-8.25)) & "/" & CStr(Fix(-8.25)) & "/" & CStr(Sgn(-8.25))
    .Left = Abs(-12.5)
  End With
End Sub
''',
      ),
    ),
  );
  final shape = SlideDeserializer()
      .readBytes(deck.bytes)
      .slides
      .single
      .shapes
      .single;
  if (shape.text != '8.25/-9/-8/-1' || shape.transform.xPoints != 12.5) {
    throw StateError('Shared numeric function changed the PowerPoint result');
  }
  return {
    'excelValues': expected,
    'powerPointText': shape.text,
    'powerPointLeftPoints': 12.5,
  };
}

Future<Map<String, Object?>> runWordNumericExample(String source) async {
  final input = wordNumericInput();
  final plan = wordNumericSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validated = await session.validate(plan);
  if (!validated.validatedOnly ||
      session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(input)) {
    throw StateError('Validation published a numeric report');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordNumericOutput(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  await session.run(plan);
  assertWordNumericOutput(session.bytes, repetitions: 2);

  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word numeric report');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(recording);
  assertWordNumericOutput(replay.bytes);

  final lateFailure = wordNumericPlan('''
ActiveDocument.Paragraphs(1).Range.InsertBefore CStr(Abs(-7.5))
ActiveDocument.Paragraphs(Int(99.5)).Range.Font.Size = Abs(-12)
''');
  for (final action in [replay.validate, replay.run]) {
    final before = base64Encode(replay.bytes);
    final revision = replay.revision;
    var refused = false;
    try {
      await action(lateFailure);
    } on OfficeMacroException catch (error) {
      refused = error.stepIndex == 1;
    }
    if (!refused ||
        replay.revision != revision ||
        base64Encode(replay.bytes) != before) {
      throw StateError(
        'Late numeric selector failure published partial changes',
      );
    }
  }
  var policyRefusals = 0;
  for (final policy in [
    OfficeMacroPolicy(allowMutation: false),
    OfficeMacroPolicy(allowedTools: {'docx.replaceText'}),
    OfficeMacroPolicy(maxSteps: 8),
  ]) {
    final denied = OfficeMacroSession(
      input,
      format: OfficeMacroFormat.docx,
      policy: policy,
    );
    try {
      await denied.run(plan);
    } on OfficeMacroException {
      policyRefusals++;
    }
    if (denied.revision != 0 ||
        base64Encode(denied.bytes) != base64Encode(input)) {
      throw StateError('A refused numeric report published changes');
    }
  }
  if (policyRefusals != 3) throw StateError('A numeric report bypassed policy');

  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'opaquePartsPreserved': true,
    'richFormattingPreserved': true,
    'nativeXmlUnitsVerified': true,
    'lateRollback': true,
    'policyRefusals': policyRefusals,
    'text': wordNumericText(saved),
    'sharedDialects': await runSharedNumericExamples(),
  };
}

Future<void> main() async {
  if (_example.isEmpty) throw StateError('Supply WORD_NUMERIC_BAS_BASE64');
  print(
    jsonEncode(
      await runWordNumericExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
