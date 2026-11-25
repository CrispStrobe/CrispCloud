/// Automatic per-paragraph language identification for proofing routing.
///
/// A [LanguageIdentifier] wraps a statistical classifier (the bundled CLD3
/// model in `quds_language_id`); everything else here is policy and can be
/// tested with a fake. Detection only steers which proofing providers check
/// a range. It never rewrites the document: writing the detected languages
/// is a separate, explicit and undoable editor command.
///
/// The policy, in order:
///
/// 1. **Script first.** The paragraph is split into Unicode script runs
///    ([scriptSegments]); spaces, digits and punctuation join the preceding
///    run. Each run gets its own language.
/// 2. **Arabic script** is `ar` unless the classifier confidently says one of
///    [LanguageDetectionPolicy.arabicScriptAlternatives] (fa, ur, ps, ku, sd,
///    ug). **Hebrew script** is `he` unless it confidently says `yi`. These two
///    scripts get a language even when they are too short to classify.
/// 3. **Other scripts** (Latin, Cyrillic, Greek, ...) get the classifier's
///    top language only when the run has at least
///    [LanguageDetectionPolicy.minLetters] letters and the top probability is
///    at least [LanguageDetectionPolicy.minConfidence], and the language is
///    written in that script. Otherwise the run has no detected language.
/// 4. **Precedence** (see [resolveDetectedLanguage]): an explicit language on
///    the text wins. A *default* language (none set, or one equal to the
///    document default) yields to a detected language with another primary
///    subtag.
library;

import 'dart:async';
import 'dart:collection';

import 'office_proofing.dart';

/// One candidate language and its probability (0..1).
final class LanguageGuess {
  const LanguageGuess(this.language, this.confidence);

  /// BCP-47 tag without region (`de`, `en`, `he`, `zh-Latn`, ...).
  final String language;
  final double confidence;

  @override
  String toString() => '$language ${confidence.toStringAsFixed(3)}';

  @override
  bool operator ==(Object other) =>
      other is LanguageGuess &&
      other.language == language &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(language, confidence);
}

/// A text language classifier (bundled CLD3 in production, a fake in tests).
abstract interface class LanguageIdentifier {
  /// Whether the classifier is loaded and can answer.
  bool get isAvailable;

  /// Candidates for each of [texts], best first, in input order. A text
  /// without letters, or any text while unavailable, has an empty list.
  Future<List<List<LanguageGuess>>> identify(List<String> texts);
}

/// Placeholder when no classifier is present: detection then relies on the
/// script alone (Arabic and Hebrew) and never guesses Latin languages.
class UnavailableLanguageIdentifier implements LanguageIdentifier {
  const UnavailableLanguageIdentifier();

  @override
  bool get isAvailable => false;

  @override
  Future<List<List<LanguageGuess>>> identify(List<String> texts) async => [
    for (final _ in texts) const <LanguageGuess>[],
  ];
}

/// Writing systems the policy distinguishes.
enum TextScript {
  latin,
  arabic,
  hebrew,
  cyrillic,
  greek,
  other;

  /// Word stores the language of these scripts in `w:lang/@w:bidi`.
  bool get isComplex => this == arabic || this == hebrew;
}

/// A maximal run of one script in a paragraph, in UTF-16 offsets. Neutral
/// characters (spaces, digits, punctuation, marks) belong to the preceding
/// run, or to the first run when they lead the text.
final class ScriptSegment {
  const ScriptSegment(this.start, this.end, this.script, this.letters);

  final int start;
  final int end;
  final TextScript script;

  /// Letters of [script] in the run (neutral characters excluded).
  final int letters;

  @override
  String toString() => '$script[$start,$end) $letters letters';
}

final _letter = RegExp(r'\p{L}', unicode: true);
final _latin = RegExp(r'\p{Script=Latin}', unicode: true);
final _arabic = RegExp(r'\p{Script=Arabic}', unicode: true);
final _hebrew = RegExp(r'\p{Script=Hebrew}', unicode: true);
final _cyrillic = RegExp(r'\p{Script=Cyrillic}', unicode: true);
final _greek = RegExp(r'\p{Script=Greek}', unicode: true);

TextScript? _scriptOf(int rune) {
  if (rune < 0x80) {
    final lower = rune | 0x20;
    return lower >= 0x61 && lower <= 0x7a ? TextScript.latin : null;
  }
  final character = String.fromCharCode(rune);
  if (!_letter.hasMatch(character)) return null;
  if (_latin.hasMatch(character)) return TextScript.latin;
  if (_arabic.hasMatch(character)) return TextScript.arabic;
  if (_hebrew.hasMatch(character)) return TextScript.hebrew;
  if (_cyrillic.hasMatch(character)) return TextScript.cyrillic;
  if (_greek.hasMatch(character)) return TextScript.greek;
  return TextScript.other;
}

/// Whether [text] contains a Unicode letter and can produce a script run.
bool hasScriptLetters(String text) => _letter.hasMatch(text);

/// Splits [text] into script runs that together cover all of it. Returns an
/// empty list for text without letters.
List<ScriptSegment> scriptSegments(String text) {
  final runs = <ScriptSegment>[];
  TextScript? currentScript;
  var start = 0;
  var offset = 0;
  var letters = 0;
  for (final rune in text.runes) {
    final script = _scriptOf(rune);
    if (script != null) {
      if (script != currentScript) {
        if (currentScript != null) {
          runs.add(ScriptSegment(start, offset, currentScript, letters));
          start = offset;
        }
        currentScript = script;
        letters = 0;
      }
      letters++;
    }
    offset += rune > 0xffff ? 2 : 1;
  }
  if (currentScript != null) {
    runs.add(ScriptSegment(start, offset, currentScript, letters));
  }
  return runs;
}

/// Which script a detected language is written in, for the CLD3 labels the
/// policy can be asked about. Unknown tags are treated as Latin unless they
/// carry an explicit script subtag.
TextScript languageScript(String language) {
  final parts = language.trim().replaceAll('_', '-').toLowerCase().split('-');
  if (parts.length > 1 && _scriptSubtag.hasMatch(parts[1])) {
    return switch (parts[1]) {
      'latn' => TextScript.latin,
      'arab' => TextScript.arabic,
      'hebr' => TextScript.hebrew,
      'cyrl' => TextScript.cyrillic,
      'grek' => TextScript.greek,
      _ => TextScript.other,
    };
  }
  return switch (parts.first) {
    'ar' || 'fa' || 'ur' || 'ps' || 'ku' || 'sd' || 'ug' => TextScript.arabic,
    'he' || 'yi' => TextScript.hebrew,
    'ru' ||
    'uk' ||
    'be' ||
    'bg' ||
    'mk' ||
    'sr' ||
    'kk' ||
    'ky' ||
    'mn' ||
    'tg' => TextScript.cyrillic,
    'el' => TextScript.greek,
    'am' ||
    'bn' ||
    'gu' ||
    'hi' ||
    'hy' ||
    'ja' ||
    'ka' ||
    'km' ||
    'kn' ||
    'ko' ||
    'lo' ||
    'ml' ||
    'mr' ||
    'my' ||
    'ne' ||
    'pa' ||
    'si' ||
    'ta' ||
    'te' ||
    'th' ||
    'zh' => TextScript.other,
    _ => TextScript.latin,
  };
}

final _scriptSubtag = RegExp(r'^[a-z]{4}$');

/// The language decided for one script run.
final class DetectedSegment {
  const DetectedSegment({
    required this.start,
    required this.end,
    required this.script,
    required this.language,
    required this.confidence,
    required this.byScript,
    this.guesses = const [],
  });

  final int start;
  final int end;
  final TextScript script;

  /// Detected BCP-47 tag (no region), or null when nothing is certain.
  final String? language;

  /// The classifier's probability for [language]; 1 for a script decision
  /// without a classifier answer, 0 when [language] is null.
  final double confidence;

  /// The language follows from the script (Arabic, Hebrew) rather than from
  /// a confident classifier answer.
  final bool byScript;

  /// The classifier's candidates for this run, best first (empty when it
  /// was not asked).
  final List<LanguageGuess> guesses;

  /// The classifier's probability for [language] (primary subtag match),
  /// or 0 when it is not among [guesses].
  double probabilityOf(String language) {
    final primary = primaryLanguageSubtag(language);
    for (final guess in guesses) {
      if (primaryLanguageSubtag(guess.language) == primary) {
        return guess.confidence;
      }
    }
    return 0;
  }

  @override
  String toString() =>
      '$script[$start,$end) ${language ?? '-'}'
      '${byScript ? ' (script)' : ' ${confidence.toStringAsFixed(3)}'}';
}

/// Thresholds of the detection policy. The defaults are calibrated on UD
/// r2.14 test sentences (see docs/PROOFING.md, "Automatic language
/// detection").
final class LanguageDetectionPolicy {
  const LanguageDetectionPolicy({
    this.minLetters = 20,
    this.minConfidence = 0.95,
    this.complexScriptMinLetters = 20,
    this.complexScriptMinConfidence = 0.95,
    this.keepDefaultConfidence = 0.01,
    this.arabicScriptAlternatives = const {'fa', 'ur', 'ps', 'ku', 'sd', 'ug'},
    this.hebrewScriptAlternatives = const {'yi'},
  });

  /// Letters a Latin/Cyrillic/Greek/other run needs before the classifier
  /// is asked at all.
  final int minLetters;

  /// Top probability the classifier needs for those runs.
  final double minConfidence;

  /// Letters and probability needed before an Arabic- or Hebrew-script run
  /// is given a language other than `ar` / `he`.
  final int complexScriptMinLetters;
  final double complexScriptMinConfidence;

  /// A default language is kept when the classifier still gives it at
  /// least this probability among its candidates (see
  /// [resolveDetectedLanguage]).
  final double keepDefaultConfidence;

  final Set<String> arabicScriptAlternatives;
  final Set<String> hebrewScriptAlternatives;

  /// Whether the classifier is consulted for [segment].
  bool needsClassifier(ScriptSegment segment) => segment.script.isComplex
      ? segment.letters >= complexScriptMinLetters
      : segment.letters >= minLetters;

  /// The decision for [segment] given the classifier's [guesses] (empty when
  /// it was not asked or had no answer).
  DetectedSegment decide(ScriptSegment segment, List<LanguageGuess> guesses) {
    final first = guesses.isEmpty ? null : guesses.first;
    final top = first != null && _validConfidence(first.confidence)
        ? first
        : null;
    DetectedSegment result(String? language, double confidence, bool script) =>
        DetectedSegment(
          start: segment.start,
          end: segment.end,
          script: segment.script,
          language: language,
          confidence: confidence,
          byScript: script,
          guesses: guesses,
        );
    switch (segment.script) {
      case TextScript.arabic || TextScript.hebrew:
        final fallback = segment.script == TextScript.arabic ? 'ar' : 'he';
        final alternatives = segment.script == TextScript.arabic
            ? arabicScriptAlternatives
            : hebrewScriptAlternatives;
        if (top != null &&
            segment.letters >= complexScriptMinLetters &&
            top.confidence >= complexScriptMinConfidence &&
            alternatives.contains(top.language)) {
          return result(top.language, top.confidence, false);
        }
        final own = guesses
            .where(
              (g) => g.language == fallback && _validConfidence(g.confidence),
            )
            .firstOrNull;
        return result(fallback, own?.confidence ?? 1, true);
      case TextScript.latin ||
          TextScript.cyrillic ||
          TextScript.greek ||
          TextScript.other:
        if (top != null &&
            segment.letters >= minLetters &&
            top.confidence >= minConfidence &&
            languageScript(top.language) == segment.script) {
          return result(top.language, top.confidence, false);
        }
        return result(null, 0, false);
    }
  }
}

bool _validConfidence(double confidence) =>
    confidence.isFinite && confidence >= 0 && confidence <= 1;

/// The detected languages of one paragraph text.
final class ParagraphLanguages {
  ParagraphLanguages(this.text, List<DetectedSegment> segments)
    : segments = List.unmodifiable(segments);

  final String text;
  final List<DetectedSegment> segments;

  /// The segment covering UTF-16 [offset], or null (text without letters).
  DetectedSegment? segmentAt(int offset) {
    for (final segment in segments) {
      if (offset >= segment.start && offset < segment.end) return segment;
    }
    return null;
  }

  /// Distinct detected languages per script, in text order.
  Map<TextScript, Set<String>> get languagesByScript {
    final result = <TextScript, Set<String>>{};
    for (final segment in segments) {
      final language = segment.language;
      if (language == null) continue;
      result.putIfAbsent(segment.script, () => <String>{}).add(language);
    }
    return result;
  }

  /// A stable description for cache keys.
  List<Object?> get key => [
    for (final s in segments) [s.start, s.end, s.script.name, s.language],
  ];
}

typedef _PendingLanguageDetection = ({
  Future<List<ParagraphLanguages>> batch,
  int index,
});

/// Runs the policy over paragraphs, batching classifier calls and caching
/// results by text (least recently used dropped after [cacheSize] texts).
final class ParagraphLanguageDetector {
  ParagraphLanguageDetector(
    this.identifier, {
    this.policy = const LanguageDetectionPolicy(),
    this.cacheSize = 4096,
  });

  final LanguageIdentifier identifier;
  final LanguageDetectionPolicy policy;
  final int cacheSize;
  final LinkedHashMap<String, ParagraphLanguages> _cache = LinkedHashMap();
  final _running = <String, _PendingLanguageDetection>{};
  int _cacheGeneration = 0;

  /// The cached result for [text], if detection already ran.
  ParagraphLanguages? cached(String text) {
    final hit = _cache.remove(text);
    if (hit != null) _cache[text] = hit;
    return hit;
  }

  /// Detects [text] (cached).
  Future<ParagraphLanguages> detect(String text) async =>
      (await detectAll([text])).single;

  /// Detects every text with one classifier call for all uncached ones.
  Future<List<ParagraphLanguages>> detectAll(List<String> texts) async {
    final input = List<String>.of(texts, growable: false);
    final results = <String, ParagraphLanguages>{};
    final waits = <String, _PendingLanguageDetection>{};
    final missing = <String>{};
    for (final text in input) {
      if (results.containsKey(text) || waits.containsKey(text)) continue;
      final hit = cached(text);
      final running = _running[text];
      if (hit != null) {
        results[text] = hit;
      } else if (running != null) {
        waits[text] = running;
      } else {
        missing.add(text);
      }
    }
    if (missing.isNotEmpty) {
      final pendingTexts = missing.toList(growable: false);
      final work = _run(pendingTexts, _cacheGeneration);
      for (var i = 0; i < pendingTexts.length; i++) {
        _running[pendingTexts[i]] = (batch: work, index: i);
      }
      try {
        final done = await work;
        for (var i = 0; i < pendingTexts.length; i++) {
          results[pendingTexts[i]] = done[i];
        }
      } finally {
        for (final text in pendingTexts) {
          // A cache reset can start a new batch for the same text.
          if (identical(_running[text]?.batch, work)) _running.remove(text);
        }
      }
    }
    for (final entry in waits.entries) {
      final (:batch, :index) = entry.value;
      results[entry.key] = (await batch)[index];
    }
    return [for (final text in input) results[text]!];
  }

  Future<List<ParagraphLanguages>> _run(
    List<String> texts,
    int generation,
  ) async {
    final segmented = [for (final text in texts) scriptSegments(text)];
    final queries = <String>[];
    for (var t = 0; t < texts.length; t++) {
      for (final segment in segmented[t]) {
        if (!policy.needsClassifier(segment)) continue;
        queries.add(texts[t].substring(segment.start, segment.end));
      }
    }
    var answers = const <List<LanguageGuess>>[];
    if (queries.isNotEmpty && identifier.isAvailable) {
      try {
        answers = await identifier.identify(queries);
        if (answers.length != queries.length) answers = const [];
      } on Object {
        // A failing classifier is the same as an absent one.
        answers = const [];
      }
    }
    final results = <ParagraphLanguages>[];
    // Replies follow the same paragraph and script order as the queries.
    // The policy's letter thresholds are stable across both walks.
    var nextAnswer = 0;
    for (var t = 0; t < texts.length; t++) {
      final segments = <DetectedSegment>[];
      for (final segment in segmented[t]) {
        final guesses =
            nextAnswer < answers.length && policy.needsClassifier(segment)
            ? answers[nextAnswer++]
            : const <LanguageGuess>[];
        segments.add(policy.decide(segment, guesses));
      }
      final result = ParagraphLanguages(texts[t], segments);
      if (generation == _cacheGeneration) _remember(texts[t], result);
      results.add(result);
    }
    return results;
  }

  void _remember(String text, ParagraphLanguages result) {
    if (cacheSize <= 0) return;
    _cache.remove(text);
    _cache[text] = result;
    while (_cache.length > cacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Drops cached and in-flight results (for example after the classifier
  /// became available). Existing callers still receive their result, but
  /// it cannot refill this cache or replace a new detection of the same text.
  void clearCache() {
    _cacheGeneration++;
    _cache.clear();
    _running.clear();
  }
}

/// Primary language subtag of [tag] (`de-CH` -> `de`), lower case.
String primaryLanguageSubtag(String tag) =>
    tag.trim().replaceAll('_', '-').split('-').first.toLowerCase();

/// The proofing language for text whose own (Word) language is [current].
///
/// [currentIsDefault] says whether [current] is only a default: no language
/// set on the text, or one equal to the document default (Word writes the
/// document default onto ordinary text, so it says nothing about the text).
///
/// * An explicit language always wins.
/// * A default yields to the [detection]'s language when that has a
///   different primary subtag, unless the classifier still gives the
///   default at least [keepDefaultConfidence] (CLD3 confuses close
///   languages; a default that is still a candidate is kept).
/// * With the same primary subtag the current tag is kept, so its region
///   (de-CH, en-GB) still applies.
String? resolveDetectedLanguage({
  required String? current,
  required bool currentIsDefault,
  required DetectedSegment? detection,
  double keepDefaultConfidence = 0.01,
}) {
  final detected = detection?.language;
  if (detected == null || (current != null && !currentIsDefault)) {
    return current;
  }
  if (current != null) {
    if (primaryLanguageSubtag(current) == primaryLanguageSubtag(detected)) {
      return current;
    }
    if (detection!.guesses.isNotEmpty &&
        detection.probabilityOf(current) >= keepDefaultConfidence) {
      return current;
    }
  }
  return normalizeProofingLanguage(detected);
}

/// The tag written into the document by "Apply detected language": Word's
/// usual region for the common languages, otherwise the plain tag.
String wordLanguageTagForDetected(String detected) =>
    const <String, String>{
      'ar': 'ar-SA',
      'de': 'de-DE',
      'en': 'en-US',
      'es': 'es-ES',
      'fa': 'fa-IR',
      'fr': 'fr-FR',
      'he': 'he-IL',
      'it': 'it-IT',
      'nl': 'nl-NL',
      'pl': 'pl-PL',
      'pt': 'pt-PT',
      'ru': 'ru-RU',
      'tr': 'tr-TR',
      'ur': 'ur-PK',
    }[detected] ??
    detected;
