import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _example = String.fromEnvironment('WORD_COMPARISON_COLORS_BAS_BASE64');
const _w = OfficeNamespaces.w;
const _extension = 'urn:word-comparison-colors';
const _project = <int>[0, 7, 42, 128, 255];
const _custom = '<comparison xmlns="$_extension">preserved</comparison>';
const _macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
const _vbaRelationship =
    'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
const _colors = ['008000', '800000', 'auto', '000080', 'auto'];

OfficeMacro wordComparisonColorsSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordComparisonColors',
        source: source,
      ),
    );

OfficeMacro wordComparisonColorsPlan(String body) =>
    wordComparisonColorsSource('Sub Main()\n$body\nEnd Sub');

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

WmlParagraph _paragraph(String text) => WmlParagraph(
  properties: WmlParagraphProps(spacingAfter: 9),
  inlines: [
    WmlRun(
      text: text,
      properties: WmlRunProps(
        bold: true,
        asciiFont: 'Courier New',
        fontSizeHalfPoints: 24,
        color: '2468AC',
        proofingLanguage: 'de-DE',
      ),
    ),
  ],
);

/// The template keeps selected stories independent and includes ordinary cell
/// text, multiple text runs, native theme color metadata and inert DOCM parts.
Uint8List wordComparisonColorsInput({bool macroEnabled = true}) {
  final first = _paragraph('Ready — Straße 😀');
  first.inlines.add(
    WmlRun(
      text: ' العربية',
      properties: WmlRunProps(
        italic: true,
        asciiFont: 'Arial',
        fontSizeHalfPoints: 22,
        color: '112233',
      ),
    ),
  );
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          first,
          _paragraph('Review — Résumé'),
          _paragraph('Automatic status'),
          WmlTable(
            grid: [120, 120],
            properties: WmlTableProps(cellMargin: 4, borderColor: '1F4E79'),
            rows: [
              WmlTableRow(
                cantSplit: true,
                cells: [
                  for (final label in ['Equality', 'Ordering'])
                    WmlTableCell(
                      width: 120,
                      fillColor: 'EAF1F8',
                      blocks: [_paragraph(label)],
                    ),
                ],
              ),
            ],
          ),
        ],
        header: [_paragraph('Report header')],
        footer: [_paragraph('Report footer')],
        linkToPrevious: false,
      ),
    ],
  );
  final package = OpcPackage.openBytes(WordSerializer().writeBytes(document));
  final main = package.getPart('/word/document.xml')!;
  const initial = '<w:color w:val="2468AC"/>';
  _check(main.readText().contains(initial), 'Missing native color fixture');
  main.writeText(
    main.readText().replaceFirst(
      initial,
      '<w:color w:val="2468AC" w:themeColor="accent1" '
      'w:themeTint="33" w:themeShade="CC" xmlns:x="$_extension" '
      'x:val="foreign-value" x:token="preserve">'
      '<x:metadata x:token="nested"/></w:color>',
    ),
  );
  if (macroEnabled) {
    main.contentType = _macroType;
    package.contentTypes.setOverride('/word/document.xml', _macroType);
    package.createPart(
      '/word/vbaProject.bin',
      'application/vnd.ms-office.vbaProject',
      Uint8List.fromList(_project),
    );
    package
        .relationshipsFor('/word/document.xml')
        .add(
          type: _vbaRelationship,
          target: 'vbaProject.bin',
          id: 'rIdComparisonProject',
        );
  }
  package.createPart(
    '/customXml/comparison.xml',
    'application/xml',
    Uint8List.fromList(utf8.encode(_custom)),
  );
  return package.save();
}

List<WmlParagraph> _paragraphs(WmlDocument document) => [
  ...document.sections.single.blocks.whereType<WmlParagraph>(),
  ...document.sections.single.header,
  ...document.sections.single.footer,
];

Map<String, Object?> _paragraphState(
  WmlParagraph paragraph, {
  bool includeColor = true,
}) => {
  'text': paragraph.text,
  'spacingAfter': paragraph.properties.spacingAfter,
  'alignment': paragraph.properties.justification.name,
  'runs': [
    for (final run in paragraph.inlines.whereType<WmlRun>())
      {
        'text': run.text,
        'bold': run.properties.bold,
        'italic': run.properties.italic,
        'font': run.properties.asciiFont,
        'size': run.properties.fontSizeHalfPoints,
        'language': run.properties.proofingLanguage,
        if (includeColor) 'color': run.properties.color,
      },
  ],
};

List<Map<String, Object?>> wordComparisonColorsState(Uint8List bytes) => [
  for (final paragraph in _paragraphs(WordDeserializer().readBytes(bytes)))
    _paragraphState(paragraph),
];

List<String> wordComparisonCellText(Uint8List bytes) => [
  for (final row
      in WordDeserializer()
          .readBytes(bytes)
          .sections
          .single
          .blocks
          .whereType<WmlTable>()
          .single
          .rows)
    for (final cell in row.cells) (cell.blocks.single as WmlParagraph).text,
];

void assertWordComparisonColorsOutput(
  Uint8List bytes, {
  bool macroEnabled = true,
}) {
  final document = WordDeserializer().readBytes(bytes);
  final paragraphs = _paragraphs(document);
  _check(
    paragraphs.length == 5,
    'The report changed paragraph/story ownership',
  );
  final original = WordDeserializer().readBytes(
    wordComparisonColorsInput(macroEnabled: macroEnabled),
  );
  _check(
    jsonEncode([
          for (final paragraph in paragraphs)
            _paragraphState(paragraph, includeColor: false),
        ]) ==
        jsonEncode([
          for (final paragraph in _paragraphs(original))
            _paragraphState(paragraph, includeColor: false),
        ]),
    'Font colors changed text, run boundaries or unrelated formatting',
  );
  for (var index = 0; index < paragraphs.length; index++) {
    _check(
      paragraphs[index].inlines.whereType<WmlRun>().every(
        (run) => run.properties.color == _colors[index],
      ),
      'Wrong color on report paragraph/story $index',
    );
  }
  _check(
    jsonEncode(wordComparisonCellText(bytes)) == jsonEncode(['0', '-1']),
    'StrComp did not produce the expected table result',
  );
  final table = document.sections.single.blocks.whereType<WmlTable>().single;
  _check(
    table.rows.length == 1 &&
        table.rows.single.cells.length == 2 &&
        table.rows.single.cantSplit &&
        jsonEncode(table.grid) == jsonEncode([120.0, 120.0]) &&
        table.properties.cellMargin == 4 &&
        table.properties.borderColor == '1F4E79',
    'Comparison output changed table geometry',
  );
  for (final cell in table.rows.single.cells) {
    final paragraph = cell.blocks.single as WmlParagraph;
    _check(
      cell.width == 120 &&
          cell.fillColor == 'EAF1F8' &&
          paragraph.properties.spacingAfter == 9 &&
          paragraph.inlines.whereType<WmlRun>().every(
            (run) =>
                run.properties.bold &&
                run.properties.color == '2468AC' &&
                run.properties.asciiFont == 'Courier New' &&
                run.properties.fontSizeHalfPoints == 24,
          ),
      'Comparison output changed cell formatting',
    );
  }
  final package = OpcPackage.openBytes(bytes);
  final main = package.getPart('/word/document.xml')!;
  final root = XmlDocument.parse(main.readText()).root!;
  final color = root
      .firstChild('body', namespaceUri: _w)!
      .firstChild('p', namespaceUri: _w)!
      .firstChild('r', namespaceUri: _w)!
      .firstChild('rPr', namespaceUri: _w)!
      .firstChild('color', namespaceUri: _w)!;
  _check(
    color.getAttribute('val', namespaceUri: _w) == '008000' &&
        color.getAttribute('themeColor', namespaceUri: _w) == null &&
        color.getAttribute('themeTint', namespaceUri: _w) == null &&
        color.getAttribute('themeShade', namespaceUri: _w) == null &&
        color.getAttribute('val', namespaceUri: _extension) ==
            'foreign-value' &&
        color.getAttribute('token', namespaceUri: _extension) == 'preserve' &&
        color
                .firstChild('metadata', namespaceUri: _extension)
                ?.getAttribute('token', namespaceUri: _extension) ==
            'nested',
    'Explicit font color lost metadata or retained a competing theme: '
    '${XmlDocument(root: color.copy()).toXmlString()}',
  );
  _check(
    main.readText().contains('w:val="auto"') &&
        package.getPart('/customXml/comparison.xml')!.readText() == _custom,
    'Automatic foreground or unrelated custom XML was lost',
  );
  final project = package.getPart('/word/vbaProject.bin');
  if (macroEnabled) {
    final relationship = package
        .relationshipsFor('/word/document.xml')
        .byId('rIdComparisonProject');
    _check(
      project != null &&
          base64Encode(project.readBytes()) == base64Encode(_project) &&
          main.contentType == _macroType &&
          relationship?.type == _vbaRelationship &&
          relationship?.target == 'vbaProject.bin',
      'The report changed its inert embedded VBA project',
    );
  } else {
    _check(project == null, 'The DOCX report acquired a VBA project');
  }
}

Future<Map<String, Object?>> runWordComparisonColorsExample(
  String source,
) async {
  final input = wordComparisonColorsInput();
  final plan = wordComparisonColorsSource(source);
  _check(plan.steps.length == 9, 'Expected nine comparison/color operations');
  _check(
    jsonEncode([
          for (final step in plan.steps.where(
            (step) => step.tool == 'docx.runFormat',
          ))
            step.arguments['color'],
        ]) ==
        jsonEncode([
          '008000',
          '800000',
          '0000FF',
          'auto',
          '000080',
          'FF0000',
          'auto',
        ]),
    'Comparison branches or palette/automatic color plans are incorrect',
  );
  final guard = (await WordPackagePreservation.capture(input, 'report.docm'))!;
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Playback must not record itself');
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == 9 &&
        session.revision == 0 &&
        base64Encode(session.bytes) == base64Encode(input),
    'Detached comparison/color validation published changes',
  );
  await session.run(OfficeMacro.parse(plan.encode()));
  _check(
    session.revision == 1 && session.stopRecording().steps.isEmpty,
    'The report did not publish one transaction or recorded its own playback',
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordComparisonColorsOutput(saved);
    await guard.validateSaved(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  await session.run(plan);
  assertWordComparisonColorsOutput(session.bytes);
  _check(session.revision == 2, 'Repeated report did not retain its revision');

  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word comparison/color native operations');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  _check(recording.steps.length == 9, 'Native report edits were not recorded');
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recording.encode()));
  assertWordComparisonColorsOutput(replay.bytes);

  final lateFailure = wordComparisonColorsPlan('''
ActiveDocument.Paragraphs(1).Range.Font.ColorIndex = wdBlue
ActiveDocument.Tables(1).Cell(2, 1).Range.Text = "missing row"
''');
  for (final action in [replay.validate, replay.run]) {
    final before = base64Encode(replay.bytes);
    final revision = replay.revision;
    var refused = false;
    try {
      await action(lateFailure);
    } on OfficeMacroException catch (error) {
      refused = error.stepIndex == 1;
    }
    _check(
      refused &&
          replay.revision == revision &&
          base64Encode(replay.bytes) == before,
      'A later missing cell published earlier font changes',
    );
  }
  var policyRefusals = 0;
  for (final policy in [
    OfficeMacroPolicy(allowMutation: false),
    OfficeMacroPolicy(allowedTools: {'docx.tableCellRangeText'}),
    OfficeMacroPolicy(maxSteps: 8),
  ]) {
    final denied = OfficeMacroSession(
      input,
      format: OfficeMacroFormat.docx,
      policy: policy,
    );
    try {
      await denied.run(plan);
    } on OfficeMacroException {
      policyRefusals++;
    }
    _check(
      denied.revision == 0 && base64Encode(denied.bytes) == base64Encode(input),
      'A refused report bypassed atomic policy validation',
    );
  }
  _check(policyRefusals == 3, 'A report policy was bypassed');
  final package = OpcPackage.openBytes(saved);
  final nativeParts =
      package.parts
          .where(
            (part) =>
                part.uri == '/word/document.xml' ||
                part.uri.startsWith('/word/header') ||
                part.uri.startsWith('/word/footer'),
          )
          .map((part) => part.uri)
          .toList()
        ..sort();
  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'opaquePartsPreserved': true,
    'colorMetadataPreserved': true,
    'lateRollback': true,
    'policyRefusals': policyRefusals,
    'colors': _colors,
    'cellText': wordComparisonCellText(saved),
    'nativePartSha256': {
      for (final uri in nativeParts)
        uri: sha256.convert(package.getPart(uri)!.readBytes()).toString(),
    },
  };
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError('Supply WORD_COMPARISON_COLORS_BAS_BASE64');
  }
  print(
    jsonEncode(
      await runWordComparisonColorsExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
