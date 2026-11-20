import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// Supply the exact committed BAS bytes as base64 to both VM and JS compilation.
const _wordExample = String.fromEnvironment('WORD_OPTIONAL_HELPERS_BAS_BASE64');
const _powerPointExample = String.fromEnvironment(
  'POWERPOINT_OPTIONAL_HELPERS_BAS_BASE64',
);

Uint8List wordHelperInput() => WordSerializer().writeBytes(
  WmlDocument(
    sections: <WmlSection>[
      WmlSection(
        blocks: <WmlBlock>[
          for (final text in <String>[
            'Original heading',
            'Original body',
            'Original annotation',
            'Untouched paragraph',
          ])
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: text)]),
        ],
      ),
    ],
  ),
);

Uint8List powerPointHelperInput() => SlideSerializer().writeBytes(
  PmlPresentation(
    slides: <PmlSlide>[
      PmlSlide(
        id: 256,
        shapes: <PmlShape>[
          PmlShape(id: 2, name: 'Title', text: 'First title'),
          PmlShape(id: 3, name: 'Body', text: 'Untouched body'),
        ],
      ),
      PmlSlide(
        id: 257,
        shapes: <PmlShape>[
          PmlShape(id: 2, name: 'Title', text: 'Second title'),
        ],
      ),
    ],
  ),
);

Future<Uint8List> _publish(
  String source,
  String language,
  OfficeMacroFormat format,
  Uint8List input,
  int operations,
) async {
  final original = base64Encode(input);
  final plan = OfficeMacroLanguages().compile(
    OfficeMacroSource(language: language, format: format, source: source),
  );
  if (plan.steps.length != operations || plan.format != format) {
    throw StateError('$language helper example emitted an unexpected plan');
  }
  final session = OfficeMacroSession(input, format: format);
  final validation = await session.validate(plan);
  if (!validation.validatedOnly ||
      validation.completedSteps != operations ||
      session.revision != 0 ||
      base64Encode(session.bytes) != original) {
    throw StateError('$language validation changed published state');
  }
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  if (result.validatedOnly ||
      result.completedSteps != operations ||
      session.revision != 1 ||
      base64Encode(input) != original) {
    throw StateError('$language did not publish one detached transaction');
  }
  return session.bytes;
}

Map<String, Object?> _wordSummary(Uint8List bytes) {
  final paragraphs = WordDeserializer().readBytes(bytes).paragraphs.toList();
  const texts = <String>[
    'Heading: Original heading',
    'Original body',
    'Original annotation',
    'Untouched paragraph',
  ];
  const halfPoints = <int>[36, 24, 20];
  const bold = <bool>[false, true, false];
  if (paragraphs.length != texts.length) {
    throw StateError('Word helpers changed paragraph structure');
  }
  for (var index = 0; index < paragraphs.length; index++) {
    if (paragraphs[index].text != texts[index]) {
      throw StateError('Word helper text mismatch at paragraph $index');
    }
    if (index == 3) continue;
    final runs = paragraphs[index].inlines.whereType<WmlRun>().toList();
    if (runs.isEmpty ||
        runs.any(
          (run) =>
              run.properties.fontSizeHalfPoints != halfPoints[index] ||
              run.properties.bold != bold[index],
        )) {
      throw StateError('Word optional formatting did not persist');
    }
  }
  return <String, Object?>{
    'paragraphs': texts,
    'halfPoints': halfPoints,
    'bold': bold,
    'operations': 7,
  };
}

Map<String, Object?> _powerPointSummary(Uint8List bytes) {
  final slides = SlideDeserializer().readBytes(bytes).slides;
  if (slides.length != 2 ||
      slides[0].shapes.length != 2 ||
      slides[1].shapes.length != 1 ||
      slides[0].shapes[1].text != 'Untouched body') {
    throw StateError('PowerPoint helpers changed unrelated structure');
  }
  const texts = <String>['Optional helpers', 'Second title'];
  const sizes = <int>[20, 28];
  const bold = <bool>[false, true];
  for (var index = 0; index < slides.length; index++) {
    final shape = slides[index].shapes.first;
    final runs = shape.resolvedRichText.expand((paragraph) => paragraph.runs);
    if (shape.text != texts[index] ||
        shape.fontSizePt != sizes[index] ||
        runs.isEmpty ||
        runs.any((run) => run.bold != bold[index])) {
      throw StateError('PowerPoint optional formatting did not persist');
    }
  }
  return <String, Object?>{
    'titles': texts,
    'sizePoints': sizes,
    'bold': bold,
    'untouchedBody': slides[0].shapes[1].text,
    'operations': 5,
  };
}

/// Exercises actual example source through native validation, publication, and
/// two additional save/reopen cycles without using a host filesystem API.
Future<Map<String, Object?>> runOptionalHelperExamples(
  String wordSource,
  String powerPointSource,
) async {
  var word = await _publish(
    wordSource,
    'vba-word',
    OfficeMacroFormat.docx,
    wordHelperInput(),
    7,
  );
  var powerpoint = await _publish(
    powerPointSource,
    'vba-powerpoint',
    OfficeMacroFormat.pptx,
    powerPointHelperInput(),
    5,
  );
  final firstWord = _wordSummary(word);
  final firstPowerPoint = _powerPointSummary(powerpoint);
  for (var cycle = 0; cycle < 2; cycle++) {
    word = WordSerializer().writeBytes(WordDeserializer().readBytes(word));
    powerpoint = SlideSerializer().writeBytes(
      SlideDeserializer().readBytes(powerpoint),
    );
    if (jsonEncode(_wordSummary(word)) != jsonEncode(firstWord) ||
        jsonEncode(_powerPointSummary(powerpoint)) !=
            jsonEncode(firstPowerPoint)) {
      throw StateError('Optional helper results changed after native reopen');
    }
  }
  await _rollback(
    'vba-word',
    OfficeMacroFormat.docx,
    wordHelperInput(),
    'ActiveDocument.Paragraphs(index).Range.InsertBefore text',
  );
  await _rollback(
    'vba-powerpoint',
    OfficeMacroFormat.pptx,
    powerPointHelperInput(),
    'ActivePresentation.Slides(index).Shapes("Title").TextFrame.TextRange.Text = text',
  );
  return <String, Object?>{'word': firstWord, 'powerpoint': firstPowerPoint};
}

Future<void> _rollback(
  String language,
  OfficeMacroFormat format,
  Uint8List input,
  String write,
) async {
  final original = base64Encode(input);
  final session = OfficeMacroSession(input, format: format);
  final plan = OfficeMacroLanguages().compile(
    OfficeMacroSource(
      language: language,
      format: format,
      source:
          '''
Sub Main()
  Put text:="first"
  Put index:=99, text:="must not publish"
End Sub
Sub Put(Optional ByVal index As Long = 1, Optional ByVal text As String = "default")
  $write
End Sub
''',
    ),
  );
  try {
    await session.run(plan);
    throw StateError('$language late failure unexpectedly published');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed' || error.stepIndex != 1) rethrow;
  }
  if (session.revision != 0 || base64Encode(session.bytes) != original) {
    throw StateError('$language helper failure changed the input');
  }
}

Map<String, Object?> _languageSummary() {
  final plan = const OfficeVbaMacroLanguage().compile(
    OfficeMacroSource(
      language: 'vba-excel',
      format: OfficeMacroFormat.xlsx,
      source: '''
Sub Main()
  Worksheets(1).Range("B1").Value2 = Pair(second:=Mark(2), first:=Mark(1))
  Inspect
  Inspect Empty
  Inspect Null
End Sub
Function Mark(ByVal value As Long) As Long
  Worksheets(1).Range("A1").Value2 = value
  Mark = value
End Function
Function Pair(Optional ByVal first As Long = 4, Optional ByVal second As Long = 5) As Long
  Pair = first * 10 + second
End Function
Sub Inspect(Optional ByVal item)
  Worksheets(1).Range("C1").Value2 = IsMissing(item)
  If Not IsMissing(item) Then
    Worksheets(1).Range("C2").Value2 = IsEmpty(item)
    Worksheets(1).Range("C3").Value2 = IsNull(item)
  End If
End Sub
''',
    ),
  );
  final values = <Object?>[
    for (final step in plan.steps) step.arguments['value'],
  ];
  const expected = <Object?>[
    2,
    1,
    12,
    true,
    false,
    true,
    false,
    false,
    false,
    true,
  ];
  if (jsonEncode(values) != jsonEncode(expected)) {
    throw StateError('Source ordering or Missing/Empty/Null semantics changed');
  }
  final refusals = <String>[];
  for (final (source, code) in <(String, String)>[
    (
      'Sub Main()\nCall Put(value:=1, VALUE:=2)\nEnd Sub\n'
          'Sub Put(ByVal value, Optional ByVal second)\nEnd Sub',
      'vba_type_error',
    ),
    (
      'Sub Main()\nCall Put(value:=1, 2)\nEnd Sub\n'
          'Sub Put(ByVal value, Optional ByVal second)\nEnd Sub',
      'vba_type_error',
    ),
    (
      'Sub Main()\nPut\nEnd Sub\nSub Put(Optional ByVal value)\n'
          'Worksheets(1).Range("A1").Value2 = value\nEnd Sub',
      'vba_missing_argument',
    ),
    (
      'Sub Main()\nEnd Sub\nSub Put(Optional ByVal value = Compute())\nEnd Sub\n'
          'Function Compute() As Long\nCompute = 1\nEnd Function',
      'vba_unsupported',
    ),
  ]) {
    try {
      const OfficeVbaMacroLanguage().compile(
        OfficeMacroSource(
          language: 'vba-excel',
          format: OfficeMacroFormat.xlsx,
          source: source,
        ),
      );
      throw StateError('Invalid helper arguments unexpectedly compiled');
    } on OfficeVbaCompileException catch (error) {
      if (error.code != code) rethrow;
      refusals.add(error.code);
    }
  }
  return <String, Object?>{'values': values, 'refusals': refusals};
}

Future<void> main() async {
  if (_wordExample.isEmpty || _powerPointExample.isEmpty) {
    throw StateError('Supply both committed helper examples as base64 defines');
  }
  final result = await runOptionalHelperExamples(
    utf8.decode(base64Decode(_wordExample)),
    utf8.decode(base64Decode(_powerPointExample)),
  );
  result['language'] = _languageSummary();
  print(jsonEncode(result));
}
