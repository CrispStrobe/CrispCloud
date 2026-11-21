import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _example = String.fromEnvironment('WORD_MEASUREMENTS_BAS_BASE64');

OfficeMacro measurementPlan(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    source: source,
  ),
);

Uint8List wordMeasurementInput() => WordSerializer().writeBytes(
  WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(
            properties: WmlParagraphProps(
              keepTogether: true,
              tabs: const [
                WmlTabStop(
                  position: 54,
                  alignment: WmlTabAlignment.center,
                  leader: WmlTabLeader.hyphen,
                ),
              ],
            ),
            inlines: [
              WmlRun(
                text: 'Measure\tValue',
                properties: WmlRunProps(bold: true),
              ),
            ],
          ),
          WmlParagraph(),
          WmlParagraph(
            properties: WmlParagraphProps(spacingBefore: 9),
            inlines: [WmlRun(text: 'Untouched')],
          ),
        ],
      ),
    ],
  ),
);

List<XmlElement> _elements(XmlElement root, String name) => <XmlElement>[
  for (final child in root.childElements) ...<XmlElement>[
    if (child.localName == name && child.namespaceUri == OfficeNamespaces.w)
      child,
    ..._elements(child, name),
  ],
];

Map<String, Object?> wordMeasurementState(Uint8List bytes) {
  final paragraphs = WordDeserializer().readBytes(bytes).paragraphs.toList();
  if (paragraphs.length != 3 ||
      paragraphs[0].text != 'Measure\tValue' ||
      paragraphs[1].text.isNotEmpty ||
      paragraphs[2].text != 'Untouched' ||
      paragraphs[2].properties.spacingBefore != 9) {
    throw StateError(
      'Measurement formatting changed unrelated paragraph content',
    );
  }
  final first = paragraphs[0].properties;
  if (first.indent.left != 36 ||
      first.indent.right != 72 ||
      first.indent.hanging != 18 ||
      first.indent.firstLine != 0 ||
      first.spacingBefore != 6 ||
      first.spacingAfter != 36 ||
      first.lineSpacingRule != WmlLineSpacingRule.exact ||
      first.lineSpacing != 18 ||
      !first.keepTogether ||
      paragraphs[1].properties.indent.left != 7.2) {
    throw StateError('Measurements did not retain exact native values');
  }
  if (first.tabs.length != 2 ||
      first.tabs[0].position != 54 ||
      first.tabs[0].alignment != WmlTabAlignment.center ||
      first.tabs[0].leader != WmlTabLeader.hyphen ||
      first.tabs[1].position != 108 ||
      first.tabs[1].alignment != WmlTabAlignment.right ||
      first.tabs[1].leader != WmlTabLeader.dot ||
      paragraphs[0].inlines.whereType<WmlRun>().any(
        (run) => !run.properties.bold,
      )) {
    throw StateError(
      'Measurements lost an existing tab stop or run formatting',
    );
  }
  final root = XmlDocument.parse(
    OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
  ).root!;
  final firstXml = _elements(root, 'p').first;
  final indent = _elements(firstXml, 'ind').single;
  final spacing = _elements(firstXml, 'spacing').single;
  const expectedIndent = <String, String>{
    'left': '720',
    'right': '1440',
    'hanging': '360',
  };
  const expectedSpacing = <String, String>{
    'before': '120',
    'after': '720',
    'line': '360',
    'lineRule': 'exact',
  };
  for (final entry in expectedIndent.entries) {
    if (indent.getAttribute(entry.key, namespaceUri: OfficeNamespaces.w) !=
        entry.value) {
      throw StateError('Indent XML does not match the physical-unit fixture');
    }
  }
  for (final entry in expectedSpacing.entries) {
    if (spacing.getAttribute(entry.key, namespaceUri: OfficeNamespaces.w) !=
        entry.value) {
      throw StateError('Spacing XML does not match the physical-unit fixture');
    }
  }
  return <String, Object?>{
    'paragraphs': paragraphs.length,
    'firstIndentTwips': expectedIndent,
    'firstSpacingTwips': expectedSpacing,
    'tabPositionsTwips': [1080, 2160],
    'emptyParagraphLeftTwips': 144,
    'untouchedTextAndFormatting': true,
  };
}

Future<Map<String, Object?>> runWordMeasurementExample(String source) async {
  final input = wordMeasurementInput();
  final original = base64Encode(input);
  final plan = measurementPlan(source);
  if (plan.steps.length != 8) {
    throw StateError('The actual measurement example must emit eight writes');
  }
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Measurement playback');
  await session.validate(plan);
  if (base64Encode(session.bytes) != original || session.revision != 0) {
    throw StateError('Validation published a document');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  if (session.revision != 1 || session.stopRecording().steps.isNotEmpty) {
    throw StateError('Playback changed publication or recording semantics');
  }
  var saved = session.bytes;
  final expected = wordMeasurementState(saved);
  for (var cycle = 0; cycle < 2; cycle++) {
    saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    if (jsonEncode(wordMeasurementState(saved)) != jsonEncode(expected)) {
      throw StateError('A native reopen changed measurement formatting');
    }
  }
  // Reapplying an explicit source plan must preserve its measured layout.
  final replay = OfficeMacroSession(saved, format: OfficeMacroFormat.docx);
  await replay.run(plan);
  if (jsonEncode(wordMeasurementState(replay.bytes)) != jsonEncode(expected)) {
    throw StateError('Replaying the measurement plan changed its layout');
  }
  return <String, Object?>{
    'operations': plan.steps.length,
    'revision': session.revision,
    'additionalReopens': 2,
    'replayStable': true,
    'state': expected,
  };
}

Future<void> _rollback() async {
  final input = wordMeasurementInput();
  final original = base64Encode(input);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Refused measurement plan');
  final plan = measurementPlan('''
Sub Main()
  ActiveDocument.Paragraphs(1).Format.LeftIndent = InchesToPoints(0.5)
  ActiveDocument.Paragraphs(99).TabStops.Add PicasToPoints(6)
End Sub
''');
  for (final validateOnly in [true, false]) {
    try {
      if (validateOnly) {
        await session.validate(plan);
      } else {
        await session.run(plan);
      }
      throw StateError('Missing paragraph unexpectedly succeeded');
    } on OfficeMacroException catch (error) {
      if (error.code != 'operation_failed' || error.stepIndex != 1) rethrow;
    }
    if (base64Encode(session.bytes) != original || session.revision != 0) {
      throw StateError('Late failure published measurement formatting');
    }
  }
  if (session.stopRecording().steps.isNotEmpty) {
    throw StateError('Failed measurement playback changed recording');
  }
}

Future<void> _policy(String source) async {
  final input = wordMeasurementInput();
  final original = base64Encode(input);
  final session = OfficeMacroSession(
    input,
    format: OfficeMacroFormat.docx,
    policy: OfficeMacroPolicy(allowMutation: false),
  );
  try {
    await session.run(measurementPlan(source));
    throw StateError('Measurements bypassed read-only policy');
  } on OfficeMacroException catch (error) {
    if (error.code != 'permission_denied') rethrow;
  }
  if (base64Encode(session.bytes) != original || session.revision != 0) {
    throw StateError('Denied measurement formatting changed its document');
  }
}

Future<void> _mcp(String source) async {
  final session = OfficeMacroSession(
    wordMeasurementInput(),
    format: OfficeMacroFormat.docx,
  );
  final mcp = OfficeMacroMcp(session);
  final compiled = await mcp.callTool('office_macro_compile', {
    'source': {'language': 'vba-word', 'format': 'docx', 'source': source},
  });
  if (compiled['isError'] != false || session.revision != 0) {
    throw StateError('MCP measurement compilation failed or published bytes');
  }
  final content = compiled['structuredContent']! as Map<String, Object?>;
  final executed = await mcp.callTool('office_macro_run', {
    'macro': content['macro'],
  });
  if (executed['isError'] != false || session.revision != 1) {
    throw StateError('MCP measurement playback failed');
  }
  wordMeasurementState(session.bytes);
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError('Supply the committed WORD_MEASUREMENTS_BAS_BASE64 bytes');
  }
  final source = utf8.decode(base64Decode(_example));
  final example = await runWordMeasurementExample(source);
  await _rollback();
  await _policy(source);
  await _mcp(source);
  print(
    jsonEncode(<String, Object?>{
      'example': example,
      'lateFailureRollback': true,
      'readOnlyPolicy': true,
      'mcpCompileAndRun': true,
    }),
  );
}
