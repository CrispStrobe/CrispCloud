// test/office_formatting_preservation_test.dart
//
// Round-trips the Word paragraph/font properties exposed by the CrispCloud
// ribbon through Quds save/reopen. This is intentionally semantic: it checks
// the model and package parts, not a whole-file hash.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:xml/xml.dart' as xml;

Map<String, Uint8List> _parts(Uint8List bytes) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  return <String, Uint8List>{
    for (final ArchiveFile file in archive.files)
      if (file.isFile) file.name: Uint8List.fromList(file.content),
  };
}


const _pPrOrder = <String>[
  'pStyle','keepNext','keepLines','pageBreakBefore','framePr','widowControl',
  'numPr','suppressLineNumbers','pBdr','shd','tabs','suppressAutoHyphens',
  'kinsoku','wordWrap','overflowPunct','topLinePunct','autoSpaceDE',
  'autoSpaceDN','bidi','adjustRightInd','snapToGrid','spacing','ind',
  'contextualSpacing','mirrorIndents','suppressOverlap','jc','textDirection',
  'textAlignment','textboxTightWrap','outlineLvl','divId','cnfStyle','rPr',
  'sectPr','pPrChange',
];
const _rPrOrder = <String>[
  'rStyle','rFonts','b','bCs','i','iCs','caps','smallCaps','strike',
  'dstrike','outline','shadow','emboss','imprint','noProof','snapToGrid',
  'vanish','webHidden','color','spacing','w','kern','position','sz','szCs',
  'highlight','u','effect','bdr','shd','fitText','vertAlign','rtl','cs','em',
  'lang','eastAsianLayout','specVanish','oMath',
];
const _sectPrOrder = <String>[
  'headerReference','footerReference','footnotePr','endnotePr','type','pgSz',
  'pgMar','paperSrc','pgBorders','lnNumType','pgNumType','cols','formProt',
  'vAlign','noEndnote','titlePg','textDirection','bidi','rtlGutter','docGrid',
  'printerSettings','sectPrChange',
];

void _assertOrder(xml.XmlDocument doc, String container, List<String> order) {
  final rank = <String, int>{
    for (var i = 0; i < order.length; i++) order[i]: i,
  };
  for (final element in doc.descendants.whereType<xml.XmlElement>()) {
    if (element.name.local != container) continue;
    var last = -1;
    for (final child in element.children.whereType<xml.XmlElement>()) {
      final value = rank[child.name.local];
      expect(value, isNotNull, reason: 'unknown <${child.name.local}> in $container');
      expect(value! >= last, isTrue,
          reason: '<${child.name.local}> after out-of-order child in $container');
      last = value;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('paragraph and font settings survive save and reopen', () {
    final Uint8List original =
        File('test/fixtures/footnote.docx').readAsBytesSync();
    final WordEditorController controller =
        WordEditorController.fromBytes(original);
    addTearDown(controller.dispose);

    final WmlParagraph paragraph = controller.document.paragraphs.first;
    paragraph.properties
      ..justification = WmlJustification.center
      ..lineSpacing = 1.5
      ..lineSpacingRule = WmlLineSpacingRule.auto
      ..spacingBefore = 6
      ..spacingAfter = 10
      ..indent = const WmlIndent(left: 18, right: 12, firstLine: 6)
      ..tabs = const <WmlTabStop>[
        WmlTabStop(position: 72),
        WmlTabStop(position: 144),
      ]
      ..dropCapLines = 2
      ..shadingFill = 'FFF2CC'
      ..borderColor = 'C00000'
      ..keepTogether = true
      ..pageBreakBefore = true;

    final WmlRun run = paragraph.inlines.whereType<WmlRun>().first;
    run.properties
      ..asciiFont = 'Georgia'
      ..csFont = 'Georgia'
      ..fontSizeHalfPoints = 28
      ..bold = true
      ..italic = true
      ..underline = WmlUnderline.double
      ..strike = true
      ..color = '1F4E79'
      ..highlight = 'FFFF00'
      ..vertAlign = WmlVertAlign.superscript;

    final Uint8List saved = controller.saveBytes();
    final Map<String, Uint8List> parts = _parts(saved);
    final String documentXml = utf8.decode(parts['word/document.xml']!);
    expect(documentXml, contains('w:lineRule="auto"'));
    expect(documentXml, contains('w:line="360"'));
    expect(documentXml, contains('w:before="120"'));
    expect(documentXml, contains('w:after="200"'));
    expect(documentXml, contains('w:left="360"'));
    expect(documentXml, contains('w:right="240"'));
    expect(documentXml, contains('w:firstLine="120"'));
    expect(documentXml, contains('<w:tabs>'));
    expect(documentXml, contains('w:dropCap'));
    expect(documentXml, contains('w:shd'));
    expect(documentXml, contains('w:pBdr'));
    expect(documentXml, contains('w:keepLines'));
    expect(documentXml, contains('w:pageBreakBefore'));

    final WordEditorController reopened =
        WordEditorController.fromBytes(saved);
    addTearDown(reopened.dispose);
    final WmlParagraph after = reopened.document.paragraphs.first;
    expect(after.properties.justification, WmlJustification.center);
    expect(after.properties.lineSpacing, 1.5);
    expect(after.properties.spacingBefore, 6);
    expect(after.properties.spacingAfter, 10);
    expect(after.properties.indent.left, 18);
    expect(after.properties.indent.right, 12);
    expect(after.properties.indent.firstLine, 6);
    expect(after.properties.tabs.map((WmlTabStop t) => t.position), [72, 144]);
    expect(after.properties.dropCapLines, 2);
    expect(after.properties.shadingFill?.toUpperCase(), 'FFF2CC');
    expect(after.properties.borderColor?.toUpperCase(), 'C00000');
    expect(after.properties.keepTogether, isTrue);
    expect(after.properties.pageBreakBefore, isTrue);

    final WmlRun runAfter = after.inlines.whereType<WmlRun>().first;
    expect(runAfter.properties.asciiFont, 'Georgia');
    expect(runAfter.properties.fontSizeHalfPoints, 28);
    expect(runAfter.properties.bold, isTrue);
    expect(runAfter.properties.italic, isTrue);
    expect(runAfter.properties.underline, WmlUnderline.double);
    expect(runAfter.properties.strike, isTrue);
    expect(runAfter.properties.color.toUpperCase(), '1F4E79');
    expect(runAfter.properties.highlight?.toUpperCase(), 'FFFF00');
    expect(runAfter.properties.vertAlign, WmlVertAlign.superscript);
  });

  test('exact and at-least line-spacing rules serialize correctly', () {
    final Uint8List original =
        File('test/fixtures/footnote.docx').readAsBytesSync();
    final WordEditorController controller =
        WordEditorController.fromBytes(original);
    addTearDown(controller.dispose);
    controller.document.paragraphs.toList()[0].properties
      ..lineSpacing = 18
      ..lineSpacingRule = WmlLineSpacingRule.exact;
    controller.document.paragraphs.toList()[1].properties
      ..lineSpacing = 20
      ..lineSpacingRule = WmlLineSpacingRule.atLeast;

    final String xmlText = utf8.decode(
      _parts(controller.saveBytes())['word/document.xml']!,
    );
    expect(xmlText, contains('w:lineRule="exact"'));
    expect(xmlText, contains('w:lineRule="atLeast"'));
    expect(xmlText, contains('w:line="360"'));
    expect(xmlText, contains('w:line="400"'));
  });


  test('saved package follows strict OOXML child order', () {
    final Uint8List original =
        File('test/fixtures/footnote.docx').readAsBytesSync();
    final WordEditorController controller =
        WordEditorController.fromBytes(original);
    addTearDown(controller.dispose);
    final p = controller.document.paragraphs.first;
    p.properties
      ..lineSpacing = 1.5
      ..lineSpacingRule = WmlLineSpacingRule.auto
      ..tabs = const <WmlTabStop>[WmlTabStop(position: 72)]
      ..dropCapLines = 2
      ..shadingFill = 'FFF2CC'
      ..borderColor = 'C00000'
      ..keepTogether = true;
    p.inlines.whereType<WmlRun>().first.properties
      ..highlight = 'FFFF00'
      ..vertAlign = WmlVertAlign.superscript;

    final parts = _parts(controller.saveBytes());
    for (final name in <String>[
      'word/document.xml',
      'word/footnotes.xml',
      'word/styles.xml',
      'word/numbering.xml',
    ]) {
      final doc = xml.XmlDocument.parse(utf8.decode(parts[name]!));
      _assertOrder(doc, 'pPr', _pPrOrder);
      _assertOrder(doc, 'rPr', _rPrOrder);
      _assertOrder(doc, 'sectPr', _sectPrOrder);
      for (final hi in doc.descendants.whereType<xml.XmlElement>()) {
        if (hi.name.local == 'highlight') {
          expect(<String>{
            'yellow','green','cyan','magenta','blue','red','darkBlue',
            'darkCyan','darkGreen','darkMagenta','darkRed','darkYellow',
            'darkGray','lightGray','black','white',
          }, contains(hi.attributes
              .firstWhere((a) => a.name.local == 'val')
              .value));
        }
      }
    }
  });

  test('style assignment survives save and reopen', () {
    final Uint8List original =
        File('test/fixtures/footnote.docx').readAsBytesSync();
    final WordEditorController controller =
        WordEditorController.fromBytes(original);
    addTearDown(controller.dispose);
    controller.applyStyle('Heading1');

    final WordEditorController reopened =
        WordEditorController.fromBytes(controller.saveBytes());
    addTearDown(reopened.dispose);
    expect(reopened.document.paragraphs.first.properties.styleId, 'Heading1');
  });
}
