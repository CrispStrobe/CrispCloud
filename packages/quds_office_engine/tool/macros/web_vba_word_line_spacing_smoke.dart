import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// Both hosts receive the exact committed BAS, including comments and whitespace.
const _example = String.fromEnvironment('WORD_LINE_SPACING_BAS_BASE64');
const _w = OfficeNamespaces.w;
const _extension = 'urn:line-spacing-example';
const _macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
const _projectType = 'application/vnd.ms-office.vbaProject';
const _projectRelationship =
    'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
const _projectBytes = [0, 42, 127, 128, 255, 10];
const _signatureBytes = [19, 18, 17, 0, 255];

OfficeMacro wordLineSpacingSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        source: source,
      ),
    );

OfficeMacro wordLineSpacingPlan(String body) =>
    wordLineSpacingSource('Sub Main()\n$body\nEnd Sub');

/// An imported DOCM with inherited spacing and unrelated paragraph metadata.
Uint8List wordLineSpacingInput() {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package.getPart('/word/document.xml')!
    ..writeText('''
<w:document xmlns:w="$_w" xmlns:x="$_extension"><w:body>
<w:p><w:pPr><w:pStyle w:val="Layout"/><w:keepLines/>
<w:jc w:val="right"/><w:ind w:left="240" w:right="160" w:firstLine="60"/>
<w:tabs><w:tab w:val="center" w:leader="dot" w:pos="1440"/></w:tabs>
<w:spacing w:before="120" w:after="180" w:beforeLines="10" w:afterLines="20"
w:beforeAutospacing="1" w:afterAutospacing="0" w:line="300" w:lineRule="exact"
x:line="foreign-line" x:token="first"/></w:pPr>
<w:r><w:rPr><w:b/></w:rPr><w:t>Exact paragraph</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="Layout"/><w:spacing x:token="second"/></w:pPr>
<w:r><w:rPr><w:i/></w:rPr><w:t>Minimum paragraph</w:t></w:r></w:p>
<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="480"
w:lineRule="auto" x:token="third"/></w:pPr></w:p>
<w:p><w:pPr><w:pStyle w:val="Layout"/><w:keepNext/>
<w:spacing w:line="600" w:lineRule="exact" x:token="untouched"/></w:pPr>
<w:r><w:t>Untouched paragraph</w:t></w:r></w:p>
<w:sectPr/></w:body></w:document>''')
    ..contentType = _macroType;
  package.contentTypes.setOverride('/word/document.xml', _macroType);
  package.getPart('/word/styles.xml')!.writeText('''
<w:styles xmlns:w="$_w"><w:style w:type="paragraph" w:styleId="Layout">
<w:name w:val="Layout"/><w:pPr><w:spacing w:before="180" w:after="240"
w:line="480" w:lineRule="auto"/></w:pPr></w:style></w:styles>''');
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
  package
      .relationshipsFor('/word/document.xml')
      .add(
        type: _projectRelationship,
        target: 'vbaProject.bin',
        id: 'rIdSpacingProject',
      );
  package
      .relationshipsFor('/word/vbaProject.bin')
      .add(
        type: '${_projectRelationship}Signature',
        target: 'vbaProjectSignature.bin',
        id: 'rIdSpacingSignature',
      );
  return package.save();
}

XmlElement wordLineSpacingProperties(Uint8List bytes, int index) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .childrenNamed('p', namespaceUri: _w)
        .elementAt(index)
        .firstChild('pPr', namespaceUri: _w)!;

XmlElement wordLineSpacingXml(Uint8List bytes, int index) =>
    wordLineSpacingProperties(
      bytes,
      index,
    ).firstChild('spacing', namespaceUri: _w)!;

// JSON has one numeric kind. Emit integral values as integers on both hosts;
// preserve every fractional value without rounding it.
num _reportNumber(double value) =>
    value == value.truncateToDouble() ? value.toInt() : value;

List<Map<String, Object?>> wordLineSpacingState(Uint8List bytes) {
  final paragraphs = WordDeserializer().readBytes(bytes).paragraphs.toList();
  return [
    for (var index = 0; index < paragraphs.length; index++)
      (() {
        final paragraph = paragraphs[index];
        final spacing = wordLineSpacingXml(bytes, index);
        return <String, Object?>{
          'text': paragraph.text,
          'rule': paragraph.properties.lineSpacingRule.name,
          'amount': _reportNumber(paragraph.properties.lineSpacing),
          'nativeLine': spacing.getAttribute('line', namespaceUri: _w),
          'nativeRule': spacing.getAttribute('lineRule', namespaceUri: _w),
          'directBefore': spacing.getAttribute('before', namespaceUri: _w),
          'directAfter': spacing.getAttribute('after', namespaceUri: _w),
          'effectiveBefore': _reportNumber(paragraph.properties.spacingBefore),
          'effectiveAfter': _reportNumber(paragraph.properties.spacingAfter),
          'token': spacing.getAttribute('token', namespaceUri: _extension),
        };
      })(),
  ];
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _checkMacroParts(Uint8List bytes) {
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
        project.id == 'rIdSpacingProject' &&
        project.target == 'vbaProject.bin' &&
        signature.id == 'rIdSpacingSignature' &&
        signature.target == 'vbaProjectSignature.bin' &&
        signature.type == '${_projectRelationship}Signature',
    'Line spacing changed opaque VBA project payloads or relationships',
  );
}

// These expected values are explicit source/native contract examples; they are
// not generated by the adapter, native operation or a copy of its arithmetic.
void _checkExamplePlan(OfficeMacro plan) {
  const expected = <(String, Map<String, Object?>)>[
    (
      'docx.paragraphFormat',
      {'paragraph': 0, 'lineSpacing': 1.0, 'lineSpacingRule': 'auto'},
    ),
    ('docx.lineSpacing', {'paragraph': 0, 'rule': 'exact', 'points': 14.25}),
    (
      'docx.paragraphFormat',
      {'paragraph': 1, 'lineSpacing': 1.5, 'lineSpacingRule': 'auto'},
    ),
    ('docx.lineSpacing', {'paragraph': 1, 'rule': 'atLeast', 'points': 18.0}),
    (
      'docx.paragraphFormat',
      {'paragraph': 2, 'lineSpacing': 2.0, 'lineSpacingRule': 'auto'},
    ),
    ('docx.lineSpacing', {'paragraph': 2, 'rule': 'multiple', 'points': 21.0}),
  ];
  _check(plan.steps.length == expected.length, 'Unexpected example step count');
  for (var index = 0; index < expected.length; index++) {
    final (tool, arguments) = expected[index];
    final actual = plan.steps[index];
    _check(
      actual.tool == tool &&
          actual.arguments.length == arguments.length &&
          arguments.entries.every(
            (entry) => actual.arguments[entry.key] == entry.value,
          ),
      'Example step $index differs from its independent expected operation',
    );
  }
}

void _checkExample(Uint8List bytes, Map<String, Object?> untouched) {
  final states = wordLineSpacingState(bytes);
  const expected = [
    ('Exact paragraph', 'exact', 14.25, '285', 'exact'),
    ('Minimum paragraph', 'atLeast', 18.0, '360', 'atLeast'),
    ('', 'auto', 1.75, '420', 'auto'),
  ];
  for (var index = 0; index < expected.length; index++) {
    final (text, rule, amount, nativeLine, nativeRule) = expected[index];
    final state = states[index];
    _check(
      state['text'] == text &&
          state['rule'] == rule &&
          state['amount'] == amount &&
          state['nativeLine'] == nativeLine &&
          state['nativeRule'] == nativeRule,
      'Unexpected saved line-spacing state: $state',
    );
  }
  _check(
    states.length == 4 && jsonEncode(states.last) == jsonEncode(untouched),
    'Example changed the unselected paragraph',
  );
  final firstSpacing = wordLineSpacingXml(bytes, 0);
  for (final entry in const {
    'before': '120',
    'after': '180',
    'beforeLines': '10',
    'afterLines': '20',
    'beforeAutospacing': '1',
    'afterAutospacing': '0',
  }.entries) {
    _check(
      firstSpacing.getAttribute(entry.key, namespaceUri: _w) == entry.value,
      'Custom spacing changed unrelated native ${entry.key}',
    );
  }
  final document = WordDeserializer().readBytes(bytes);
  final first = document.paragraphs.first;
  final second = document.paragraphs.elementAt(1);
  _check(
    firstSpacing.getAttribute('line', namespaceUri: _extension) ==
            'foreign-line' &&
        states[0]['token'] == 'first' &&
        states[1]['token'] == 'second' &&
        states[2]['token'] == 'third' &&
        first.properties.keepTogether &&
        first.properties.justification == WmlJustification.right &&
        first.properties.indent.right == 8 &&
        first.properties.tabs.single.position == 72 &&
        first.properties.tabs.single.alignment == WmlTabAlignment.center &&
        first.properties.tabs.single.leader == WmlTabLeader.dot &&
        first.inlines.whereType<WmlRun>().single.properties.bold &&
        second.inlines.whereType<WmlRun>().single.properties.italic &&
        states[1]['directBefore'] == null &&
        states[1]['directAfter'] == null &&
        states[1]['effectiveBefore'] == 9 &&
        states[1]['effectiveAfter'] == 12,
    'Custom spacing changed formatting, inheritance, or extension metadata',
  );
  _checkMacroParts(bytes);
}

Future<Map<String, Object?>> runWordLineSpacingExample(String source) async {
  final input = wordLineSpacingInput();
  final original = base64Encode(input);
  final untouched = wordLineSpacingState(input).last;
  final guard = (await WordPackagePreservation.capture(input, 'spacing.docm'))!;
  final plan = wordLineSpacingSource(source);
  _checkExamplePlan(plan);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Line spacing playback');
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == 6 &&
        session.revision == 0 &&
        base64Encode(session.bytes) == original,
    'Dry-run validation published a change',
  );
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  _check(
    result.completedSteps == 6 &&
        result.revision == 1 &&
        !result.validatedOnly &&
        base64Encode(input) == original &&
        session.stopRecording().steps.isEmpty,
    'Example did not publish one detached transaction',
  );
  var saved = session.bytes;
  final expectedState = wordLineSpacingState(saved);
  for (var cycle = 0; cycle < 3; cycle++) {
    _checkExample(saved, untouched);
    await guard.validateSaved(saved);
    _check(
      jsonEncode(wordLineSpacingState(saved)) == jsonEncode(expectedState),
      'Repeated native save changed line-spacing meaning',
    );
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  return {
    'operations': 6,
    'revision': 1,
    'additionalReopens': 2,
    'opaqueVbaPreserved': true,
    'paragraphs': expectedState,
  };
}

Future<Map<String, Object?>> runWordLineSpacingExampleReplay(
  String source,
) async {
  final input = wordLineSpacingInput();
  final untouched = wordLineSpacingState(input).last;
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final plan = wordLineSpacingSource(source);
  await session.run(plan);
  final expected = jsonEncode(wordLineSpacingState(session.bytes));
  final before = base64Encode(session.bytes);
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == 6 &&
        session.revision == 1 &&
        base64Encode(session.bytes) == before,
    'Second validation changed the saved output',
  );
  await session.run(plan);
  _checkExample(session.bytes, untouched);
  _check(
    session.revision == 2 &&
        jsonEncode(wordLineSpacingState(session.bytes)) == expected,
    'Example changed meaning when replayed on its own output',
  );
  return {'operationsPerRun': 6, 'revision': 2, 'sameSavedState': true};
}

/// Ordinary decimal line multiples must survive conversion and the twip gate.
Future<Map<String, Object?>> runWordLineSpacingDecimalConversions() async {
  final plan = wordLineSpacingPlan('''
Dim points As Double
Dim lines As Double
With Application
  points = .LinesToPoints(1.15)
  lines = .PointsToLines(13.8)
End With
With ActiveDocument.Paragraphs(1).Format
  .LineSpacingRule = wdLineSpaceExactly
  .LineSpacing = points
End With
With ActiveDocument.Paragraphs(2).Format
  .LineSpacingRule = wdLineSpaceMultiple
  .LineSpacing = Application.LinesToPoints(1.15)
End With
With ActiveDocument.Paragraphs(3).Format
  .LineSpacingRule = wdLineSpaceExactly
  .LineSpacing = lines
End With
''');
  _check(
    plan.steps.length == 3 &&
        plan.steps[0].arguments['points'] == 13.8 &&
        plan.steps[1].arguments['points'] == 13.8 &&
        plan.steps[2].arguments['points'] == 1.15,
    'Ordinary decimal conversions did not retain their exact grid values',
  );
  final session = OfficeMacroSession(
    wordLineSpacingInput(),
    format: OfficeMacroFormat.docx,
  );
  await session.run(plan);
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    final state = wordLineSpacingState(saved);
    _check(
      state[0]['nativeLine'] == '276' &&
          state[0]['nativeRule'] == 'exact' &&
          state[0]['amount'] == 13.8 &&
          state[1]['nativeLine'] == '276' &&
          state[1]['nativeRule'] == 'auto' &&
          state[1]['amount'] == 1.15 &&
          state[2]['nativeLine'] == '23' &&
          state[2]['nativeRule'] == 'exact' &&
          state[2]['amount'] == 1.15,
      'Ordinary decimal spacing changed during save/reopen',
    );
    _checkMacroParts(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  return {
    'linesToPoints': 13.8,
    'pointsToLines': 1.15,
    'nativeLines': ['276', '276', '23'],
    'savedMultiple': 1.15,
    'additionalReopens': 2,
  };
}

Future<void> assertWordLineSpacingRefusal(
  Uint8List input,
  OfficeMacro plan, {
  int? stepIndex,
  String? tool,
  String code = 'operation_failed',
  OfficeMacroPolicy? policy,
}) async {
  final original = base64Encode(input);
  final session = OfficeMacroSession(
    input,
    format: OfficeMacroFormat.docx,
    policy: policy,
  );
  if (session.policy.allowMutation) {
    session.startRecording('Rejected line spacing');
  }
  for (final action in [session.validate, session.run]) {
    try {
      await action(plan);
      throw StateError('Invalid line-spacing plan unexpectedly succeeded');
    } on OfficeMacroException catch (error) {
      if (error.code != code ||
          (stepIndex != null && error.stepIndex != stepIndex) ||
          (tool != null && error.tool != tool)) {
        rethrow;
      }
    }
    _check(
      session.revision == 0 && base64Encode(session.bytes) == original,
      'Rejected line-spacing plan published a partial edit',
    );
  }
  if (session.policy.allowMutation) {
    _check(
      session.stopRecording().steps.isEmpty,
      'Rejected playback contaminated the recording',
    );
  }
}

const wordLineSpacingPresetGuardCases = <(String, String, String, double)>[
  ('Space1 duplicate spacing', 'duplicate', 'target.Space1', 1.0),
  ('Space15 spacing alternative', 'alternative', 'Call target.Space15()', 1.5),
  ('Space2 unbalanced field', 'field', 'Call target.Space2', 2.0),
  (
    'single preset duplicate spacing',
    'duplicate',
    'target.LineSpacingRule = wdLineSpaceSingle',
    1.0,
  ),
];

Uint8List _presetGuardInput(String kind) {
  final package = OpcPackage.openBytes(wordLineSpacingInput());
  final part = package.getPart('/word/document.xml')!;
  final source = part.readText();
  final changed = switch (kind) {
    'duplicate' => source.replaceFirst(
      '<w:tabs>',
      '<w:spacing w:line="480" w:lineRule="auto"/><w:tabs>',
    ),
    'alternative' => source.replaceFirst(
      '</w:pPr>',
      '<mc:AlternateContent '
          'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">'
          '<mc:Choice Requires="x"><w:spacing w:line="480" w:lineRule="auto"/>'
          '</mc:Choice><mc:Fallback><w:spacing w:line="240" w:lineRule="auto"/>'
          '</mc:Fallback></mc:AlternateContent></w:pPr>',
    ),
    'field' => source.replaceFirst(
      '<w:t>Untouched paragraph</w:t>',
      '<w:fldChar w:fldCharType="begin"/><w:instrText>PAGE</w:instrText>'
          '<w:t>Untouched paragraph</w:t>',
    ),
    _ => throw ArgumentError.value(
      kind,
      'kind',
      'Unknown preset guard fixture',
    ),
  };
  _check(changed != source, 'Preset guard fixture did not change the source');
  part.writeText(changed);
  return package.save();
}

Future<void> assertWordLineSpacingPresetGuard(
  (String, String, String, double) scenario,
) async {
  final (name, kind, statement, multiple) = scenario;
  final input = _presetGuardInput(kind);
  final plan = wordLineSpacingPlan('''
Dim target As ParagraphFormat
Set target = ActiveDocument.Paragraphs(1).Format
ActiveDocument.Paragraphs(2).Range.Font.Bold = True
$statement
''');
  await assertWordLineSpacingRefusal(
    input,
    plan,
    stepIndex: 1,
    tool: 'docx.paragraphFormat',
  );
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Refused preset: $name');
  try {
    await session.callTool('docx.paragraphFormat', {
      'paragraph': 0,
      'lineSpacing': multiple,
      'lineSpacingRule': 'auto',
    });
    throw StateError('Unsafe native preset was recorded: $name');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed') rethrow;
  }
  _check(
    session.revision == 0 &&
        base64Encode(session.bytes) == base64Encode(input) &&
        session.stopRecording().steps.isEmpty,
    'Unsafe preset published or contaminated the recording: $name',
  );
}

Future<Map<String, Object?>> runWordLineSpacingPresetGuards() async {
  for (final scenario in wordLineSpacingPresetGuardCases) {
    await assertWordLineSpacingPresetGuard(scenario);
  }
  return {
    'refusedSourcePlans': 4,
    'validateAndRunRollback': true,
    'failedNativeCallsExcluded': 4,
  };
}

Future<Map<String, Object?>> runWordLineSpacingPolicies() async {
  final input = wordLineSpacingInput();
  final plan = wordLineSpacingPlan('''
With ActiveDocument.Paragraphs(1).Format
  .LineSpacingRule = wdLineSpaceExactly
  .LineSpacing = 14.25
End With
With ActiveDocument.Paragraphs(2).Format
  .LineSpacingRule = wdLineSpaceMultiple
  .LineSpacing = LinesToPoints(1.75)
End With
''');
  for (final (policy, code) in <(OfficeMacroPolicy, String)>[
    (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
    (
      OfficeMacroPolicy(allowedTools: {'docx.paragraphFormat'}),
      'permission_denied',
    ),
    (OfficeMacroPolicy(maxSteps: 1), 'limit_exceeded'),
  ]) {
    await assertWordLineSpacingRefusal(input, plan, policy: policy, code: code);
  }
  final session = OfficeMacroSession(
    input,
    format: OfficeMacroFormat.docx,
    policy: OfficeMacroPolicy(allowedTools: {'docx.lineSpacing'}, maxSteps: 2),
  );
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == 2 &&
        session.revision == 0 &&
        base64Encode(session.bytes) == base64Encode(input),
    'Allowlisted validation changed the original',
  );
  await session.run(plan);
  final state = wordLineSpacingState(session.bytes);
  _check(
    session.revision == 1 &&
        state[0]['nativeLine'] == '285' &&
        state[0]['nativeRule'] == 'exact' &&
        state[1]['nativeLine'] == '420' &&
        state[1]['nativeRule'] == 'auto',
    'The custom line-spacing allowlist did not preserve the operation plan',
  );
  return {'refusedPolicies': 3, 'completeAllowlistRevision': 1};
}

Future<Map<String, Object?>> runWordLineSpacingRollback() async {
  await assertWordLineSpacingRefusal(
    wordLineSpacingInput(),
    wordLineSpacingPlan('''
With ActiveDocument.Paragraphs(1).Format
  .LineSpacingRule = wdLineSpaceExactly
  .LineSpacing = 18
End With
ActiveDocument.Paragraphs(2).Range.Font.Bold = True
With ActiveDocument.Paragraphs(99).Format
  .LineSpacingRule = wdLineSpaceMultiple
  .LineSpacing = LinesToPoints(2)
End With
'''),
    stepIndex: 2,
    tool: 'docx.lineSpacing',
  );
  return {'failedStep': 2, 'validateAndRunRollback': true};
}

Future<Map<String, Object?>> runWordLineSpacingRecording() async {
  final input = wordLineSpacingInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Custom line spacing');
  await session.callTool('docx.lineSpacing', {
    'paragraph': 0,
    'rule': 'exact',
    'points': 14.25,
  });
  await session.callTool('docx.lineSpacing', {
    'paragraph': 1,
    'rule': 'atLeast',
    'points': 18,
  });
  await session.callTool('docx.lineSpacing', {
    'paragraph': 2,
    'rule': 'multiple',
    'points': 21,
  });
  final beforeFailure = base64Encode(session.bytes);
  try {
    await session.callTool('docx.lineSpacing', {
      'paragraph': 99,
      'rule': 'exact',
      'points': 12,
    });
    throw StateError('A missing paragraph was recorded');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed') rethrow;
  }
  final recorded = session.stopRecording();
  _check(
    recorded.steps.length == 3 &&
        session.revision == 3 &&
        base64Encode(session.bytes) == beforeFailure,
    'Failed call changed publication or recording',
  );
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recorded.encode()));
  _check(
    replay.revision == 1 &&
        jsonEncode(wordLineSpacingState(replay.bytes)) ==
            jsonEncode(wordLineSpacingState(session.bytes)),
    'Recorded custom spacing changed meaning on replay',
  );
  _checkMacroParts(replay.bytes);
  return {'recordedSteps': 3, 'failedCallExcluded': true, 'replayRevision': 1};
}

int _sourceRefusals() {
  const target = 'ActiveDocument.Paragraphs(1).Format';
  const pair = '$target.LineSpacingRule = wdLineSpaceExactly\n';
  const statements = [
    '$target.LineSpacing = 12',
    '$target.LineSpacingRule = wdLineSpaceExactly',
    '${pair}ActiveDocument.Paragraphs(2).Format.LineSpacing = 12',
    '$pair$target.SpaceAfter = 6\n$target.LineSpacing = 12',
    '$pair$target.LineSpacing = True',
    '$pair$target.LineSpacing = "12"',
    '$pair$target.LineSpacing = 0',
    '$pair$target.LineSpacing = -1',
    '$pair$target.LineSpacing = 0.025',
    '$pair$target.LineSpacing = 107374182.4',
    '$pair$target.LineSpacing = 12\n$target.LineSpacing = 18',
    '$pair$target.LineSpacing = LinesToPoints(True)',
    '$pair$target.LineSpacing = Application.PointsToLines("12")',
    '$target.Space1 1',
    'Dim value As Double\nvalue = $target.LineSpacing',
  ];
  for (final statement in statements) {
    try {
      wordLineSpacingPlan(statement);
      throw StateError('Unsupported line-spacing source compiled: $statement');
    } on OfficeVbaCompileException {
      // Unsupported source cannot produce a partially executable plan.
    }
  }
  return statements.length;
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError(
      'Supply exact committed WORD_LINE_SPACING_BAS_BASE64 bytes',
    );
  }
  final source = utf8.decode(base64Decode(_example));
  print(
    jsonEncode({
      'example': await runWordLineSpacingExample(source),
      'exampleReplay': await runWordLineSpacingExampleReplay(source),
      'ordinaryDecimals': await runWordLineSpacingDecimalConversions(),
      'presetGuards': await runWordLineSpacingPresetGuards(),
      'policies': await runWordLineSpacingPolicies(),
      'rollback': await runWordLineSpacingRollback(),
      'recording': await runWordLineSpacingRecording(),
      'refusedSources': _sourceRefusals(),
    }),
  );
}
