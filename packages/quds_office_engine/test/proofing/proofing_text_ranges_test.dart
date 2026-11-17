import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

List<String> protectedText(String text) => OfficeProofingTextRanges(
  text,
).ranges.map((range) => text.substring(range.start, range.end)).toList();

void main() {
  test(
    'Unicode emails and uppercase URLs retain original UTF-16 positions',
    () {
      const text =
          '😀 müller+büro@beispiel.de, HTTPS://example.invalid/Überblick.';
      final protected = OfficeProofingTextRanges(text);
      expect(protectedText(text), [
        'müller+büro@beispiel.de',
        'HTTPS://example.invalid/Überblick',
      ]);
      expect(protected.ranges.first.start, 3);
      expect(protected.overlaps(0, 3), isFalse);
      expect(protected.overlaps(3, 4), isTrue);
      expect(protected.overlaps(text.length - 1, text.length), isFalse);
      expect(protectedText("o'connor@example.invalid"), [
        "o'connor@example.invalid",
      ]);
    },
  );

  test(
    'URL punctuation keeps prose delimiters available to grammar checks',
    () {
      const text = '(https://example.invalid/a_(b)). „https://[::1]/x“';
      expect(protectedText(text), [
        'https://example.invalid/a_(b)',
        'https://[::1]/x',
      ]);
      final ranges = OfficeProofingTextRanges(text);
      expect(ranges.overlaps(0, 1), isFalse);
      final closing = text.indexOf(')).') + 1;
      expect(ranges.overlaps(closing, closing + 1), isFalse);
      expect(ranges.overlaps(text.length - 1, text.length), isFalse);
    },
  );

  test(
    'decomposed email letters and apostrophes in URL paths stay protected',
    () {
      for (final text in [
        'Huas@ba\u0308r.de',
        'mu\u0308ller@büro.example',
        "https://example.invalid/'Silbentrennung",
        "https://example.invalid/a'/Silbentrennung",
      ]) {
        expect(protectedText(text), [text]);
      }
      const quoted = "'https://example.invalid/a' ordinary";
      expect(protectedText(quoted), ['https://example.invalid/a']);
      expect(OfficeProofingTextRanges(quoted).overlaps(0, 1), isFalse);
    },
  );

  test('matching backtick runs own nested ticks and multiline contents', () {
    for (final text in [
      '`ich hast`',
      '``dictionary `hyphenation` organization``',
      '```ich hast\nwir kann```',
    ]) {
      expect(protectedText(text), [text]);
    }
    const mixed = '``unfinished `closed` ordinary';
    expect(protectedText(mixed), ['`closed`']);
    for (final text in ['`unfinished', '``unfinished`', '```']) {
      expect(protectedText(text), isEmpty);
    }
  });

  test('overlapping links and code merge without hiding following prose', () {
    const text = '`https://example.invalid` spelling';
    final protected = OfficeProofingTextRanges(text);
    expect(protectedText(text), ['`https://example.invalid`']);
    final end = text.indexOf(' spelling');
    expect(protected.overlaps(0, 0), isTrue);
    expect(protected.overlaps(end - 1, end - 1), isTrue);
    expect(protected.overlaps(end, end), isFalse);
    expect(protected.overlaps(end, text.length), isFalse);
    expect(protected.overlaps(0, text.length), isTrue);
    expect(() => protected.ranges.clear(), throwsUnsupportedError);
  });

  test('empty input and invalid source intervals have explicit semantics', () {
    final empty = OfficeProofingTextRanges('');
    expect(empty.overlaps(0, 0), isFalse);
    for (final range in [(-1, 0), (0, 1), (1, 0)]) {
      expect(() => empty.overlaps(range.$1, range.$2), throwsRangeError);
    }
  });
}
