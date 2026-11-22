import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_page_setup_smoke.dart' as package_fixture;

const _example = String.fromEnvironment('WORD_STYLES_BAS_BASE64');
const _w = OfficeNamespaces.w;
const _x = 'urn:word-style-example';

OfficeMacro wordStylesSource(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'StylesExample',
    source: source,
  ),
);

OfficeMacro wordStylesPlan(String body) =>
    wordStylesSource('Option Explicit\nSub Main()\n$body\nEnd Sub');

/// An existing style catalog, direct formatting, an independent header and
/// opaque DOCM payloads. Built-in identities deliberately differ from IDs.
Uint8List wordStylesInput() {
  final package = OpcPackage.openBytes(package_fixture.wordPageSetupInput());
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="$_w" xmlns:r="${OfficeNamespaces.r}" xmlns:x="$_x"><w:body>
<w:p><w:pPr><w:pStyle w:val="Base" x:val="foreign-value" x:tag="style"><x:annotation x:token="keep"/></w:pStyle><w:spacing w:before="60"/><x:keep x:token="paragraph"/></w:pPr><w:r><w:rPr><w:rStyle w:val="Accent"/><w:color w:val="AA0000"/></w:rPr><w:t>Report heading</w:t></w:r></w:p>
<w:p><w:pPr><w:spacing w:after="80"/></w:pPr><w:r><w:t>Report body</w:t></w:r></w:p>
<w:p><w:r><w:t>Figure caption</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="BodyCustom"/></w:pPr><w:r><w:t>Untouched paragraph</w:t></w:r></w:p>
<w:sectPr><w:headerReference w:type="default" r:id="rIdStyleHeader"/><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440" w:header="720" w:footer="720"/></w:sectPr>
</w:body></w:document>''');
  final styles =
      package.getPart('/word/styles.xml') ??
      package.createPart('/word/styles.xml', OfficeContentTypes.wordStyles);
  styles.writeText('''
<w:styles xmlns:w="$_w" xmlns:x="$_x">
<w:style w:type="paragraph" w:styleId="Base" w:default="1"><w:name w:val="Normal"/><w:pPr><w:spacing w:after="0"/></w:pPr><w:rPr><w:sz w:val="22"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="HeadingNative"><w:name w:val="heading 1"/><w:basedOn w:val="Base"/><w:pPr><w:spacing w:after="240"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b w:val="0"/><w:sz w:val="32"/><w:color w:val="224466"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="BodyCustom" w:customStyle="1"><w:name w:val="Report Body"/><w:basedOn w:val="Base"/><w:pPr><w:spacing w:after="160"/></w:pPr><w:rPr><w:sz w:val="24"/></w:rPr><x:definition x:token="unchanged"/></w:style>
<w:style w:type="paragraph" w:styleId="CaptionNative"><w:name w:val="caption"/><w:basedOn w:val="Base"/><w:pPr><w:jc w:val="center"/></w:pPr></w:style>
<w:style w:type="character" w:styleId="Accent"><w:name w:val="Accent"/><w:rPr><w:i/><w:color w:val="00AA00"/></w:rPr></w:style>
</w:styles>''');
  final relationships = package.relationshipsFor('/word/document.xml');
  if (relationships.byType(RelationshipTypes.styles).isEmpty) {
    relationships.add(type: RelationshipTypes.styles, target: 'styles.xml');
  }
  package
      .createPart('/word/header1.xml', OfficeContentTypes.wordHeader)
      .writeText(
        '<w:hdr xmlns:w="$_w"><w:p><w:r><w:t>Independent header</w:t></w:r></w:p></w:hdr>',
      );
  relationships.add(
    type: RelationshipTypes.header,
    target: 'header1.xml',
    id: 'rIdStyleHeader',
  );
  return package.save();
}

List<Map<String, Object?>> wordStylesState(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  return [
    for (final paragraph in [
      ...document.paragraphs,
      ...document.sections.first.header,
    ])
      {
        'text': paragraph.text,
        'style': paragraph.properties.styleId,
        'before': paragraph.properties.spacingBefore,
        'after': paragraph.properties.spacingAfter,
        'runs': [
          for (final run in paragraph.inlines.whereType<WmlRun>())
            {
              'bold': run.properties.bold,
              'italic': run.properties.italic,
              'color': run.properties.color,
              'size': run.properties.fontSizePoints,
            },
        ],
      },
  ];
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void assertWordStylesExample(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  final paragraphs = document.paragraphs.toList();
  _check(
    paragraphs.map((p) => p.properties.styleId).join(',') ==
        'HeadingNative,BodyCustom,CaptionNative,BodyCustom',
    'Style assignments selected the wrong native styles',
  );
  final title = paragraphs[0].inlines.whereType<WmlRun>().single;
  final caption = paragraphs[2].inlines.whereType<WmlRun>().single;
  _check(
    title.properties.bold &&
        title.properties.italic &&
        title.properties.color == 'AA0000' &&
        title.properties.fontSizePoints == 16 &&
        paragraphs[0].properties.spacingBefore == 3 &&
        paragraphs[0].properties.spacingAfter == 12 &&
        paragraphs[1].properties.spacingAfter == 4 &&
        paragraphs[1].inlines
                .whereType<WmlRun>()
                .single
                .properties
                .fontSizePoints ==
            12 &&
        paragraphs[2].properties.justification == WmlJustification.center &&
        caption.properties.italic,
    'Style cascade lost direct formatting or pending operations',
  );
  final package = OpcPackage.openBytes(bytes);
  final root = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!;
  final properties = root
      .firstChild('body', namespaceUri: _w)!
      .childrenNamed('p', namespaceUri: _w)
      .first
      .firstChild('pPr', namespaceUri: _w)!;
  final reference = properties.firstChild('pStyle', namespaceUri: _w)!;
  _check(
    reference.getAttribute('val', namespaceUri: _x) == 'foreign-value' &&
        reference.getAttribute('tag', namespaceUri: _x) == 'style' &&
        reference
                .firstChild('annotation', namespaceUri: _x)
                ?.getAttribute('token', namespaceUri: _x) ==
            'keep' &&
        properties
                .firstChild('keep', namespaceUri: _x)
                ?.getAttribute('token', namespaceUri: _x) ==
            'paragraph',
    'A style reference edit dropped unrelated source metadata',
  );
  final original = wordStylesState(wordStylesInput());
  final current = wordStylesState(bytes);
  _check(
    jsonEncode(current.skip(3).toList()) ==
        jsonEncode(original.skip(3).toList()),
    'Style assignment changed an unselected paragraph or header',
  );
  package_fixture.assertWordPageSetupPackage(bytes);
}

Future<Map<String, Object?>> runWordStylesExample(String source) async {
  final input = wordStylesInput();
  final before = base64Encode(input);
  final macro = wordStylesSource(source);
  _check(macro.steps.length == 5, 'Unexpected committed example length');
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final guard = (await WordPackagePreservation.capture(input, 'styles.docm'))!;
  final validation = await session.validate(macro);
  _check(
    validation.validatedOnly &&
        session.revision == 0 &&
        base64Encode(session.bytes) == before,
    'Validation published edits',
  );
  await session.run(OfficeMacro.parse(macro.encode()));
  _check(
    session.revision == 1 && base64Encode(input) == before,
    'Execution did not preserve the detached input',
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordStylesExample(saved);
    await guard.validateSaved(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  await session.run(macro);
  assertWordStylesExample(session.bytes);
  return {
    'operations': 5,
    'revision': session.revision,
    'additionalReopens': 2,
    'opaquePayloadsPreserved': true,
  };
}

Future<Map<String, Object?>> runWordStylesRollback() async {
  final input = wordStylesInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final macro = wordStylesPlan('''
ActiveDocument.Paragraphs(1).Style = wdStyleHeading1
ActiveDocument.Paragraphs(2).Style = "Missing style"
''');
  session.startRecording('Style rollback');
  for (final action in [session.validate, session.run]) {
    try {
      await action(macro);
      throw StateError('Missing style unexpectedly resolved');
    } on OfficeMacroException catch (error) {
      _check(
        error.code == 'operation_failed' &&
            error.stepIndex == 1 &&
            error.tool == 'docx.paragraphStyle',
        'Failure lost native attribution',
      );
    }
    _check(
      session.revision == 0 &&
          base64Encode(session.bytes) == base64Encode(input),
      'Failed style assignment published a partial transaction',
    );
  }
  _check(
    session.stopRecording().steps.isEmpty,
    'Failed operations were recorded',
  );
  return {'failedStep': 1, 'validateAndRunRollback': true};
}

Future<Map<String, Object?>> runWordStylesRecording() async {
  final input = wordStylesInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Paragraph styles');
  await session.callTool('docx.paragraphStyle', {
    'paragraph': 0,
    'builtin': -2,
  });
  await session.callTool('docx.paragraphStyle', {
    'paragraph': 1,
    'name': 'report body',
  });
  final before = base64Encode(session.bytes);
  try {
    await session.callTool('docx.paragraphStyle', {
      'paragraph': 99,
      'builtin': -1,
    });
    throw StateError('Missing paragraph unexpectedly resolved');
  } on OfficeMacroException catch (error) {
    _check(error.code == 'operation_failed', 'Wrong failed call attribution');
  }
  final macro = session.stopRecording();
  _check(
    macro.steps.length == 2 &&
        session.revision == 2 &&
        base64Encode(session.bytes) == before,
    'Recording included a failed edit',
  );
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(macro.encode()));
  _check(
    jsonEncode(wordStylesState(replay.bytes)) ==
        jsonEncode(wordStylesState(session.bytes)),
    'Replayed styles differ from recorded styles',
  );
  return {
    'recordedSteps': 2,
    'failedCallExcluded': true,
    'replayRevision': replay.revision,
  };
}

Future<Map<String, Object?>> runWordStylesPolicy() async {
  final input = wordStylesInput();
  final macro = wordStylesPlan('''
ActiveDocument.Paragraphs(1).Style = wdStyleHeading1
ActiveDocument.Paragraphs(2).Style = "Report Body"
''');
  var denials = 0;
  for (final (policy, code) in <(OfficeMacroPolicy, String)>[
    (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
    (OfficeMacroPolicy(allowedTools: {'docx.runFormat'}), 'permission_denied'),
    (OfficeMacroPolicy(maxSteps: 1), 'limit_exceeded'),
  ]) {
    final session = OfficeMacroSession(
      input,
      format: OfficeMacroFormat.docx,
      policy: policy,
    );
    for (final action in [session.validate, session.run]) {
      try {
        await action(macro);
        throw StateError('Restricted style operation succeeded');
      } on OfficeMacroException catch (error) {
        _check(error.code == code, 'Wrong policy refusal');
      }
      _check(
        session.revision == 0 &&
            base64Encode(session.bytes) == base64Encode(input),
        'Policy refusal published edits',
      );
      denials++;
    }
  }
  final allowed = OfficeMacroSession(
    input,
    format: OfficeMacroFormat.docx,
    policy: OfficeMacroPolicy(
      allowedTools: {'docx.paragraphStyle'},
      maxSteps: 2,
    ),
  );
  final result = await allowed.run(macro);
  return {'atomicDenials': denials, 'allowedSteps': result.completedSteps};
}

Future<void> main() async {
  _check(_example.isNotEmpty, 'Supply committed BAS in WORD_STYLES_BAS_BASE64');
  print(
    jsonEncode({
      'example': await runWordStylesExample(
        utf8.decode(base64Decode(_example)),
      ),
      'rollback': await runWordStylesRollback(),
      'recording': await runWordStylesRecording(),
      'policy': await runWordStylesPolicy(),
    }),
  );
}
