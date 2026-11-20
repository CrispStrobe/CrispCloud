import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// Supply the exact committed BAS bytes to both VM and JS compilation.
const _example = String.fromEnvironment('WORD_LIST_LEVELS_BAS_BASE64');
const _w = OfficeNamespaces.w;
const _macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
const _projectType = 'application/vnd.ms-office.vbaProject';
const _projectRelationship =
    'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
const _projectBytes = [0, 1, 127, 128, 254, 255];
const _signatureBytes = [9, 8, 7, 6];

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    source: source,
  ),
);

OfficeMacro wordListLevelPlan(String body) =>
    _source('Sub Main()\n$body\nEnd Sub');

/// A DOCM fixture with formatting, custom tabs and an untouched existing list.
Uint8List wordListLevelInput() {
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(
            properties: WmlParagraphProps(
              keepTogether: true,
              spacingBefore: 6,
              explicitIndent: true,
              indent: const WmlIndent(left: 6, right: 12, firstLine: 3),
              tabs: const [
                WmlTabStop(
                  position: 72,
                  alignment: WmlTabAlignment.center,
                  leader: WmlTabLeader.dot,
                ),
              ],
            ),
            inlines: [
              WmlRun(
                text: 'Outline section',
                properties: WmlRunProps(bold: true),
              ),
            ],
          ),
          WmlParagraph(
            properties: WmlParagraphProps(
              explicitIndent: true,
              indent: const WmlIndent(right: 8),
            ),
            inlines: [WmlRun(text: 'Outline detail')],
          ),
          WmlParagraph(),
          WmlParagraph(inlines: [WmlRun(text: 'Untouched imported outline')]),
        ],
      ),
    ],
  );
  final untouched = document.paragraphs.last;
  WordLists.applyLevel(untouched, numbered: true, level: 1, document: document);
  untouched.properties
    ..explicitIndent = true
    ..indent = const WmlIndent(left: 42, right: 7, hanging: 6);
  final package = OpcPackage.openBytes(WordSerializer().writeBytes(document));
  package.getPart('/word/document.xml')!.contentType = _macroType;
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
  package
      .relationshipsFor('/word/document.xml')
      .add(
        type: _projectRelationship,
        target: 'vbaProject.bin',
        id: 'rIdListLevelProject',
      );
  package
      .relationshipsFor('/word/vbaProject.bin')
      .add(
        type: '${_projectRelationship}Signature',
        target: 'vbaProjectSignature.bin',
        id: 'rIdListLevelSignature',
      );
  return package.save();
}

/// An imported list whose geometry differs from the Quds defaults.
Uint8List wordListLevelImportedInput({
  int level = 0,
  int? omitLevel,
  bool bullet = false,
  bool normalize = true,
}) {
  final package = OpcPackage.openBytes(wordListLevelInput());
  final levels = StringBuffer();
  for (var index = 0; index < 9; index++) {
    if (index == omitLevel) continue;
    levels.write('''
<w:lvl w:ilvl="$index"><w:start w:val="3"/>
<w:numFmt w:val="${bullet ? 'bullet' : 'decimal'}"/>
<w:lvlText w:val="${bullet ? '•' : '[%${index + 1}]'}"/>
<w:pPr><w:ind w:left="${600 + index * 240}" w:hanging="${120 + index * 20}"/></w:pPr>
</w:lvl>''');
  }
  package.getPart('/word/numbering.xml')!.writeText('''
<w:numbering xmlns:w="$_w">
<w:abstractNum w:abstractNumId="41"><w:nsid w:val="1234ABCD"/>
<w:multiLevelType w:val="multilevel"/><w:name w:val="Imported levels"/>
$levels</w:abstractNum>
<w:num w:numId="37"><w:abstractNumId w:val="41"/></w:num>
</w:numbering>''');
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="$_w"><w:body>
<w:p><w:pPr><w:keepLines/><w:spacing w:before="120"/>
<w:numPr><w:ilvl w:val="$level"/><w:numId w:val="37"/></w:numPr>
<w:ind w:left="840" w:right="140" w:hanging="120"/></w:pPr>
<w:r><w:rPr><w:b/></w:rPr><w:t>Imported selected item</w:t></w:r></w:p>
<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="37"/></w:numPr>
<w:ind w:left="600" w:right="80" w:hanging="120"/></w:pPr>
<w:r><w:t>Untouched shared instance</w:t></w:r></w:p>
<w:sectPr/></w:body></w:document>''');
  final input = package.save();
  // The ordinary serializer adds absent legacy definitions 1/2 and normalizes
  // XML. Full-part byte comparisons use this deliberately normalized baseline.
  // Separate raw-import tests compare all existing definition/instance nodes.
  return normalize
      ? WordSerializer().writeBytes(WordDeserializer().readBytes(input))
      : input;
}

String wordListLevelNumbering(Uint8List bytes) =>
    OpcPackage.openBytes(bytes).getPart('/word/numbering.xml')!.readText();

Object _semanticNumberingNode(XmlNode node) {
  if (node is XmlElement) {
    final attributes = <String, String>{
      for (final attribute in node.attributes)
        if (attribute.prefix != 'xmlns' && attribute.localName != 'xmlns')
          '{${attribute.namespaceUri}}${attribute.localName}': attribute.value,
    };
    final names = attributes.keys.toList()..sort();
    return {
      'name': '{${node.namespaceUri}}${node.localName}',
      'attributes': {for (final name in names) name: attributes[name]},
      'children': [
        for (final child in node.children)
          if (child is! XmlText || child.text.trim().isNotEmpty)
            _semanticNumberingNode(child),
      ],
    };
  }
  return switch (node) {
    XmlText() => {'text': node.text},
    XmlCdata() => {'cdata': node.text},
    XmlComment() => {'comment': node.text},
    _ => throw StateError('Unknown numbering XML node'),
  };
}

String _importedNumberingNodes(Uint8List bytes) {
  final root = XmlDocument.parse(wordListLevelNumbering(bytes)).root!;
  return jsonEncode([
    _semanticNumberingNode(
      root
          .childrenNamed('abstractNum')
          .singleWhere((node) => node.getAttribute('abstractNumId') == '41'),
    ),
    _semanticNumberingNode(
      root
          .childrenNamed('num')
          .singleWhere((node) => node.getAttribute('numId') == '37'),
    ),
  ]);
}

/// Raw imported XML may be normalized, but its complete existing nodes survive.
Future<Map<String, Object?>> runWordListLevelRawImport({
  bool bullet = false,
}) async {
  final input = wordListLevelImportedInput(bullet: bullet, normalize: false);
  final originalNodes = _importedNumberingNodes(input);
  final untouched = wordListLevelState(input).last;
  final guard = (await WordPackagePreservation.capture(
    input,
    'raw-import.docm',
  ))!;
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await session.run(
    wordListLevelPlan('''
ActiveDocument.Paragraphs(1).Range.ListFormat.ListLevelNumber = 7
'''),
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    final state = wordListLevelState(saved);
    if (_importedNumberingNodes(saved) != originalNodes ||
        state.first['numId'] != 37 ||
        state.first['level'] != 6 ||
        state.first['format'] != (bullet ? 'bullet' : 'decimal') ||
        state.first['leftTwips'] != 2040 ||
        state.first['rightTwips'] != 140 ||
        state.first['hangingTwips'] != 240 ||
        jsonEncode(state.last) != jsonEncode(untouched)) {
      throw StateError('Level editing changed imported native numbering nodes');
    }
    await guard.validateSaved(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  return {
    'format': bullet ? 'bullet' : 'decimal',
    'retainedNumId': 37,
    'level': 6,
    'existingNodesPreserved': true,
    'additionalReopens': 2,
  };
}

/// Read persisted definitions and indentation, not the cached display label.
List<Map<String, Object?>> wordListLevelState(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  final numbering = XmlDocument.parse(wordListLevelNumbering(bytes)).root!;
  return [
    for (final paragraph in document.paragraphs)
      (() {
        final properties = paragraph.properties;
        String? format;
        String? label;
        int? levelCount;
        if (properties.numId case final int id) {
          final instance = numbering
              .childrenNamed('num')
              .singleWhere((node) => node.getAttribute('numId') == '$id');
          final abstractId = instance
              .firstChild('abstractNumId')!
              .getAttribute('val');
          final definition = numbering
              .childrenNamed('abstractNum')
              .singleWhere(
                (node) => node.getAttribute('abstractNumId') == abstractId,
              );
          final levels = definition.childrenNamed('lvl').toList();
          levelCount = levels.length;
          final level = levels.singleWhere(
            (node) => node.getAttribute('ilvl') == '${properties.ilvl}',
          );
          format = level.firstChild('numFmt')!.getAttribute('val');
          label = level.firstChild('lvlText')!.getAttribute('val');
        }
        return <String, Object?>{
          'text': paragraph.text,
          'numId': properties.numId,
          'level': properties.ilvl,
          'format': format,
          'label': label,
          'definedLevels': levelCount,
          'suppressed': properties.numberingSuppressed,
          'leftTwips': (properties.indent.left * 20).round(),
          'rightTwips': (properties.indent.right * 20).round(),
          'firstLineTwips': (properties.indent.firstLine * 20).round(),
          'hangingTwips': (properties.indent.hanging * 20).round(),
        };
      })(),
  ];
}

void _checkMacroBytes(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  final project = package
      .relationshipsFor('/word/document.xml')
      .items
      .singleWhere((item) => item.type == _projectRelationship);
  final signature = package
      .relationshipsFor('/word/vbaProject.bin')
      .items
      .single;
  if (package.getPart('/word/document.xml')!.contentType != _macroType ||
      package.getPart('/word/vbaProject.bin')!.contentType != _projectType ||
      base64Encode(package.getPart('/word/vbaProject.bin')!.readBytes()) !=
          base64Encode(_projectBytes) ||
      base64Encode(
            package.getPart('/word/vbaProjectSignature.bin')!.readBytes(),
          ) !=
          base64Encode(_signatureBytes) ||
      project.id != 'rIdListLevelProject' ||
      project.target != 'vbaProject.bin' ||
      signature.id != 'rIdListLevelSignature' ||
      signature.target != 'vbaProjectSignature.bin' ||
      signature.type != '${_projectRelationship}Signature') {
    throw StateError('List editing changed opaque VBA payloads or links');
  }
}

String _outlineLabel(int level) =>
    '${List.generate(level + 1, (index) => '%${index + 1}').join('.')}.';

void _checkExample(Uint8List bytes, Map<String, Object?> untouched) {
  final states = wordListLevelState(bytes);
  const texts = ['Outline section', 'Outline detail', ''];
  const levels = [1, 2, 8];
  const right = [240, 160, 0];
  for (var index = 0; index < 3; index++) {
    final state = states[index];
    final level = levels[index];
    if (state['text'] != texts[index] ||
        state['numId'] == null ||
        state['level'] != level ||
        state['format'] != 'decimal' ||
        state['label'] != _outlineLabel(level) ||
        state['definedLevels'] != 9 ||
        state['suppressed'] != false ||
        state['leftTwips'] != (level + 1) * 360 ||
        state['rightTwips'] != right[index] ||
        state['firstLineTwips'] != 0 ||
        state['hangingTwips'] != 180) {
      throw StateError('Unexpected saved outline level or geometry: $state');
    }
  }
  final first = WordDeserializer().readBytes(bytes).paragraphs.first;
  if (states.length != 4 ||
      jsonEncode(states.last) != jsonEncode(untouched) ||
      !first.properties.keepTogether ||
      first.properties.spacingBefore != 6 ||
      !first.inlines.whereType<WmlRun>().first.properties.bold ||
      first.properties.tabs.single.position != 72 ||
      first.properties.tabs.single.alignment != WmlTabAlignment.center ||
      first.properties.tabs.single.leader != WmlTabLeader.dot) {
    throw StateError('List level editing changed unrelated document content');
  }
  _checkMacroBytes(bytes);
}

/// Executes the actual supplied BAS and checks two additional save/reopen cycles.
Future<Map<String, Object?>> runWordListLevelExample(String source) async {
  final input = wordListLevelInput();
  final original = base64Encode(input);
  final untouched = wordListLevelState(input).last;
  final preservation = (await WordPackagePreservation.capture(
    input,
    'list-levels.docm',
  ))!;
  final plan = _source(source);
  if (plan.steps.length != 13) {
    throw StateError('Expected thirteen example operations');
  }
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Outline level example playback');
  final validation = await session.validate(plan);
  if (!validation.validatedOnly ||
      validation.completedSteps != 13 ||
      session.revision != 0 ||
      base64Encode(session.bytes) != original) {
    throw StateError('Validation changed the published document');
  }
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  if (result.completedSteps != 13 ||
      result.revision != 1 ||
      result.validatedOnly ||
      base64Encode(input) != original ||
      session.stopRecording().steps.isNotEmpty) {
    throw StateError('Example did not publish one isolated transaction');
  }
  var saved = session.bytes;
  final state = wordListLevelState(saved);
  final definitions = wordListLevelNumbering(saved);
  for (var cycle = 0; cycle < 3; cycle++) {
    _checkExample(saved, untouched);
    await preservation.validateSaved(saved);
    if (jsonEncode(wordListLevelState(saved)) != jsonEncode(state) ||
        wordListLevelNumbering(saved) != definitions) {
      throw StateError('Repeated save changed native numbering');
    }
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  return {
    'operations': 13,
    'revision': 1,
    'additionalReopens': 2,
    'opaqueVbaPreserved': true,
    'paragraphs': state,
  };
}

Future<Map<String, Object?>> runWordListLevelExampleReplay(
  String source,
) async {
  final input = wordListLevelInput();
  final untouched = wordListLevelState(input).last;
  final plan = _source(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await session.run(plan);
  final firstState = jsonEncode(wordListLevelState(session.bytes));
  final firstBytes = base64Encode(session.bytes);
  final validation = await session.validate(plan);
  if (!validation.validatedOnly ||
      validation.completedSteps != 13 ||
      session.revision != 1 ||
      base64Encode(session.bytes) != firstBytes) {
    throw StateError('Repeated example validation published a change');
  }
  final result = await session.run(plan);
  _checkExample(session.bytes, untouched);
  if (result.completedSteps != 13 ||
      session.revision != 2 ||
      jsonEncode(wordListLevelState(session.bytes)) != firstState) {
    throw StateError('Example changed its meaning when run on its own output');
  }
  return {'operationsPerRun': 13, 'revision': 2, 'sameSavedState': true};
}

Future<Map<String, Object?>> runWordListLevelTransitions() async {
  final session = OfficeMacroSession(
    wordListLevelInput(),
    format: OfficeMacroFormat.docx,
  );
  const target = 'ActiveDocument.Paragraphs(1).Range.ListFormat';
  await session.run(wordListLevelPlan('$target.ApplyOutlineNumberDefault'));
  final id = wordListLevelState(session.bytes).first['numId'];
  final definitions = wordListLevelNumbering(session.bytes);
  for (var level = 0; level < 9; level++) {
    await session.run(
      wordListLevelPlan('$target.ListLevelNumber = ${level + 1}'),
    );
    final state = wordListLevelState(session.bytes).first;
    if (state['numId'] != id ||
        state['level'] != level ||
        state['label'] != _outlineLabel(level) ||
        state['leftTwips'] != (level + 1) * 360 ||
        state['rightTwips'] != 240 ||
        state['hangingTwips'] != 180 ||
        wordListLevelNumbering(session.bytes) != definitions) {
      throw StateError('Absolute level change rewrote numbering or geometry');
    }
  }
  for (final (method, level) in [('ListOutdent', 7), ('ListIndent', 8)]) {
    await session.run(wordListLevelPlan('Call $target.$method()'));
    final state = wordListLevelState(session.bytes).first;
    if (state['numId'] != id ||
        state['level'] != level ||
        state['leftTwips'] != (level + 1) * 360 ||
        wordListLevelNumbering(session.bytes) != definitions) {
      throw StateError('Relative level change rewrote numbering or geometry');
    }
  }
  await session.run(wordListLevelPlan('$target.ApplyOutlineNumberDefault'));
  final cleared = wordListLevelState(session.bytes).first;
  if (cleared['numId'] != null ||
      cleared['suppressed'] != true ||
      cleared['leftTwips'] != 3240 ||
      cleared['hangingTwips'] != 180) {
    throw StateError('Outline default did not toggle off with retained indent');
  }
  await session.run(wordListLevelPlan('$target.ApplyOutlineNumberDefault'));
  final reapplied = wordListLevelState(session.bytes).first;
  if (reapplied['numId'] == null ||
      reapplied['level'] != 0 ||
      reapplied['label'] != '%1.' ||
      reapplied['leftTwips'] != 360 ||
      session.revision != 14) {
    throw StateError('Outline default did not toggle back on at level one');
  }
  _checkMacroBytes(session.bytes);
  return {
    'absoluteLevels': 9,
    'relativeLevels': [7, 8],
    'retainedListIdentity': true,
    'toggleOffRetainsIndent': true,
    'toggleOnLevel': 0,
    'revision': session.revision,
  };
}

/// Both dry-run and execution must fail without publishing or recording.
Future<void> assertWordListLevelRefusal(
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
  final canRecord = session.policy.allowMutation;
  if (canRecord) {
    session.startRecording('Refused outline level update');
  } else {
    try {
      session.startRecording('Read-only recording must be refused');
      throw StateError('A read-only session unexpectedly started recording');
    } on OfficeMacroException catch (error) {
      if (error.code != 'permission_denied') rethrow;
    }
    if (session.isRecording) {
      throw StateError('A read-only session retained a recording');
    }
  }
  for (final action in [session.validate, session.run]) {
    try {
      await action(plan);
      throw StateError('Unsupported list level request unexpectedly published');
    } on OfficeMacroException catch (error) {
      if (error.code != code ||
          (stepIndex != null && error.stepIndex != stepIndex) ||
          (tool != null && error.tool != tool)) {
        rethrow;
      }
    }
    if (session.revision != 0 || base64Encode(session.bytes) != original) {
      throw StateError('Refused list operation changed the published document');
    }
  }
  if (canRecord && session.stopRecording().steps.isNotEmpty) {
    throw StateError('Rejected playback contaminated the recording');
  }
}

Future<Map<String, Object?>> runWordListLevelGuards() async {
  const target = 'ActiveDocument.Paragraphs(1).Range.ListFormat';
  var cases = 0;
  for (final statement in [
    '$target.ListLevelNumber = 2',
    '$target.ListIndent',
    '$target.ListOutdent',
  ]) {
    await assertWordListLevelRefusal(
      wordListLevelInput(),
      wordListLevelPlan(statement),
      stepIndex: 0,
      tool: 'docx.listLevel',
    );
    cases++;
  }
  for (final (level, statement) in [
    (0, '$target.ListOutdent'),
    (8, '$target.ListIndent'),
  ]) {
    await assertWordListLevelRefusal(
      wordListLevelImportedInput(level: level),
      wordListLevelPlan(statement),
      stepIndex: 0,
      tool: 'docx.listLevel',
    );
    cases++;
  }
  for (final statement in [
    '$target.ListLevelNumber = 2',
    '$target.ListIndent',
  ]) {
    await assertWordListLevelRefusal(
      wordListLevelImportedInput(omitLevel: 1),
      wordListLevelPlan('''
ActiveDocument.Paragraphs(2).Range.ParagraphFormat.SpaceAfter = 12
$statement
'''),
      stepIndex: 1,
      tool: 'docx.listLevel',
    );
    cases++;
  }
  await assertWordListLevelRefusal(
    wordListLevelInput(),
    wordListLevelPlan('''
$target.ApplyOutlineNumberDefault
$target.ListLevelNumber = 4
ActiveDocument.Paragraphs(99).Range.ListFormat.ListIndent
'''),
    stepIndex: 2,
    tool: 'docx.listLevel',
  );
  cases++;
  final sourceLevel = wordListLevelPlan('$target.ListIndent').steps.single;
  await assertWordListLevelRefusal(
    wordListLevelImportedInput(),
    OfficeMacro(
      name: 'Pending restart refuses level change',
      format: OfficeMacroFormat.docx,
      steps: [
        OfficeMacroStep(
          tool: 'docx.listRestart',
          arguments: {'paragraph': 0, 'at': 4},
        ),
        sourceLevel,
      ],
    ),
    stepIndex: 1,
    tool: 'docx.listLevel',
  );
  cases++;
  return {'refusedPlans': cases, 'validateAndRunRollback': true};
}

Future<Map<String, Object?>> runWordListLevelPolicies() async {
  final input = wordListLevelInput();
  final plan = wordListLevelPlan('''
ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyOutlineNumberDefault
ActiveDocument.Paragraphs(1).Range.ListFormat.ListLevelNumber = 3
''');
  for (final (policy, code) in <(OfficeMacroPolicy, String)>[
    (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
    (
      OfficeMacroPolicy(allowedTools: {'docx.listOutlineDefault'}),
      'permission_denied',
    ),
    (OfficeMacroPolicy(allowedTools: {'docx.listLevel'}), 'permission_denied'),
    (OfficeMacroPolicy(maxSteps: 1), 'limit_exceeded'),
  ]) {
    await assertWordListLevelRefusal(input, plan, policy: policy, code: code);
  }
  final session = OfficeMacroSession(
    input,
    format: OfficeMacroFormat.docx,
    policy: OfficeMacroPolicy(
      allowedTools: {'docx.listOutlineDefault', 'docx.listLevel'},
    ),
  );
  final validated = await session.validate(plan);
  if (!validated.validatedOnly ||
      session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(input)) {
    throw StateError('Allowlisted validation published an edit');
  }
  await session.run(plan);
  if (session.revision != 1 ||
      wordListLevelState(session.bytes).first['level'] != 2) {
    throw StateError('Allowlisting both native tools did not permit the plan');
  }
  return {'refusedPolicies': 4, 'completeAllowlistRevision': 1};
}

Future<Map<String, Object?>> runWordListLevelRecording() async {
  final input = wordListLevelInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Recorded outline operations');
  await session.callTool('docx.listOutlineDefault', {'paragraph': 0});
  await session.callTool('docx.listLevel', {'paragraph': 0, 'delta': 1});
  final beforeFailure = base64Encode(session.bytes);
  try {
    await session.callTool('docx.listLevel', {'paragraph': 99, 'delta': 1});
    throw StateError('Missing paragraph unexpectedly recorded');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed') rethrow;
  }
  final recorded = session.stopRecording();
  if (recorded.steps.length != 2 ||
      session.revision != 2 ||
      base64Encode(session.bytes) != beforeFailure) {
    throw StateError('Failed native call changed document or recorded steps');
  }
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recorded.encode()));
  if (replay.revision != 1 ||
      jsonEncode(wordListLevelState(replay.bytes)) !=
          jsonEncode(wordListLevelState(session.bytes))) {
    throw StateError('Recorded outline operations changed meaning on replay');
  }
  return {'recordedSteps': 2, 'failedCallExcluded': true, 'replayRevision': 1};
}

int _sourceRefusals() {
  const target = 'ActiveDocument.Paragraphs(1).Range.ListFormat';
  const statements = [
    '$target.ApplyOutlineNumberDefault wdWord9ListBehavior',
    '$target.ApplyOutlineNumberDefault wdWord10ListBehavior',
    '$target.ApplyOutlineNumberDefault True',
    '$target.ApplyOutlineNumberDefault "0"',
    '$target.ListLevelNumber = 0',
    '$target.ListLevelNumber = 10',
    '$target.ListLevelNumber = 1.5',
    '$target.ListLevelNumber = True',
    '$target.ListLevelNumber = "2"',
    '$target.ListIndent 1',
    '$target.ListOutdent Level:=1',
    'Dim n As Long\nn = $target.ListLevelNumber',
  ];
  for (final statement in statements) {
    try {
      wordListLevelPlan(statement);
      throw StateError('Unsupported source unexpectedly compiled: $statement');
    } on OfficeVbaCompileException {
      // Refused source does not produce a native macro plan.
    }
  }
  return statements.length;
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError(
      'Supply exact committed WORD_LIST_LEVELS_BAS_BASE64 bytes',
    );
  }
  print(
    jsonEncode({
      'example': await runWordListLevelExample(
        utf8.decode(base64Decode(_example)),
      ),
      'exampleReplay': await runWordListLevelExampleReplay(
        utf8.decode(base64Decode(_example)),
      ),
      'transitions': await runWordListLevelTransitions(),
      'rawImports': [
        await runWordListLevelRawImport(),
        await runWordListLevelRawImport(bullet: true),
      ],
      'nativeGuards': await runWordListLevelGuards(),
      'policies': await runWordListLevelPolicies(),
      'recording': await runWordListLevelRecording(),
      'refusedSources': _sourceRefusals(),
    }),
  );
}
