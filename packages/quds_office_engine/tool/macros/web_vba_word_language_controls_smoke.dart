import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _example = String.fromEnvironment('WORD_LANGUAGE_CONTROLS_BAS_BASE64');
const _project = <int>[0, 42, 127, 128, 255];

OfficeMacro wordLanguageSource(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordLanguageControls',
    source: source,
  ),
);

OfficeMacro wordLanguagePlan(String body) =>
    wordLanguageSource('Sub Main()\n$body\nEnd Sub');

Uint8List wordLanguageInput() {
  WmlParagraph paragraph(String text) => WmlParagraph(
    properties: WmlParagraphProps(proofingLanguage: 'it-IT'),
    inlines: [
      WmlRun(
        text: text,
        properties: WmlRunProps(
          noProof: true,
          proofingLanguage: 'en-US',
          complexScriptLanguage: 'ar-SA',
          asciiFont: 'Latin Original',
          csFont: 'Complex Original',
        ),
      ),
    ],
  );
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [paragraph('Prüfbericht العربية'), paragraph('Report العربية')],
        header: [paragraph('En-tête العربية')],
        linkToPrevious: false,
      ),
    ],
  );
  final package = OpcPackage.openBytes(WordSerializer().writeBytes(document));
  for (final part in package.parts) {
    if (part.uri == '/word/document.xml' ||
        part.uri.startsWith('/word/header')) {
      final loaded = package.getPart(part.uri)!;
      loaded.writeText(
        loaded.readText().replaceAll(
          'w:bidi="ar-SA"',
          'w:bidi="ar-SA" w:eastAsia="ja-JP"',
        ),
      );
    }
  }
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
        id: 'rIdLanguageProject',
      );
  return package.save();
}

List<Map<String, Object?>> wordLanguageState(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  return [
    for (final paragraph in [
      ...document.sections.single.blocks.whereType<WmlParagraph>(),
      ...document.sections.single.header,
    ])
      {
        'text': paragraph.text,
        'paragraphLanguage': paragraph.properties.proofingLanguage,
        'runs': [
          for (final run in paragraph.inlines.whereType<WmlRun>())
            {
              'language': run.properties.proofingLanguage,
              'complexLanguage': run.properties.complexScriptLanguage,
              'font': run.properties.asciiFont,
              'csFont': run.properties.csFont,
              'noProof': run.properties.noProof,
            },
        ],
      },
  ];
}

Iterable<XmlElement> _elements(XmlElement root) sync* {
  yield root;
  for (final child in root.children.whereType<XmlElement>()) {
    yield* _elements(child);
  }
}

void _verifyUnownedSlots(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  var inspected = 0;
  for (final part in package.parts) {
    if (part.uri != '/word/document.xml' &&
        !part.uri.startsWith('/word/header')) {
      continue;
    }
    final xml = package.getPart(part.uri)!.readText();
    for (final element in _elements(XmlDocument.parse(xml).root!)) {
      if (element.localName != 'lang' ||
          element.namespaceUri != OfficeNamespaces.w ||
          element.getAttribute('bidi', namespaceUri: OfficeNamespaces.w) ==
              null) {
        continue;
      }
      if (element.getAttribute('bidi', namespaceUri: OfficeNamespaces.w) !=
              'ar-SA' ||
          element.getAttribute('eastAsia', namespaceUri: OfficeNamespaces.w) !=
              'ja-JP') {
        throw StateError('A language edit changed an unrelated language slot');
      }
      inspected++;
    }
  }
  if (inspected != 3) {
    throw StateError('Expected three independently retained language slots');
  }
  if (base64Encode(package.getPart('/word/vbaProject.bin')!.readBytes()) !=
      base64Encode(_project)) {
    throw StateError('Opaque embedded project changed');
  }
}

Future<Map<String, Object?>> runWordLanguageExample(String source) async {
  final input = wordLanguageInput();
  final plan = wordLanguageSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validation = await session.validate(plan);
  if (!validation.validatedOnly ||
      session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(input)) {
    throw StateError('Validation published a detached edit');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  final expected = <Map<String, Object?>>[
    {
      'text': 'Prüfbericht العربية',
      'paragraphLanguage': 'it-IT',
      'runs': [
        {
          'language': 'de-DE',
          'complexLanguage': 'ar-SA',
          'font': 'Latin Original',
          'csFont': 'Complex Original',
          'noProof': false,
        },
      ],
    },
    {
      'text': 'Report العربية',
      'paragraphLanguage': 'it-IT',
      'runs': [
        {
          'language': 'en-GB',
          'complexLanguage': 'ar-SA',
          'font': 'Latin Original',
          'csFont': 'Amiri',
          'noProof': true,
        },
      ],
    },
    {
      'text': 'En-tête العربية',
      'paragraphLanguage': 'it-IT',
      'runs': [
        {
          'language': 'fr-FR',
          'complexLanguage': 'ar-SA',
          'font': 'Calibri',
          'csFont': 'Noto Naskh Arabic',
          'noProof': true,
        },
      ],
    },
  ];
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    if (jsonEncode(wordLanguageState(saved)) != jsonEncode(expected)) {
      throw StateError(
        'Incorrect language/font state after reopen $cycle: ${jsonEncode(wordLanguageState(saved))}',
      );
    }
    _verifyUnownedSlots(saved);
    saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
  }
  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word language controls');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(recording);
  if (jsonEncode(wordLanguageState(replay.bytes)) != jsonEncode(expected)) {
    throw StateError('Recorded edits changed target identity');
  }
  _verifyUnownedSlots(replay.bytes);
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
    'nativePartSha256': {
      for (final part in selectedParts)
        part.uri: sha256
            .convert(package.getPart(part.uri)!.readBytes())
            .toString(),
    },
  };
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError('Supply WORD_LANGUAGE_CONTROLS_BAS_BASE64');
  }
  print(
    jsonEncode(
      await runWordLanguageExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
