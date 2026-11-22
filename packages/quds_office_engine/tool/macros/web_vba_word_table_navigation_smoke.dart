import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_cell_paragraphs_smoke.dart' as fixture;
import 'web_vba_word_cell_prefix_smoke.dart' as prefix;

const _example = String.fromEnvironment('WORD_TABLE_NAVIGATION_BAS_BASE64');
const _expectedText = <String>[
  'Item',
  'Status',
  'Document: Quarterly report',
  'Ready\tReviewed',
  'second 0/0',
];

OfficeMacro wordTableNavigationSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordTableNavigation',
        source: source,
      ),
    );

OfficeMacro wordTableNavigationPlan(String body) =>
    wordTableNavigationSource('Option Explicit\nSub Main()\n$body\nEnd Sub');

/// An ordinary 2x2 table, a separate 1x1 table, rich text and an empty cell,
/// foreign paragraph metadata, custom XML, headers and an optional inert VBA
/// part. All existing package guards remain part of the runtime path.
Uint8List wordTableNavigationInput({bool macroEnabled = true}) =>
    prefix.wordCellPrefixInput(macroEnabled: macroEnabled);

List<Map<String, Object?>> wordTableNavigationState(Uint8List bytes) =>
    fixture.wordCellParagraphState(bytes);

String wordTableNavigationUntouched(Uint8List bytes) =>
    fixture.wordCellParagraphUntouched(bytes, selectedCellCount: 4);

void assertWordTableNavigationExample(Uint8List bytes) {
  final cells = fixture.wordCellParagraphs(WordDeserializer().readBytes(bytes));
  if (jsonEncode(cells.map((cell) => cell.text).toList()) !=
      jsonEncode(_expectedText)) {
    throw StateError('Row/column navigation selected the wrong table cell');
  }
  for (var index = 0; index < cells.length; index++) {
    final paragraph = cells[index];
    if (paragraph.properties.justification !=
            (index == 3 ? WmlJustification.right : WmlJustification.center) ||
        paragraph.properties.spacingAfter != 3) {
      throw StateError('Navigation changed unrelated paragraph formatting');
    }
    if (index < 2 &&
        paragraph.inlines.whereType<WmlRun>().any(
          (run) => !run.properties.bold,
        )) {
      throw StateError('A Cells helper lost its selected heading');
    }
    if (index == 3 &&
        paragraph.inlines.whereType<WmlRun>().any(
          (run) => run.properties.color != '008000',
        )) {
      throw StateError('The retained column Range omitted its appended text');
    }
  }
}

Map<String, Object?> _structured(Map<String, Object?> response) =>
    response['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _source(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'WordTableNavigation',
    'source': source,
  },
};

void _checkPlan(OfficeMacro plan) {
  const tools = <String>[
    'docx.tableCellRangeText',
    'docx.runFormat',
    'docx.tableCellRangeText',
    'docx.runFormat',
    'docx.tableCellRangeText',
    'docx.tableCellRangeText',
    'docx.tableCellRangeInsertAfter',
    'docx.runFormat',
    'docx.paragraphFormat',
    'docx.tableCellRangeInsertBefore',
  ];
  const targets = <List<int>>[
    [0, 0, 0],
    [0, 0, 0],
    [0, 0, 1],
    [0, 0, 1],
    [0, 1, 0],
    [0, 1, 1],
    [0, 1, 1],
    [0, 1, 1],
    [0, 1, 1],
    [0, 1, 0],
  ];
  if (jsonEncode(plan.steps.map((step) => step.tool).toList()) !=
          jsonEncode(tools) ||
      jsonEncode([
            for (final step in plan.steps)
              [
                step.arguments['table'],
                step.arguments['row'],
                step.arguments['column'],
              ],
          ]) !=
          jsonEncode(targets)) {
    throw StateError('The example did not lower to the ten expected targets');
  }
}

Future<Map<String, Object?>> runWordTableNavigationExample(
  String source, {
  bool macroEnabled = true,
}) async {
  final input = wordTableNavigationInput(macroEnabled: macroEnabled);
  final original = base64Encode(input);
  final untouched = wordTableNavigationUntouched(input);
  final plan = wordTableNavigationSource(source);
  _checkPlan(plan);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final preview = await session.validate(plan);
  if (!preview.validatedOnly ||
      preview.completedSteps != 10 ||
      session.revision != 0 ||
      base64Encode(session.bytes) != original) {
    throw StateError('Validation changed the table session');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordTableNavigationExample(saved);
    if (wordTableNavigationUntouched(saved) != untouched) {
      throw StateError('Navigation changed unrelated geometry, XML or VBA');
    }
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  final state = jsonEncode(wordTableNavigationState(saved));
  final invalid = wordTableNavigationPlan('''
ActiveDocument.Tables(Index:=1).Rows(Index:=1).Cells(Index:=1).Range.Text = "Discard"
ActiveDocument.Tables(2).Columns(1).Cells(2).Range.Text = "Missing row"
''');
  final beforeFailure = base64Encode(session.bytes);
  session.startRecording('Rejected row and column navigation');
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
      throw StateError('A missing cell published an earlier navigation edit');
    }
  }
  if (session.stopRecording().steps.isNotEmpty) {
    throw StateError('Failed table navigation entered the recording');
  }
  final mcpSession = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final mcp = OfficeMacroMcp(mcpSession);
  final compiled = await mcp.callTool('office_macro_compile', _source(source));
  if (compiled['isError'] != false ||
      mcpSession.revision != 0 ||
      base64Encode(mcpSession.bytes) != original) {
    throw StateError('MCP compilation failed or touched its document');
  }
  final arguments = <String, Object?>{'macro': _structured(compiled)['macro']};
  final validated = await mcp.callTool('office_macro_validate', arguments);
  if (validated['isError'] != false ||
      _structured(validated)['completedSteps'] != 10 ||
      mcpSession.revision != 0 ||
      base64Encode(mcpSession.bytes) != original) {
    throw StateError('MCP preview failed or changed its document');
  }
  final executed = await mcp.callTool('office_macro_run', arguments);
  if (executed['isError'] != false ||
      _structured(executed)['completedSteps'] != 10 ||
      mcpSession.revision != 1 ||
      jsonEncode(wordTableNavigationState(mcpSession.bytes)) != state ||
      wordTableNavigationUntouched(mcpSession.bytes) != untouched) {
    throw StateError('MCP execution disagrees with native plan execution');
  }
  final badSource = await mcp.callTool(
    'office_macro_compile',
    _source('''
Sub Main()
  ActiveDocument.Tables(1).Rows(1).Cells(1).Range.Text = "Discard"
  If False Then
    ActiveDocument.Tables(1).Rows(Row:=1).Cells(1).Range.Text = "Invalid"
  End If
End Sub
'''),
  );
  final error = _structured(badSource)['error']! as Map<String, Object?>;
  if (badSource['isError'] != true ||
      _structured(badSource).containsKey('macro') ||
      error['code'] != 'vba_name_error' ||
      error['line'] != 4 ||
      mcpSession.revision != 1 ||
      jsonEncode(wordTableNavigationState(mcpSession.bytes)) != state) {
    throw StateError('An inactive malformed named selector escaped checking');
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
    throw StateError('Table navigation bypassed the read-only host policy');
  }
  return {
    'language': 'vba-word',
    'operations': plan.steps.length,
    'revision': session.revision,
    'additionalReopens': 2,
    'untouchedGeometryAndParts': true,
    'opaqueVbaPreserved': macroEnabled,
    'immutableValidation': true,
    'lateRollbackAndRecording': true,
    'mcpCompileValidateRun': true,
    'inactiveNamedArgumentRejected': true,
    'readOnlyPolicy': true,
    'state': wordTableNavigationState(saved),
  };
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError('Supply WORD_TABLE_NAVIGATION_BAS_BASE64');
  }
  print(
    jsonEncode(
      await runWordTableNavigationExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
