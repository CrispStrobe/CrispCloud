import 'package:quds_office_engine/src/bidi/line_breaker.dart';
import 'package:test/test.dart';

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

double _estimate(int cp) => cp == 32 ? 5 : 10;

List<ShapedGlyph> _actual(List<ShapedGlyph> glyphs) => [
  for (final glyph in glyphs) _advance(glyph, glyph.isSpace ? 5 : 10.25),
];

String _painted(BrokenLine line) => String.fromCharCodes(
  line.glyphs.where((g) => g.codePoint != 0).map((g) => g.codePoint),
);

List<int> _sourceInk(List<BrokenLine> lines) =>
    lines
        .expand((line) => line.glyphs)
        .where((glyph) => !glyph.isSpace && !glyph.isDiscretionaryHyphen)
        .map((glyph) => glyph.logicalIndex)
        .toList()
      ..sort();

void main() {
  test('remeasured trimmed lines repair a context-dependent overflow', () {
    const text = 'aa bb cc dd';
    final approximate = LineBreaker.breakLines(
      text: text,
      maxWidth: 45.5,
      widthOf: _estimate,
      justify: false,
    );
    expect(_painted(approximate.first), 'aa bb');
    final seen = <List<ShapedGlyph>>[];
    final lines = LineBreaker.breakLines(
      text: text,
      maxWidth: 45.5,
      widthOf: _estimate,
      justify: false,
      measureLine: (glyphs) {
        seen.add(glyphs);
        return _actual(glyphs);
      },
    );
    expect(lines.map(_painted), ['aa', 'bb', 'cc', 'dd']);
    expect(lines.map((line) => line.width), everyElement(20.5));
    expect(_sourceInk(lines), _sourceInk(approximate));
    expect(seen.every((slice) => !slice.last.isSpace), isTrue);
    for (final slice in seen) {
      expect(
        slice.map((glyph) => glyph.logicalIndex).toList(),
        orderedEquals(
          slice.map((glyph) => glyph.logicalIndex).toList()..sort(),
        ),
      );
    }
  });

  test('prepared widths use the same repair and preserve hard breaks', () {
    const text = 'aa bb\r\n\r\ncc 😀 dd\nee ff';
    final fixed = LineBreaker.breakLines(
      text: text,
      maxWidth: 45.5,
      widthOf: _estimate,
      justify: false,
      measureLine: _actual,
    );
    final prepared = LineBreaker.prepare(
      text: text,
      widthOf: _estimate,
      justify: false,
      measureLine: _actual,
    );
    final lines = <BrokenLine>[];
    var offset = 0;
    while (offset < text.length) {
      final next = prepared.breakNext(start: offset, maxWidth: 45.5);
      expect(next.nextOffset, greaterThan(offset));
      expect(next.nextOffset, lessThanOrEqualTo(text.length));
      lines.add(next.line);
      offset = next.nextOffset;
    }
    expect(lines.map(_painted), fixed.map(_painted));
    expect(lines.map((line) => line.width), fixed.map((line) => line.width));
    expect(_sourceInk(lines), _sourceInk(fixed));
    expect(lines.where((line) => line.glyphs.isEmpty), hasLength(1));
  });

  test('prepared retries cache metrics without consuming source', () {
    final calls = <String, int>{};
    final prepared = LineBreaker.prepare(
      text: 'aa bb cc dd',
      widthOf: _estimate,
      justify: false,
      measureLine: (glyphs) {
        final key = glyphs.map((glyph) => glyph.logicalIndex).join(',');
        calls.update(key, (count) => count + 1, ifAbsent: () => 1);
        return _actual(glyphs);
      },
    );
    final narrow = prepared.breakNext(start: 0, maxWidth: 45.5);
    final wide = prepared.breakNext(start: 0, maxWidth: 100);
    final repeated = prepared.breakNext(start: 0, maxWidth: 45.5);
    expect(_painted(narrow.line), 'aa');
    expect(wide.nextOffset, greaterThan(narrow.nextOffset));
    expect(repeated.nextOffset, narrow.nextOffset);
    expect(repeated.line.width, narrow.line.width);
    expect(calls.values, everyElement(1));
  });

  test('overflow repair bounds host calls even when no word can fit', () {
    final text = List.filled(80, 'a').join(' ');
    final calls = <int, int>{};
    final lines = LineBreaker.breakLines(
      text: text,
      maxWidth: 1,
      widthOf: (_) => 0.001,
      justify: false,
      measureLine: (glyphs) {
        calls.update(
          glyphs.first.logicalIndex,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        return [for (final glyph in glyphs) _advance(glyph, 100)];
      },
    );
    expect(lines, hasLength(80));
    expect(lines.map(_painted), everyElement('a'));
    // One initial estimate, at most 32 repair candidates, and final emission
    // if the bounded paragraph cache has already evicted the selected slice.
    expect(calls.values, everyElement(lessThanOrEqualTo(34)));
    expect(_sourceInk(lines), [for (var i = 0; i < text.length; i += 2) i]);
  });

  for (final emergency in [false, true]) {
    test('emergency source-grapheme cuts are opt-in: $emergency', () {
      final lines = LineBreaker.breakLines(
        text: 'A\u0308BC',
        maxWidth: 21,
        widthOf: (_) => 1,
        justify: false,
        breakLongWords: emergency,
        measureLine: (glyphs) => [
          for (final glyph in glyphs)
            _advance(glyph, glyph.logicalIndex == 1 ? 0 : 12),
        ],
      );
      expect(
        lines.map(_painted),
        emergency ? ['A\u0308', 'B', 'C'] : ['A\u0308BC'],
      );
      expect(_sourceInk(lines), [0, 1, 2, 3]);
      if (emergency) {
        expect(lines.map((line) => line.width), everyElement(12));
      } else {
        expect(lines.single.width, 36);
      }
    });
  }

  test('an oversized source grapheme remains intact and makes progress', () {
    final prepared = LineBreaker.prepare(
      text: 'A\u0308B',
      widthOf: (_) => 1,
      justify: false,
      breakLongWords: true,
      measureLine: (glyphs) => [
        for (final glyph in glyphs)
          _advance(glyph, glyph.logicalIndex == 0 ? 30 : 0),
      ],
    );
    final first = prepared.breakNext(start: 0, maxWidth: 10);
    expect(_painted(first.line), 'A\u0308');
    expect(first.line.width, 30);
    expect(first.nextOffset, 2);
    final second = prepared.breakNext(start: first.nextOffset, maxWidth: 10);
    expect(_painted(second.line), 'B');
    expect(second.nextOffset, 3);
  });

  for (final spaces in [' ', '   ']) {
    test('contextual emergency repair consumes boundary spaces: "$spaces"', () {
      final text = 'A\u0308${spaces}BC';
      List<ShapedGlyph> actual(List<ShapedGlyph> glyphs) => [
        for (final glyph in glyphs)
          _advance(
            glyph,
            glyph.logicalIndex == 0
                ? 10
                : glyph.logicalIndex == 1
                ? 0
                : 3,
          ),
      ];

      final fixed = LineBreaker.breakLines(
        text: text,
        maxWidth: 5,
        widthOf: (_) => 0.1,
        justify: false,
        breakLongWords: true,
        measureLine: actual,
      );
      final prepared = LineBreaker.prepare(
        text: text,
        widthOf: (_) => 0.1,
        justify: false,
        breakLongWords: true,
        measureLine: actual,
      );
      final first = prepared.breakNext(start: 0, maxWidth: 5);
      // The oversized grapheme stays whole, with its following spaces owned
      // by the same line instead of becoming a blank or indented next line.
      expect(first.nextOffset, 2 + spaces.length);
      final variable = <BrokenLine>[];
      var offset = 0;
      while (offset < text.length) {
        final next = prepared.breakNext(start: offset, maxWidth: 5);
        expect(next.nextOffset, greaterThan(offset));
        variable.add(next.line);
        offset = next.nextOffset;
      }
      for (final lines in [fixed, variable]) {
        expect(lines.map(_painted), ['A\u0308', 'B', 'C']);
        expect(
          lines.every(
            (line) =>
                line.glyphs.isNotEmpty && line.glyphs.first.codePoint != 32,
          ),
          isTrue,
        );
        expect(_sourceInk(lines), [0, 1, 2 + spaces.length, 3 + spaces.length]);
        expect(lines.first.width, 10);
        expect(lines.skip(1).map((line) => line.width), everyElement(3));
      }
    });
  }

  test('natural breaks never detach a mark from a source space grapheme', () {
    final lines = LineBreaker.breakLines(
      text: 'A \u0308B C',
      maxWidth: 13,
      widthOf: (_) => 6,
      justify: false,
    );
    final markedSpaceLine = lines.singleWhere(
      (line) => line.glyphs.any((glyph) => glyph.logicalIndex == 1),
    );
    expect(
      markedSpaceLine.glyphs.map((glyph) => glyph.logicalIndex),
      contains(2),
    );
    expect(lines.any((line) => line.glyphs.first.logicalIndex == 2), isFalse);
  });

  test('selected hyphens are measured with their original source records', () {
    final observed = <ShapedGlyph>[];
    final lines = LineBreaker.breakLines(
      text: 'ab\u00adcd',
      maxWidth: 35,
      widthOf: (_) => 10,
      justify: false,
      measureLine: (glyphs) {
        observed.addAll(glyphs.where((glyph) => glyph.isDiscretionaryHyphen));
        return glyphs;
      },
    );
    expect(lines.map(_painted), ['ab-', 'cd']);
    expect(observed, isNotEmpty);
    expect(observed.first.logicalIndex, 2);
    expect(observed.first.sourceLength, 1);
    expect(lines.first.logicalEnd, 3);
    expect(_sourceInk(lines), [0, 1, 3, 4]);
  });

  test(
    'a newly oversized discretionary hyphen does not split a whole word',
    () {
      final lines = LineBreaker.breakLines(
        text: 'abcdef',
        maxWidth: 35,
        widthOf: (_) => 10,
        hyphenationOffsets: [2, 4],
        justify: false,
        measureLine: (glyphs) => [
          for (final glyph in glyphs)
            _advance(glyph, glyph.isDiscretionaryHyphen ? 100 : glyph.advance),
        ],
      );
      expect(lines.map(_painted), ['abcdef']);
      expect(
        lines.single.glyphs.any((glyph) => glyph.isDiscretionaryHyphen),
        isFalse,
      );
      expect(_sourceInk(lines), [0, 1, 2, 3, 4, 5]);
    },
  );

  for (final invalid in ['remove', 'reorder', 'negative', 'infinite']) {
    test(
      'invalid $invalid measurement retains original source and metrics',
      () {
        final lines = LineBreaker.breakLines(
          text: 'abcd',
          maxWidth: 100,
          widthOf: (_) => 10,
          justify: false,
          measureLine: (glyphs) => switch (invalid) {
            'remove' => glyphs.sublist(1),
            'reorder' => glyphs.reversed.toList(),
            'negative' => [for (final glyph in glyphs) _advance(glyph, -1)],
            _ => [for (final glyph in glyphs) _advance(glyph, double.infinity)],
          },
        );
        expect(_painted(lines.single), 'abcd');
        expect(lines.single.width, 40);
        expect(_sourceInk(lines), [0, 1, 2, 3]);
      },
    );
  }
}
