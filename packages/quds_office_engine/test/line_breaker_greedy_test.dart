import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

String textOf(BrokenLine line) =>
    String.fromCharCodes(line.glyphs.map((g) => g.codePoint));

void main() {
  test(
    'Word-style greedy wrapping consumes the longest fitting word prefix',
    () {
      final lines = LineBreaker.breakLines(
        text: 'aaaa bbb c dd eeee',
        maxWidth: 10,
        widthOf: (_) => 1,
        justify: false,
        balanceLines: false,
      );
      expect(lines.map(textOf), ['aaaa bbb c', 'dd eeee']);
    },
  );

  test(
    'prepared and static greedy layout preserve hard breaks and space ownership',
    () {
      const source = 'ab- cd ef gh\nlast words here';
      final staticLines = LineBreaker.breakLines(
        text: source,
        maxWidth: 6,
        widthOf: (_) => 1,
        justify: false,
        balanceLines: false,
      );
      final prepared = LineBreaker.prepare(
        text: source,
        widthOf: (_) => 1,
        justify: false,
        balanceLines: false,
      );
      final actual = <BrokenLine>[];
      var offset = 0;
      while (offset < source.length) {
        final next = prepared.breakNext(start: offset, maxWidth: 6);
        expect(next.nextOffset, greaterThan(offset));
        actual.add(next.line);
        offset = next.nextOffset;
      }
      expect(actual.map(textOf), staticLines.map(textOf));
      expect(actual.every((line) => !textOf(line).startsWith(' ')), isTrue);
      expect(
        actual.map((line) => line.logicalStart),
        staticLines.map((line) => line.logicalStart),
      );
    },
  );

  test(
    'an oversized word stays intact unless grapheme breaking is requested',
    () {
      final intact = LineBreaker.breakLines(
        text: 'abcdefghij',
        maxWidth: 4,
        widthOf: (_) => 1,
        justify: false,
        balanceLines: false,
      );
      expect(intact, hasLength(1));
      expect(textOf(intact.single), 'abcdefghij');
      final split = LineBreaker.breakLines(
        text: 'abcdefghij',
        maxWidth: 4,
        widthOf: (_) => 1,
        justify: false,
        balanceLines: false,
        breakLongWords: true,
      );
      expect(split.map(textOf), ['abcd', 'efgh', 'ij']);
    },
  );

  test('discretionary breaks retain hyphen ownership and width', () {
    final lines = LineBreaker.breakLines(
      text: 'ab\u00adcdef',
      maxWidth: 3,
      widthOf: (_) => 1,
      justify: false,
      balanceLines: false,
    );
    expect(textOf(lines.first), 'ab-');
    expect(lines.first.glyphs.last.isDiscretionaryHyphen, isTrue);
    expect(lines.first.glyphs.last.sourceLength, 1);
    expect(textOf(lines.last), 'cdef');
  });
}
