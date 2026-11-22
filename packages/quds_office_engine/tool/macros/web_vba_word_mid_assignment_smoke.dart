import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_cell_paragraphs_smoke.dart' as fixture;
import 'web_vba_word_cell_prefix_smoke.dart' as prefix;

const _example = String.fromEnvironment('WORD_MID_ASSIGNMENT_BAS_BASE64');
const _expectedText = <String>[
  'Item: Widget',
  'State: Ready  ',
  'Code: 0042',
  'OPEN/DONE',
  'second 0/0',
];

OfficeMacro wordMidAssignmentSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordMidAssignment',
        source: source,
      ),
    );

OfficeMacro wordMidAssignmentPlan(String body) =>
    wordMidAssignmentSource('Option Explicit\nSub Main()\n$body\nEnd Sub');

/// A 2x2 table plus an untouched 1x1 table, rich text, an empty cell, native
/// and foreign paragraph properties, headers, custom XML and optional inert
/// VBA. The fixture has already undergone an ordinary preservation-baseline save.
Uint8List wordMidAssignmentInput({bool macroEnabled = true}) =>
    prefix.wordCellPrefixInput(macroEnabled: macroEnabled);

List<Map<String, Object?>> wordMidAssignmentState(Uint8List bytes) =>
    fixture.wordCellParagraphState(bytes);

String wordMidAssignmentUntouched(Uint8List bytes) =>
    prefix.wordCellPrefixUntouched(bytes, selectedCellCount: 4);

void assertWordMidAssignmentExample(Uint8List bytes) {
  final cells = fixture.wordCellParagraphs(WordDeserializer().readBytes(bytes));
  if (jsonEncode(cells.map((cell) => cell.text).toList()) !=
      jsonEncode(_expectedText)) {
    throw StateError('Fixed-width labels or untouched neighboring text differ');
  }
  for (var index = 0; index < cells.length; index++) {
    final paragraph = cells[index];
    if (paragraph.properties.justification != WmlJustification.center ||
        paragraph.properties.spacingAfter != 3) {
      throw StateError('Source string editing changed paragraph formatting');
    }
    if (index < 4 &&
        (paragraph.inlines.whereType<WmlRun>().isEmpty ||
            paragraph.inlines.whereType<WmlRun>().any(
              (run) => run.properties.bold != (index < 2),
            ))) {
      throw StateError('Fixed-width label formatting selected the wrong cell');
    }
  }
}

Map<String, Object?> _structured(Map<String, Object?> response) =>
    response['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _source(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'WordMidAssignment',
    'source': source,
  },
};

void _checkPlan(OfficeMacro plan) {
  final expected = <Map<String, Object?>>[
    for (var index = 0; index < 4; index++) ...[
      {
        'tool': 'docx.tableCellRangeText',
        'arguments': {
          'table': 0,
          'row': index ~/ 2,
          'column': index % 2,
          'text': _expectedText[index],
        },
      },
      {
        'tool': 'docx.runFormat',
        'arguments': {
          'paragraph': 0,
          'story': 'tableCell',
          'table': 0,
          'row': index ~/ 2,
          'column': index % 2,
          'bold': index < 2,
        },
      },
    ],
  ];
  if (jsonEncode(plan.steps.map((step) => step.toJson()).toList()) !=
      jsonEncode(expected)) {
    throw StateError(
      'The exact BAS did not lower to eight expected operations',
    );
  }
}

Future<Map<String, Object?>> runWordMidAssignmentExample(
  String source, {
  bool macroEnabled = true,
}) async {
  final input = wordMidAssignmentInput(macroEnabled: macroEnabled);
  final original = base64Encode(input);
  final untouched = wordMidAssignmentUntouched(input);
  final plan = wordMidAssignmentSource(source);
  _checkPlan(plan);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final preview = await session.validate(plan);
  if (!preview.validatedOnly ||
      preview.completedSteps != 8 ||
      session.revision != 0 ||
      base64Encode(session.bytes) != original) {
    throw StateError('Validation changed the document or fixed-width plan');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordMidAssignmentExample(saved);
    if (wordMidAssignmentUntouched(saved) != untouched) {
      throw StateError(
        'Labels changed unrelated geometry, properties or parts',
      );
    }
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  final state = jsonEncode(wordMidAssignmentState(saved));
  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx)
    ..startRecording('Fixed-width source labels');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  if (jsonEncode(recording.steps.map((step) => step.toJson()).toList()) !=
      jsonEncode(plan.steps.map((step) => step.toJson()).toList())) {
    throw StateError('Native recording did not retain the exact label plan');
  }
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recording.encode()));
  if (jsonEncode(wordMidAssignmentState(replay.bytes)) != state ||
      wordMidAssignmentUntouched(replay.bytes) != untouched) {
    throw StateError('Recorded label replay differs from source execution');
  }
  final invalid = wordMidAssignmentPlan(r'''
Dim label As String
label = "OK----"
Mid$(label, 3, 4) = "DONE"
ActiveDocument.Tables(1).Cell(1, 1).Range.Text = label
ActiveDocument.Tables(2).Cell(2, 1).Range.Text = label
''');
  final beforeFailure = base64Encode(session.bytes);
  session.startRecording('Rejected label publication');
  for (final action in [session.validate, session.run]) {
    var refused = false;
    try {
      await action(invalid);
    } on OfficeMacroException catch (error) {
      refused = error.stepIndex == 1 && error.tool == 'docx.tableCellRangeText';
    }
    if (!refused ||
        session.revision != 1 ||
        base64Encode(session.bytes) != beforeFailure) {
      throw StateError('A missing cell published an earlier generated label');
    }
  }
  if (session.stopRecording().steps.isNotEmpty) {
    throw StateError('Failed label publication entered the recording');
  }
  final mcpSession = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final mcp = OfficeMacroMcp(mcpSession);
  final compiled = await mcp.callTool('office_macro_compile', _source(source));
  if (compiled['isError'] != false ||
      mcpSession.revision != 0 ||
      base64Encode(mcpSession.bytes) != original) {
    throw StateError('MCP compilation failed or modified its input');
  }
  final arguments = <String, Object?>{'macro': _structured(compiled)['macro']};
  final validated = await mcp.callTool('office_macro_validate', arguments);
  if (validated['isError'] != false ||
      _structured(validated)['completedSteps'] != 8 ||
      mcpSession.revision != 0 ||
      base64Encode(mcpSession.bytes) != original) {
    throw StateError('MCP preview failed or changed the document');
  }
  final executed = await mcp.callTool('office_macro_run', arguments);
  if (executed['isError'] != false ||
      _structured(executed)['completedSteps'] != 8 ||
      mcpSession.revision != 1 ||
      jsonEncode(wordMidAssignmentState(mcpSession.bytes)) != state ||
      wordMidAssignmentUntouched(mcpSession.bytes) != untouched) {
    throw StateError(
      'MCP execution disagrees with the native generated labels',
    );
  }
  final badSource = await mcp.callTool(
    'office_macro_compile',
    _source(r'''
Sub Main()
  Dim label As String
  label = "0000"
  ActiveDocument.Tables(1).Cell(1, 1).Range.Text = "Discard"
  Mid$(label, 0, 1) = "X"
End Sub
'''),
  );
  final error = _structured(badSource)['error']! as Map<String, Object?>;
  if (badSource['isError'] != true ||
      _structured(badSource).containsKey('macro') ||
      error['code'] != 'vba_type_error' ||
      error['line'] != 5 ||
      mcpSession.revision != 1 ||
      jsonEncode(wordMidAssignmentState(mcpSession.bytes)) != state) {
    throw StateError('A failing source string edit exposed a partial plan');
  }
  final readOnly = OfficeMacroSession(
    input,
    format: OfficeMacroFormat.docx,
    policy: OfficeMacroPolicy(allowMutation: false),
  );
  var denied = false;
  try {
    await readOnly.run(plan);
  } on OfficeMacroException catch (error) {
    denied = error.code == 'permission_denied';
  }
  if (!denied ||
      readOnly.revision != 0 ||
      base64Encode(readOnly.bytes) != original) {
    throw StateError('Generated labels bypassed the read-only host policy');
  }
  return {
    'language': 'vba-word',
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'untouchedGeometryAndParts': true,
    'opaqueVbaPreserved': macroEnabled,
    'immutableValidation': true,
    'lateRollbackAndRecording': true,
    'mcpCompileValidateRun': true,
    'sourceFailureNoPublication': true,
    'readOnlyPolicy': true,
    'state': wordMidAssignmentState(saved),
  };
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError('Supply WORD_MID_ASSIGNMENT_BAS_BASE64');
  }
  final source = utf8.decode(base64Decode(_example));
  print(
    jsonEncode({
      'docx': await runWordMidAssignmentExample(source, macroEnabled: false),
      'docm': await runWordMidAssignmentExample(source),
    }),
  );
}
