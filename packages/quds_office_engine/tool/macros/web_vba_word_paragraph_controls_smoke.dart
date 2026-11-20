import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// Each host receives the exact committed BAS, including comments/whitespace.
const _example = String.fromEnvironment('WORD_PARAGRAPH_CONTROLS_BAS_BASE64');
const _w = OfficeNamespaces.w;
const _extension = 'urn:paragraph-controls-example';
const _macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
const _projectType = 'application/vnd.ms-office.vbaProject';
const _projectRelationship =
    'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
const _projectBytes = [0, 42, 127, 128, 255, 10];
const _signatureBytes = [19, 18, 17, 0, 255];

OfficeMacro wordParagraphControlsSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        source: source,
      ),
    );

OfficeMacro wordParagraphControlsPlan(String body) =>
    wordParagraphControlsSource('Sub Main()\n$body\nEnd Sub');

/// Imported DOCM with explicit and inherited before/after/line spacing.
Uint8List wordParagraphControlsInput() {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package.getPart('/word/document.xml')!
    ..writeText('''
<w:document xmlns:w="$_w" xmlns:x="$_extension"><w:body>
<w:p><w:pPr><w:pStyle w:val="Layout"/><w:keepLines/>
<w:jc w:val="right"/><w:ind w:left="240" w:right="160" w:firstLine="60"/>
<w:tabs><w:tab w:val="center" w:leader="dot" w:pos="1440"/></w:tabs>
<w:spacing w:before="120" w:after="180" w:afterLines="20"
w:beforeAutospacing="0" w:afterAutospacing="1" w:line="300" w:lineRule="exact"
x:before="foreign-before" x:token="first"/></w:pPr>
<w:r><w:rPr><w:b/></w:rPr><w:t>Open paragraph</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="Layout"/><w:spacing x:token="second"/></w:pPr>
<w:r><w:rPr><w:i/></w:rPr><w:t>Close paragraph</w:t></w:r></w:p>
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
<w:name w:val="Layout"/><w:pPr><w:spacing w:before="240" w:after="180"
w:line="360" w:lineRule="auto"/></w:pPr></w:style></w:styles>''');
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
        id: 'rIdParagraphProject',
      );
  package
      .relationshipsFor('/word/vbaProject.bin')
      .add(
        type: '${_projectRelationship}Signature',
        target: 'vbaProjectSignature.bin',
        id: 'rIdParagraphSignature',
      );
  return package.save();
}

XmlElement wordParagraphControlsProperties(Uint8List bytes, int index) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .childrenNamed('p', namespaceUri: _w)
        .elementAt(index)
        .firstChild('pPr', namespaceUri: _w)!;

XmlElement wordParagraphControlsSpacing(Uint8List bytes, int index) =>
    wordParagraphControlsProperties(
      bytes,
      index,
    ).firstChild('spacing', namespaceUri: _w)!;

// Emit integral numbers identically on VM and JavaScript without rounding
// fractional values in the independent output receipt.
num _number(double value) =>
    value == value.truncateToDouble() ? value.toInt() : value;

List<Map<String, Object?>> wordParagraphControlsState(Uint8List bytes) {
  final paragraphs = WordDeserializer().readBytes(bytes).paragraphs.toList();
  return [
    for (var index = 0; index < paragraphs.length; index++)
      (() {
        final paragraph = paragraphs[index];
        final spacing = wordParagraphControlsSpacing(bytes, index);
        return <String, Object?>{
          'text': paragraph.text,
          'before': _number(paragraph.properties.spacingBefore),
          'after': _number(paragraph.properties.spacingAfter),
          'line': _number(paragraph.properties.lineSpacing),
          'rule': paragraph.properties.lineSpacingRule.name,
          'directBefore': spacing.getAttribute('before', namespaceUri: _w),
          'directAfter': spacing.getAttribute('after', namespaceUri: _w),
          'nativeLine': spacing.getAttribute('line', namespaceUri: _w),
          'nativeRule': spacing.getAttribute('lineRule', namespaceUri: _w),
          'token': spacing.getAttribute('token', namespaceUri: _extension),
        };
      })(),
  ];
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void assertWordParagraphControlsMacroParts(Uint8List bytes) {
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
        project.id == 'rIdParagraphProject' &&
        project.target == 'vbaProject.bin' &&
        signature.id == 'rIdParagraphSignature' &&
        signature.target == 'vbaProjectSignature.bin' &&
        signature.type == '${_projectRelationship}Signature',
    'Paragraph controls changed opaque VBA payloads or relationships',
  );
}

void _checkExamplePlan(OfficeMacro plan) {
  // Specification-derived explicit actions, independent of compiler lowering.
  const expected = [
    (0, 'close'),
    (0, 'open'),
    (0, 'toggle'),
    (0, 'open'),
    (1, 'open'),
    (1, 'toggle'),
    (2, 'close'),
    (2, 'toggle'),
    (2, 'toggle'),
    (2, 'open'),
  ];
  _check(plan.steps.length == expected.length, 'Unexpected example step count');
  for (var index = 0; index < expected.length; index++) {
    final actual = plan.steps[index];
    final (paragraph, action) = expected[index];
    _check(
      actual.tool == 'docx.paragraphSpaceBefore' &&
          actual.arguments.length == 2 &&
          actual.arguments['paragraph'] == paragraph &&
          actual.arguments['action'] == action,
      'Example step $index differs from its expected native action',
    );
  }
}

void _checkExample(Uint8List bytes, Map<String, Object?> untouched) {
  final states = wordParagraphControlsState(bytes);
  const expected = [
    ('Open paragraph', 12, '240'),
    ('Close paragraph', 0, '0'),
    ('', 12, '240'),
  ];
  for (var index = 0; index < expected.length; index++) {
    final (text, before, directBefore) = expected[index];
    final state = states[index];
    _check(
      state['text'] == text &&
          state['before'] == before &&
          state['directBefore'] == directBefore,
      'Unexpected paragraph-space result: $state',
    );
  }
  _check(
    states.length == 4 && jsonEncode(states.last) == jsonEncode(untouched),
    'Example changed the unselected paragraph',
  );
  final spacing = wordParagraphControlsSpacing(bytes, 0);
  for (final entry in const {
    'after': '180',
    'afterLines': '20',
    'afterAutospacing': '1',
    'line': '300',
    'lineRule': 'exact',
  }.entries) {
    _check(
      spacing.getAttribute(entry.key, namespaceUri: _w) == entry.value,
      'Paragraph-space write changed unrelated ${entry.key}',
    );
  }
  _check(
    const [
      null,
      '0',
      'false',
      'off',
    ].contains(spacing.getAttribute('beforeAutospacing', namespaceUri: _w)),
    'Explicit before spacing retained an automatic before conflict',
  );
  final document = WordDeserializer().readBytes(bytes);
  final first = document.paragraphs.first;
  final second = document.paragraphs.elementAt(1);
  _check(
    spacing.getAttribute('before', namespaceUri: _extension) ==
            'foreign-before' &&
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
        states[1]['directAfter'] == null &&
        states[1]['nativeLine'] == null &&
        states[1]['after'] == 9 &&
        states[1]['line'] == 1.5,
    'Paragraph controls changed formatting, inheritance or extension metadata',
  );
  assertWordParagraphControlsMacroParts(bytes);
}

Future<Map<String, Object?>> runWordParagraphControlsExample(
  String source,
) async {
  final input = wordParagraphControlsInput();
  final original = base64Encode(input);
  final untouched = wordParagraphControlsState(input).last;
  final guard = (await WordPackagePreservation.capture(
    input,
    'paragraph-controls.docm',
  ))!;
  final plan = wordParagraphControlsSource(source);
  _checkExamplePlan(plan);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Paragraph controls playback');
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == 10 &&
        session.revision == 0 &&
        base64Encode(session.bytes) == original,
    'Example dry-run changed publication',
  );
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  _check(
    result.completedSteps == 10 &&
        result.revision == 1 &&
        !result.validatedOnly &&
        base64Encode(input) == original &&
        session.stopRecording().steps.isEmpty,
    'Example did not publish one detached transaction',
  );
  var saved = session.bytes;
  final expectedState = wordParagraphControlsState(saved);
  for (var cycle = 0; cycle < 3; cycle++) {
    _checkExample(saved, untouched);
    await guard.validateSaved(saved);
    _check(
      jsonEncode(wordParagraphControlsState(saved)) ==
          jsonEncode(expectedState),
      'Save/reopen changed paragraph controls meaning',
    );
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  return {
    'operations': 10,
    'revision': 1,
    'additionalReopens': 2,
    'opaqueVbaPreserved': true,
    'paragraphs': expectedState,
  };
}

Future<Map<String, Object?>> runWordParagraphControlsExampleReplay(
  String source,
) async {
  final input = wordParagraphControlsInput();
  final untouched = wordParagraphControlsState(input).last;
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final plan = wordParagraphControlsSource(source);
  await session.run(plan);
  final expected = jsonEncode(wordParagraphControlsState(session.bytes));
  final before = base64Encode(session.bytes);
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == 10 &&
        session.revision == 1 &&
        base64Encode(session.bytes) == before,
    'Second dry-run changed the saved document',
  );
  await session.run(plan);
  _checkExample(session.bytes, untouched);
  _check(
    session.revision == 2 &&
        jsonEncode(wordParagraphControlsState(session.bytes)) == expected,
    'Example was not repeatable on its own output',
  );
  return {'operationsPerRun': 10, 'revision': 2, 'sameSavedState': true};
}

Future<Map<String, Object?>> runWordParagraphControlsSequentialToggles() async {
  final session = OfficeMacroSession(
    wordParagraphControlsInput(),
    format: OfficeMacroFormat.docx,
  );
  final plan = wordParagraphControlsPlan('''
With ActiveDocument.Paragraphs(2)
  .OpenOrCloseUp
  .OpenOrCloseUp
End With
With ActiveDocument.Paragraphs(3).Format
  .OpenOrCloseUp
  .OpenOrCloseUp
End With
ActiveDocument.Paragraphs(1).Format.SpaceBefore = 0
ActiveDocument.Paragraphs(1).OpenOrCloseUp
''');
  await session.run(plan);
  final state = wordParagraphControlsState(session.bytes);
  _check(
    plan.steps.length == 6 &&
        session.revision == 1 &&
        state[0]['before'] == 12 &&
        state[1]['before'] == 12 &&
        state[1]['directBefore'] == '240' &&
        state[2]['before'] == 0 &&
        state[2]['directBefore'] == '0',
    'A toggle did not read the detached state left by earlier operations',
  );
  return {
    'operations': 6,
    'before': [12, 12, 0],
    'revision': 1,
  };
}

Future<Map<String, Object?>> runWordParagraphControlsStyleOwnership() async {
  final session = OfficeMacroSession(
    wordParagraphControlsInput(),
    format: OfficeMacroFormat.docx,
  );
  await session.run(
    wordParagraphControlsPlan('ActiveDocument.Paragraphs(2).Format.OpenUp'),
  );
  var spacing = wordParagraphControlsSpacing(session.bytes, 1);
  _check(
    spacing.getAttribute('before', namespaceUri: _w) == '240' &&
        spacing.getAttribute('after', namespaceUri: _w) == null &&
        spacing.getAttribute('line', namespaceUri: _w) == null,
    'A same-value write did not own only the before-spacing group',
  );
  final package = OpcPackage.openBytes(session.bytes);
  final styles = package.getPart('/word/styles.xml')!;
  styles.writeText(
    styles
        .readText()
        .replaceAll('w:before="240"', 'w:before="400"')
        .replaceAll('w:after="180"', 'w:after="600"')
        .replaceAll('w:line="360"', 'w:line="480"'),
  );
  var saved = package.save();
  for (var cycle = 0; cycle < 3; cycle++) {
    final document = WordDeserializer().readBytes(saved);
    final paragraph = document.paragraphs.elementAt(1);
    spacing = wordParagraphControlsSpacing(saved, 1);
    _check(
      paragraph.properties.spacingBefore == 12 &&
          paragraph.properties.spacingAfter == 30 &&
          paragraph.properties.lineSpacing == 2 &&
          spacing.getAttribute('before', namespaceUri: _w) == '240' &&
          spacing.getAttribute('after', namespaceUri: _w) == null &&
          spacing.getAttribute('line', namespaceUri: _w) == null &&
          document.paragraphs.elementAt(3).properties.spacingBefore == 20,
      'Later style edit defeated direct before ownership or froze inheritance',
    );
    assertWordParagraphControlsMacroParts(saved);
    if (cycle < 2) saved = WordSerializer().writeBytes(document);
  }
  return {
    'before': 12,
    'after': 30,
    'line': 2,
    'untouchedBefore': 20,
    'additionalReopens': 2,
  };
}

Future<void> assertWordParagraphControlsRefusal(
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
  if (session.policy.allowMutation) session.startRecording('Rejected controls');
  for (final action in [session.validate, session.run]) {
    try {
      await action(plan);
      throw StateError(
        'Invalid paragraph-controls plan unexpectedly succeeded',
      );
    } on OfficeMacroException catch (error) {
      if (error.code != code ||
          (stepIndex != null && error.stepIndex != stepIndex) ||
          (tool != null && error.tool != tool)) {
        rethrow;
      }
    }
    _check(
      session.revision == 0 && base64Encode(session.bytes) == original,
      'Rejected paragraph-controls plan published a partial edit',
    );
  }
  if (session.policy.allowMutation) {
    _check(
      session.stopRecording().steps.isEmpty,
      'Rejected playback contaminated the recording',
    );
  }
}

Future<Map<String, Object?>> runWordParagraphControlsPolicies() async {
  final input = wordParagraphControlsInput();
  final plan = wordParagraphControlsPlan('''
ActiveDocument.Paragraphs(1).OpenUp
ActiveDocument.Paragraphs(2).Format.CloseUp
''');
  for (final (policy, code) in <(OfficeMacroPolicy, String)>[
    (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
    (
      OfficeMacroPolicy(allowedTools: {'docx.paragraphFormat'}),
      'permission_denied',
    ),
    (OfficeMacroPolicy(maxSteps: 1), 'limit_exceeded'),
  ]) {
    await assertWordParagraphControlsRefusal(
      input,
      plan,
      policy: policy,
      code: code,
    );
  }
  final session = OfficeMacroSession(
    input,
    format: OfficeMacroFormat.docx,
    policy: OfficeMacroPolicy(
      allowedTools: {'docx.paragraphSpaceBefore'},
      maxSteps: 2,
    ),
  );
  await session.run(plan);
  final state = wordParagraphControlsState(session.bytes);
  _check(
    session.revision == 1 &&
        state[0]['before'] == 12 &&
        state[1]['before'] == 0,
    'Allowlisted paragraph controls did not preserve the plan',
  );
  return {'refusedPolicies': 3, 'completeAllowlistRevision': 1};
}

Future<Map<String, Object?>> runWordParagraphControlsRollback() async {
  await assertWordParagraphControlsRefusal(
    wordParagraphControlsInput(),
    wordParagraphControlsPlan('''
ActiveDocument.Paragraphs(1).OpenUp
ActiveDocument.Paragraphs(2).Range.Font.Bold = True
ActiveDocument.Paragraphs(99).Format.OpenOrCloseUp
'''),
    stepIndex: 2,
    tool: 'docx.paragraphSpaceBefore',
  );
  return {'failedStep': 2, 'validateAndRunRollback': true};
}

Future<Map<String, Object?>> runWordParagraphControlsNativeGuards() async {
  // Exercise XML integer parsing and automatic-unit refusals on both hosts.
  // The exact boundary is deliberately greater than signed 32-bit twips.
  const variants = [
    ('w:before="120"', 'w:before="2147483648"'),
    ('w:before="120"', 'w:before="120" w:beforeLines="10"'),
    ('w:beforeAutospacing="0"', 'w:beforeAutospacing="true"'),
  ];
  for (final (before, after) in variants) {
    final package = OpcPackage.openBytes(wordParagraphControlsInput());
    final part = package.getPart('/word/document.xml')!;
    final source = part.readText();
    final changed = source.replaceFirst(before, after);
    _check(source != changed, 'Native refusal fixture did not alter XML');
    part.writeText(changed);
    await assertWordParagraphControlsRefusal(
      package.save(),
      wordParagraphControlsPlan('''
ActiveDocument.Paragraphs(2).Range.Font.Bold = True
ActiveDocument.Paragraphs(1).OpenOrCloseUp
'''),
      stepIndex: 1,
      tool: 'docx.paragraphSpaceBefore',
    );
  }
  return {'refusedSources': 3, 'validateAndRunRollback': true};
}

Future<Map<String, Object?>> runWordParagraphControlsRecording() async {
  final input = wordParagraphControlsInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Paragraph spacing controls');
  for (final (paragraph, action) in const [
    (0, 'open'),
    (1, 'close'),
    (2, 'toggle'),
  ]) {
    await session.callTool('docx.paragraphSpaceBefore', {
      'paragraph': paragraph,
      'action': action,
    });
  }
  final beforeFailure = base64Encode(session.bytes);
  try {
    await session.callTool('docx.paragraphSpaceBefore', {
      'paragraph': 99,
      'action': 'toggle',
    });
    throw StateError('A failed native call was accepted');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed') rethrow;
  }
  final recorded = session.stopRecording();
  _check(
    recorded.steps.length == 3 &&
        recorded.steps[2].arguments['action'] == 'toggle' &&
        session.revision == 3 &&
        base64Encode(session.bytes) == beforeFailure,
    'Failed native call changed publication or recording',
  );
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recorded.encode()));
  _check(
    replay.revision == 1 &&
        jsonEncode(wordParagraphControlsState(replay.bytes)) ==
            jsonEncode(wordParagraphControlsState(session.bytes)),
    'Recorded controls changed meaning on replay',
  );
  // Record the action, not the result read from the first document.
  final changedPackage = OpcPackage.openBytes(input);
  final part = changedPackage.getPart('/word/document.xml')!;
  part.writeText(
    part.readText().replaceFirst('w:before="0"', 'w:before="120"'),
  );
  final changed = OfficeMacroSession(
    changedPackage.save(),
    format: OfficeMacroFormat.docx,
  );
  await changed.run(OfficeMacro.parse(recorded.encode()));
  _check(
    wordParagraphControlsState(changed.bytes)[2]['before'] == 0,
    'Recorded toggle froze its original result instead of reading its target',
  );
  assertWordParagraphControlsMacroParts(replay.bytes);
  return {
    'recordedSteps': 3,
    'failedCallExcluded': true,
    'replayRevision': 1,
    'toggleReadsReplayTarget': true,
  };
}

Future<void> main() async {
  _check(
    _example.isNotEmpty,
    'Provide exact committed BAS in the compile define',
  );
  final source = utf8.decode(base64Decode(_example));
  final result = <String, Object?>{
    'example': await runWordParagraphControlsExample(source),
    'repeat': await runWordParagraphControlsExampleReplay(source),
    'sequential': await runWordParagraphControlsSequentialToggles(),
    'ownership': await runWordParagraphControlsStyleOwnership(),
    'policies': await runWordParagraphControlsPolicies(),
    'rollback': await runWordParagraphControlsRollback(),
    'nativeGuards': await runWordParagraphControlsNativeGuards(),
    'recording': await runWordParagraphControlsRecording(),
  };
  print(jsonEncode(result));
}
