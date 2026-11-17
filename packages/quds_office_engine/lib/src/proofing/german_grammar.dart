part of 'german_writing_rules.dart';

// Independently authored, bounded phrase analysis. These are ordinary language
// facts and first-party examples, not imported rules, tagged corpora, or a
// statistical parser. Unknown words and competing analyses cause abstention.
const Set<String> _germanPhraseRuleIds = <String>{
  'de.grammar.preposition-pronoun',
  'de.grammar.preposition-case',
  'de.grammar.dative-plural',
  'de.grammar.adjective-ending',
  'de.grammar.das-dass',
  'de.grammar.subordinate-comma',
  'de.grammar.comparison',
};

final class _GermanGrammarIssue {
  const _GermanGrammarIssue(
    this.ruleId,
    this.start,
    this.end,
    this.replacement,
    this.message,
  );

  final String ruleId;
  final int start;
  final int end;
  final String replacement;
  final String message;
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

// Explicit singular/plural pairs, authored here. Inflection is restricted to
// these regular strong nouns; weak nouns, proper names and gender homographs
// such as Band, See, Leiter, Steuer and Kiefer are intentionally absent.
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
  const _GermanNounReading(this.noun, this.gender, this.isDativePlural);
  final _GermanNoun noun;
  final _GermanGender gender;
  final bool isDativePlural;

  String inCase(_GermanCase grammaticalCase) => gender != _GermanGender.plural
      ? noun.singular
      : grammaticalCase == _GermanCase.dative
      ? noun.dativePlural
      : noun.plural;
}

final Map<String, List<_GermanNounReading>> _grammarNounForms =
    _buildGrammarNounForms();

Map<String, List<_GermanNounReading>> _buildGrammarNounForms() {
  final Map<String, List<_GermanNounReading>> result =
      <String, List<_GermanNounReading>>{};
  for (final _GermanNoun noun in _grammarNouns) {
    result
        .putIfAbsent(noun.singular.toLowerCase(), () => <_GermanNounReading>[])
        .add(_GermanNounReading(noun, noun.gender, false));
    result
        .putIfAbsent(noun.plural.toLowerCase(), () => <_GermanNounReading>[])
        .add(_GermanNounReading(noun, _GermanGender.plural, false));
    if (noun.dativePlural != noun.plural) {
      result
          .putIfAbsent(
            noun.dativePlural.toLowerCase(),
            () => <_GermanNounReading>[],
          )
          .add(_GermanNounReading(noun, _GermanGender.plural, true));
    }
  }
  for (final MapEntry<String, List<_GermanNounReading>> entry
      in result.entries.toList(growable: false)) {
    final String swiss = entry.key.replaceAll('ß', 'ss');
    if (swiss != entry.key) {
      result
          .putIfAbsent(swiss, () => <_GermanNounReading>[])
          .addAll(entry.value);
    }
  }
  return result;
}

final class _GermanDeterminer {
  const _GermanDeterminer(this.stem, {this.definite = false});
  final String stem;
  final bool definite;

  bool get permitsPlural => stem != 'ein';

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

Iterable<_GermanGrammarIssue> _germanGrammarIssues(
  String text,
  bool Function(int, int) protected,
  Set<int> boundaries,
) sync* {
  final List<_GermanGrammarWord> words = _grammarWordExpression
      .allMatches(text)
      .map(_GermanGrammarWord.new)
      .toList(growable: false);
  final Set<int> governedDeterminers = <int>{};
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
      );
    }
  }
  for (int i = 0; i < words.length; i++) {
    if (!governedDeterminers.contains(i) &&
        _grammarDeterminerForms.containsKey(words[i].lower)) {
      yield* _grammarNounPhrase(
        text,
        words,
        i,
        null,
        words[i].start,
        protected,
        boundaries,
      );
    }
  }
  yield* _grammarClauseIssues(text, words, protected, boundaries);
  yield* _grammarComparisonIssues(text, words, protected, boundaries);
  yield* _grammarInvertedAgreement(text, words, protected, boundaries);
}

Iterable<_GermanGrammarIssue> _grammarNounPhrase(
  String text,
  List<_GermanGrammarWord> words,
  int index,
  _GermanCase? governedCase,
  int contextStart,
  bool Function(int, int) protected,
  Set<int> boundaries,
) sync* {
  final _GermanGrammarWord article = words[index];
  final _GermanDeterminer determiner = _grammarDeterminerForms[article.lower]!;
  final List<_GermanGrammarWord> adjectives = <_GermanGrammarWord>[];
  int nounIndex = index + 1;
  while (nounIndex < words.length &&
      _grammarAdjacent(text, words[nounIndex - 1], words[nounIndex]) &&
      adjectives.length < 2 &&
      !words[nounIndex].capitalized &&
      _grammarAdjectiveForms.containsKey(words[nounIndex].lower)) {
    adjectives.add(words[nounIndex++]);
  }
  if (nounIndex >= words.length ||
      !_grammarAdjacent(text, words[nounIndex - 1], words[nounIndex])) {
    return;
  }
  final _GermanGrammarWord noun = words[nounIndex];
  if (!noun.capitalized ||
      !_grammarContextSafe(contextStart, noun.end, protected, boundaries)) {
    return;
  }
  final List<_GermanNounReading>? readings = _grammarNounForms[noun.lower];
  if (readings == null) return;
  if (governedCase == _GermanCase.dative &&
      (determiner.form(_GermanCase.dative, _GermanGender.masculine) ==
              article.lower ||
          determiner.form(_GermanCase.dative, _GermanGender.neuter) ==
              article.lower) &&
      _grammarNouns.any(
        (_GermanNoun entry) =>
            entry.gender != _GermanGender.feminine &&
            '${entry.singular.toLowerCase()}e' == noun.lower,
      )) {
    // The optional literary dative -e can coincide with the plural:
    // "von diesem Tage", "nach dem Jahre", "aus dem Texte". Without this
    // reading, a plural-only lookup must not rewrite a valid singular phrase.
    return;
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
                      _germanFormsEquivalent(
                        reading.inCase(grammaticalCase).toLowerCase(),
                        noun.lower,
                      ))
                (reading, grammaticalCase),
      ];
  if (analyses.isEmpty) return;
  // Honor an already valid determiner first. This disambiguates e.g.
  // "mit den Fehler" (plural) from "mit dem Fehler" (singular).
  final List<(_GermanNounReading, _GermanCase)> matchingArticles = analyses
      .where(
        ((_GermanNounReading, _GermanCase) analysis) =>
            determiner.form(analysis.$2, analysis.$1.gender) == article.lower,
      )
      .toList(growable: false);
  if (matchingArticles.isNotEmpty) analyses = matchingArticles;

  final Set<String> articleForms = <String>{
    for (final (_GermanNounReading, _GermanCase) analysis in analyses)
      determiner.form(analysis.$2, analysis.$1.gender),
  };
  if (governedCase != null &&
      articleForms.length == 1 &&
      !articleForms.contains(article.lower)) {
    yield _GermanGrammarIssue(
      'de.grammar.preposition-case',
      article.start,
      article.end,
      _matchCase(article.text, articleForms.single),
      'Artikel, Nomen und Präposition verlangen hier normalerweise diese Form.',
    );
  }
  final Set<String> nounForms = <String>{
    for (final (_GermanNounReading, _GermanCase) analysis in analyses)
      analysis.$1.inCase(analysis.$2),
  };
  if (governedCase == _GermanCase.dative &&
      nounForms.length == 1 &&
      !_germanFormsEquivalent(nounForms.single.toLowerCase(), noun.lower) &&
      analyses.every(
        ((_GermanNounReading, _GermanCase) analysis) =>
            analysis.$1.gender == _GermanGender.plural,
      )) {
    yield _GermanGrammarIssue(
      'de.grammar.dative-plural',
      noun.start,
      noun.end,
      _matchCase(noun.text, nounForms.single),
      'Dieses Nomen erhält im Dativ Plural normalerweise ein zusätzliches „n“.',
    );
  }
  // Do not repair adjective endings while the article itself is unresolved.
  if (articleForms.length != 1 || articleForms.single != article.lower) return;
  for (final _GermanGrammarWord adjective in adjectives) {
    // A bare modifier can be an adverb attached to the following adjective:
    // "die automatisch geänderte Datei", "ein leicht beschädigtes Buch".
    // Inflecting it would change the phrase's structure and meaning.
    if (adjective != adjectives.last &&
        (_grammarAdjectiveStems.any(
              (String stem) => _germanFormsEquivalent(stem, adjective.lower),
            ) ||
            const <String>{'leise', 'müde'}.contains(adjective.lower) ||
            adjective.lower.endsWith('er'))) {
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
