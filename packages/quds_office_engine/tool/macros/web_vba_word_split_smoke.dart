import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_table_cells_smoke.dart' as fixture;

// Supply the complete checked-in example to both the VM and JavaScript build.
const _example = String.fromEnvironment('WORD_SPLIT_BAS_BASE64');
const _signature = <int>[73, 0, 19, 128, 255];
const _signatureRelationship =
    'http://schemas.microsoft.com/office/2006/relationships/vbaProjectSignature';

OfficeMacro wordSplitSource(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordSplitReport',
    source: source,
  ),
);

OfficeMacro wordSplitPlan(String body) =>
    wordSplitSource('Option Explicit\nSub Main()\n$body\nEnd Sub');

List<WmlTable> _tables(WmlDocument document) => [
  for (final section in document.sections)
    ...section.blocks.whereType<WmlTable>(),
];

/// A formatted 2x2 report, an untouched second table, body/story neighbors and
/// opaque custom content. Only DOCM has an inert project and signature payload.
Uint8List wordSplitInput({bool macroEnabled = true}) {
  final document = WordDeserializer().readBytes(
    fixture.wordTableInput(macroEnabled: macroEnabled),
  );
  for (final row in _tables(document).first.rows) {
    for (final cell in row.cells) {
      final paragraph = cell.blocks.single as WmlParagraph;
      for (final run in paragraph.inlines.whereType<WmlRun>()) {
        run.properties.bold = false;
      }
    }
  }
  final package = OpcPackage.openBytes(WordSerializer().writeBytes(document));
  if (macroEnabled) {
    package.createPart(
      '/word/vbaProjectSignature.bin',
      'application/octet-stream',
      Uint8List.fromList(_signature),
    );
    package
        .relationshipsFor('/word/vbaProject.bin')
        .add(
          type: _signatureRelationship,
          target: 'vbaProjectSignature.bin',
          id: 'rIdSplitSignature',
        );
  }
  return package.save();
}

Map<String, Object?> _paragraph(WmlParagraph paragraph) => {
  'text': paragraph.text,
  'alignment': paragraph.properties.justification.name,
  'before': paragraph.properties.spacingBefore,
  'after': paragraph.properties.spacingAfter,
  'runs': [
    for (final run in paragraph.inlines.whereType<WmlRun>())
      {
        'text': run.text,
        'font': run.properties.asciiFont,
        'size': run.properties.fontSizeHalfPoints,
        'bold': run.properties.bold,
        'italic': run.properties.italic,
        'color': run.properties.color,
      },
  ],
};

Map<String, Object?> wordSplitState(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  final tables = _tables(document);
  return {
    'body': [
      for (final section in document.sections)
        for (final paragraph in section.blocks.whereType<WmlParagraph>())
          _paragraph(paragraph),
    ],
    'stories': [
      for (final section in document.sections)
        for (final story in [
          section.header,
          section.footer,
          section.firstHeader,
          section.firstFooter,
          section.evenHeader,
          section.evenFooter,
        ])
          [for (final paragraph in story) _paragraph(paragraph)],
    ],
    'tables': [
      for (final table in tables)
        {
          'grid': table.grid.map((width) => width.toInt()).toList(),
          'margin': table.properties.cellMargin,
          'border': table.properties.borderColor,
          'rows': [
            for (final row in table.rows)
              {
                'cantSplit': row.cantSplit,
                'cells': [
                  for (final cell in row.cells)
                    {
                      'width': cell.width,
                      'fill': cell.fillColor,
                      'span': cell.gridSpan,
                      'paragraph': _paragraph(
                        cell.blocks.single as WmlParagraph,
                      ),
                    },
                ],
              },
          ],
        },
    ],
  };
}

const wordSplitExpectedSteps = <Map<String, Object?>>[
  {
    'tool': 'docx.tableCellRangeText',
    'arguments': {'table': 0, 'row': 0, 'column': 0, 'text': 'Item'},
  },
  {
    'tool': 'docx.runFormat',
    'arguments': {
      'paragraph': 0,
      'story': 'tableCell',
      'table': 0,
      'row': 0,
      'column': 0,
      'bold': true,
    },
  },
  {
    'tool': 'docx.tableCellRangeText',
    'arguments': {'table': 0, 'row': 0, 'column': 1, 'text': 'Status'},
  },
  {
    'tool': 'docx.runFormat',
    'arguments': {
      'paragraph': 0,
      'story': 'tableCell',
      'table': 0,
      'row': 0,
      'column': 1,
      'bold': true,
    },
  },
  {
    'tool': 'docx.tableCellRangeText',
    'arguments': {
      'table': 0,
      'row': 1,
      'column': 0,
      'text': 'Quarterly report',
    },
  },
  {
    'tool': 'docx.tableCellRangeText',
    'arguments': {'table': 0, 'row': 1, 'column': 1, 'text': 'Ready'},
  },
  {
    'tool': 'docx.runFormat',
    'arguments': {
      'paragraph': 0,
      'story': 'tableCell',
      'table': 0,
      'row': 1,
      'column': 1,
      'color': '008000',
    },
  },
];

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void assertWordSplitPlan(OfficeMacro plan) {
  _check(
    plan.steps.length == 7,
    'Split report must produce seven native edits',
  );
  for (var index = 0; index < wordSplitExpectedSteps.length; index++) {
    final expected = wordSplitExpectedSteps[index];
    final arguments = expected['arguments']! as Map<String, Object?>;
    final step = plan.steps[index];
    _check(
      step.tool == expected['tool'] &&
          step.arguments.length == arguments.length &&
          arguments.entries.every(
            (entry) => step.arguments[entry.key] == entry.value,
          ),
      'Unexpected Split report operation at index $index',
    );
  }
}

void assertWordSplitOutput(Uint8List bytes, Uint8List input) {
  final expected = wordSplitState(input);
  final tables = expected['tables']! as List<Object?>;
  final rows =
      (tables.first! as Map<String, Object?>)['rows']! as List<Object?>;
  const texts = ['Item', 'Status', 'Quarterly report', 'Ready'];
  for (var row = 0; row < 2; row++) {
    final cells =
        (rows[row]! as Map<String, Object?>)['cells']! as List<Object?>;
    for (var column = 0; column < 2; column++) {
      final paragraph =
          (cells[column]! as Map<String, Object?>)['paragraph']!
              as Map<String, Object?>;
      final text = texts[row * 2 + column];
      paragraph['text'] = text;
      final run =
          (paragraph['runs']! as List<Object?>).single! as Map<String, Object?>;
      run['text'] = text;
      run['bold'] = row == 0;
      if (row == 1 && column == 1) run['color'] = '008000';
    }
  }
  _check(
    jsonEncode(wordSplitState(bytes)) == jsonEncode(expected),
    'Split report text, formatting or unselected document content changed',
  );
  final originalPackage = OpcPackage.openBytes(input);
  final package = OpcPackage.openBytes(bytes);
  for (final path in [
    '/word/vbaProject.bin',
    '/word/vbaProjectSignature.bin',
    '/word/_rels/vbaProject.bin.rels',
    '/customXml/table.xml',
  ]) {
    final original = originalPackage.getPart(path);
    final saved = package.getPart(path);
    _check(
      original == null
          ? saved == null
          : saved != null &&
                saved.contentType == original.contentType &&
                base64Encode(saved.readBytes()) ==
                    base64Encode(original.readBytes()),
      'Split report changed or created the opaque part $path',
    );
  }
  _check(
    package.getPart('/word/document.xml')!.contentType ==
        originalPackage.getPart('/word/document.xml')!.contentType,
    'Split report changed DOCX/DOCM document type',
  );
}

Map<String, Object?> _structured(Map<String, Object?> response) =>
    response['structuredContent']! as Map<String, Object?>;

Future<Map<String, Object?>> runWordSplitExample(
  String source, {
  bool macroEnabled = true,
}) async {
  final input = wordSplitInput(macroEnabled: macroEnabled);
  final original = base64Encode(input);
  final plan = wordSplitSource(source);
  assertWordSplitPlan(plan);
  final guard = (await WordPackagePreservation.capture(
    input,
    macroEnabled ? 'split-report.docm' : 'split-report.docx',
  ))!;
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final preview = await session.validate(plan);
  _check(
    preview.validatedOnly &&
        preview.completedSteps == 7 &&
        session.revision == 0 &&
        base64Encode(session.bytes) == original,
    'Detached Split validation published a document change',
  );
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  _check(
    result.completedSteps == 7 && session.revision == 1,
    'Split report did not publish one complete transaction',
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordSplitOutput(saved, input);
    await guard.validateSaved(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }

  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx)
    ..startRecording('Delimited Word table');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(recording);
  assertWordSplitOutput(recorder.bytes, input);
  assertWordSplitOutput(replay.bytes, input);
  _check(
    recording.steps.length == 7,
    'Split native recording lost an operation',
  );

  final mcpSession = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final mcp = OfficeMacroMcp(mcpSession);
  final compilation = await mcp.callTool('office_macro_compile', {
    'source': {
      'language': 'vba-word',
      'format': 'docx',
      'moduleName': 'WordSplitReport',
      'source': source,
    },
  });
  _check(compilation['isError'] == false, 'MCP could not compile Split report');
  final arguments = {'macro': _structured(compilation)['macro']};
  final validation = await mcp.callTool('office_macro_validate', arguments);
  _check(
    validation['isError'] == false &&
        _structured(validation)['completedSteps'] == 7 &&
        mcpSession.revision == 0 &&
        base64Encode(mcpSession.bytes) == original,
    'MCP Split compilation/validation mutated its input',
  );
  final execution = await mcp.callTool('office_macro_run', arguments);
  _check(
    execution['isError'] == false &&
        _structured(execution)['completedSteps'] == 7 &&
        mcpSession.revision == 1,
    'MCP Split report did not publish exactly once',
  );
  assertWordSplitOutput(mcpSession.bytes, input);
  await guard.validateSaved(mcpSession.bytes);

  await session.run(plan);
  assertWordSplitOutput(session.bytes, input);
  _check(
    base64Encode(input) == original,
    'Split report mutated caller input bytes',
  );
  return {
    'language': 'vba-word',
    'format': macroEnabled ? 'docm' : 'docx',
    'operations': plan.steps.length,
    'firstRunRevision': result.revision,
    'repeatedRevision': session.revision,
    'additionalReopens': 2,
    'recordedSteps': recording.steps.length,
    'immutableValidation': true,
    'opaquePartsPreserved': true,
    'nativeRecordingAndReplay': true,
    'mcpCompileValidateRun': true,
    'state': wordSplitState(saved),
  };
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError('Supply WORD_SPLIT_BAS_BASE64 from the BAS file');
  }
  final source = utf8.decode(base64Decode(_example));
  print(
    jsonEncode({
      for (final macroEnabled in [false, true])
        macroEnabled ? 'docm' : 'docx': await runWordSplitExample(
          source,
          macroEnabled: macroEnabled,
        ),
    }),
  );
}
