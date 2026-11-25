import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlRunProps _mark() => WmlRunProps()
  ..bold = true
  ..italic = true
  ..fontSizeHalfPoints = 40
  ..color = 'C00000'
  ..asciiFont = 'Georgia';

void main() {
  group('WmlRunEdit.propsAt', () {
    test('an empty paragraph reads its paragraph mark', () {
      final WmlRunProps mark = _mark();
      final paragraph = WmlParagraph(
        properties: WmlParagraphProps()..importedParagraphMark = mark.copy(),
        inlines: <WmlInline>[WmlRun()],
      );

      expect(WmlRunEdit.propsAt(paragraph, 0).bold, isTrue);
      expect(WmlRunEdit.propsAt(paragraph, 0).fontSizeHalfPoints, 40);
      expect(WmlRunEdit.propsAt(paragraph, 0).color, 'C00000');
    });

    test('typing in an empty paragraph continues the mark formatting', () {
      final paragraph = WmlParagraph(
        properties: WmlParagraphProps()..importedParagraphMark = _mark(),
        inlines: <WmlInline>[WmlRun()],
      );

      WmlRunEdit.replaceRange(paragraph, 0, 0, 'Typed');

      final run = paragraph.inlines.whereType<WmlRun>().single;
      expect(run.text, 'Typed');
      expect(run.properties.bold, isTrue);
      expect(run.properties.fontSizeHalfPoints, 40);
    });

    test('a non-empty paragraph reads the run at the offset', () {
      final first = WmlRun(
        text: 'plain',
        properties: WmlRunProps()..fontSizeHalfPoints = 20,
      );
      final second = WmlRun(
        text: 'bold',
        properties: WmlRunProps()
          ..bold = true
          ..fontSizeHalfPoints = 32,
      );
      final paragraph = WmlParagraph(inlines: <WmlInline>[first, second]);

      expect(WmlRunEdit.propsAt(paragraph, 0).fontSizeHalfPoints, 20);
      expect(WmlRunEdit.propsAt(paragraph, 4).fontSizeHalfPoints, 20);
      expect(WmlRunEdit.propsAt(paragraph, 5).bold, isTrue);
      expect(WmlRunEdit.propsAt(paragraph, 9).bold, isTrue);
    });
  });

  group('paragraph mark layout', () {
    test('a split mark advances the empty line at its own size', () {
      final font = SfntFont.parse(
        File(
          '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
        ).readAsBytesSync(),
      );
      final engine = WordLayoutEngine(
        font: null,
        measureFont: (int _, double size, WmlRunProps _) =>
            FontMetrics(font: font, fontSizePoints: size),
      );
      const int halfPoints = 40;
      final document = WmlDocument.empty();
      final first = document.paragraphs.first;
      first.inlines
        ..clear()
        ..add(
          WmlRun(
            text: 'Body',
            properties: WmlRunProps()..fontSizeHalfPoints = halfPoints,
          ),
        );
      first.properties = first.properties.copy()
        ..spacingBefore = 0
        ..spacingAfter = 0
        ..importedParagraphMark = (WmlRunProps()
          ..fontSizeHalfPoints = halfPoints);
      final empty = WmlParagraph(
        properties: WmlParagraphProps(spacingBefore: 0, spacingAfter: 0)
          ..importedParagraphMark = (WmlRunProps()
            ..fontSizeHalfPoints = halfPoints),
        inlines: <WmlInline>[WmlRun()],
      );
      final next = WmlParagraph(
        properties: WmlParagraphProps(spacingBefore: 0, spacingAfter: 0),
        inlines: <WmlInline>[
          WmlRun(
            text: 'Next',
            properties: WmlRunProps()..fontSizeHalfPoints = halfPoints,
          ),
        ],
      );
      document.sections.first.blocks.addAll(<WmlBlock>[empty, next]);

      final lines = engine.layout(document).pages.first.lines;

      expect(lines, hasLength(2));
      final lineHeight =
          FontMetrics(
            font: font,
            fontSizePoints: halfPoints / 2,
          ).typographicLineHeight *
          1.15;
      expect(lines[1].y - lines[0].y, closeTo(lineHeight * 2, 1.0));
    });
  });

  group('paragraph mark round trip', () {
    test('pPr/rPr keeps the continuation format across save and reopen', () {
      final document = WmlDocument.empty(text: 'Body');
      final paragraph = document.paragraphs.first;
      paragraph.properties = paragraph.properties.copy()
        ..spacingBefore = 12
        ..spacingAfter = 18
        ..lineSpacing = 1.5
        ..explicitLineSpacing = true
        ..explicitSpacingBefore = true
        ..explicitSpacingAfter = true
        ..indent = const WmlIndent(left: 24, right: 6, firstLine: 3)
        ..explicitIndent = true
        ..justification = WmlJustification.center
        ..explicitJustification = true
        ..importedParagraphMark = _mark();

      final bytes = WordSerializer().writeBytes(document);
      final reopened = WordDeserializer().readBytes(bytes);
      final reopenedProps = reopened.paragraphs.first.properties;

      expect(reopenedProps.spacingBefore, 12);
      expect(reopenedProps.spacingAfter, 18);
      expect(reopenedProps.lineSpacing, 1.5);
      expect(reopenedProps.indent.left, 24);
      expect(reopenedProps.indent.right, 6);
      expect(reopenedProps.indent.firstLine, 3);
      expect(reopenedProps.justification, WmlJustification.center);
      final mark = reopenedProps.importedParagraphMark;
      expect(mark, isNotNull);
      expect(mark!.bold, isTrue);
      expect(mark.italic, isTrue);
      expect(mark.fontSizeHalfPoints, 40);
      expect(mark.color, 'C00000');
    });

    test('an empty paragraph keeps its mark after a fresh save', () {
      final document = WmlDocument.empty();
      final paragraph = document.paragraphs.first;
      paragraph.properties = paragraph.properties.copy()
        ..importedParagraphMark = _mark();

      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );

      expect(reopened.paragraphs.first.text, '');
      expect(
        reopened.paragraphs.first.properties.importedParagraphMark?.bold,
        isTrue,
      );
      expect(
        reopened
            .paragraphs
            .first
            .properties
            .importedParagraphMark
            ?.fontSizeHalfPoints,
        40,
      );
    });
  });
}
