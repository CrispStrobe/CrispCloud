part of 'german_writing_rules.dart';

/// One independently reviewed present-indicative paradigm that accepts the
/// original surface. It does not infer forms for an unlisted lemma.
final class GermanReviewedPresentReading {
  const GermanReviewedPresentReading({
    required this.infinitive,
    required this.thirdSingular,
    required this.thirdPlural,
    required this.thirdPersonSubjunctive,
  });

  final String infinitive;
  final String thirdSingular;
  final String thirdPlural;

  /// The source also admits a reviewed Konjunktiv-I reading. A model's
  /// indicative prediction cannot discard this valid competing interpretation.
  final bool thirdPersonSubjunctive;

  String forNumber(bool plural) => plural ? thirdPlural : thirdSingular;

  Map<String, Object> toJson() => {
    'infinitive': infinitive,
    'third_singular': thirdSingular,
    'third_plural': thirdPlural,
    'source_allows_third_person_subjunctive': thirdPersonSubjunctive,
  };
}

/// A licensed or first-party reviewed nominative reading retained by the same
/// facts used by the ordinary German writing provider.
final class GermanNominativeReading {
  GermanNominativeReading({
    required this.gender,
    required this.plural,
    required Iterable<String> forms,
  }) : forms = Set<String>.unmodifiable(forms);

  final String gender;
  final bool plural;
  final Set<String> forms;

  Map<String, Object> toJson() => {
    'gender': gender,
    'plural': plural,
    'nominative_forms': forms.toList(growable: false)..sort(),
  };
}

/// An immutable account of every compatible lexical nominative reading.
/// [ready] does not mean that the phrase is a syntactic subject.
final class GermanNominativeEvidence {
  GermanNominativeEvidence({
    required this.reason,
    Iterable<GermanNominativeReading> readings = const [],
  }) : readings = List<GermanNominativeReading>.unmodifiable(readings);

  final String reason;
  final List<GermanNominativeReading> readings;
  bool get ready => reason == 'reviewed';
  Set<bool> get numbers =>
      Set<bool>.unmodifiable(readings.map((reading) => reading.plural));

  Map<String, Object> toJson() => {
    'reason': reason,
    'numbers': numbers.map((plural) => plural ? 'Plur' : 'Sing').toList(),
    'readings': readings.map((reading) => reading.toJson()).toList(),
  };
}

/// Read-only access to the existing German agreement facts for optional
/// syntax planners. This does not register a provider or change the ordinary
/// provider's matching, tables, precedence, or default behavior.
abstract final class GermanAgreementFacts {
  static int get reviewedParadigmCount =>
      GermanWritingRulesProvider._presentParadigms.length;

  /// Return ALL accepting paradigms, never a last-wins surface dictionary.
  static List<GermanReviewedPresentReading> reviewedPresentReadings(
    String surface,
  ) {
    final lower = normalizeGermanWord(surface).toLowerCase();
    return List<GermanReviewedPresentReading>.unmodifiable([
      for (final paradigm in GermanWritingRulesProvider._presentParadigms)
        if (paradigm.forms.any((form) => _germanFormsEquivalent(form, lower)))
          GermanReviewedPresentReading(
            infinitive: paradigm.infinitive,
            thirdSingular: paradigm.thirdPerson,
            thirdPlural: paradigm.wir,
            thirdPersonSubjunctive: paradigm.isThirdPersonSubjunctive(lower),
          ),
    ]);
  }

  /// Whether a complete source token has licensed, resolved noun evidence.
  /// This is not a case, number, role, or grammatical-validity assertion.
  static Future<bool> hasKnownNoun(String source) async {
    final morphology = GermanNounMorphology.shared;
    await morphology.prepareWords([source]);
    return !morphology.hasUnresolvedReading(source) &&
        morphology.acceptsSpelling(source) &&
        _lookupGrammarNoun(source.toLowerCase()).isNotEmpty;
  }

  static bool sameForm(String a, String b) => _germanFormsEquivalent(a, b);

  /// Grammar corrections, unlike annotation display, need whole graphemes.
  static bool hasSourceBoundaries(String text, int start, int end) {
    if (start < 0 || end < start || end > text.length) return false;
    final boundaries = _sourceGraphemeBoundaries(text);
    return boundaries.contains(start) && boundaries.contains(end);
  }

  /// The existing reviewed predicate vocabulary is safe to share as facts;
  /// callers still have to establish the actual syntactic role independently.
  static bool isReviewedPredicateWord(String surface) =>
      _grammarPredicateAdverbs.contains(surface.toLowerCase());

  static bool isReviewedAttributiveWord(String surface) =>
      _grammarAdjectiveForms.containsKey(surface.toLowerCase());

  /// Preserve all noun alternatives, including number homographs such as
  /// "die Leiter". Unknown/unresolved nouns and nominalized adjectives veto
  /// agreement; a model-selected number cannot bypass those checks.
  static Future<GermanNominativeEvidence> nominativePhrase({
    required String determiner,
    required String noun,
    List<String> adjectives = const [],
  }) async {
    final words = [determiner, ...adjectives, noun];
    final word = RegExp(r'^\p{L}[\p{L}\p{M}]*$', unicode: true);
    if (words.any((value) => !word.hasMatch(value)) ||
        adjectives.length > 3 ||
        noun == noun.toLowerCase()) {
      return GermanNominativeEvidence(reason: 'unsupported-phrase');
    }
    final article = _grammarDeterminerForms[determiner.toLowerCase()];
    if (article == null) {
      return GermanNominativeEvidence(reason: 'unreviewed-determiner');
    }
    if (adjectives.any(
      (value) =>
          value != value.toLowerCase() ||
          !_grammarAdjectiveForms.containsKey(value.toLowerCase()),
    )) {
      return GermanNominativeEvidence(reason: 'unreviewed-adjective');
    }
    final morphology = GermanNounMorphology.shared;
    await morphology.prepareWords([noun]);
    if (morphology.hasUnresolvedReading(noun)) {
      return GermanNominativeEvidence(reason: 'unresolved-noun');
    }
    if (!morphology.acceptsSpelling(noun)) {
      return GermanNominativeEvidence(reason: 'unknown-noun');
    }
    final source = '$determiner $noun';
    final parsed = _grammarWordExpression
        .allMatches(source)
        .map(_GermanGrammarWord.new)
        .toList(growable: false);
    if (parsed.length != 2 ||
        _grammarCouldBeNominalizedAdjective(
          parsed.first,
          article,
          parsed.last,
          null,
        )) {
      return GermanNominativeEvidence(reason: 'nominalized-adjective');
    }
    final readings = [
      for (final reading in _lookupGrammarNoun(noun.toLowerCase()))
        if ((reading.gender != _GermanGender.plural || article.permitsPlural) &&
            article.form(_GermanCase.nominative, reading.gender) ==
                determiner.toLowerCase() &&
            reading.accepts(noun.toLowerCase(), _GermanCase.nominative))
          reading,
    ];
    final retained = [
      for (final reading in readings)
        GermanNominativeReading(
          gender: reading.gender.name,
          plural: reading.gender == _GermanGender.plural,
          forms: reading.inCase(_GermanCase.nominative),
        ),
    ];
    if (retained.isEmpty) {
      return GermanNominativeEvidence(reason: 'no-nominative-reading');
    }
    // Do not use a predicted adjective reading to discard a noun alternative.
    // Every retained reading must satisfy the reviewed adjective forms.
    for (final reading in readings) {
      for (final adjective in adjectives) {
        final ending = _grammarAdjectiveEnding(
          article,
          _GermanCase.nominative,
          reading.gender,
        );
        if (!_grammarAdjectiveForms[adjective.toLowerCase()]!.any(
          (stem) => _germanFormsEquivalent('$stem$ending', adjective),
        )) {
          return GermanNominativeEvidence(
            reason: 'adjective-conflict',
            readings: retained,
          );
        }
      }
    }
    return GermanNominativeEvidence(reason: 'reviewed', readings: retained);
  }
}
