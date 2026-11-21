import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// Both VM and JavaScript receive the complete committed BAS, not a substitute.
const _example = String.fromEnvironment('WORD_HEADERS_FOOTERS_BAS_BASE64');
const _macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
const _projectType = 'application/vnd.ms-office.vbaProject';
const _projectRelationship =
    'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
const _project = [0, 1, 42, 127, 128, 255];
const _signature = [90, 0, 91, 255];
const _custom = [6, 7, 0, 8, 254];

const wordHeaderFooterStories = [
  'header',
  'footer',
  'firstHeader',
  'firstFooter',
  'evenHeader',
  'evenFooter',
];

OfficeMacro wordHeadersFootersSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordHeadersFooters',
        source: source,
      ),
    );

OfficeMacro wordHeadersFootersPlan(String body) =>
    wordHeadersFootersSource('Sub Main()\n$body\nEnd Sub');

List<WmlParagraph> wordHeaderFooterParagraphs(
  WmlSection section,
  String story,
) => switch (story) {
  'header' => section.header,
  'footer' => section.footer,
  'firstHeader' => section.firstHeader,
  'firstFooter' => section.firstFooter,
  'evenHeader' => section.evenHeader,
  'evenFooter' => section.evenFooter,
  _ => throw ArgumentError.value(story, 'story'),
};

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

/// Every section/variant has its own two paragraphs and independent OPC part.
Uint8List wordHeadersFootersInput() {
  List<WmlParagraph> story(int section, String name) => [
    _paragraph('S$section $name 1'),
    _paragraph('S$section $name 2'),
  ];
  final document = WmlDocument(
    sections: [
      for (var i = 1; i <= 3; i++)
        WmlSection(
          blocks: [_paragraph('Body $i')],
          linkToPrevious: false,
          differentFirstPage: true,
          differentOddEven: true,
          header: story(i, 'header'),
          footer: story(i, 'footer'),
          firstHeader: story(i, 'firstHeader'),
          firstFooter: story(i, 'firstFooter'),
          evenHeader: story(i, 'evenHeader'),
          evenFooter: story(i, 'evenFooter'),
        ),
    ],
  );
  final package = OpcPackage.openBytes(WordSerializer().writeBytes(document));
  package.getPart('/word/document.xml')!.contentType = _macroType;
  package.contentTypes.setOverride('/word/document.xml', _macroType);
  package.createPart(
    '/word/vbaProject.bin',
    _projectType,
    Uint8List.fromList(_project),
  );
  package.createPart(
    '/word/vbaProjectSignature.bin',
    'application/octet-stream',
    Uint8List.fromList(_signature),
  );
  package.createPart(
    '/custom/header-footer.bin',
    'application/octet-stream',
    Uint8List.fromList(_custom),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(
        type: _projectRelationship,
        target: 'vbaProject.bin',
        id: 'rIdHeaderFooterProject',
      );
  package
      .relationshipsFor('/word/vbaProject.bin')
      .add(
        type: '${_projectRelationship}Signature',
        target: 'vbaProjectSignature.bin',
        id: 'rIdHeaderFooterSignature',
      );
  return package.save();
}

Map<String, Object?> _paragraphState(WmlParagraph paragraph) => {
  'text': paragraph.text,
  'bold': paragraph.inlines
      .whereType<WmlRun>()
      .map((r) => r.properties.bold)
      .toSet()
      .toList(),
  'italic': paragraph.inlines
      .whereType<WmlRun>()
      .map((r) => r.properties.italic)
      .toSet()
      .toList(),
  'size': paragraph.inlines
      .whereType<WmlRun>()
      .map((r) => r.properties.fontSizeHalfPoints)
      .toSet()
      .toList(),
  'color': paragraph.inlines
      .whereType<WmlRun>()
      .map((r) => r.properties.color)
      .toSet()
      .toList(),
  'alignment': paragraph.properties.justification.name,
  'before': paragraph.properties.spacingBefore,
  'after': paragraph.properties.spacingAfter,
  'tabs': [
    for (final tab in paragraph.properties.tabs)
      {
        'position': tab.position,
        'alignment': tab.alignment.name,
        'leader': tab.leader.name,
      },
  ],
};

Map<String, Object?> wordHeadersFootersState(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  return {
    'body': document.paragraphs.map((p) => p.text).toList(),
    for (var section = 0; section < document.sections.length; section++)
      for (final story in wordHeaderFooterStories)
        for (
          var paragraph = 0;
          paragraph <
              wordHeaderFooterParagraphs(
                document.sections[section],
                story,
              ).length;
          paragraph++
        )
          '${section + 1}.$story.${paragraph + 1}': _paragraphState(
            wordHeaderFooterParagraphs(
              document.sections[section],
              story,
            )[paragraph],
          ),
  };
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void assertWordHeadersFootersPackage(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  final relation = package
      .relationshipsFor('/word/document.xml')
      .items
      .singleWhere((r) => r.type == _projectRelationship);
  final signature = package
      .relationshipsFor('/word/vbaProject.bin')
      .items
      .single;
  _check(
    package.getPart('/word/document.xml')!.contentType == _macroType &&
        package.getPart('/word/vbaProject.bin')!.contentType == _projectType &&
        base64Encode(package.getPart('/word/vbaProject.bin')!.readBytes()) ==
            base64Encode(_project) &&
        base64Encode(
              package.getPart('/word/vbaProjectSignature.bin')!.readBytes(),
            ) ==
            base64Encode(_signature) &&
        base64Encode(
              package.getPart('/custom/header-footer.bin')!.readBytes(),
            ) ==
            base64Encode(_custom) &&
        relation.id == 'rIdHeaderFooterProject' &&
        relation.target == 'vbaProject.bin' &&
        signature.id == 'rIdHeaderFooterSignature' &&
        signature.target == 'vbaProjectSignature.bin' &&
        signature.type == '${_projectRelationship}Signature',
    'A header/footer edit changed an opaque payload or its relationship',
  );
}

/// Independently specified expected edits; all 30 other paragraphs stay exact.
void assertWordHeadersFootersExample(Uint8List bytes, {int repetitions = 1}) {
  final expected = wordHeadersFootersState(wordHeadersFootersInput());
  void edit(String key, Map<String, Object?> changes) {
    expected[key] = {...expected[key]! as Map<String, Object?>, ...changes};
  }

  edit('1.header.1', {
    'text': '${List.filled(repetitions, 'Report: ').join()}S1 header 1',
    'bold': [true],
    'alignment': 'center',
  });
  edit('1.footer.2', {
    'text': '${List.filled(repetitions, 'Page: ').join()}S1 footer 2',
    'size': [20],
  });
  edit('2.firstHeader.1', {
    'italic': [true],
  });
  edit('2.evenFooter.2', {
    'text': '${List.filled(repetitions, 'Appendix: ').join()}S2 evenFooter 2',
    'after': 6.0,
    'tabs': [
      {'position': 36.0, 'alignment': 'center', 'leader': 'dot'},
    ],
  });
  edit('1.evenHeader.2', {'before': 12.0});
  edit('2.firstFooter.1', {
    'color': ['1F4E79'],
  });
  final actual = wordHeadersFootersState(bytes);
  _check(
    jsonEncode(actual) == jsonEncode(expected),
    'Wrong body/story state: ${jsonEncode(actual)}',
  );
  assertWordHeadersFootersPackage(bytes);
}

Future<Map<String, Object?>> runWordHeadersFootersExample(String source) async {
  final input = wordHeadersFootersInput();
  final original = base64Encode(input);
  final plan = wordHeadersFootersSource(source);
  // This explicit BAS contract is independent of compiler lookup/dispatch tables.
  const expected = <(String, String, int, int, Map<String, Object?>)>[
    (
      'docx.replaceText',
      'header',
      0,
      0,
      {'start': 0, 'end': 0, 'text': 'Report: '},
    ),
    ('docx.runFormat', 'header', 0, 0, {'bold': true}),
    ('docx.paragraphFormat', 'header', 0, 0, {'alignment': 'center'}),
    (
      'docx.replaceText',
      'footer',
      0,
      1,
      {'start': 0, 'end': 0, 'text': 'Page: '},
    ),
    ('docx.runFormat', 'footer', 0, 1, {'size': 10}),
    ('docx.runFormat', 'firstHeader', 1, 0, {'italic': true}),
    (
      'docx.replaceText',
      'evenFooter',
      1,
      1,
      {'start': 0, 'end': 0, 'text': 'Appendix: '},
    ),
    ('docx.paragraphFormat', 'evenFooter', 1, 1, {'after': 6}),
    (
      'docx.tabStop',
      'evenFooter',
      1,
      1,
      {'position': 36, 'alignment': 'center', 'leader': 'dot'},
    ),
    ('docx.paragraphFormat', 'evenHeader', 0, 1, {'before': 12}),
    ('docx.runFormat', 'firstFooter', 1, 0, {'color': '1F4E79'}),
  ];
  _check(plan.steps.length == expected.length, 'Wrong example operation count');
  for (var i = 0; i < expected.length; i++) {
    final (tool, story, section, paragraph, fields) = expected[i];
    final arguments = {
      'story': story,
      'section': section,
      'paragraph': paragraph,
      ...fields,
    };
    final step = plan.steps[i];
    _check(
      step.tool == tool &&
          step.arguments.length == arguments.length &&
          arguments.entries.every((e) => step.arguments[e.key] == e.value),
      'Unexpected header/footer example operation $i: ${step.toJson()}',
    );
  }
  final guard = (await WordPackagePreservation.capture(input, 'stories.docm'))!;
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == 11 &&
        session.revision == 0 &&
        base64Encode(session.bytes) == original,
    'Dry-run published an edit',
  );
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  _check(
    result.completedSteps == 11 &&
        result.revision == 1 &&
        base64Encode(input) == original,
    'Example did not publish exactly one transaction',
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordHeadersFootersExample(saved);
    await guard.validateSaved(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  await session.run(plan);
  assertWordHeadersFootersExample(session.bytes, repetitions: 2);
  await guard.validateSaved(session.bytes);
  return {
    'operations': expected.length,
    'addressedStoryVariants': 6,
    'firstRunRevision': result.revision,
    'repeatedRevision': session.revision,
    'additionalReopens': 2,
    'opaquePayloadsPreserved': true,
    'untouchedBody': ['Body 1', 'Body 2', 'Body 3'],
    'firstHeader': 'Report: S1 header 1',
    'evenFooter': 'Appendix: S2 evenFooter 2',
  };
}

Future<Map<String, Object?>> runWordHeadersFootersRollback() async {
  final input = wordHeadersFootersInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Header/footer rollback');
  final plan = wordHeadersFootersPlan('''
ThisDocument.Paragraphs(1).Range.InsertBefore "Temporary: "
ThisDocument.Sections(2).Headers(wdHeaderFooterPrimary).Range.Paragraphs(99).Range.Font.Bold = True
''');
  for (final action in [session.validate, session.run]) {
    try {
      await action(plan);
      throw StateError('Missing story paragraph unexpectedly succeeded');
    } on OfficeMacroException catch (error) {
      _check(
        error.code == 'operation_failed' &&
            error.stepIndex == 1 &&
            error.tool == 'docx.runFormat',
        'Failure did not identify the native story edit',
      );
    }
    _check(
      session.revision == 0 &&
          base64Encode(session.bytes) == base64Encode(input),
      'Failed story edit published earlier body edits',
    );
  }
  _check(
    session.stopRecording().steps.isEmpty,
    'Failed story edits were recorded',
  );
  return {
    'failedStep': 1,
    'validateAndRunRollback': true,
    'recordingUnchanged': true,
  };
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError(
      'Supply WORD_HEADERS_FOOTERS_BAS_BASE64 from the committed example',
    );
  }
  final source = utf8.decode(base64Decode(_example));
  print(
    jsonEncode({
      'example': await runWordHeadersFootersExample(source),
      'rollback': await runWordHeadersFootersRollback(),
    }),
  );
}
