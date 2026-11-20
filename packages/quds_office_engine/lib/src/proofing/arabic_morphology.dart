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
///
/// An implementation may also implement [ArabicContextMorphology]: with a
/// downloaded context disambiguation model it ranks each word's analyses in
/// its sentence ([ArabicContextReading]). Rules may then narrow a word to its
/// best reading when that reading clearly leads, and keep reasoning over all
/// analyses otherwise.
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

/// One token's analyses ranked in its sentence by a context disambiguator.
///
/// Analyses that share the model's tag, lemma and part of speech form one
/// candidate; [scores] gives each analysis its candidate's probability in
/// context (the candidates of a token sum to 1) and [ranks] the candidate's
/// rank (0 = best).
final class ArabicContextReading {
  ArabicContextReading(this.analyses, this.scores, this.ranks)
    : assert(analyses.length == scores.length),
      assert(analyses.length == ranks.length);

  /// A token without analyses (unknown or rejected word).
  static final ArabicContextReading none = ArabicContextReading(
    const <ArabicAnalysis>[],
    const <double>[],
    const <int>[],
  );

  /// Every analysis, in the analyzer's order.
  final List<ArabicAnalysis> analyses;
  final List<double> scores;
  final List<int> ranks;

  /// Score of the best candidate (0 when there are no analyses).
  double get bestScore {
    for (int i = 0; i < ranks.length; i++) {
      if (ranks[i] == 0) return scores[i];
    }
    return 0;
  }

  /// How far the best candidate leads the second (its score when it is the
  /// only one).
  double get margin {
    double second = 0;
    for (int i = 0; i < ranks.length; i++) {
      if (ranks[i] == 1) second = scores[i];
    }
    return bestScore - second;
  }

  /// The analyses of the best candidate.
  List<ArabicAnalysis> get best => <ArabicAnalysis>[
    for (int i = 0; i < analyses.length; i++)
      if (ranks[i] == 0) analyses[i],
  ];

  /// [best] when it leads by at least [minMargin], otherwise null.
  List<ArabicAnalysis>? confident(double minMargin) =>
      analyses.isNotEmpty && margin >= minMargin ? best : null;
}

/// An [ArabicMorphology] that can also rank analyses in context.
abstract interface class ArabicContextMorphology implements ArabicMorphology {
  /// Whether a context disambiguation model is installed and loaded.
  bool get canDisambiguate;

  /// Readings of every token of every sentence, in order. Tokens come from
  /// [arabicContextSentences]: punctuation, numbers and Latin words are
  /// tokens too, because they are context. Without a model (or when it
  /// fails) the result is empty.
  Future<List<List<ArabicContextReading>>> disambiguate(
    List<List<String>> sentences,
  );
}

/// A token of [arabicContextSentences]: its text and UTF-16 range.
final class ArabicContextToken {
  const ArabicContextToken(this.text, this.start, this.end);
  final String text;
  final int start;
  final int end;
}

/// Tokens of [text] grouped into sentences, as the context disambiguation
/// model was trained (CrispEmbed `tools/arabic_morph/disambig_train.py`): an
/// Arabic word (a letter, then letters, harakat and tatweel), a number, a run
/// of other letters, or any other single non-space character. A line break
/// and the marks `. ! ? ؟ …` end a sentence (the mark stays in it).
List<List<ArabicContextToken>> arabicContextSentences(String text) {
  final List<List<ArabicContextToken>> sentences = <List<ArabicContextToken>>[];
  List<ArabicContextToken> current = <ArabicContextToken>[];
  int lineEnd = text.indexOf('\n');
  for (final RegExpMatch m in _contextToken.allMatches(text)) {
    while (lineEnd >= 0 && lineEnd < m.start) {
      if (current.isNotEmpty) sentences.add(current);
      current = <ArabicContextToken>[];
      lineEnd = text.indexOf('\n', lineEnd + 1);
    }
    final String token = m.group(0)!;
    current.add(ArabicContextToken(token, m.start, m.end));
    if (_sentenceEnd.contains(token)) {
      sentences.add(current);
      current = <ArabicContextToken>[];
    }
  }
  if (current.isNotEmpty) sentences.add(current);
  return sentences;
}

final RegExp _contextToken = RegExp(
  '[ء-غف-يٱ-ۓ][ء-غف-يٱ-ۓً-ٰٟـ]*'
  r'|[0-9٠-٩۰-۹]+(?:[.,٫٬][0-9٠-٩۰-۹]+)*'
  r'|[\p{L}\p{Nl}\p{No}]+'
  r'|\S',
  unicode: true,
);
const Set<String> _sentenceEnd = <String>{'.', '!', '?', '؟', '…'};
