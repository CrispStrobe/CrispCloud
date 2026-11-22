import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_headers_footers_smoke.dart' as fixture;

// The portable runner consumes the actual checked-in BAS on both targets.
const _example = String.fromEnvironment('WORD_TEXT_SELECTORS_BAS_BASE64');

OfficeMacro wordTextSelectorsSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordTextSelectors',
        source: source,
      ),
    );

OfficeMacro wordTextSelectorsPlan(String body) =>
    wordTextSelectorsSource('Option Explicit\nSub Main()\n$body\nEnd Sub');

/// Three independent sections, all six header/footer variants, two paragraphs
/// per story and opaque VBA/signature/custom parts. This fixture is DOCM; the
/// shared substring integration tests independently cover ordinary DOCX.
Uint8List wordTextSelectorsInput() => fixture.wordHeadersFootersInput();

Map<String, Object?> wordTextSelectorsState(Uint8List bytes) =>
    fixture.wordHeadersFootersState(bytes);

const wordTextSelectorsExpectedSteps = <Map<String, Object?>>[
  {
    'tool': 'docx.replaceText',
    'arguments': {
      'paragraph': 0,
      'story': 'header',
      'section': 1,
      'start': 0,
      'end': 0,
      'text': 'INV 0042 / DE: ',
    },
  },
  {
    'tool': 'docx.runFormat',
    'arguments': {
      'paragraph': 0,
      'story': 'header',
      'section': 1,
      'bold': true,
    },
  },
  {
    'tool': 'docx.replaceText',
    'arguments': {
      'paragraph': 1,
      'story': 'evenFooter',
      'section': 1,
      'start': 0,
      'end': 0,
      'text': 'DE ',
    },
  },
  {
    'tool': 'docx.replaceText',
    'arguments': {'paragraph': 0, 'start': 0, 'end': 0, 'text': 'INV '},
  },
  {
    'tool': 'docx.replaceText',
    'arguments': {
      'paragraph': 0,
      'story': 'firstHeader',
      'section': 2,
      'start': 0,
      'end': 0,
      'text': 'Pending: ',
    },
  },
];

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// Independently expected text and formatting for every body/story paragraph.
void assertWordTextSelectorsExample(Uint8List bytes, {int repetitions = 1}) {
  final expected = wordTextSelectorsState(wordTextSelectorsInput());
  void edit(String key, Map<String, Object?> changes) {
    expected[key] = {...expected[key]! as Map<String, Object?>, ...changes};
  }

  expected['body'] = [
    '${List.filled(repetitions, 'INV ').join()}Body 1',
    'Body 2',
    'Body 3',
  ];
  edit('2.header.1', {
    'text': '${List.filled(repetitions, 'INV 0042 / DE: ').join()}S2 header 1',
    'bold': [true],
  });
  edit('2.evenFooter.2', {
    'text': '${List.filled(repetitions, 'DE ').join()}S2 evenFooter 2',
  });
  edit('3.firstHeader.1', {
    'text': '${List.filled(repetitions, 'Pending: ').join()}S3 firstHeader 1',
  });
  final actual = wordTextSelectorsState(bytes);
  _check(
    jsonEncode(actual) == jsonEncode(expected),
    'Named selectors or substring helpers changed the wrong paragraph',
  );
  fixture.assertWordHeadersFootersPackage(bytes);
}

void assertWordTextSelectorsPlan(OfficeMacro plan) {
  _check(plan.steps.length == 5, 'The BAS must produce exactly five edits');
  for (var index = 0; index < wordTextSelectorsExpectedSteps.length; index++) {
    final expected = wordTextSelectorsExpectedSteps[index];
    final fields = expected['arguments']! as Map<String, Object?>;
    final actual = plan.steps[index];
    _check(
      actual.tool == expected['tool'] &&
          actual.arguments.length == fields.length &&
          fields.entries.every(
            (field) => actual.arguments[field.key] == field.value,
          ),
      'The BAS produced an unexpected operation at index $index',
    );
  }
}

Map<String, Object?> _structured(Map<String, Object?> response) =>
    response['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _source(String source) => {
  'source': {
    'language': 'vba-word',
    'format': 'docx',
    'moduleName': 'WordTextSelectors',
    'source': source,
  },
};

Future<Map<String, Object?>> runWordTextSelectorsExample(String source) async {
  final input = wordTextSelectorsInput();
  final original = base64Encode(input);
  final plan = wordTextSelectorsSource(source);
  assertWordTextSelectorsPlan(plan);
  final guard = (await WordPackagePreservation.capture(
    input,
    'selectors.docm',
  ))!;
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final preview = await session.validate(plan);
  _check(
    preview.validatedOnly &&
        preview.completedSteps == 5 &&
        session.revision == 0 &&
        base64Encode(session.bytes) == original,
    'Detached validation published a document edit',
  );
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  _check(
    result.completedSteps == 5 && session.revision == 1,
    'The example did not publish exactly one native transaction',
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordTextSelectorsExample(saved);
    await guard.validateSaved(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  final state = jsonEncode(wordTextSelectorsState(saved));

  // Native operation recording is explicit; source-plan execution itself does
  // not add a duplicate macro to a recorder.
  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx)
    ..startRecording('Named template labels');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(recording);
  _check(
    recording.steps.length == 5 &&
        jsonEncode(wordTextSelectorsState(replay.bytes)) == state &&
        jsonEncode(wordTextSelectorsState(recorder.bytes)) == state,
    'Recorded native operations did not replay the selected report',
  );
  await guard.validateSaved(recorder.bytes);
  await guard.validateSaved(replay.bytes);

  final invalid = wordTextSelectorsPlan('''
ActiveDocument.Paragraphs(Index:=1).Range.InsertBefore Text:=Left("Discard", 3)
ActiveDocument.Sections(Index:=2).Headers(Index:=wdHeaderFooterPrimary).Range.Paragraphs(Index:=99).Range.Font.Bold = True
''');
  final beforeFailure = base64Encode(session.bytes);
  session.startRecording('Rejected named template edit');
  for (final action in [session.validate, session.run]) {
    var refused = false;
    try {
      await action(invalid);
    } on OfficeMacroException catch (error) {
      refused =
          error.code == 'operation_failed' &&
          error.stepIndex == 1 &&
          error.tool == 'docx.runFormat';
    }
    _check(
      refused &&
          session.revision == 1 &&
          base64Encode(session.bytes) == beforeFailure,
      'A missing named paragraph published an earlier operation',
    );
  }
  _check(
    session.stopRecording().steps.isEmpty,
    'A rejected native transaction entered the recording',
  );

  final mcpSession = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final mcp = OfficeMacroMcp(mcpSession);
  final compiled = await mcp.callTool('office_macro_compile', _source(source));
  _check(
    compiled['isError'] == false &&
        mcpSession.revision == 0 &&
        base64Encode(mcpSession.bytes) == original,
    'MCP compilation failed or touched its document',
  );
  final arguments = <String, Object?>{'macro': _structured(compiled)['macro']};
  final validated = await mcp.callTool('office_macro_validate', arguments);
  _check(
    validated['isError'] == false &&
        _structured(validated)['completedSteps'] == 5 &&
        mcpSession.revision == 0 &&
        base64Encode(mcpSession.bytes) == original,
    'MCP validation changed its source document',
  );
  final executed = await mcp.callTool('office_macro_run', arguments);
  _check(
    executed['isError'] == false &&
        _structured(executed)['completedSteps'] == 5 &&
        mcpSession.revision == 1 &&
        jsonEncode(wordTextSelectorsState(mcpSession.bytes)) == state,
    'MCP execution disagrees with direct execution',
  );
  await guard.validateSaved(mcpSession.bytes);
  final badSource = await mcp.callTool(
    'office_macro_compile',
    _source('''
Sub Main()
  ActiveDocument.Paragraphs(Index:=1).Range.InsertBefore "Discard"
  If False Then
    ActiveDocument.Paragraphs(Ordinal:=1).Range.InsertBefore "Invalid"
  End If
End Sub
'''),
  );
  final error = _structured(badSource)['error']! as Map<String, Object?>;
  _check(
    badSource['isError'] == true &&
        !_structured(badSource).containsKey('macro') &&
        error['code'] == 'vba_name_error' &&
        error['line'] == 4 &&
        mcpSession.revision == 1 &&
        jsonEncode(wordTextSelectorsState(mcpSession.bytes)) == state,
    'An inactive malformed named selector escaped source checking',
  );

  for (final (policy, expectedCode) in <(OfficeMacroPolicy, String)>[
    (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
    (
      OfficeMacroPolicy(allowedTools: {'docx.replaceText'}),
      'permission_denied',
    ),
    (OfficeMacroPolicy(maxSteps: 4), 'limit_exceeded'),
  ]) {
    final restricted = OfficeMacroSession(
      input,
      format: OfficeMacroFormat.docx,
      policy: policy,
    );
    var refused = false;
    try {
      await restricted.run(plan);
    } on OfficeMacroException catch (error) {
      refused = error.code == expectedCode;
    }
    _check(
      refused &&
          restricted.revision == 0 &&
          base64Encode(restricted.bytes) == original,
      'The new language bypassed an existing native policy boundary',
    );
  }

  await session.run(plan);
  assertWordTextSelectorsExample(session.bytes, repetitions: 2);
  await guard.validateSaved(session.bytes);
  _check(base64Encode(input) == original, 'Source input bytes changed');
  return {
    'language': 'vba-word',
    'fixtureFormat': 'docm',
    'operations': plan.steps.length,
    'firstRunRevision': result.revision,
    'repeatedRevision': session.revision,
    'additionalReopens': 2,
    'recordedSteps': recording.steps.length,
    'untouchedStoryParagraphs': 33,
    'untouchedBodyParagraphs': 2,
    'opaquePayloadsPreserved': true,
    'immutableValidation': true,
    'nativeRecordingAndReplay': true,
    'lateRollbackAndRecording': true,
    'mcpCompileValidateRun': true,
    'inactiveNamedArgumentRejected': true,
    'hostPolicyGuards': true,
    'state': wordTextSelectorsState(saved),
  };
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError('Supply WORD_TEXT_SELECTORS_BAS_BASE64 from the BAS file');
  }
  print(
    jsonEncode(
      await runWordTextSelectorsExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
