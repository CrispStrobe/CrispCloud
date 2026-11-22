import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_cell_paragraphs_smoke.dart' as fixture;

const _example = String.fromEnvironment('WORD_CELL_PREFIX_BAS_BASE64');
const _w = OfficeNamespaces.w;
const _expected = <String>[
  'Review\tStatus\tfirst 0/0',
  'Owner\tPeer\tfirst 0/1',
  'New\t',
  'first 1/1',
  'second 0/0',
];

OfficeMacro wordCellPrefixSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordCellPrefix',
        source: source,
      ),
    );

OfficeMacro wordCellPrefixPlan(String body) =>
    wordCellPrefixSource('Option Explicit\nSub Main()\n$body\nEnd Sub');

/// Two existing tables, a rich first cell, an empty cell, retained foreign
/// paragraph properties, custom XML, headers and an optional inert VBA part.
/// One ordinary save establishes the source-preservation baseline.
Uint8List wordCellPrefixInput({bool macroEnabled = true}) {
  final document = WordDeserializer().readBytes(
    fixture.wordCellParagraphInput(macroEnabled: macroEnabled),
  );
  final first = fixture.wordCellParagraphs(document).first;
  final initial = first.inlines.single as WmlRun;
  initial.text = 'first ';
  initial.properties
    ..bold = false
    ..italic = true
    ..color = '17365D'
    ..kerningHalfPoints = 0;
  first.inlines.add(
    WmlRun(
      text: '0/0',
      properties: WmlRunProps(
        color: 'A23B35',
        asciiFont: 'Georgia',
        fontSizeHalfPoints: 28,
        kerningHalfPoints: 24,
      ),
    ),
  );
  return WordSerializer().writeBytes(document);
}

List<Map<String, Object?>> wordCellPrefixState(Uint8List bytes) => [
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

List<XmlElement> _elements(XmlElement root, String name) => [
  for (final child in root.childElements) ...[
    if (child.namespaceUri == _w && child.localName == name) child,
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

/// Prefixing changes only selected runs. Compare all paragraph properties,
/// untouched cells/body paragraphs, geometry, headers and opaque package parts.
String wordCellPrefixUntouched(Uint8List bytes, {int selectedCellCount = 3}) {
  final root = XmlDocument.parse(
    OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
  ).root!;
  return jsonEncode({
    'layoutAndParts': fixture.wordCellParagraphUntouched(
      bytes,
      selectedCellCount: selectedCellCount,
    ),
    'paragraphProperties': [for (final p in _elements(root, 'pPr')) _xml(p)],
  });
}

void assertWordCellPrefixExample(Uint8List bytes) {
  final cells = fixture.wordCellParagraphs(WordDeserializer().readBytes(bytes));
  if (jsonEncode(cells.map((cell) => cell.text).toList()) !=
      jsonEncode(_expected)) {
    throw StateError(
      'Prefix insertion changed the selected text or a neighbor',
    );
  }
  final first = cells.first;
  // Both inserted labels and the original first span retain italic styling.
  // The final Bold assignment must cover the prefixes and both original spans.
  for (var index = 0; index < first.text.length; index++) {
    final props = WmlRunEdit.propsAt(first, index);
    final leading = index < first.text.length - 3;
    if (!props.bold ||
        props.italic != leading ||
        props.color != (leading ? '17365D' : 'A23B35') ||
        props.asciiFont != (leading ? 'Courier New' : 'Georgia') ||
        props.fontSizeHalfPoints != (leading ? 24 : 28) ||
        props.kerningHalfPoints != (leading ? 0 : 24)) {
      throw StateError('Prefix insertion or subsequent formatting lost a run');
    }
  }
  for (final run in cells[1].inlines.whereType<WmlRun>()) {
    if (!run.properties.bold ||
        run.properties.color != '1F4E79' ||
        run.properties.asciiFont != 'Courier New' ||
        run.properties.fontSizeHalfPoints != 24) {
      throw StateError('Projected insertion changed existing run formatting');
    }
  }
  if (cells.any(
    (cell) =>
        cell.properties.justification != WmlJustification.center ||
        cell.properties.spacingAfter != 3,
  )) {
    throw StateError('Prefix insertion changed paragraph formatting');
  }
}

Future<Map<String, Object?>> runWordCellPrefixExample(
  String source, {
  bool macroEnabled = true,
}) async {
  final input = wordCellPrefixInput(macroEnabled: macroEnabled);
  final original = base64Encode(input);
  final untouched = wordCellPrefixUntouched(input);
  final plan = wordCellPrefixSource(source);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final preview = await session.validate(plan);
  if (!preview.validatedOnly ||
      preview.completedSteps != 6 ||
      session.revision != 0 ||
      base64Encode(session.bytes) != original) {
    throw StateError('Prefix validation changed the session or step count');
  }
  await session.run(OfficeMacro.parse(plan.encode()));
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordCellPrefixExample(saved);
    if (wordCellPrefixUntouched(saved) != untouched) {
      throw StateError('Prefix insertion changed unrelated XML or parts');
    }
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  final state = jsonEncode(wordCellPrefixState(saved));
  final recorder = OfficeMacroSession(input, format: OfficeMacroFormat.docx)
    ..startRecording('Retained table text with labels');
  for (final step in plan.steps) {
    await recorder.callTool(step.tool, step.arguments);
  }
  final recording = recorder.stopRecording();
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recording.encode()));
  assertWordCellPrefixExample(replay.bytes);
  if (jsonEncode(wordCellPrefixState(replay.bytes)) != state ||
      wordCellPrefixUntouched(replay.bytes) != untouched) {
    throw StateError('Recorded prefixes changed their text or target identity');
  }
  final invalid = wordCellPrefixPlan('''
ActiveDocument.Tables(1).Cell(1, 1).Range.InsertBefore Text:="Discard: "
ActiveDocument.Tables(2).Cell(2, 1).Range.InsertBefore Text:="Missing: "
''');
  final beforeFailure = base64Encode(session.bytes);
  session.startRecording('Rejected prefixes');
  for (final action in [session.validate, session.run]) {
    var refused = false;
    try {
      await action(invalid);
    } on OfficeMacroException catch (error) {
      refused =
          error.stepIndex == 1 &&
          error.tool == 'docx.tableCellRangeInsertBefore';
    }
    if (!refused ||
        session.revision != 1 ||
        base64Encode(session.bytes) != beforeFailure) {
      throw StateError('A late invalid cell published earlier prefix changes');
    }
  }
  if (session.stopRecording().steps.isNotEmpty) {
    throw StateError('A failed prefix run entered the recording');
  }
  return {
    'operations': plan.steps.length,
    'revision': session.revision,
    'recordedSteps': recording.steps.length,
    'additionalReopens': 2,
    'untouchedLayoutAndParts': true,
    'opaqueVbaPreserved': macroEnabled,
    'lateRollback': true,
    'state': wordCellPrefixState(saved),
  };
}

Future<void> main() async {
  if (_example.isEmpty) throw StateError('Supply WORD_CELL_PREFIX_BAS_BASE64');
  print(
    jsonEncode(
      await runWordCellPrefixExample(utf8.decode(base64Decode(_example))),
    ),
  );
}
