import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// Feed the identical committed BAS bytes to the Dart VM and compiled JS.
const _example = String.fromEnvironment('WORD_NAMED_MEASUREMENTS_BAS_BASE64');
const _w = OfficeNamespaces.w;
const _extension = 'urn:measurement-example';
const _macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
const _projectType = 'application/vnd.ms-office.vbaProject';
const _projectRelationship =
    'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
const _projectBytes = [0, 42, 127, 128, 255, 10];
const _signatureBytes = [19, 18, 17, 0, 255];

OfficeMacro wordMeasurementSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'Measurements',
        source: source,
      ),
    );

OfficeMacro wordMeasurementPlan(String body) =>
    wordMeasurementSource('Sub Main()\n$body\nEnd Sub');

/// Imported DOCM: rich text, native styles, an empty paragraph, extension data
/// and opaque VBA/signature parts exercise the existing native write contract.
/// Native indentation writes update their owned geometry while retaining
/// unrelated extension attributes, including the adversarial x:token.
Uint8List wordMeasurementInput() {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package.getPart('/word/document.xml')!
    ..writeText('''
<w:document xmlns:w="$_w" xmlns:x="$_extension"><w:body>
<w:p><w:pPr><w:pStyle w:val="Layout"/><w:keepLines/><w:jc w:val="right"/>
<w:ind w:left="240" w:right="160" w:firstLine="60" x:token="indent"/>
<w:spacing w:before="120" w:after="180" w:line="300" w:lineRule="exact"
x:token="spacing"/><x:custom x:value="preserved"/></w:pPr>
<w:r><w:rPr><w:b/></w:rPr><w:t>Measured paragraph</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="Layout"/></w:pPr></w:p>
<w:p><w:pPr><w:keepNext/><w:spacing w:before="40" w:after="80"/></w:pPr>
<w:r><w:rPr><w:i/></w:rPr><w:t>Untouched paragraph</w:t></w:r></w:p>
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
        id: 'rIdMeasurementProject',
      );
  package
      .relationshipsFor('/word/vbaProject.bin')
      .add(
        type: '${_projectRelationship}Signature',
        target: 'vbaProjectSignature.bin',
        id: 'rIdMeasurementSignature',
      );
  return package.save();
}

XmlElement wordMeasurementProperties(Uint8List bytes, int index) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .childrenNamed('p', namespaceUri: _w)
        .elementAt(index)
        .firstChild('pPr', namespaceUri: _w)!;

num _reportNumber(double value) =>
    value == value.truncateToDouble() ? value.toInt() : value;

List<Map<String, Object?>> wordMeasurementState(Uint8List bytes) => [
  for (final paragraph in WordDeserializer().readBytes(bytes).paragraphs)
    {
      'text': paragraph.text,
      'left': _reportNumber(paragraph.properties.indent.left),
      'right': _reportNumber(paragraph.properties.indent.right),
      'firstLine': _reportNumber(paragraph.properties.indent.firstLine),
      'hanging': _reportNumber(paragraph.properties.indent.hanging),
      'before': _reportNumber(paragraph.properties.spacingBefore),
      'after': _reportNumber(paragraph.properties.spacingAfter),
      'line': _reportNumber(paragraph.properties.lineSpacing),
      'rule': paragraph.properties.lineSpacingRule.name,
      'tabs': [
        for (final tab in paragraph.properties.tabs)
          [_reportNumber(tab.position), tab.alignment.name, tab.leader.name],
      ],
    },
];

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

// Native saving may normalize XML whitespace/declarations. Compare the style
// tree's names, values and child order rather than claiming lexical identity.
List<Object> _xmlState(XmlElement element) {
  final attributes = [
    for (final attribute in element.attributes)
      if (attribute.prefix != 'xmlns' && attribute.qualifiedName != 'xmlns')
        jsonEncode([
          attribute.namespaceUri,
          attribute.localName,
          attribute.value,
        ]),
  ]..sort();
  return [
    element.namespaceUri,
    element.localName,
    attributes,
    [
      for (final child in element.children)
        if (child is XmlElement)
          _xmlState(child)
        else if (child is XmlText && child.text.trim().isNotEmpty)
          child.text,
    ],
  ];
}

void _checkPlan(OfficeMacro plan) {
  // Literal expected outputs are independent of the conversion implementation.
  const expected = <(String, Map<String, Object?>)>[
    ('docx.paragraphFormat', {'paragraph': 0, 'left': 36.0}),
    ('docx.paragraphFormat', {'paragraph': 0, 'right': 36.0}),
    ('docx.paragraphFormat', {'paragraph': 0, 'firstLine': 0, 'hanging': 18.0}),
    ('docx.paragraphFormat', {'paragraph': 0, 'before': 9.0}),
    ('docx.paragraphFormat', {'paragraph': 0, 'after': 6.0}),
    ('docx.lineSpacing', {'paragraph': 0, 'rule': 'exact', 'points': 13.8}),
    ('docx.clearTabStops', {'paragraph': 0}),
    (
      'docx.tabStop',
      {
        'paragraph': 0,
        'position': 72.0,
        'alignment': 'center',
        'leader': 'dot',
      },
    ),
    ('docx.paragraphFormat', {'paragraph': 1, 'left': 72.0}),
    ('docx.paragraphFormat', {'paragraph': 1, 'right': 72.0}),
    ('docx.paragraphFormat', {'paragraph': 1, 'before': 72.0}),
    ('docx.paragraphFormat', {'paragraph': 1, 'after': 72.0}),
    ('docx.lineSpacing', {'paragraph': 1, 'rule': 'multiple', 'points': 13.8}),
  ];
  _check(plan.steps.length == expected.length, 'Wrong example operation count');
  for (var index = 0; index < expected.length; index++) {
    final (tool, arguments) = expected[index];
    final actual = plan.steps[index];
    _check(
      actual.tool == tool &&
          actual.arguments.length == arguments.length &&
          arguments.entries.every(
            (entry) => actual.arguments[entry.key] == entry.value,
          ),
      'Measurement example step $index differs from the expected plan',
    );
  }
}

/// Checks both native storage and model projection without recomputing ratios.
void checkWordMeasurementExample(Uint8List bytes, Uint8List original) {
  final states = wordMeasurementState(bytes);
  const first = <String, Object?>{
    'text': 'Measured paragraph',
    'left': 36,
    'right': 36,
    'firstLine': 0,
    'hanging': 18,
    'before': 9,
    'after': 6,
    'line': 13.8,
    'rule': 'exact',
    'tabs': [
      [72, 'center', 'dot'],
    ],
  };
  const second = <String, Object?>{
    'text': '',
    'left': 72,
    'right': 72,
    'firstLine': 0,
    'hanging': 0,
    'before': 72,
    'after': 72,
    'line': 1.15,
    'rule': 'auto',
    'tabs': <Object>[],
  };
  _check(
    states.length == 3 &&
        jsonEncode(states[0]) == jsonEncode(first) &&
        jsonEncode(states[1]) == jsonEncode(second) &&
        jsonEncode(states[2]) == jsonEncode(wordMeasurementState(original)[2]),
    'Unexpected measured or unselected paragraph state: $states',
  );
  _check(
    jsonEncode(_xmlState(wordMeasurementProperties(bytes, 2))) ==
        jsonEncode(_xmlState(wordMeasurementProperties(original, 2))),
    'Measurement writes changed the untouched native paragraph properties',
  );
  final firstProperties = wordMeasurementProperties(bytes, 0);
  final indent = firstProperties.firstChild('ind', namespaceUri: _w)!;
  final spacing = firstProperties.firstChild('spacing', namespaceUri: _w)!;
  for (final (element, key, value) in [
    (indent, 'left', '720'),
    (indent, 'right', '720'),
    (indent, 'hanging', '360'),
    (spacing, 'before', '180'),
    (spacing, 'after', '120'),
    (spacing, 'line', '276'),
    (spacing, 'lineRule', 'exact'),
  ]) {
    _check(
      element.getAttribute(key, namespaceUri: _w) == value,
      'Wrong native measurement $key',
    );
  }
  final document = WordDeserializer().readBytes(bytes);
  // Explicit formatting owns the modeled indent geometry. The sparse native
  // writer preserves unrelated extension attributes in the same property.
  _check(
    indent.getAttribute('token', namespaceUri: _extension) == 'indent',
    'Measurement writes changed unrelated indentation extension metadata',
  );
  _check(
    spacing.getAttribute('token', namespaceUri: _extension) == 'spacing' &&
        firstProperties
                .firstChild('custom', namespaceUri: _extension)!
                .getAttribute('value', namespaceUri: _extension) ==
            'preserved' &&
        document.paragraphs.first.properties.keepTogether &&
        document.paragraphs.first.properties.justification ==
            WmlJustification.right &&
        document.paragraphs.first.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .bold &&
        document.paragraphs.last.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .italic,
    'Measurement writes changed unrelated formatting or extension XML',
  );
  final package = OpcPackage.openBytes(bytes);
  final sourcePackage = OpcPackage.openBytes(original);
  _check(
    jsonEncode(
          _xmlState(
            XmlDocument.parse(
              package.getPart('/word/styles.xml')!.readText(),
            ).root!,
          ),
        ) ==
        jsonEncode(
          _xmlState(
            XmlDocument.parse(
              sourcePackage.getPart('/word/styles.xml')!.readText(),
            ).root!,
          ),
        ),
    'Measurement writes changed the native style tree',
  );
  for (final path in [
    '/word/vbaProject.bin',
    '/word/vbaProjectSignature.bin',
  ]) {
    _check(
      base64Encode(package.getPart(path)!.readBytes()) ==
          base64Encode(sourcePackage.getPart(path)!.readBytes()),
      'Measurement writes changed preserved part $path',
    );
  }
}

Future<Map<String, Object?>> runWordMeasurementExample(String source) async {
  final input = wordMeasurementInput();
  final original = base64Encode(input);
  final guard = (await WordPackagePreservation.capture(input, 'layout.docm'))!;
  final plan = wordMeasurementSource(source);
  _checkPlan(plan);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == 13 &&
        session.revision == 0 &&
        base64Encode(session.bytes) == original,
    'Validation published a layout change',
  );
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  _check(
    result.completedSteps == 13 &&
        result.revision == 1 &&
        !result.validatedOnly &&
        base64Encode(input) == original,
    'Example did not publish one detached transaction',
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    checkWordMeasurementExample(saved, input);
    await guard.validateSaved(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  await session.run(plan);
  checkWordMeasurementExample(session.bytes, input);
  return {
    'operations': 13,
    'revisionAfterReplay': session.revision,
    'additionalReopens': 2,
    'opaqueVbaPreserved': true,
    'nativeIndentGeometryReplaced': true,
    'nativeIndentExtensionsPreserved': true,
    'paragraphs': wordMeasurementState(saved),
  };
}

Future<void> _refuse(
  OfficeMacro plan, {
  required String code,
  OfficeMacroPolicy? policy,
  int? stepIndex,
}) async {
  final input = wordMeasurementInput();
  final session = OfficeMacroSession(
    input,
    format: OfficeMacroFormat.docx,
    policy: policy,
  );
  for (final action in [session.validate, session.run]) {
    try {
      await action(plan);
      throw StateError('Invalid measured plan unexpectedly succeeded');
    } on OfficeMacroException catch (error) {
      if (error.code != code ||
          (stepIndex != null && error.stepIndex != stepIndex)) {
        rethrow;
      }
    }
    _check(
      session.revision == 0 &&
          base64Encode(session.bytes) == base64Encode(input),
      'Rejected measured plan published a partial edit',
    );
  }
}

Future<Map<String, Object?>> runWordMeasurementGuards() async {
  const target = 'ActiveDocument.Paragraphs(1).Format';
  final plan = wordMeasurementPlan('''
$target.LeftIndent = InchesToPoints(0.5)
$target.LineSpacingRule = wdLineSpaceExactly
$target.LineSpacing = PicasToPoints(1.15)
''');
  for (final (policy, code) in <(OfficeMacroPolicy, String)>[
    (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
    (
      OfficeMacroPolicy(allowedTools: {'docx.paragraphFormat'}),
      'permission_denied',
    ),
    (OfficeMacroPolicy(maxSteps: 1), 'limit_exceeded'),
  ]) {
    await _refuse(plan, policy: policy, code: code);
  }
  final session = OfficeMacroSession(
    wordMeasurementInput(),
    format: OfficeMacroFormat.docx,
    policy: OfficeMacroPolicy(
      allowedTools: {'docx.paragraphFormat', 'docx.lineSpacing'},
      maxSteps: 2,
    ),
  );
  await session.run(plan);
  _check(session.revision == 1, 'Complete allowlist did not admit the plan');
  await _refuse(
    wordMeasurementPlan('''
$target.LeftIndent = CentimetersToPoints(1.27)
ActiveDocument.Paragraphs(99).Format.RightIndent = MillimetersToPoints(12.7)
'''),
    code: 'operation_failed',
    stepIndex: 1,
  );
  return {
    'refusedPolicies': 3,
    'completeAllowlistRevision': 1,
    'lateFailureStep': 1,
    'validateAndRunRollback': true,
  };
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError(
      'Supply exact committed WORD_NAMED_MEASUREMENTS_BAS_BASE64 bytes',
    );
  }
  final source = utf8.decode(base64Decode(_example));
  print(
    jsonEncode({
      'example': await runWordMeasurementExample(source),
      'guards': await runWordMeasurementGuards(),
    }),
  );
}
