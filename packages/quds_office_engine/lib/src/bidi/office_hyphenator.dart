import 'english_hyphenator.dart';
import 'german_hyphenator.dart';
import 'hyphenation_words.dart';

/// Automatic hyphenation for the languages with explicitly licensed patterns.
///
/// English uses separate American and British patterns; German preserves its
/// reformed-orthography implementation. Unsupported languages receive no
/// automatic candidates. Explicit U+00AD handling remains in the line breaker.
abstract final class OfficeHyphenator {
  static bool supports(String? language) =>
      EnglishHyphenator.supports(language) ||
      GermanHyphenator.supports(language);

  static List<int> wordOffsets(String word, {required String? language}) {
    if (EnglishHyphenator.supports(language)) {
      return EnglishHyphenator.wordOffsets(word, language: language);
    }
    return GermanHyphenator.wordOffsets(word, language: language);
  }

  /// Return sorted original UTF-16 offsets, honoring per-run language scope.
  static List<int> breakOffsets(
    String text, {
    String? language,
    String? Function(int sourceOffset)? languageAt,
    bool allowGermanSoftHyphenAlternatives = false,
  }) {
    if (languageAt == null) {
      if (EnglishHyphenator.supports(language)) {
        return EnglishHyphenator.breakOffsets(text, language: language);
      }
      return GermanHyphenator.breakOffsets(
        text,
        language: language,
        allowSoftHyphenAlternatives: allowGermanSoftHyphenAlternatives,
      );
    }
    return [
      for (final item in hyphenationCandidates(
        text,
        language: language,
        languageAt: languageAt,
        supported: const {'en-US', 'en-GB', 'de-DE', 'de-AT', 'de-CH'},
      ))
        for (final offset
            in item.language.startsWith('en-')
                ? EnglishHyphenator.wordOffsets(
                    item.word,
                    language: item.language,
                  )
                : GermanHyphenator.wordOffsets(
                    item.word,
                    language: item.language,
                    allowSoftHyphenAlternatives:
                        allowGermanSoftHyphenAlternatives,
                  ))
          item.start + offset,
    ];
  }
}
