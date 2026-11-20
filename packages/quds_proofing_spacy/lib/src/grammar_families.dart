import 'package:quds_office_engine/quds_office_engine.dart'
    show
        GermanAgreementFacts,
        GermanLiteralTextRanges,
        GermanPhraseFacts,
        GermanReviewedPresentParadigm,
        normalizeGermanWord,
        OfficeProofingCategory,
        OfficeProofingFinding,
        OfficeProofingRequest,
        OfficeProofingTextRanges;

import 'analysis.dart';
import 'grammar_verbs.dart';

/// Rule families of the optional manual native German grammar provider.
///
/// [nounVerb] is the W6/W7-qualified noun/finite-verb number agreement. The
/// other families were added in grammar v2 (evidence:
/// `docs/validation/native-spacy-grammar-v2-20261120`). Each family has a
/// stable rule ID, the deterministic rule IDs whose ignore also suppresses
/// it, and short German/English labels and explanations for host UI.
enum SpacyGrammarFamily {
  nounVerb(
    id: 'noun-verb',
    ruleId: 'de.spacy.noun-verb',
    legacyRuleIds: {'de.grammar.noun-verb'},
    labelDe: 'Subjekt und Verb: Singular/Plural',
    labelEn: 'Subject and verb: singular/plural',
    explanationDe:
        'Diese Verbform passt nicht zum lexikalisch eindeutigen Singular oder Plural des analysierten Subjekts.',
    explanationEn:
        'This verb form does not match the unambiguous singular or plural of the analyzed subject.',
  ),
  nounPhraseAgreement(
    id: 'np-agreement',
    ruleId: 'de.spacy.np-agreement',
    legacyRuleIds: {
      'de.grammar.phrase-agreement',
      'de.grammar.adjective-ending',
    },
    labelDe: 'Artikel, Adjektiv und Nomen: Übereinstimmung',
    labelEn: 'Article, adjective and noun agreement',
    explanationDe:
        'Artikel bzw. Adjektivendung passen nicht zu Genus und Numerus des Nomens in dieser Nominalgruppe.',
    explanationEn:
        'The article or adjective ending does not match the gender and number of the noun in this noun phrase.',
  ),
  prepositionCase(
    id: 'preposition-case',
    ruleId: 'de.spacy.preposition-case',
    legacyRuleIds: {'de.grammar.preposition-case'},
    labelDe: 'Kasus nach Präpositionen',
    labelEn: 'Case after prepositions',
    explanationDe:
        'Diese Präposition verlangt einen festen Kasus; die Nominalgruppe steht in einem anderen.',
    explanationEn:
        'This preposition requires a fixed case; the noun phrase is in a different one.',
  ),
  subjectPerson(
    id: 'subject-person',
    ruleId: 'de.spacy.subject-person',
    legacyRuleIds: {'de.grammar.pronoun-verb'},
    labelDe: 'Subjekt und Verb: Person',
    labelEn: 'Subject and verb: person',
    explanationDe:
        'Die Personalform des Verbs passt nicht zum analysierten Subjekt (z. B. „ich geht“ statt „ich gehe“).',
    explanationEn:
        'The verb’s person does not match the analyzed subject (e.g. “ich geht” instead of “ich gehe”).',
  ),
  verbPosition(
    id: 'verb-position',
    ruleId: 'de.spacy.verb-position',
    legacyRuleIds: {'de.grammar.word-order'},
    labelDe: 'Stellung des finiten Verbs',
    labelEn: 'Position of the finite verb',
    explanationDe:
        'Im Hauptsatz steht das finite Verb an zweiter Stelle, im eingeleiteten Nebensatz am Ende.',
    explanationEn:
        'In a main clause the finite verb comes second; in an introduced subordinate clause it comes last.',
  );

  const SpacyGrammarFamily({
    required this.id,
    required this.ruleId,
    required this.legacyRuleIds,
    required this.labelDe,
    required this.labelEn,
    required this.explanationDe,
    required this.explanationEn,
  });

  final String id;
  final String ruleId;
  final Set<String> legacyRuleIds;
  final String labelDe;
  final String labelEn;
  final String explanationDe;
  final String explanationEn;

  bool ignoredBy(Set<String> ignoredRuleIds) =>
      ignoredRuleIds.contains(ruleId) ||
      legacyRuleIds.any(ignoredRuleIds.contains);

  static SpacyGrammarFamily? byId(String id) {
    for (final family in values) {
      if (family.id == id || family.ruleId == id) return family;
    }
    return null;
  }
}

/// One proposal or abstention of a v2 family at one parsed site.
typedef SpacyFamilyOutcome = ({
  SpacyGrammarFamily family,
  int start,
  int end,
  String action,
  String reason,
  List<int> tokenIndices,
  Map<String, Object?> evidence,
  OfficeProofingFinding? finding,
});

final _word = RegExp(r'^\p{L}[\p{L}\p{M}]*$', unicode: true);
final _horizontal = RegExp(r'^[ \t  ]+$');
final _quoteCharacters = RegExp(r'''["'„“”‚‘’«»‹›]''');
final _unsupportedCharacters = RegExp(r'[\u0000-\u001f\u007f­￼]');

// Case indices follow GermanNounCaseReading: 0 Nom, 1 Acc, 2 Dat, 3 Gen.
const _caseNames = ['Nom', 'Acc', 'Dat', 'Gen'];
const _genderNames = ['Masc', 'Fem', 'Neut', 'Plur'];

/// Prepositions with one fixed case when they govern a following noun phrase
/// (value: target case, accepted cases). Variable or regional ones (ab,
/// entlang, laut, dank) are deliberately absent. For wegen/trotz/während/
/// statt the colloquial dative is accepted and never flagged.
const Map<String, (int, Set<int>)> _fixedCasePrepositions = {
  'aus': (2, {2}),
  'bei': (2, {2}),
  'mit': (2, {2}),
  'nach': (2, {2}),
  'seit': (2, {2}),
  'von': (2, {2}),
  'zu': (2, {2}),
  'gegenüber': (2, {2}),
  'außer': (2, {2}),
  'samt': (2, {2}),
  'nebst': (2, {2}),
  'gemäß': (2, {2}),
  'entgegen': (2, {2}),
  'mitsamt': (2, {2}),
  'durch': (1, {1}),
  'für': (1, {1}),
  'gegen': (1, {1}),
  'ohne': (1, {1}),
  'um': (1, {1}),
  'wider': (1, {1}),
  'während': (3, {3, 2}),
  'wegen': (3, {3, 2}),
  'trotz': (3, {3, 2}),
  'statt': (3, {3, 2}),
  'anstatt': (3, {3, 2}),
  'innerhalb': (3, {3}),
  'außerhalb': (3, {3}),
  'oberhalb': (3, {3}),
  'unterhalb': (3, {3}),
  'aufgrund': (3, {3}),
  'anhand': (3, {3}),
  'mittels': (3, {3}),
  'infolge': (3, {3}),
  'bezüglich': (3, {3}),
  'hinsichtlich': (3, {3}),
  'anlässlich': (3, {3}),
};

const _twoWayPrepositions = {
  'in',
  'an',
  'auf',
  'über',
  'unter',
  'vor',
  'hinter',
  'neben',
  'zwischen',
};

const _contractions = <String, Map<String, String>>{
  'an': {'dem': 'am', 'das': 'ans'},
  'in': {'dem': 'im', 'das': 'ins'},
  'bei': {'dem': 'beim'},
  'von': {'dem': 'vom'},
  'zu': {'dem': 'zum', 'der': 'zur'},
};

const _frontedAdverbs = {
  'heute',
  'morgen',
  'gestern',
  'jetzt',
  'dann',
  'danach',
  'später',
  'bald',
  'oft',
  'manchmal',
  'immer',
  'dort',
  'hier',
  'deshalb',
  'deswegen',
  'trotzdem',
  'leider',
  'endlich',
  'zuerst',
  'anschließend',
  'abends',
  'morgens',
  'vorher',
  'nachher',
};

const _subordinators = {
  'dass',
  'ob',
  'wenn',
  'obwohl',
  'nachdem',
  'bevor',
  'falls',
  'damit',
  'sobald',
  'sodass',
};

const _quantityHeads = {
  'reihe',
  'anzahl',
  'mehrheit',
  'minderheit',
  'vielzahl',
  'menge',
  'hälfte',
  'teil',
  'dutzend',
  'paar',
  'prozent',
  'drittel',
  'viertel',
  'million',
  'milliarde',
  'hundert',
  'tausend',
  'handvoll',
  'haufen',
  'mehrzahl',
  'masse',
  'fülle',
  'gruppe',
  'art',
  'rest',
  'großteil',
};

const _finiteTags = {'VVFIN', 'VAFIN', 'VMFIN'};

/// Uninflected colloquial or colour adjectives ("eine super Kneipe").
const _invariableAdjectives = {
  'super',
  'klasse',
  'spitze',
  'prima',
  'rosa',
  'lila',
  'orange',
  'beige',
  'creme',
  'extra',
  'gratis',
  'okay',
  'top',
  'mega',
  'cool',
  'online',
  'live',
};

bool _feature(LinguisticToken token, String name, String value) =>
    token.morphology.split('|').contains('$name=$value');

String _matchInitial(String original, String replacement) {
  if (original.isEmpty || replacement.isEmpty) return replacement;
  final first = original.substring(0, 1);
  if (first != first.toLowerCase()) {
    return replacement.substring(0, 1).toUpperCase() + replacement.substring(1);
  }
  return replacement.substring(0, 1).toLowerCase() + replacement.substring(1);
}

String _nounCase(String form) => form.isEmpty
    ? form
    : form.substring(0, 1).toUpperCase() + form.substring(1);

/// Plans the enabled v2 families for one sentence. Pure Dart: performs no
/// inference, uses the native annotations only for structure (heads,
/// dependency labels, POS/tags of words it does not correct) and the
/// engine's reviewed lexical facts for every corrected form.
final class SpacyGrammarFamilyPlanner {
  SpacyGrammarFamilyPlanner({
    required this.request,
    required this.analysis,
    required this.sentence,
    required this.families,
    required this.personalWords,
    required this.protected,
    required this.literals,
    this.englishMessages = false,
  }) : tokens = analysis.tokens
           .sublist(sentence.startToken, sentence.endToken)
           .where((token) => !token.isSpace)
           .toList(growable: false) {
    for (var i = 0; i < tokens.length; i++) {
      _position[tokens[i].index] = i;
      _byIndex[tokens[i].index] = tokens[i];
    }
  }

  final OfficeProofingRequest request;
  final LinguisticAnalysisResult analysis;
  final LinguisticSentence sentence;
  final Set<SpacyGrammarFamily> families;
  final Set<String> personalWords;
  final OfficeProofingTextRanges protected;
  final GermanLiteralTextRanges literals;
  final bool englishMessages;
  final List<LinguisticToken> tokens;
  final Map<int, int> _position = {};
  final Map<int, LinguisticToken> _byIndex = {};
  final List<SpacyFamilyOutcome> _outcomes = [];

  List<LinguisticToken> _children(LinguisticToken token) => [
    for (final other in tokens)
      if (other.head == token.index && other.index != token.index) other,
  ];

  bool _adjacent(LinguisticToken a, LinguisticToken b) =>
      _position[b.index] == _position[a.index]! + 1 &&
      b.start >= a.end &&
      _horizontal.hasMatch(request.text.substring(a.end, b.start));

  LinguisticToken? _at(int position) =>
      position >= 0 && position < tokens.length ? tokens[position] : null;

  bool _personal(Iterable<LinguisticToken> words) => words.any(
    (token) =>
        personalWords.contains(normalizeGermanWord(token.text).toLowerCase()),
  );

  bool _protectedSpan(int start, int end) =>
      protected.overlaps(start, end) || literals.overlaps(start, end);

  void _record(
    SpacyGrammarFamily family,
    int start,
    int end,
    String action,
    String reason,
    Iterable<LinguisticToken> involved,
    Map<String, Object?> evidence, [
    OfficeProofingFinding? finding,
  ]) {
    _outcomes.add((
      family: family,
      start: start,
      end: end,
      action: action,
      reason: reason,
      tokenIndices: [for (final token in involved) token.index],
      evidence: {'family': family.id, ...evidence},
      finding: finding,
    ));
  }

  /// Returns every recorded site outcome for this sentence.
  Future<List<SpacyFamilyOutcome>> plan() async {
    final text = sentence.text;
    if (_quoteCharacters.hasMatch(text) ||
        _unsupportedCharacters.hasMatch(text) ||
        tokens.length > 80 ||
        text.length > 2048) {
      return const [];
    }
    if (families.contains(SpacyGrammarFamily.nounPhraseAgreement) ||
        families.contains(SpacyGrammarFamily.prepositionCase)) {
      for (final token in tokens) {
        if (token.pos == 'NOUN' && token.tag == 'NN') await _nounPhrase(token);
      }
    }
    if (families.contains(SpacyGrammarFamily.subjectPerson)) {
      for (final token in tokens) {
        if (_finiteTags.contains(token.tag)) await _person(token);
      }
    }
    if (families.contains(SpacyGrammarFamily.verbPosition)) {
      _verbThird();
      for (final token in tokens) {
        if (token.pos == 'SCONJ' &&
            token.tag == 'KOUS' &&
            _subordinators.contains(token.text.toLowerCase())) {
          _subordinateVerbSecond(token);
        }
      }
    }
    return List<SpacyFamilyOutcome>.unmodifiable(_outcomes);
  }

  // ---------------------------------------------------------------------
  // Noun phrase agreement and preposition case.

  Future<void> _nounPhrase(LinguisticToken noun) async {
    final nounAt = _position[noun.index]!;
    var at = nounAt - 1;
    final adjectives = <LinguisticToken>[];
    while (at >= 0 &&
        tokens[at].tag == 'ADJA' &&
        tokens[at].head == noun.index &&
        tokens[at].dependency == 'nk') {
      adjectives.insert(0, tokens[at]);
      at--;
    }
    final article = _at(at);
    if (article == null ||
        article.pos != 'DET' ||
        !const {'ART', 'PPOSAT', 'PDAT', 'PIAT'}.contains(article.tag) ||
        article.head != noun.index ||
        article.dependency != 'nk') {
      return;
    }
    final determiner = GermanPhraseFacts.determiner(article.text);
    if (determiner == null) return;
    final phrase = [article, ...adjectives, noun];
    final evidence = <String, Object?>{
      'determiner': article.text,
      'adjectives': [for (final a in adjectives) a.text],
      'noun': noun.text,
      'noun_dependency': noun.dependency,
    };
    // Family is decided after analysis; until then record under np.
    var family = SpacyGrammarFamily.nounPhraseAgreement;
    void abstain(String reason, {String action = 'abstained'}) => _record(
      family,
      article.start,
      noun.end,
      action,
      reason,
      phrase,
      evidence,
    );

    if (phrase.any((token) => !_word.hasMatch(token.text)) ||
        adjectives.length > 3) {
      return abstain('unsupported-phrase-shape');
    }
    for (var i = 1; i < phrase.length; i++) {
      if (!_adjacent(phrase[i - 1], phrase[i])) {
        return abstain('unsupported-word-boundary');
      }
    }
    if (noun.text == noun.text.toLowerCase() ||
        (noun.text.length > 1 && noun.text == noun.text.toUpperCase()) ||
        adjectives.any((a) => a.text != a.text.toLowerCase()) ||
        (article.text != article.text.toLowerCase() &&
            article.text.substring(1) !=
                article.text.substring(1).toLowerCase())) {
      return abstain('unsupported-capitalization');
    }
    // Coordination, modified adjectives and further prenominal material can
    // share or redistribute agreement ("die Lehrer und Lehrerinnen").
    if (noun.dependency == 'cj' ||
        _children(noun).any((c) => const {'cd', 'cj'}.contains(c.dependency)) ||
        adjectives.any((a) => _children(a).isNotEmpty) ||
        _children(article).isNotEmpty) {
      return abstain('coordination-or-modifier');
    }
    final before = _at(at - 1);
    if (before != null && before.head == noun.index) {
      return abstain('additional-prenominal-material');
    }
    if (before != null &&
        (const {
              'PIAT',
              'PIDAT',
              'CARD',
              'ART',
              'PDAT',
              'PPOSAT',
            }.contains(before.tag) ||
            const {'als', 'wie'}.contains(before.text.toLowerCase()))) {
      return abstain('unsupported-prenominal-context');
    }
    final after = _at(nounAt + 1);
    if (after != null &&
        after.start == noun.end &&
        !const {'.', ',', '!', '?', ';', ':'}.contains(after.text)) {
      return abstain('attached-continuation');
    }
    if (after != null &&
        (RegExp(r'^[-–—/]+$').hasMatch(after.text) ||
            const {'NOUN', 'PROPN'}.contains(after.pos))) {
      // Truncated compounds ("Gouverneurs- und ...") and multiword names or
      // appositions ("des Power Forwards") have no single agreeing head.
      return abstain('compound-or-multiword');
    }
    if (before != null && before.text == ',' && determiner.stem == 'd') {
      return abstain('possible-relative-pronoun');
    }
    if (article.text.toLowerCase() == 'ein' &&
        const {'uhr'}.contains(noun.text.toLowerCase())) {
      return abstain('numeral-reading');
    }
    if (adjectives.any(
      (a) => _invariableAdjectives.contains(a.text.toLowerCase()),
    )) {
      return abstain('invariable-adjective');
    }
    if (_personal(phrase)) return abstain('personal-vocabulary');
    if (GermanPhraseFacts.reviewedAdjectiveStems(noun.text).isNotEmpty) {
      return abstain('nominalized-adjective');
    }
    // "Email" (enamel, neuter) is the common spelling of "E-Mail" (feminine);
    // its article reflects the intended word, not an agreement error.
    if (const {'email', 'emails'}.contains(noun.text.toLowerCase())) {
      return abstain('orthographic-variant-noun');
    }
    if (_quantityHeads.contains(noun.text.toLowerCase()) ||
        _quantityHeads.contains(noun.lemma.toLowerCase())) {
      return abstain('quantity-head');
    }

    // Governing preposition: the token directly before the determiner that
    // the parse makes the head of this noun.
    int? targetCase;
    Set<int> allowed = {0, 1, 2, 3};
    var context = 'none';
    LinguisticToken? preposition;
    if (before != null &&
        noun.head == before.index &&
        noun.dependency == 'nk' &&
        _adjacent(before, article)) {
      final lower = before.text.toLowerCase();
      final fixed = _fixedCasePrepositions[lower];
      if (fixed != null &&
          (before.pos == 'ADP' ||
              (lower == 'während' && before.pos == 'SCONJ'))) {
        preposition = before;
        targetCase = fixed.$1;
        allowed = fixed.$2;
        context = 'fixed-preposition';
        if (lower == 'um' &&
            tokens.any((token) => token.text.toLowerCase() == 'willen')) {
          return abstain('um-willen');
        }
      } else if (_twoWayPrepositions.contains(lower) && before.pos == 'ADP') {
        preposition = before;
        allowed = {1, 2};
        context = 'two-way-preposition';
      } else {
        return abstain('unreviewed-governor');
      }
    } else if (before != null &&
        (before.pos == 'ADP' || before.tag == 'APPRART')) {
      return abstain('unattached-governor');
    }
    evidence['context'] = context;
    if (preposition != null) evidence['preposition'] = preposition.text;
    final start = preposition?.start ?? article.start;
    if (_protectedSpan(start, noun.end)) return abstain('protected-context');

    final readings = await GermanPhraseFacts.nounReadings(noun.text);
    if (readings.isEmpty) return abstain('unknown-noun');
    if (readings.any((r) => r.forms.any((set) => set.isEmpty))) {
      return abstain('incomplete-noun-paradigm');
    }
    evidence['noun_readings'] = [for (final r in readings) r.toJson()];
    final adjectiveOptions = <List<(String, String)>>[];
    for (final adjective in adjectives) {
      final options = _adjectiveOptions(adjective);
      if (options.isEmpty) return abstain('unknown-adjective');
      adjectiveOptions.add(options);
    }

    bool adjectivesFit(int c, int g) {
      final ending = determiner.adjectiveEnding(c, g);
      return adjectiveOptions.every(
        (options) => options.any((option) => option.$2 == ending),
      );
    }

    final consistent = <(int, int)>[
      for (var c = 0; c < 4; c++)
        for (final reading in readings)
          if ((reading.gender != 3 || determiner.permitsPlural) &&
              determiner.form(c, reading.gender) ==
                  article.text.toLowerCase() &&
              reading.accepts(noun.text, c) &&
              adjectivesFit(c, reading.gender))
            (c, reading.gender),
    ];
    evidence['consistent_readings'] = [
      for (final r in consistent) '${_caseNames[r.$1]}.${_genderNames[r.$2]}',
    ];
    if (consistent.any((r) => allowed.contains(r.$1))) {
      return abstain('compatible-reading', action: 'preserved');
    }
    family = consistent.isNotEmpty
        ? SpacyGrammarFamily.prepositionCase
        : SpacyGrammarFamily.nounPhraseAgreement;
    if (!families.contains(family)) return abstain('family-disabled');

    // Candidate target cases: the governed case; otherwise the article's own
    // case readings, narrowed by the parsed role when that is one of them.
    final articleCases = {
      for (final r in determiner.readings(article.text)) r.$1,
    };
    Set<int> cases;
    if (targetCase != null) {
      cases = {targetCase};
    } else if (context == 'two-way-preposition') {
      cases = consistent.isEmpty ? articleCases.intersection({1, 2}) : {1, 2};
    } else {
      cases = articleCases;
      final role = switch (noun.dependency) {
        'sb' || 'pd' => 0,
        'oa' => 1,
        'da' => 2,
        'ag' => 3,
        _ => null,
      };
      if (role != null && cases.contains(role)) cases = {role};
    }
    evidence['target_cases'] = [
      for (final c in cases.toList()..sort()) _caseNames[c],
    ];

    final candidates =
        <
          ({int edits, List<String> words, String key, bool plural, int gender})
        >[];
    for (final c in cases) {
      for (final reading in readings) {
        final g = reading.gender;
        if (g == 3 && !determiner.permitsPlural) continue;
        String nounOut;
        if (reading.accepts(noun.text, c)) {
          nounOut = noun.text;
        } else {
          final forms = reading.forms[c].map((f) => f.toLowerCase()).toSet();
          String? chosen;
          if (forms.length == 1) {
            chosen = forms.single;
          } else if (forms.length == 2) {
            final sorted = forms.toList()..sort((a, b) => a.length - b.length);
            if ('${sorted[0].substring(0, sorted[0].length - 1)}es' ==
                    sorted[1] &&
                sorted[0].endsWith('s')) {
              chosen = sorted[0];
            }
          }
          if (chosen == null) continue;
          nounOut = _nounCase(chosen);
        }
        final articleOut = _matchInitial(article.text, determiner.form(c, g));
        final adjectiveOut = <String>[];
        var ambiguous = false;
        for (final options in adjectiveOptions) {
          final outs = {
            for (final option in options)
              '${option.$1}${determiner.adjectiveEnding(c, g)}',
          };
          if (outs.length != 1) ambiguous = true;
          adjectiveOut.add(outs.first);
        }
        if (ambiguous) continue;
        final words = [articleOut, ...adjectiveOut, nounOut];
        var edits = 0;
        for (var i = 0; i < phrase.length; i++) {
          if (words[i] != phrase[i].text) edits++;
        }
        candidates.add((
          edits: edits,
          words: words,
          key: words.join(' '),
          plural: g == 3,
          gender: g,
        ));
      }
    }
    if (candidates.isEmpty) return abstain('no-reviewed-target');
    // Keep the number the writer's article already expresses when possible.
    final articleNumbers = {
      for (final r in determiner.readings(article.text)) r.$2 == 3,
    };
    final sameNumber = [
      for (final c in candidates)
        if (articleNumbers.contains(c.plural)) c,
    ];
    if (sameNumber.isNotEmpty && sameNumber.length < candidates.length) {
      candidates
        ..clear()
        ..addAll(sameNumber);
    }
    final fewest = candidates
        .map((c) => c.edits)
        .reduce((a, b) => a < b ? a : b);
    final best = {
      for (final c in candidates)
        if (c.edits == fewest) c.key: c,
    };
    evidence['targets'] = best.keys.toList()..sort();
    if (best.length != 1 || fewest == 0) return abstain('ambiguous-target');
    final chosen = best.values.single;
    final target = chosen.words;
    // A noun form is only rewritten together with its article: a changed noun
    // alone may be an accepted variant the lexicon lacks ("der Willen").
    if (target.last != noun.text && target.first == article.text) {
      return abstain('noun-form-only');
    }
    // For a gender/number mismatch the lexicon decides the target gender; a
    // disagreeing model reading of the noun itself (e.g. "Email" vs
    // "E-Mail") vetoes the proposal rather than being overridden.
    if (family == SpacyGrammarFamily.nounPhraseAgreement) {
      final modelPlural = _feature(noun, 'Number', 'Plur');
      final modelSingular = _feature(noun, 'Number', 'Sing');
      final modelGender = [
        for (final g in const ['Masc', 'Fem', 'Neut'])
          if (_feature(noun, 'Gender', g)) g,
      ];
      if ((chosen.plural && modelSingular) ||
          (!chosen.plural && modelPlural) ||
          (!chosen.plural &&
              modelGender.length == 1 &&
              modelGender.single != _genderNames[chosen.gender])) {
        evidence['model_noun_morphology'] = noun.morphology;
        return abstain('model-lexicon-gender-disagreement');
      }
    }

    // Build one edit from the first to the last changed token, keeping the
    // original separators; contract "zu dem" -> "zum" when the article changed.
    var first = phrase.indexWhere((t) => target[phrase.indexOf(t)] != t.text);
    final last = phrase.lastIndexWhere(
      (t) => target[phrase.indexOf(t)] != t.text,
    );
    var editStart = phrase[first].start;
    final buffer = StringBuffer();
    String? contracted;
    if (first == 0 && preposition != null && determiner.stem == 'd') {
      contracted =
          _contractions[preposition.text.toLowerCase()]?[target[0]
              .toLowerCase()];
    }
    if (contracted != null) {
      editStart = preposition!.start;
      buffer.write(_matchInitial(preposition.text, contracted));
      first = 1;
      if (last >= 1) {
        buffer.write(request.text.substring(phrase[0].end, phrase[1].start));
      }
    }
    for (var i = first; i <= last; i++) {
      if (i > first) {
        buffer.write(
          request.text.substring(phrase[i - 1].end, phrase[i].start),
        );
      }
      buffer.write(target[i]);
    }
    final editEnd = phrase[last].end;
    final replacement = buffer.toString();
    evidence['replacement'] = replacement;
    if (!GermanAgreementFacts.hasSourceBoundaries(
      request.text,
      editStart,
      editEnd,
    )) {
      return abstain('non-grapheme-edit');
    }
    if (family.ignoredBy(request.ignoredRuleIds)) {
      return abstain('ignored-rule', action: 'suppressed');
    }
    _record(
      family,
      editStart,
      editEnd,
      'proposed',
      family == SpacyGrammarFamily.prepositionCase
          ? 'governed-case-mismatch'
          : 'phrase-agreement-mismatch',
      [?preposition, ...phrase],
      evidence,
      OfficeProofingFinding.forRequest(
        request,
        providerId: 'spacy-german-grammar',
        start: editStart,
        end: editEnd,
        ruleId: family.ruleId,
        message: englishMessages ? family.explanationEn : family.explanationDe,
        category: OfficeProofingCategory.grammar,
        replacements: [replacement],
      ),
    );
  }

  List<(String, String)> _adjectiveOptions(LinguisticToken adjective) {
    final lower = adjective.text.toLowerCase();
    final options = <(String, String)>{};
    const endings = ['e', 'en', 'em', 'er', 'es'];
    for (final stem in GermanPhraseFacts.reviewedAdjectiveStems(lower)) {
      for (final ending in endings) {
        if (GermanPhraseFacts.sameForm('$stem$ending', lower)) {
          options.add((stem, ending));
        }
      }
    }
    final lemma = adjective.lemma;
    if (_word.hasMatch(lemma) && lemma == lemma.toLowerCase()) {
      for (final ending in endings) {
        if (GermanPhraseFacts.sameForm('$lemma$ending', lower)) {
          options.add((lemma, ending));
        }
      }
    }
    return options.toList(growable: false);
  }

  // ---------------------------------------------------------------------
  // Subject person agreement.

  Future<void> _person(LinguisticToken verb) async {
    final subjects = _children(
      verb,
    ).where((t) => t.dependency == 'sb').toList();
    if (subjects.length != 1) return;
    final subject = subjects.single;
    const family = SpacyGrammarFamily.subjectPerson;
    final evidence = <String, Object?>{
      'verb': verb.text,
      'subject': subject.text,
      'subject_tag': subject.tag,
    };
    final sentenceInitial = _position[verb.index] == 0;
    void abstain(String reason, {String action = 'abstained'}) => _record(
      family,
      verb.start,
      verb.end,
      action,
      reason,
      [subject, verb],
      evidence,
    );

    String? person;
    var nounSubject = false;
    final lowerSubject = subject.text.toLowerCase();
    if (subject.tag == 'PPER') {
      person = const {
        'ich': 'ich',
        'du': 'du',
        'er': 'er',
        'wir': 'wir',
        'ihr': 'ihr',
      }[lowerSubject];
      if (person == null) return; // sie/Sie/es: never adjudicated.
      if (subject.text != lowerSubject && _position[subject.index] != 0) {
        return abstain('unsupported-capitalization');
      }
      if (!_feature(subject, 'Case', 'Nom')) {
        return abstain('pronoun-not-nominative');
      }
    } else if (subject.tag == 'PIS' && subject.text == 'man') {
      person = 'er';
    } else if (subject.pos == 'NOUN' && subject.tag == 'NN') {
      nounSubject = true;
    } else {
      return;
    }
    if (!_word.hasMatch(verb.text) ||
        (verb.text != verb.text.toLowerCase() &&
            !(sentenceInitial &&
                verb.text.substring(1) ==
                    verb.text.substring(1).toLowerCase()))) {
      return abstain('unsupported-verb-capitalization');
    }
    if (_children(
          subject,
        ).any((c) => const {'cd', 'cj'}.contains(c.dependency)) ||
        subject.dependency == 'cj') {
      return abstain('coordinated-subject');
    }
    // Post-qualification guard (grammar v2 record, sp-valid-07): the parser
    // can attach "X und ich" so that only "ich" is the subject of a plural
    // verb. A nominal directly before "und/oder ich" means coordination.
    final subjectAt = _position[subject.index]!;
    final conjunction = _at(subjectAt - 1);
    final previous = _at(subjectAt - 2);
    if (conjunction != null &&
        conjunction.pos == 'CCONJ' &&
        previous != null &&
        const {'NOUN', 'PROPN', 'PRON'}.contains(previous.pos)) {
      return abstain('possible-coordinated-subject');
    }
    if (_personal([subject, verb])) return abstain('personal-vocabulary');
    final paradigms = spacyPresentParadigms(verb.text);
    evidence['paradigms'] = [for (final p in paradigms) p.toJson()];
    if (paradigms.isEmpty) return abstain('unreviewed-verb');
    bool same(String a) =>
        GermanPhraseFacts.sameForm(a, verb.text.toLowerCase());
    // "ich muss sagen", "was man haben muss": an infinitive misparsed as the
    // finite verb. Any other finite auxiliary/modal in the same clause vetoes.
    if (paradigms.any((p) => same(p.infinitive)) &&
        _clauseHasOtherFinite(verb)) {
      return abstain('infinitive-homograph');
    }

    if (nounSubject) {
      // Third person by construction; number comes from reviewed lexical
      // facts of the complete determiner phrase.
      if (paradigms.any((p) => same(p.thirdSingular) || same(p.thirdPlural))) {
        return; // Number agreement belongs to the existing noun-verb rule.
      }
      if (_quantityHeads.contains(lowerSubject) ||
          _quantityHeads.contains(subject.lemma.toLowerCase())) {
        return abstain('quantity-head');
      }
      final subjectAt = _position[subject.index]!;
      var at = subjectAt - 1;
      final adjectives = <LinguisticToken>[];
      while (at >= 0 &&
          tokens[at].tag == 'ADJA' &&
          tokens[at].head == subject.index) {
        adjectives.insert(0, tokens[at]);
        at--;
      }
      final article = _at(at);
      if (article == null ||
          article.pos != 'DET' ||
          article.head != subject.index ||
          article.dependency != 'nk') {
        return abstain('missing-determiner');
      }
      final lexical = await GermanAgreementFacts.nominativePhrase(
        determiner: article.text,
        noun: subject.text,
        adjectives: [for (final a in adjectives) a.text],
      );
      evidence['noun_evidence'] = lexical.toJson();
      if (!lexical.ready) return abstain(lexical.reason);
      if (lexical.numbers.length != 1) return abstain('ambiguous-noun-number');
      person = lexical.numbers.single ? 'sie-plural' : 'er';
      if (_personal([article, ...adjectives])) {
        return abstain('personal-vocabulary');
      }
    }
    evidence['person'] = person;
    String expected(GermanReviewedPresentParadigm p) => switch (person) {
      'ich' => p.ich,
      'du' => p.du,
      'er' => p.thirdSingular,
      'wir' || 'sie-plural' => p.wir,
      'ihr' => p.ihr,
      _ => throw StateError('person'),
    };
    if (paradigms.any((p) => same(expected(p)))) {
      return abstain('compatible-reading', action: 'preserved');
    }
    if ((person == 'er' || person == 'sie-plural') &&
        paradigms.any(
          (p) => p.isThirdPersonSubjunctive(verb.text.toLowerCase()),
        )) {
      return abstain('compatible-subjunctive-reading', action: 'preserved');
    }
    if (person == 'du' &&
        _position[verb.index]! < _position[subject.index]! &&
        paradigms.any(
          (p) => p.isThirdPersonSubjunctive(verb.text.toLowerCase()),
        )) {
      return abstain('possible-imperative', action: 'preserved');
    }
    final targets = {for (final p in paradigms) expected(p)};
    if (targets.length != 1) return abstain('competing-verb-targets');
    final replacement = _matchInitial(verb.text, targets.single);
    evidence['replacement'] = replacement;
    if (_protectedSpan(
      subject.start < verb.start ? subject.start : verb.start,
      subject.end > verb.end ? subject.end : verb.end,
    )) {
      return abstain('protected-context');
    }
    if (!GermanAgreementFacts.hasSourceBoundaries(
      request.text,
      verb.start,
      verb.end,
    )) {
      return abstain('non-grapheme-edit');
    }
    if (family.ignoredBy(request.ignoredRuleIds)) {
      return abstain('ignored-rule', action: 'suppressed');
    }
    _record(
      family,
      verb.start,
      verb.end,
      'proposed',
      'reviewed-person-disagreement',
      [subject, verb],
      evidence,
      OfficeProofingFinding.forRequest(
        request,
        providerId: 'spacy-german-grammar',
        start: verb.start,
        end: verb.end,
        ruleId: family.ruleId,
        message: englishMessages ? family.explanationEn : family.explanationDe,
        category: OfficeProofingCategory.grammar,
        replacements: [replacement],
      ),
    );
  }

  bool _clauseHasOtherFinite(LinguisticToken verb) {
    final at = _position[verb.index]!;
    bool boundary(LinguisticToken t) =>
        t.pos == 'PUNCT' || t.pos == 'SCONJ' || t.pos == 'CCONJ';
    bool verbal(LinguisticToken t) =>
        t.index != verb.index &&
        (_finiteTags.contains(t.tag) || t.tag == 'VMINF' || t.tag == 'VAINF');
    for (var i = at - 1; i >= 0 && !boundary(tokens[i]); i--) {
      if (verbal(tokens[i])) return true;
    }
    for (var i = at + 1; i < tokens.length && !boundary(tokens[i]); i++) {
      if (verbal(tokens[i])) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------
  // Verb position.

  /// The subject phrase starting at [position]: a nominative personal pronoun
  /// or determiner + adjectives + common noun, all headed to [verb].
  List<LinguisticToken>? _subjectAt(int position, LinguisticToken verb) {
    final first = _at(position);
    if (first == null) return null;
    if (first.tag == 'PPER' &&
        first.dependency == 'sb' &&
        first.head == verb.index &&
        _feature(first, 'Case', 'Nom') &&
        first.text == first.text.toLowerCase()) {
      return [first];
    }
    if (first.pos != 'DET' || first.dependency != 'nk') return null;
    final phrase = [first];
    var at = position + 1;
    while (_at(at)?.tag == 'ADJA') {
      phrase.add(tokens[at++]);
    }
    final noun = _at(at);
    if (noun == null ||
        noun.pos != 'NOUN' ||
        noun.dependency != 'sb' ||
        noun.head != verb.index ||
        phrase.any((t) => t.head != noun.index)) {
      return null;
    }
    return [...phrase, noun];
  }

  void _verbThird() {
    if (tokens.length < 4) return;
    final first = tokens.first;
    final lower = first.text.toLowerCase();
    List<LinguisticToken> fronted;
    if (first.pos == 'ADV' && _frontedAdverbs.contains(lower)) {
      fronted = [first];
    } else if (first.pos == 'ADP' && first.tag == 'APPR' ||
        first.tag == 'APPRART') {
      // Preposition, optional determiner/adjectives, noun headed to it.
      var at = 1;
      if (first.tag == 'APPR' && _at(at)?.pos == 'DET') at++;
      while (_at(at)?.tag == 'ADJA') {
        at++;
      }
      final noun = _at(at);
      if (noun == null ||
          !const {'NOUN', 'PROPN'}.contains(noun.pos) ||
          noun.head != first.index ||
          noun.dependency != 'nk') {
        return;
      }
      fronted = tokens.sublist(0, at + 1);
      if (fronted
          .skip(1)
          .take(fronted.length - 2)
          .any((t) => t.head != noun.index)) {
        return;
      }
    } else {
      return;
    }
    final verbCandidates = [
      for (final t in tokens)
        if (t.dependency == 'ROOT' && _finiteTags.contains(t.tag)) t,
    ];
    if (verbCandidates.length != 1) return;
    final verb = verbCandidates.single;
    if (fronted.first.head != verb.index) return;
    final subject = _subjectAt(fronted.length, verb);
    if (subject == null) return;
    final verbAt = fronted.length + subject.length;
    if (_at(verbAt)?.index != verb.index) return;
    const family = SpacyGrammarFamily.verbPosition;
    final involved = [...fronted, ...subject, verb];
    final evidence = <String, Object?>{
      'subtype': 'main-clause-verb-third',
      'fronted': [for (final t in fronted) t.text],
      'subject': [for (final t in subject) t.text],
      'verb': verb.text,
    };
    void abstain(String reason, {String action = 'abstained'}) => _record(
      family,
      subject.first.start,
      verb.end,
      action,
      reason,
      involved,
      evidence,
    );
    final last = tokens.last;
    if (!const {'.', '!'}.contains(last.text) ||
        tokens.any((t) => t.text == '?')) {
      return abstain('unsupported-sentence-type');
    }
    for (var i = 1; i <= verbAt; i++) {
      if (!_adjacent(tokens[i - 1], tokens[i]) ||
          !_word.hasMatch(tokens[i].text)) {
        return abstain('unsupported-word-boundary');
      }
    }
    if (!_word.hasMatch(first.text) ||
        verb.text != verb.text.toLowerCase() ||
        _children(verb).where((t) => t.dependency == 'sb').length != 1) {
      return abstain('unsupported-verb-analysis');
    }
    if (_personal(involved)) return abstain('personal-vocabulary');
    if (_protectedSpan(first.start, verb.end)) {
      return abstain('protected-context');
    }
    final start = subject.first.start;
    final gap = request.text.substring(subject.last.end, verb.start);
    final replacement =
        '${verb.text}$gap${request.text.substring(start, subject.last.end)}';
    evidence['replacement'] = replacement;
    if (!GermanAgreementFacts.hasSourceBoundaries(
      request.text,
      start,
      verb.end,
    )) {
      return abstain('non-grapheme-edit');
    }
    if (family.ignoredBy(request.ignoredRuleIds)) {
      return abstain('ignored-rule', action: 'suppressed');
    }
    _record(
      family,
      start,
      verb.end,
      'proposed',
      'main-clause-verb-third',
      involved,
      evidence,
      OfficeProofingFinding.forRequest(
        request,
        providerId: 'spacy-german-grammar',
        start: start,
        end: verb.end,
        ruleId: family.ruleId,
        message: englishMessages ? family.explanationEn : family.explanationDe,
        category: OfficeProofingCategory.grammar,
        replacements: [replacement],
      ),
    );
  }

  void _subordinateVerbSecond(LinguisticToken conjunction) {
    final conjunctionAt = _position[conjunction.index]!;
    final head = _byIndex[conjunction.head];
    if (head == null) return;
    if (conjunction.dependency != 'cp' || !_finiteTags.contains(head.tag)) {
      return;
    }
    final verb = head;
    final subject = _subjectAt(conjunctionAt + 1, verb);
    if (subject == null) return;
    final verbAt = conjunctionAt + 1 + subject.length;
    if (_at(verbAt)?.index != verb.index) return;
    const family = SpacyGrammarFamily.verbPosition;
    final rest = <LinguisticToken>[];
    var at = verbAt + 1;
    while (_at(at) != null && tokens[at].pos != 'PUNCT') {
      rest.add(tokens[at++]);
    }
    final closing = _at(at);
    final involved = [conjunction, ...subject, verb, ...rest];
    final evidence = <String, Object?>{
      'subtype': 'subordinate-clause-verb-second',
      'conjunction': conjunction.text,
      'subject': [for (final t in subject) t.text],
      'verb': verb.text,
      'rest': [for (final t in rest) t.text],
    };
    void abstain(String reason, {String action = 'abstained'}) => _record(
      family,
      verb.start,
      rest.isEmpty ? verb.end : rest.last.end,
      action,
      reason,
      involved,
      evidence,
    );
    if (rest.isEmpty) return; // Already clause-final.
    if (closing == null ||
        !const {',', '.', '!', '?', ';', ':'}.contains(closing.text)) {
      return abstain('unsupported-clause-end');
    }
    if (rest.length > 12) return abstain('clause-too-long');
    // Comparisons and prepositional phrases may legitimately follow the
    // clause-final verb (Ausklammerung: "dass es aussah wie ein Wal").
    if (rest.first.pos == 'ADP' ||
        rest.any((t) => t.tag == 'KOKOM' || t.tag == 'APPRART')) {
      return abstain('possible-extraposition');
    }
    final clause = [conjunction, ...subject, verb, ...rest];
    for (var i = 1; i < clause.length; i++) {
      if (!_adjacent(clause[i - 1], clause[i])) {
        return abstain('unsupported-word-boundary');
      }
    }
    if (clause.any((t) => !_word.hasMatch(t.text) && t.pos != 'NUM')) {
      return abstain('unsupported-token');
    }
    if (verb.text != verb.text.toLowerCase()) {
      return abstain('unsupported-verb-capitalization');
    }
    // Another verb form, separable particle, zu-infinitive, coordination or a
    // nested clause makes the target order a real reordering problem.
    if (rest.any(
      (t) =>
          const {'VERB', 'AUX', 'CCONJ', 'SCONJ'}.contains(t.pos) ||
          t.tag.startsWith('V') ||
          const {
            'PTKVZ',
            'PTKZU',
            'PRELS',
            'PRELAT',
            'PWS',
            'PWAV',
            'PWAT',
            'KON',
          }.contains(t.tag),
    )) {
      return abstain('complex-clause');
    }
    // Every remaining token must belong to the finite verb's clause.
    final members = {for (final t in rest) t.index};
    for (final token in rest) {
      var current = token;
      var steps = 0;
      while (current.head != verb.index) {
        if (steps++ > 20 ||
            current.head == current.index ||
            !members.contains(current.head)) {
          return abstain('detached-clause-material');
        }
        current = _byIndex[current.head]!;
      }
    }
    if (_personal(clause)) return abstain('personal-vocabulary');
    final start = verb.start;
    final end = rest.last.end;
    if (_protectedSpan(conjunction.start, end)) {
      return abstain('protected-context');
    }
    final gap = request.text.substring(verb.end, rest.first.start);
    final replacement =
        '${request.text.substring(rest.first.start, end)}$gap${verb.text}';
    evidence['replacement'] = replacement;
    if (!GermanAgreementFacts.hasSourceBoundaries(request.text, start, end)) {
      return abstain('non-grapheme-edit');
    }
    if (family.ignoredBy(request.ignoredRuleIds)) {
      return abstain('ignored-rule', action: 'suppressed');
    }
    _record(
      family,
      start,
      end,
      'proposed',
      'subordinate-clause-verb-second',
      involved,
      evidence,
      OfficeProofingFinding.forRequest(
        request,
        providerId: 'spacy-german-grammar',
        start: start,
        end: end,
        ruleId: family.ruleId,
        message: englishMessages ? family.explanationEn : family.explanationDe,
        category: OfficeProofingCategory.grammar,
        replacements: [replacement],
      ),
    );
  }
}

/// Exposed for tests and host UI: the explanation for a rule ID.
String? spacyGrammarExplanation(String ruleId, {bool english = false}) {
  final family = SpacyGrammarFamily.byId(ruleId);
  if (family == null) return null;
  return english ? family.explanationEn : family.explanationDe;
}
