import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_arguments_smoke.dart' as helpers;
import 'web_vba_office_layout_smoke.dart' as previous;

const _wordSource = String.fromEnvironment('WORD_PARAGRAPH_LAYOUT_BAS_BASE64');
const _slideSource = String.fromEnvironment(
  'POWERPOINT_TEXT_MARGINS_BAS_BASE64',
);

Future<Object?> _capture(Future<void> Function() run) async {
  final lines = <String>[];
  await runZoned(
    run,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  if (lines.length != 1) throw StateError('Expected one semantic JSON result');
  return jsonDecode(lines.single);
}

Future<Uint8List> _publish(
  String encoded,
  String language,
  OfficeMacroFormat format,
  Uint8List input,
  int operations,
) async {
  if (encoded.isEmpty) throw StateError('Supply the exact committed BAS bytes');
  final source = utf8.decode(base64Decode(encoded));
  final original = base64Encode(input);
  final plan = OfficeMacroLanguages().compile(
    OfficeMacroSource(source: source, language: language, format: format),
  );
  if (plan.steps.length != operations) throw StateError('Unexpected plan size');
  final session = OfficeMacroSession(input, format: format);
  final validation = await session.validate(plan);
  if (!validation.validatedOnly ||
      validation.completedSteps != operations ||
      session.revision != 0 ||
      base64Encode(session.bytes) != original) {
    throw StateError('Detached validation changed the input');
  }
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  if (result.completedSteps != operations ||
      result.revision != 1 ||
      base64Encode(input) != original) {
    throw StateError('Run did not publish one isolated transaction');
  }
  return session.bytes;
}

Map<String, Object?> _wordState(Uint8List bytes) {
  final paragraphs = WordDeserializer().readBytes(bytes).paragraphs.toList();
  if (paragraphs.length != 4 ||
      paragraphs[0].text != 'Original heading' ||
      paragraphs[1].text != 'Original body' ||
      paragraphs[2].text != 'Original annotation' ||
      paragraphs[3].text != 'Untouched paragraph') {
    throw StateError('Word text changed');
  }
  final expected = [1.0, 1.5, 2.0];
  for (var i = 0; i < 3; i++) {
    if (paragraphs[i].properties.lineSpacingRule != WmlLineSpacingRule.auto ||
        paragraphs[i].properties.lineSpacing != expected[i]) {
      throw StateError('Word line spacing changed on save');
    }
  }
  final font = paragraphs[0].inlines.whereType<WmlRun>().first.properties;
  if (!font.bold ||
      font.fontSizeHalfPoints != 32 ||
      paragraphs[0].properties.spacingAfter != 6 ||
      paragraphs[1].properties.rightToLeft != true ||
      paragraphs[2].properties.rightToLeft != false ||
      !paragraphs[2].properties.keepTogether) {
    throw StateError('Word helper formatting changed');
  }
  return {
    'operations': 10,
    'text': [for (final paragraph in paragraphs) paragraph.text],
    'lineMultipliers': [
      for (final paragraph in paragraphs.take(3))
        paragraph.properties.lineSpacing,
    ],
    'rtl': [
      for (final paragraph in paragraphs.take(3))
        paragraph.properties.rightToLeft,
    ],
    'headingHalfPoints': font.fontSizeHalfPoints,
    'headingBold': font.bold,
    'headingAfterPoints': paragraphs[0].properties.spacingAfter,
    'lastKeepTogether': paragraphs[2].properties.keepTogether,
  };
}

Map<String, Object?> _slideState(Uint8List bytes) {
  final deck = SlideDeserializer().readBytes(bytes);
  final title = deck.slides[0].shapes[0];
  final values = [
    for (final side in PmlTextInsetSide.values) title.textInsets[side],
  ];
  if (jsonEncode(values) != jsonEncode(<double>[18, 6, 18, 12]) ||
      title.textAnchor != PmlTextAnchor.center ||
      title.text != 'First title' ||
      deck.slides[0].shapes[1].text != 'Untouched body' ||
      deck.slides[1].shapes[0].text != 'Second title') {
    throw StateError('PowerPoint margins or unrelated content changed');
  }
  return {
    'operations': 5,
    'margins': values,
    'anchor': title.textAnchor.name,
    'title': title.text,
    'other': [deck.slides[0].shapes[1].text, deck.slides[1].shapes[0].text],
  };
}

Future<Map<String, Object?>> _layouts() async {
  var word = await _publish(
    _wordSource,
    'vba-word',
    OfficeMacroFormat.docx,
    helpers.wordHelperInput(),
    10,
  );
  var slides = await _publish(
    _slideSource,
    'vba-powerpoint',
    OfficeMacroFormat.pptx,
    helpers.powerPointHelperInput(),
    5,
  );
  final firstWord = _wordState(word);
  final firstSlides = _slideState(slides);
  for (var cycle = 0; cycle < 2; cycle++) {
    word = WordSerializer().writeBytes(WordDeserializer().readBytes(word));
    slides = SlideSerializer().writeBytes(
      SlideDeserializer().readBytes(slides),
    );
    if (jsonEncode(_wordState(word)) != jsonEncode(firstWord) ||
        jsonEncode(_slideState(slides)) != jsonEncode(firstSlides)) {
      throw StateError('Repeated native saves changed the expansion examples');
    }
  }
  // Exercise fractional points at both exact integer-EMU boundaries in both
  // runtimes, through real serialization rather than plan-only assertions.
  final boundary = base64Encode(
    utf8.encode('''
Sub Main()
With ActivePresentation.Slides(1).Shapes("Title").TextFrame
  .MarginLeft = 1 / 12700
  .MarginTop = 2147483647 / 12700
End With
End Sub
'''),
  );
  final edge = await _publish(
    boundary,
    'vba-powerpoint',
    OfficeMacroFormat.pptx,
    helpers.powerPointHelperInput(),
    2,
  );
  final shape = SlideDeserializer().readBytes(edge).slides[0].shapes[0];
  if (shape.textInsets.left != 1 / 12700 ||
      shape.textInsets.top != 2147483647 / 12700) {
    throw StateError('Exact EMU boundary failed to survive serialization');
  }
  return {
    'word': firstWord,
    'powerpoint': firstSlides,
    'insetBoundaryEmus': [1, 2147483647],
    'additionalReopens': 2,
  };
}

Future<void> main() async {
  final result = <String, Object?>{
    'previousTypographyAndSlideshow': await _capture(previous.main),
    'optionalHelpers': await _capture(helpers.main),
    'paragraphsAndMargins': await _layouts(),
  };
  print(jsonEncode(result));
}
