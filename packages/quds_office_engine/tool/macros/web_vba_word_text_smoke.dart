import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _example = String.fromEnvironment('WORD_TEXT_BAS_BASE64');
const _project = <int>[0, 17, 42, 128, 255];

const wordTextExpected = <String>[
  'FINAL summary: body one',
  'Annual 😀 report | prepared for review: body two',
  'INTERNAL: report header',
];

OfficeMacro wordTextSource(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordTextReport',
    source: source,
  ),
);

OfficeMacro wordTextPlan(String body) =>
    wordTextSource('Sub Main()\n$body\nEnd Sub');

Uint8List wordTextInput() {
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(
            inlines: [
              WmlRun(
                text: 'body ',
                properties: WmlRunProps(italic: true, asciiFont: 'Courier New'),
              ),
              WmlRun(
                text: 'one',
                properties: WmlRunProps(color: '9C0006'),
              ),
            ],
          ),
          WmlParagraph(inlines: [WmlRun(text: 'body two')]),
        ],
        header: [
          WmlParagraph(inlines: [WmlRun(text: 'report header')]),
        ],
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
        id: 'rIdTextProject',
      );
  return package.save();
}

List<String> wordTextState(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  return [
    for (final paragraph
        in document.sections.single.blocks.whereType<WmlParagraph>())
      paragraph.text,
    document.sections.single.header.single.text,
  ];
}

void _verify(Uint8List bytes, int cycle) {
  if (jsonEncode(wordTextState(bytes)) != jsonEncode(wordTextExpected)) {
    throw StateError('Incorrect source text processing after reopen $cycle');
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
      )) {
    throw StateError('Prefix insertion lost existing rich formatting');
  }
  final second = document.sections.single.blocks
      .whereType<WmlParagraph>()
      .elementAt(1);
  if (!second.inlines.whereType<WmlRun>().every(
        (run) => run.properties.color == '1F4E79',
      ) ||
      !document.sections.single.header.single.inlines.whereType<WmlRun>().every(
        (run) => run.properties.italic == true,
      )) {
    throw StateError('Text processing changed explicit formatting targets');
  }
  final package = OpcPackage.openBytes(bytes);
  if (base64Encode(package.getPart('/word/vbaProject.bin')!.readBytes()) !=
      base64Encode(_project)) {
    throw StateError('Opaque VBA project changed');
  }
}

Future<Map<String, Object?>> runWordTextExample(String source) async {
  final input = wordTextInput();
  final plan = wordTextSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validation = await session.validate(plan);
  if (!validation.validatedOnly ||
      session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(input)) {
    throw StateError('Validation published the detached document');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    _verify(saved, cycle);
    saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
  }
  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word source text report');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(recording);
  _verify(replay.bytes, 0);
  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'opaqueVbaPreserved': true,
    'richFormattingPreserved': true,
    'text': wordTextExpected,
  };
}

Future<void> main() async {
  if (_example.isEmpty) throw StateError('Supply WORD_TEXT_BAS_BASE64');
  print(
    jsonEncode(await runWordTextExample(utf8.decode(base64Decode(_example)))),
  );
}
