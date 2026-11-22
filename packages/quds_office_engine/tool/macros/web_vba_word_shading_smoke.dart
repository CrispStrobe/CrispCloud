import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _example = String.fromEnvironment('WORD_SHADING_BAS_BASE64');
const _project = <int>[0, 42, 127, 128, 255];
const _customXml = '<review xmlns="urn:word-shading-example">preserve</review>';
const _w = OfficeNamespaces.w;
const _extension = 'urn:word-shading-example';
const _first = 'ActiveDocument.Paragraphs(1).Shading';
const _second = 'ActiveDocument.Paragraphs(2).Range.Shading';

OfficeMacro wordShadingSource(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordShading',
    source: source,
  ),
);

OfficeMacro wordShadingPlan(String body) =>
    wordShadingSource('Sub Main()\n$body\nEnd Sub');

/// Three body paragraphs (including an empty one), independent primary stories,
/// opaque macro bytes and custom XML. The first shading owns foreign metadata.
Uint8List wordShadingInput() {
  WmlParagraph paragraph(String text, String color) => WmlParagraph(
    properties: WmlParagraphProps(shadingFill: color, spacingAfter: 9),
    inlines: [
      if (text.isNotEmpty)
        WmlRun(
          text: text,
          properties: WmlRunProps(
            bold: true,
            color: '2468AC',
            fontSizeHalfPoints: 24,
            proofingLanguage: 'de-DE',
          ),
        ),
    ],
  );
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          paragraph('Straße 😀 العربية', '334455'),
          paragraph('Résumé', 'DDEEFF'),
          paragraph('', 'FFCC00'),
        ],
        header: [paragraph('En-tête', '112233')],
        footer: [paragraph('Footer العربية', '445566')],
        linkToPrevious: false,
      ),
    ],
  );
  final package = OpcPackage.openBytes(WordSerializer().writeBytes(document));
  final main = package.getPart('/word/document.xml')!;
  const initial = '<w:shd w:val="clear" w:fill="334455"/>';
  _check(main.readText().contains(initial), 'Fixture shading was not emitted');
  main.writeText(
    main.readText().replaceFirst(
      initial,
      '<w:shd w:val="clear" w:color="auto" w:fill="334455" '
      'xmlns:x="$_extension" x:fill="unowned-fill" x:token="preserve">'
      '<x:metadata x:token="nested"/></w:shd>',
    ),
  );
  const macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
  main.contentType = macroType;
  package.contentTypes.setOverride('/word/document.xml', macroType);
  package.createPart(
    '/word/vbaProject.bin',
    'application/vnd.ms-office.vbaProject',
    Uint8List.fromList(_project),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(
        type:
            'http://schemas.microsoft.com/office/2006/relationships/vbaProject',
        target: 'vbaProject.bin',
        id: 'rIdShadingProject',
      );
  package.createPart(
    '/customXml/item1.xml',
    'application/xml',
    Uint8List.fromList(utf8.encode(_customXml)),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(
        type: '${OfficeNamespaces.r}/customXml',
        target: '../customXml/item1.xml',
        id: 'rIdShadingMetadata',
      );
  return package.save();
}

List<Map<String, Object?>> wordShadingState(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  return [
    for (final paragraph in [
      ...document.sections.single.blocks.whereType<WmlParagraph>(),
      ...document.sections.single.header,
      ...document.sections.single.footer,
    ])
      {
        'text': paragraph.text,
        'fill': paragraph.properties.shadingFill,
        'spacingAfterTwips': (paragraph.properties.spacingAfter * 20).round(),
        'runs': [
          for (final run in paragraph.inlines.whereType<WmlRun>())
            {
              'text': run.text,
              'bold': run.properties.bold,
              'color': run.properties.color,
              'size': run.properties.fontSizeHalfPoints,
              'language': run.properties.proofingLanguage,
            },
        ],
      },
  ];
}

List<String?> wordShadingNativeFills(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  final document = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!.firstChild('body', namespaceUri: _w)!;
  final storyRoots = <XmlElement>[
    document,
    for (final prefix in ['header', 'footer'])
      for (final part in package.parts.where(
        (part) =>
            part.uri.startsWith('/word/$prefix') && part.uri.endsWith('.xml'),
      ))
        XmlDocument.parse(package.getPart(part.uri)!.readText()).root!,
  ];
  return [
    for (final root in storyRoots)
      for (final paragraph in root.childrenNamed('p', namespaceUri: _w))
        paragraph
            .firstChild('pPr', namespaceUri: _w)
            ?.firstChild('shd', namespaceUri: _w)
            ?.getAttribute('fill', namespaceUri: _w),
  ];
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void assertWordShadingPackage(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  _check(
    base64Encode(package.getPart('/word/vbaProject.bin')!.readBytes()) ==
            base64Encode(_project) &&
        package.getPart('/customXml/item1.xml')!.readText() == _customXml &&
        package.getPart('/word/document.xml')!.contentType ==
            'application/vnd.ms-word.document.macroEnabled.main+xml',
    'Shading changed an opaque payload or DOCM content type',
  );
  final shading =
      XmlDocument.parse(package.getPart('/word/document.xml')!.readText()).root!
          .firstChild('body', namespaceUri: _w)!
          .firstChild('p', namespaceUri: _w)!
          .firstChild('pPr', namespaceUri: _w)!
          .firstChild('shd', namespaceUri: _w)!;
  _check(
    shading.getAttribute('fill', namespaceUri: _extension) == 'unowned-fill' &&
        shading.getAttribute('token', namespaceUri: _extension) == 'preserve' &&
        shading
                .firstChild('metadata', namespaceUri: _extension)
                ?.getAttribute('token', namespaceUri: _extension) ==
            'nested',
    'Shading dropped foreign attributes or nested metadata',
  );
}

void assertWordShadingExample(Uint8List bytes) {
  final original = wordShadingState(wordShadingInput());
  // Automatic is an explicit native override; the rendering model uses null.
  const expectedFills = <String?>['123456', null, 'C0C0C0', '00FFFF', null];
  final expected = [
    for (var i = 0; i < original.length; i++)
      {...original[i], 'fill': expectedFills[i]},
  ];
  final actual = wordShadingState(bytes);
  _check(
    jsonEncode(actual) == jsonEncode(expected),
    'Shading changed text, another format or the wrong paragraph: $actual',
  );
  _check(
    jsonEncode(wordShadingNativeFills(bytes)) ==
        jsonEncode(['123456', 'auto', 'C0C0C0', '00FFFF', 'auto']),
    'Shading lost explicit native colors or an automatic direct override',
  );
  assertWordShadingPackage(bytes);
}

Future<Map<String, Object?>> runWordShadingExample(String source) async {
  final input = wordShadingInput();
  final plan = wordShadingSource(source);
  _check(plan.steps.length == 7, 'Expected seven paragraph-shading operations');
  _check(
    plan.steps.every((step) => step.tool == 'docx.paragraphShading') &&
        plan.steps.map((step) => step.arguments['color']).join(',') ==
            '123456,FFFF00,auto,C0C0C0,00FFFF,123456,auto',
    'Packed RGB, palette or automatic colors compiled incorrectly',
  );
  final guard = (await WordPackagePreservation.capture(input, 'shading.docm'))!;
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Playback is separate from native recording');
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == 7 &&
        session.revision == 0 &&
        base64Encode(session.bytes) == base64Encode(input),
    'Shading validation published a detached edit',
  );
  final run = await session.run(OfficeMacro.parse(plan.encode()));
  _check(
    run.completedSteps == 7 &&
        session.revision == 1 &&
        session.stopRecording().steps.isEmpty,
    'Shading did not publish one transaction or recorded macro playback',
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordShadingExample(saved);
    await guard.validateSaved(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word paragraph shading');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  _check(recording.steps.length == 7, 'Native shading edits were not recorded');
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recording.encode()));
  assertWordShadingExample(replay.bytes);
  await guard.validateSaved(replay.bytes);
  await session.run(plan);
  assertWordShadingExample(session.bytes);
  _check(session.revision == 2, 'Repeated shading lost its revision');
  final package = OpcPackage.openBytes(saved);
  final parts =
      package.parts
          .where(
            (part) =>
                part.uri == '/word/document.xml' ||
                part.uri.startsWith('/word/header') ||
                part.uri.startsWith('/word/footer') ||
                part.uri == '/word/vbaProject.bin' ||
                part.uri == '/customXml/item1.xml',
          )
          .toList()
        ..sort((a, b) => a.uri.compareTo(b.uri));
  return {
    'operations': plan.steps.length,
    'revision': run.revision,
    'repeatedRevision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'opaquePayloadsPreserved': true,
    'plan': [for (final step in plan.steps) step.toJson()],
    'state': wordShadingState(saved),
    'nativeFills': wordShadingNativeFills(saved),
    'nativePartSha256': {
      for (final part in parts)
        part.uri: sha256
            .convert(package.getPart(part.uri)!.readBytes())
            .toString(),
    },
  };
}

Future<Map<String, Object?>> runWordShadingRollback() async {
  final input = wordShadingInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Rejected shading');
  final plan = wordShadingPlan('''
$_first.BackgroundPatternColor = RGB(1, 2, 3)
ActiveDocument.Paragraphs(99).Shading.BackgroundPatternColorIndex = wdYellow
''');
  for (final action in [session.validate, session.run]) {
    try {
      await action(plan);
      throw StateError('Missing paragraph unexpectedly succeeded');
    } on OfficeMacroException catch (error) {
      _check(
        error.stepIndex == 1 && error.tool == 'docx.paragraphShading',
        'Shading failure lost native operation attribution',
      );
    }
    _check(
      session.revision == 0 &&
          base64Encode(session.bytes) == base64Encode(input),
      'Failed shading published a prefix edit',
    );
  }
  _check(session.stopRecording().steps.isEmpty, 'Failed shading was recorded');
  return {'failedStep': 1, 'validateAndRunRollback': true};
}

Future<Map<String, Object?>> runWordShadingPolicy() async {
  final input = wordShadingInput();
  final plan = wordShadingPlan('''
$_first.BackgroundPatternColor = RGB(1, 2, 3)
$_second.BackgroundPatternColorIndex = wdYellow
''');
  var denied = 0;
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
      try {
        await action(plan);
        throw StateError('Restricted shading unexpectedly succeeded');
      } on OfficeMacroException catch (error) {
        _check(error.code == code, 'Wrong shading policy failure');
      }
      _check(
        session.revision == 0 &&
            base64Encode(session.bytes) == base64Encode(input),
        'Policy rejection published part of a shading plan',
      );
      denied++;
    }
  }
  final allowed = OfficeMacroSession(
    input,
    format: OfficeMacroFormat.docx,
    policy: OfficeMacroPolicy(
      allowedTools: {'docx.paragraphShading'},
      maxSteps: 2,
    ),
  );
  final result = await allowed.run(plan);
  _check(
    result.completedSteps == 2 && allowed.revision == 1,
    'Explicitly allowed shading did not run',
  );
  return {'atomicDenials': denied, 'allowedSteps': result.completedSteps};
}

Future<void> main() async {
  _check(
    _example.isNotEmpty,
    'Supply the committed BAS in WORD_SHADING_BAS_BASE64',
  );
  print(
    jsonEncode({
      'example': await runWordShadingExample(
        utf8.decode(base64Decode(_example)),
      ),
      'rollback': await runWordShadingRollback(),
      'policy': await runWordShadingPolicy(),
    }),
  );
}
