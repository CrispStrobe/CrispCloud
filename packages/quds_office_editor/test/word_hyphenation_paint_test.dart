import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

List<LaidOutLine> _lines(
  String source,
  double width, {
  List<int> offsets = const [],
}) => [
  for (final broken in LineBreaker.breakLines(
    text: source,
    maxWidth: width,
    widthOf: (cp) => cp == 0x2d ? 3 : 6,
    justify: false,
    hyphenationOffsets: offsets,
  ))
    LaidOutLine(
      glyphs: [
        for (final glyph in broken.glyphs)
          LaidOutGlyph(
            glyph: glyph,
            x: 10,
            y: 20,
            color: '000000',
            fontSize: 12,
            bold: false,
            underline: WmlUnderline.none,
          ),
      ],
      x: 10,
      y: 10,
      width: broken.width,
      height: 14,
      pageIndex: 0,
      justification: WmlJustification.left,
      sourceText: source,
    ),
];

String _paintText(LaidOutLine line, String source) =>
    PaintRunText.paintSegments(
      line,
    ).map((run) => PaintRunText.runText(source, run)).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test('automatic break paints a hyphen and owns only its source boundary', () {
    const source = 'Silben';
    final lines = _lines(source, 22, offsets: [3]);
    expect(lines.map((line) => _paintText(line, source)), ['Sil-', 'ben']);
    expect(lines.map((line) => line.text), ['Sil', 'ben']);
    for (final line in lines) {
      PaintRunText.fitLine(line, source);
    }
    final first = lines.first;
    final hyphen = first.glyphs.singleWhere(
      (g) => g.glyph.isDiscretionaryHyphen,
    );
    expect(hyphen.advance, greaterThan(0));
    expect(hyphen.logicalEnd, 3);
    expect(CaretEngine.logicalSpan(first), (min: 0, max: 3));
    for (final fraction in [0.1, 0.9]) {
      final x = hyphen.x + hyphen.advance * fraction;
      expect(
        PaintRunText.hitLogicalIndexOnLine(first, x, paragraph: source),
        3,
      );
      expect(CaretEngine.hitLogicalIndex(first, x), 3);
    }
    expect(
      PaintRunText.caretXOnLine(first, 3, paragraph: source),
      closeTo(hyphen.x + hyphen.advance, 0.001),
    );
    expect(
      CaretEngine.caretX(first, 3),
      closeTo(hyphen.x + hyphen.advance, 0.001),
    );
    expect(CaretEngine.visualStops(first).map((stop) => stop.index), [
      0,
      1,
      2,
      3,
    ]);
  });

  test('selected soft hyphen paints visibly with its original UTF-16 span', () {
    const source = 'Sil\u00adben';
    final lines = _lines(source, 22);
    expect(lines.map((line) => _paintText(line, source)), ['Sil-', 'ben']);
    expect(lines.map((line) => line.text), ['Sil\u00ad', 'ben']);
    final first = lines.first;
    PaintRunText.fitLine(first, source);
    final hyphen = first.glyphs.last;
    expect(hyphen.glyph.logicalIndex, 3);
    expect(hyphen.logicalEnd, 4);
    expect(
      PaintRunText.hitLogicalIndexOnLine(
        first,
        hyphen.x + hyphen.advance * 0.1,
        paragraph: source,
      ),
      3,
    );
    expect(
      PaintRunText.hitLogicalIndexOnLine(
        first,
        hyphen.x + hyphen.advance * 0.9,
        paragraph: source,
      ),
      4,
    );
    expect(
      PaintRunText.caretXOnLine(first, 4, paragraph: source),
      closeTo(hyphen.x + hyphen.advance, 0.001),
    );
  });

  test(
    'selecting the next source span does not select an automatic hyphen',
    () {
      const source = 'Silben';
      final line = LineBreaker.breakLines(
        text: source,
        maxWidth: 22,
        widthOf: (cp) => cp == 0x2d ? 3 : 6,
        justify: false,
        hyphenationOffsets: [3],
      ).first;
      expect(CaretEngine.rangeRects(line, 0, 12, 3, 6), isEmpty);
      expect(CaretEngine.rangeRects(line, 0, 12, 0, 3).single.width, 21);
      final laid = _lines(source, 22, offsets: [3]).first;
      PaintRunText.fitLine(laid, source);
      expect(CaretEngine.rangeRectsOnLine(laid, 0, 12, 3, 6), isEmpty);
    },
  );

  test('unselected soft hyphen remains invisible without shifting caret', () {
    const source = 'Sil\u00adben';
    final line = _lines(source, 100).single;
    expect(line.glyphs.any((g) => g.glyph.isDiscretionaryHyphen), isFalse);
    PaintRunText.fitLine(line, source);
    final plain = PaintRunText.painterFor(
      text: 'Silben',
      first: line.glyphs.first,
    )..layout();
    addTearDown(plain.dispose);
    expect(line.width, closeTo(plain.width, 0.001));
    expect(
      PaintRunText.caretXOnLine(line, 3, paragraph: source),
      closeTo(PaintRunText.caretXOnLine(line, 4, paragraph: source), 0.001),
    );
    expect(line.text, source);
  });

  test('surrogate pairs and combining marks next to a break stay complete', () {
    for (final source in ['😀ab', 'a\u0308ab']) {
      final line = _lines(source, 15, offsets: [2]).first;
      expect(_paintText(line, source), '${source.substring(0, 2)}-');
      expect(line.text, source.substring(0, 2));
      PaintRunText.fitLine(line, source);
      final hyphen = line.glyphs.last;
      expect(
        PaintRunText.hitLogicalIndexOnLine(
          line,
          hyphen.x + hyphen.advance * 0.8,
          paragraph: source,
        ),
        2,
      );
    }
  });

  test('RTL discretionary breaks have no fabricated source unit', () {
    const source = 'אבגד';
    final line = _lines(source, 15, offsets: [2]).first;
    PaintRunText.fitLine(line, source);
    final hyphen = line.glyphs.first;
    expect(hyphen.glyph.isDiscretionaryHyphen, isTrue);
    expect(CaretEngine.logicalSpan(line), (min: 0, max: 2));
    expect(line.text, 'אב');
    expect(PaintRunText.runText(source, [hyphen]), '-');
    for (final fraction in [0.1, 0.9]) {
      expect(
        PaintRunText.hitLogicalIndexOnLine(
          line,
          hyphen.x + hyphen.advance * fraction,
          paragraph: source,
        ),
        2,
      );
    }
    expect(
      PaintRunText.caretXOnLine(line, 2, paragraph: source),
      closeTo(hyphen.x, 0.001),
    );
  });

  test('manual and automatic breaks keep distinct source offsets together', () {
    const source = 'Sil\u00adben Silben';
    final lines = _lines(source, 22, offsets: [11]);
    final hyphens = <LaidOutGlyph>[];
    for (final line in lines) {
      PaintRunText.fitLine(line, source);
      for (final glyph in line.glyphs.where(
        (glyph) => glyph.glyph.isDiscretionaryHyphen,
      )) {
        hyphens.add(glyph);
        expect(PaintRunText.runText(source, [glyph]), '-');
        expect(
          PaintRunText.hitLogicalIndexOnLine(
            line,
            glyph.x + glyph.advance * 0.9,
            paragraph: source,
          ),
          glyph.logicalEnd,
        );
      }
    }
    expect(hyphens.map((g) => (g.glyph.logicalIndex, g.logicalEnd)), [
      (3, 4),
      (11, 11),
    ]);
    expect(lines.last.text, 'ben');
  });

  test('RTL explicit break hit testing follows the source direction', () {
    const source = 'אב\u00adגד';
    final line = _lines(source, 15).first;
    PaintRunText.fitLine(line, source);
    final hyphen = line.glyphs.first;
    expect(hyphen.glyph.isDiscretionaryHyphen, isTrue);
    expect(
      PaintRunText.hitLogicalIndexOnLine(
        line,
        hyphen.x + hyphen.advance * 0.1,
        paragraph: source,
      ),
      3,
    );
    expect(
      PaintRunText.hitLogicalIndexOnLine(
        line,
        hyphen.x + hyphen.advance * 0.9,
        paragraph: source,
      ),
      2,
    );
  });

  test('Word layout renders German automatic breaks from unchanged text', () {
    const source = 'Silbentrennung';
    final document = WmlDocument.empty(text: source)
      ..proofingLanguage = 'de-DE'
      ..autoHyphenation = true;
    document.sections.single.pageSize = const WmlPageSize(
      width: 70,
      height: 160,
    );
    document.sections.single.margins = const WmlPageMargins(
      left: 10,
      right: 10,
      top: 10,
      bottom: 10,
    );
    final controller = WordEditorController(document: document);
    addTearDown(controller.dispose);
    final lines = controller.documentLaidOut.pages.expand((page) => page.lines);
    expect(
      lines
          .expand((line) => line.glyphs)
          .any((g) => g.glyph.isDiscretionaryHyphen),
      isTrue,
    );
    expect(lines.map((line) => line.text).join(), source);
    for (final line in lines) {
      final visible = _paintText(line, source);
      if (line.glyphs.any((g) => g.glyph.isDiscretionaryHyphen)) {
        expect(visible, endsWith('-'));
        expect(visible.substring(0, visible.length - 1), line.text);
      }
    }
    expect(document.paragraphs.single.text, source);
    expect(
      WordDeserializer()
          .readBytes(controller.saveBytes())
          .paragraphs
          .single
          .text,
      source,
    );
  });
}
