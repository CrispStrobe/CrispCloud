import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlDocument _document(String text, {bool automatic = false}) {
  final document = WmlDocument.empty(text: text)
    ..proofingLanguage = 'de-DE'
    ..autoHyphenation = automatic;
  document.sections.single
    ..pageSize = const WmlPageSize(width: 42, height: 200)
    ..margins = const WmlPageMargins(left: 10, right: 10, top: 10, bottom: 10);
  return document;
}

List<LaidOutLine> _lines(WmlDocument document) => WordLayoutEngine(
  font: null,
  measure: (cp, size, props) => cp == 0x2d ? 3 : 6,
).layout(document).pages.expand((page) => page.lines).toList();

String _painted(LaidOutLine line, String source) =>
    PaintRunText.paintSegments(line)
        .map((run) => PaintRunText.runText(source, run))
        .join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  for (final automatic in [false, true]) {
    test(
      'paints ${automatic ? 'automatic' : 'manual'} break with source-aware hit testing',
      () {
        final source = automatic ? 'Silben' : 'Sil\u00adben';
        final document = _document(source, automatic: automatic);
        final lines = _lines(document);
        expect(lines, hasLength(2));
        expect(lines.map((line) => _painted(line, source)), ['Sil-', 'ben']);
        expect(lines.map((line) => line.text).join(), source);
        final first = lines.first;
        PaintRunText.fitLine(first, source);
        final hyphen = first.glyphs.singleWhere(
          (g) => g.glyph.isDiscretionaryHyphen,
        );
        expect(hyphen.displayText, '-');
        expect(hyphen.advance, greaterThan(0));
        expect(hyphen.logicalEnd, automatic ? 3 : 4);
        expect(hyphen.actualText, automatic ? '' : '\u00ad');
        final left = hyphen.x;
        final right = left + hyphen.advance;
        for (final (fraction, expected) in [
          (0.1, 3),
          (0.9, automatic ? 3 : 4),
        ]) {
          final x = left + (right - left) * fraction;
          expect(
            PaintRunText.hitLogicalIndexOnLine(first, x, paragraph: source),
            expected,
          );
          expect(CaretEngine.hitLogicalIndex(first, x), expected);
        }
        expect(CaretEngine.logicalSpan(first).max, automatic ? 3 : 4);
        expect(
          CaretEngine.visualStops(first).map((stop) => stop.index),
          isNot(contains(automatic ? 4 : 5)),
        );
        final selected = CaretEngine.rangeRectsOnLine(
          first,
          first.y,
          first.height,
          0,
          automatic ? 3 : 4,
        );
        expect(selected.single.right, closeTo(right, .01));
        expect(document.paragraphs.single.text, source);
      },
    );
  }

  test('unselected soft hyphen has the same width and caret position as plain text', () {
    final document = _document('Sil\u00adben');
    document.sections.single.pageSize = const WmlPageSize(
      width: 200,
      height: 200,
    );
    final line = _lines(document).single;
    PaintRunText.fitLine(line, 'Sil\u00adben');
    final painter = PaintRunText.painterFor(
      text: 'Silben',
      first: line.glyphs.first,
    )..layout();
    addTearDown(painter.dispose);
    expect(line.width, closeTo(painter.width, .01));
    expect(line.glyphs.any((g) => g.glyph.isDiscretionaryHyphen), isFalse);
    expect(
      PaintRunText.caretXOnLine(line, 4, paragraph: 'Sil\u00adben'),
      closeTo(line.x + PaintRunText.caretDx(painter, 3), .01),
    );
    expect(line.text, 'Sil\u00adben');
  });

  test('automatic hyphen keeps the preceding formatting at a run boundary', () {
    final document = _document('Silben', automatic: true);
    document.paragraphs.single.inlines
      ..clear()
      ..addAll([
        WmlRun(text: 'Sil', properties: WmlRunProps(bold: true)),
        WmlRun(text: 'ben'),
      ]);
    final lines = _lines(document);
    final hyphen = lines.first.glyphs.last;
    expect(hyphen.glyph.isDiscretionaryHyphen, isTrue);
    expect(hyphen.bold, isTrue);
    expect(lines.last.glyphs.first.bold, isFalse);
    expect(lines.map((line) => _painted(line, 'Silben')), ['Sil-', 'ben']);
  });

  test('last non-BMP source character is painted as a complete scalar', () {
    final document = _document('Hi 😀');
    document.sections.single.pageSize = const WmlPageSize(
      width: 200,
      height: 200,
    );
    final line = _lines(document).single;
    expect(_painted(line, 'Hi 😀'), 'Hi 😀');
    expect(line.text, 'Hi 😀');
    PaintRunText.fitLine(line, 'Hi 😀');
    final finalGlyph = line.glyphs.last;
    expect(
      PaintRunText.hitLogicalIndexOnLine(
        line,
        finalGlyph.x + finalGlyph.advance * .95,
        paragraph: 'Hi 😀',
      ),
      5,
    );
  });

  test('presentation labels retain adjacent invisible authored controls', () {
    final document = _document('a\u00adb');
    document.sections.single.pageSize = const WmlPageSize(
      width: 200,
      height: 200,
    );
    document.paragraphs.single.inlines
      ..clear()
      ..addAll([
        WmlRun(text: 'a', properties: WmlRunProps(smallCaps: true)),
        WmlRun(text: '\u00adb'),
      ]);
    final line = _lines(document).single;
    expect(line.text, 'A\u00adb');
    expect(document.paragraphs.single.text, 'a\u00adb');
  });

  test(
    'RTL paragraph paints each German discretionary hyphen as its own run',
    () {
      final document = _document('مرحبا Silbentrennung', automatic: true);
      document.sections.single.pageSize = const WmlPageSize(
        width: 68,
        height: 300,
      );
      document.paragraphs.single.properties.rightToLeft = true;
      final lines = _lines(document);
      final hyphens = lines
          .expand((line) => line.glyphs)
          .where((g) => g.glyph.isDiscretionaryHyphen);
      expect(hyphens, isNotEmpty);
      for (final line in lines) {
        for (final run in PaintRunText.paintSegments(line)) {
          if (run.any((g) => g.glyph.isDiscretionaryHyphen)) {
            expect(run, hasLength(1));
            expect(
              PaintRunText.runText(document.paragraphs.single.text, run),
              '-',
            );
          }
        }
      }
      expect(document.paragraphs.single.text, 'مرحبا Silbentrennung');
    },
  );
}
