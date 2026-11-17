/// Independently authored German metalinguistic mention conventions.
///
/// These ranges are literal examples, not general quotation protection. A
/// misspelling in ordinary quoted speech remains eligible for checking.
final class GermanLiteralTextRanges {
  GermanLiteralTextRanges(String text) {
    for (final match in _mentions.allMatches(text)) {
      final prefix = text.substring(
        match.start > 80 ? match.start - 80 : 0,
        match.start,
      );
      final suffix = text.substring(
        match.end,
        match.end + 80 < text.length ? match.end + 80 : text.length,
      );
      if (match.group(1)!.isNotEmpty ||
          _declaration.hasMatch(suffix) ||
          _objectMention.hasMatch(prefix)) {
        _ranges.add((match.end - match.group(2)!.length, match.end));
      }
    }
    final quotation = _exampleQuotation.firstMatch(text);
    if (quotation != null &&
        (_quotePairs[quotation.group(1)]?.contains(quotation.group(3)) ??
            false)) {
      // Group two starts immediately after the opening delimiter.
      final opening =
          quotation.group(0)!.indexOf(quotation.group(1)!) +
          quotation.group(1)!.length;
      _ranges.add((opening, opening + quotation.group(2)!.length));
    }
    _ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final range in _ranges) {
      if (merged.isNotEmpty && range.$1 <= merged.last.$2) {
        final previous = merged.removeLast();
        merged.add((
          previous.$1,
          range.$2 > previous.$2 ? range.$2 : previous.$2,
        ));
      } else {
        merged.add(range);
      }
    }
    _ranges
      ..clear()
      ..addAll(merged);
  }

  static const _quotePairs = <String, Set<String>>{
    '„': {'“'},
    '‚': {'‘'},
    '»': {'«'},
    '›': {'‹'},
    '«': {'»'},
    '‹': {'›'},
    '“': {'”'},
    '‘': {'’'},
    '"': {'"'},
    "'": {"'"},
  };
  final List<(int, int)> _ranges = [];
  static final _mentions = RegExp(
    r'''(?<![\p{L}\p{M}])(?:Wort|Ausdruck|Begriff|Titel|Zeichenfolge|Token)[ \t]+([„‚»›«‹“‘"']?)([\p{L}\p{M}]{1,128})(?![\p{L}\p{M}])''',
    unicode: true,
  );
  static final _declaration = RegExp(
    r'^[ \t]+(?:ist|sind|war|waren|bleibt|bleiben|wird|werden|steht|stehen|heißt|heißen|bedeutet|enthält|genannt)(?![\p{L}\p{M}])',
    unicode: true,
  );
  static final _objectMention = RegExp(
    r'(?<![\p{L}\p{M}])(?:habe|hast|hat|haben|habt)[ \t]+(?:das|ein|dieses|jenes|den|einen)[ \t]+$',
    unicode: true,
  );
  static final _exampleQuotation = RegExp(
    r'''^[ \t]*([„‚»›«‹“‘"'])([^\r\n]{1,512})([“‘«‹»›”’"'])[ \t]+(?:(?:steht|erscheint)[ \t]+(?:im Text|im Beispiel|in der Datei)|ist ein Beispiel)[.!]?[ \t]*$''',
    unicode: true,
  );

  bool overlaps(int start, int end) {
    // Merged ranges are disjoint and sorted by both endpoints.
    var low = 0, high = _ranges.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_ranges[middle].$2 < start ||
          start < end && _ranges[middle].$2 == start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low < _ranges.length &&
        (start == end ? _ranges[low].$1 <= start : _ranges[low].$1 < end);
  }
}
