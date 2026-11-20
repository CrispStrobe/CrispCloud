import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// Supply the exact committed BAS bytes to both VM and JS compilation.
const _example = String.fromEnvironment('WORD_LISTS_BAS_BASE64');

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    source: source,
  ),
);

Uint8List wordListInput() {
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
                  position: 54,
                  alignment: WmlTabAlignment.center,
                  leader: WmlTabLeader.dot,
                ),
              ],
            ),
            inlines: [
              WmlRun(
                text: 'Numbered report',
                properties: WmlRunProps(bold: true),
              ),
            ],
          ),
          WmlParagraph(
            properties: WmlParagraphProps(
              explicitIndent: true,
              indent: const WmlIndent(right: 8),
            ),
            inlines: [WmlRun(text: 'Bullet report')],
          ),
          WmlParagraph(),
          WmlParagraph(inlines: [WmlRun(text: 'Cleared existing bullet')]),
          WmlParagraph(inlines: [WmlRun(text: 'Untouched nested numbering')]),
        ],
      ),
    ],
  );
  final paragraphs = document.paragraphs.toList();
  WordLists.applyLevel(paragraphs[3], numbered: false, document: document);
  paragraphs[3].properties
    ..explicitIndent = true
    ..indent = const WmlIndent(left: 27, right: 5, hanging: 3);
  WordLists.applyLevel(
    paragraphs[4],
    numbered: true,
    level: 1,
    document: document,
  );
  paragraphs[4].properties
    ..explicitIndent = true
    ..indent = const WmlIndent(left: 42, right: 7, hanging: 6);
  return WordSerializer().writeBytes(document);
}

/// Inspect the saved native definitions rather than relying on cached labels.
List<Map<String, Object?>> wordListState(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  final package = document.package!;
  final relationships = package.relationshipsFor('/word/document.xml');
  final relationship = relationships.firstByType(RelationshipTypes.numbering);
  final part = relationship == null
      ? null
      : package.getPart(relationships.resolve(relationship));
  final numbering = part == null
      ? null
      : XmlDocument.parse(part.readText()).root;
  return [
    for (final paragraph in document.paragraphs)
      (() {
        final properties = paragraph.properties;
        final id = properties.numId;
        String kind = 'none';
        if (id != null) {
          final instance = numbering!
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
          final level = definition
              .childrenNamed('lvl')
              .singleWhere(
                (node) => node.getAttribute('ilvl') == '${properties.ilvl}',
              );
          kind = level.firstChild('numFmt')!.getAttribute('val')!;
        }
        return <String, Object?>{
          'text': paragraph.text,
          'kind': kind,
          'level': properties.ilvl,
          'suppressed': properties.numberingSuppressed,
          'leftTwips': (properties.indent.left * 20).round(),
          'rightTwips': (properties.indent.right * 20).round(),
          'firstLineTwips': (properties.indent.firstLine * 20).round(),
          'hangingTwips': (properties.indent.hanging * 20).round(),
        };
      })(),
  ];
}

void _checkExample(Uint8List bytes, Map<String, Object?> untouched) {
  final state = wordListState(bytes);
  const texts = [
    'Numbered report',
    'Bullet report',
    '',
    'Cleared existing bullet',
    'Untouched nested numbering',
  ];
  const kinds = ['decimal', 'bullet', 'bullet', 'none', 'decimal'];
  const levels = [0, 0, 0, 0, 1];
  const left = [360, 360, 360, 540, 840];
  const right = [240, 160, 0, 100, 140];
  const hanging = [180, 180, 180, 60, 120];
  for (var i = 0; i < texts.length; i++) {
    if (state[i]['text'] != texts[i] ||
        state[i]['kind'] != kinds[i] ||
        state[i]['level'] != levels[i] ||
        state[i]['suppressed'] != (i == 3) ||
        state[i]['leftTwips'] != left[i] ||
        state[i]['rightTwips'] != right[i] ||
        state[i]['firstLineTwips'] != 0 ||
        state[i]['hangingTwips'] != hanging[i]) {
      throw StateError(
        'Native list or unrelated indentation changed: ${state[i]}',
      );
    }
  }
  final first = WordDeserializer().readBytes(bytes).paragraphs.first;
  if (jsonEncode(state.last) != jsonEncode(untouched) ||
      !first.properties.keepTogether ||
      first.properties.spacingBefore != 6 ||
      !first.inlines.whereType<WmlRun>().first.properties.bold ||
      first.properties.tabs.single.position != 54 ||
      first.properties.tabs.single.alignment != WmlTabAlignment.center ||
      first.properties.tabs.single.leader != WmlTabLeader.dot) {
    throw StateError('List editing changed unrelated document content');
  }
}

/// Runs the actual supplied BAS and two further native save/reopen cycles.
Future<Map<String, Object?>> runWordListExample(String source) async {
  final input = wordListInput();
  final original = base64Encode(input);
  final untouched = wordListState(input).last;
  final plan = _compile(source);
  if (plan.steps.length != 8) {
    throw StateError('Expected eight example operations');
  }
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Word default lists');
  final validation = await session.validate(plan);
  if (!validation.validatedOnly ||
      validation.completedSteps != 8 ||
      session.revision != 0 ||
      base64Encode(session.bytes) != original) {
    throw StateError('Validation changed the published document');
  }
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  if (result.completedSteps != 8 ||
      result.revision != 1 ||
      result.validatedOnly ||
      base64Encode(input) != original ||
      session.stopRecording().steps.isNotEmpty) {
    throw StateError('Example did not publish one isolated transaction');
  }
  var saved = session.bytes;
  _checkExample(saved, untouched);
  final state = wordListState(saved);
  for (var cycle = 0; cycle < 2; cycle++) {
    saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    _checkExample(saved, untouched);
    if (jsonEncode(wordListState(saved)) != jsonEncode(state)) {
      throw StateError('Repeated save changed native list semantics');
    }
  }
  return {
    'operations': 8,
    'revision': 1,
    'additionalReopens': 2,
    'paragraphs': state,
  };
}

Future<Map<String, Object?>> _toggleAndChangeKind() async {
  final session = OfficeMacroSession(
    wordListInput(),
    format: OfficeMacroFormat.docx,
  );
  const methods = [
    'ApplyNumberDefault',
    'ApplyNumberDefault',
    'ApplyBulletDefault',
    'ApplyNumberDefault',
    'RemoveNumbers NumberType:=wdNumberParagraph',
  ];
  const expected = ['decimal', 'none', 'bullet', 'decimal', 'none'];
  for (var i = 0; i < methods.length; i++) {
    await session.run(
      _compile('''
Sub Main()
  ActiveDocument.Paragraphs(1).Range.ListFormat.${methods[i]}
End Sub
'''),
    );
    if (session.revision != i + 1 ||
        wordListState(session.bytes).first['kind'] != expected[i]) {
      throw StateError('Matching-kind toggle or kind conversion changed');
    }
  }
  return {'kinds': expected, 'revision': methods.length};
}

Future<void> _rollback() async {
  final input = wordListInput();
  final original = base64Encode(input);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Rejected list update');
  final plan = _compile('''
Sub Main()
  ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyNumberDefault
  ActiveDocument.Paragraphs(4).Range.ListFormat.RemoveNumbers
  ActiveDocument.Paragraphs(99).Range.ListFormat.ApplyBulletDefault
End Sub
''');
  for (final validateOnly in [true, false]) {
    try {
      if (validateOnly) {
        await session.validate(plan);
      } else {
        await session.run(plan);
      }
      throw StateError('Missing paragraph unexpectedly published');
    } on OfficeMacroException catch (error) {
      if (error.code != 'operation_failed' ||
          error.stepIndex != 2 ||
          error.tool != 'docx.listDefault') {
        rethrow;
      }
    }
  }
  if (session.revision != 0 ||
      base64Encode(session.bytes) != original ||
      session.stopRecording().steps.isNotEmpty) {
    throw StateError('Late list failure changed the published document');
  }
}

Future<Map<String, Object?>> _fieldAndPolicyGuards() async {
  final package = OpcPackage.openBytes(wordListInput());
  final part = package.getPart('/word/document.xml')!;
  final xml = XmlDocument.parse(part.readText());
  final first = xml.root!.firstChild('body')!.childrenNamed('p').first;
  first.addChild(
    XmlDocument.parse(
      '<w:fldSimple xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'w:instr=" LISTNUM LegalDefault "><w:r><w:t>7</w:t></w:r></w:fldSimple>',
    ).root!,
  );
  part.writeText(xml.toXmlString());
  final input = package.save();
  final original = base64Encode(input);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final plan = _compile('''
Sub Main()
  ActiveDocument.Paragraphs(2).Range.ListFormat.ApplyNumberDefault
  ActiveDocument.Paragraphs(1).Range.ListFormat.RemoveNumbers
End Sub
''');
  for (final validateOnly in [true, false]) {
    try {
      if (validateOnly) {
        await session.validate(plan);
      } else {
        await session.run(plan);
      }
      throw StateError('Unsupported LISTNUM removal unexpectedly published');
    } on OfficeMacroException catch (error) {
      if (error.code != 'operation_failed' ||
          error.stepIndex != 1 ||
          error.tool != 'docx.removeNumbers') {
        rethrow;
      }
    }
  }
  if (session.revision != 0 || base64Encode(session.bytes) != original) {
    throw StateError('LISTNUM refusal changed the published document');
  }
  await session.run(
    _compile('''
Sub Main()
  ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyBulletDefault
  ActiveDocument.Paragraphs(1).Range.ListFormat.RemoveNumbers wdNumberParagraph
End Sub
'''),
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    final document = WordDeserializer().readBytes(saved);
    final paragraph = document.paragraphs.first;
    if (paragraph.text != 'Numbered report7' ||
        paragraph.properties.numId != null ||
        !paragraph.properties.numberingSuppressed ||
        !document.package!
            .getPart('/word/document.xml')!
            .readText()
            .contains('LISTNUM LegalDefault')) {
      throw StateError('Paragraph-only removal changed a LISTNUM field');
    }
    saved = WordSerializer().writeBytes(document);
  }
  for (final (policy, code) in [
    (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
    (OfficeMacroPolicy(maxSteps: 1), 'limit_exceeded'),
  ]) {
    final guarded = OfficeMacroSession(
      input,
      format: OfficeMacroFormat.docx,
      policy: policy,
    );
    try {
      await guarded.run(plan);
      throw StateError('List macro bypassed its policy');
    } on OfficeMacroException catch (error) {
      if (error.code != code) rethrow;
    }
    if (guarded.revision != 0 || base64Encode(guarded.bytes) != original) {
      throw StateError('Policy refusal changed the published document');
    }
  }
  return {
    'allNumberRefusalRollback': true,
    'paragraphModePreservesField': true,
    'policyRefusals': 2,
  };
}

List<String> _nativeFieldTokens(Uint8List bytes) {
  final xml = OpcPackage.openBytes(
    bytes,
  ).getPart('/word/document.xml')!.readText();
  final tokens = <String>[];
  void visit(XmlElement node) {
    if (node.namespaceUri == OfficeNamespaces.w) {
      if (node.localName == 'fldChar') {
        tokens.add(
          'boundary:${node.getAttribute('fldCharType', namespaceUri: OfficeNamespaces.w)}',
        );
      } else if (node.localName == 'instrText') {
        tokens.add('instruction:${node.text}');
      }
    }
    for (final child in node.childElements) {
      visit(child);
    }
  }

  visit(XmlDocument.parse(xml).root!);
  return tokens;
}

Future<Map<String, Object?>> _opaqueFieldBoundaryGuards() async {
  var cases = 0;
  var paragraphRefusals = 0;
  var paragraphPreservations = 0;
  for (final wrapper in ['customXml', 'smartTag']) {
    for (final opaqueEnd in [false, true]) {
      final template = wordListInput();
      final bullet = WordDeserializer()
          .readBytes(template)
          .paragraphs
          .elementAt(3)
          .properties
          .numId;
      final package = OpcPackage.openBytes(template);
      const end = '<w:r><w:fldChar w:fldCharType="end"/></w:r>';
      final close = opaqueEnd
          ? '<w:$wrapper w:uri="urn:list-test" w:element="end"><w:p>$end</w:p></w:$wrapper>'
          : '';
      package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
  <w:p><w:r><w:t>First paragraph</w:t></w:r></w:p>
  <w:$wrapper w:uri="urn:list-test" w:element="start"><w:p>
    <w:r><w:fldChar w:fldCharType="begin"/></w:r>
    <w:r><w:instrText xml:space="preserve"> LISTNUM LegalDefault </w:instrText></w:r>
    <w:r><w:fldChar w:fldCharType="separate"/></w:r>
    <w:r><w:t>Start</w:t></w:r>
  </w:p></w:$wrapper>
  <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="$bullet"/></w:numPr></w:pPr>
    <w:r><w:t>Selected result</w:t></w:r>${opaqueEnd ? '' : end}
  </w:p>$close
  <w:p><w:r><w:t>Last paragraph</w:t></w:r></w:p><w:sectPr/>
</w:body></w:document>
''');
      final input = package.save();
      final original = base64Encode(input);
      final expectedFields = jsonEncode(_nativeFieldTokens(input));
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Opaque field boundary must not publish');
      final plan = _compile('''
Sub Main()
  ActiveDocument.Paragraphs(1).Range.ParagraphFormat.SpaceAfter = 12
  ActiveDocument.Paragraphs(2).Range.ListFormat.RemoveNumbers
End Sub
''');
      for (final validateOnly in [true, false]) {
        try {
          if (validateOnly) {
            await session.validate(plan);
          } else {
            await session.run(plan);
          }
          throw StateError('Opaque LISTNUM boundary unexpectedly published');
        } on OfficeMacroException catch (error) {
          if (error.code != 'operation_failed' ||
              error.stepIndex != 1 ||
              error.tool != 'docx.removeNumbers') {
            rethrow;
          }
        }
      }
      if (session.revision != 0 ||
          base64Encode(session.bytes) != original ||
          session.stopRecording().steps.isNotEmpty) {
        throw StateError(
          'Opaque field refusal did not roll back the complete plan',
        );
      }
      final paragraphPlan = _compile('''
Sub Main()
  ActiveDocument.Paragraphs(2).Range.ListFormat.RemoveNumbers wdNumberParagraph
End Sub
''');
      if (!opaqueEnd) {
        session.startRecording('Unbalanced field boundary must not publish');
        for (final validateOnly in [true, false]) {
          try {
            if (validateOnly) {
              await session.validate(paragraphPlan);
            } else {
              await session.run(paragraphPlan);
            }
            throw StateError(
              'Unbalanced field boundary unexpectedly published',
            );
          } on OfficeMacroException catch (error) {
            if (error.code != 'operation_failed' ||
                error.stepIndex != 0 ||
                error.tool != 'docx.removeNumbers') {
              rethrow;
            }
          }
        }
        if (session.revision != 0 ||
            base64Encode(session.bytes) != original ||
            session.stopRecording().steps.isNotEmpty) {
          throw StateError('Unbalanced field refusal changed the document');
        }
        paragraphRefusals++;
        cases++;
        continue;
      }
      await session.run(paragraphPlan);
      if (session.revision != 1) {
        throw StateError('Paragraph removal did not publish once');
      }
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final document = WordDeserializer().readBytes(saved);
        final paragraphs = document.paragraphs.toList();
        if (paragraphs.length != 3 ||
            paragraphs[1].text != 'Selected result' ||
            paragraphs[1].properties.numId != null ||
            !paragraphs[1].properties.numberingSuppressed ||
            paragraphs.first.text != 'First paragraph' ||
            paragraphs.last.text != 'Last paragraph' ||
            jsonEncode(_nativeFieldTokens(saved)) != expectedFields) {
          throw StateError(
            'Paragraph-only removal changed an opaque field span',
          );
        }
        saved = WordSerializer().writeBytes(document);
      }
      paragraphPreservations++;
      cases++;
    }
  }
  return {
    'cases': cases,
    'allModeRollback': true,
    'paragraphModeRefusals': paragraphRefusals,
    'paragraphModePreservations': paragraphPreservations,
    'additionalReopens': 2,
  };
}

int _refusals() {
  const invalid = [
    'ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyBulletDefault 1',
    'ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyNumberDefault 2',
    'ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyNumberDefault True',
    'ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyNumberDefault "0"',
    'ActiveDocument.Paragraphs(1).Range.ListFormat.RemoveNumbers 2',
    'ActiveDocument.Paragraphs(1).Range.ListFormat.RemoveNumbers 0',
    'ActiveDocument.Paragraphs(1).Range.ListFormat.RemoveNumbers False',
    'ActiveDocument.Paragraphs(1).ListFormat.ApplyNumberDefault',
  ];
  for (final statement in invalid) {
    try {
      _compile('Sub Main()\n$statement\nEnd Sub');
      throw StateError('Unsupported list source unexpectedly compiled');
    } on OfficeVbaCompileException {
      // No plan is published for unsupported Word behavior.
    }
  }
  return invalid.length;
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError('Supply exact committed WORD_LISTS_BAS_BASE64 bytes');
  }
  final example = await runWordListExample(utf8.decode(base64Decode(_example)));
  final transitions = await _toggleAndChangeKind();
  await _rollback();
  final guards = await _fieldAndPolicyGuards();
  final opaqueBoundaries = await _opaqueFieldBoundaryGuards();
  print(
    jsonEncode({
      'example': example,
      'toggleAndChangeKind': transitions,
      'lateFailureRollback': true,
      'fieldAndPolicyGuards': guards,
      'opaqueBoundaryGuards': opaqueBoundaries,
      'refusedSources': _refusals(),
    }),
  );
}
