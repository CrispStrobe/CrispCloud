/// Locale-aware Word-style typing substitutions.
///
/// This is deliberately limited to the character the user just typed. It never
/// rewrites pasted text or an unfinished IME composition.
library;

final class WordAutocorrectResult {
  const WordAutocorrectResult(this.text, this.caretDelta);

  final String text;

  /// Difference between the corrected text length and the input text length.
  final int caretDelta;
}

/// Applies Word-style smart quotes and spaced dash substitution.
///
/// [offset] is the index of the single inserted character in [text]. The
/// caller adjusts the caret by [WordAutocorrectResult.caretDelta].
WordAutocorrectResult wordAutocorrectInsertion({
  required String text,
  required int offset,
  required String inserted,
  required String language,
}) {
  if (inserted.length != 1 || offset < 0 || offset >= text.length) {
    return WordAutocorrectResult(text, 0);
  }
  final german = language.toLowerCase().startsWith('de');
  final before = offset == 0 ? '' : text.substring(offset - 1, offset);
  final after = offset + 1 < text.length
      ? text.substring(offset + 1, offset + 2)
      : '';

  if (inserted == '"') {
    final replacement = _opensQuote(before)
        ? (german ? '„' : '“')
        : (german ? '“' : '”');
    return WordAutocorrectResult(
      text.replaceRange(offset, offset + 1, replacement),
      0,
    );
  }
  if (inserted == "'") {
    final replacement = _wordCharacter(before) && _wordCharacter(after)
        ? '’'
        : _opensQuote(before)
        ? (german ? '‚' : '‘')
        : (german ? '‘' : '’');
    return WordAutocorrectResult(
      text.replaceRange(offset, offset + 1, replacement),
      0,
    );
  }
  if (inserted == ' ' && offset >= 2) {
    var firstHyphen = offset - 1;
    while (firstHyphen >= 0 && text[firstHyphen] == '-') {
      firstHyphen--;
    }
    final count = offset - 1 - firstHyphen;
    if (count > 0) {
      final beforeHyphens = firstHyphen < 0 ? '' : text[firstHyphen];
      if (beforeHyphens.isEmpty || _space(beforeHyphens)) {
        final replacement = count >= 3 ? '—' : '–';
        // Replace only the hyphens; the just-typed space stays in place.
        final corrected = text.replaceRange(
          firstHyphen + 1,
          offset,
          replacement,
        );
        return WordAutocorrectResult(corrected, corrected.length - text.length);
      }
    }
  }
  return WordAutocorrectResult(text, 0);
}

bool _opensQuote(String before) =>
    before.isEmpty || _space(before) || '([{<„“‚‘\'"'.contains(before);

bool _space(String value) => RegExp(r'\s').hasMatch(value);

bool _wordCharacter(String value) =>
    value.isNotEmpty && RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(value);
