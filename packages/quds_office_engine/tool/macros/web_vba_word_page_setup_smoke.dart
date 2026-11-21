import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// Supply the complete committed example on both VM and JavaScript hosts.
const _example = String.fromEnvironment('WORD_PAGE_SETUP_BAS_BASE64');
const _w = OfficeNamespaces.w;
const _extension = 'urn:word-page-setup-example';
const _macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
const _projectType = 'application/vnd.ms-office.vbaProject';
const _projectRelationship =
    'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
const _projectBytes = [0, 42, 127, 128, 255, 10];
const _signatureBytes = [19, 18, 17, 0, 255];
const _opaqueBytes = [3, 4, 5, 0, 250];

OfficeMacro wordPageSetupSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'PageSetupExample',
        source: source,
      ),
    );

OfficeMacro wordPageSetupPlan(String body) =>
    wordPageSetupSource('Sub Main()\n$body\nEnd Sub');

/// Three independently selected sections and opaque package payloads.
Uint8List wordPageSetupInput() {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package.getPart('/word/document.xml')!
    ..writeText('''
<w:document xmlns:w="$_w" xmlns:x="$_extension"><w:body>
<w:p><w:pPr><w:sectPr x:token="first">
<w:pgSz w:w="12240" w:h="15840" w:orient="portrait" w:code="9" x:w="foreign-width"><x:paper x:token="paper"/></w:pgSz>
<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440" w:header="720" w:footer="720" w:gutter="0" x:left="foreign-left"/>
<w:pgNumType w:start="7" w:fmt="upperRoman"/>
<w:cols w:num="2" w:space="360" w:sep="1"/>
<x:sectionTag x:token="preserve-first"/>
</w:sectPr></w:pPr><w:r><w:t>First section</w:t></w:r></w:p>
<w:p><w:pPr><w:sectPr x:token="second">
<w:type w:val="continuous"/><w:pgSz w:w="12000" w:h="16000" w:code="5"/>
<w:pgMar w:top="1000" w:bottom="1200" w:left="1400" w:right="1600" w:header="500" w:footer="600"/>
<w:cols w:num="1" w:space="720"/>
</w:sectPr></w:pPr><w:r><w:t>Second section</w:t></w:r></w:p>
<w:p><w:r><w:t>Untouched section</w:t></w:r></w:p>
<w:sectPr x:token="third"><w:pgSz w:w="14000" w:h="18000" w:code="3"/>
<w:pgMar w:top="900" w:bottom="1000" w:left="1100" w:right="1200" w:header="400" w:footer="500"/>
<w:cols w:num="1" w:space="480"/><x:sectionTag x:token="untouched"/>
</w:sectPr></w:body></w:document>''')
    ..contentType = _macroType;
  package.contentTypes.setOverride('/word/document.xml', _macroType);
  package.createPart(
    '/word/vbaProject.bin',
    _projectType,
    Uint8List.fromList(_projectBytes),
  );
  package.createPart(
    '/word/vbaProjectSignature.bin',
    'application/octet-stream',
    Uint8List.fromList(_signatureBytes),
  );
  package.createPart(
    '/custom/page-setup.bin',
    'application/octet-stream',
    Uint8List.fromList(_opaqueBytes),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(
        type: _projectRelationship,
        target: 'vbaProject.bin',
        id: 'rIdPageSetupProject',
      );
  package
      .relationshipsFor('/word/vbaProject.bin')
      .add(
        type: '${_projectRelationship}Signature',
        target: 'vbaProjectSignature.bin',
        id: 'rIdPageSetupSignature',
      );
  return package.save();
}

XmlElement wordPageSetupSection(Uint8List bytes, int index) =>
    XmlDocument.parse(
      WordDeserializer().readBytes(bytes).sections[index].sourceProperties!.xml,
    ).root!;

num _number(double value) =>
    value == value.truncateToDouble() ? value.toInt() : value;

List<Map<String, Object?>> wordPageSetupState(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  return [
    for (final section in document.sections)
      {
        'text': section.blocks
            .whereType<WmlParagraph>()
            .map((p) => p.text)
            .join(),
        'width': _number(section.pageSize.width),
        'height': _number(section.pageSize.height),
        'top': _number(section.margins.top),
        'bottom': _number(section.margins.bottom),
        'left': _number(section.margins.left),
        'right': _number(section.margins.right),
        'header': _number(section.margins.header),
        'footer': _number(section.margins.footer),
        'columnCount': section.columnCount,
        'columnSpace': _number(section.columnSpace),
        'columnSep': section.columnSep,
        'break': section.breakKind.name,
      },
  ];
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void assertWordPageSetupPackage(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  final project = package
      .relationshipsFor('/word/document.xml')
      .items
      .singleWhere((item) => item.type == _projectRelationship);
  final signature = package
      .relationshipsFor('/word/vbaProject.bin')
      .items
      .single;
  _check(
    package.getPart('/word/document.xml')!.contentType == _macroType &&
        package.getPart('/word/vbaProject.bin')!.contentType == _projectType &&
        base64Encode(package.getPart('/word/vbaProject.bin')!.readBytes()) ==
            base64Encode(_projectBytes) &&
        base64Encode(
              package.getPart('/word/vbaProjectSignature.bin')!.readBytes(),
            ) ==
            base64Encode(_signatureBytes) &&
        base64Encode(package.getPart('/custom/page-setup.bin')!.readBytes()) ==
            base64Encode(_opaqueBytes) &&
        project.id == 'rIdPageSetupProject' &&
        project.target == 'vbaProject.bin' &&
        signature.id == 'rIdPageSetupSignature' &&
        signature.target == 'vbaProjectSignature.bin' &&
        signature.type == '${_projectRelationship}Signature',
    'Page setup changed an opaque payload or its relationship',
  );
}

void assertWordPageSetupExample(Uint8List bytes) {
  final states = wordPageSetupState(bytes);
  final original = wordPageSetupState(wordPageSetupInput());
  final expected = <Map<String, Object?>>[
    {
      ...original[0],
      'width': 648,
      'height': 864,
      'top': 72,
      'bottom': 54,
      'left': 54,
      'right': 54,
      'header': 36,
      'footer': 36,
    },
    {...original[1], 'left': 36, 'right': 36},
    original[2],
  ];
  _check(
    jsonEncode(states) == jsonEncode(expected),
    'Page setup changed the wrong section or produced wrong geometry: $states',
  );
  final first = wordPageSetupSection(bytes, 0);
  final size = first.firstChild('pgSz', namespaceUri: _w)!;
  final margins = first.firstChild('pgMar', namespaceUri: _w)!;
  _check(
    size.getAttribute('code', namespaceUri: _w) == null &&
        size.getAttribute('orient', namespaceUri: _w) == 'portrait' &&
        size.getAttribute('w', namespaceUri: _extension) == 'foreign-width' &&
        size
                .firstChild('paper', namespaceUri: _extension)!
                .getAttribute('token', namespaceUri: _extension) ==
            'paper' &&
        margins.getAttribute('gutter', namespaceUri: _w) == '0' &&
        margins.getAttribute('left', namespaceUri: _extension) ==
            'foreign-left' &&
        first
                .firstChild('pgNumType', namespaceUri: _w)!
                .getAttribute('start', namespaceUri: _w) ==
            '7' &&
        first
                .firstChild('sectionTag', namespaceUri: _extension)!
                .getAttribute('token', namespaceUri: _extension) ==
            'preserve-first' &&
        wordPageSetupSection(bytes, 1)
                .firstChild('pgSz', namespaceUri: _w)!
                .getAttribute('code', namespaceUri: _w) ==
            '5' &&
        wordPageSetupSection(bytes, 2)
                .firstChild('sectionTag', namespaceUri: _extension)!
                .getAttribute('token', namespaceUri: _extension) ==
            'untouched',
    'Page setup lost unrelated native or extension metadata',
  );
  assertWordPageSetupPackage(bytes);
}

Future<Map<String, Object?>> runWordPageSetupExample(String source) async {
  final input = wordPageSetupInput();
  final original = base64Encode(input);
  final plan = wordPageSetupSource(source);
  const expected = <(int, String, num)>[
    (0, 'width', 648),
    (0, 'height', 864),
    (0, 'top', 72),
    (0, 'bottom', 54),
    (0, 'left', 54),
    (0, 'right', 54),
    (0, 'header', 36),
    (0, 'footer', 36),
    (1, 'left', 36),
    (1, 'right', 36),
  ];
  _check(plan.steps.length == expected.length, 'Wrong example operation count');
  for (var i = 0; i < expected.length; i++) {
    final (section, property, points) = expected[i];
    final step = plan.steps[i];
    _check(
      step.tool == 'docx.pageSetup' &&
          step.arguments.length == 3 &&
          step.arguments['section'] == section &&
          step.arguments['property'] == property &&
          step.arguments['points'] == points,
      'Page setup example step $i differs from its declared operation',
    );
  }
  final guard = (await WordPackagePreservation.capture(input, 'pages.docm'))!;
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == expected.length &&
        session.revision == 0 &&
        base64Encode(session.bytes) == original,
    'Page setup dry-run published an edit',
  );
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  _check(
    result.completedSteps == expected.length &&
        result.revision == 1 &&
        !result.validatedOnly &&
        base64Encode(input) == original,
    'Page setup did not publish exactly one detached transaction',
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordPageSetupExample(saved);
    await guard.validateSaved(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  await session.run(plan);
  assertWordPageSetupExample(session.bytes);
  _check(session.revision == 2, 'Example replay was not repeatable');
  return {
    'operations': expected.length,
    'firstRunRevision': result.revision,
    'repeatedRevision': session.revision,
    'additionalReopens': 2,
    'opaquePayloadsPreserved': true,
    'sections': wordPageSetupState(saved),
  };
}

Future<Map<String, Object?>> runWordPageSetupRollback() async {
  final input = wordPageSetupInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Page setup rollback');
  final plan = wordPageSetupPlan('''
ActiveDocument.Sections(1).PageSetup.PageWidth = 648
ActiveDocument.Sections(2).PageSetup.TopMargin = 800
''');
  for (final action in [session.validate, session.run]) {
    try {
      await action(plan);
      throw StateError('Invalid geometry unexpectedly succeeded');
    } on OfficeMacroException catch (error) {
      _check(
        error.code == 'operation_failed' &&
            error.stepIndex == 1 &&
            error.tool == 'docx.pageSetup',
        'Invalid geometry did not fail at the expected native step',
      );
    }
    _check(
      session.revision == 0 &&
          base64Encode(session.bytes) == base64Encode(input),
      'Failed geometry published a partial edit',
    );
  }
  _check(session.stopRecording().steps.isEmpty, 'Failed playback was recorded');
  return {'failedStep': 1, 'validateAndRunRollback': true};
}

Future<Map<String, Object?>> runWordPageSetupRecording() async {
  final input = wordPageSetupInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Section dimensions');
  await session.callTool('docx.pageSetup', {
    'section': 0,
    'property': 'width',
    'points': 648,
  });
  await session.callTool('docx.pageSetup', {
    'section': 1,
    'property': 'left',
    'points': 36,
  });
  final beforeFailure = base64Encode(session.bytes);
  try {
    await session.callTool('docx.pageSetup', {
      'section': 99,
      'property': 'header',
      'points': 12,
    });
    throw StateError('Missing section unexpectedly succeeded');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed') rethrow;
  }
  final recorded = session.stopRecording();
  _check(
    recorded.steps.length == 2 &&
        session.revision == 2 &&
        base64Encode(session.bytes) == beforeFailure,
    'Failed page setup changed the recording or document',
  );
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recorded.encode()));
  _check(
    replay.revision == 1 &&
        jsonEncode(wordPageSetupState(replay.bytes)) ==
            jsonEncode(wordPageSetupState(session.bytes)),
    'Recorded page setup changed meaning on replay',
  );
  assertWordPageSetupPackage(replay.bytes);
  return {'recordedSteps': 2, 'failedCallExcluded': true, 'replayRevision': 1};
}

Future<void> main() async {
  _check(_example.isNotEmpty, 'Supply the exact BAS in the compile define');
  final source = utf8.decode(base64Decode(_example));
  print(
    jsonEncode({
      'example': await runWordPageSetupExample(source),
      'rollback': await runWordPageSetupRollback(),
      'recording': await runWordPageSetupRecording(),
    }),
  );
}
