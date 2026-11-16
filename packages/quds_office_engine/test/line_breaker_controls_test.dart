import 'package:quds_office_engine/src/bidi/line_breaker.dart';
import 'package:test/test.dart';

double _width(int cp) => cp == 0x20 ? 3 : 6;

String _painted(BrokenLine line) =>
    String.fromCharCodes(line.glyphs.map((glyph) => glyph.codePoint));

ShapedGlyph _advance(ShapedGlyph glyph, double advance) => ShapedGlyph(
  codePoint: glyph.codePoint,
  glyphId: glyph.glyphId,
  advance: advance,
  logicalIndex: glyph.logicalIndex,
  level: glyph.level,
  isSpace: glyph.isSpace,
  paintDx: glyph.paintDx,
  paintDy: glyph.paintDy,
  isDiscretionaryHyphen: glyph.isDiscretionaryHyphen,
  sourceLength: glyph.sourceLength,
);

List<BrokenLine> _prepared(
  String text,
  double maxWidth, {
  bool breakLongWords = false,
  bool remeasure = false,
}) {
  final prepared = LineBreaker.prepare(
    text: text,
    widthOf: remeasure ? (_) => 1 : _width,
    justify: false,
    breakLongWords: breakLongWords,
    measureLine: remeasure
        ? (glyphs) => [
            for (final glyph in glyphs)
              _advance(glyph, _width(glyph.codePoint)),
          ]
        : null,
  );
  final lines = <BrokenLine>[];
  final consumedSource = StringBuffer();
  var offset = 0;
  while (offset < text.length) {
    final next = prepared.breakNext(start: offset, maxWidth: maxWidth);
    expect(next.nextOffset, greaterThan(offset));
    expect(next.nextOffset, lessThanOrEqualTo(text.length));
    consumedSource.write(text.substring(offset, next.nextOffset));
    lines.add(next.line);
    offset = next.nextOffset;
  }
  expect(consumedSource.toString(), text);
  return lines;
}

void _expectBoth(
  String text,
  double maxWidth,
  List<String> expected, {
  bool breakLongWords = false,
  bool remeasure = false,
}) {
  final fixed = LineBreaker.breakLines(
    text: text,
    maxWidth: maxWidth,
    widthOf: remeasure ? (_) => 1 : _width,
    justify: false,
    breakLongWords: breakLongWords,
    measureLine: remeasure
        ? (glyphs) => [
            for (final glyph in glyphs)
              _advance(glyph, _width(glyph.codePoint)),
          ]
        : null,
  );
  final variable = _prepared(
    text,
    maxWidth,
    breakLongWords: breakLongWords,
    remeasure: remeasure,
  );
  for (final lines in [fixed, variable]) {
    expect(lines.map(_painted), expected);
    final visibleSource = <int>[];
    var at = 0;
    for (final cp in text.runes) {
      if (cp != 0x20 &&
          cp != 0x200b &&
          cp != 0x200e &&
          cp != 0x2060 &&
          cp != 0xfeff) {
        visibleSource.add(at);
      }
      at += cp > 0xffff ? 2 : 1;
    }
    final actualSource =
        lines
            .expand((line) => line.glyphs)
            .where((glyph) => !glyph.isSpace)
            .map((glyph) => glyph.logicalIndex)
            .toList()
          ..sort();
    expect(actualSource, visibleSource);
    expect(
      lines
          .expand((line) => line.glyphs)
          .any(
            (glyph) =>
                glyph.codePoint == 0x200b ||
                glyph.codePoint == 0x2060 ||
                glyph.codePoint == 0xfeff,
          ),
      isFalse,
    );
  }
  expect(variable.map((line) => line.width), fixed.map((line) => line.width));
}

void main() {
  for (final separator in [
    '\u200b',
    '\u200b\u200b',
    '\u200b\u200e',
    '\u200b   ',
  ]) {
    test(
      'zero width space offers an invisible source-preserving break: $separator',
      () {
        _expectBoth('ab${separator}cd', 12, ['ab', 'cd']);
      },
    );
  }

  test('zero width space preserves supplementary source offsets', () {
    _expectBoth('😀a\u200bcd', 12, ['😀a', 'cd']);
  });

  for (final joiner in ['\u2060', '\ufeff']) {
    test('word joiner suppresses a hyphen break: $joiner', () {
      _expectBoth(
        'ab-$joiner'
        'cd',
        18,
        ['ab-cd'],
      );
    });
    test('word joiner suppresses the preceding space break: $joiner', () {
      _expectBoth(
        'ab $joiner'
        'cd',
        18,
        ['ab cd'],
      );
    });
    test('a space after the joiner still permits its own break: $joiner', () {
      _expectBoth('ab$joiner cd', 12, ['ab', 'cd']);
    });
    test('emergency wrapping keeps the joiner boundary together: $joiner', () {
      _expectBoth(
        'a-$joiner'
        'b',
        6,
        ['a', '-b'],
        breakLongWords: true,
      );
    });
  }

  test(
    'explicit zero width opportunities take precedence over word joiners',
    () {
      for (final gap in ['\u200b\u2060', '\u2060\u200b', '\u200b  \u2060']) {
        _expectBoth('ab${gap}cd', 12, ['ab', 'cd']);
      }
    },
  );

  test('contextual overflow repair uses invisible break opportunities', () {
    _expectBoth('ab\u200bcd ef', 12, ['ab', 'cd', 'ef'], remeasure: true);
  });

  test('contextual overflow repair retains word joiner constraints', () {
    _expectBoth('ab-\u2060cd ef', 18, ['ab-cd', 'ef'], remeasure: true);
  });
}
