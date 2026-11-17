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
  if (unit >= 0xdc00 && unit <= 0xdfff && offset > 0) {
    final before = text.codeUnitAt(offset - 1);
    if (before >= 0xd800 && before <= 0xdbff) start--;
  } else if (unit >= 0xd800 && unit <= 0xdbff && end < text.length) {
    final after = text.codeUnitAt(end);
    if (after >= 0xdc00 && after <= 0xdfff) end++;
  }
  return _identifierPart.hasMatch(text.substring(start, end));
}
