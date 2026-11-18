import 'package:characters/characters.dart';

import 'german_literal_ranges.dart';
import 'german_morphology.dart';
import 'german_spelling.dart' show normalizeGermanWord;
import 'office_proofing.dart';
import 'proofing_text_ranges.dart';

part 'german_grammar.dart';
part 'german_context_grammar.dart';
part 'german_agreement_facts.dart';

Set<int> _sourceGraphemeBoundaries(String text) {
  final Set<int> boundaries = <int>{0};
  int end = 0;
  for (final String cluster in text.characters) {
    end += cluster.length;
    boundaries.add(end);
  }
  return boundaries;
}

/// Independently authored writing checks with licensed noun morphology.
/// This provider is not a general sentence parser.
/// Findings are advisory and never rewrite text. Unbalanced quotes can be valid
/// across paragraph boundaries and are explicitly described as review items.
/// A pattern with an endpoint inside a source grapheme is omitted rather than
/// offering a partial range or widening a replacement over adjacent marks.
class GermanWritingRulesProvider extends OfficeProofingProvider {
  bool _disposed = false;
  @override
  String get id => 'german-writing';
  @override
  bool supportsLanguage(String language) => const <String>{
    'de-DE',
    'de-AT',
    'de-CH',
  }.contains(normalizeProofingLanguage(language));
  static const Set<String> ruleIds = <String>{
    'de.spacing.repeated',
    'de.spacing.before-punctuation',
    'de.spacing.after-punctuation',
    'de.repetition.conjunction',
    'de.grammar.pronoun-verb',
    'de.grammar.seit-seid',
    ..._germanPhraseRuleIds,
    'de.delimiter.balance',
    'de.quote.balance',
  };
  static final RegExp _letterBefore = RegExp(r'[\p{L}\p{M}]$', unicode: true);
  static final RegExp _letterAfter = RegExp(r'^\p{L}', unicode: true);
  // Independently authored present-indicative forms. Do not infer forms for
  // unlisted verbs, subjunctives, or separated subject/verb constructions.
  static const List<_GermanPresentParadigm>
  _presentParadigms = <_GermanPresentParadigm>[
    _GermanPresentParadigm('sein', 'bin', 'bist', 'ist', 'sind', 'seid'),
    _GermanPresentParadigm('haben', 'habe', 'hast', 'hat', 'haben', 'habt'),
    _GermanPresentParadigm(
      'werden',
      'werde',
      'wirst',
      'wird',
      'werden',
      'werdet',
    ),
    _GermanPresentParadigm(
      'können',
      'kann',
      'kannst',
      'kann',
      'können',
      'könnt',
    ),
    _GermanPresentParadigm(
      'müssen',
      'muss',
      'musst',
      'muss',
      'müssen',
      'müsst',
    ),
    _GermanPresentParadigm(
      'dürfen',
      'darf',
      'darfst',
      'darf',
      'dürfen',
      'dürft',
    ),
    _GermanPresentParadigm(
      'sollen',
      'soll',
      'sollst',
      'soll',
      'sollen',
      'sollt',
    ),
    _GermanPresentParadigm(
      'wollen',
      'will',
      'willst',
      'will',
      'wollen',
      'wollt',
    ),
    _GermanPresentParadigm('mögen', 'mag', 'magst', 'mag', 'mögen', 'mögt'),
    _GermanPresentParadigm('gehen', 'gehe', 'gehst', 'geht', 'gehen', 'geht'),
    _GermanPresentParadigm(
      'kommen',
      'komme',
      'kommst',
      'kommt',
      'kommen',
      'kommt',
    ),
    _GermanPresentParadigm(
      'machen',
      'mache',
      'machst',
      'macht',
      'machen',
      'macht',
    ),
    _GermanPresentParadigm('sagen', 'sage', 'sagst', 'sagt', 'sagen', 'sagt'),
    _GermanPresentParadigm(
      'arbeiten',
      'arbeite',
      'arbeitest',
      'arbeitet',
      'arbeiten',
      'arbeitet',
    ),
    _GermanPresentParadigm(
      'lernen',
      'lerne',
      'lernst',
      'lernt',
      'lernen',
      'lernt',
    ),
    _GermanPresentParadigm(
      'brauchen',
      'brauche',
      'brauchst',
      'braucht',
      'brauchen',
      'braucht',
    ),
    _GermanPresentParadigm(
      'finden',
      'finde',
      'findest',
      'findet',
      'finden',
      'findet',
    ),
    _GermanPresentParadigm('geben', 'gebe', 'gibst', 'gibt', 'geben', 'gebt'),
    _GermanPresentParadigm(
      'nehmen',
      'nehme',
      'nimmst',
      'nimmt',
      'nehmen',
      'nehmt',
    ),
    _GermanPresentParadigm('sehen', 'sehe', 'siehst', 'sieht', 'sehen', 'seht'),
    _GermanPresentParadigm('lesen', 'lese', 'liest', 'liest', 'lesen', 'lest'),
    _GermanPresentParadigm(
      'sprechen',
      'spreche',
      'sprichst',
      'spricht',
      'sprechen',
      'sprecht',
    ),
    _GermanPresentParadigm(
      'fahren',
      'fahre',
      'fährst',
      'fährt',
      'fahren',
      'fahrt',
    ),
    _GermanPresentParadigm(
      'laufen',
      'laufe',
      'läufst',
      'läuft',
      'laufen',
      'lauft',
    ),
    _GermanPresentParadigm('essen', 'esse', 'isst', 'isst', 'essen', 'esst'),
    _GermanPresentParadigm(
      'bleiben',
      'bleibe',
      'bleibst',
      'bleibt',
      'bleiben',
      'bleibt',
    ),
    _GermanPresentParadigm(
      'stehen',
      'stehe',
      'stehst',
      'steht',
      'stehen',
      'steht',
    ),
    _GermanPresentParadigm(
      'sitzen',
      'sitze',
      'sitzt',
      'sitzt',
      'sitzen',
      'sitzt',
    ),
    _GermanPresentParadigm(
      'liegen',
      'liege',
      'liegst',
      'liegt',
      'liegen',
      'liegt',
    ),
    _GermanPresentParadigm(
      'heißen',
      'heiße',
      'heißt',
      'heißt',
      'heißen',
      'heißt',
    ),
    _GermanPresentParadigm(
      'wissen',
      'weiß',
      'weißt',
      'weiß',
      'wissen',
      'wisst',
    ),
    _GermanPresentParadigm(
      'denken',
      'denke',
      'denkst',
      'denkt',
      'denken',
      'denkt',
    ),
    _GermanPresentParadigm(
      'glauben',
      'glaube',
      'glaubst',
      'glaubt',
      'glauben',
      'glaubt',
    ),
    _GermanPresentParadigm(
      'hoffen',
      'hoffe',
      'hoffst',
      'hofft',
      'hoffen',
      'hofft',
    ),
    _GermanPresentParadigm(
      'kennen',
      'kenne',
      'kennst',
      'kennt',
      'kennen',
      'kennt',
    ),
    _GermanPresentParadigm(
      'verstehen',
      'verstehe',
      'verstehst',
      'versteht',
      'verstehen',
      'versteht',
    ),
    _GermanPresentParadigm(
      'bringen',
      'bringe',
      'bringst',
      'bringt',
      'bringen',
      'bringt',
    ),
    _GermanPresentParadigm(
      'kaufen',
      'kaufe',
      'kaufst',
      'kauft',
      'kaufen',
      'kauft',
    ),
    _GermanPresentParadigm(
      'schreiben',
      'schreibe',
      'schreibst',
      'schreibt',
      'schreiben',
      'schreibt',
    ),
    _GermanPresentParadigm('hören', 'höre', 'hörst', 'hört', 'hören', 'hört'),
    _GermanPresentParadigm(
      'helfen',
      'helfe',
      'hilfst',
      'hilft',
      'helfen',
      'helft',
    ),
    _GermanPresentParadigm(
      'fragen',
      'frage',
      'fragst',
      'fragt',
      'fragen',
      'fragt',
    ),
    _GermanPresentParadigm(
      'antworten',
      'antworte',
      'antwortest',
      'antwortet',
      'antworten',
      'antwortet',
    ),
    _GermanPresentParadigm(
      'warten',
      'warte',
      'wartest',
      'wartet',
      'warten',
      'wartet',
    ),
    _GermanPresentParadigm(
      'wohnen',
      'wohne',
      'wohnst',
      'wohnt',
      'wohnen',
      'wohnt',
    ),
    _GermanPresentParadigm('leben', 'lebe', 'lebst', 'lebt', 'leben', 'lebt'),
    _GermanPresentParadigm(
      'spielen',
      'spiele',
      'spielst',
      'spielt',
      'spielen',
      'spielt',
    ),
    _GermanPresentParadigm(
      'suchen',
      'suche',
      'suchst',
      'sucht',
      'suchen',
      'sucht',
    ),
    _GermanPresentParadigm(
      'zeigen',
      'zeige',
      'zeigst',
      'zeigt',
      'zeigen',
      'zeigt',
    ),
    _GermanPresentParadigm(
      'stellen',
      'stelle',
      'stellst',
      'stellt',
      'stellen',
      'stellt',
    ),
    _GermanPresentParadigm('legen', 'lege', 'legst', 'legt', 'legen', 'legt'),
    _GermanPresentParadigm(
      'halten',
      'halte',
      'hältst',
      'hält',
      'halten',
      'haltet',
    ),
    _GermanPresentParadigm(
      'tragen',
      'trage',
      'trägst',
      'trägt',
      'tragen',
      'tragt',
    ),
    _GermanPresentParadigm(
      'treffen',
      'treffe',
      'triffst',
      'trifft',
      'treffen',
      'trefft',
    ),
    _GermanPresentParadigm(
      'schlafen',
      'schlafe',
      'schläfst',
      'schläft',
      'schlafen',
      'schlaft',
    ),
    _GermanPresentParadigm(
      'vergessen',
      'vergesse',
      'vergisst',
      'vergisst',
      'vergessen',
      'vergesst',
    ),
    _GermanPresentParadigm(
      'trinken',
      'trinke',
      'trinkst',
      'trinkt',
      'trinken',
      'trinkt',
    ),
  ];
  static final Map<String, _GermanPresentParadigm> _presentByForm =
      <String, _GermanPresentParadigm>{
        for (final _GermanPresentParadigm paradigm in _presentParadigms)
          for (final String form in paradigm.forms) form: paradigm,
      };
  static final RegExp _pronounVerb = RegExp(
    '(?<!$_wordEdge)(ich|du|er|man|wir|ihr)$_horizontalSpace('
    '${_presentByForm.keys.map(RegExp.escape).join('|')})(?!$_wordEdge)',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _comparisonPrefix = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])(?:wie|als|außer)[ \t\u00a0\u202f]+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _coordinationPrefix = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])(?:(und|oder|noch|sowie)(?:[ \t\u00a0\u202f]+auch)?|(?:sondern|als|wie)[ \t\u00a0\u202f]+auch)[ \t\u00a0\u202f]+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _nominalPronounPrefix = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])(?:das|dem|des|der|die|den|dessen|deren|dies|'
    r'(?:ein|mein|dein|sein|unser|euer|eur|ihr|kein)(?:e[rmns]?|n)?|'
    r'(?:dies|jen|jed|welch)e[rmns]?|'
    r'am|beim|im|ins|vom|zum|ans|aufs|durchs|fürs|ums|übers|unters|vors|'
    r'hinters|hinterm|überm|unterm|vorm)'
    r'(?:[ \t\u00a0\u202f]+[\p{L}\p{M}]+){0,3}[ \t\u00a0\u202f]+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _dativePrefix = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])(?:aus|bei|mit|nach|seit|von|zu|außer|gegenüber|dank|wegen|trotz|vor|hinter|unter|über|neben|zwischen|an|auf|in)(?:[ \t\u00a0\u202f]+(?:nur|gerade|auch|selbst|allein))*[ \t\u00a0\u202f]+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _followingSubject = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])(?:ich|du|er|sie|es|wir|man|jemand|niemand|der|die|das|ein|eine|alle|beide|jeder|jede|jedes|viele|wenige)(?![\p{L}\p{M}\p{N}_])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _followingNoun = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])\p{Lu}[\p{L}\p{M}]*(?![\p{L}\p{M}\p{N}_])',
    unicode: true,
  );
  static final RegExp _clauseEnd = RegExp(r'[.!?;:\r\n]');
  static const Set<String> _nominalFiniteForms = <String>{
    'macht',
    'habe',
    'hast',
    'sage',
    'ist',
    'soll',
    'sitze',
    'liege',
    'glaube',
    'frage',
    'suche',
    'stelle',
    'warte',
    'trage',
    'halte',
  };
  static final RegExp _subordinatePrefix = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])(?:weil|wenn|dass|ob|obwohl|falls|damit|'
    r'bevor|nachdem|sobald|solange|während|seitdem|indem|bis)'
    r'[ \t\u00a0\u202f]+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _followingWord = RegExp(
    r'^[ \t\u00a0\u202f]+\p{L}',
    unicode: true,
  );
  static final RegExp _precedingFiniteWord = RegExp(
    '(?<!$_wordEdge)([\\p{L}\\p{M}]+)$_horizontalSpace\$',
    unicode: true,
  );
  static final RegExp _lastClauseWord = RegExp(
    r'([\p{L}\p{M}]+)[^\p{L}\p{M}\p{N}]*$',
    unicode: true,
  );
  static final RegExp _anotherNominative = RegExp(
    '(?<!$_wordEdge)(?:ich|du|er|wir|man)(?!$_wordEdge)',
    caseSensitive: false,
    unicode: true,
  );
  static final Set<String> _infinitiveGovernors = <String>{
    for (final _GermanPresentParadigm paradigm in _presentParadigms)
      if (const <String>{
        'können',
        'müssen',
        'dürfen',
        'sollen',
        'wollen',
        'mögen',
        'werden',
        'gehen',
        'bleiben',
        'helfen',
        'lernen',
        'sehen',
        'hören',
      }.contains(paradigm.infinitive))
        ...paradigm.forms,
    'möchte',
    'möchtest',
    'möchten',
    'möchtet',
    'könne',
    'könnest',
    'könnet',
    'konnte',
    'konntest',
    'konnten',
    'konntet',
    'könnte',
    'könntest',
    'könnten',
    'könntet',
    'müsse',
    'müssest',
    'müsset',
    'musste',
    'musstest',
    'mussten',
    'musstet',
    'müsste',
    'müsstest',
    'müssten',
    'müsstet',
    'dürfe',
    'dürfest',
    'dürfet',
    'durfte',
    'durftest',
    'durften',
    'durftet',
    'dürfte',
    'dürftest',
    'dürften',
    'dürftet',
    'solle',
    'sollest',
    'sollet',
    'sollte',
    'solltest',
    'sollten',
    'solltet',
    'wolle',
    'wollest',
    'wollet',
    'wollte',
    'wolltest',
    'wollten',
    'wolltet',
    'würde',
    'würdest',
    'würden',
    'würdet',
    'lasse',
    'lässt',
    'lasst',
    'lassen',
    'ließ',
    'ließen',
  };

  // "seit" and "seid" are both dictionary words. Recognize only contexts
  // that identify their role without a sentence parser. In particular, never
  // treat "ihr seid gestern gekommen" or "seid drei Wochen geduldig" as a
  // preposition error merely because a time expression follows "seid".
  static const String _horizontalSpace = r'[ \t\u00a0\u202f]+';
  static const String _wordEdge =
      r"[\p{L}\p{M}\p{N}_'’@\u2010\u2011\u200c\u200d\u2060\ufeff-]";
  static final RegExp _predicateSeit = RegExp(
    '(?<!$_wordEdge)(ihr)$_horizontalSpace(seit)$_horizontalSpace'
    '(?:(?:nicht|wirklich|sehr|so|ganz)$_horizontalSpace){0,2}'
    '(?:hier|dort|da|bereit|fertig|willkommen|pünktlich|freundlich|nett|müde)'
    '(?!$_wordEdge)',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _temporalSeid = RegExp(
    '(?<!$_wordEdge)'
    '(bin|bist|ist|sind|war|waren|habe|hat|haben|warte|wartet|warten|'
    'lebe|lebt|leben|wohne|wohnt|wohnen|arbeite|arbeitet|arbeiten)'
    '$_horizontalSpace(seid)$_horizontalSpace'
    '(?:gestern|vorgestern|damals|jeher|langem|kurzem|längerem|'
    '(?:einem|diesem|jenem)$_horizontalSpace(?:Tag|Monat|Jahr)|'
    '(?:einer|dieser|jener)$_horizontalSpace(?:Woche|Stunde|Minute|Sekunde)|'
    '(?:[0-9]+|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn|'
    'vielen|einigen|mehreren)$_horizontalSpace'
    '(?:Tagen|Monaten|Jahren|Wochen|Stunden|Minuten|Sekunden))'
    '(?!$_wordEdge)',
    caseSensitive: false,
    unicode: true,
  );

  static bool _ambiguousAgreementContext(
    String text,
    RegExpMatch match,
    String subject,
    String verb,
  ) {
    final String prefix = text.substring(
      match.start > 96 ? match.start - 96 : 0,
      match.start,
    );
    final RegExpMatch? precedingVerb = _precedingFiniteWord.firstMatch(prefix);
    if (precedingVerb != null &&
        (_presentByForm.containsKey(precedingVerb.group(1)!.toLowerCase()) ||
            _infinitiveGovernors.contains(
              precedingVerb.group(1)!.toLowerCase(),
            ))) {
      // Inversion already supplies the finite verb: "Kann ich gehen?",
      // "Will er lesen?". The following infinitive does not agree with the
      // pronoun. Do not issue a second, contradictory correction there.
      return true;
    }
    final _GermanPresentParadigm? paradigm = _presentByForm[verb];
    if (paradigm != null && _germanFormsEquivalent(verb, paradigm.infinitive)) {
      final int end = match.end + 180 < text.length
          ? match.end + 180
          : text.length;
      final String following = text.substring(match.end, end);
      final RegExpMatch? stop = _grammarClauseEnd.firstMatch(following);
      final String clause = stop == null
          ? following
          : following.substring(0, stop.start);
      final RegExpMatch? last = _lastClauseWord.firstMatch(clause);
      final String? lastWord = last?.group(1)?.toLowerCase();
      final _GermanPresentParadigm? governor = _presentByForm[lastWord];
      final bool finiteGovernor =
          governor == null ||
          _germanFormsEquivalent(lastWord!, governor.forSubject(subject)) ||
          const <String>{'er', 'man'}.contains(subject) &&
              governor.isThirdPersonSubjunctive(lastWord);
      if (last != null &&
          finiteGovernor &&
          _infinitiveGovernors.contains(lastWord) &&
          !_anotherNominative.hasMatch(clause)) {
        // A subordinate clause can put its finite governor after the
        // infinitive: "weil ich helfen kann", "ob er arbeiten wird".
        return true;
      }
      if (_subordinatePrefix.hasMatch(prefix) &&
          stop == null &&
          end < text.length) {
        // A bounded lookahead cannot rule out a later finite governor.
        return true;
      }
    }
    final String originalVerb = match.group(2)!;
    // All-capital text loses the noun/verb capitalization cue. In a directly
    // introduced subordinate clause, a reviewed noun homograph can instead be
    // an object before another verb: "WEIL ICH MACHT HABE". Abstain for only
    // these listed homographs without pretending to parse the whole clause.
    // Other uppercase finite forms and main-clause corrections stay enabled.
    if (originalVerb != originalVerb.toLowerCase() &&
        originalVerb == originalVerb.toUpperCase() &&
        originalVerb.toLowerCase() == verb &&
        _nominalFiniteForms.contains(verb) &&
        _subordinatePrefix.hasMatch(prefix) &&
        _followingWord.hasMatch(
          text.substring(
            match.end,
            match.end + 32 < text.length ? match.end + 32 : text.length,
          ),
        )) {
      return true;
    }
    // "wie du haben wir" and "du und ich sind" do not assign the verb
    // exclusively to the last pronoun. A preceding comma can also close a
    // relative clause: "Mein Bruder, den du kennst, und ich haben Zeit".
    // Keep plausible plural forms untouched even after that comma.
    if (_comparisonPrefix.hasMatch(prefix)) return true;
    final RegExpMatch? coordination = _coordinationPrefix.firstMatch(prefix);
    if (coordination != null &&
        (coordination.group(1) == null ||
            !prefix
                .substring(0, coordination.start)
                .trimRight()
                .endsWith(',') ||
            paradigm != null &&
                (_germanFormsEquivalent(verb, paradigm.wir) ||
                    _germanFormsEquivalent(verb, paradigm.ihr)))) {
      return true;
    }
    final String originalSubject = match.group(1)!;
    if (originalSubject != subject &&
        (_nominalPronounPrefix.hasMatch(prefix) ||
            subject == 'man' &&
                (_dativePrefix.hasMatch(prefix) ||
                    precedingVerb != null &&
                        _governedCases.containsKey(
                          precedingVerb.group(1)!.toLowerCase(),
                        )) ||
            verb == 'ist' && const <String>{'ich', 'du'}.contains(subject))) {
      return true;
    }
    if (subject != 'ihr') return false;
    // "ihr" also denotes a dative object. "Ihr ist kalt" is valid without an
    // explicit subject; "Ihr bin ich dankbar" and "Mit ihr sind wir ..." are
    // also valid. Preserve narrow existing sein checks only outside those
    // ambiguous contexts; do not expand ihr to the additional verb families.
    if (verb == 'ist' || _dativePrefix.hasMatch(prefix)) return true;
    final int end = match.end + 160 < text.length
        ? match.end + 160
        : text.length;
    final String following = text.substring(match.end, end);
    final RegExpMatch? stop = _clauseEnd.firstMatch(following);
    final String clause = stop == null
        ? following
        : following.substring(0, stop.start);
    return _followingSubject.hasMatch(clause) ||
        _followingNoun.hasMatch(clause);
  }

  static bool _hasLetterBefore(String text, int offset) =>
      offset > 0 &&
      _letterBefore.hasMatch(
        text.substring(offset > 1 ? offset - 2 : 0, offset),
      );

  static bool _hasLetterAfter(String text, int offset) =>
      offset + 1 < text.length &&
      _letterAfter.hasMatch(
        text.substring(
          offset + 1,
          offset + 3 < text.length ? offset + 3 : text.length,
        ),
      );

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    if (_disposed || !supportsLanguage(request.language)) {
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: _disposed
            ? OfficeProofingStatus.unavailable
            : OfficeProofingStatus.unsupported,
        message: _disposed
            ? 'German writing provider is disposed.'
            : 'German writing checks support de-DE, de-AT and de-CH.',
      );
    }
    final _GermanWritingText projection = _GermanWritingText(request.text);
    final String text = projection.text;
    final OfficeProofingTextRanges protected = OfficeProofingTextRanges(text);
    final literals = GermanLiteralTextRanges(text);
    bool isProtected(int start, int end) =>
        protected.overlaps(start, end) || literals.overlaps(start, end);
    final Set<int> boundaries = projection.boundaries;
    await GermanNounMorphology.shared.prepareWords(
      _grammarMorphologyCandidates(text, isProtected, boundaries),
    );
    if (_disposed) {
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.unavailable,
        message: 'German writing provider is disposed.',
      );
    }
    final List<OfficeProofingFinding> findings = <OfficeProofingFinding>[];

    void add(
      String ruleId,
      int start,
      int end,
      String message, {
      OfficeProofingCategory category = OfficeProofingCategory.style,
      List<String> replacements = const <String>[],
    }) {
      if (!boundaries.contains(start) ||
          !boundaries.contains(end) ||
          request.ignoredRuleIds.contains(ruleId) ||
          isProtected(start, end)) {
        return;
      }
      final ({int start, int end})? source = projection.sourceRange(start, end);
      if (source == null) return;
      findings.add(
        OfficeProofingFinding.forRequest(
          request,
          providerId: id,
          start: source.start,
          end: source.end,
          ruleId: ruleId,
          message: message,
          category: category,
          replacements: request.language == 'de-CH'
              ? <String>[
                  for (final String replacement in replacements)
                    replacement.replaceAll('ß', 'ss').replaceAll('ẞ', 'SS'),
                ]
              : replacements,
        ),
      );
    }

    for (final RegExpMatch m in RegExp(
      r'(?<=\S) {2,}(?=\S)',
    ).allMatches(text)) {
      if (RegExp(r'\d').hasMatch(text[m.start - 1]) &&
          RegExp(r'\d').hasMatch(text[m.end])) {
        continue;
      }
      add(
        'de.spacing.repeated',
        m.start,
        m.end,
        'Mehrere Leerzeichen zwischen Wörtern prüfen.',
        replacements: <String>[' '],
      );
    }
    for (final RegExpMatch m in RegExp(r' +(?=[,;:!?])').allMatches(text)) {
      add(
        'de.spacing.before-punctuation',
        m.start,
        m.end,
        'Vor diesem Satzzeichen steht normalerweise kein Leerzeichen.',
        replacements: <String>[''],
      );
    }
    for (final RegExpMatch m in RegExp(
      r'[,;](?=\p{L})',
      unicode: true,
    ).allMatches(text)) {
      add(
        'de.spacing.after-punctuation',
        m.end,
        m.end,
        'Nach diesem Satzzeichen ein Leerzeichen prüfen.',
        replacements: <String>[' '],
      );
    }
    for (final RegExpMatch m in RegExp(
      r'(?<![\p{L}\p{M}])(und|oder|aber) +(\1)(?![\p{L}\p{M}])',
      caseSensitive: false,
      unicode: true,
    ).allMatches(text)) {
      add(
        'de.repetition.conjunction',
        m.start,
        m.end,
        'Die unmittelbare Wiederholung dieser Konjunktion prüfen.',
        replacements: <String>[m.group(1)!],
      );
    }
    for (final RegExpMatch match in _pronounVerb.allMatches(text)) {
      // Both the subject and verb must belong to prose, including their source
      // graphemes. Protected text cannot govern an unrelated following verb.
      if (isProtected(match.start, match.end) ||
          !boundaries.contains(match.start)) {
        continue;
      }
      final String subject = match.group(1)!.toLowerCase();
      final String verb = match.group(2)!;
      final String lowerVerb = verb.toLowerCase();
      final _GermanPresentParadigm? paradigm = _presentByForm[lowerVerb];
      // Unicode case folding can match a form whose lowercase text is not
      // a listed spelling (for example long-s). Leave it to spelling checks.
      if (paradigm == null ||
          subject == 'ihr' && paradigm.infinitive != 'sein') {
        continue;
      }
      // A capitalized homograph may be an object, not the finite verb:
      // "weil ich Essen bestelle", "wenn du Habe besitzt", "ich Macht habe".
      // Let spelling handle unusual verb capitalization. All-capital finite
      // forms retain their established behavior; capitalized infinitives are
      // also ambiguous in all-capital text, so leave those untouched.
      if (verb != lowerVerb &&
          (verb != verb.toUpperCase() ||
              _germanFormsEquivalent(lowerVerb, paradigm.infinitive))) {
        continue;
      }
      final String replacement = paradigm.forSubject(subject);
      if (_germanFormsEquivalent(replacement, lowerVerb) ||
          const <String>{'er', 'man'}.contains(subject) &&
              paradigm.isThirdPersonSubjunctive(lowerVerb) ||
          _ambiguousAgreementContext(text, match, subject, lowerVerb)) {
        continue;
      }
      add(
        'de.grammar.pronoun-verb',
        match.end - verb.length,
        match.end,
        'Diese Form von „${paradigm.infinitive}“ passt normalerweise nicht zum unmittelbar vorangehenden Pronomen.',
        category: OfficeProofingCategory.grammar,
        replacements: <String>[
          verb == verb.toUpperCase() ? replacement.toUpperCase() : replacement,
        ],
      );
    }
    for (final RegExpMatch match in _predicateSeit.allMatches(text)) {
      if (isProtected(match.start, match.end) ||
          !boundaries.contains(match.start) ||
          _ambiguousAgreementContext(text, match, 'ihr', 'seid')) {
        continue;
      }
      final String original = match.group(2)!;
      final int start =
          match.start +
          match.group(0)!.indexOf(original, match.group(1)!.length);
      add(
        'de.grammar.seit-seid',
        start,
        start + original.length,
        'Zur Anrede „ihr“ passt hier normalerweise die Verbform „seid“.',
        category: OfficeProofingCategory.grammar,
        replacements: <String>[_matchCase(original, 'seid')],
      );
    }
    for (final RegExpMatch match in _temporalSeid.allMatches(text)) {
      if (isProtected(match.start, match.end) ||
          !boundaries.contains(match.start)) {
        continue;
      }
      final String original = match.group(2)!;
      final int start =
          match.start +
          match.group(0)!.indexOf(original, match.group(1)!.length);
      add(
        'de.grammar.seit-seid',
        start,
        start + original.length,
        'Für den Beginn oder die Dauer ist hier normalerweise „seit“ gemeint.',
        category: OfficeProofingCategory.grammar,
        replacements: <String>[_matchCase(original, 'seit')],
      );
    }
    for (final _GermanGrammarIssue issue in _germanGrammarIssues(
      text,
      isProtected,
      boundaries,
      request.language == 'de-CH',
    )) {
      add(
        issue.ruleId,
        issue.start,
        issue.end,
        issue.message,
        category: OfficeProofingCategory.grammar,
        replacements: <String>[issue.replacement, ...issue.alternatives],
      );
    }
    final List<(String, int)> delimiters = <(String, int)>[];
    final List<(String, int)> quotes = <(String, int)>[];
    const Map<String, String> bracketPairs = <String, String>{
      '(': ')',
      '[': ']',
      '{': '}',
    };
    const Map<String, String> quotePairs = <String, String>{
      '„': '“',
      '‚': '‘',
      '“': '”',
      '‘': '’',
      '«': '»',
      '»': '«',
    };
    for (int i = 0; i < text.length; i++) {
      if (i % 2048 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (_disposed) {
          return OfficeProofingResult(
            request: request,
            providerId: id,
            status: OfficeProofingStatus.unavailable,
            message: 'German writing provider is disposed.',
          );
        }
      }
      if (isProtected(i, i + 1)) continue;
      final String char = text[i];
      if (bracketPairs.containsKey(char)) {
        delimiters.add((bracketPairs[char]!, i));
      } else if (bracketPairs.containsValue(char)) {
        if (delimiters.isNotEmpty && delimiters.last.$1 == char) {
          delimiters.removeLast();
        } else {
          add(
            'de.delimiter.balance',
            i,
            i + 1,
            'Zu dieser schließenden Klammer fehlt im Absatz eine passende öffnende Klammer.',
          );
        }
      }
      // An apostrophe inside a name or contraction must not consume the
      // enclosing English single quote: ‘O’Connor’ and ‘geht’s’ are balanced.
      // Inspect whole neighboring scalars, including supplementary letters
      // and decomposed accents, while leaving all source offsets unchanged.
      if (char == '’' &&
          _hasLetterBefore(text, i) &&
          _hasLetterAfter(text, i)) {
        continue;
      }
      if (quotes.isNotEmpty && quotes.last.$1 == char) {
        quotes.removeLast();
      } else if (quotePairs.containsKey(char)) {
        quotes.add((quotePairs[char]!, i));
      } else if (char == '”' || char == '’') {
        final bool apostrophe = char == '’' && _hasLetterBefore(text, i);
        if (!apostrophe) {
          add(
            'de.quote.balance',
            i,
            i + 1,
            'Zu diesem Anführungszeichen fehlt im Absatz ein passendes öffnendes Zeichen.',
          );
        }
      }
    }
    for (final (String, int) entry in delimiters) {
      add(
        'de.delimiter.balance',
        entry.$2,
        entry.$2 + 1,
        'Zu dieser Klammer fehlt im Absatz „${entry.$1}“. Absatzübergreifende Inhalte bitte manuell prüfen.',
      );
    }
    for (final (String, int) entry in quotes) {
      add(
        'de.quote.balance',
        entry.$2,
        entry.$2 + 1,
        'Zu diesem Anführungszeichen fehlt im Absatz „${entry.$1}“. Mehrabsätzige Zitate bitte manuell prüfen.',
      );
    }
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: findings,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}

String _matchCase(String source, String replacement) =>
    source == source.toUpperCase()
    ? replacement.toUpperCase()
    : source[0] == source[0].toUpperCase()
    ? '${replacement[0].toUpperCase()}${replacement.substring(1)}'
    : replacement;

// Grammar compares inflection independently of regional sharp-s spelling.
// Spelling still diagnoses ss/ß orthography where appropriate; grammar must
// not reject a correctly inflected Swiss form or duplicate that finding.
bool _germanFormsEquivalent(String a, String b) =>
    normalizeGermanWord(a).replaceAll('ß', 'ss') ==
    normalizeGermanWord(b).replaceAll('ß', 'ss');

/// Discretionary hyphens belong to layout, not grammar. The projection removes
/// them only from checker text and maps every result back to the untouched
/// UTF-16 source. Controls inside a replacement belong to that replacement;
/// adjacent controls remain outside. Both representations require whole
/// graphemes, including when omitting a control rejoins an accented letter.
final class _GermanWritingText {
  _GermanWritingText(String source) : _sourceLength = source.length {
    _sourceBoundaries = _sourceGraphemeBoundaries(source);
    if (!source.contains('\u00ad')) {
      text = source;
      boundaries = _sourceBoundaries;
      return;
    }
    final List<int> units = <int>[];
    final List<int> sourceOffsets = <int>[];
    for (int i = 0; i < source.length; i++) {
      final int unit = source.codeUnitAt(i);
      if (unit != 0x00ad) {
        units.add(unit);
        sourceOffsets.add(i);
      }
    }
    _sourceOffsets = sourceOffsets;
    text = String.fromCharCodes(units);
    boundaries = _sourceGraphemeBoundaries(text);
  }

  final int _sourceLength;
  late final String text;
  late final Set<int> boundaries;
  late final Set<int> _sourceBoundaries;
  List<int>? _sourceOffsets;

  ({int start, int end})? sourceRange(int start, int end) {
    if (!boundaries.contains(start) || !boundaries.contains(end)) return null;
    final List<int>? offsets = _sourceOffsets;
    if (offsets == null) return (start: start, end: end);
    final int sourceStart = start == offsets.length
        ? _sourceLength
        : offsets[start];
    final int sourceEnd = start == end ? sourceStart : offsets[end - 1] + 1;
    if (!_sourceBoundaries.contains(sourceStart) ||
        !_sourceBoundaries.contains(sourceEnd)) {
      return null;
    }
    return (start: sourceStart, end: sourceEnd);
  }
}

/// A finite, reviewed indicative paradigm; this is not a morphology engine.
class _GermanPresentParadigm {
  const _GermanPresentParadigm(
    this.infinitive,
    this.ich,
    this.du,
    this.thirdPerson,
    this.wir,
    this.ihr,
  );

  final String infinitive;
  final String ich;
  final String du;
  final String thirdPerson;
  final String wir;
  final String ihr;

  Set<String> get forms => <String>{
    for (final String form in <String>[
      ich,
      du,
      thirdPerson,
      wir,
      ihr,
    ]) ...<String>[form, form.replaceAll('ß', 'ss')],
  };

  // First-person -e forms are also common third-person Konjunktiv I forms:
  // "er habe", "man nehme", "er werde". A local agreement rule cannot
  // determine the intended mood and must preserve those homographs.
  bool isThirdPersonSubjunctive(String form) =>
      _germanFormsEquivalent(form, ich) && form.endsWith('e');

  String forSubject(String subject) => switch (subject) {
    'ich' => ich,
    'du' => du,
    'wir' => wir,
    'ihr' => ihr,
    'er' || 'man' => thirdPerson,
    _ => throw ArgumentError.value(subject, 'subject'),
  };
}

/// Host-authored literal terminology policy, with language and boundary controls.
class OfficeTerminologyRule {
  OfficeTerminologyRule({
    required this.id,
    required this.term,
    required this.message,
    required List<String> replacements,
    this.caseSensitive = false,
    this.wholeWord = true,
    Set<String> languages = const <String>{},
  }) : replacements = List<String>.unmodifiable(replacements),
       languages = Set<String>.unmodifiable(
         languages.map(normalizeProofingLanguage),
       ) {
    if (id.trim().isEmpty || term.isEmpty) {
      throw ArgumentError(
        'A terminology rule needs an id and a nonempty literal term.',
      );
    }
  }
  final String id;
  final String term;
  final String message;
  final List<String> replacements;
  final bool caseSensitive;
  final bool wholeWord;

  /// Empty means every explicitly selected document language.
  final Set<String> languages;
}

class OfficeTerminologyProvider extends OfficeProofingProvider {
  OfficeTerminologyProvider({required List<OfficeTerminologyRule> rules})
    : rules = List<OfficeTerminologyRule>.unmodifiable(rules) {
    final Set<String> ids = <String>{};
    for (final OfficeTerminologyRule rule in rules) {
      if (!ids.add(rule.id)) {
        throw ArgumentError('Duplicate terminology rule id: ${rule.id}');
      }
    }
  }
  final List<OfficeTerminologyRule> rules;
  bool _disposed = false;
  @override
  String get id => 'terminology';
  @override
  bool supportsLanguage(String language) => rules.any(
    (OfficeTerminologyRule rule) =>
        rule.languages.isEmpty ||
        rule.languages.contains(normalizeProofingLanguage(language)),
  );
  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    if (_disposed || rules.isEmpty || !supportsLanguage(request.language)) {
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: _disposed || rules.isEmpty
            ? OfficeProofingStatus.unavailable
            : OfficeProofingStatus.unsupported,
        message: _disposed
            ? 'Terminology provider is disposed.'
            : 'No terminology rules apply.',
      );
    }
    final List<OfficeProofingFinding> findings = <OfficeProofingFinding>[];
    final Set<int> boundaries = _sourceGraphemeBoundaries(request.text);
    for (final OfficeTerminologyRule rule in rules) {
      await Future<void>.delayed(Duration.zero);
      if (_disposed) {
        return OfficeProofingResult(
          request: request,
          providerId: id,
          status: OfficeProofingStatus.unavailable,
          message: 'Terminology provider is disposed.',
        );
      }
      if (request.ignoredRuleIds.contains(rule.id) ||
          rule.languages.isNotEmpty &&
              !rule.languages.contains(request.language)) {
        continue;
      }
      final String term = RegExp.escape(rule.term);
      final RegExp expression = RegExp(
        rule.wholeWord
            ? '(?<![\\p{L}\\p{M}\\p{N}_])$term(?![\\p{L}\\p{M}\\p{N}_])'
            : term,
        caseSensitive: rule.caseSensitive,
        unicode: true,
      );
      for (final RegExpMatch m in expression.allMatches(request.text)) {
        // Literal substring rules still may not replace part of a visible
        // character (for example Cafe within decomposed Café).
        if (!boundaries.contains(m.start) || !boundaries.contains(m.end)) {
          continue;
        }
        findings.add(
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            start: m.start,
            end: m.end,
            ruleId: rule.id,
            message: rule.message,
            category: OfficeProofingCategory.style,
            replacements: rule.replacements,
          ),
        );
      }
    }
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: findings,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
