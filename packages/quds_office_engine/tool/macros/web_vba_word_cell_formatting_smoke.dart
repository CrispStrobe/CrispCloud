import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_table_cells_smoke.dart' as fixture;

const _example = String.fromEnvironment('WORD_CELL_FORMAT_BAS_BASE64');
const _w = OfficeNamespaces.w;

// Establish the serializer's ordinary control-save state: its first read/save
// materializes the inherited second-section header even without a macro.
// Check XML semantics, opaque part bytes and all core metadata except the
// ordinary save timestamp after subsequent formatting.
Uint8List wordCellFormattingInput() => WordSerializer().writeBytes(
  WordDeserializer().readBytes(fixture.wordTableInput()),
);

OfficeMacro wordCellFormattingSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordTableFormatting',
        source: source,
      ),
    );

List<WmlTable> _tables(WmlDocument document) => [
  for (final section in document.sections)
    ...section.blocks.whereType<WmlTable>(),
];

List<Map<String, Object?>> wordCellFormattingState(Uint8List bytes) => [
  for (final table in _tables(WordDeserializer().readBytes(bytes)))
    for (final row in table.rows)
      for (final cell in row.cells)
        for (final paragraph in cell.blocks.whereType<WmlParagraph>())
          {
            'text': paragraph.text,
            'alignment': paragraph.properties.justification.name,
            'before': paragraph.properties.spacingBefore,
            'after': paragraph.properties.spacingAfter,
            'keepTogether': paragraph.properties.keepTogether,
            'line': paragraph.properties.lineSpacing,
            'lineRule': paragraph.properties.lineSpacingRule.name,
            'tabs': [
              for (final tab in paragraph.properties.tabs)
                {
                  'position': tab.position,
                  'alignment': tab.alignment.name,
                  'leader': tab.leader.name,
                },
            ],
            'runs': [
              for (final run in paragraph.inlines.whereType<WmlRun>())
                {
                  'text': run.text,
                  'font': run.properties.asciiFont,
                  'size': run.properties.fontSizeHalfPoints,
                  'bold': run.properties.bold,
                  'allCaps': run.properties.allCaps,
                  'color': run.properties.color,
                },
            ],
          },
];

void assertWordCellFormattingOutput(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  final tables = _tables(document);
  if (tables.length != 2 ||
      tables.first.rows.length != 2 ||
      tables.first.rows.any((row) => row.cells.length != 2) ||
      tables.last.rows.length != 1 ||
      tables.last.rows.single.cells.length != 1) {
    throw StateError('Cell formatting changed table structure');
  }
  const labels = ['Item', 'Quantity', 'Quds report', '42'];
  var index = 0;
  for (final row in tables.first.rows) {
    for (final cell in row.cells) {
      final paragraph = cell.blocks.single as WmlParagraph;
      final heading = index < 2;
      final props = paragraph.properties;
      if (paragraph.text != labels[index++] ||
          props.justification != WmlJustification.left ||
          props.spacingBefore != 0 ||
          props.spacingAfter != 4 ||
          !props.keepTogether ||
          props.lineSpacingRule != WmlLineSpacingRule.exact ||
          props.lineSpacing != 14 ||
          props.tabs.length != 1 ||
          props.tabs.single.position != 72 ||
          props.tabs.single.alignment != WmlTabAlignment.right ||
          props.tabs.single.leader != WmlTabLeader.dot) {
        throw StateError('Cell text or paragraph formatting is incorrect');
      }
      final runs = paragraph.inlines.whereType<WmlRun>().toList();
      if (runs.isEmpty ||
          runs.any(
            (run) =>
                run.properties.asciiFont != 'Calibri' ||
                run.properties.fontSizeHalfPoints != 22 ||
                run.properties.bold != heading ||
                run.properties.allCaps != heading ||
                run.properties.color != '1F4E79',
          )) {
        throw StateError('Cell font formatting is incorrect');
      }
    }
  }
  final root = _root(bytes);
  final firstTable = _elements(root, 'tbl').first;
  for (final cell in _elements(firstTable, 'tc')) {
    final spacing = _elements(cell, 'spacing').single;
    if (spacing.getAttribute('line', namespaceUri: _w) != '280' ||
        spacing.getAttribute('lineRule', namespaceUri: _w) != 'exact' ||
        spacing.getAttribute('after', namespaceUri: _w) != '80') {
      throw StateError('Cell spacing did not preserve exact native twips');
    }
  }
}

XmlElement _root(Uint8List bytes) => XmlDocument.parse(
  OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
).root!;

List<XmlElement> _elements(XmlElement root, String name) => [
  for (final child in root.childElements) ...[
    if (child.localName == name && child.namespaceUri == _w) child,
    ..._elements(child, name),
  ],
];

// Only namespace declaration placement and prefixes are nonsemantic here.
// All expanded names, substantive attributes and ordered children are retained.
Object _xmlValue(XmlNode node) => switch (node) {
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
    'children': [for (final child in node.children) _xmlValue(child)],
  },
  XmlText() => {'text': node.text},
  XmlCdata() => {'cdata': node.text},
  XmlComment() => {'comment': node.text},
};

String _xml(XmlElement element) => jsonEncode(_xmlValue(element));

String _coreMetadata(String source) {
  final root = XmlDocument.parse(source).root!;
  // Saves refresh dcterms:modified. Every other metadata value, attribute and
  // node remains part of the preservation comparison.
  for (final modified in root.childrenNamed(
    'modified',
    namespaceUri: 'http://purl.org/dc/terms/',
  )) {
    if (modified.childElements.isNotEmpty ||
        DateTime.tryParse(modified.text) == null) {
      throw StateError('A saved modification timestamp is not a scalar date');
    }
    modified.children.clear();
    modified.addText('save timestamp');
  }
  return _xml(root);
}

String _untouched(Uint8List bytes) {
  final root = _root(bytes);
  final body = root.childrenNamed('body', namespaceUri: _w).single;
  final package = OpcPackage.openBytes(bytes);
  return jsonEncode({
    'otherTable': _xml(_elements(root, 'tbl').last),
    'body': [
      for (final paragraph in body.childrenNamed('p', namespaceUri: _w))
        _xml(paragraph),
    ],
    for (final name in ['tblPr', 'tblGrid', 'trPr', 'tcPr', 'sectPr'])
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

Future<Map<String, Object?>> runWordCellFormattingExample(String source) async {
  final input = wordCellFormattingInput();
  final originalPackage = OpcPackage.openBytes(input);
  if (base64Encode(
            originalPackage.getPart('/word/vbaProject.bin')!.readBytes(),
          ) !=
          base64Encode(Uint8List.fromList([0, 7, 42, 128, 255])) ||
      originalPackage.getPart('/customXml/table.xml')!.readBytes().isEmpty) {
    throw StateError('Cell formatting fixture lost its opaque payloads');
  }
  final unchanged = _untouched(input);
  final plan = wordCellFormattingSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final preview = await session.validate(plan);
  if (!preview.validatedOnly ||
      preview.completedSteps != plan.steps.length ||
      session.revision != 0 ||
      base64Encode(session.bytes) != base64Encode(input)) {
    throw StateError('Cell-formatting validation published changes');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordCellFormattingOutput(saved);
    if (_untouched(saved) != unchanged) {
      throw StateError('Cell formatting changed an untargeted owner or part');
    }
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  final state = jsonEncode(wordCellFormattingState(session.bytes));
  await session.run(plan);
  if (jsonEncode(wordCellFormattingState(session.bytes)) != state ||
      _untouched(session.bytes) != unchanged) {
    throw StateError('Cell-formatting replay changed its saved result');
  }

  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word table formatting');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recording.encode()));
  if (jsonEncode(wordCellFormattingState(replay.bytes)) != state ||
      _untouched(replay.bytes) != unchanged) {
    throw StateError('Recorded cell formatting changed its target or effects');
  }

  final invalid = wordCellFormattingSource('''
Sub Main()
  ActiveDocument.Tables(1).Cell(1, 1).Range.Text = "Do not publish"
  ActiveDocument.Tables(1).Cell(1, 1).Range.Font.ColorIndex = wdRed
  ActiveDocument.Tables(2).Cell(2, 1).Range.ParagraphFormat.Space2
End Sub
''');
  replay.startRecording('Refused table formatting');
  for (final action in [replay.validate, replay.run]) {
    final before = base64Encode(replay.bytes);
    final revision = replay.revision;
    var refused = false;
    try {
      await action(invalid);
    } on OfficeMacroException catch (error) {
      refused = error.stepIndex == 2;
    }
    if (!refused ||
        replay.revision != revision ||
        base64Encode(replay.bytes) != before) {
      throw StateError('A late missing cell published partial formatting');
    }
  }
  if (replay.stopRecording().steps.isNotEmpty) {
    throw StateError('Refused cell formatting entered the recording');
  }
  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'untargetedXmlSemanticsPreserved': true,
    'opaquePartBytesPreserved': true,
    'coreMetadataPreservedExceptSaveTimestamp': true,
    'opaqueVbaPreserved': true,
    'lateRollback': true,
    'state': wordCellFormattingState(saved),
  };
}

Future<void> main() async {
  if (_example.isEmpty) throw StateError('Supply WORD_CELL_FORMAT_BAS_BASE64');
  print(
    jsonEncode(
      await runWordCellFormattingExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
