// Synthetic planner controls for the grammar v2 families. Annotations copy the
// shape of real de_core_news_sm parses of authored development sentences;
// they are not qualification evidence (see
// docs/validation/native-spacy-grammar-v2-20261120).
import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';
import 'package:quds_proofing_spacy/src/grammar_planner.dart';
import 'package:test/test.dart';

final class _Spec {
  const _Spec(
    this.text,
    this.pos,
    this.tag,
    this.dep,
    this.head, {
    this.morph = '',
    this.lemma,
  });
  final String text;
  final String pos;
  final String tag;
  final String dep;
  final int head;
  final String morph;
  final String? lemma;

  _Spec withText(String value) =>
      _Spec(value, pos, tag, dep, head, morph: morph, lemma: lemma);
}

({OfficeProofingRequest request, LinguisticAnalysisResult analysis}) _input(
  List<_Spec> specs, {
  int origin = 0,
  Set<String> ignored = const {},
  String nativeSha = spacyGrammarNativeSha256,
  int capabilityMask = 15,
  Set<int> sentenceEnds = const {},
}) {
  final buffer = StringBuffer();
  final tokens = <LinguisticToken>[];
  var byteAt = 0;
  var scalarAt = 0;
  for (var index = 0; index < specs.length; index++) {
    final spec = specs[index];
    final start = buffer.length;
    buffer.write(spec.text);
    final end = buffer.length;
    final byteEnd = byteAt + utf8.encode(spec.text).length;
    final scalarEnd = scalarAt + spec.text.runes.length;
    final space =
        index + 1 < specs.length &&
        specs[index + 1].pos != 'PUNCT' &&
        !const {'„', '«', '`'}.contains(spec.text);
    tokens.add(
      LinguisticToken(
        index: index,
        text: spec.text,
        byteStart: byteAt,
        byteEnd: byteEnd,
        scalarStart: scalarAt,
        scalarEnd: scalarEnd,
        start: start,
        end: end,
        lemma: spec.lemma ?? spec.text.toLowerCase(),
        tag: spec.tag,
        pos: spec.pos,
        morphology: spec.morph,
        dependency: spec.dep,
        head: spec.head,
        sentenceStart: index == 0 || sentenceEnds.contains(index - 1),
        sentenceEnd: index == specs.length - 1 || sentenceEnds.contains(index),
        spaceAfter: space,
      ),
    );
    if (space) buffer.write(' ');
    byteAt = byteEnd + (space ? 1 : 0);
    scalarAt = scalarEnd + (space ? 1 : 0);
  }
  final request = OfficeProofingRequest(
    documentId: 'planner-control',
    blockId: 'body:1',
    revision: 7,
    text: buffer.toString(),
    startOffset: origin,
    ignoredRuleIds: ignored,
  );
  return (
    request: request,
    analysis: LinguisticAnalysisResult.success(
      request: LinguisticAnalysisRequest(
        documentId: request.documentId,
        blockId: request.blockId,
        revision: request.revision,
        text: request.text,
        startOffset: origin,
      ),
      identity: SpacyBackendIdentity(
        librarySha256: nativeSha,
        capabilityMask: capabilityMask,
      ),
      tokens: tokens,
    ),
  );
}

const _all = {
  SpacyGrammarFamily.nounVerb,
  SpacyGrammarFamily.nounPhraseAgreement,
  SpacyGrammarFamily.prepositionCase,
  SpacyGrammarFamily.subjectPerson,
  SpacyGrammarFamily.verbPosition,
};

Future<SpacyGrammarPlan> _plan(
  List<_Spec> specs, {
  Set<SpacyGrammarFamily> families = _all,
  Set<String> ignored = const {},
  bool english = false,
}) {
  final input = _input(specs, origin: 12, ignored: ignored);
  return SpacyGermanGrammarPlanner(
    families: families,
    englishMessages: english,
  ).plan(input.request, input.analysis);
}

String _apply(SpacyGrammarPlan plan) {
  var text = plan.result.request.text;
  final origin = plan.result.request.startOffset;
  final findings = [...plan.result.findings]
    ..sort((a, b) => b.start.compareTo(a.start));
  for (final f in findings) {
    text = text.replaceRange(
      f.start - origin,
      f.end - origin,
      f.replacements.single,
    );
  }
  return text;
}

const _nom = 'Case=Nom|Number=Sing|Person=1|PronType=Prs';
const _fin = 'Mood=Ind|Number=Sing|Person=3|Tense=Pres|VerbForm=Fin';

// Die Haus steht am Ende der Straße.
const _dieHaus = <_Spec>[
  _Spec(
    'Die',
    'DET',
    'ART',
    'nk',
    1,
    lemma: 'der',
    morph: 'Case=Nom|Definite=Def|Gender=Fem|Number=Sing|PronType=Art',
  ),
  _Spec(
    'Haus',
    'NOUN',
    'NN',
    'sb',
    2,
    morph: 'Case=Nom|Gender=Neut|Number=Sing',
  ),
  _Spec('steht', 'VERB', 'VVFIN', 'ROOT', 2, lemma: 'stehen', morph: _fin),
  _Spec('am', 'ADP', 'APPRART', 'mo', 2),
  _Spec(
    'Ende',
    'NOUN',
    'NN',
    'nk',
    3,
    morph: 'Case=Dat|Gender=Neut|Number=Sing',
  ),
  _Spec('der', 'DET', 'ART', 'nk', 6, lemma: 'der'),
  _Spec(
    'Straße',
    'NOUN',
    'NN',
    'ag',
    4,
    morph: 'Case=Gen|Gender=Fem|Number=Sing',
  ),
  _Spec('.', 'PUNCT', r'$.', 'punct', 2),
];

// Sie geht zu der Arzt.
const _zuDerArzt = <_Spec>[
  _Spec(
    'Sie',
    'PRON',
    'PPER',
    'sb',
    1,
    morph: 'Case=Nom|Gender=Fem|Number=Sing|Person=3|PronType=Prs',
  ),
  _Spec('geht', 'VERB', 'VVFIN', 'ROOT', 1, lemma: 'gehen', morph: _fin),
  _Spec('zu', 'ADP', 'APPR', 'op', 1),
  _Spec('der', 'DET', 'ART', 'nk', 4, lemma: 'der'),
  _Spec(
    'Arzt',
    'NOUN',
    'NN',
    'nk',
    2,
    morph: 'Case=Nom|Gender=Masc|Number=Sing',
  ),
  _Spec('.', 'PUNCT', r'$.', 'punct', 1),
];

// Er sagt, dass ich heute lange arbeitet.
const _dassIch = <_Spec>[
  _Spec(
    'Er',
    'PRON',
    'PPER',
    'sb',
    1,
    morph: 'Case=Nom|Gender=Masc|Number=Sing|Person=3|PronType=Prs',
  ),
  _Spec('sagt', 'VERB', 'VVFIN', 'ROOT', 1, lemma: 'sagen', morph: _fin),
  _Spec(',', 'PUNCT', r'$,', 'punct', 1),
  _Spec('dass', 'SCONJ', 'KOUS', 'cp', 7),
  _Spec('ich', 'PRON', 'PPER', 'sb', 7, morph: _nom),
  _Spec('heute', 'ADV', 'ADV', 'mo', 7),
  _Spec('lange', 'ADV', 'ADV', 'mo', 7),
  _Spec('arbeitet', 'VERB', 'VVFIN', 'oc', 1, lemma: 'arbeiten', morph: _fin),
  _Spec('.', 'PUNCT', r'$.', 'punct', 1),
];

// Ich weiß, dass er hat keine Zeit.
const _dassHat = <_Spec>[
  _Spec('Ich', 'PRON', 'PPER', 'sb', 1, morph: _nom),
  _Spec(
    'weiß',
    'VERB',
    'VVFIN',
    'ROOT',
    1,
    lemma: 'wissen',
    morph: 'Mood=Ind|Number=Sing|Person=1|Tense=Pres|VerbForm=Fin',
  ),
  _Spec(',', 'PUNCT', r'$,', 'punct', 1),
  _Spec('dass', 'SCONJ', 'KOUS', 'cp', 5),
  _Spec(
    'er',
    'PRON',
    'PPER',
    'sb',
    5,
    morph: 'Case=Nom|Gender=Masc|Number=Sing|Person=3|PronType=Prs',
  ),
  _Spec('hat', 'VERB', 'VAFIN', 'oc', 1, lemma: 'haben', morph: _fin),
  _Spec('keine', 'DET', 'PIAT', 'nk', 7, lemma: 'kein'),
  _Spec(
    'Zeit',
    'NOUN',
    'NN',
    'oa',
    5,
    morph: 'Case=Acc|Gender=Fem|Number=Sing',
  ),
  _Spec('.', 'PUNCT', r'$.', 'punct', 1),
];

// Heute ich gehe ins Kino.
const _heuteIch = <_Spec>[
  _Spec('Heute', 'ADV', 'ADV', 'mo', 2),
  _Spec('ich', 'PRON', 'PPER', 'sb', 2, morph: _nom),
  _Spec(
    'gehe',
    'VERB',
    'VVFIN',
    'ROOT',
    2,
    lemma: 'gehen',
    morph: 'Mood=Ind|Number=Sing|Person=1|Tense=Pres|VerbForm=Fin',
  ),
  _Spec('ins', 'ADP', 'APPRART', 'mo', 2),
  _Spec(
    'Kino',
    'NOUN',
    'NN',
    'nk',
    3,
    morph: 'Case=Acc|Gender=Neut|Number=Sing',
  ),
  _Spec('.', 'PUNCT', r'$.', 'punct', 2),
];

// Meine Kollegin und ich bereiten die Präsentation vor. (misparsed: only
// "ich" is the subject of the coordinated verb)
const _kolleginUndIch = <_Spec>[
  _Spec('Meine', 'DET', 'PPOSAT', 'nk', 1),
  _Spec('Kollegin', 'NOUN', 'NN', 'ROOT', 1),
  _Spec('und', 'CCONJ', 'KON', 'cd', 1),
  _Spec('ich', 'PRON', 'PPER', 'sb', 4, morph: _nom),
  _Spec(
    'bereiten',
    'VERB',
    'VVFIN',
    'cj',
    2,
    lemma: 'bereiten',
    morph: 'Mood=Ind|Number=Plur|Person=3|Tense=Pres|VerbForm=Fin',
  ),
  _Spec('die', 'DET', 'ART', 'nk', 6),
  _Spec('Präsentation', 'NOUN', 'NN', 'oa', 4),
  _Spec('vor', 'ADP', 'PTKVZ', 'svp', 4),
  _Spec('.', 'PUNCT', r'$.', 'punct', 1),
];

void main() {
  test('a coordinated "X und ich" subject is never adjudicated', () async {
    final plan = await _plan(_kolleginUndIch);
    expect(plan.result.findings, isEmpty);
    expect(
      plan.decisions.map((d) => d.reason),
      contains('possible-coordinated-subject'),
    );
  });

  test(
    'the default planner keeps the original noun/verb family only',
    () async {
      for (final specs in [
        _dieHaus,
        _zuDerArzt,
        _dassIch,
        _dassHat,
        _heuteIch,
      ]) {
        final input = _input(specs);
        final plan = await const SpacyGermanGrammarPlanner().plan(
          input.request,
          input.analysis,
        );
        expect(plan.result.findings, isEmpty);
        expect(
          plan.decisions.every((d) => !d.evidence.containsKey('family')),
          isTrue,
        );
      }
    },
  );

  test(
    'noun-phrase agreement corrects the article from lexical gender',
    () async {
      final plan = await _plan(_dieHaus);
      final finding = plan.result.findings.single;
      expect(finding.ruleId, 'de.spacy.np-agreement');
      expect(finding.originalText, 'Die');
      expect(_apply(plan), 'Das Haus steht am Ende der Straße.');
    },
  );

  test('case after a fixed-case preposition contracts the article', () async {
    final plan = await _plan(_zuDerArzt);
    expect(plan.result.findings.single.ruleId, 'de.spacy.preposition-case');
    expect(_apply(plan), 'Sie geht zum Arzt.');
  });

  test('subject person is checked across a subordinate clause', () async {
    final plan = await _plan(_dassIch);
    expect(plan.result.findings.single.ruleId, 'de.spacy.subject-person');
    expect(_apply(plan), 'Er sagt, dass ich heute lange arbeite.');
  });

  test('verb-second in a dass clause moves the finite verb last', () async {
    final plan = await _plan(_dassHat);
    expect(plan.result.findings.single.ruleId, 'de.spacy.verb-position');
    expect(_apply(plan), 'Ich weiß, dass er keine Zeit hat.');
  });

  test('verb-third after a fronted adverb swaps subject and verb', () async {
    final plan = await _plan(_heuteIch);
    expect(plan.result.findings.single.ruleId, 'de.spacy.verb-position');
    expect(_apply(plan), 'Heute gehe ich ins Kino.');
  });

  test('a disabled family proposes nothing', () async {
    final plan = await _plan(
      _dassIch,
      families: _all.difference({SpacyGrammarFamily.subjectPerson}),
    );
    expect(plan.result.findings, isEmpty);
  });

  test('the new and the matching deterministic rule IDs suppress', () async {
    for (final ignored in [
      'de.spacy.subject-person',
      'de.grammar.pronoun-verb',
    ]) {
      final plan = await _plan(_dassIch, ignored: {ignored});
      expect(plan.result.findings, isEmpty);
      expect(plan.decisions.any((d) => d.action == 'suppressed'), isTrue);
    }
  });

  test('explanations follow the host UI language', () async {
    final german = await _plan(_dassHat);
    final english = await _plan(_dassHat, english: true);
    expect(
      german.result.findings.single.message,
      SpacyGrammarFamily.verbPosition.explanationDe,
    );
    expect(
      english.result.findings.single.message,
      SpacyGrammarFamily.verbPosition.explanationEn,
    );
    expect(
      english.result.findings.single.replacements,
      german.result.findings.single.replacements,
    );
  });

  test('a weil clause with verb-second is never reordered', () async {
    final specs = [
      for (final s in _dassHat) s.text == 'dass' ? s.withText('weil') : s,
    ];
    final plan = await _plan(specs);
    expect(plan.result.findings, isEmpty);
  });

  test('family IDs, rule IDs and labels are stable and unique', () {
    expect(
      SpacyGrammarFamily.values.map((f) => f.ruleId).toSet(),
      hasLength(SpacyGrammarFamily.values.length),
    );
    for (final family in SpacyGrammarFamily.values) {
      expect(SpacyGrammarFamily.byId(family.id), family);
      expect(SpacyGrammarFamily.byId(family.ruleId), family);
      expect(family.labelDe, isNotEmpty);
      expect(family.labelEn, isNotEmpty);
      expect(
        spacyGrammarExplanation(family.ruleId, english: true),
        family.explanationEn,
      );
    }
  });
}
