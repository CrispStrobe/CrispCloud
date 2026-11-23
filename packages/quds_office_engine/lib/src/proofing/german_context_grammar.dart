part of 'german_writing_rules.dart';

// Independently authored language facts and bounded complete-clause checks.
// No LanguageTool code, patterns, messages, dictionaries or test corpus used.
final class _GermanVerbContext {
  const _GermanVerbContext(
    this.articleIndex,
    this.nounIndex,
    this.grammaticalCase,
  );
  final int articleIndex;
  final int nounIndex;
  final _GermanCase grammaticalCase;
}

final RegExp _contextEnd = RegExp(
  r'^[ \t\r\n\u00a0\u202f]*[.!?]?[ \t\r\n\u00a0\u202f]*$',
);
const _contextPronouns = {'ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr', 'man'};

bool _contextWhole(
  String text,
  List<_GermanGrammarWord> words,
  bool Function(int, int) protected,
  GraphemeBoundaries boundaries,
) =>
    words.isNotEmpty &&
    words.length <= 48 &&
    text.substring(0, words.first.start).trim().isEmpty &&
    _contextEnd.hasMatch(text.substring(words.last.end)) &&
    _grammarContextSafe(words.first.start, text.length, protected, boundaries);

_GermanVerbContext? _grammarVerbContext(
  String text,
  List<_GermanGrammarWord> words,
  bool Function(int, int) protected,
  GraphemeBoundaries boundaries,
) {
  if (words.length < 4 ||
      !_contextWhole(text, words, protected, boundaries) ||
      !_grammarAdjacent(text, words[0], words[1]) ||
      !_grammarAdjacent(text, words[1], words[2])) {
    return null;
  }
  final prepositional = _contextPrepositionalObject(text, words);
  if (prepositional != null) return prepositional;
  if (!_grammarDeterminerForms.containsKey(words[2].lower)) return null;
  final noun = _grammarNounIndex(text, words, 2);
  if (noun == null) return null;
  final subject = words[0].lower;
  final verb = words[1].lower;
  if ({'das', 'dies', 'es'}.contains(subject) &&
      {'ist', 'sind'}.contains(verb)) {
    if (noun == words.length - 1) {
      return _GermanVerbContext(2, noun, _GermanCase.nominative);
    }
    return _contextGenitiveAttribute(text, words, noun);
  }
  if (noun != words.length - 1) return null;
  if (!_contextPronouns.contains(subject) || words[1].capitalized) return null;
  final paradigm = GermanWritingRulesProvider._presentByForm[verb];
  if (paradigm == null || !_contextAgrees(paradigm, verb, subject)) return null;
  // Share the incoming object/subject ambiguity veto with the older verb
  // contexts too. In particular, "Ihr antwortet der Lehrer" can mean that
  // the teacher answers her, rather than that you answer the teacher.
  if (const {'sie', 'es', 'ihr'}.contains(subject) &&
      _grammarPossiblePostverbalSubject(words, 2, noun, paradigm, words[1])) {
    return null;
  }
  final grammaticalCase = switch (paradigm.infinitive) {
    'haben' ||
    'sehen' ||
    'lesen' ||
    'kaufen' ||
    'kennen' ||
    'finden' ||
    'lieben' ||
    'mögen' => _GermanCase.accusative,
    'helfen' || 'antworten' => _GermanCase.dative,
    _ => null,
  };
  if (grammaticalCase == null) return null;
  return _GermanVerbContext(2, noun, grammaticalCase);
}

// Only complete copula clauses with an already agreeing head noun phrase.
// A following adjacent determiner phrase is a genitive attribute here, rather
// than a guessed subject or an unbounded dependency. Coordination, relative
// clauses, possessive-dative constructions and nominalizations stay outside.
_GermanVerbContext? _contextGenitiveAttribute(
  String text,
  List<_GermanGrammarWord> words,
  int head,
) {
  final articleIndex = head + 1;
  if (articleIndex >= words.length ||
      !_grammarAdjacent(text, words[head], words[articleIndex]) ||
      !_grammarDeterminerForms.containsKey(words[articleIndex].lower)) {
    return null;
  }
  final nounIndex = _grammarNounIndex(text, words, articleIndex);
  if (nounIndex != words.length - 1 ||
      _grammarAdjectiveForms.containsKey(words[nounIndex!].lower)) {
    return null;
  }
  final article = words[2];
  final determiner = _grammarDeterminerForms[article.lower]!;
  final headValid = _lookupGrammarNoun(words[head].lower).any(
    (reading) =>
        (reading.gender != _GermanGender.plural || determiner.permitsPlural) &&
        determiner.form(_GermanCase.nominative, reading.gender) ==
            article.lower &&
        reading.accepts(words[head].lower, _GermanCase.nominative) &&
        words
            .sublist(3, head)
            .every(
              (adjective) => _grammarAdjectiveForms[adjective.lower]!.any(
                (stem) => _germanFormsEquivalent(
                  '$stem${_grammarAdjectiveEnding(determiner, _GermanCase.nominative, reading.gender)}',
                  adjective.lower,
                ),
              ),
            ),
  );
  return headValid
      ? _GermanVerbContext(articleIndex, nounIndex, _GermanCase.genitive)
      : null;
}

// These finite abstract heads support a prepositional object without silently
// turning a literal location (auf dem Bus/Dach/Bahnsteig, auf der Arbeit) into
// one. They are first-party scope limits, not an imported semantic lexicon.
const _contextPrideObjects = {
  'ergebnis',
  'erfolg',
  'fortschritt',
  'entscheidung',
  'beitrag',
  'leistung',
};
const _contextWaitingObjects = {
  'ergebnis',
  'antwort',
  'nachricht',
  'zusage',
  'entscheidung',
  'anruf',
  'bescheid',
};

_GermanVerbContext? _contextPrepositionalObject(
  String text,
  List<_GermanGrammarWord> words,
) {
  if (!_contextPronouns.contains(words.first.lower) || words[1].capitalized) {
    return null;
  }
  final paradigm = GermanWritingRulesProvider._presentByForm[words[1].lower];
  if (paradigm == null ||
      !_contextAgrees(paradigm, words[1].lower, words.first.lower)) {
    return null;
  }
  int articleIndex;
  Set<String> heads;
  if (paradigm.infinitive == 'sein' &&
      words.length >= 6 &&
      words[2].lower == 'stolz' &&
      words[3].lower == 'auf') {
    articleIndex = 4;
    heads = _contextPrideObjects;
  } else if (paradigm.infinitive == 'warten' &&
      words.length >= 5 &&
      words[2].lower == 'auf') {
    articleIndex = 3;
    heads = _contextWaitingObjects;
  } else {
    return null;
  }
  if (!_grammarDeterminerForms.containsKey(words[articleIndex].lower) ||
      [
        for (var i = 2; i <= articleIndex; i++) i,
      ].any((i) => !_grammarAdjacent(text, words[i - 1], words[i]))) {
    return null;
  }
  final noun = _grammarNounIndex(text, words, articleIndex);
  if (noun != words.length - 1) return null;
  final readings = GermanNounMorphology.shared.lookup(words[noun!].lower);
  if (readings.isEmpty ||
      !readings.every(
        (reading) => heads.contains(reading.lemma.toLowerCase()),
      )) {
    return null;
  }
  return _GermanVerbContext(articleIndex, noun, _GermanCase.accusative);
}

bool _contextAgrees(
  _GermanPresentParadigm paradigm,
  String verb,
  String subject,
) {
  if (subject == 'sie') {
    return _germanFormsEquivalent(verb, paradigm.thirdPerson) ||
        _germanFormsEquivalent(verb, paradigm.wir);
  }
  if (subject == 'es') {
    return _germanFormsEquivalent(verb, paradigm.thirdPerson);
  }
  if (!_contextPronouns.contains(subject)) return false;
  return _germanFormsEquivalent(verb, paradigm.forSubject(subject));
}

Iterable<_GermanGrammarIssue> _grammarContextIssues(
  String text,
  List<_GermanGrammarWord> words,
  bool Function(int, int) protected,
  GraphemeBoundaries boundaries,
  _GermanVerbContext? context,
) sync* {
  if (!_contextWhole(text, words, protected, boundaries)) return;
  if (context?.grammaticalCase == _GermanCase.nominative) {
    final noun = words[context!.nounIndex];
    final article = words[context.articleIndex];
    final determiner = _grammarDeterminerForms[article.lower]!;
    final numbers = <bool>{
      for (final reading in _lookupGrammarNoun(noun.lower))
        if ((reading.gender != _GermanGender.plural ||
                determiner.permitsPlural) &&
            determiner.form(_GermanCase.nominative, reading.gender) ==
                article.lower &&
            reading.accepts(noun.lower, _GermanCase.nominative))
          reading.gender == _GermanGender.plural,
    };
    if (numbers.length == 1) {
      final target = numbers.single ? 'sind' : 'ist';
      if (words[1].lower != target) {
        yield _GermanGrammarIssue(
          'de.grammar.copula-agreement',
          words[1].start,
          words[1].end,
          target,
          'Die Form von „sein“ passt hier zum eindeutigen Singular oder Plural der Nominalgruppe.',
        );
      }
    }
  }
  yield* _contextIhrHaben(text, words);
  yield* _contextReferentialRelative(text, words);
  yield* _contextWordOrder(text, words);
  yield* _contextParticiple(text, words);
}

Iterable<_GermanGrammarIssue> _contextWordOrder(
  String text,
  List<_GermanGrammarWord> words,
) sync* {
  if (words.length < 3) return;
  var subjectIndex = -1;
  if (const {
        'gestern',
        'heute',
        'morgen',
        'dann',
        'danach',
        'dort',
        'hier',
        'deshalb',
        'trotzdem',
        'anschließend',
        'anschliessend',
        'jetzt',
      }.contains(words.first.lower) &&
      _grammarAdjacent(text, words[0], words[1])) {
    subjectIndex = 1;
  } else if (const {
    'weil',
    'wenn',
    'obwohl',
    'nachdem',
    'bevor',
    'falls',
    'während',
    'solange',
    'seitdem',
    'da',
    'bis',
  }.contains(words.first.lower)) {
    final commas = ','.allMatches(text).toList();
    if (commas.length != 1 ||
        words.length < 5 ||
        !_contextPronouns.contains(words[1].lower) ||
        !_grammarAdjacent(text, words[0], words[1])) {
      return;
    }
    final comma = commas.single.start;
    final before = words.lastIndexWhere((word) => word.end <= comma);
    if (before < 2 ||
        before > 12 ||
        before + 2 >= words.length ||
        text.substring(words[before].end, comma).trim().isNotEmpty ||
        text.substring(comma + 1, words[before + 1].start).trim().isNotEmpty) {
      return;
    }
    final finite = words[before];
    final paradigm = GermanWritingRulesProvider._presentByForm[finite.lower];
    final knownWeather =
        words[1].lower == 'es' &&
        before == 2 &&
        const {'regnet', 'schneit', 'stürmt'}.contains(finite.lower);
    if (!knownWeather &&
        (paradigm == null ||
            !_contextAgrees(paradigm, finite.lower, words[1].lower))) {
      return;
    }
    subjectIndex = before + 1;
  }
  if (subjectIndex < 0 || subjectIndex + 1 >= words.length) return;
  final subject = words[subjectIndex];
  final verb = words[subjectIndex + 1];
  if (!_contextPronouns.contains(subject.lower) ||
      subject.text != subject.lower ||
      verb.capitalized ||
      !_grammarAdjacent(text, subject, verb)) {
    return;
  }
  final paradigm = GermanWritingRulesProvider._presentByForm[verb.lower];
  if (paradigm == null ||
      !_contextAgrees(paradigm, verb.lower, subject.lower)) {
    return;
  }
  final gap = text.substring(subject.end, verb.start);
  yield _GermanGrammarIssue(
    'de.grammar.word-order',
    subject.start,
    verb.end,
    '${verb.text}$gap${subject.text}',
    'Nach diesem vorangestellten Satzglied steht im Hauptsatz normalerweise das finite Verb vor dem Subjekt.',
  );
}

// Independently authored common overregularizations; never synthesize a new
// participle. The licensed spelling provider still checks the original text.
const _contextParticiples = {
  'gelest': 'gelesen',
  'gegangt': 'gegangen',
  'gekommt': 'gekommen',
  'geschreibt': 'geschrieben',
  'getrinkt': 'getrunken',
  'gegesst': 'gegessen',
  'gefahrt': 'gefahren',
  'genehmt': 'genommen',
  'gesprecht': 'gesprochen',
  'getrefft': 'getroffen',
  'geseht': 'gesehen',
  'gefindet': 'gefunden',
  'gehelft': 'geholfen',
  'gebringt': 'gebracht',
  'geruft': 'gerufen',
};

Iterable<_GermanGrammarIssue> _contextParticiple(
  String text,
  List<_GermanGrammarWord> words,
) sync* {
  if (words.length < 3 ||
      !_contextPronouns.contains(words.first.lower) ||
      !_grammarAdjacent(text, words[0], words[1]) ||
      !const {
        'habe',
        'hast',
        'hat',
        'haben',
        'habt',
        'bin',
        'bist',
        'ist',
        'sind',
        'seid',
      }.contains(words[1].lower) ||
      words.last.capitalized) {
    return;
  }
  final replacement = _contextParticiples[words.last.lower];
  if (replacement == null) return;
  for (var i = 2; i < words.length; i++) {
    if (!_grammarAdjacent(text, words[i - 1], words[i]) ||
        const {
              'und',
              'oder',
              'dass',
              'das',
              'weil',
              'wenn',
              'zu',
            }.contains(words[i].lower) &&
            words[i].lower != 'das') {
      return;
    }
    if (i < words.length - 1 &&
        !words[i].capitalized &&
        GermanWritingRulesProvider._presentByForm.containsKey(words[i].lower)) {
      return;
    }
  }
  yield _GermanGrammarIssue(
    'de.grammar.participle',
    words.last.start,
    words.last.end,
    replacement,
    'Nach diesem Hilfsverb ist hier normalerweise dieses unregelmäßige Partizip gemeint.',
  );
}

// Restrict ambiguous dative/possessive "ihr" to a complete idiomatic
// haben + mass-object clause. No following subject or participle is allowed.
Iterable<_GermanGrammarIssue> _contextIhrHaben(
  String text,
  List<_GermanGrammarWord> words,
) sync* {
  if (words.length < 3 ||
      words.length > 4 ||
      words.first.lower != 'ihr' ||
      words[1].capitalized ||
      !const {'habe', 'hast', 'hat', 'haben'}.contains(words[1].lower) ||
      !const {
        'zeit',
        'geld',
        'arbeit',
        'hunger',
        'durst',
        'angst',
        'glück',
        'pech',
        'spaß',
      }.contains(words.last.lower) ||
      !words.last.capitalized ||
      words.length == 4 &&
          !const {'viel', 'wenig', 'genug', 'keine'}.contains(words[2].text)) {
    return;
  }
  for (var i = 1; i < words.length; i++) {
    if (!_grammarAdjacent(text, words[i - 1], words[i])) return;
  }
  yield _GermanGrammarIssue(
    'de.grammar.pronoun-verb',
    words[1].start,
    words[1].end,
    'habt',
    'In dieser vollständigen Verbindung mit „haben“ passt „habt“ zu „ihr“.',
  );
}

// Referential artifact heads admit the object relative pronoun "das".
// The finite list records independently authored neuter singular noun facts.
// Content-clause heads (Problem, Wissen, Tatsache, etc.) are deliberately
// excluded. Do not infer a relative clause from arbitrary nouns or verbs.
Iterable<_GermanGrammarIssue> _contextReferentialRelative(
  String text,
  List<_GermanGrammarWord> words,
) sync* {
  if (words.length < 7 || words.first.text != 'Das') return;
  final commas = ','.allMatches(text).toList();
  if (commas.length != 2) return;
  final head = _grammarNounIndex(text, words, 0);
  if (head == null || head > 4 || head + 5 >= words.length) return;
  final noun = words[head];
  if (!const {
    'buch',
    'haus',
    'auto',
    'dokument',
    'bild',
    'foto',
    'gerät',
    'fenster',
    'zimmer',
    'formular',
    'paket',
    'heft',
    'video',
    'rad',
  }.contains(noun.lower)) {
    return;
  }
  final relative = words[head + 1];
  final subject = words[head + 2];
  final finite = words[head + 3];
  final matrix = words[head + 4];
  if (relative.text != 'dass' ||
      subject.text != subject.lower ||
      finite.capitalized ||
      matrix.text != 'ist' ||
      text.substring(noun.end, relative.start).trim() != ',' ||
      commas[0].start < noun.end ||
      commas[0].start >= relative.start ||
      text.substring(finite.end, matrix.start).trim() != ',' ||
      commas[1].start < finite.end ||
      commas[1].start >= matrix.start ||
      !_grammarAdjacent(text, relative, subject) ||
      !_grammarAdjacent(text, subject, finite)) {
    return;
  }
  final paradigm = GermanWritingRulesProvider._presentByForm[finite.lower];
  if (paradigm == null ||
      !const {
        'lesen',
        'kennen',
        'sehen',
        'finden',
        'kaufen',
        'lieben',
        'mögen',
      }.contains(paradigm.infinitive) ||
      !_contextAgrees(paradigm, finite.lower, subject.lower)) {
    return;
  }
  yield _GermanGrammarIssue(
    'de.grammar.das-dass',
    relative.start,
    relative.end,
    'das',
    'Dieser begrenzte Relativsatz bezieht sich auf das vorangehende sächliche Dingwort.',
  );
}
