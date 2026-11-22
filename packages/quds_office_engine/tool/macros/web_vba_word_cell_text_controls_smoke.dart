import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_table_cells_smoke.dart' as fixture;

const _example = String.fromEnvironment('WORD_CELL_TEXT_BAS_BASE64');
const _w = OfficeNamespaces.w;

// Establish the same ordinary control save as the table-formatting fixture:
// the first read/save materializes an inherited second-section header.
Uint8List wordCellTextControlInput({bool macroEnabled = true}) =>
    WordSerializer().writeBytes(
      WordDeserializer().readBytes(
        fixture.wordTableInput(macroEnabled: macroEnabled),
      ),
    );

OfficeMacro wordCellTextControlSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordTableTextControls',
        source: source,
      ),
    );

OfficeMacro wordCellTextControlPlan(String body) =>
    wordCellTextControlSource('Sub Main()\n$body\nEnd Sub');

List<Map<String, Object?>> wordCellTextControlState(Uint8List bytes) => [
  for (final section in WordDeserializer().readBytes(bytes).sections)
    for (final table in section.blocks.whereType<WmlTable>())
      for (final row in table.rows)
        for (final cell in row.cells)
          for (final paragraph in cell.blocks.whereType<WmlParagraph>())
            {
              'text': paragraph.text,
              'runs': [
                for (final run in paragraph.inlines.whereType<WmlRun>())
                  {
                    'text': run.text,
                    'language': run.properties.proofingLanguage,
                    'complexLanguage': run.properties.complexScriptLanguage,
                    'noProof': run.properties.noProof,
                    'highlight': run.properties.highlight,
                    'bold': run.properties.bold,
                    'italic': run.properties.italic,
                    'font': run.properties.asciiFont,
                    'size': run.properties.fontSizeHalfPoints,
                    'color': run.properties.color,
                  },
              ],
            },
];

List<XmlElement> _elements(XmlElement root, String name) => [
  for (final child in root.childElements) ...[
    if (child.localName == name && child.namespaceUri == _w) child,
    ..._elements(child, name),
  ],
];

Object _xml(XmlNode node) => switch (node) {
  XmlElement() => {
    'name': [node.namespaceUri, node.localName],
    'attributes': {
      for (final attribute
          in (node.attributes
              .where(
                (attribute) =>
                    attribute.prefix != 'xmlns' &&
                    !(attribute.prefix.isEmpty &&
                        attribute.localName == 'xmlns'),
              )
              .toList()
            ..sort(
              (a, b) => '${a.namespaceUri}:${a.localName}'.compareTo(
                '${b.namespaceUri}:${b.localName}',
              ),
            )))
        '${attribute.namespaceUri}:${attribute.localName}': attribute.value,
    },
    'children': [for (final child in node.children) _xml(child)],
  },
  XmlText() => {'text': node.text},
  XmlCdata() => {'cdata': node.text},
  XmlComment() => {'comment': node.text},
};

Object _coreMetadata(String source) {
  final root = XmlDocument.parse(source).root!;
  for (final modified in root.childrenNamed(
    'modified',
    namespaceUri: 'http://purl.org/dc/terms/',
  )) {
    if (modified.childElements.isNotEmpty ||
        DateTime.tryParse(modified.text) == null) {
      throw StateError('Expected a scalar modification timestamp');
    }
    modified.children.clear();
    modified.addText('save timestamp');
  }
  return _xml(root);
}

/// Expanded-name XML comparison ignores redundant namespace bindings only.
/// The report changes first-table text/runs, never paragraph or table layout.
String wordCellTextControlUntouched(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  final root = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!;
  final body = root.childrenNamed('body', namespaceUri: _w).single;
  return jsonEncode({
    'otherTable': _xml(_elements(root, 'tbl').last),
    'body': [
      for (final paragraph in body.childrenNamed('p', namespaceUri: _w))
        _xml(paragraph),
    ],
    for (final name in ['tblPr', 'tblGrid', 'trPr', 'tcPr', 'pPr', 'sectPr'])
      name: [for (final node in _elements(root, name)) _xml(node)],
    'parts': {
      for (final part in package.parts)
        if (part.uri != '/word/document.xml')
          part.uri: part.uri == '/docProps/core.xml'
              ? _coreMetadata(package.getPart(part.uri)!.readText())
              : base64Encode(package.getPart(part.uri)!.readBytes()),
    },
  });
}

void _assertReport(Uint8List bytes) {
  final cells = wordCellTextControlState(bytes);
  const labels = ['Product', 'Artikel', 'SKU-042', 'Prêt 😀'];
  const languages = ['en-US', 'de-DE', 'en-US', 'fr-FR'];
  const highlights = <String?>[null, 'FFFF00', null, '00FF00'];
  if (cells.length != 5) throw StateError('Cell count changed');
  for (var index = 0; index < labels.length; index++) {
    final cell = cells[index];
    final runs = cell['runs']! as List<Map<String, Object?>>;
    if (cell['text'] != labels[index] ||
        runs.isEmpty ||
        runs.any(
          (run) =>
              run['language'] != languages[index] ||
              run['noProof'] != (index == 2) ||
              run['highlight'] != highlights[index] ||
              run['bold'] != true ||
              run['font'] != 'Courier New' ||
              run['size'] != 24 ||
              run['color'] != '1F4E79',
        )) {
      throw StateError(
        'Cell text controls or retained formatting differ at $index',
      );
    }
  }
}

Future<Map<String, Object?>> runWordCellTextControlsExample(
  String source, {
  bool macroEnabled = true,
}) async {
  final input = wordCellTextControlInput(macroEnabled: macroEnabled);
  final untouched = wordCellTextControlUntouched(input);
  final plan = wordCellTextControlSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final preview = await session.validate(plan);
  if (!preview.validatedOnly ||
      preview.completedSteps != plan.steps.length ||
      session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(input)) {
    throw StateError('Validation published a change');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    _assertReport(saved);
    if (wordCellTextControlUntouched(saved) != untouched) {
      throw StateError(
        'Text controls changed unrelated layout, owners or parts',
      );
    }
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  final state = jsonEncode(wordCellTextControlState(saved));
  await session.run(plan);
  if (jsonEncode(wordCellTextControlState(session.bytes)) != state) {
    throw StateError('Repeated explicit values changed the saved result');
  }
  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word cell text controls');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recording.encode()));
  if (jsonEncode(wordCellTextControlState(replay.bytes)) != state ||
      wordCellTextControlUntouched(replay.bytes) != untouched) {
    throw StateError('Recorded controls changed their target or effects');
  }
  final invalid = wordCellTextControlPlan('''
ActiveDocument.Tables(1).Cell(1, 1).Range.NoProofing = True
ActiveDocument.Tables(1).Cell(1, 1).Range.LanguageID = wdGerman
ActiveDocument.Tables(2).Cell(2, 1).Range.HighlightColorIndex = wdRed
''');
  replay.startRecording('Refused cell text controls');
  final before = base64Encode(replay.bytes);
  for (final action in [replay.validate, replay.run]) {
    var refused = false;
    try {
      await action(invalid);
    } on OfficeMacroException catch (error) {
      refused = error.stepIndex == 2;
    }
    if (!refused ||
        replay.revision != 1 ||
        base64Encode(replay.bytes) != before) {
      throw StateError('A late missing cell published partial text controls');
    }
  }
  if (replay.stopRecording().steps.isNotEmpty) {
    throw StateError('Refused text controls entered the recording');
  }
  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'untouchedLayoutAndParts': true,
    'opaqueVbaPreserved': macroEnabled,
    'lateRollback': true,
    'state': wordCellTextControlState(saved),
  };
}

Future<void> main() async {
  if (_example.isEmpty) throw StateError('Supply WORD_CELL_TEXT_BAS_BASE64');
  print(
    jsonEncode(
      await runWordCellTextControlsExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
