/// Morphological analysis contract for Arabic proofing rules.
///
/// Implementations wrap a morphological analyzer (the native CrispEmbed port
/// of the camel_tools analyzer over the user-downloaded Camel Morph MSA
/// database, `noprob` variant); rules depend only on this interface so they
/// can be tested with a fake and run without the analyzer installed.
///
/// Feature names and values follow camel_tools / Camel Morph (for example
/// `lex`, `pos`, `gen`, `num`, `cas`, `stt`, `mod`, `asp`, `per`, `vox`,
/// `rat`, `form_gen`, `form_num`, `prc0`–`prc3`, `enc0`, `diac`, `bw`).
/// Analyses carry no ranking: the `noprob` database has no corpus
/// probabilities, so rules must reason over the full analysis set (for
/// example: report only when no analysis of a word is compatible).
library;

/// One analysis: camel_tools feature name to value.
typedef ArabicAnalysis = Map<String, String>;

/// Analyzer abstraction used by Arabic grammar rules.
abstract interface class ArabicMorphology {
  /// Whether the analyzer and its database are installed and loaded.
  bool get isAvailable;

  /// Analyses for each distinct surface [words] entry, in no particular
  /// order. Unknown words map to an empty list; every requested word is a
  /// key of the result. Words are passed exactly as they appear in the text
  /// (harakat and tatweel included); normalization is the analyzer's job.
  Future<Map<String, List<ArabicAnalysis>>> analyzeWords(
    Iterable<String> words,
  );
}

/// Placeholder used when no analyzer is installed: never available, analyzes
/// nothing. Morphology-dependent rules stay silent with it.
class UnavailableArabicMorphology implements ArabicMorphology {
  const UnavailableArabicMorphology();

  @override
  bool get isAvailable => false;

  @override
  Future<Map<String, List<ArabicAnalysis>>> analyzeWords(
    Iterable<String> words,
  ) async => <String, List<ArabicAnalysis>>{
    for (final word in words) word: const <ArabicAnalysis>[],
  };
}
