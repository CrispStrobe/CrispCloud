import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _example = String.fromEnvironment('WORD_ALL_CAPS_BAS_BASE64');
const _project = <int>[0, 42, 127, 128, 255];

OfficeMacro wordAllCapsSource(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordAllCaps',
    source: source,
  ),
);

OfficeMacro wordAllCapsPlan(String body) =>
    wordAllCapsSource('Sub Main()\n$body\nEnd Sub');

Uint8List wordAllCapsInput() {
  WmlParagraph paragraph(String text, {bool allCaps = false}) => WmlParagraph(
    inlines: [
      WmlRun(
        text: text,
        properties: WmlRunProps(
          allCaps: allCaps,
          smallCaps: !allCaps,
          color: '2468AC',
          fontSizeHalfPoints: 24,
          proofingLanguage: 'de-DE',
        ),
      ),
    ],
  );
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [paragraph('Straße ﬃ 😀'), paragraph('Résumé', allCaps: true)],
        header: [paragraph('État العربية')],
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
        id: 'rIdAllCapsProject',
      );
  return package.save();
}

List<Map<String, Object?>> wordAllCapsState(Uint8List bytes) {
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
              'text': run.text,
              'allCaps': run.properties.allCaps,
              'smallCaps': run.properties.smallCaps,
              'size': run.properties.fontSizeHalfPoints,
              'color': run.properties.color,
              'language': run.properties.proofingLanguage,
            },
        ],
      },
  ];
}

void _verifyProject(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  if (base64Encode(package.getPart('/word/vbaProject.bin')!.readBytes()) !=
      base64Encode(_project)) {
    throw StateError('Opaque embedded project changed');
  }
}

Future<Map<String, Object?>> runWordAllCapsExample(String source) async {
  final input = wordAllCapsInput();
  final plan = wordAllCapsSource(source);
  if (plan.steps.length != 7) {
    throw StateError('Expected seven explicit capital-formatting operations');
  }
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validation = await session.validate(plan);
  if (!validation.validatedOnly ||
      session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(input)) {
    throw StateError('Validation published a detached edit');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  final expected = <Map<String, Object?>>[
    for (final (text, allCaps) in [
      ('Straße ﬃ 😀', true),
      ('Résumé', false),
      ('État العربية', true),
    ])
      {
        'text': text,
        'runs': [
          {
            'text': text,
            'allCaps': allCaps,
            'smallCaps': false,
            'size': 24,
            'color': '2468AC',
            'language': 'de-DE',
          },
        ],
      },
  ];
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    if (jsonEncode(wordAllCapsState(saved)) != jsonEncode(expected)) {
      throw StateError(
        'Incorrect capitals after reopen $cycle: ${jsonEncode(wordAllCapsState(saved))}',
      );
    }
    _verifyProject(saved);
    saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
  }

  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word capital formatting');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(recording);
  if (jsonEncode(wordAllCapsState(replay.bytes)) != jsonEncode(expected)) {
    throw StateError('Recorded edits changed target identity');
  }
  _verifyProject(replay.bytes);

  // Run the same Unicode display conversion on VM and JS. Authoring remains
  // separate from display, including expanding uppercase mappings.
  final display = WordSmallCaps.segments('Straße ﬃ 😀', allCaps: true);
  if (display.map((s) => s.text).join() != 'STRASSE FFI 😀' ||
      display.any((s) => s.scale != 1)) {
    throw StateError('AllCaps must uppercase at the original font size');
  }
  final package = OpcPackage.openBytes(session.bytes);
  final selectedParts =
      package.parts
          .where(
            (part) =>
                part.uri == '/word/document.xml' ||
                part.uri.startsWith('/word/header') ||
                part.uri == '/word/vbaProject.bin',
          )
          .toList()
        ..sort((a, b) => a.uri.compareTo(b.uri));
  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'opaqueVbaPreserved': true,
    'plan': [for (final step in plan.steps) step.toJson()],
    'state': expected,
    'display': [
      for (final s in display)
        {'text': s.text, 'start': s.start, 'end': s.end, 'scale': s.scale},
    ],
    'nativePartSha256': {
      for (final part in selectedParts)
        part.uri: sha256
            .convert(package.getPart(part.uri)!.readBytes())
            .toString(),
    },
  };
}

Future<void> main() async {
  if (_example.isEmpty) throw StateError('Supply WORD_ALL_CAPS_BAS_BASE64');
  print(
    jsonEncode(
      await runWordAllCapsExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
