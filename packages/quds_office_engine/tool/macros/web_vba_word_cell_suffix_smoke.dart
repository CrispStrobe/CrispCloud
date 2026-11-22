import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_cell_paragraphs_smoke.dart' as fixture;
import 'web_vba_word_cell_prefix_smoke.dart' as prefix;

const _example = String.fromEnvironment('WORD_CELL_SUFFIX_BAS_BASE64');
const _expected = <String>[
  'first 0/0\tReady\tReviewed',
  'first 0/1\tPeer\tOwner',
  'New\tReady',
  'first 1/1',
  'second 0/0',
];

OfficeMacro wordCellSuffixSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordCellSuffix',
        source: source,
      ),
    );

OfficeMacro wordCellSuffixPlan(String body) =>
    wordCellSuffixSource('Option Explicit\nSub Main()\n$body\nEnd Sub');

/// Two existing tables, a rich first cell, an empty cell, retained foreign
/// paragraph properties, custom XML, headers and an optional inert VBA part.
/// One ordinary save establishes the source-preservation baseline.
Uint8List wordCellSuffixInput({bool macroEnabled = true}) =>
    prefix.wordCellPrefixInput(macroEnabled: macroEnabled);

List<Map<String, Object?>> wordCellSuffixState(Uint8List bytes) => [
  for (final paragraph in fixture.wordCellParagraphs(
    WordDeserializer().readBytes(bytes),
  ))
    {
      'text': paragraph.text,
      'style': paragraph.properties.styleId,
      'shading': paragraph.properties.shadingFill,
      'runs': [
        for (final run in paragraph.inlines.whereType<WmlRun>())
          {
            'text': run.text,
            'bold': run.properties.bold,
            'italic': run.properties.italic,
            'font': run.properties.asciiFont,
            'size': run.properties.fontSizeHalfPoints,
            'kerning': run.properties.kerningHalfPoints,
            'color': run.properties.color,
          },
      ],
    },
];

/// Compare paragraph properties, untouched cells, geometry and opaque parts.
String wordCellSuffixUntouched(Uint8List bytes, {int selectedCellCount = 3}) =>
    prefix.wordCellPrefixUntouched(bytes, selectedCellCount: selectedCellCount);

void assertWordCellSuffixExample(Uint8List bytes) {
  final cells = fixture.wordCellParagraphs(WordDeserializer().readBytes(bytes));
  if (jsonEncode(cells.map((cell) => cell.text).toList()) !=
      jsonEncode(_expected)) {
    throw StateError(
      'Suffix insertion changed the selected text or a neighbor',
    );
  }
  final first = cells.first;
  // Only the original first span is italic. Appended labels inherit the
  // differently formatted final span, including its independent kerning.
  // The final Bold assignment covers both original spans and both suffixes.
  for (var index = 0; index < first.text.length; index++) {
    final props = WmlRunEdit.propsAt(first, index);
    final leading = index < 'first '.length;
    if (!props.bold ||
        props.italic != leading ||
        props.color != (leading ? '17365D' : 'A23B35') ||
        props.asciiFont != (leading ? 'Courier New' : 'Georgia') ||
        props.fontSizeHalfPoints != (leading ? 24 : 28) ||
        props.kerningHalfPoints != (leading ? 0 : 24)) {
      throw StateError('Suffix insertion or subsequent formatting lost a run');
    }
  }
  for (final run in cells[1].inlines.whereType<WmlRun>()) {
    if (!run.properties.bold ||
        run.properties.color != '1F4E79' ||
        run.properties.asciiFont != 'Courier New' ||
        run.properties.fontSizeHalfPoints != 24) {
      throw StateError(
        'Appending a peer label changed existing run formatting',
      );
    }
  }
  if (cells.any(
    (cell) =>
        cell.properties.justification != WmlJustification.center ||
        cell.properties.spacingAfter != 3,
  )) {
    throw StateError('Suffix insertion changed paragraph formatting');
  }
}

Future<Map<String, Object?>> runWordCellSuffixExample(
  String source, {
  bool macroEnabled = true,
}) async {
  final input = wordCellSuffixInput(macroEnabled: macroEnabled);
  final original = base64Encode(input);
  final untouched = wordCellSuffixUntouched(input);
  final plan = wordCellSuffixSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final preview = await session.validate(plan);
  if (!preview.validatedOnly ||
      preview.completedSteps != 6 ||
      session.revision != 0 ||
      base64Encode(session.bytes) != original) {
    throw StateError('Suffix validation changed the session or step count');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordCellSuffixExample(saved);
    if (wordCellSuffixUntouched(saved) != untouched) {
      throw StateError('Suffix insertion changed unrelated XML or parts');
    }
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  final state = jsonEncode(wordCellSuffixState(saved));
  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx)
    ..startRecording('Retained table text with labels');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recording.encode()));
  assertWordCellSuffixExample(replay.bytes);
  if (jsonEncode(wordCellSuffixState(replay.bytes)) != state ||
      wordCellSuffixUntouched(replay.bytes) != untouched) {
    throw StateError('Recorded suffixes changed their text or target identity');
  }
  final invalid = wordCellSuffixPlan('''
ActiveDocument.Tables(1).Cell(1, 1).Range.InsertAfter Text:="Discard: "
ActiveDocument.Tables(2).Cell(2, 1).Range.InsertAfter Text:="Missing: "
''');
  final beforeFailure = base64Encode(session.bytes);
  session.startRecording('Rejected suffixes');
  for (final action in [session.validate, session.run]) {
    var refused = false;
    try {
      await action(invalid);
    } on OfficeMacroException catch (error) {
      refused =
          error.stepIndex == 1 &&
          error.tool == 'docx.tableCellRangeInsertAfter';
    }
    if (!refused ||
        session.revision != 1 ||
        base64Encode(session.bytes) != beforeFailure) {
      throw StateError('A late invalid cell published earlier suffix changes');
    }
  }
  if (session.stopRecording().steps.isNotEmpty) {
    throw StateError('A failed suffix run entered the recording');
  }
  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'untouchedLayoutAndParts': true,
    'opaqueVbaPreserved': macroEnabled,
    'lateRollback': true,
    'state': wordCellSuffixState(saved),
  };
}

Future<void> main() async {
  if (_example.isEmpty) throw StateError('Supply WORD_CELL_SUFFIX_BAS_BASE64');
  print(
    jsonEncode(
      await runWordCellSuffixExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
