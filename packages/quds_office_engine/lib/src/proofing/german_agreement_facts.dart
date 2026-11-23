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
    final boundaries = GraphemeBoundaries(text);
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

/// One reviewed present-indicative paradigm with every person, for optional
/// syntax planners that establish the subject independently.
final class GermanReviewedPresentParadigm {
  const GermanReviewedPresentParadigm({
    required this.infinitive,
    required this.ich,
    required this.du,
    required this.thirdSingular,
    required this.wir,
    required this.ihr,
  });

  final String infinitive;
  final String ich;
  final String du;
  final String thirdSingular;
  final String wir;
  final String ihr;

  /// Third plural and the polite form equal the wir form in every paradigm.
  String get thirdPlural => wir;

  Set<String> get forms => {ich, du, thirdSingular, wir, ihr};

  /// "er habe", "man nehme": first-person -e forms double as Konjunktiv I.
  bool isThirdPersonSubjunctive(String form) =>
      _germanFormsEquivalent(form, ich) && form.endsWith('e');

  Map<String, Object> toJson() => {
    'infinitive': infinitive,
    'ich': ich,
    'du': du,
    'er': thirdSingular,
    'wir': wir,
    'ihr': ihr,
  };
}

/// A licensed or first-party noun reading with its forms per case.
/// Case indices: 0 nominative, 1 accusative, 2 dative, 3 genitive.
/// Gender indices: 0 masculine, 1 feminine, 2 neuter, 3 plural.
/// An empty case set means unknown, never "no form".
final class GermanNounCaseReading {
  GermanNounCaseReading({
    required this.gender,
    required Iterable<Set<String>> forms,
  }) : forms = List<Set<String>>.unmodifiable(
         forms.map((set) => Set<String>.unmodifiable(set)),
       );

  final int gender;
  final List<Set<String>> forms;
  bool get plural => gender == 3;

  bool accepts(String surface, int grammaticalCase) =>
      forms[grammaticalCase].any(
        (form) =>
            _germanFormsEquivalent(form.toLowerCase(), surface.toLowerCase()),
      );

  Map<String, Object> toJson() => {
    'gender': _GermanGender.values[gender].name,
    'forms': [for (final set in forms) set.toList(growable: false)..sort()],
  };
}

/// The closed reviewed determiner paradigm that contains one surface form.
final class GermanDeterminerFacts {
  const GermanDeterminerFacts._(this._determiner);
  final _GermanDeterminer _determiner;

  String get stem => _determiner.stem;
  bool get definite => _determiner.definite;
  bool get permitsPlural => _determiner.permitsPlural;

  /// The lowercase form for case/gender indices (see [GermanNounCaseReading]).
  String form(int grammaticalCase, int gender) => _determiner.form(
    _GermanCase.values[grammaticalCase],
    _GermanGender.values[gender],
  );

  /// Reviewed attributive adjective ending after this determiner.
  String adjectiveEnding(int grammaticalCase, int gender) =>
      _grammarAdjectiveEnding(
        _determiner,
        _GermanCase.values[grammaticalCase],
        _GermanGender.values[gender],
      );

  /// Every (case, gender) reading whose form equals [surface].
  List<(int, int)> readings(String surface) => [
    for (var c = 0; c < 4; c++)
      for (var g = 0; g < 4; g++)
        if ((g != 3 || permitsPlural) && form(c, g) == surface.toLowerCase())
          (c, g),
  ];
}

/// Additive read-only facts for the optional native planner families.
/// Nothing here changes the ordinary provider's tables or behavior.
abstract final class GermanPhraseFacts {
  static GermanDeterminerFacts? determiner(String surface) {
    final value = _grammarDeterminerForms[surface.toLowerCase()];
    return value == null ? null : GermanDeterminerFacts._(value);
  }

  /// All licensed readings of a complete noun token, or empty when the noun
  /// is unknown, unresolved or not an accepted spelling.
  static Future<List<GermanNounCaseReading>> nounReadings(
    String surface,
  ) async {
    final morphology = GermanNounMorphology.shared;
    await morphology.prepareWords([surface]);
    if (morphology.hasUnresolvedReading(surface) ||
        !morphology.acceptsSpelling(surface)) {
      return const [];
    }
    return List<GermanNounCaseReading>.unmodifiable([
      for (final reading in _lookupGrammarNoun(surface.toLowerCase()))
        GermanNounCaseReading(
          gender: reading.gender.index,
          forms: reading.forms,
        ),
    ]);
  }

  /// Reviewed adjective stems that produce [surface] with a standard ending.
  static Set<String> reviewedAdjectiveStems(String surface) =>
      Set<String>.unmodifiable(
        _grammarAdjectiveForms[surface.toLowerCase()] ?? const <String>{},
      );

  /// Every reviewed present paradigm that contains [surface].
  static List<GermanReviewedPresentParadigm> reviewedPresentParadigms(
    String surface,
  ) {
    final lower = normalizeGermanWord(surface).toLowerCase();
    return List<GermanReviewedPresentParadigm>.unmodifiable([
      for (final paradigm in GermanWritingRulesProvider._presentParadigms)
        if (paradigm.forms.any((form) => _germanFormsEquivalent(form, lower)))
          GermanReviewedPresentParadigm(
            infinitive: paradigm.infinitive,
            ich: paradigm.ich,
            du: paradigm.du,
            thirdSingular: paradigm.thirdPerson,
            wir: paradigm.wir,
            ihr: paradigm.ihr,
          ),
    ]);
  }

  static bool sameForm(String a, String b) => _germanFormsEquivalent(a, b);
}
