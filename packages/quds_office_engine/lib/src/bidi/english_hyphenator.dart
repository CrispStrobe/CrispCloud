import 'english_gb_hyphenation_data.dart';
import 'english_us_hyphenation_data.dart';

/// American and British English opportunities in original UTF-16 source units.
///
/// The pinned pattern sets have independent permissive licenses; see
/// third_party/hyphenation/ENGLISH.md. Only the explicitly supported dialects
/// receive automatic breaks. Authored soft hyphens always take precedence.
abstract final class EnglishHyphenator {
  static String? _language(String? language) {
    final normalized = language?.trim().replaceAll('_', '-').toLowerCase();
    return normalized == 'en' ? 'en-us' : normalized;
  }

  static bool supports(String? language) =>
      const {'en-us', 'en-gb'}.contains(_language(language));

  static final _EnglishPatternSet _american = _EnglishPatternSet(
    englishUsHyphenationPatterns,
    englishUsHyphenationExceptions,
  );
  static final _EnglishPatternSet _british = _EnglishPatternSet(
    englishGbHyphenationPatterns,
    englishGbHyphenationExceptions,
  );
  static final RegExp _letters = RegExp(r'^[a-zA-Z]+$');
  // Keep contractions and possessives whole so their pieces cannot receive
  // independent dictionary breaks. Quotation marks around a word stay outside.
  static final RegExp _words = RegExp(
    r"[\p{L}][\p{L}\p{M}\u00ad]*(?:['\u2019\u02bc][\p{L}\p{M}\u00ad]+)*",
    unicode: true,
  );

  static final RegExp _protectedTokens = RegExp(
    r'(?:https?://|www\.)[^\s<>\u0022\u0027\u0060]+|'
    r'[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}|'
    r'(?<!`)(`+)(?!`)[\s\S]*?(?<!`)\1(?!`)',
    unicode: true,
    caseSensitive: false,
  );

  /// Breaks for a plain Latin word, with at least two letters before and
  /// three after each break. Accented words, identifiers, contractions and
  /// words containing an explicit soft hyphen are conservatively skipped.
  ///
  /// These pattern sets contain ASCII letters only. Rejecting other source
  /// characters avoids normalization or breaks inside a source grapheme.
  static List<int> wordOffsets(String word, {String? language = 'en-US'}) {
    if (!supports(language) ||
        word.length < 5 ||
        word.length > 128 ||
        !_letters.hasMatch(word)) {
      return const [];
    }
    final patterns = _language(language) == 'en-gb' ? _british : _american;
    return patterns.offsets(word.toLowerCase());
  }

  /// Paragraph candidates. A word crossing a language boundary is skipped.
  static List<int> breakOffsets(
    String text, {
    String? language,
    String? Function(int sourceOffset)? languageAt,
  }) {
    if (languageAt == null && !supports(language)) return const [];
    final result = <int>[];
    final protected = _protectedTokens.allMatches(text).toList(growable: false);
    var protectedIndex = 0;
    for (final word in _words.allMatches(text)) {
      while (protectedIndex < protected.length &&
          protected[protectedIndex].end <= word.start) {
        protectedIndex++;
      }
      if (protectedIndex < protected.length &&
          protected[protectedIndex].start < word.end) {
        continue;
      }
      final wordLanguage = languageAt?.call(word.start) ?? language;
      if (!supports(wordLanguage)) continue;
      // Do not treat the letter portion of an identifier as ordinary prose.
      if ((word.start > 0 && _identifierNeighbor(text, word.start - 1)) ||
          (word.end < text.length && _identifierNeighbor(text, word.end))) {
        continue;
      }
      if (languageAt != null) {
        var homogeneous = true;
        for (var at = word.start; at < word.end; at++) {
          if (_language(languageAt(at) ?? language) !=
              _language(wordLanguage)) {
            homogeneous = false;
            break;
          }
        }
        if (!homogeneous) continue;
      }
      result.addAll(
        wordOffsets(
          word.group(0)!,
          language: wordLanguage,
        ).map((offset) => word.start + offset),
      );
    }
    return result;
  }

  static final RegExp _identifierPart = RegExp(
    r'[\p{N}_@\u200c\u200d\u2060\ufeff]',
    unicode: true,
  );
  static bool _identifierNeighbor(String text, int offset) {
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
}

final class _EnglishPatternSet {
  _EnglishPatternSet(this.patterns, this.exceptions);

  final String patterns;
  final String exceptions;
  late final _EnglishPatternNode _root = _readPatterns();
  late final Map<String, List<int>> _exceptions = _readExceptions();
  final Map<String, List<int>> _cache = {};

  List<int> offsets(String word) {
    var positions = _cache[word];
    if (positions == null) {
      positions = _exceptions[word] ?? _match(word);
      if (_cache.length >= 2048) _cache.remove(_cache.keys.first);
      _cache[word] = positions;
    }
    // Callers must not be able to mutate future cached results.
    return List<int>.of(positions);
  }

  List<int> _match(String source) {
    final word = [46, ...source.codeUnits, 46];
    final scores = List<int>.filled(word.length + 1, 0);
    for (var start = 0; start < word.length; start++) {
      var node = _root;
      for (var at = start; at < word.length; at++) {
        final child = node.children[word[at]];
        if (child == null) break;
        node = child;
        final values = node.values;
        if (values == null) continue;
        for (var j = 0; j < values.length; j++) {
          if (values[j] > scores[start + j]) scores[start + j] = values[j];
        }
      }
    }
    return [
      for (var cut = 2; cut <= source.length - 3; cut++)
        if (scores[cut + 1].isOdd) cut,
    ];
  }

  _EnglishPatternNode _readPatterns() {
    final root = _EnglishPatternNode();
    for (final pattern in patterns.trim().split('\n')) {
      var node = root;
      final values = <int>[0];
      for (final cp in pattern.codeUnits) {
        if (cp >= 48 && cp <= 57) {
          values[values.length - 1] = cp - 48;
        } else {
          node = node.children.putIfAbsent(cp, _EnglishPatternNode.new);
          values.add(0);
        }
      }
      node.values = values;
    }
    return root;
  }

  Map<String, List<int>> _readExceptions() {
    final result = <String, List<int>>{};
    for (final exception in exceptions.trim().split('\n')) {
      var offset = 0;
      final positions = <int>[];
      for (final cp in exception.codeUnits) {
        if (cp == 45) {
          positions.add(offset);
        } else {
          offset++;
        }
      }
      // A word without hyphens is an explicit no-break exception, not a
      // missing entry; it must not fall through to the pattern matcher.
      result[exception.replaceAll('-', '')] = [
        for (final position in positions)
          if (position >= 2 && position <= offset - 3) position,
      ];
    }
    return result;
  }
}

final class _EnglishPatternNode {
  final Map<int, _EnglishPatternNode> children = {};
  List<int>? values;
}
