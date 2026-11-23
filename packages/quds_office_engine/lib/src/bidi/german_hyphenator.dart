import '../proofing/office_proofing.dart';
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
  static List<int> wordOffsets(
    String word, {
    String? language = 'de-DE',
    bool allowSoftHyphenAlternatives = false,
  }) {
    if (!supports(language)) return const [];
    if (word.contains('\u00ad')) {
      return allowSoftHyphenAlternatives
          ? _offsetsWithSoftHyphens(word, language)
          : const [];
    }
    if (word.contains("'") || word.contains('’') || word.contains('ʼ')) {
      return const [];
    }
    if (word.length >= 4 && word.length <= 128 && _isPlainGerman(word)) {
      final normalized = word.toLowerCase();
      // These letters are single UTF-16 source units before and after case
      // folding. Offsets from the pattern cache are already source offsets.
      return List<int>.of(_cachedMatches(normalized));
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
    return [
      for (final offset in _cachedMatches(letters.join(), letters))
        sourceOffsets[offset],
    ];
  }

  static bool _isPlainGerman(String word) {
    for (var i = 0; i < word.length; i++) {
      final unit = word.codeUnitAt(i);
      if ((unit >= 0x41 && unit <= 0x5a) || (unit >= 0x61 && unit <= 0x7a)) {
        continue;
      }
      if (!const {
        0xc4,
        0xd6,
        0xdc,
        0xdf,
        0xe4,
        0xf6,
        0xfc,
        0x1e9e,
      }.contains(unit)) {
        return false;
      }
    }
    return true;
  }

  static List<int> _cachedMatches(String normalized, [List<String>? letters]) {
    final cached = _cache[normalized];
    if (cached != null) return cached;
    final positions = _match(letters ?? normalized.split(''));
    if (_cache.length >= 2048) _cache.remove(_cache.keys.first);
    _cache[normalized] = positions;
    return positions;
  }

  /// Paragraph candidates. A word crossing a language boundary is skipped.
  static List<int> breakOffsets(
    String text, {
    String? language,
    String? Function(int sourceOffset)? languageAt,
    bool allowSoftHyphenAlternatives = false,
  }) {
    return [
      for (final item in hyphenationCandidates(
        text,
        language: language,
        languageAt: languageAt,
        supported: const {'de-DE', 'de-AT', 'de-CH'},
      ))
        for (final offset in wordOffsets(
          item.word,
          language: item.language,
          allowSoftHyphenAlternatives: allowSoftHyphenAlternatives,
        ))
          item.start + offset,
    ];
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
