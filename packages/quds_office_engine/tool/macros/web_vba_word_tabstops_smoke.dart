import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// Supply the actual committed example bytes to both VM and JS compilation.
const _example = String.fromEnvironment('WORD_TABSTOPS_BAS_BASE64');

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    source: source,
  ),
);

Uint8List wordTabStopInput() => WordSerializer().writeBytes(
  WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(
            properties: WmlParagraphProps(
              keepTogether: true,
              spacingBefore: 6,
              tabs: const [
                WmlTabStop(
                  position: 36,
                  alignment: WmlTabAlignment.center,
                  leader: WmlTabLeader.hyphen,
                ),
              ],
            ),
            inlines: [
              WmlRun(
                text: 'Heading\tValue',
                properties: WmlRunProps(bold: true),
              ),
            ],
          ),
          WmlParagraph(
            properties: WmlParagraphProps(
              tabs: const [WmlTabStop(position: 90)],
            ),
            inlines: [WmlRun(text: 'Middle\tValue')],
          ),
          WmlParagraph(),
          WmlParagraph(
            properties: WmlParagraphProps(
              tabs: const [
                WmlTabStop(
                  position: 54,
                  alignment: WmlTabAlignment.right,
                  leader: WmlTabLeader.underscore,
                ),
              ],
            ),
            inlines: [WmlRun(text: 'Untouched\tparagraph')],
          ),
        ],
      ),
    ],
  ),
);

List<Object> _tabs(WmlParagraph paragraph) => [
  for (final tab in paragraph.properties.tabs)
    <String, Object>{
      'twips': (tab.position * 20).round(),
      'alignment': tab.alignment.name,
      'leader': tab.leader.name,
    },
];

Map<String, Object?> _state(Uint8List bytes) {
  final paragraphs = WordDeserializer().readBytes(bytes).paragraphs.toList();
  const expectedTexts = [
    'Heading\tValue',
    'Middle\tValue',
    '',
    'Untouched\tparagraph',
  ];
  final texts = [for (final paragraph in paragraphs) paragraph.text];
  final tabs = [for (final paragraph in paragraphs) _tabs(paragraph)];
  final expectedTabs = [
    [
      {'twips': 1440, 'alignment': 'left', 'leader': 'none'},
      {'twips': 8640, 'alignment': 'right', 'leader': 'dot'},
    ],
    [
      {'twips': 1800, 'alignment': 'left', 'leader': 'none'},
      {'twips': 4320, 'alignment': 'center', 'leader': 'hyphen'},
      {'twips': 6480, 'alignment': 'left', 'leader': 'underscore'},
    ],
    [
      {'twips': -360, 'alignment': 'decimal', 'leader': 'none'},
    ],
    [
      {'twips': 1080, 'alignment': 'right', 'leader': 'underscore'},
    ],
  ];
  if (jsonEncode(texts) != jsonEncode(expectedTexts) ||
      jsonEncode(tabs) != jsonEncode(expectedTabs) ||
      !paragraphs.first.properties.keepTogether ||
      paragraphs.first.properties.spacingBefore != 6 ||
      !paragraphs.first.inlines.whereType<WmlRun>().first.properties.bold) {
    throw StateError('Tab stops or unrelated document content changed');
  }
  return {'paragraphs': texts, 'tabs': tabs};
}

/// Runs the exact supplied BAS source and two further native save/reopen cycles.
Future<Map<String, Object?>> runWordTabStopExample(String source) async {
  final input = wordTabStopInput();
  final original = base64Encode(input);
  final plan = _compile(source);
  if (plan.steps.length != 7) {
    throw StateError('Expected seven example operations');
  }
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Word tab stops');
  final validation = await session.validate(plan);
  if (!validation.validatedOnly ||
      validation.completedSteps != 7 ||
      session.revision != 0 ||
      base64Encode(session.bytes) != original) {
    throw StateError('Validation changed the published document');
  }
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  if (result.completedSteps != 7 ||
      result.revision != 1 ||
      result.validatedOnly ||
      base64Encode(input) != original ||
      session.stopRecording().steps.isNotEmpty) {
    throw StateError('Example did not publish one isolated transaction');
  }
  var saved = session.bytes;
  final state = _state(saved);
  for (var cycle = 0; cycle < 2; cycle++) {
    saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    if (jsonEncode(_state(saved)) != jsonEncode(state)) {
      throw StateError('Repeated native save changed tab-stop semantics');
    }
  }
  return {'operations': 7, 'revision': 1, 'additionalReopens': 2, ...state};
}

Future<Map<String, Object?>> _boundariesAndOrdering() async {
  final session = OfficeMacroSession(
    wordTabStopInput(),
    format: OfficeMacroFormat.docx,
  );
  await session.run(
    _compile('''
Sub Main()
  With ActiveDocument.Paragraphs(1).TabStops
    .ClearAll
    .Add -1584, wdAlignTabDecimal
    .Add 0.05
    .Add 1584, wdAlignTabRight
  End With
  ActiveDocument.Paragraphs(2).TabStops.Add Leader:=Mark(1), Position:=Mark(72), Alignment:=Mark(2)
End Sub
Function Mark(ByVal value As Long) As Long
  ActiveDocument.Paragraphs(4).Range.InsertBefore CStr(value) & "|"
  Mark = value
End Function
'''),
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    final paragraphs = WordDeserializer().readBytes(saved).paragraphs.toList();
    final positions = [
      for (final tab in paragraphs.first.properties.tabs) tab.position,
    ];
    if (positions.length != 3 ||
        positions[0] != -1584 ||
        positions[1] != 0.05 ||
        positions[2] != 1584 ||
        paragraphs[3].text != '2|72|1|Untouched\tparagraph') {
      throw StateError('Twip boundaries or named argument ordering changed');
    }
    final named = paragraphs[1].properties.tabs.singleWhere(
      (tab) => tab.position == 72,
    );
    if (named.alignment != WmlTabAlignment.right ||
        named.leader != WmlTabLeader.dot) {
      throw StateError('Named values bound to the wrong tab-stop arguments');
    }
    saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
  }
  return {
    'boundaryTwips': [-31680, 1, 31680],
    'namedEvaluationOrder': [1, 72, 2],
    'namedPositionTwips': 1440,
    'namedAlignment': 'right',
    'namedLeader': 'dot',
  };
}

Future<void> _rollback() async {
  final input = wordTabStopInput();
  final original = base64Encode(input);
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Rejected tab stops');
  final plan = _compile('''
Sub Main()
  ActiveDocument.Paragraphs(1).TabStops.ClearAll
  ActiveDocument.Paragraphs(2).TabStops.Add 72
  ActiveDocument.Paragraphs(99).TabStops.Add 144
End Sub
''');
  for (final validateOnly in [true, false]) {
    try {
      if (validateOnly) {
        await session.validate(plan);
      } else {
        await session.run(plan);
      }
      throw StateError('Missing-paragraph tab stop unexpectedly published');
    } on OfficeMacroException catch (error) {
      if (error.code != 'operation_failed' || error.stepIndex != 2) rethrow;
    }
  }
  if (session.revision != 0 ||
      base64Encode(session.bytes) != original ||
      session.stopRecording().steps.isNotEmpty) {
    throw StateError('Late tab-stop failure changed the published document');
  }
}

int _refusals() {
  const invalid = [
    'ActiveDocument.Paragraphs(1).TabStops.Add 1.01',
    'ActiveDocument.Paragraphs(1).TabStops.Add 1584.05',
    'ActiveDocument.Paragraphs(1).TabStops.Add True',
    'ActiveDocument.Paragraphs(1).TabStops.Add "72"',
    'ActiveDocument.Paragraphs(1).TabStops.Add 72, 4',
    'ActiveDocument.Paragraphs(1).TabStops.ClearAll 1',
  ];
  for (final statement in invalid) {
    try {
      _compile('Sub Main()\n$statement\nEnd Sub');
      throw StateError('Unsupported tab-stop source unexpectedly compiled');
    } on OfficeVbaCompileException {
      // Unsupported source must fail before any native plan is published.
    }
  }
  return invalid.length;
}

Future<void> main() async {
  if (_example.isEmpty) {
    throw StateError('Supply exact committed WORD_TABSTOPS_BAS_BASE64 bytes');
  }
  final example = await runWordTabStopExample(
    utf8.decode(base64Decode(_example)),
  );
  final boundaries = await _boundariesAndOrdering();
  await _rollback();
  print(
    jsonEncode({
      'example': example,
      'boundariesAndOrdering': boundaries,
      'lateFailureRollback': true,
      'refusedSources': _refusals(),
    }),
  );
}
