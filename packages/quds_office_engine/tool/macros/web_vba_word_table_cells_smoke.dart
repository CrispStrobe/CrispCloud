import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _example = String.fromEnvironment('WORD_TABLE_BAS_BASE64');
const _project = <int>[0, 7, 42, 128, 255];
const _custom = '<table-proof xmlns="urn:quds:test">retained</table-proof>';
const _macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
const _vbaRelationship =
    'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
const _expected = <String>['Item', 'Quds report', 'Total', '42', 'Prepared ✓'];

OfficeMacro wordTableSource(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordTableReport',
    source: source,
  ),
);

OfficeMacro wordTablePlan(String body) =>
    wordTableSource('Sub Main()\n$body\nEnd Sub');

WmlTable _table(int rows, int columns, String label) => WmlTable(
  grid: List<double>.filled(columns, 120),
  properties: WmlTableProps(cellMargin: 4, borderColor: '1F4E79'),
  rows: [
    for (var row = 0; row < rows; row++)
      WmlTableRow(
        cantSplit: true,
        cells: [
          for (var column = 0; column < columns; column++)
            WmlTableCell(
              width: 120,
              fillColor: 'EAF1F8',
              blocks: [
                WmlParagraph(
                  properties: WmlParagraphProps(
                    justification: WmlJustification.center,
                    spacingAfter: 3,
                  ),
                  inlines: [
                    WmlRun(
                      text: '$label $row/$column',
                      properties: WmlRunProps(
                        bold: true,
                        asciiFont: 'Courier New',
                        fontSizeHalfPoints: 24,
                        color: '1F4E79',
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
  ],
);

Uint8List wordTableInput({bool macroEnabled = true}) {
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(inlines: [WmlRun(text: 'Report introduction')]),
          _table(2, 2, 'first'),
          WmlParagraph(inlines: [WmlRun(text: 'Between tables')]),
        ],
        header: [
          WmlParagraph(inlines: [WmlRun(text: 'Untouched header')]),
        ],
        linkToPrevious: false,
      ),
      WmlSection(
        blocks: [
          WmlParagraph(inlines: [WmlRun(text: 'Second section')]),
          _table(1, 1, 'second'),
          WmlParagraph(inlines: [WmlRun(text: 'Report ending')]),
        ],
      ),
    ],
  );
  final package = OpcPackage.openBytes(WordSerializer().writeBytes(document));
  if (macroEnabled) {
    package.getPart('/word/document.xml')!.contentType = _macroType;
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
          id: 'rIdTableProject',
        );
  }
  package.createPart(
    '/customXml/table.xml',
    'application/xml',
    Uint8List.fromList(utf8.encode(_custom)),
  );
  return package.save();
}

List<WmlTable> _tables(WmlDocument document) => [
  for (final section in document.sections)
    ...section.blocks.whereType<WmlTable>(),
];

List<String> wordTableText(Uint8List bytes) => [
  for (final table in _tables(WordDeserializer().readBytes(bytes)))
    for (final row in table.rows)
      for (final cell in row.cells)
        cell.blocks.whereType<WmlParagraph>().single.text,
];

void assertWordTableOutput(Uint8List bytes, {bool macroEnabled = true}) {
  if (jsonEncode(wordTableText(bytes)) != jsonEncode(_expected)) {
    throw StateError('The table report contains incorrect cell text');
  }
  final document = WordDeserializer().readBytes(bytes);
  final tables = _tables(document);
  if (tables.length != 2 ||
      tables[0].rows.length != 2 ||
      tables[0].rows.any((row) => row.cells.length != 2) ||
      tables[1].rows.length != 1 ||
      tables[1].rows.single.cells.length != 1) {
    throw StateError('The table report changed table structure');
  }
  for (final table in tables) {
    if (table.properties.cellMargin != 4 ||
        table.properties.borderColor != '1F4E79' ||
        table.grid.any((width) => width != 120)) {
      throw StateError('The table report changed table formatting');
    }
    for (final row in table.rows) {
      if (!row.cantSplit) throw StateError('The row pagination flag changed');
      for (final cell in row.cells) {
        final paragraph = cell.blocks.single as WmlParagraph;
        if (cell.width != 120 ||
            cell.fillColor != 'EAF1F8' ||
            paragraph.properties.justification != WmlJustification.center ||
            paragraph.properties.spacingAfter != 3 ||
            paragraph.inlines.whereType<WmlRun>().any(
              (run) =>
                  !run.properties.bold ||
                  run.properties.asciiFont != 'Courier New' ||
                  run.properties.fontSizeHalfPoints != 24 ||
                  run.properties.color != '1F4E79',
            )) {
          throw StateError('The table report changed cell or text formatting');
        }
      }
    }
  }
  final paragraphs = [
    for (final section in document.sections)
      for (final paragraph in section.blocks.whereType<WmlParagraph>())
        paragraph.text,
  ];
  if (jsonEncode(paragraphs) !=
          jsonEncode([
            'Report introduction',
            'Between tables',
            'Second section',
            'Report ending',
          ]) ||
      document.sections.first.header.single.text != 'Untouched header') {
    throw StateError('The table report changed unselected content');
  }
  final package = OpcPackage.openBytes(bytes);
  if (package.getPart('/customXml/table.xml')!.readText() != _custom) {
    throw StateError('The table report changed unrelated custom XML');
  }
  final project = package.getPart('/word/vbaProject.bin');
  if (macroEnabled) {
    final relationship = package
        .relationshipsFor('/word/document.xml')
        .byId('rIdTableProject');
    if (project == null ||
        base64Encode(project.readBytes()) !=
            base64Encode(Uint8List.fromList(_project)) ||
        package.getPart('/word/document.xml')!.contentType != _macroType ||
        relationship?.type != _vbaRelationship ||
        relationship?.target != 'vbaProject.bin') {
      throw StateError('The table report changed the inert VBA project');
    }
  } else if (project != null) {
    throw StateError('A DOCX table report acquired a VBA project');
  }
}

Future<Map<String, Object?>> runWordTableExample(String source) async {
  final input = wordTableInput();
  final plan = wordTableSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validated = await session.validate(plan);
  if (!validated.validatedOnly ||
      session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(input)) {
    throw StateError('Table report validation published changes');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordTableOutput(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  await session.run(plan);
  assertWordTableOutput(session.bytes);

  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word table report');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(recording);
  assertWordTableOutput(replay.bytes);

  final lateFailure = wordTablePlan('''
ActiveDocument.Tables(1).Cell(1, 1).Range.Text = "not published"
ActiveDocument.Tables(2).Cell(2, 1).Range.Text = "missing row"
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
    if (!refused ||
        replay.revision != revision ||
        base64Encode(replay.bytes) != before) {
      throw StateError('A late table-cell failure published partial changes');
    }
  }
  var policyRefusals = 0;
  for (final policy in [
    OfficeMacroPolicy(allowMutation: false),
    OfficeMacroPolicy(allowedTools: {'docx.replaceText'}),
    OfficeMacroPolicy(maxSteps: 4),
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
    if (denied.revision != 0 ||
        base64Encode(denied.bytes) != base64Encode(input)) {
      throw StateError('A refused table report published changes');
    }
  }
  if (policyRefusals != 3) throw StateError('A table report bypassed policy');
  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'opaquePartsPreserved': true,
    'formattingPreserved': true,
    'lateRollback': true,
    'policyRefusals': policyRefusals,
    'text': wordTableText(saved),
  };
}

Future<void> main() async {
  if (_example.isEmpty) throw StateError('Supply WORD_TABLE_BAS_BASE64');
  print(
    jsonEncode(await runWordTableExample(utf8.decode(base64Decode(_example)))),
  );
}
