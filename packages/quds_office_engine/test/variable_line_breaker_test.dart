import 'package:quds_office_engine/src/bidi/line_breaker.dart';
import 'package:test/test.dart';

double _width(int cp) => cp == 32 ? 3 : (cp > 0xffff ? 8 : 6);

List<BrokenLine> _prepared(String text, double Function(int) width) {
  final prepared = LineBreaker.prepare(text: text, widthOf: _width);
  final lines = <BrokenLine>[];
  var offset = 0;
  while (offset < text.length || lines.isEmpty) {
    final next = prepared.breakNext(
      start: offset,
      maxWidth: width(lines.length),
    );
    expect(next.nextOffset, greaterThanOrEqualTo(offset));
    if (offset < text.length) expect(next.nextOffset, greaterThan(offset));
    lines.add(next.line);
    offset = next.nextOffset;
  }
  return lines;
}

void main() {
  test('prepared lines can revisit earlier chunks after width changes', () {
    const text = 'First words together\r\nSecond words apart\nThird';
    PreparedLineBreaker prepare() => LineBreaker.prepare(
      text: text,
      widthOf: _width,
      balanceLines: false,
    );
    final reused = prepare();
    final second = text.indexOf('Second');
    for (final (offset, width) in [
      (0, 42.0),
      (second, 54.0),
      (second + 7, 54.0),
      (text.indexOf('Third'), 54.0),
      (6, 42.0),
      (text.indexOf('\r'), 42.0),
      (second, 54.0),
    ]) {
      final actual = reused.breakNext(start: offset, maxWidth: width);
      final fresh = prepare().breakNext(start: offset, maxWidth: width);
      expect(actual.nextOffset, fresh.nextOffset);
      expect(actual.line.logicalStart, fresh.line.logicalStart);
      expect(actual.line.logicalEnd, fresh.line.logicalEnd);
      expect(actual.line.width, fresh.line.width);
      expect(
        actual.line.glyphs.map((glyph) => glyph.logicalIndex),
        fresh.line.glyphs.map((glyph) => glyph.logicalIndex),
      );
    }
  });

  for (final text in [
    'Alpha beta gamma delta epsilon zeta eta theta iota kappa.',
    'First\r\n\r\nSecond\n\nThird\n',
    '  Leading spaces and trailing spaces   ',
    'Emoji 😀 plus 🧭 and nonbreaking\u00a0space.',
    'مرحبا بالعالم 123 test نهاية',
    '\u2067مرحبا\u2069 English \u2067نهاية\u2069',
  ]) {
    for (final width in [36.0, 90.0]) {
      test('prepared line context matches fixed width $width: $text', () {
        final expected = LineBreaker.breakLines(
          text: text,
          maxWidth: width,
          widthOf: _width,
        );
        final actual = _prepared(text, (_) => width);
        expect(actual, hasLength(expected.length));
        for (var i = 0; i < expected.length; i++) {
          expect(actual[i].width, expected[i].width);
          expect(actual[i].justificationRatio, expected[i].justificationRatio);
          expect(
            actual[i].glyphs.map((g) => [g.codePoint, g.logicalIndex, g.level]),
            expected[i].glyphs.map(
              (g) => [g.codePoint, g.logicalIndex, g.level],
            ),
          );
        }
      });
    }
  }
  for (final spaces in [' ', '   ']) {
    test('soft wrap after hyphen consumes boundary spaces: "$spaces"', () {
      final text = 'Stadt-${spaces}und Kreisjugendringen';
      final fixed = LineBreaker.breakLines(
        text: text,
        maxWidth: 36,
        widthOf: _width,
      );
      final prepared = LineBreaker.prepare(text: text, widthOf: _width);
      final first = prepared.breakNext(start: 0, maxWidth: 36);
      expect(first.nextOffset, 6 + spaces.length);
      for (final lines in [fixed, _prepared(text, (_) => 36)]) {
        expect(
          String.fromCharCodes(lines.first.glyphs.map((g) => g.codePoint)),
          'Stadt-',
        );
        expect(lines[1].glyphs.first.codePoint, 'u'.codeUnitAt(0));
        expect(lines[1].logicalStart, 6 + spaces.length);
        expect(
          lines
              .expand((l) => l.glyphs)
              .where((g) => !g.isSpace)
              .map((g) => g.logicalIndex)
              .toSet()
              .length,
          text.runes.where((cp) => cp != 32).length,
        );
      }
    });
  }
  test('explicit line break preserves intentional leading spaces', () {
    final lines = _prepared('Stadt-\n  und Kreis', (_) => 90);
    expect(lines[1].logicalStart, 7);
    expect(lines[1].glyphs.take(2).every((g) => g.codePoint == 32), isTrue);
  });
  test(
    'nonbreaking space after hyphen is never treated as ordinary boundary space',
    () {
      final prepared = LineBreaker.prepare(
        text: 'Stadt-\u00a0und Kreis',
        widthOf: _width,
      );
      final first = prepared.breakNext(start: 0, maxWidth: 36);
      expect(first.nextOffset, 6);
    },
  );
  test('variable widths consume Unicode and hard breaks exactly once', () {
    const text = 'One 😀 two\r\n\r\nthree 🧭 four five six\nseven eight nine';
    final lines = _prepared(text, (i) => i < 3 ? 38 : 100);
    final indices =
        lines
            .expand((l) => l.glyphs)
            .where((g) => !g.isSpace)
            .map((g) => g.logicalIndex)
            .toList()
          ..sort();
    final expected = <int>[];
    var offset = 0;
    for (final cp in text.runes) {
      if (cp != 32 && cp != 10 && cp != 13) expected.add(offset);
      offset += cp > 0xffff ? 2 : 1;
    }
    expect(indices, expected);
    expect(lines.where((l) => l.glyphs.isEmpty), hasLength(1));
    for (final line in lines) {
      if (line.glyphs.isNotEmpty) {
        expect(
          text.substring(line.logicalStart, line.logicalEnd).runes,
          isNot(contains(0xfffd)),
        );
      }
    }
  });
  test('pagination can retry a source offset without consuming it', () {
    final prepared = LineBreaker.prepare(
      text: 'Alpha beta gamma delta epsilon',
      widthOf: _width,
    );
    final narrow = prepared.breakNext(start: 0, maxWidth: 40);
    final wide = prepared.breakNext(start: 0, maxWidth: 100);
    expect(wide.nextOffset, greaterThan(narrow.nextOffset));
    expect(
      prepared.breakNext(start: 0, maxWidth: 40).nextOffset,
      narrow.nextOffset,
    );
  });
}
