part of 'german_writing_rules.dart';

// Independently authored, bounded phrase analysis. These are ordinary language
// facts and first-party examples, not imported grammar rules or a statistical
// parser. Noun analyses use the separately licensed Unicode morphology data.
// Unknown words and competing analyses cause abstention.
const Set<String> _germanPhraseRuleIds = <String>{
  'de.grammar.preposition-pronoun',
  'de.grammar.preposition-case',
  'de.grammar.verb-object-case',
  'de.grammar.dative-plural',
  'de.grammar.noun-case',
  'de.grammar.adjective-ending',
  'de.grammar.phrase-agreement',
  'de.grammar.das-dass',
  'de.grammar.subordinate-comma',
  'de.grammar.comparison',
  'de.grammar.noun-verb',
  'de.grammar.verb-case',
  'de.grammar.genitive-attribute',
  'de.grammar.copula-agreement',
  'de.grammar.word-order',
  'de.grammar.participle',
};

final class _GermanGrammarIssue {
  const _GermanGrammarIssue(
    this.ruleId,
    this.start,
    this.end,
    this.replacement,
    this.message, {
    this.alternatives = const [],
  });

  final String ruleId;
  final int start;
  final int end;
  final String replacement;
  final String message;
  final List<String> alternatives;
}

final class _GermanGrammarWord {
  _GermanGrammarWord(RegExpMatch match)
    : text = match.group(0)!,
      lower = match.group(0)!.toLowerCase(),
      start = match.start,
      end = match.end;

  final String text;
  final String lower;
  final int start;
  final int end;

  bool get capitalized => text != lower;
}

enum _GermanCase { nominative, accusative, dative, genitive }

enum _GermanGender { masculine, feminine, neuter, plural }

const Map<String, _GermanCase> _governedCases = <String, _GermanCase>{
  'aus': _GermanCase.dative,
  'bei': _GermanCase.dative,
  'mit': _GermanCase.dative,
  'nach': _GermanCase.dative,
  'seit': _GermanCase.dative,
  'von': _GermanCase.dative,
  'zu': _GermanCase.dative,
  'gegenüber': _GermanCase.dative,
  'durch': _GermanCase.accusative,
  'für': _GermanCase.accusative,
  'gegen': _GermanCase.accusative,
  'ohne': _GermanCase.accusative,
  'um': _GermanCase.accusative,
};

// Deliberately omit variable cases (wegen, trotz, dank, außer), two-way
// prepositions, and bis/entlang. Only an actual noun phrase is analyzed.
final RegExp _grammarWordExpression = RegExp(
  '(?<!${GermanWritingRulesProvider._wordEdge})[\\p{L}\\p{M}]+'
  '(?!${GermanWritingRulesProvider._wordEdge})',
  unicode: true,
);
final RegExp _grammarHorizontal = RegExp(r'^[ \t\u00a0\u202f]+$');
final RegExp _grammarComma = RegExp(r'^[ \t\u00a0\u202f]*,[ \t\u00a0\u202f]+$');
final RegExp _grammarClauseEnd = RegExp(r'[.!?;:\r\n,]');

bool _grammarAdjacent(
  String text,
  _GermanGrammarWord a,
  _GermanGrammarWord b,
) => _grammarHorizontal.hasMatch(text.substring(a.end, b.start));

bool _grammarContextSafe(
  int start,
  int end,
  bool Function(int, int) protected,
  Set<int> boundaries,
) =>
    boundaries.contains(start) &&
    boundaries.contains(end) &&
    !protected(start, end);

// Reviewed first-party fallback for words absent from the external resource.
// The licensed morphology lookup is preferred, including competing genders and
// all recorded case alternatives; this small table never overrides them.
final class _GermanNoun {
  const _GermanNoun(this.singular, this.gender, this.plural);
  final String singular;
  final _GermanGender gender;
  final String plural;

  String get dativePlural =>
      plural.endsWith('n') || plural.endsWith('s') ? plural : '${plural}n';
}

const List<_GermanNoun> _grammarNouns = <_GermanNoun>[
  _GermanNoun('Mann', _GermanGender.masculine, 'Männer'),
  _GermanNoun('Frau', _GermanGender.feminine, 'Frauen'),
  _GermanNoun('Kind', _GermanGender.neuter, 'Kinder'),
  _GermanNoun('Haus', _GermanGender.neuter, 'Häuser'),
  _GermanNoun('Buch', _GermanGender.neuter, 'Bücher'),
  _GermanNoun('Auto', _GermanGender.neuter, 'Autos'),
  _GermanNoun('Tag', _GermanGender.masculine, 'Tage'),
  _GermanNoun('Woche', _GermanGender.feminine, 'Wochen'),
  _GermanNoun('Monat', _GermanGender.masculine, 'Monate'),
  _GermanNoun('Jahr', _GermanGender.neuter, 'Jahre'),
  _GermanNoun('Stunde', _GermanGender.feminine, 'Stunden'),
  _GermanNoun('Minute', _GermanGender.feminine, 'Minuten'),
  _GermanNoun('Sekunde', _GermanGender.feminine, 'Sekunden'),
  _GermanNoun('Satz', _GermanGender.masculine, 'Sätze'),
  _GermanNoun('Text', _GermanGender.masculine, 'Texte'),
  _GermanNoun('Brief', _GermanGender.masculine, 'Briefe'),
  _GermanNoun('Tisch', _GermanGender.masculine, 'Tische'),
  _GermanNoun('Stuhl', _GermanGender.masculine, 'Stühle'),
  _GermanNoun('Hund', _GermanGender.masculine, 'Hunde'),
  _GermanNoun('Katze', _GermanGender.feminine, 'Katzen'),
  _GermanNoun('Stadt', _GermanGender.feminine, 'Städte'),
  _GermanNoun('Straße', _GermanGender.feminine, 'Straßen'),
  _GermanNoun('Schule', _GermanGender.feminine, 'Schulen'),
  _GermanNoun('Aufgabe', _GermanGender.feminine, 'Aufgaben'),
  _GermanNoun('Frage', _GermanGender.feminine, 'Fragen'),
  _GermanNoun('Antwort', _GermanGender.feminine, 'Antworten'),
  _GermanNoun('Problem', _GermanGender.neuter, 'Probleme'),
  _GermanNoun('Lösung', _GermanGender.feminine, 'Lösungen'),
  _GermanNoun('Datei', _GermanGender.feminine, 'Dateien'),
  _GermanNoun('Ordner', _GermanGender.masculine, 'Ordner'),
  _GermanNoun('Bericht', _GermanGender.masculine, 'Berichte'),
  _GermanNoun('Vertrag', _GermanGender.masculine, 'Verträge'),
  _GermanNoun('Projekt', _GermanGender.neuter, 'Projekte'),
  _GermanNoun('Termin', _GermanGender.masculine, 'Termine'),
  _GermanNoun('Rechnung', _GermanGender.feminine, 'Rechnungen'),
  _GermanNoun('Nachricht', _GermanGender.feminine, 'Nachrichten'),
  _GermanNoun('Dokument', _GermanGender.neuter, 'Dokumente'),
  _GermanNoun('Beispiel', _GermanGender.neuter, 'Beispiele'),
  _GermanNoun('Fehler', _GermanGender.masculine, 'Fehler'),
  _GermanNoun('Bild', _GermanGender.neuter, 'Bilder'),
  _GermanNoun('Fenster', _GermanGender.neuter, 'Fenster'),
  _GermanNoun('Tür', _GermanGender.feminine, 'Türen'),
  _GermanNoun('Zimmer', _GermanGender.neuter, 'Zimmer'),
  _GermanNoun('Raum', _GermanGender.masculine, 'Räume'),
  _GermanNoun('Plan', _GermanGender.masculine, 'Pläne'),
  _GermanNoun('Zahl', _GermanGender.feminine, 'Zahlen'),
  _GermanNoun('Seite', _GermanGender.feminine, 'Seiten'),
  _GermanNoun('Zeile', _GermanGender.feminine, 'Zeilen'),
  _GermanNoun('Spalte', _GermanGender.feminine, 'Spalten'),
  _GermanNoun('Tabelle', _GermanGender.feminine, 'Tabellen'),
  _GermanNoun('Absatz', _GermanGender.masculine, 'Absätze'),
  _GermanNoun('Kapitel', _GermanGender.neuter, 'Kapitel'),
  _GermanNoun('Weg', _GermanGender.masculine, 'Wege'),
  _GermanNoun('Ziel', _GermanGender.neuter, 'Ziele'),
  _GermanNoun('Ergebnis', _GermanGender.neuter, 'Ergebnisse'),
  _GermanNoun('Gespräch', _GermanGender.neuter, 'Gespräche'),
  _GermanNoun('Büro', _GermanGender.neuter, 'Büros'),
  _GermanNoun('Sprache', _GermanGender.feminine, 'Sprachen'),
  _GermanNoun('Regel', _GermanGender.feminine, 'Regeln'),
  _GermanNoun('Version', _GermanGender.feminine, 'Versionen'),
];

final class _GermanNounReading {
  const _GermanNounReading(this.gender, this.forms);
  final _GermanGender gender;
  final List<Set<String>> forms;

  Set<String> inCase(_GermanCase grammaticalCase) =>
      forms[grammaticalCase.index];

  bool accepts(String lower, _GermanCase grammaticalCase) => inCase(
    grammaticalCase,
  ).any((String form) => _germanFormsEquivalent(form.toLowerCase(), lower));
}

final Map<String, List<_GermanNounReading>> _grammarNounForms =
    _buildGrammarNounForms();

Map<String, List<_GermanNounReading>> _buildGrammarNounForms() {
  final Map<String, List<_GermanNounReading>> result =
      <String, List<_GermanNounReading>>{};
  void add(String form, _GermanNounReading reading) {
    final String lower = form.toLowerCase();
    result.putIfAbsent(lower, () => <_GermanNounReading>[]).add(reading);
    final String swiss = lower.replaceAll('ß', 'ss');
    if (swiss != lower) {
      result.putIfAbsent(swiss, () => <_GermanNounReading>[]).add(reading);
    }
  }

  for (final _GermanNoun noun in _grammarNouns) {
    final _GermanNounReading singular = _GermanNounReading(
      noun.gender,
      <Set<String>>[
        <String>{noun.singular},
        <String>{noun.singular},
        <String>{noun.singular},
        // The first-party fallback did not model genitive alternatives.
        // Empty means unknown, never permission to invent a paradigm.
        const <String>{},
      ],
    );
    final _GermanNounReading plural = _GermanNounReading(
      _GermanGender.plural,
      <Set<String>>[
        <String>{noun.plural},
        <String>{noun.plural},
        <String>{noun.dativePlural},
        <String>{noun.plural},
      ],
    );
    add(noun.singular, singular);
    add(noun.plural, plural);
    if (noun.dativePlural != noun.plural) add(noun.dativePlural, plural);
  }
  return result;
}

List<_GermanNounReading> _lookupGrammarNoun(String lower) {
  final List<GermanNounReading> lexical = GermanNounMorphology.shared.lookup(
    lower,
  );
  if (lexical.isEmpty) {
    // An explicitly unresolved competing reading is not an unknown word.
    // A small fallback must not restore the confidence the resource rejected.
    if (GermanNounMorphology.shared.hasUnresolvedReading(lower)) {
      return const <_GermanNounReading>[];
    }
    return _grammarNounForms[lower] ?? const <_GermanNounReading>[];
  }
  return <_GermanNounReading>[
    for (final GermanNounReading reading in lexical)
      _GermanNounReading(_GermanGender.values[reading.gender], <Set<String>>[
        for (final _GermanCase grammaticalCase in _GermanCase.values)
          reading.formsForCase(grammaticalCase.index),
      ]),
  ];
}

final class _GermanDeterminer {
  const _GermanDeterminer(this.stem, {this.definite = false});
  final String stem;
  final bool definite;

  bool get permitsPlural => stem != 'ein';

  bool isUnambiguousGenitive(String surface) {
    final Set<_GermanCase> cases = <_GermanCase>{
      for (final _GermanCase grammaticalCase in _GermanCase.values)
        for (final _GermanGender gender in _GermanGender.values)
          if ((gender != _GermanGender.plural || permitsPlural) &&
              form(grammaticalCase, gender) == surface)
            grammaticalCase,
    };
    return cases.length == 1 && cases.contains(_GermanCase.genitive);
  }

  String form(_GermanCase grammaticalCase, _GermanGender gender) {
    final int index = grammaticalCase.index * 4 + gender.index;
    if (stem == 'd') {
      return const <String>[
        'der',
        'die',
        'das',
        'die',
        'den',
        'die',
        'das',
        'die',
        'dem',
        'der',
        'dem',
        'den',
        'des',
        'der',
        'des',
        'der',
      ][index];
    }
    final String ending = (definite
        ? const <String>[
            'er',
            'e',
            'es',
            'e',
            'en',
            'e',
            'es',
            'e',
            'em',
            'er',
            'em',
            'en',
            'es',
            'er',
            'es',
            'er',
          ]
        : const <String>[
            '',
            'e',
            '',
            'e',
            'en',
            'e',
            '',
            'e',
            'em',
            'er',
            'em',
            'en',
            'es',
            'er',
            'es',
            'er',
          ])[index];
    return stem == 'eur' && ending.isEmpty ? 'euer' : '$stem$ending';
  }
}

const List<_GermanDeterminer> _grammarDeterminers = <_GermanDeterminer>[
  _GermanDeterminer('d', definite: true),
  _GermanDeterminer('dies', definite: true),
  _GermanDeterminer('jen', definite: true),
  _GermanDeterminer('ein'),
  _GermanDeterminer('kein'),
  _GermanDeterminer('mein'),
  _GermanDeterminer('dein'),
  _GermanDeterminer('sein'),
  _GermanDeterminer('ihr'),
  _GermanDeterminer('unser'),
  _GermanDeterminer('eur'),
];

final Map<String, _GermanDeterminer> _grammarDeterminerForms =
    <String, _GermanDeterminer>{
      for (final _GermanDeterminer determiner in _grammarDeterminers)
        for (final _GermanCase grammaticalCase in _GermanCase.values)
          for (final _GermanGender gender in _GermanGender.values)
            if (gender != _GermanGender.plural || determiner.permitsPlural)
              determiner.form(grammaticalCase, gender): determiner,
    };

const Set<String> _grammarAdjectiveStems = <String>{
  'gut',
  'schön',
  'groß',
  'klein',
  'neu',
  'alt',
  'jung',
  'wichtig',
  'richtig',
  'falsch',
  'freundlich',
  'möglich',
  'nötig',
  'vollständig',
  'deutsch',
  'englisch',
  'interessant',
  'unterschiedlich',
  'persönlich',
  'eigen',
  'erst',
  'zweit',
  'letzt',
  'nächst',
  'lang',
  'kurz',
  'schnell',
  'schwer',
  'leicht',
  'offen',
  'geschlossen',
  'beschädigt',
  'geprüft',
  'geändert',
  'gemeinsam',
  'zuverlässig',
  'aktuell',
  'automatisch',
  'öffentlich',
  'endgültig',
  'einfach',
  'klar',
  'modern',
  'kostenlos',
  'digital',
  'besser',
  'größer',
  'kleiner',
  'älter',
  'jünger',
  'wichtiger',
  'schneller',
  'früher',
  'hoh',
  'teur',
  'dunkl',
  'leis',
  'müd',
  // Common office/general modifiers, independently reviewed regular stems.
  'best',
  'schlimm',
  'hell',
  'gültig',
  'ungültig',
  'neugierig',
  'hochwertig',
  'deutlich',
  'weiß',
  'rot',
  'grün',
  'blau',
  'dunkelblau',
  'zusätzlich',
  'erforderlich',
  'verfügbar',
  'relevant',
  'sicher',
  'unsicher',
  'lesbar',
  'bearbeitet',
  'gespeichert',
  'erfahren',
  'technisch',
  'versiert',
  'sorgfältig',
  'praktisch',
  'rechtlich',
  'wirtschaftlich',
  'wissenschaftlich',
  'intern',
  'extern',
  'ander',
};

final Map<String, Set<String>> _grammarAdjectiveForms =
    _buildGrammarAdjectives();

Map<String, Set<String>> _buildGrammarAdjectives() {
  final Map<String, Set<String>> result = <String, Set<String>>{};
  for (final String stem in _grammarAdjectiveStems) {
    for (final String ending in const <String>[
      '',
      'e',
      'en',
      'em',
      'er',
      'es',
    ]) {
      final String form = '$stem$ending';
      result.putIfAbsent(form, () => <String>{}).add(stem);
      result
          .putIfAbsent(form.replaceAll('ß', 'ss'), () => <String>{})
          .add(stem);
    }
  }
  return result;
}

String _grammarAdjectiveEnding(
  _GermanDeterminer determiner,
  _GermanCase grammaticalCase,
  _GermanGender gender,
) {
  if (grammaticalCase == _GermanCase.dative ||
      grammaticalCase == _GermanCase.genitive ||
      gender == _GermanGender.plural ||
      grammaticalCase == _GermanCase.accusative &&
          gender == _GermanGender.masculine) {
    return 'en';
  }
  if (determiner.definite) return 'e';
  return switch (gender) {
    _GermanGender.masculine => 'er',
    _GermanGender.feminine => 'e',
    _GermanGender.neuter => 'es',
    _GermanGender.plural => 'en',
  };
}

// A case-bearing token inside an infinitive is governed by its verb, not by
// "ohne" or "um": "ohne ihm helfen zu können", "um dem Kind zu helfen".
// Likewise "seit ich ..." introduces a clause, and additive "mit" can be an
// adverb. These known competing structures are excluded before case checking.
bool _grammarPrepositionAmbiguous(
  String text,
  List<_GermanGrammarWord> words,
  int index,
) {
  final _GermanGrammarWord preposition = words[index];
  final int limit = preposition.end + 180 < text.length
      ? preposition.end + 180
      : text.length;
  final String suffix = text.substring(preposition.end, limit);
  final RegExpMatch? stop = _grammarClauseEnd.firstMatch(suffix);
  final String clause = stop == null ? suffix : suffix.substring(0, stop.start);
  if ((preposition.lower == 'ohne' || preposition.lower == 'um') &&
      (stop == null && limit < text.length || stop?.group(0) == ',')) {
    // A long or parenthetical infinitive may continue beyond this bounded
    // scan. A truncated lookahead must never assert that it is absent.
    return true;
  }
  if ((preposition.lower == 'ohne' || preposition.lower == 'um') &&
      RegExp(
        r'(?<![\p{L}\p{M}])zu[ \t\u00a0\u202f]+(?:sein|tun|[\p{L}\p{M}]+(?:en|ern|eln))(?![\p{L}\p{M}])',
        unicode: true,
      ).hasMatch(clause)) {
    return true;
  }
  if (preposition.lower == 'um' &&
      RegExp(
        r'(?<![\p{L}\p{M}])willen(?![\p{L}\p{M}])',
        unicode: true,
      ).hasMatch(clause)) {
    return true;
  }
  if (preposition.lower != 'mit') return false;
  if (index > 0 &&
      _grammarAdjacent(text, words[index - 1], preposition) &&
      const <String>{
        'ist',
        'sind',
        'war',
        'waren',
        'bleibt',
        'bleiben',
        'wird',
        'werden',
      }.contains(words[index - 1].lower)) {
    return true;
  }
  // A following infinitive can make "mit" additive; deciding otherwise needs
  // a sentence parser. Prefer a false negative to altering its object.
  return RegExp(
    r'[ \t\u00a0\u202f][a-zäöüß][a-zäöüß]*(?:en|ern|eln)[ \t\u00a0\u202f]*$',
  ).hasMatch(clause);
}

// Shared syntactic gate for prewarming and actual noun-phrase analysis. This
// does not consult the lexicon, so sentence-start capitals and unrelated names
// do not cause dictionary buckets to be decoded.
int? _grammarNounIndex(
  String text,
  List<_GermanGrammarWord> words,
  int articleIndex,
) {
  int nounIndex = articleIndex + 1;
  int adjectiveCount = 0;
  while (nounIndex < words.length &&
      _grammarAdjacent(text, words[nounIndex - 1], words[nounIndex]) &&
      adjectiveCount < 2 &&
      !words[nounIndex].capitalized &&
      _grammarAdjectiveForms.containsKey(words[nounIndex].lower)) {
    adjectiveCount++;
    nounIndex++;
  }
  if (nounIndex >= words.length ||
      !words[nounIndex].capitalized ||
      !_grammarAdjacent(text, words[nounIndex - 1], words[nounIndex])) {
    return null;
  }
  return nounIndex;
}

Iterable<String> _grammarMorphologyCandidates(
  String text,
  bool Function(int, int) protected,
  Set<int> boundaries,
) sync* {
  final List<_GermanGrammarWord> words = _grammarWordExpression
      .allMatches(text)
      .map(_GermanGrammarWord.new)
      .toList(growable: false);
  for (int i = 0; i < words.length; i++) {
    if (!_grammarDeterminerForms.containsKey(words[i].lower)) continue;
    final int? nounIndex = _grammarNounIndex(text, words, i);
    if (nounIndex == null) continue;
    int contextStart = words[i].start;
    if (i > 0 &&
        _governedCases.containsKey(words[i - 1].lower) &&
        _grammarAdjacent(text, words[i - 1], words[i]) &&
        !_grammarPrepositionAmbiguous(text, words, i - 1)) {
      contextStart = words[i - 1].start;
    }
    final _GermanGrammarWord noun = words[nounIndex];
    if (_grammarContextSafe(contextStart, noun.end, protected, boundaries)) {
      yield noun.text;
    }
  }
}

Iterable<_GermanGrammarIssue> _germanGrammarIssues(
  String text,
  bool Function(int, int) protected,
  Set<int> boundaries,
  bool swiss,
) sync* {
  final List<_GermanGrammarWord> words = _grammarWordExpression
      .allMatches(text)
      .map(_GermanGrammarWord.new)
      .toList(growable: false);
  final Set<int> governedDeterminers = <int>{};
  final verbContext = _grammarVerbContext(text, words, protected, boundaries);
  for (int i = 0; i + 1 < words.length; i++) {
    final _GermanGrammarWord preposition = words[i];
    final _GermanCase? grammaticalCase = _governedCases[preposition.lower];
    if (grammaticalCase == null ||
        !_grammarAdjacent(text, preposition, words[i + 1]) ||
        _grammarPrepositionAmbiguous(text, words, i)) {
      continue;
    }
    final _GermanGrammarWord next = words[i + 1];
    if (_grammarContextSafe(
          preposition.start,
          next.end,
          protected,
          boundaries,
        ) &&
        preposition.lower != 'seit' &&
        !next.capitalized) {
      final String? replacement = (grammaticalCase == _GermanCase.dative
          ? const <String, String>{
              'ich': 'mir',
              'mich': 'mir',
              'du': 'dir',
              'dich': 'dir',
              'er': 'ihm',
              'ihn': 'ihm',
              'wir': 'uns',
            }
          : const <String, String>{
              'ich': 'mich',
              'mir': 'mich',
              'du': 'dich',
              'dir': 'dich',
              'er': 'ihn',
              'ihm': 'ihn',
              'wir': 'uns',
              'ihnen': 'sie',
            })[next.lower];
      if (replacement != null) {
        yield _GermanGrammarIssue(
          'de.grammar.preposition-pronoun',
          next.start,
          next.end,
          replacement,
          'Nach „${preposition.lower}“ steht dieses Pronomen hier normalerweise im '
              '${grammaticalCase == _GermanCase.dative ? 'Dativ' : 'Akkusativ'}.',
        );
      }
    }
    if (_grammarDeterminerForms.containsKey(next.lower)) {
      governedDeterminers.add(i + 1);
      yield* _grammarNounPhrase(
        text,
        words,
        i + 1,
        grammaticalCase,
        preposition.start,
        protected,
        boundaries,
        swiss,
      );
    }
  }
  for (int i = 0; i < words.length; i++) {
    if (!governedDeterminers.contains(i) &&
        _grammarDeterminerForms.containsKey(words[i].lower)) {
      if (_grammarPotentialVerbObject(text, words, i)) {
        // An incomplete or ambiguous verb frame must not fall through to a
        // case guess based only on the malformed article. In particular,
        // "ein kleinen Hund" must not become "ein kleiner Hund" here.
        if (_grammarCompleteVerbObject(text, words, i, protected, boundaries)) {
          yield* _grammarNounPhrase(
            text,
            words,
            i,
            _GermanCase.accusative,
            words.first.start,
            protected,
            boundaries,
            swiss,
            articleRuleId: 'de.grammar.verb-object-case',
            articleMessage:
                'Das direkte Objekt dieses Verbs steht hier normalerweise im Akkusativ.',
          );
        }
        continue;
      }
      yield* _grammarNounPhrase(
        text,
        words,
        i,
        verbContext?.articleIndex == i ? verbContext!.grammaticalCase : null,
        verbContext?.articleIndex == i ? words.first.start : words[i].start,
        protected,
        boundaries,
        swiss,
        articleRuleId: verbContext?.articleIndex == i
            ? verbContext!.grammaticalCase == _GermanCase.genitive
                  ? 'de.grammar.genitive-attribute'
                  : 'de.grammar.verb-case'
            : 'de.grammar.preposition-case',
        articleMessage:
            'Artikel und Nomen verlangen in diesem eindeutigen Kasus normalerweise diese Form.',
      );
    }
  }
  yield* _grammarClauseIssues(text, words, protected, boundaries);
  yield* _grammarComparisonIssues(text, words, protected, boundaries);
  yield* _grammarInvertedAgreement(text, words, protected, boundaries);
  yield* _grammarSimpleNounAgreement(text, words, protected, boundaries, swiss);
  yield* _grammarContextIssues(text, words, protected, boundaries, verbContext);
}

// Reviewed lexical uses with a direct accusative object. The present forms are
// shared with the existing authored agreement table. Copulas, modals, dative
// governors and unreviewed verbs deliberately do not establish object case.
// "haben" qualifies only as a complete lexical frame; any later participle,
// infinitive, extra phrase or clause prevents the positive inference below.
const _grammarAccusativeVerbs = <String>{
  'haben',
  'brauchen',
  'finden',
  'nehmen',
  'sehen',
  'lesen',
  'essen',
  'kennen',
  'verstehen',
  'kaufen',
  'hören',
  'suchen',
  'tragen',
  'treffen',
  'vergessen',
  'trinken',
};
const _grammarObjectSubjects = <String>{
  'ich',
  'du',
  'er',
  'es',
  'man',
  'wir',
  'ihr',
  'sie',
};
final _grammarObjectEnd = RegExp(r'^[.!?][ \t\r\n\u00a0\u202f]*$');

_GermanPresentParadigm? _grammarObjectParadigm(_GermanGrammarWord verb) {
  final paradigm = GermanWritingRulesProvider
      ._presentByForm[normalizeGermanWord(verb.lower)];
  return paradigm != null &&
          _grammarAccusativeVerbs.contains(paradigm.infinitive)
      ? paradigm
      : null;
}

bool _grammarPotentialVerbObject(
  String text,
  List<_GermanGrammarWord> words,
  int index,
) {
  // A potential governor is enough for abstention, including one separated by
  // protected markup. Only the stricter complete-frame gate may emit findings.
  if (index > 0 &&
      _grammarObjectParadigm(words[index - 1]) != null &&
      !_grammarClauseEnd.hasMatch(
        text.substring(words[index - 1].end, words[index].start),
      )) {
    return true;
  }
  // Inversion: "Heute sehe ich ein ...". This narrow implementation does not
  // infer case for post-verbal subjects or fronted objects.
  if (index > 1 &&
      _grammarObjectSubjects.contains(words[index - 1].lower) &&
      _grammarObjectParadigm(words[index - 2]) != null &&
      _grammarAdjacent(text, words[index - 2], words[index - 1]) &&
      _grammarAdjacent(text, words[index - 1], words[index])) {
    return true;
  }
  final nounIndex = _grammarNounIndex(text, words, index);
  if (nounIndex == null || nounIndex + 1 >= words.length) return false;
  final verb = words[nounIndex + 1];
  if (_grammarObjectParadigm(verb) == null ||
      !_grammarAdjacent(text, words[nounIndex], verb)) {
    return false;
  }
  // Subordinate or fronted phrase: "wenn ich ein ... sehe" / "ein ... sehe
  // ich". These are also unsafe places for the old nominative-only fallback.
  return index > 0 &&
          _grammarObjectSubjects.contains(words[index - 1].lower) &&
          _grammarAdjacent(text, words[index - 1], words[index]) ||
      nounIndex + 2 < words.length &&
          _grammarObjectSubjects.contains(words[nounIndex + 2].lower) &&
          _grammarAdjacent(text, verb, words[nounIndex + 2]);
}

bool _grammarCompleteVerbObject(
  String text,
  List<_GermanGrammarWord> words,
  int index,
  bool Function(int, int) protected,
  Set<int> boundaries,
) {
  // Accept only an entire short clause: pronoun + matching finite verb + one
  // modeled noun phrase + actual final punctuation. Never truncate lookahead
  // to satisfy the gate. The bounds cover two modeled adjectives and a noun.
  if (index != 2 || words.length > 6 || text.length > 512) return false;
  final subject = words[0];
  final verb = words[1];
  final paradigm = _grammarObjectParadigm(verb);
  if (paradigm == null ||
      verb.capitalized ||
      text.substring(0, subject.start).trim().isNotEmpty ||
      !_grammarAdjacent(text, subject, verb) ||
      !_grammarAdjacent(text, verb, words[index]) ||
      !_grammarContextSafe(subject.start, text.length, protected, boundaries)) {
    return false;
  }
  final expected = switch (subject.lower) {
    'ich' => [paradigm.ich],
    'du' => [paradigm.du],
    'er' || 'es' || 'man' => [paradigm.thirdPerson],
    'wir' => [paradigm.wir],
    'ihr' => [paradigm.ihr],
    'sie' => [paradigm.thirdPerson, paradigm.wir],
    _ => const <String>[],
  };
  if (!expected.any((form) => _germanFormsEquivalent(form, verb.lower))) {
    return false;
  }
  final nounIndex = _grammarNounIndex(text, words, index);
  if (nounIndex == null ||
      nounIndex != words.length - 1 ||
      !_grammarObjectEnd.hasMatch(text.substring(words[nounIndex].end))) {
    return false;
  }
  // A bare comparative can also be an inflected positive adjective, e.g.
  // "kleiner" has modeled stems "klein" and "kleiner". Do not repair an
  // article while silently choosing or leaving unresolved its modifier's
  // degree. Every adjective in this new complete-frame inference must have a
  // single modeled stem; the existing phrase rules retain their own policy.
  for (var i = index + 1; i < nounIndex; i++) {
    if (_grammarAdjectiveForms[words[i].lower]!.length != 1) return false;
  }
  // "Sie sieht der alte Mann" is valid with a fronted object. "es" shares
  // nominative/accusative spelling; "ihr" can instead be a dative object.
  // Retain every valid noun-number reading before preferring pronoun-subject
  // order. No correction may depend on discarding this grammatical reading.
  if (const {'sie', 'es', 'ihr'}.contains(subject.lower) &&
      _grammarPossiblePostverbalSubject(
        words,
        index,
        nounIndex,
        paradigm,
        verb,
      )) {
    return false;
  }
  return true;
}

bool _grammarPossiblePostverbalSubject(
  List<_GermanGrammarWord> words,
  int index,
  int nounIndex,
  _GermanPresentParadigm paradigm,
  _GermanGrammarWord verb,
) {
  final article = words[index];
  final determiner = _grammarDeterminerForms[article.lower]!;
  final noun = words[nounIndex];
  if (_grammarCouldBeNominalizedAdjective(
    article,
    determiner,
    noun,
    _GermanCase.nominative,
  )) {
    return true;
  }
  for (final reading in _lookupGrammarNoun(noun.lower)) {
    if (reading.gender == _GermanGender.plural && !determiner.permitsPlural ||
        determiner.form(_GermanCase.nominative, reading.gender) !=
            article.lower ||
        !reading.accepts(noun.lower, _GermanCase.nominative) ||
        !_germanFormsEquivalent(
          reading.gender == _GermanGender.plural
              ? paradigm.wir
              : paradigm.thirdPerson,
          verb.lower,
        )) {
      continue;
    }
    var valid = true;
    for (var i = index + 1; i < nounIndex; i++) {
      final adjective = words[i];
      if (i + 1 < nounIndex && _grammarAdverbModifier(adjective)) continue;
      final ending = _grammarAdjectiveEnding(
        determiner,
        _GermanCase.nominative,
        reading.gender,
      );
      if (!_grammarAdjectiveForms[adjective.lower]!.any(
        (stem) => _germanFormsEquivalent('$stem$ending', adjective.lower),
      )) {
        valid = false;
        break;
      }
    }
    if (valid) return true;
  }
  return false;
}

// A deliberately small complete-clause gate. A fronted object can look like a
// subject until its actual subject appears: "Die Kinder sieht meine Frau".
// Only permit finite predicates with no following subject/object noun phrase,
// coordination, relative clause, auxiliary, quotation or reported-speech cue.
// A full syntax backend is still needed for the excluded constructions.
const _grammarPredicateAdverbs = <String>{
  'heute',
  'morgen',
  'jetzt',
  'hier',
  'dort',
  'draußen',
  'drinnen',
  'bald',
  'gerne',
  'oft',
  'immer',
  'selten',
  'zusammen',
  'wieder',
  'allein',
  'auch',
  'nicht',
  'wirklich',
  'sehr',
  'müde',
  'bereit',
  'fertig',
  'sauber',
  'pünktlich',
  'leise',
  'laut',
  'schnell',
  'langsam',
  'lange',
  'gut',
  'schlecht',
  'schön',
  'hungrig',
  'glücklich',
  'traurig',
  'wach',
  'krank',
};
const _grammarPredicatePrepositions = <String>{
  'im',
  'am',
  'zum',
  'beim',
  'vom',
  'ins',
  'ans',
  'zur',
  'nach',
  'zu',
  'bei',
  'mit',
  'ohne',
};
final _grammarPredicateNoun = RegExp(r'^\p{Lu}[\p{L}\p{M}]*$', unicode: true);

bool _grammarPredicateHorizontal(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0xa0 || unit == 0x202f;

bool _grammarSimplePredicate(String text, int start) {
  // Scan whitespace once instead of backtracking over overlapping repetitions.
  // Newlines are allowed only after the optional final period or final word.
  var end = text.length;
  while (end > start) {
    final unit = text.codeUnitAt(end - 1);
    if (!_grammarPredicateHorizontal(unit) && unit != 0x0a && unit != 0x0d) {
      break;
    }
    end--;
  }
  if (end > start && text.codeUnitAt(end - 1) == 0x2e) end--;
  while (end > start && _grammarPredicateHorizontal(text.codeUnitAt(end - 1))) {
    end--;
  }
  var cursor = start;
  while (cursor < end) {
    while (cursor < end &&
        _grammarPredicateHorizontal(text.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor == end) return true;
    final tokenStart = cursor;
    while (cursor < end &&
        !_grammarPredicateHorizontal(text.codeUnitAt(cursor))) {
      cursor++;
    }
    final token = text.substring(tokenStart, cursor);
    if (_grammarPredicateAdverbs.contains(token)) continue;
    // Preserve the old gate's optional space before the final preposition,
    // including an adjacent adverb/preposition. This checks a fixed-size set.
    final preposition = _grammarPredicatePrepositions.any(
      (word) =>
          token == word ||
          token.endsWith(word) &&
              _grammarPredicateAdverbs.contains(
                token.substring(0, token.length - word.length),
              ),
    );
    if (!preposition) return false;
    while (cursor < end &&
        _grammarPredicateHorizontal(text.codeUnitAt(cursor))) {
      cursor++;
    }
    // Exactly one capitalized noun must finish this optional phrase. The
    // anchored character-class match is linear and cannot split whitespace.
    return cursor < end &&
        _grammarPredicateNoun.hasMatch(text.substring(cursor, end));
  }
  return true;
}

Iterable<_GermanGrammarIssue> _grammarSimpleNounAgreement(
  String text,
  List<_GermanGrammarWord> words,
  bool Function(int, int) protected,
  Set<int> boundaries,
  bool swiss,
) sync* {
  if (words.length < 3 ||
      text.substring(0, words.first.start).trim().isNotEmpty) {
    return;
  }
  final article = words.first;
  final determiner = _grammarDeterminerForms[article.lower];
  if (determiner == null) return;
  final nounIndex = _grammarNounIndex(text, words, 0);
  if (nounIndex == null || nounIndex + 1 >= words.length) return;
  final noun = words[nounIndex];
  final verb = words[nounIndex + 1];
  if (!_grammarAdjacent(text, noun, verb) ||
      verb.capitalized ||
      !_grammarSimplePredicate(text, verb.end) ||
      !_grammarContextSafe(article.start, text.length, protected, boundaries) ||
      _grammarCouldBeNominalizedAdjective(article, determiner, noun, null)) {
    return;
  }
  final paradigm = GermanWritingRulesProvider._presentByForm[verb.lower];
  if (paradigm == null ||
      !_germanFormsEquivalent(verb.lower, paradigm.thirdPerson) &&
          !_germanFormsEquivalent(verb.lower, paradigm.wir)) {
    return;
  }
  final morphology = GermanNounMorphology.shared;
  if (!morphology.acceptsSpelling(noun.text, swiss: swiss)) return;
  final numbers = <bool>{
    for (final reading in _lookupGrammarNoun(noun.lower))
      if ((reading.gender != _GermanGender.plural ||
              determiner.permitsPlural) &&
          determiner.form(_GermanCase.nominative, reading.gender) ==
              article.lower &&
          reading.accepts(noun.lower, _GermanCase.nominative))
        reading.gender == _GermanGender.plural,
  };
  // Retain ALL readings: "die Leiter" can be a singular ladder or plural
  // leaders. A parser's guessed number must not erase that ambiguity.
  if (numbers.length != 1) return;
  final plural = numbers.single;
  // Every modeled adjective must agree with the selected nominative reading;
  // otherwise leave the phrase to the existing adjective/case checks.
  for (var index = 1; index < nounIndex; index++) {
    final adjective = words[index];
    final stems = _grammarAdjectiveForms[adjective.lower]!;
    final genders = _lookupGrammarNoun(noun.lower).where(
      (reading) =>
          (reading.gender == _GermanGender.plural) == plural &&
          determiner.form(_GermanCase.nominative, reading.gender) ==
              article.lower &&
          reading.accepts(noun.lower, _GermanCase.nominative),
    );
    if (genders.any(
      (reading) => !stems.any(
        (stem) => _germanFormsEquivalent(
          '$stem${_grammarAdjectiveEnding(determiner, _GermanCase.nominative, reading.gender)}',
          adjective.lower,
        ),
      ),
    )) {
      return;
    }
  }
  var replacement = plural ? paradigm.wir : paradigm.thirdPerson;
  if (swiss) replacement = replacement.replaceAll('ß', 'ss');
  if (_germanFormsEquivalent(verb.lower, replacement)) return;
  yield _GermanGrammarIssue(
    'de.grammar.noun-verb',
    verb.start,
    verb.end,
    replacement,
    'Diese Verbform passt normalerweise nicht zum eindeutigen Singular oder Plural des vorangehenden Subjekts.',
  );
}

bool _grammarCouldBeNominalizedAdjective(
  _GermanGrammarWord article,
  _GermanDeterminer determiner,
  _GermanGrammarWord noun,
  _GermanCase? governedCase,
) {
  final Set<String>? stems =
      _grammarAdjectiveForms[normalizeGermanWord(noun.lower)];
  if (stems == null) return false;
  for (final _GermanCase grammaticalCase
      in governedCase == null
          ? _GermanCase.values
          : <_GermanCase>[governedCase]) {
    for (final _GermanGender gender in _GermanGender.values) {
      if (gender == _GermanGender.plural && !determiner.permitsPlural ||
          determiner.form(grammaticalCase, gender) != article.lower) {
        continue;
      }
      final String ending = _grammarAdjectiveEnding(
        determiner,
        grammaticalCase,
        gender,
      );
      if (stems.any(
        (String stem) => _germanFormsEquivalent('$stem$ending', noun.lower),
      )) {
        return true;
      }
    }
  }
  return false;
}

Iterable<_GermanGrammarIssue> _grammarNounPhrase(
  String text,
  List<_GermanGrammarWord> words,
  int index,
  _GermanCase? governedCase,
  int contextStart,
  bool Function(int, int) protected,
  Set<int> boundaries,
  bool swiss, {
  String articleRuleId = 'de.grammar.preposition-case',
  String articleMessage =
      'Artikel, Nomen und Präposition verlangen hier normalerweise diese Form.',
}) sync* {
  final _GermanGrammarWord article = words[index];
  final _GermanDeterminer determiner = _grammarDeterminerForms[article.lower]!;
  final int? nounIndex = _grammarNounIndex(text, words, index);
  if (nounIndex == null) return;
  final _GermanGrammarWord noun = words[nounIndex];
  if (!_grammarContextSafe(contextStart, noun.end, protected, boundaries)) {
    return;
  }
  final List<_GermanGrammarWord> adjectives = words.sublist(
    index + 1,
    nounIndex,
  );
  if (_grammarCouldBeNominalizedAdjective(
    article,
    determiner,
    noun,
    governedCase,
  )) {
    // A valid capitalized adjective can share its surface with an ordinary
    // noun: "für die Junge" / "mit der Jungen". Preserve that reading rather
    // than changing its gender or case. This is only a validity veto; it does
    // not infer or correct unmodeled nominalizations. "mit dem Junge" does
    // not satisfy the dative adjective ending and remains eligible for repair.
    return;
  }
  final List<_GermanNounReading> readings = _lookupGrammarNoun(noun.lower);
  if (readings.isEmpty) return;
  if (governedCase == null &&
      !determiner.definite &&
      article.lower == determiner.stem &&
      adjectives.isNotEmpty &&
      readings.any(
        (reading) => _GermanCase.values.any(
          (grammaticalCase) =>
              (reading.gender != _GermanGender.plural ||
                  determiner.permitsPlural) &&
              reading.accepts(noun.lower, grammaticalCase) &&
              determiner.form(grammaticalCase, reading.gender) !=
                  article.lower &&
              adjectives.every(
                (adjective) => _grammarAdjectiveForms[adjective.lower]!.any(
                  (stem) => _germanFormsEquivalent(
                    '$stem${_grammarAdjectiveEnding(determiner, grammaticalCase, reading.gender)}',
                    adjective.lower,
                  ),
                ),
              ),
        ),
      )) {
    // The article can be wrong instead of the adjective. Without a governor,
    // "ein roten Mantel" must not be turned into the nominative "ein roter".
    return;
  }
  // "des" and "eines" identify genitive without a clause parser or an
  // assumed preposition governor. "dieses", "jenes" and "der" also have
  // other cases, so their noun endings remain undecided. Use the full
  // determiner table rather than discarding inconvenient noun readings.
  final bool explicitGenitive =
      governedCase == null && determiner.isUnambiguousGenitive(article.lower);
  if (governedCase == _GermanCase.dative &&
      noun.lower.endsWith('e') &&
      readings.any(
        (_GermanNounReading reading) =>
            reading.gender == _GermanGender.plural &&
            reading.accepts(noun.lower, _GermanCase.nominative),
      )) {
    final String base = noun.lower.substring(0, noun.lower.length - 1);
    if (_lookupGrammarNoun(base).any(
      (_GermanNounReading reading) =>
          (reading.gender == _GermanGender.masculine ||
              reading.gender == _GermanGender.neuter) &&
          determiner.form(_GermanCase.dative, reading.gender) ==
              article.lower &&
          reading.accepts(base, _GermanCase.nominative) &&
          reading.accepts(base, _GermanCase.dative),
    )) {
      // Literary dative -e can coincide with a recorded plural: "mit dem
      // Sterne", "von diesem Tage", "aus dem Worte". Lexical resources often
      // omit this optional form. Treat this as a possible singular reading;
      // this safeguard never invents or suggests a literary replacement.
      return;
    }
  }
  List<(_GermanNounReading, _GermanCase)> analyses =
      <(_GermanNounReading, _GermanCase)>[
        for (final _GermanNounReading reading in readings)
          if (reading.gender != _GermanGender.plural ||
              determiner.permitsPlural)
            for (final _GermanCase grammaticalCase
                in governedCase == null
                    ? _GermanCase.values
                    : <_GermanCase>[governedCase])
              if (governedCase != null ||
                  determiner.form(grammaticalCase, reading.gender) ==
                          article.lower &&
                      (reading.accepts(noun.lower, grammaticalCase) ||
                          explicitGenitive &&
                              grammaticalCase == _GermanCase.genitive))
                (reading, grammaticalCase),
      ];
  if (analyses.isEmpty) return;
  // An ending with no plural use anywhere in this determiner's paradigm
  // establishes singular even when its case is wrong (für diesem Schlüssel).
  // Preserve every singular gender. If only plural noun readings exist, do
  // not invent a singular; the existing plural repair still applies.
  if (governedCase != null &&
      readings.any((reading) => reading.gender != _GermanGender.plural) &&
      !_GermanCase.values.any(
        (grammaticalCase) =>
            determiner.permitsPlural &&
            determiner.form(grammaticalCase, _GermanGender.plural) ==
                article.lower,
      )) {
    analyses = analyses
        .where((analysis) => analysis.$1.gender != _GermanGender.plural)
        .toList(growable: false);
  }
  // Honor an already valid determiner first. This disambiguates e.g.
  // "mit den Fehler" (plural) from "mit dem Fehler" (singular).
  final List<(_GermanNounReading, _GermanCase)> matchingArticles = analyses
      .where(
        ((_GermanNounReading, _GermanCase) analysis) =>
            determiner.form(analysis.$2, analysis.$1.gender) == article.lower,
      )
      .toList(growable: false);
  bool agreesWithAdjectives(
    (_GermanNounReading, _GermanCase) analysis,
  ) => adjectives.every(
    (adjective) => _grammarAdjectiveForms[adjective.lower]!.any(
      (stem) => _germanFormsEquivalent(
        '$stem${_grammarAdjectiveEnding(determiner, analysis.$2, analysis.$1.gender)}',
        adjective.lower,
      ),
    ),
  );
  if (governedCase != null &&
      analyses.map((analysis) => analysis.$1.gender).toSet().length > 1 &&
      (matchingArticles.isEmpty ||
          adjectives.isNotEmpty &&
              !matchingArticles.any(agreesWithAdjectives) &&
              analyses.any(
                (analysis) =>
                    determiner.form(analysis.$2, analysis.$1.gender) !=
                        article.lower &&
                    agreesWithAdjectives(analysis),
              ))) {
    final choice = _grammarPhraseAlternatives(
      text,
      article,
      noun,
      adjectives,
      determiner,
      analyses,
      swiss,
    );
    if (choice != null) {
      yield choice;
      return;
    }
  }
  if (governedCase != null &&
      adjectives.isNotEmpty &&
      matchingArticles.isNotEmpty &&
      !matchingArticles.any(agreesWithAdjectives) &&
      analyses.any(
        (analysis) =>
            determiner.form(analysis.$2, analysis.$1.gender) != article.lower &&
            agreesWithAdjectives(analysis),
      )) {
    // Competing lexical genders can support two repairs: der Tag (day) versus
    // das Tag (metadata). Neither article nor adjective is a semantic oracle.
    return;
  }
  if (matchingArticles.isNotEmpty) analyses = matchingArticles;
  if (analyses.any(
    ((_GermanNounReading, _GermanCase) analysis) =>
        analysis.$1.inCase(analysis.$2).isEmpty,
  )) {
    // A missing paradigm slot is unknown. It cannot be discarded to make a
    // competing reading look certain.
    return;
  }

  final Set<String> articleForms = <String>{
    for (final (_GermanNounReading, _GermanCase) analysis in analyses)
      determiner.form(analysis.$2, analysis.$1.gender),
  };
  if (governedCase != null &&
      articleForms.length == 1 &&
      !articleForms.contains(article.lower)) {
    yield _GermanGrammarIssue(
      articleRuleId,
      article.start,
      article.end,
      _matchCase(article.text, articleForms.single),
      articleMessage,
    );
  }
  // Any valid analysis vetoes a noun correction. Optional alternatives,
  // including literary dative forms, must not become false positives merely
  // because another analysis has a different preferred spelling.
  final bool nounAlreadyValid = analyses.any(
    ((_GermanNounReading, _GermanCase) analysis) =>
        analysis.$1.accepts(noun.lower, analysis.$2),
  );
  final Set<String> nounForms = <String>{
    for (final (_GermanNounReading, _GermanCase) analysis in analyses)
      ...analysis.$1.inCase(analysis.$2),
  };
  if ((governedCase != null || explicitGenitive) &&
      !nounAlreadyValid &&
      nounForms.length == 1) {
    final String replacement = nounForms.single;
    // Upstream morphology is useful for analysis but is not an independent
    // spelling authority. Never suggest an inflected form missing from the
    // existing modern dictionary (including its reviewed Swiss equivalent).
    if (GermanNounMorphology.shared.acceptsSpelling(
      replacement,
      swiss: swiss,
    )) {
      final bool dativePlural =
          governedCase == _GermanCase.dative &&
          analyses.every(
            ((_GermanNounReading, _GermanCase) analysis) =>
                analysis.$1.gender == _GermanGender.plural,
          );
      yield _GermanGrammarIssue(
        dativePlural ? 'de.grammar.dative-plural' : 'de.grammar.noun-case',
        noun.start,
        noun.end,
        _matchCase(noun.text, replacement),
        dativePlural
            ? 'Dieses Nomen erhält im Dativ Plural normalerweise ein zusätzliches „n“.'
            : 'Dieses Nomen verlangt hier normalerweise diese Kasusform.',
      );
    }
  }
  // A unique target article is enough to repair its adjective endings in the
  // same pass. Findings are disjoint; applying the whole phrase therefore does
  // not require accepting a second round of corrections.
  if (articleForms.length != 1) return;
  for (final _GermanGrammarWord adjective in adjectives) {
    // A bare modifier can be an adverb attached to the following adjective:
    // "die automatisch geänderte Datei", "ein leicht beschädigtes Buch".
    // Inflecting it would change the phrase's structure and meaning.
    if (_grammarUninflectedModifier(adjectives, adjective)) {
      continue;
    }
    final Set<String> replacements = <String>{
      for (final String stem in _grammarAdjectiveForms[adjective.lower]!)
        for (final (_GermanNounReading, _GermanCase) analysis in analyses)
          '$stem${_grammarAdjectiveEnding(determiner, analysis.$2, analysis.$1.gender)}',
    };
    if (replacements.length != 1 ||
        replacements.any(
          (String replacement) =>
              _germanFormsEquivalent(replacement, adjective.lower),
        )) {
      continue;
    }
    yield _GermanGrammarIssue(
      'de.grammar.adjective-ending',
      adjective.start,
      adjective.end,
      replacements.single,
      'Die Adjektivendung muss hier zu Artikel, Kasus und Nomen passen.',
    );
  }
}

bool _grammarUninflectedModifier(
  List<_GermanGrammarWord> adjectives,
  _GermanGrammarWord adjective,
) => adjective != adjectives.last && _grammarAdverbModifier(adjective);

// Offer complete, internally agreeing phrases instead of splicing independent
// gender guesses into article/adjective/noun findings. Existing valid phrases
// veto a finding. Bounded alternatives retain competing meanings, in stable
// grammatical-gender order; this order is not a semantic confidence score.
_GermanGrammarIssue? _grammarPhraseAlternatives(
  String text,
  _GermanGrammarWord article,
  _GermanGrammarWord noun,
  List<_GermanGrammarWord> adjectives,
  _GermanDeterminer determiner,
  List<(_GermanNounReading, _GermanCase)> analyses,
  bool swiss,
) {
  final ordered = analyses.toList()
    ..sort((a, b) => a.$1.gender.index.compareTo(b.$1.gender.index));
  final replacements = <String>{};
  final original = text.substring(article.start, noun.end);
  for (final (reading, grammaticalCase) in ordered) {
    final nouns = reading.inCase(grammaticalCase);
    if (nouns.isEmpty) return null;
    var endings = <List<String>>[[]];
    for (final adjective in adjectives) {
      final forms = _grammarUninflectedModifier(adjectives, adjective)
          ? {adjective.text}
          : {
              for (final stem in _grammarAdjectiveForms[adjective.lower]!)
                '$stem${_grammarAdjectiveEnding(determiner, grammaticalCase, reading.gender)}',
            };
      endings = [
        for (final prefix in endings)
          for (final form in forms) [...prefix, form],
      ];
      if (endings.length > 8) return null;
    }
    for (final targetNoun in nouns) {
      if (!GermanNounMorphology.shared.acceptsSpelling(
        targetNoun,
        swiss: swiss,
      )) {
        // Do not discard an unsupported alternative to manufacture certainty.
        return null;
      }
      for (final targets in endings) {
        var candidate = original.replaceRange(
          noun.start - article.start,
          noun.end - article.start,
          _matchCase(noun.text, targetNoun),
        );
        for (var i = adjectives.length - 1; i >= 0; i--) {
          candidate = candidate.replaceRange(
            adjectives[i].start - article.start,
            adjectives[i].end - article.start,
            targets[i],
          );
        }
        candidate = candidate.replaceRange(
          0,
          article.text.length,
          _matchCase(
            article.text,
            determiner.form(grammaticalCase, reading.gender),
          ),
        );
        if (swiss) candidate = candidate.replaceAll('ß', 'ss');
        if (_germanFormsEquivalent(candidate, original)) return null;
        replacements.add(candidate);
        if (replacements.length > 8) return null;
      }
    }
  }
  if (replacements.length < 2) return null;
  return _GermanGrammarIssue(
    'de.grammar.phrase-agreement',
    article.start,
    noun.end,
    replacements.first,
    'Diese Nominalgruppe stimmt im regierten Kasus nicht überein. Wählen Sie die zur gemeinten Bedeutung passende vollständige Form.',
    alternatives: replacements.skip(1).toList(growable: false),
  );
}

bool _grammarAdverbModifier(_GermanGrammarWord adjective) =>
    _grammarAdjectiveStems.any(
      (String stem) => _germanFormsEquivalent(stem, adjective.lower),
    ) ||
    const <String>{'leise', 'müde'}.contains(adjective.lower) ||
    adjective.lower.endsWith('er');

const Set<String> _grammarMatrixVerbs = <String>{
  'denke',
  'denkst',
  'denkt',
  'denken',
  'glaube',
  'glaubst',
  'glaubt',
  'glauben',
  'hoffe',
  'hoffst',
  'hofft',
  'hoffen',
  'weiß',
  'weißt',
  'weiss',
  'weisst',
  'wissen',
  'wisst',
  'vermute',
  'vermutest',
  'vermutet',
  'vermuten',
  'finde',
  'findest',
  'findet',
  'finden',
  'merke',
  'merkst',
  'merkt',
  'merken',
  'erwarte',
  'erwartest',
  'erwartet',
  'erwarten',
  'sehe',
  'siehst',
  'sieht',
  'sehen',
  'seht',
  'sage',
  'sagst',
  'sagt',
  'sagen',
};
const Set<String> _grammarSubjects = <String>{
  'ich',
  'du',
  'er',
  'sie',
  'es',
  'wir',
  'ihr',
  'man',
};

Iterable<_GermanGrammarIssue> _grammarClauseIssues(
  String text,
  List<_GermanGrammarWord> words,
  bool Function(int, int) protected,
  Set<int> boundaries,
) sync* {
  for (int i = 2; i + 2 < words.length; i++) {
    final _GermanGrammarWord conjunction = words[i];
    if (conjunction.lower != 'das' && conjunction.lower != 'dass') continue;
    final _GermanGrammarWord matrixVerb = words[i - 1];
    final _GermanGrammarWord matrixSubject = words[i - 2];
    if (!_grammarMatrixVerbs.contains(matrixVerb.lower) ||
        !_grammarSubjects.contains(matrixSubject.lower) ||
        !_grammarAdjacent(text, matrixSubject, matrixVerb) ||
        !_grammarSubjects.contains(words[i + 1].lower) ||
        !_grammarAdjacent(text, conjunction, words[i + 1])) {
      continue;
    }
    final String gap = text.substring(matrixVerb.end, conjunction.start);
    final bool hasComma = _grammarComma.hasMatch(gap);
    if (!hasComma && !_grammarHorizontal.hasMatch(gap)) continue;
    // Require an explicitly known finite final verb in this same bounded
    // clause. A pronoun alone does not establish a subordinate clause.
    int last = i + 1;
    while (last + 1 < words.length &&
        last - i < 18 &&
        words[last + 1].end - conjunction.start <= 180 &&
        _grammarAdjacent(text, words[last], words[last + 1])) {
      last++;
    }
    final _GermanGrammarWord finite = words[last];
    if (last <= i + 1 ||
        last + 1 < words.length &&
            _grammarAdjacent(text, finite, words[last + 1]) ||
        !GermanWritingRulesProvider._presentByForm.containsKey(finite.lower) ||
        finite.capitalized ||
        !_grammarContextSafe(
          matrixSubject.start,
          finite.end,
          protected,
          boundaries,
        )) {
      continue;
    }
    if (conjunction.lower == 'das') {
      yield _GermanGrammarIssue(
        'de.grammar.das-dass',
        conjunction.start,
        conjunction.end,
        _matchCase(conjunction.text, 'dass'),
        'Hier leitet „dass“ einen ergänzenden Nebensatz mit eigenem Subjekt und Verb ein.',
      );
    }
    if (!hasComma) {
      yield _GermanGrammarIssue(
        'de.grammar.subordinate-comma',
        matrixVerb.end,
        matrixVerb.end,
        ',',
        'Der ergänzende Nebensatz wird hier mit einem Komma abgegrenzt.',
      );
    }
  }
}

const Set<String> _grammarComparatives = <String>{
  'besser',
  'schlechter',
  'größer',
  'grösser',
  'kleiner',
  'älter',
  'jünger',
  'schneller',
  'langsamer',
  'höher',
  'niedriger',
  'länger',
  'kürzer',
  'leichter',
  'schwerer',
  'teurer',
  'billiger',
  'wichtiger',
};
const Set<String> _grammarPositiveComparisons = <String>{
  'gut',
  'schlecht',
  'groß',
  'gross',
  'klein',
  'alt',
  'jung',
  'schnell',
  'langsam',
  'hoch',
  'niedrig',
  'lang',
  'kurz',
  'leicht',
  'schwer',
  'teuer',
  'billig',
  'wichtig',
};

Iterable<_GermanGrammarIssue> _grammarInvertedAgreement(
  String text,
  List<_GermanGrammarWord> words,
  bool Function(int, int) protected,
  Set<int> boundaries,
) sync* {
  for (int i = 0; i + 1 < words.length; i++) {
    final _GermanGrammarWord verb = words[i];
    final _GermanGrammarWord subject = words[i + 1];
    if (!const <String>{
          'ich',
          'du',
          'er',
          'man',
          'wir',
        }.contains(subject.lower) ||
        !_grammarAdjacent(text, verb, subject) ||
        !_grammarContextSafe(verb.start, subject.end, protected, boundaries)) {
      continue;
    }
    final _GermanPresentParadigm? paradigm =
        GermanWritingRulesProvider._presentByForm[verb.lower];
    if (paradigm == null) continue;
    final String replacement = paradigm.forSubject(subject.lower);
    if (_germanFormsEquivalent(replacement, verb.lower) ||
        const <String>{'er', 'man'}.contains(subject.lower) &&
            paradigm.isThirdPersonSubjunctive(verb.lower) ||
        subject.lower == 'du' &&
            paradigm.isThirdPersonSubjunctive(verb.lower)) {
      // "Habe er gesagt" is reported speech; "Habe du Geduld" is an
      // imperative with an optional hearer pronoun. Neither is an error.
      continue;
    }
    if (subject.capitalized &&
        (subject.text != subject.text.toUpperCase() ||
            verb.text != verb.text.toUpperCase())) {
      continue;
    }
    // The verb may already belong to a preceding subject, followed by a
    // metalinguistic pronoun: "Wir haben du gesagt". Do not reinterpret it.
    if (i > 0 &&
        _grammarAdjacent(text, words[i - 1], verb) &&
        (_grammarSubjects.contains(words[i - 1].lower) ||
            _grammarDeterminerForms.containsKey(words[i - 1].lower))) {
      continue;
    }
    if (i + 2 < words.length) {
      final _GermanGrammarWord next = words[i + 2];
      final String gap = text.substring(subject.end, next.start);
      if (gap.trimLeft().startsWith(',') ||
          _grammarAdjacent(text, subject, next) &&
              const <String>{
                'und',
                'oder',
                'sowie',
                'noch',
              }.contains(next.lower)) {
        // "Haben du und ich Zeit?" has a coordinated plural subject.
        continue;
      }
    }
    if (i > 0 && verb.capitalized && verb.text != verb.text.toUpperCase()) {
      final String prefix = text
          .substring(verb.start > 96 ? verb.start - 96 : 0, verb.start)
          .trimRight();
      if (prefix.isNotEmpty &&
          !RegExp(r'''[.!?;:,\n„“«»(]$''').hasMatch(prefix)) {
        // A title-case word mid-clause may be a noun, e.g. "die Macht".
        continue;
      }
    }
    yield _GermanGrammarIssue(
      'de.grammar.pronoun-verb',
      verb.start,
      verb.end,
      _matchCase(verb.text, replacement),
      'Diese Verbform passt normalerweise nicht zum unmittelbar folgenden Subjektpronomen.',
    );
  }
}

Iterable<_GermanGrammarIssue> _grammarComparisonIssues(
  String text,
  List<_GermanGrammarWord> words,
  bool Function(int, int) protected,
  Set<int> boundaries,
) sync* {
  for (int i = 1; i + 1 < words.length; i++) {
    final _GermanGrammarWord conjunction = words[i];
    final _GermanGrammarWord adjective = words[i - 1];
    if (!_grammarAdjacent(text, adjective, conjunction) ||
        !_grammarAdjacent(text, conjunction, words[i + 1]) ||
        adjective.capitalized) {
      continue;
    }
    String? replacement;
    int contextStart = adjective.start;
    if (conjunction.lower == 'wie' &&
        _grammarComparatives.contains(adjective.lower)) {
      if (const <String>{
        'auch',
        'etwa',
        'beispielsweise',
        'zum',
      }.contains(words[i + 1].lower)) {
        continue;
      }
      replacement = 'als';
    } else if (conjunction.lower == 'als' &&
        i >= 2 &&
        _grammarPositiveComparisons.contains(adjective.lower) &&
        const <String>{
          'so',
          'ebenso',
          'genauso',
        }.contains(words[i - 2].lower) &&
        _grammarAdjacent(text, words[i - 2], adjective)) {
      // "so ... als möglich" is a documented regional standard variant;
      // "so ... als ob/wenn" introduces an irrealis comparison, not equality.
      if (const <String>{
        'möglich',
        'ob',
        'wenn',
        'dass',
      }.contains(words[i + 1].lower)) {
        continue;
      }
      // Without a parser a following clause can instead be temporal "als":
      // "Er war so klein als er geboren wurde" needs a comma, not "wie".
      // Keep only a short nominal/pronominal comparison, never a full clause.
      int last = i + 1;
      while (last + 1 < words.length &&
          last - i < 5 &&
          _grammarAdjacent(text, words[last], words[last + 1])) {
        last++;
      }
      final int count = last - i;
      final _GermanGrammarWord next = words[i + 1];
      final bool simplePronoun =
          count == 1 &&
          (_grammarSubjects.contains(next.lower) ||
              const <String>{
                'früher',
                'zuvor',
                'bisher',
                'gestern',
                'heute',
              }.contains(next.lower));
      final bool simpleNounPhrase =
          _grammarDeterminerForms.containsKey(next.lower) &&
          (count == 2 && words[last].capitalized ||
              count == 3 &&
                  _grammarAdjectiveForms.containsKey(words[i + 2].lower) &&
                  words[last].capitalized);
      if (!simplePronoun && !simpleNounPhrase) {
        // Bare roles ("so gut als Lehrer") and pronoun-led clauses
        // ("so klein als er hier ankam") do not establish an equality
        // comparison. Do not guess their meaning or enumerate past verbs.
        continue;
      }
      replacement = 'wie';
      contextStart = words[i - 2].start;
    }
    if (replacement == null ||
        !_grammarContextSafe(
          contextStart,
          words[i + 1].end,
          protected,
          boundaries,
        )) {
      continue;
    }
    yield _GermanGrammarIssue(
      'de.grammar.comparison',
      conjunction.start,
      conjunction.end,
      _matchCase(conjunction.text, replacement),
      replacement == 'als'
          ? 'In diesem standardsprachlichen Vergleich folgt auf den Komparativ normalerweise „als“.'
          : 'Ein Gleichheitsvergleich mit „so“ wird normalerweise mit „wie“ angeschlossen.',
    );
  }
}
