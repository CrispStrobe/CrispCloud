import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// Supply the exact repository example bytes to both the VM and dart compile js
// with -DWORD_TYPOGRAPHY_BAS_BASE64=... and
// -DPOWERPOINT_SLIDESHOW_BAS_BASE64=... . No host filesystem API is needed.
const _wordExample = String.fromEnvironment('WORD_TYPOGRAPHY_BAS_BASE64');
const _powerPointExample = String.fromEnvironment(
  'POWERPOINT_SLIDESHOW_BAS_BASE64',
);

String _source(String encoded, String define) {
  if (encoded.isEmpty) {
    throw StateError('Supply the committed example with -D$define=<base64>');
  }
  return utf8.decode(base64Decode(encoded));
}

Future<(OfficeMacro, OfficeMacroSession)> _publish(
  String source,
  String language,
  OfficeMacroFormat format,
  Uint8List input,
) async {
  final original = base64Encode(input);
  final macro = OfficeMacroLanguages().compile(
    OfficeMacroSource(language: language, format: format, source: source),
  );
  if (macro.format != format || macro.steps.length != 12) {
    throw StateError('$language example produced an unexpected native plan');
  }
  final session = OfficeMacroSession(input, format: format);
  final validation = await session.validate(macro);
  if (!validation.validatedOnly ||
      validation.completedSteps != 12 ||
      validation.revision != 0 ||
      session.revision != 0 ||
      base64Encode(session.bytes) != original) {
    throw StateError('$language validation changed the published input');
  }
  final result = await session.run(OfficeMacro.parse(macro.encode()));
  if (result.validatedOnly ||
      result.completedSteps != 12 ||
      result.revision != 1 ||
      session.revision != 1 ||
      base64Encode(input) != original ||
      base64Encode(session.bytes) == original) {
    throw StateError('$language did not publish exactly one detached result');
  }
  return (macro, session);
}

Uint8List _wordInput() => WordSerializer().writeBytes(
  WmlDocument(
    sections: <WmlSection>[
      WmlSection(
        blocks: <WmlBlock>[
          WmlParagraph(inlines: <WmlInline>[WmlRun(text: ' original heading')]),
          WmlParagraph(
            inlines: <WmlInline>[
              WmlRun(
                text: ' original marker',
                properties: WmlRunProps(
                  highlight: 'FFFF00',
                  vertAlign: WmlVertAlign.subscript,
                ),
              ),
            ],
          ),
          WmlParagraph(
            inlines: <WmlInline>[
              WmlRun(
                text: ' original formula',
                properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
              ),
            ],
          ),
          WmlParagraph(
            inlines: <WmlInline>[WmlRun(text: 'Untouched paragraph')],
          ),
        ],
      ),
    ],
  ),
);

Map<String, Object?> _wordSummary(Uint8List bytes) {
  final paragraphs = WordDeserializer().readBytes(bytes).paragraphs.toList();
  const expectedText = <String>[
    'Research note original heading',
    'Reference marker original marker',
    'Formula annotation original formula',
    'Untouched paragraph',
  ];
  const scripts = <WmlVertAlign>[
    WmlVertAlign.baseline,
    WmlVertAlign.superscript,
    WmlVertAlign.subscript,
  ];
  const highlights = <String?>['FFFF00', null, 'C0C0C0'];
  if (paragraphs.length != expectedText.length) {
    throw StateError('Word example changed the paragraph count');
  }
  for (var index = 0; index < paragraphs.length; index++) {
    if (paragraphs[index].text != expectedText[index]) {
      throw StateError('Word example changed paragraph $index unexpectedly');
    }
    if (index >= 3) continue;
    final runs = paragraphs[index].inlines.whereType<WmlRun>().toList();
    if (runs.isEmpty ||
        runs.any((run) {
          final properties = run.properties;
          return properties.vertAlign != scripts[index] ||
              properties.highlight != highlights[index] ||
              (index == 0 && (!properties.smallCaps || !properties.bold));
        })) {
      throw StateError('Word typography did not survive in paragraph $index');
    }
  }
  final heading = paragraphs.first.inlines.whereType<WmlRun>().first.properties;
  return <String, Object?>{
    'paragraphs': <String>[for (final paragraph in paragraphs) paragraph.text],
    'headingSmallCaps': heading.smallCaps,
    'headingBold': heading.bold,
    'scriptModes': <String>[
      for (final paragraph in paragraphs.take(3))
        paragraph.inlines.whereType<WmlRun>().first.properties.vertAlign.name,
    ],
    'highlightRgb': <String?>[
      for (final paragraph in paragraphs.take(3))
        paragraph.inlines.whereType<WmlRun>().first.properties.highlight,
    ],
  };
}

Uint8List _powerPointInput() => SlideSerializer().writeBytes(
  PmlPresentation(
    slides: <PmlSlide>[
      PmlSlide(
        id: 256,
        hidden: true,
        transition: const PmlSlideTransition(
          kind: PmlTransitionKind.push,
          direction: PmlTransitionDir.right,
          durationMs: 900,
          advanceOnClick: false,
          advanceAfterMs: 2500,
        ),
        shapes: <PmlShape>[
          PmlShape(id: 2, name: 'Title', text: 'Original title'),
          PmlShape(id: 3, name: 'Body', text: 'Untouched body'),
        ],
      ),
      PmlSlide(
        id: 257,
        shapes: <PmlShape>[
          PmlShape(id: 2, name: 'Title', text: 'Untouched appendix'),
        ],
      ),
    ],
  ),
);

Map<String, Object?> _powerPointSummary(Uint8List bytes) {
  final slides = SlideDeserializer().readBytes(bytes).slides;
  if (slides.length != 2 ||
      slides[0].id != 256 ||
      slides[1].id != 257 ||
      slides[0].hidden ||
      !slides[1].hidden ||
      slides[0].shapes.length != 2 ||
      slides[0].shapes[1].text != 'Untouched body' ||
      slides[1].shapes.single.text != 'Untouched appendix') {
    throw StateError(
      'PowerPoint visibility, order or untouched content changed',
    );
  }
  final title = slides[0].shapes.first;
  final transition = slides[0].transition;
  final runs = title.resolvedRichText
      .expand((paragraph) => paragraph.runs)
      .toList();
  if (title.text != 'Quarterly report' ||
      title.textAnchor != PmlTextAnchor.center ||
      title.textAlign != PmlTextAlign.center ||
      title.fontSizePt != 28 ||
      title.textColor != '1F4E79' ||
      runs.isEmpty ||
      runs.any((run) => run.fontFamily != 'Arial' || !run.bold) ||
      transition.kind != PmlTransitionKind.fade ||
      transition.durationMs != 1250 ||
      !transition.advanceOnClick ||
      transition.advanceAfterMs != 2500) {
    throw StateError('PowerPoint layout or transition did not round-trip');
  }
  final root = XmlDocument.parse(
    OpcPackage.openBytes(bytes).getPart('/ppt/slides/slide1.xml')!.readText(),
  ).root!;
  final body = root
      .firstChild('cSld', namespaceUri: OfficeNamespaces.p)!
      .firstChild('spTree', namespaceUri: OfficeNamespaces.p)!
      .firstChild('sp', namespaceUri: OfficeNamespaces.p)!
      .firstChild('txBody', namespaceUri: OfficeNamespaces.p)!
      .firstChild('bodyPr', namespaceUri: OfficeNamespaces.a)!;
  final motion = root.firstChild(
    'transition',
    namespaceUri: OfficeNamespaces.p,
  )!;
  if (body.getAttribute('anchor', namespaceUri: '') != 'ctr' ||
      motion.getAttribute(
            'dur',
            namespaceUri:
                'http://schemas.microsoft.com/office/powerpoint/2010/main',
          ) !=
          '1250' ||
      motion.getAttribute('advClick', namespaceUri: '') != '1' ||
      motion.getAttribute('advTm', namespaceUri: '') != '2500' ||
      motion.firstChild('fade', namespaceUri: OfficeNamespaces.p) == null) {
    throw StateError('PowerPoint native XML did not retain requested values');
  }
  return <String, Object?>{
    'slideIds': <int>[for (final slide in slides) slide.id],
    'hidden': <bool>[for (final slide in slides) slide.hidden],
    'title': title.text,
    'verticalAnchor': title.textAnchor.name,
    'alignment': title.textAlign.name,
    'fontFamily': runs.first.fontFamily,
    'bold': runs.first.bold,
    'fontSizeHundredths': (title.fontSizePt * 100).round(),
    'textRgb': title.textColor,
    'effect': transition.kind.name,
    'durationMs': transition.durationMs,
    'advanceOnClick': transition.advanceOnClick,
    'advanceAfterMs': transition.advanceAfterMs,
    'untouchedBody': slides[0].shapes[1].text,
    'untouchedAppendix': slides[1].shapes.single.text,
  };
}

/// Compile actual BAS examples and compare semantic VM/JavaScript output.
Future<void> main() async {
  final wordSource = _source(_wordExample, 'WORD_TYPOGRAPHY_BAS_BASE64');
  final powerPointSource = _source(
    _powerPointExample,
    'POWERPOINT_SLIDESHOW_BAS_BASE64',
  );
  final (wordPlan, wordSession) = await _publish(
    wordSource,
    'vba-word',
    OfficeMacroFormat.docx,
    _wordInput(),
  );
  final (powerPointPlan, powerPointSession) = await _publish(
    powerPointSource,
    'vba-powerpoint',
    OfficeMacroFormat.pptx,
    _powerPointInput(),
  );
  final word = _wordSummary(wordSession.bytes);
  final powerPoint = _powerPointSummary(powerPointSession.bytes);
  final wordResaved = WordSerializer().writeBytes(
    WordDeserializer().readBytes(wordSession.bytes),
  );
  final powerPointResaved = SlideSerializer().writeBytes(
    SlideDeserializer().readBytes(powerPointSession.bytes),
  );
  if (jsonEncode(_wordSummary(wordResaved)) != jsonEncode(word) ||
      jsonEncode(_powerPointSummary(powerPointResaved)) !=
          jsonEncode(powerPoint)) {
    throw StateError('A second native save changed example semantics');
  }
  // Semantic JSON is deterministic even when ZIP metadata differs by runtime.
  print(
    jsonEncode(<String, Object?>{
      'smoke': 'vba-office-layout-v1',
      'word': <String, Object?>{
        'example': 'word_typography.bas',
        'sourceBytes': utf8.encode(wordSource).length,
        'steps': wordPlan.steps.length,
        'revision': wordSession.revision,
        ...word,
      },
      'powerpoint': <String, Object?>{
        'example': 'powerpoint_slideshow.bas',
        'sourceBytes': utf8.encode(powerPointSource).length,
        'steps': powerPointPlan.steps.length,
        'revision': powerPointSession.revision,
        ...powerPoint,
      },
      'immutableValidation': true,
      'unchangedCallerInput': true,
      'secondSaveSemanticMatch': true,
    }),
  );
}
