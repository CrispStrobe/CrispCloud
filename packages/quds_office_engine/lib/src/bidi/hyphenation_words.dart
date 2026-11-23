import '../proofing/office_proofing.dart';
import '../proofing/proofing_text_ranges.dart';

/// Whole words, including apostrophes, so contractions are never split into
/// unrelated fragments. Language-specific matchers decide accepted letters.
final RegExp hyphenationWords = RegExp(
  r"[\p{L}][\p{L}\p{M}\u00ad]*(?:['\u2019\u02bc][\p{L}\p{M}\u00ad]+)*",
  unicode: true,
);

final RegExp _identifierPart = RegExp(
  r'[\p{N}\p{Pc}@\u200c\u200d\u2060\ufeff]',
  unicode: true,
);

/// Read a whole neighboring scalar, including supplementary-plane digits.
bool isHyphenationIdentifierNeighbor(String text, int offset) {
  var start = offset;
  var end = offset + 1;
  final unit = text.codeUnitAt(offset);
  if (unit < 0x80) {
    return (unit >= 0x30 && unit <= 0x39) || unit == 0x40 || unit == 0x5f;
  }
  if (unit >= 0xdc00 && unit <= 0xdfff && offset > 0) {
    final before = text.codeUnitAt(offset - 1);
    if (before >= 0xd800 && before <= 0xdbff) start--;
  } else if (unit >= 0xd800 && unit <= 0xdbff && end < text.length) {
    final after = text.codeUnitAt(end);
    if (after >= 0xdc00 && after <= 0xdfff) end++;
  }
  return _identifierPart.hasMatch(text.substring(start, end));
}

/// Find source words enclosed by a single supported language. Link and code
/// protection and source offsets are shared by the pattern providers.
Iterable<({int start, String word, String language})> hyphenationCandidates(
  String text, {
  required String? language,
  required String? Function(int)? languageAt,
  required Set<String> supported,
}) sync* {
  final defaultLanguage = language == null
      ? null
      : normalizeProofingLanguage(language);
  if (languageAt == null && !supported.contains(defaultLanguage)) return;
  final aliases = <String, String>{};
  String? resolved(int offset) {
    final raw = languageAt?.call(offset);
    return raw == null
        ? defaultLanguage
        : aliases.putIfAbsent(raw, () => normalizeProofingLanguage(raw));
  }

  final protected = OfficeProofingTextRanges(text);
  for (final word in hyphenationWords.allMatches(text)) {
    if (protected.overlaps(word.start, word.end)) continue;
    final locale = resolved(word.start);
    if (locale == null || !supported.contains(locale)) continue;
    if ((word.start > 0 &&
            isHyphenationIdentifierNeighbor(text, word.start - 1)) ||
        (word.end < text.length &&
            isHyphenationIdentifierNeighbor(text, word.end))) {
      continue;
    }
    if (languageAt != null) {
      var end = word.start + 1;
      while (end < word.end && resolved(end) == locale) {
        end++;
      }
      if (end != word.end) continue;
    }
    yield (start: word.start, word: word.group(0)!, language: locale);
  }
}
