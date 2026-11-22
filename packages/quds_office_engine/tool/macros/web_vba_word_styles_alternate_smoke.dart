import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_line_spacing_smoke.dart' as fixture;

// Both hosts receive the exact committed BAS, including its helper and comments.
const _example = String.fromEnvironment('WORD_STYLES_BAS_BASE64');
const _w = OfficeNamespaces.w;
const _extension = 'urn:word-style-example';

OfficeMacro wordStylesSource(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordStylesExample',
    source: source,
  ),
);

OfficeMacro wordStylesPlan(String body) =>
    wordStylesSource('Sub Main()\n$body\nEnd Sub');

/// Imported DOCM with direct formatting, character-style overrides, an aliased
/// native pStyle, and opaque VBA/signature parts inherited from the fixture.
Uint8List wordStylesInput() {
  final package = OpcPackage.openBytes(fixture.wordLineSpacingInput());
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="$_w" xmlns:x="$_extension"><w:body>
<w:p><w:pPr><s:pStyle xmlns:s="$_w" xmlns:w="$_extension"
s:val="Legacy" w:val="foreign-style" w:token="keep-style">
<w:metadata w:token="keep-child"/></s:pStyle>
<w:jc w:val="right"/><w:spacing w:after="180"/></w:pPr>
<w:r><w:rPr><w:color w:val="112233"/><w:sz w:val="22"/></w:rPr>
<w:t>Report title</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="Legacy"/></w:pPr>
<w:r><w:rPr><w:rStyle w:val="Emphasis"/><w:b w:val="0"/></w:rPr>
<w:t>Report body</w:t></w:r></w:p>
<w:p><w:r><w:t>Figure caption</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="Legacy"/><w:keepNext/></w:pPr>
<w:r><w:t>Untouched paragraph</w:t></w:r></w:p>
<w:sectPr/></w:body></w:document>''');
  package.getPart('/word/styles.xml')!.writeText('''
<w:styles xmlns:w="$_w" xmlns:x="$_extension">
<w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val="20"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal">
<w:name w:val="Normal"/><w:pPr><w:spacing w:after="100"/></w:pPr></w:style>
<w:style w:type="paragraph" w:customStyle="1" w:styleId="Legacy">
<w:name w:val="Legacy body"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:before="40" w:after="60"/></w:pPr>
<w:rPr><w:i/><w:color w:val="AA0000"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ReportHeadingOne">
<w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:before="240" w:after="120"/><w:keepNext/></w:pPr>
<w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="234567"/></w:rPr></w:style>
<w:style w:type="paragraph" w:customStyle="1" w:styleId="ReportBody">
<w:name w:val="Report Body"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:before="60" w:after="240"/></w:pPr>
<w:rPr><w:b/><w:color w:val="456789"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="CaptionStyle">
<w:name w:val="caption"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:before="80"/></w:pPr></w:style>
<w:style w:type="character" w:customStyle="1" w:styleId="Emphasis">
<w:name w:val="Emphasis"/><w:rPr><w:i/><w:color w:val="654321"/></w:rPr></w:style>
<x:metadata x:token="styles-stay-opaque"/>
</w:styles>''');
  return package.save();
}

XmlElement wordStylesParagraphXml(Uint8List bytes, int index) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .childrenNamed('p', namespaceUri: _w)
        .elementAt(index);

num _number(double value) =>
    value == value.truncateToDouble() ? value.toInt() : value;

List<Map<String, Object?>> wordStylesState(Uint8List bytes) => [
  for (final paragraph in WordDeserializer().readBytes(bytes).paragraphs)
    {
      'text': paragraph.text,
      'style': paragraph.properties.styleId,
      'before': _number(paragraph.properties.spacingBefore),
      'after': _number(paragraph.properties.spacingAfter),
      'alignment': paragraph.properties.justification.name,
      'runs': [
        for (final run in paragraph.inlines.whereType<WmlRun>())
          {
            'bold': run.properties.bold,
            'italic': run.properties.italic,
            'color': run.properties.color,
            'size': _number(run.properties.fontSizePoints),
            'characterStyle': run.properties.styleId,
          },
      ],
    },
];

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

String _stylesXml(Uint8List bytes) => XmlDocument.parse(
  OpcPackage.openBytes(bytes).getPart('/word/styles.xml')!.readText(),
).toXmlString(declaration: false);

/// Independent expected values: style-derived formatting changes, previously
/// authored direct formatting and the untouched fourth paragraph do not.
void assertWordStylesExample(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  final paragraphs = document.paragraphs.toList();
  final first = paragraphs[0];
  final firstRun = first.inlines.whereType<WmlRun>().single;
  final second = paragraphs[1];
  final secondRun = second.inlines.whereType<WmlRun>().single;
  final third = paragraphs[2];
  _check(
    first.properties.styleId == 'ReportHeadingOne' &&
        first.properties.justification == WmlJustification.right &&
        first.properties.spacingBefore == 12 &&
        first.properties.spacingAfter == 9 &&
        firstRun.properties.bold &&
        !firstRun.properties.italic &&
        firstRun.properties.color == '112233' &&
        firstRun.properties.fontSizePoints == 11 &&
        second.properties.styleId == 'ReportBody' &&
        second.properties.spacingBefore == 3 &&
        second.properties.spacingAfter == 12 &&
        secondRun.properties.styleId == 'Emphasis' &&
        !secondRun.properties.bold &&
        secondRun.properties.italic &&
        secondRun.properties.color == '654321' &&
        third.properties.styleId == 'CaptionStyle' &&
        third.properties.spacingBefore == 4 &&
        third.properties.spacingAfter == 5 &&
        third.inlines.whereType<WmlRun>().single.properties.italic,
    'Style assignment lost its inherited/direct cascade: ${wordStylesState(bytes)}',
  );
  _check(
    jsonEncode(wordStylesState(bytes).last) ==
        jsonEncode(wordStylesState(wordStylesInput()).last),
    'Style assignment changed an unselected paragraph',
  );
  final style = wordStylesParagraphXml(bytes, 0)
      .firstChild('pPr', namespaceUri: _w)!
      .firstChild('pStyle', namespaceUri: _w)!;
  _check(
    style.getAttribute('val', namespaceUri: _w) == 'ReportHeadingOne' &&
        style.getAttribute('val', namespaceUri: _extension) ==
            'foreign-style' &&
        style.getAttribute('token', namespaceUri: _extension) == 'keep-style' &&
        style
                .firstChild('metadata', namespaceUri: _extension)!
                .getAttribute('token', namespaceUri: _extension) ==
            'keep-child',
    'Style assignment damaged opaque pStyle metadata or namespace ownership',
  );
  _check(
    _stylesXml(bytes) == _stylesXml(wordStylesInput()),
    'Style assignment rewrote style definitions',
  );
}

Future<Map<String, Object?>> runWordStylesExample(String source) async {
  final input = wordStylesInput();
  final before = base64Encode(input);
  final plan = wordStylesSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final guard = (await WordPackagePreservation.capture(input, 'styles.docm'))!;
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == 5 &&
        session.revision == 0 &&
        base64Encode(session.bytes) == before,
    'Style validation published an edit or lost a step',
  );
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  _check(
    result.completedSteps == 5 &&
        session.revision == 1 &&
        base64Encode(input) == before,
    'Style execution did not publish exactly one detached transaction',
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordStylesExample(saved);
    await guard.validateSaved(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  await session.run(plan);
  assertWordStylesExample(session.bytes);
  await guard.validateSaved(session.bytes);
  return {
    'operations': result.completedSteps,
    'firstRunRevision': result.revision,
    'repeatedRevision': session.revision,
    'additionalReopens': 2,
    'opaquePayloadsPreserved': true,
    'paragraphs': wordStylesState(saved),
  };
}

Future<Map<String, Object?>> runWordStylesRollback() async {
  final input = wordStylesInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Rejected style transaction');
  final plan = wordStylesPlan('''
ActiveDocument.Paragraphs(1).Style = wdStyleHeading1
ActiveDocument.Paragraphs(2).Range.Font.Bold = True
ActiveDocument.Paragraphs(3).Style = "Missing style"
''');
  for (final action in [session.validate, session.run]) {
    try {
      await action(plan);
      throw StateError('Missing style unexpectedly resolved');
    } on OfficeMacroException catch (error) {
      _check(
        error.code == 'operation_failed' &&
            error.stepIndex == 2 &&
            error.tool == 'docx.paragraphStyle',
        'Style failure lost its native operation attribution',
      );
    }
    _check(
      session.revision == 0 &&
          base64Encode(session.bytes) == base64Encode(input),
      'Failed style transaction published a prefix edit',
    );
  }
  _check(session.stopRecording().steps.isEmpty, 'Rejected edits were recorded');
  return {'failedStep': 2, 'validateAndRunRollback': true};
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
    'name': 'rEpOrT bOdY',
  });
  final before = base64Encode(session.bytes);
  try {
    await session.callTool('docx.paragraphStyle', {
      'paragraph': 99,
      'builtin': -1,
    });
    throw StateError('Missing paragraph unexpectedly resolved');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed') rethrow;
  }
  final recording = session.stopRecording();
  _check(
    recording.steps.length == 2 &&
        session.revision == 2 &&
        base64Encode(session.bytes) == before,
    'Recording retained a failed call or lost an accepted edit',
  );
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recording.encode()));
  _check(
    replay.revision == 1 &&
        jsonEncode(wordStylesState(replay.bytes)) ==
            jsonEncode(wordStylesState(session.bytes)),
    'Recorded style selectors changed meaning on replay',
  );
  return {'recordedSteps': 2, 'failedCallExcluded': true, 'replayRevision': 1};
}

Future<Map<String, Object?>> runWordStylesPolicy() async {
  final input = wordStylesInput();
  final plan = wordStylesPlan('''
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
        await action(plan);
        throw StateError('Restricted style plan unexpectedly ran');
      } on OfficeMacroException catch (error) {
        _check(error.code == code, 'Wrong style policy failure');
      }
      _check(
        session.revision == 0 &&
            base64Encode(session.bytes) == base64Encode(input),
        'A rejected style plan published an edit',
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
  final result = await allowed.run(plan);
  _check(
    result.completedSteps == 2 && allowed.revision == 1,
    'Explicitly permitted style operations did not run',
  );
  return {'atomicDenials': denials, 'allowedSteps': result.completedSteps};
}

Future<void> main() async {
  _check(
    _example.isNotEmpty,
    'Supply the committed BAS in WORD_STYLES_BAS_BASE64',
  );
  final source = utf8.decode(base64Decode(_example));
  print(
    jsonEncode({
      'example': await runWordStylesExample(source),
      'rollback': await runWordStylesRollback(),
      'recording': await runWordStylesRecording(),
      'policy': await runWordStylesPolicy(),
    }),
  );
}
