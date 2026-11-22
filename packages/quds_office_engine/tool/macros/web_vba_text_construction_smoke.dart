import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_text_smoke.dart' as text_fixture;

const _example = String.fromEnvironment('WORD_TEXT_CONSTRUCTION_BAS_BASE64');

const textConstructionExpected = <String>[
  '★★ READY body one',
  '😀  \u8000: body two',
  '--- report header',
];

OfficeMacro textConstructionSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordTextConstruction',
        source: source,
      ),
    );

OfficeMacro textConstructionPlan(String body) =>
    textConstructionSource('Sub Main()\n$body\nEnd Sub');

void _check(Uint8List bytes) {
  if (jsonEncode(text_fixture.wordTextState(bytes)) !=
      jsonEncode(textConstructionExpected)) {
    throw StateError('Constructed Unicode text changed after publication');
  }
  final document = WordDeserializer().readBytes(bytes);
  final first = document.sections.single.blocks.whereType<WmlParagraph>().first;
  final runs = first.inlines.whereType<WmlRun>().toList();
  if (!runs.every((run) => run.properties.bold == true) ||
      !runs.any(
        (run) =>
            run.text.contains('body ') &&
            run.properties.italic == true &&
            run.properties.asciiFont == 'Courier New',
      ) ||
      !runs.any(
        (run) => run.text.contains('one') && run.properties.color == '9C0006',
      ) ||
      !document.sections.single.header.single.inlines.whereType<WmlRun>().every(
        (run) => run.properties.italic == true,
      )) {
    throw StateError(
      'Constructed text damaged existing or requested formatting',
    );
  }
  final original = OpcPackage.openBytes(text_fixture.wordTextInput());
  final saved = OpcPackage.openBytes(bytes);
  if (base64Encode(saved.getPart('/word/vbaProject.bin')!.readBytes()) !=
      base64Encode(original.getPart('/word/vbaProject.bin')!.readBytes())) {
    throw StateError('Constructed text changed the inert VBA project');
  }
}

Future<Map<String, Object?>> runTextConstructionExample(String source) async {
  final input = text_fixture.wordTextInput();
  final plan = textConstructionSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validation = await session.validate(plan);
  if (!validation.validatedOnly ||
      session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(input)) {
    throw StateError('Validation published prepared text');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    _check(saved);
    saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
  }

  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word Unicode construction');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(recording);
  _check(replay.bytes);

  final rollback = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final lateFailure = textConstructionPlan('''
ActiveDocument.Paragraphs(1).Range.InsertBefore String\$(3, "*")
ActiveDocument.Paragraphs(99).Range.InsertBefore ChrW(8364)
''');
  for (final action in [rollback.validate, rollback.run]) {
    var refused = false;
    try {
      await action(lateFailure);
    } on OfficeMacroException catch (error) {
      refused = error.stepIndex == 1;
    }
    if (!refused ||
        rollback.revision != 0 ||
        base64Encode(rollback.bytes) != base64Encode(input)) {
      throw StateError('Late failure published earlier generated text');
    }
  }
  for (final policy in [
    OfficeMacroPolicy(allowMutation: false),
    OfficeMacroPolicy(allowedTools: {'docx.runFormat'}),
    OfficeMacroPolicy(maxSteps: 4),
  ]) {
    final denied = OfficeMacroSession(
      input,
      format: OfficeMacroFormat.docx,
      policy: policy,
    );
    var refused = false;
    try {
      await denied.run(plan);
    } on OfficeMacroException {
      refused = true;
    }
    if (!refused ||
        denied.revision != 0 ||
        base64Encode(denied.bytes) != base64Encode(input)) {
      throw StateError('Generated text bypassed the mutation policy');
    }
  }
  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'opaqueVbaPreserved': true,
    'richFormattingPreserved': true,
    'lateRollback': true,
    'policyDenials': 3,
    'text': textConstructionExpected,
    'scalarChecks': textConstructionSource('''
Sub Main()
ActiveDocument.Paragraphs(1).Range.InsertBefore CStr(AscW(ChrW(-32768)))
ActiveDocument.Paragraphs(1).Range.InsertBefore CStr(Len(String\$(3, "😀")))
End Sub
''').steps.map((step) => step.arguments['text']).toList(),
  };
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError('Supply WORD_TEXT_CONSTRUCTION_BAS_BASE64');
  }
  print(
    jsonEncode(
      await runTextConstructionExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
