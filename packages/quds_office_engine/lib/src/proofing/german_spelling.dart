import 'dart:async';
import 'dart:convert';

import '../opc/zip/deflate_codec.dart';
import 'data/german_lexicon_data.dart';
import 'office_proofing.dart';

/// Canonicalizes common decomposed Latin letters without changing source text.
/// This comparison helper is deliberately separate from source-offset handling.
String normalizeGermanWord(String word) {
  const Map<String, String> composed = <String, String>{
    'a\u0308': 'ä',
    'o\u0308': 'ö',
    'u\u0308': 'ü',
    'A\u0308': 'Ä',
    'O\u0308': 'Ö',
    'U\u0308': 'Ü',
    'a\u0301': 'á',
    'e\u0301': 'é',
    'i\u0301': 'í',
    'o\u0301': 'ó',
    'u\u0301': 'ú',
    'y\u0301': 'ý',
    'A\u0301': 'Á',
    'E\u0301': 'É',
    'I\u0301': 'Í',
    'O\u0301': 'Ó',
    'U\u0301': 'Ú',
    'Y\u0301': 'Ý',
    'a\u0300': 'à',
    'e\u0300': 'è',
    'i\u0300': 'ì',
    'o\u0300': 'ò',
    'u\u0300': 'ù',
    'A\u0300': 'À',
    'E\u0300': 'È',
    'I\u0300': 'Ì',
    'O\u0300': 'Ò',
    'U\u0300': 'Ù',
    'a\u0302': 'â',
    'e\u0302': 'ê',
    'i\u0302': 'î',
    'o\u0302': 'ô',
    'u\u0302': 'û',
    'A\u0302': 'Â',
    'E\u0302': 'Ê',
    'I\u0302': 'Î',
    'O\u0302': 'Ô',
    'U\u0302': 'Û',
    'c\u0327': 'ç',
    'C\u0327': 'Ç',
    'n\u0303': 'ñ',
    'N\u0303': 'Ñ',
  };
  String result = word;
  for (final MapEntry<String, String> entry in composed.entries) {
    if (result.contains(entry.key)) {
      result = result.replaceAll(entry.key, entry.value);
    }
  }
  return result
      .replaceAll('\u00ad', '')
      .replaceAll('\u2010', '-')
      .replaceAll('\u2011', '-');
}

/// Host-owned personal and session-ignored words. Nothing is persisted or shared
/// by the engine. A host can save [toJson] under [ownerId] in its own storage.
/// Membership is case-sensitive after canonical accent composition.
class OfficeProofingVocabulary {
  OfficeProofingVocabulary({this.ownerId = 'local', this.onChanged});

  factory OfficeProofingVocabulary.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1 || json['ownerId'] is! String) {
      throw const FormatException('Unsupported proofing vocabulary snapshot');
    }
    final OfficeProofingVocabulary result = OfficeProofingVocabulary(
      ownerId: json['ownerId']! as String,
    );
    void restore(Object? value, Map<String, Set<String>> target) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('Invalid vocabulary map');
      }
      for (final MapEntry<String, Object?> entry in value.entries) {
        if (entry.value is! List<Object?>) {
          throw const FormatException('Invalid vocabulary list');
        }
        final Set<String> words = <String>{};
        for (final Object? word in entry.value! as List<Object?>) {
          if (word is! String || word.trim().isEmpty) {
            throw const FormatException('Invalid vocabulary word');
          }
          words.add(normalizeGermanWord(word));
        }
        target[normalizeProofingLanguage(entry.key)] = words;
      }
    }

    restore(json['words'], result._words);
    restore(json['ignoredWords'], result._ignored);
    return result;
  }

  final String ownerId;
  final void Function()? onChanged;
  final Map<String, Set<String>> _words = <String, Set<String>>{};
  final Map<String, Set<String>> _ignored = <String, Set<String>>{};
  int _revision = 0;
  int get revision => _revision;

  Set<String> wordsFor(String language) => Set<String>.unmodifiable(
    _words[normalizeProofingLanguage(language)] ?? const <String>{},
  );
  Set<String> ignoredWordsFor(String language) => Set<String>.unmodifiable(
    _ignored[normalizeProofingLanguage(language)] ?? const <String>{},
  );

  bool contains(String word, {String language = 'de-DE'}) {
    final String key = normalizeProofingLanguage(language);
    final String normalized = normalizeGermanWord(word);
    return (_words[key]?.contains(normalized) ?? false) ||
        (_ignored[key]?.contains(normalized) ?? false);
  }

  void _change(
    Map<String, Set<String>> target,
    String word,
    String language,
    bool add,
  ) {
    final String normalized = normalizeGermanWord(word.trim());
    if (normalized.isEmpty) throw ArgumentError.value(word, 'word');
    final String key = normalizeProofingLanguage(language);
    final Set<String> values = target.putIfAbsent(key, () => <String>{});
    if (add ? values.add(normalized) : values.remove(normalized)) {
      _revision++;
      onChanged?.call();
    }
  }

  void addWord(String word, {String language = 'de-DE'}) =>
      _change(_words, word, language, true);
  void removeWord(String word, {String language = 'de-DE'}) =>
      _change(_words, word, language, false);
  void ignoreWord(String word, {String language = 'de-DE'}) =>
      _change(_ignored, word, language, true);
  void unignoreWord(String word, {String language = 'de-DE'}) =>
      _change(_ignored, word, language, false);

  void clearIgnoredWords() {
    if (_ignored.values.every((Set<String> words) => words.isEmpty)) return;
    _ignored.clear();
    _revision++;
    onChanged?.call();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'ownerId': ownerId,
    'words': <String, Object?>{
      for (final MapEntry<String, Set<String>> entry in _words.entries)
        entry.key: entry.value.toList()..sort(),
    },
    'ignoredWords': <String, Object?>{
      for (final MapEntry<String, Set<String>> entry in _ignored.entries)
        entry.key: entry.value.toList()..sort(),
    },
  };
}

/// Pinned finite German word forms; this is not a morphological/compound parser.
/// Initialization and checking yield to the event loop in bounded batches,
/// including when compiled for JavaScript (where Dart isolates are unavailable).
class GermanSpellingProvider extends OfficeProofingProvider {
  GermanSpellingProvider({
    OfficeProofingVocabulary? vocabulary,
    this.maximumSuggestions = 5,
    this.maximumCandidateChecks = 6000,
  }) : vocabulary = vocabulary ?? OfficeProofingVocabulary() {
    if (maximumSuggestions < 0 || maximumSuggestions > 20) {
      throw RangeError.range(maximumSuggestions, 0, 20, 'maximumSuggestions');
    }
    if (maximumCandidateChecks < 1 || maximumCandidateChecks > 20000) {
      throw RangeError.range(
        maximumCandidateChecks,
        1,
        20000,
        'maximumCandidateChecks',
      );
    }
  }

  final OfficeProofingVocabulary vocabulary;
  final int maximumSuggestions;
  final int maximumCandidateChecks;
  bool _disposed = false;
  static Future<_GermanLexicon>? _sharedLexicon;
  static final RegExp _tokens = RegExp(
    r"[\p{L}\p{M}\u00ad]+(?:[-\u2010\u2011'’][\p{L}\p{M}\u00ad]+)*",
    unicode: true,
  );
  static final RegExp _webTokens = RegExp(
    r'(?:https?://|www\.)\S+|[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}',
  );
  static const String _alphabet = 'abcdefghijklmnopqrstuvwxyzäöüß';

  @override
  String get id => 'german-spelling';
  @override
  int get configurationRevision => vocabulary.revision;
  @override
  bool supportsLanguage(String language) => const <String>{
    'de-DE',
    'de-AT',
    'de-CH',
  }.contains(normalizeProofingLanguage(language));

  /// Loads the actual shipped dictionary without checking or changing text.
  Future<void> warmUp() async {
    await (_sharedLexicon ??= _GermanLexicon.load());
  }

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    OfficeProofingResult result(
      OfficeProofingStatus status, {
      List<OfficeProofingFinding> findings = const <OfficeProofingFinding>[],
      String? message,
    }) => OfficeProofingResult(
      request: request,
      providerId: id,
      status: status,
      findings: findings,
      message: message,
    );
    if (_disposed) {
      return result(
        OfficeProofingStatus.unavailable,
        message: 'German spelling provider is disposed.',
      );
    }
    if (!supportsLanguage(request.language)) {
      return result(
        OfficeProofingStatus.unsupported,
        message: 'German spelling supports de-DE, de-AT and de-CH.',
      );
    }
    final int vocabularyRevision = vocabulary.revision;
    final Set<String> personal = <String>{
      ...vocabulary.wordsFor(request.language),
      ...vocabulary.ignoredWordsFor(request.language),
    };
    final _GermanLexicon lexicon = await (_sharedLexicon ??=
        _GermanLexicon.load());
    final bool swiss = request.language == 'de-CH';
    final List<OfficeProofingFinding> findings = <OfficeProofingFinding>[];
    final List<RegExpMatch> webRanges = _webTokens
        .allMatches(request.text)
        .toList();
    final Map<String, List<String>> suggestions = <String, List<String>>{};
    int examined = 0;
    for (final RegExpMatch token in _tokens.allMatches(request.text)) {
      if (examined++ % 16 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (_disposed) {
          return result(
            OfficeProofingStatus.unavailable,
            message: 'German spelling provider is disposed.',
          );
        }
      }
      if (webRanges.any(
        (RegExpMatch range) =>
            token.start >= range.start && token.end <= range.end,
      )) {
        continue;
      }
      final String original = token.group(0)!;
      final String word = normalizeGermanWord(original);
      if (personal.contains(word) ||
          lexicon.contains(
            word,
            swiss: swiss,
            sentenceInitial: _isSentenceInitial(request.text, token.start),
          )) {
        continue;
      }
      final List<String> replacements = suggestions.putIfAbsent(
        word,
        () => _suggest(word, lexicon, swiss),
      );
      findings.add(
        OfficeProofingFinding.forRequest(
          request,
          providerId: id,
          start: token.start,
          end: token.end,
          ruleId: 'de.spelling.unknown',
          message: swiss && word.contains('ß')
              ? 'Die Schweizer Schreibweise verwendet ss statt ß.'
              : 'Dieses Wort ist nicht im deutschen Wörterverzeichnis enthalten.',
          category: OfficeProofingCategory.spelling,
          replacements: replacements,
        ),
      );
    }
    if (vocabulary.revision != vocabularyRevision) {
      return result(
        OfficeProofingStatus.failed,
        message: 'Personal vocabulary changed during this check; check again.',
      );
    }
    return result(OfficeProofingStatus.success, findings: findings);
  }

  static final RegExp _letterOrNumber = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _isSentenceInitial(String text, int offset) {
    // Inspect only the local prefix, never copy/rescan the whole paragraph for
    // every token. Leading emoji, quotes and punctuation are harmless here.
    for (int i = offset - 1; i >= 0; i--) {
      final String char = text[i];
      if (char == '.' || char == '!' || char == '?' || char == '\n') {
        return true;
      }
      if (_letterOrNumber.hasMatch(char)) return false;
    }
    return true;
  }

  List<String> _suggest(String word, _GermanLexicon lexicon, bool swiss) {
    if (maximumSuggestions == 0 || word.length > 64) return const <String>[];
    final Set<String> found = <String>{};
    int examined = 0;
    void candidate(String value) {
      if (examined++ >= maximumCandidateChecks ||
          found.length >= maximumSuggestions ||
          value == word) {
        return;
      }
      if (lexicon.exact(value, swiss: swiss)) found.add(value);
    }

    final String lower = word.toLowerCase();
    final bool upper = word == _upper(word) && word != lower;
    final bool title = word[0] == word[0].toUpperCase();
    void candidateCase(String value) {
      if (title || upper) candidate(_title(value));
      candidate(value);
    }

    candidate(lower);
    candidate(_title(lower));
    candidate(word.replaceAll('ß', 'ss').replaceAll('ẞ', 'SS'));
    if (!swiss) {
      for (final RegExpMatch match in RegExp('ss').allMatches(lower)) {
        candidateCase(lower.replaceRange(match.start, match.end, 'ß'));
      }
    }
    for (final MapEntry<String, String> pair in const <String, String>{
      'ae': 'ä',
      'oe': 'ö',
      'ue': 'ü',
    }.entries) {
      if (lower.contains(pair.key)) {
        candidateCase(lower.replaceAll(pair.key, pair.value));
      }
    }
    // Adjacent transposition, deletion, replacement and insertion at distance 1.
    // No full dictionary scan or unbounded distance-2 expansion on the UI loop.
    for (int i = 0; i + 1 < lower.length; i++) {
      candidateCase(
        '${lower.substring(0, i)}${lower[i + 1]}${lower[i]}${lower.substring(i + 2)}',
      );
    }
    for (int i = 0; i < lower.length; i++) {
      candidateCase(lower.replaceRange(i, i + 1, ''));
    }
    for (
      int i = 0;
      i <= lower.length &&
          examined < maximumCandidateChecks &&
          found.length < maximumSuggestions;
      i++
    ) {
      for (
        int c = 0;
        c < _alphabet.length &&
            examined < maximumCandidateChecks &&
            found.length < maximumSuggestions;
        c++
      ) {
        final String letter = _alphabet[c];
        if (i < lower.length) {
          candidateCase(lower.replaceRange(i, i + 1, letter));
        }
        candidateCase(lower.replaceRange(i, i, letter));
      }
    }
    return List<String>.unmodifiable(
      found.map((String value) => upper ? _upper(value) : value).toSet(),
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}

String _upper(String word) => word.replaceAll('ß', 'ss').toUpperCase();

String _title(String word) =>
    word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}';

class _GermanLexicon {
  _GermanLexicon(this.standard, this.swissAdditions)
    : sharpSCapitals = standard
          .where((String word) => word.contains('ß'))
          .map(_upper)
          .toSet();
  final Set<String> standard;
  final Set<String> swissAdditions;
  final Set<String> sharpSCapitals;

  static Future<_GermanLexicon> load() async {
    Future<Set<String>> decode(List<String> chunks) async {
      final Set<String> words = <String>{};
      for (final String chunk in chunks) {
        await Future<void>.delayed(Duration.zero);
        final String decoded = utf8.decode(
          RawDeflate.inflate(base64.decode(chunk), maxOutputBytes: 1048576),
        );
        words.addAll(
          decoded.split('\n').where((String word) => word.isNotEmpty),
        );
      }
      return words;
    }

    return _GermanLexicon(
      await decode(germanLexiconChunks),
      await decode(germanSwissLexiconChunks),
    );
  }

  bool exact(String word, {required bool swiss}) {
    if (swiss && (word.contains('ß') || word.contains('ẞ'))) return false;
    return standard.contains(word) || swiss && swissAdditions.contains(word);
  }

  bool contains(
    String word, {
    required bool swiss,
    required bool sentenceInitial,
  }) {
    if (exact(word, swiss: swiss)) return true;
    final String lower = word.toLowerCase();
    if (word == _upper(word) && word != lower) {
      if ((!swiss && sharpSCapitals.contains(word)) ||
          exact(lower, swiss: swiss) ||
          exact(_title(lower), swiss: swiss)) {
        return true;
      }
    }
    if (sentenceInitial &&
        word == _title(lower) &&
        exact(lower, swiss: swiss)) {
      return true;
    }
    // Explicitly joined words can use known constituents. We do not guess
    // arbitrary German closed compounds or infer productive inflections.
    if (word.contains('-')) {
      final List<String> parts = word.split('-');
      for (int i = 0; i < parts.length; i++) {
        if (parts[i].isEmpty ||
            !contains(
              parts[i],
              swiss: swiss,
              sentenceInitial: sentenceInitial && i == 0,
            )) {
          return false;
        }
      }
      return true;
    }
    return false;
  }
}
