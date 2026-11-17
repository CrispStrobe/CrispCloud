import 'dart:async';
import 'dart:convert';

import 'package:characters/characters.dart';

import '../opc/zip/deflate_codec.dart';
import 'data/german_lexicon_data.dart';
import 'office_proofing.dart';
import 'proofing_text_ranges.dart';

Set<int> _sourceGraphemeBoundaries(String text) {
  final Set<int> boundaries = <int>{0};
  int end = 0;
  for (final String cluster in text.characters) {
    end += cluster.length;
    boundaries.add(end);
  }
  return boundaries;
}

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
        final String language = normalizeProofingLanguage(entry.key);
        if (language.isEmpty) {
          throw const FormatException('Invalid vocabulary language');
        }
        if (entry.value is! List<Object?>) {
          throw const FormatException('Invalid vocabulary list');
        }
        final Set<String> words = <String>{};
        for (final Object? word in entry.value! as List<Object?>) {
          if (word is! String) {
            throw const FormatException('Invalid vocabulary word');
          }
          final String normalized = normalizeGermanWord(word).trim();
          if (normalized.isEmpty) {
            throw const FormatException('Invalid vocabulary word');
          }
          words.add(normalized);
        }
        // Older hosts may have saved several aliases for the same locale.
        // Restore their union instead of losing the earlier alias's words.
        target.putIfAbsent(language, () => <String>{}).addAll(words);
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
    final String normalized = normalizeGermanWord(word).trim();
    if (normalized.isEmpty) throw ArgumentError.value(word, 'word');
    final String key = normalizeProofingLanguage(language);
    if (key.isEmpty) throw ArgumentError.value(language, 'language');
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
/// Suggestions use a shared candidate budget for direct edits, personal terms
/// and an indexed distance-two fallback; no typo scans the complete dictionary.
/// Token fragments that would cut a grapheme are skipped. In particular, a
/// letter joined to an adjacent control must not offer a partial replacement.
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
    // A mark or discretionary hyphen by itself is not a word. Requiring a
    // letter at the start also keeps combining marks attached to punctuation
    // out of a finding that would split that punctuation's grapheme.
    r"\p{L}[\p{L}\p{M}\u00ad]*(?:[-\u2010\u2011'’]\p{L}[\p{L}\p{M}\u00ad]*)*",
    unicode: true,
  );
  static final RegExp _identifierBefore = RegExp(
    r'[\p{N}\p{Pc}]$',
    unicode: true,
  );
  static final RegExp _identifierAfter = RegExp(
    r'^[\p{N}\p{Pc}]',
    unicode: true,
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
    final Set<String> personal = vocabulary.wordsFor(request.language);
    final Set<String> ignored = vocabulary.ignoredWordsFor(request.language);
    final _GermanLexicon lexicon = await (_sharedLexicon ??=
        _GermanLexicon.load());
    final bool swiss = request.language == 'de-CH';
    final List<OfficeProofingFinding> findings = <OfficeProofingFinding>[];
    final Set<int> boundaries = _sourceGraphemeBoundaries(request.text);
    final OfficeProofingTextRanges protectedRanges = OfficeProofingTextRanges(
      request.text,
    );
    final Map<(String, bool), List<String>> suggestions =
        <(String, bool), List<String>>{};
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
      // Do not widen a lexical replacement over an adjacent mark or joiner.
      // Unsupported token fragments must not invalidate ordinary findings
      // elsewhere in the same paragraph.
      if (!boundaries.contains(token.start) ||
          !boundaries.contains(token.end)) {
        continue;
      }
      if (protectedRanges.overlaps(token.start, token.end) ||
          _isIdentifierFragment(request.text, token.start, token.end)) {
        continue;
      }
      final String original = token.group(0)!;
      final String word = normalizeGermanWord(original);
      final bool sentenceInitial = _isSentenceInitial(
        request.text,
        token.start,
      );
      if (ignored.contains(word) ||
          lexicon.contains(
            word,
            swiss: swiss,
            sentenceInitial: sentenceInitial,
            personal: personal,
          )) {
        continue;
      }
      final (String, bool) suggestionKey = (word, sentenceInitial);
      List<String>? replacements = suggestions[suggestionKey];
      if (replacements == null) {
        replacements = _suggest(
          word,
          lexicon,
          swiss,
          personal: personal,
          sentenceInitial: sentenceInitial,
        );
        suggestions[suggestionKey] = replacements;
        // A new indexed search can consume the full candidate budget. Do not
        // accumulate sixteen such searches in one UI event-loop turn. Known
        // words and repeated misspellings keep the ordinary cheap batch path.
        await Future<void>.delayed(Duration.zero);
        if (_disposed) {
          return result(
            OfficeProofingStatus.unavailable,
            message: 'German spelling provider is disposed.',
          );
        }
        if (vocabulary.revision != vocabularyRevision) {
          return result(
            OfficeProofingStatus.failed,
            message:
                'Personal vocabulary changed during this check; check again.',
          );
        }
      }
      findings.add(
        OfficeProofingFinding.forRequest(
          request,
          providerId: id,
          start: token.start,
          end: token.end,
          ruleId: 'de.spelling.unknown',
          message: swiss && (word.contains('ß') || word.contains('ẞ'))
              ? 'Die Schweizer Schreibweise verwendet ss statt ß.'
              : 'Dieses Wort ist nicht im deutschen Wörterverzeichnis enthalten.',
          category: OfficeProofingCategory.spelling,
          replacements: _withSourceHyphens(original, replacements),
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

  static bool _isIdentifierFragment(String text, int start, int end) {
    // A lexical replacement must not rewrite just the letters of foo42 or
    // snake_case. Two UTF-16 units cover an adjacent supplementary digit;
    // anchoring keeps unrelated numbers across whitespace out of this check.
    return start > 0 &&
            _identifierBefore.hasMatch(
              text.substring(start >= 2 ? start - 2 : 0, start),
            ) ||
        end < text.length &&
            _identifierAfter.hasMatch(
              text.substring(
                end,
                end + 2 <= text.length ? end + 2 : text.length,
              ),
            );
  }

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

  List<String> _suggest(
    String word,
    _GermanLexicon lexicon,
    bool swiss, {
    required Set<String> personal,
    required bool sentenceInitial,
  }) {
    if (maximumSuggestions == 0 || word.isEmpty || word.length > 64) {
      return const <String>[];
    }
    // Repair one unknown component of an explicitly joined compound. Other
    // components keep their source case, and every component must be known.
    // Only one ordinary suggestion search is performed, so the existing
    // per-token candidate budget also bounds this path.
    if (word.contains('-')) {
      final List<String> parts = word.split('-');
      int unknown = -1;
      if (parts.length <= 8 && parts.every((String part) => part.isNotEmpty)) {
        for (int i = 0; i < parts.length; i++) {
          if (lexicon.contains(
            parts[i],
            swiss: swiss,
            sentenceInitial: sentenceInitial && i == 0,
            personal: personal,
          )) {
            continue;
          }
          if (unknown >= 0) {
            unknown = -2;
            break;
          }
          unknown = i;
        }
        if (unknown >= 0) {
          final List<String> compounds = <String>[];
          for (final String replacement in _suggest(
            parts[unknown],
            lexicon,
            swiss,
            personal: personal,
            sentenceInitial: sentenceInitial && unknown == 0,
          )) {
            final List<String> corrected = List<String>.of(parts);
            corrected[unknown] = replacement;
            final String candidate = corrected.join('-');
            if (lexicon.contains(
              candidate,
              swiss: swiss,
              sentenceInitial: sentenceInitial,
              personal: personal,
            )) {
              compounds.add(candidate);
            }
          }
          return List<String>.unmodifiable(compounds);
        }
      }
    }
    final Set<String> found = <String>{};
    final Set<String> checked = <String>{};
    int examined = 0;
    void candidate(String value) {
      if (examined >= maximumCandidateChecks ||
          found.length >= maximumSuggestions ||
          value == word ||
          !checked.add(value)) {
        return;
      }
      examined++;
      if (personal.contains(value) || lexicon.exact(value, swiss: swiss)) {
        found.add(value);
      }
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
    // Uppercase source may use capital sharp-s. The finite lexicon normally
    // stores title/lowercase forms, so check those before restoring capitals.
    if (lower.contains('ß')) candidateCase(lower.replaceAll('ß', 'ss'));
    if (!swiss) {
      for (final RegExpMatch match in RegExp('ss').allMatches(lower)) {
        candidateCase(lower.replaceRange(match.start, match.end, 'ß'));
      }
    }
    // Keyboard transliterations can need several orthographic changes at
    // once (uebermaessig -> übermäßig). Explore at most 32 distinct forms,
    // including individual occurrences so genuine ue in Abenteuer survives.
    // Every offer still needs an exact shipped dictionary match, and these
    // lookups share the ordinary per-token budget; no distance-2 scan occurs.
    final Map<String, String> orthography = <String, String>{
      'ae': 'ä',
      'oe': 'ö',
      'ue': 'ü',
      'ß': 'ss',
      if (!swiss) 'ss': 'ß',
    };
    final List<String> variants = <String>[lower];
    final Set<String> visited = <String>{lower};
    bool canSearch() =>
        examined < maximumCandidateChecks && found.length < maximumSuggestions;
    void orthographicCandidate(String value) {
      if (variants.length >= 32 || !canSearch() || !visited.add(value)) return;
      variants.add(value);
      candidateCase(value);
    }

    for (int i = 0; i < variants.length && canSearch(); i++) {
      for (final MapEntry<String, String> pair in orthography.entries) {
        final String value = variants[i];
        if (!value.contains(pair.key)) continue;
        orthographicCandidate(value.replaceAll(pair.key, pair.value));
        for (final Match match in pair.key.allMatches(value)) {
          orthographicCandidate(
            value.replaceRange(match.start, match.end, pair.value),
          );
          if (variants.length >= 32 || !canSearch()) break;
        }
        if (variants.length >= 32 || !canSearch()) break;
      }
      if (variants.length >= 32) break;
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
    // User-declared names can contain mixed capitals that cannot be rebuilt by
    // lower/title-case edits (for example QudsCloud). Only declared words are
    // candidates; ignored misspellings never become correction vocabulary.
    // Reserve most of the budget for dictionary candidates even with a large
    // personal vocabulary. Suggestions retain the exact declared spelling.
    final List<(String, int)> personalMatches = <(String, int)>[];
    int personalChecks = 0;
    for (final String value in personal) {
      if (!canSearch() || personalChecks >= 256) break;
      if (value == word || !checked.add(value)) continue;
      examined++;
      personalChecks++;
      if ((value.length - lower.length).abs() > 2 ||
          _tokens.stringMatch(value) != value) {
        continue;
      }
      final int distance = _boundedEditDistance(
        lower,
        value.toLowerCase(),
        limit: lower.length >= 5 ? 2 : 1,
      );
      if (distance <= (lower.length >= 5 ? 2 : 1)) {
        personalMatches.add((value, distance));
      }
    }
    personalMatches.sort((a, b) {
      final int byDistance = a.$2.compareTo(b.$2);
      return byDistance != 0 ? byDistance : a.$1.compareTo(b.$1);
    });
    for (final (String value, int _) in personalMatches) {
      if (found.length >= maximumSuggestions) break;
      found.add(value);
    }

    // Two independent mistakes are common in longer words. Prefix, middle and
    // suffix buckets allow first-letter mistakes and transposition-plus-typo
    // cases without generating the quadratic neighborhood of every edit.
    // Every visited entry consumes the same maximumCandidateChecks budget.
    // Adjacent transpositions count as one edit; terms beyond two edits are
    // never offered by this fallback. This is a bounded shortlist, not an
    // exhaustive edit-distance search or a word-acceptance heuristic.
    if (lower.length >= 5 && canSearch()) {
      final List<(String, int)> matches = <(String, int)>[];
      for (final String value in lexicon.suggestionCandidates(lower)) {
        if (examined >= maximumCandidateChecks) break;
        if (value == word || !checked.add(value)) continue;
        examined++;
        final int distance = _boundedEditDistance(lower, value.toLowerCase());
        if (distance <= 2 && lexicon.exact(value, swiss: swiss)) {
          matches.add((value, distance));
        }
      }
      matches.sort((a, b) {
        final int byDistance = a.$2.compareTo(b.$2);
        if (byDistance != 0) return byDistance;
        final int byLength = (a.$1.length - word.length).abs().compareTo(
          (b.$1.length - word.length).abs(),
        );
        return byLength != 0 ? byLength : a.$1.compareTo(b.$1);
      });
      for (final (String value, int _) in matches) {
        if (found.length >= maximumSuggestions) break;
        found.add(value);
      }
    }
    return List<String>.unmodifiable(
      found.map((String value) {
        if (personal.contains(value)) return value;
        if (upper) return _upper(value);
        return sentenceInitial && title ? _title(value) : value;
      }).toSet(),
    );
  }

  static List<String> _withSourceHyphens(
    String source,
    List<String> replacements,
  ) {
    final List<String> separators = RegExp(
      r'[-\u2010\u2011]',
    ).allMatches(source).map((RegExpMatch match) => match.group(0)!).toList();
    if (separators.every((String separator) => separator == '-')) {
      return replacements;
    }
    return List<String>.unmodifiable(
      replacements.map((String replacement) {
        if ('-'.allMatches(replacement).length != separators.length) {
          return replacement;
        }
        int index = 0;
        return replacement.replaceAllMapped(
          RegExp('-'),
          (Match _) => separators[index++],
        );
      }),
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

/// Banded optimal-string-alignment distance. Values above [limit] are reported
/// as limit + 1; at most five cells per source character need evaluation for
/// the ordinary two-edit search. This implementation has no external corpus.
int _boundedEditDistance(String source, String target, {int limit = 2}) {
  if ((source.length - target.length).abs() > limit) return limit + 1;
  if (source == target) return 0;
  final int beyond = limit + 1;
  List<int> previousPrevious = List<int>.filled(target.length + 1, beyond);
  List<int> previous = <int>[
    for (int j = 0; j <= target.length; j++) j <= limit ? j : beyond,
  ];
  List<int> current = List<int>.filled(target.length + 1, beyond);
  for (int i = 1; i <= source.length; i++) {
    current.fillRange(0, current.length, beyond);
    if (i <= limit) current[0] = i;
    final int start = i > limit ? i - limit : 1;
    final int end = i + limit < target.length ? i + limit : target.length;
    int best = beyond;
    for (int j = start; j <= end; j++) {
      final int substitution =
          previous[j - 1] +
          (source.codeUnitAt(i - 1) == target.codeUnitAt(j - 1) ? 0 : 1);
      final int insertion = current[j - 1] + 1;
      final int deletion = previous[j] + 1;
      int cost = substitution < insertion ? substitution : insertion;
      if (deletion < cost) cost = deletion;
      if (i > 1 &&
          j > 1 &&
          source.codeUnitAt(i - 1) == target.codeUnitAt(j - 2) &&
          source.codeUnitAt(i - 2) == target.codeUnitAt(j - 1)) {
        final int transposition = previousPrevious[j - 2] + 1;
        if (transposition < cost) cost = transposition;
      }
      current[j] = cost;
      if (cost < best) best = cost;
    }
    if (best > limit) return beyond;
    final List<int> reusable = previousPrevious;
    previousPrevious = previous;
    previous = current;
    current = reusable;
  }
  return previous[target.length];
}

class _GermanLexicon {
  _GermanLexicon(this.standard, this.swissAdditions, this._suggestionIndex)
    : sharpSCapitals = standard
          .where((String word) => word.contains('ß'))
          .map(_upper)
          .toSet();
  final Set<String> standard;
  final Set<String> swissAdditions;
  final Set<String> sharpSCapitals;
  final Map<(int, int, String), List<String>> _suggestionIndex;

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

    final Set<String> standard = await decode(germanLexiconChunks);
    final Set<String> swiss = await decode(germanSwissLexiconChunks);
    final Map<(int, int, String), List<String>> index =
        <(int, int, String), List<String>>{};
    int indexed = 0;
    for (final String word in standard.followedBy(swiss)) {
      if (indexed++ % 4096 == 0) await Future<void>.delayed(Duration.zero);
      final String lower = word.toLowerCase();
      if (lower.length < 3 || lower.length > 66) continue;
      final int width = lower.length >= 9 ? 3 : 2;
      final int middle = (lower.length - width) ~/ 2;
      final List<String> anchors = <String>[
        lower.substring(0, width),
        lower.substring(middle, middle + width),
        lower.substring(lower.length - width),
      ];
      for (int kind = 0; kind < anchors.length; kind++) {
        index
            .putIfAbsent((kind, lower.length, anchors[kind]), () => <String>[])
            .add(word);
      }
    }
    return _GermanLexicon(standard, swiss, index);
  }

  Iterable<String> suggestionCandidates(String lower) sync* {
    final List<List<String>> groups = <List<String>>[];
    final Set<(int, int, String)> keys = <(int, int, String)>{};
    for (final int delta in const <int>[0, -1, 1, -2, 2]) {
      final int length = lower.length + delta;
      final int width = length >= 9 ? 3 : 2;
      final int middle = (lower.length - width) ~/ 2;
      final List<(int, String)> anchors = <(int, String)>[
        (0, lower.substring(0, width)),
        (2, lower.substring(lower.length - width)),
        for (final int shift in const <int>[0, -1, 1, -2, 2])
          if (middle + shift >= 0 && middle + shift + width <= lower.length)
            (1, lower.substring(middle + shift, middle + shift + width)),
      ];
      for (final (int kind, String anchor) in anchors) {
        final (int, int, String) key = (kind, length, anchor);
        if (!keys.add(key)) continue;
        final List<String>? group = _suggestionIndex[key];
        if (group != null && group.isNotEmpty) groups.add(group);
      }
    }
    // Interleave buckets so a dense common prefix cannot starve suffix/middle
    // candidates before the caller's budget expires.
    bool remaining = true;
    for (int row = 0; remaining; row++) {
      remaining = false;
      for (final List<String> group in groups) {
        if (row >= group.length) continue;
        remaining = true;
        yield group[row];
      }
    }
  }

  bool exact(String word, {required bool swiss}) {
    if (swiss && (word.contains('ß') || word.contains('ẞ'))) return false;
    return standard.contains(word) || swiss && swissAdditions.contains(word);
  }

  bool contains(
    String word, {
    required bool swiss,
    required bool sentenceInitial,
    Set<String> personal = const <String>{},
  }) {
    if (personal.contains(word) || exact(word, swiss: swiss)) return true;
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
              personal: personal,
            )) {
          return false;
        }
      }
      return true;
    }
    return false;
  }
}
