import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_table_cells_smoke.dart' as fixture;

const _example = String.fromEnvironment('WORD_CELL_PARAGRAPHS_BAS_BASE64');
const _w = OfficeNamespaces.w;
const _x = 'urn:quds:cell-paragraph-example';

OfficeMacro wordCellParagraphSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordCellParagraphs',
        source: source,
      ),
    );

OfficeMacro wordCellParagraphPlan(String body) =>
    wordCellParagraphSource('Option Explicit\nSub Main()\n$body\nEnd Sub');

/// An existing table with paragraph/native metadata, an empty cell, native
/// styles, and an inert VBA project. The initial ordinary save is the baseline
/// for subsequent preservation checks; it materializes inherited headers.
Uint8List wordCellParagraphInput({bool macroEnabled = true}) {
  final package = OpcPackage.openBytes(
    fixture.wordTableInput(macroEnabled: macroEnabled),
  );
  final document = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  );
  final root = document.root!;
  final cells = _elements(root, 'tc');
  final first = _elements(cells[0], 'p').single;
  final properties = first.firstChild('pPr', namespaceUri: _w)!;
  properties.addChild(
    XmlDocument.parse('''
<w:pStyle xmlns:w="$_w" xmlns:x="$_x" w:val="NormalNative" x:keep="style"><x:annotation x:token="retained"/></w:pStyle>
''').root!,
  );
  properties.addChild(
    XmlDocument.parse('''
<w:shd xmlns:w="$_w" xmlns:x="$_x" w:val="clear" w:fill="DDEEFF" x:keep="shading"/>
''').root!,
  );
  properties.addChild(
    XmlDocument.parse('''
<x:keep xmlns:x="$_x" x:token="paragraph"/>
''').root!,
  );
  // Empty text is still one native paragraph. Formatting must not add a run.
  final empty = _elements(cells[2], 'p').single;
  empty.children.removeWhere(
    (node) => node is XmlElement && node.localName == 'r',
  );
  package.getPart('/word/document.xml')!.writeText(document.toXmlString());
  final styles =
      package.getPart('/word/styles.xml') ??
      package.createPart('/word/styles.xml', OfficeContentTypes.wordStyles);
  styles.writeText('''
<w:styles xmlns:w="$_w" xmlns:x="$_x">
<w:style w:type="paragraph" w:styleId="NormalNative" w:default="1"><w:name w:val="Normal"/><w:pPr><w:shd w:val="clear" w:fill="CCDDFF"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="LabelNative" w:customStyle="1"><w:name w:val="Report Label"/><w:basedOn w:val="NormalNative"/><w:rPr><w:b w:val="0"/><w:color w:val="000000"/></w:rPr><x:definition x:token="retained"/></w:style>
<w:style w:type="paragraph" w:styleId="HeadingNative"><w:name w:val="heading 1"/><w:basedOn w:val="NormalNative"/><w:pPr><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:sz w:val="32"/></w:rPr></w:style>
</w:styles>
''');
  final relationships = package.relationshipsFor('/word/document.xml');
  if (relationships.byType(RelationshipTypes.styles).isEmpty) {
    relationships.add(type: RelationshipTypes.styles, target: 'styles.xml');
  }
  return WordSerializer().writeBytes(
    WordDeserializer().readBytes(package.save()),
  );
}

List<WmlParagraph> wordCellParagraphs(WmlDocument document) => [
  for (final section in document.sections)
    for (final table in section.blocks.whereType<WmlTable>())
      for (final row in table.rows)
        for (final cell in row.cells) cell.blocks.single as WmlParagraph,
];

List<Map<String, Object?>> wordCellParagraphState(Uint8List bytes) => [
  for (final paragraph in wordCellParagraphs(
    WordDeserializer().readBytes(bytes),
  ))
    {
      'text': paragraph.text,
      'style': paragraph.properties.styleId,
      'shading': paragraph.properties.shadingFill,
      'after': paragraph.properties.spacingAfter,
      'alignment': paragraph.properties.justification.name,
      'runs': [
        for (final run in paragraph.inlines.whereType<WmlRun>())
          {
            'text': run.text,
            'bold': run.properties.bold,
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
                (a) =>
                    a.prefix != 'xmlns' &&
                    !(a.prefix.isEmpty && a.localName == 'xmlns'),
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

/// Independently snapshots unselected paragraphs, cells, table geometry,
/// headers and opaque parts using expanded XML names, not serializer spacing.
String wordCellParagraphUntouched(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  final root = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!;
  final body = root.firstChild('body', namespaceUri: _w)!;
  return jsonEncode({
    'otherCells': [
      for (final cell in _elements(root, 'tc').skip(3)) _xml(cell),
    ],
    'body': [
      for (final p in body.childrenNamed('p', namespaceUri: _w)) _xml(p),
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

void assertWordCellParagraphExample(Uint8List bytes) {
  final paragraphs = wordCellParagraphs(WordDeserializer().readBytes(bytes));
  if (paragraphs.length != 5 ||
      paragraphs.map((p) => p.text).join('|') !=
          'first 0/0|first 0/1||first 1/1|second 0/0') {
    throw StateError('Paragraph selection changed cell text or structure');
  }
  const styles = ['LabelNative', 'HeadingNative', 'NormalNative'];
  const shades = <String?>['1F4E79', 'FFFF00', null];
  for (var index = 0; index < 3; index++) {
    final paragraph = paragraphs[index];
    if (paragraph.properties.styleId != styles[index] ||
        paragraph.properties.shadingFill != shades[index] ||
        paragraph.properties.justification != WmlJustification.center ||
        paragraph.properties.spacingAfter != (index == 0 ? 6 : 3)) {
      throw StateError('Selected paragraph formatting differs at $index');
    }
  }
  if (paragraphs[2].inlines.isNotEmpty) {
    throw StateError('Formatting an empty paragraph inserted content');
  }
  for (var index = 0; index < 2; index++) {
    for (final run in paragraphs[index].inlines.whereType<WmlRun>()) {
      if (!run.properties.bold ||
          run.properties.asciiFont != 'Courier New' ||
          run.properties.fontSizeHalfPoints != 24 ||
          run.properties.color != (index == 0 ? 'FFFFFF' : '1F4E79')) {
        throw StateError('A paragraph style discarded direct run formatting');
      }
    }
  }
  final root = XmlDocument.parse(
    OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
  ).root!;
  final cells = _elements(root, 'tc');
  final properties = _elements(cells.first, 'pPr').single;
  final style = properties.firstChild('pStyle', namespaceUri: _w)!;
  final shading = properties.firstChild('shd', namespaceUri: _w)!;
  if (style.getAttribute('keep', namespaceUri: _x) != 'style' ||
      style
              .firstChild('annotation', namespaceUri: _x)
              ?.getAttribute('token', namespaceUri: _x) !=
          'retained' ||
      shading.getAttribute('keep', namespaceUri: _x) != 'shading' ||
      properties
              .firstChild('keep', namespaceUri: _x)
              ?.getAttribute('token', namespaceUri: _x) !=
          'paragraph') {
    throw StateError('Paragraph edits discarded foreign native metadata');
  }
  final emptyShading = _elements(
    cells[2],
    'pPr',
  ).single.firstChild('shd', namespaceUri: _w)!;
  if (emptyShading.getAttribute('fill', namespaceUri: _w) != 'auto') {
    throw StateError('Automatic shading did not override the inherited fill');
  }
}

Future<Map<String, Object?>> runWordCellParagraphExample(
  String source, {
  bool macroEnabled = true,
}) async {
  final input = wordCellParagraphInput(macroEnabled: macroEnabled);
  final before = base64Encode(input);
  final untouched = wordCellParagraphUntouched(input);
  final plan = wordCellParagraphSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final preview = await session.validate(plan);
  if (!preview.validatedOnly ||
      preview.completedSteps != 8 ||
      session.revision != 0 ||
      base64Encode(session.bytes) != before) {
    throw StateError('Validation changed the document or operation count');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordCellParagraphExample(saved);
    if (wordCellParagraphUntouched(saved) != untouched) {
      throw StateError(
        'Paragraph edits changed unrelated cells, layout or parts',
      );
    }
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  final state = jsonEncode(wordCellParagraphState(saved));
  await session.run(plan);
  if (jsonEncode(wordCellParagraphState(session.bytes)) != state) {
    throw StateError('Repeated explicit formatting changed the saved result');
  }
  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  recorder.startRecording('Word cell paragraph formatting');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recording.encode()));
  assertWordCellParagraphExample(replay.bytes);
  if (wordCellParagraphUntouched(replay.bytes) != untouched ||
      jsonEncode(wordCellParagraphState(replay.bytes)) != state) {
    throw StateError('Recorded paragraph formatting changed its targets');
  }
  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'untouchedLayoutAndParts': true,
    'opaqueVbaPreserved': macroEnabled,
    'state': wordCellParagraphState(saved),
  };
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError('Supply WORD_CELL_PARAGRAPHS_BAS_BASE64');
  }
  print(
    jsonEncode(
      await runWordCellParagraphExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
