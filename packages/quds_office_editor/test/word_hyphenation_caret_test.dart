import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlDocument _document(
  String text, {
  required double width,
  bool automatic = false,
  bool rtl = false,
}) {
  final document = WmlDocument.empty(text: text)
    ..proofingLanguage = 'de-DE'
    ..autoHyphenation = automatic;
  document.paragraphs.single.properties.rightToLeft = rtl;
  document.sections.single
    ..pageSize = WmlPageSize(width: width + 20, height: 200)
    ..margins = const WmlPageMargins(left: 10, right: 10, top: 10, bottom: 10);
  return document;
}

List<LaidOutLine> _lines(WmlDocument document) => WordLayoutEngine(
  font: null,
  measure: (cp, size, props) => cp == 0x2d ? 3 : 6,
).layout(document).pages.expand((page) => page.lines).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  for (final rtl in [false, true]) {
    test('manual hyphen respects ${rtl ? 'RTL' : 'LTR'} source boundaries', () {
      final source = rtl ? 'אב\u00adגד' : 'ab\u00adcd';
      final document = _document(source, width: 15, rtl: rtl);
      final lines = _lines(document);
      expect(lines, hasLength(2));
      expect(lines.map((line) => line.text).join(), source);
      final line = lines.first;
      PaintRunText.fitLine(line, source);
      final hyphen = line.glyphs.singleWhere(
        (glyph) => glyph.glyph.isDiscretionaryHyphen,
      );
      expect(hyphen.displayText, '-');
      expect(hyphen.glyph.level.isOdd, rtl);
      expect(hyphen.glyph.logicalIndex, 2);
      expect(hyphen.logicalEnd, 3);
      final left = hyphen.x;
      final right = left + hyphen.advance;

      for (final (fraction, expected) in [
        (0.1, rtl ? 3 : 2),
        (0.9, rtl ? 2 : 3),
      ]) {
        final x = left + hyphen.advance * fraction;
        expect(
          PaintRunText.hitLogicalIndexOnLine(line, x, paragraph: source),
          expected,
        );
        expect(CaretEngine.hitLogicalIndex(line, x), expected);
      }
      // The nearest-run fallback must preserve the same source direction
      // when the pointer is just outside the painted end of the line.
      final outside = rtl ? left - 2 : right + 2;
      expect(
        PaintRunText.hitLogicalIndexOnLine(line, outside, paragraph: source),
        3,
      );
      expect(CaretEngine.hitLogicalIndex(line, outside), 3);
      for (final (index, x) in [
        (2, rtl ? right : left),
        (3, rtl ? left : right),
      ]) {
        expect(
          PaintRunText.caretXOnLine(line, index, paragraph: source),
          closeTo(x, .01),
        );
        expect(CaretEngine.caretX(line, index), closeTo(x, .01));
      }
      expect(document.paragraphs.single.text, source);
    });
  }

  for (final paragraphRtl in [false, true]) {
    test(
      'automatic hyphen owns its ending caret in an ${paragraphRtl ? 'RTL' : 'LTR'} paragraph',
      () {
        const source = 'Silben';
        final document = _document(
          source,
          width: 22,
          automatic: true,
          rtl: paragraphRtl,
        );
        final lines = _lines(document);
        expect(lines, hasLength(2));
        expect(lines.map((line) => line.text).join(), source);
        final line = lines.first;
        PaintRunText.fitLine(line, source);
        final hyphen = line.glyphs.singleWhere(
          (glyph) => glyph.glyph.isDiscretionaryHyphen,
        );
        expect(hyphen.glyph.level.isEven, isTrue);
        expect(hyphen.glyph.logicalIndex, 3);
        expect(hyphen.logicalEnd, 3);
        final endX = hyphen.x + hyphen.advance;
        expect(
          PaintRunText.caretXOnLine(line, 3, paragraph: source),
          closeTo(endX, .01),
        );
        expect(CaretEngine.caretX(line, 3), closeTo(endX, .01));
        final stop = CaretEngine.visualStops(
          line,
        ).singleWhere((stop) => stop.index == 3);
        expect(stop.x, closeTo(endX, .01));
        expect(CaretEngine.logicalSpan(line), (min: 0, max: 3));
        for (final fraction in [0.1, 0.9]) {
          final x = hyphen.x + hyphen.advance * fraction;
          expect(
            PaintRunText.hitLogicalIndexOnLine(line, x, paragraph: source),
            3,
          );
          expect(CaretEngine.hitLogicalIndex(line, x), 3);
        }
        expect(document.paragraphs.single.text, source);
      },
    );
  }
}
