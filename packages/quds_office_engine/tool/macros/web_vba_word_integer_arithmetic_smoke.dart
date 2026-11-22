import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_cell_suffix_smoke.dart' as fixture;

const _example = String.fromEnvironment('WORD_GROUPED_REPORT_BAS_BASE64');
const groupedReportText = <String>[
  'Alpha\tGroup 1',
  'Beta\tGroup 1',
  'Prêt 😀\tGroup 2',
  'Review\tGroup 2',
  'second 0/0',
];

OfficeMacro groupedReportSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'GroupedReport',
        source: source,
      ),
    );

String appendGroupedReportStatement(String source, String statement) {
  final end = source.lastIndexOf('End Sub');
  if (end < 0) throw ArgumentError('Expected the complete grouped report BAS');
  return '${source.substring(0, end)}$statement\n${source.substring(end)}';
}

Future<Map<String, Object?>> runGroupedReport(
  String source, {
  bool macroEnabled = true,
}) async {
  final input = fixture.wordCellSuffixInput(macroEnabled: macroEnabled);
  final untouched = fixture.wordCellSuffixUntouched(input);
  final plan = groupedReportSource(source);
  if (plan.steps.length != 12) {
    throw StateError('The complete grouped report must emit twelve operations');
  }
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final preview = await session.validate(plan);
  if (!preview.validatedOnly ||
      preview.completedSteps != 12 ||
      session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(input)) {
    throw StateError('Validation published a grouped report');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  if (session.revision != 1) {
    throw StateError('Execution did not commit one complete report');
  }
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    final state = fixture.wordCellSuffixState(saved);
    if (jsonEncode(state.map((cell) => cell['text']).toList()) !=
        jsonEncode(groupedReportText)) {
      throw StateError('Integer arithmetic selected the wrong report cell');
    }
    for (var index = 0; index < 4; index++) {
      final runs = state[index]['runs']! as List<Map<String, Object?>>;
      if (runs.isEmpty || runs.any((run) => run['bold'] != index.isEven)) {
        throw StateError('Mod-based report emphasis was not retained');
      }
    }
    if (fixture.wordCellSuffixUntouched(saved) != untouched) {
      throw StateError('The report changed unrelated layout or opaque parts');
    }
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx)
    ..startRecording('Grouped report');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  if (recording.steps.length != 12) {
    throw StateError('The complete report was not recorded');
  }
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recording.encode()));
  if (jsonEncode(fixture.wordCellSuffixState(replay.bytes)) !=
      jsonEncode(fixture.wordCellSuffixState(saved))) {
    throw StateError('Recorded native report replay changed the result');
  }

  final invalid = groupedReportSource(
    appendGroupedReportStatement(
      source,
      'ActiveDocument.Tables(99).Cell(1, 1).Range.Text = "missing"',
    ),
  );
  final beforeFailure = base64Encode(session.bytes);
  session.startRecording('Rejected grouped report');
  for (final action in [session.validate, session.run]) {
    var refused = false;
    try {
      await action(invalid);
    } on OfficeMacroException catch (error) {
      refused = error.stepIndex == 12;
    }
    if (!refused ||
        session.revision != 1 ||
        base64Encode(session.bytes) != beforeFailure) {
      throw StateError('Late report failure published earlier cell writes');
    }
  }
  if (session.stopRecording().steps.isNotEmpty) {
    throw StateError('A failed report entered the recording');
  }
  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'untouchedLayoutAndParts': true,
    'opaqueVbaPreserved': macroEnabled,
    'lateRollback': true,
    'state': fixture.wordCellSuffixState(saved),
  };
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError('Supply WORD_GROUPED_REPORT_BAS_BASE64');
  }
  print(
    jsonEncode(await runGroupedReport(utf8.decode(base64Decode(_example)))),
  );
}
