import '../proofing/office_proofing.dart';
import '../proofing/proofing_text_ranges.dart';
import 'german_hyphenation_data.dart';
import 'grapheme_clusters.dart';
import 'hyphenation_words.dart';

/// German reformed-orthography break opportunities in original UTF-16 units.
///
/// The bundled MIT patterns are independently licensed from the implementation;
/// see third_party/hyphenation. This never edits or normalizes source text.
abstract final class GermanHyphenator {
  static String? _language(String? language) {
    return language == null ? null : normalizeProofingLanguage(language);
  }

  static bool supports(String? language) =>
      const {'de-DE', 'de-AT', 'de-CH'}.contains(_language(language));

  static final _PatternNode _root = _readPatterns();
  static final Map<String, List<int>> _cache = {};
  static final RegExp _letter = RegExp(r'^\p{L}$', unicode: true);

  /// Candidate boundaries for one word; no candidates inside source graphemes.
  static List<int> wordOffsets(String word, {String? language = 'de-DE'}) {
    if (!supports(language) ||
        word.contains('\u00ad') ||
        word.contains("'") ||
        word.contains('’') ||
        word.contains('ʼ')) {
      return const [];
    }
    final letters = <String>[];
    final sourceOffsets = <int>[0];
    for (final cluster in GraphemeClusters.segment(word)) {
      final normalized = _composeUmlaut(
        word.substring(cluster.start, cluster.end),
      ).toLowerCase();
      if (!_letter.hasMatch(normalized) || normalized.runes.length != 1) {
        return const [];
      }
      letters.add(normalized);
      sourceOffsets.add(cluster.end);
    }
    if (letters.length < 4 || letters.length > 128) return const [];
    final normalized = letters.join();
    var positions = _cache[normalized];
    if (positions == null) {
      positions = _match(letters);
      if (_cache.length >= 2048) _cache.remove(_cache.keys.first);
      _cache[normalized] = positions;
    }
    return [for (final offset in positions) sourceOffsets[offset]];
  }

  /// Paragraph candidates. A word crossing a language boundary is skipped.
  static List<int> breakOffsets(
    String text, {
    String? language,
    String? Function(int sourceOffset)? languageAt,
    bool allowSoftHyphenAlternatives = false,
  }) {
    if (languageAt == null && !supports(language)) return const [];
    final result = <int>[];
    final protected = OfficeProofingTextRanges(text);
    for (final word in hyphenationWords.allMatches(text)) {
      if (protected.overlaps(word.start, word.end)) continue;
      final wordLanguage = languageAt?.call(word.start) ?? language;
      if (!supports(wordLanguage)) continue;
      if ((word.start > 0 &&
              isHyphenationIdentifierNeighbor(text, word.start - 1)) ||
          (word.end < text.length &&
              isHyphenationIdentifierNeighbor(text, word.end))) {
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
      final source = word.group(0)!;
      final offsets = allowSoftHyphenAlternatives && source.contains('\u00ad')
          ? _offsetsWithSoftHyphens(source, wordLanguage)
          : wordOffsets(source, language: wordLanguage);
      result.addAll(offsets.map((n) => word.start + n));
    }
    return result;
  }

  static List<int> _offsetsWithSoftHyphens(String source, String? language) {
    final clean = StringBuffer();
    final originalOffsets = <int>[0];
    for (var i = 0; i < source.length; i++) {
      final unit = source.codeUnitAt(i);
      if (unit == 0xad) {
        // The authored opportunity already belongs to the line breaker. Map
        // a coincident automatic candidate to the same source boundary.
        originalOffsets[originalOffsets.length - 1] = i + 1;
      } else {
        clean.writeCharCode(unit);
        originalOffsets.add(i + 1);
      }
    }
    return [
      for (final offset in wordOffsets(clean.toString(), language: language))
        originalOffsets[offset],
    ];
  }

  static String _composeUmlaut(String cluster) => switch (cluster) {
    'a\u0308' => 'ä',
    'o\u0308' => 'ö',
    'u\u0308' => 'ü',
    'A\u0308' => 'Ä',
    'O\u0308' => 'Ö',
    'U\u0308' => 'Ü',
    _ => cluster,
  };

  static List<int> _match(List<String> letters) {
    final word = ['.', ...letters, '.'];
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
      for (var cut = 2; cut <= letters.length - 2; cut++)
        if (scores[cut + 1].isOdd) cut,
    ];
  }

  static _PatternNode _readPatterns() {
    final root = _PatternNode();
    for (final pattern in germanHyphenationPatterns.trim().split('\n')) {
      var node = root;
      final values = <int>[0];
      for (final cp in pattern.runes) {
        if (cp >= 48 && cp <= 57) {
          values[values.length - 1] = cp - 48;
        } else {
          node = node.children.putIfAbsent(
            String.fromCharCode(cp),
            _PatternNode.new,
          );
          values.add(0);
        }
      }
      node.values = values;
    }
    return root;
  }
}

class _PatternNode {
  final Map<String, _PatternNode> children = {};
  List<int>? values;
}
