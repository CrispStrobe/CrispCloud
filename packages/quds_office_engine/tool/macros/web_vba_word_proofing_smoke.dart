import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _example = String.fromEnvironment('WORD_PROOFING_BAS_BASE64');
const _project = <int>[0, 42, 127, 128, 255];

OfficeMacro wordProofingSource(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordProofingControls',
    source: source,
  ),
);

OfficeMacro wordProofingPlan(String body) =>
    wordProofingSource('Sub Main()\n$body\nEnd Sub');

Uint8List wordProofingInput() {
  WmlParagraph paragraph(String text) => WmlParagraph(
    properties: WmlParagraphProps(suppressAutoHyphens: true),
    inlines: [
      WmlRun(
        text: text,
        properties: WmlRunProps(
          noProof: true,
          kerningHalfPoints: 36,
          proofingLanguage: 'de-DE',
        ),
      ),
    ],
  );
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [paragraph('Silbentrennung'), paragraph('Product ID')],
        header: [paragraph('Report header')],
        linkToPrevious: false,
      ),
    ],
  )..autoHyphenation = true;
  final package = OpcPackage.openBytes(WordSerializer().writeBytes(document));
  const macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
  package.getPart('/word/document.xml')!.contentType = macroType;
  package.contentTypes.setOverride('/word/document.xml', macroType);
  package.createPart(
    '/word/vbaProject.bin',
    'application/vnd.ms-office.vbaProject',
    Uint8List.fromList(_project),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(
        type:
            'http://schemas.microsoft.com/office/2006/relationships/vbaProject',
        target: 'vbaProject.bin',
        id: 'rIdProofingProject',
      );
  return package.save();
}

List<Map<String, Object?>> wordProofingState(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  return [
    for (final paragraph in [
      ...document.sections.single.blocks.whereType<WmlParagraph>(),
      ...document.sections.single.header,
    ])
      {
        'text': paragraph.text,
        'suppressAutoHyphens': paragraph.properties.suppressAutoHyphens,
        'noProof': [
          for (final run in paragraph.inlines.whereType<WmlRun>())
            run.properties.noProof,
        ],
        'kerningHalfPoints': [
          for (final run in paragraph.inlines.whereType<WmlRun>())
            run.properties.kerningHalfPoints,
        ],
      },
  ];
}

Future<Map<String, Object?>> runWordProofingExample(String source) async {
  final input = wordProofingInput();
  final plan = wordProofingSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validation = await session.validate(plan);
  if (!validation.validatedOnly ||
      session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(input)) {
    throw StateError('Validation published the detached document');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  final expected = <Map<String, Object?>>[
    {
      'text': 'Silbentrennung',
      'suppressAutoHyphens': false,
      'noProof': [false],
      'kerningHalfPoints': [25],
    },
    {
      'text': 'Product ID',
      'suppressAutoHyphens': true,
      'noProof': [true],
      'kerningHalfPoints': [0],
    },
    {
      'text': 'Report header',
      'suppressAutoHyphens': true,
      'noProof': [true],
      'kerningHalfPoints': [19],
    },
  ];
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    if (jsonEncode(wordProofingState(saved)) != jsonEncode(expected)) {
      throw StateError('Incorrect proofing controls after reopen $cycle');
    }
    final package = OpcPackage.openBytes(saved);
    if (base64Encode(package.getPart('/word/vbaProject.bin')!.readBytes()) !=
        base64Encode(_project)) {
      throw StateError('Opaque VBA project changed');
    }
    saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
  }
  // Playback does not append to a recording. Record the equivalent native
  // tool calls at their individual successful publication boundaries.
  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word proofing controls');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(recording);
  if (jsonEncode(wordProofingState(replay.bytes)) != jsonEncode(expected)) {
    throw StateError('Recording replay changed the selected targets');
  }
  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'opaqueVbaPreserved': true,
    'state': expected,
  };
}

Future<void> main() async {
  if (_example.isEmpty) throw StateError('Supply WORD_PROOFING_BAS_BASE64');
  print(
    jsonEncode(
      await runWordProofingExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
