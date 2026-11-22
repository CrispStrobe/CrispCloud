import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _example = String.fromEnvironment('WORD_POSITION_BAS_BASE64');
const _project = <int>[0, 42, 127, 128, 255];
const _custom =
    '<position-proof xmlns="urn:quds:test">retained</position-proof>';

OfficeMacro wordPositionSource(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordFontPosition',
    source: source,
  ),
);

OfficeMacro wordPositionPlan(String body) =>
    wordPositionSource('Sub Main()\n$body\nEnd Sub');

Uint8List wordPositionInput() {
  WmlParagraph paragraph(String text) => WmlParagraph(
    inlines: [
      WmlRun(
        text: text,
        properties: WmlRunProps(
          positionHalfPoints: 4,
          fontSizeHalfPoints: 24,
          asciiFont: 'Arial',
          italic: true,
        ),
      ),
    ],
  );
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          paragraph('Raised 😀 text'),
          paragraph('Lowered text'),
          paragraph('Reset text'),
        ],
        header: [paragraph('Report header')],
        linkToPrevious: false,
      ),
    ],
  );
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
        id: 'rIdPositionProject',
      );
  package.createPart(
    '/customXml/position.xml',
    'application/xml',
    utf8.encode(_custom),
  );
  return package.save();
}

List<Map<String, Object?>> wordPositionState(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  return [
    for (final paragraph in [
      ...document.sections.single.blocks.whereType<WmlParagraph>(),
      ...document.sections.single.header,
    ])
      {
        'text': paragraph.text,
        'runs': [
          for (final run in paragraph.inlines.whereType<WmlRun>())
            {
              'positionHalfPoints': run.properties.positionHalfPoints,
              'fontSizeHalfPoints': run.properties.fontSizeHalfPoints,
              'bold': run.properties.bold,
              'italic': run.properties.italic,
            },
        ],
      },
  ];
}

Future<Map<String, Object?>> runWordPositionExample(String source) async {
  final input = wordPositionInput();
  final plan = wordPositionSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validated = await session.validate(plan);
  if (!validated.validatedOnly ||
      session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(input)) {
    throw StateError('Validation published a position edit');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  final expected = <Map<String, Object?>>[
    for (final (text, halfPoints, bold) in [
      ('Raised 😀 text', 6, false),
      ('Lowered text', -4, true),
      ('Reset text', 0, false),
      ('Report header', 2, false),
    ])
      {
        'text': text,
        'runs': [
          {
            'positionHalfPoints': halfPoints,
            'fontSizeHalfPoints': 24,
            'bold': bold,
            'italic': true,
          },
        ],
      },
  ];
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    if (jsonEncode(wordPositionState(saved)) != jsonEncode(expected)) {
      throw StateError(
        'Incorrect position or unrelated formatting after reopen $cycle',
      );
    }
    final package = OpcPackage.openBytes(saved);
    if (base64Encode(package.getPart('/word/vbaProject.bin')!.readBytes()) !=
            base64Encode(_project) ||
        utf8.decode(package.getPart('/customXml/position.xml')!.readBytes()) !=
            _custom) {
      throw StateError('An opaque package part changed');
    }
    saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
  }

  // Absolute source assignments are idempotent even after an earlier run.
  await session.run(plan);
  if (jsonEncode(wordPositionState(session.bytes)) != jsonEncode(expected)) {
    throw StateError('Repeated position writes accumulated a displacement');
  }
  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word baseline position');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(recording);
  if (jsonEncode(wordPositionState(replay.bytes)) != jsonEncode(expected)) {
    throw StateError('Recorded position replay changed the targets');
  }

  final failing = OfficeMacro(
    name: 'Fail after position edits',
    format: OfficeMacroFormat.docx,
    steps: [
      ...plan.steps,
      OfficeMacroStep(
        tool: 'docx.runFormat',
        arguments: {'paragraph': 99, 'position': 1},
      ),
    ],
  );
  for (final action in [replay.validate, replay.run]) {
    final before = base64Encode(replay.bytes);
    final revision = replay.revision;
    var refused = false;
    try {
      await action(failing);
    } on OfficeMacroException {
      refused = true;
    }
    if (!refused ||
        replay.revision != revision ||
        base64Encode(replay.bytes) != before) {
      throw StateError(
        'A late invalid target published partial position changes',
      );
    }
  }
  var policyRefusals = 0;
  for (final policy in [
    OfficeMacroPolicy(allowMutation: false),
    OfficeMacroPolicy(allowedTools: {'docx.replaceText'}),
    OfficeMacroPolicy(maxSteps: 2),
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
      throw StateError('A denied position edit published');
    }
  }
  if (policyRefusals != 3) throw StateError('A position policy was bypassed');

  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'opaquePartsPreserved': true,
    'lateRollback': true,
    'policyRefusals': policyRefusals,
    'state': expected,
  };
}

Future<void> main() async {
  if (_example.isEmpty) throw StateError('Supply WORD_POSITION_BAS_BASE64');
  print(
    jsonEncode(
      await runWordPositionExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
