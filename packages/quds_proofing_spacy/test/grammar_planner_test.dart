// These annotations are deliberately synthetic planner controls. They are not
// native model results, held-out linguistic cases, or grammar-quality evidence.
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

const _subjectMorph = 'Case=Nom|Gender=Fem|Number=Plur';
const _verbMorph = 'Mood=Ind|Number=Sing|Person=3|Tense=Pres|VerbForm=Fin';
const _modifier = <_Spec>[
  _Spec('Die', 'DET', 'ART', 'nk', 1),
  _Spec('Katzen', 'NOUN', 'NN', 'sb', 4, morph: _subjectMorph, lemma: 'Katze'),
  _Spec('im', 'ADP', 'APPRART', 'mnr', 1),
  _Spec(
    'Garten',
    'NOUN',
    'NN',
    'nk',
    2,
    morph: 'Case=Dat|Gender=Masc|Number=Sing',
  ),
  _Spec(
    'schläft',
    'VERB',
    'VVFIN',
    'ROOT',
    4,
    morph: _verbMorph,
    lemma: 'schlafen',
  ),
  _Spec('.', 'PUNCT', r'$.', 'punct', 4),
];
const _inversion = <_Spec>[
  _Spec('Heute', 'ADV', 'ADV', 'mo', 1),
  _Spec(
    'schlafen',
    'VERB',
    'VVFIN',
    'ROOT',
    1,
    morph: 'Mood=Ind|Number=Plur|Person=3|Tense=Pres|VerbForm=Fin',
    lemma: 'schlafen',
  ),
  _Spec('die', 'DET', 'ART', 'nk', 3),
  _Spec(
    'Katze',
    'NOUN',
    'NN',
    'sb',
    1,
    morph: 'Case=Nom|Gender=Fem|Number=Sing',
    lemma: 'Katze',
  ),
  _Spec('.', 'PUNCT', r'$.', 'punct', 1),
];

({OfficeProofingRequest request, LinguisticAnalysisResult analysis}) _input(
  List<_Spec> specs, {
  int origin = 0,
  Set<String> ignored = const {},
  String nativeSha = spacyGrammarNativeSha256,
  int capabilityMask = 15,
  String? codeSha256,
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
        codeSha256: codeSha256,
      ),
      tokens: tokens,
    ),
  );
}

Future<SpacyGrammarPlan> _plan(
  List<_Spec> specs, {
  int origin = 0,
  Set<String> ignored = const {},
  Set<String> personal = const {},
}) {
  final input = _input(specs, origin: origin, ignored: ignored);
  return const SpacyGermanGrammarPlanner().plan(
    input.request,
    input.analysis,
    personalWords: personal,
  );
}

void main() {
  test('every qualified build gets the same proposal; others none', () async {
    expect(spacyGrammarNativeSha256s, contains(spacyGrammarNativeSha256));
    expect(spacyGrammarNativeSha256s, hasLength(2));
    for (final sha in spacyGrammarNativeSha256s) {
      final input = _input(_modifier, nativeSha: sha);
      final plan = await const SpacyGermanGrammarPlanner().plan(
        input.request,
        input.analysis,
      );
      expect(plan.result.status, OfficeProofingStatus.success);
      expect(plan.result.findings.single.originalText, 'schläft');
      expect(plan.result.findings.single.replacements, ['schlafen']);
    }
  });

  test(
    'a quotation blocks its middle sentence even without local quote tokens',
    () async {
      final specs = <_Spec>[const _Spec('„', 'PUNCT', r'$(', 'punct', 5)];
      for (var sentence = 0; sentence < 3; sentence++) {
        final offset = specs.length;
        for (final token in _modifier) {
          specs.add(
            _Spec(
              token.text,
              token.pos,
              token.tag,
              token.dep,
              token.head + offset,
              morph: token.morph,
              lemma: token.lemma,
            ),
          );
        }
      }
      specs.add(const _Spec('“', 'PUNCT', r'$(', 'punct', 17));
      final input = _input(specs, sentenceEnds: {6, 12});
      expect(input.analysis.sentences, hasLength(3));
      expect(input.analysis.sentences[1].text, 'Die Katzen im Garten schläft.');
      final plan = await const SpacyGermanGrammarPlanner().plan(
        input.request,
        input.analysis,
      );
      expect(plan.result.findings, isEmpty);
      expect(plan.decisions.single.reason, 'multiple-sentences');
    },
  );

  test('a single parsed quotation remains excluded', () async {
    final specs = <_Spec>[
      const _Spec('„', 'PUNCT', r'$(', 'punct', 5),
      for (final token in _modifier)
        _Spec(
          token.text,
          token.pos,
          token.tag,
          token.dep,
          token.head + 1,
          morph: token.morph,
          lemma: token.lemma,
        ),
      const _Spec('“', 'PUNCT', r'$(', 'punct', 5),
    ];
    final plan = await _plan(specs);
    expect(plan.result.findings, isEmpty);
    expect(plan.decisions.single.reason, 'quoted-context');
  });

  test('protected source ranges include the whole governing context', () async {
    final specs = <_Spec>[
      const _Spec('`', 'PUNCT', r'$(', 'punct', 5),
      for (final token in _modifier)
        _Spec(
          token.text,
          token.pos,
          token.tag,
          token.dep,
          token.head + 1,
          morph: token.morph,
          lemma: token.lemma,
        ),
      const _Spec('`', 'PUNCT', r'$(', 'punct', 5),
    ];
    final plan = await _plan(specs);
    expect(plan.result.findings, isEmpty);
    expect(plan.decisions.single.reason, 'protected-context');
  });

  test(
    'PP subject modifier proposes one reviewed edit at original origin',
    () async {
      final input = _input(_modifier, origin: 29);
      final plan = await const SpacyGermanGrammarPlanner().plan(
        input.request,
        input.analysis,
      );
      expect(plan.result.status, OfficeProofingStatus.success);
      final finding = plan.result.findings.single;
      expect(finding.providerId, spacyGrammarProviderId);
      expect(finding.ruleId, spacyNounVerbRuleId);
      expect(finding.originalText, 'schläft');
      expect(finding.replacements, ['schlafen']);
      expect(finding.start, 29 + input.request.text.indexOf('schläft'));
      expect(finding.end, finding.start + 'schläft'.length);
      expect(plan.decisions.single.action, 'proposed');
      expect(
        plan.decisions.single.evidence['construction'],
        'subject-prepositional-modifier',
      );
      expect(input.request.text, 'Die Katzen im Garten schläft.');
      expect(() => plan.decisions.clear(), throwsUnsupportedError);
      expect(
        () => plan.decisions.single.evidence.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('adverbial inversion uses the licensed singular target', () async {
    final plan = await _plan(_inversion);
    expect(plan.result.findings.single.replacements, ['schläft']);
    expect(
      plan.decisions.single.evidence['construction'],
      'adverbial-inversion',
    );
  });

  test(
    'quantity heads do not force lexical singular onto semantic agreement',
    () async {
      final specs = <_Spec>[
        const _Spec('Eine', 'DET', 'ART', 'nk', 1),
        const _Spec(
          'Reihe',
          'NOUN',
          'NN',
          'sb',
          4,
          morph: 'Case=Nom|Gender=Fem|Number=Sing',
          lemma: 'Reihe',
        ),
        const _Spec('von', 'ADP', 'APPR', 'mnr', 1),
        const _Spec(
          'Studenten',
          'NOUN',
          'NN',
          'nk',
          2,
          morph: 'Case=Dat|Gender=Masc|Number=Plur',
          lemma: 'Student',
        ),
        const _Spec(
          'kommen',
          'VERB',
          'VVFIN',
          'ROOT',
          4,
          morph: 'Mood=Ind|Number=Plur|Person=3|Tense=Pres|VerbForm=Fin',
          lemma: 'kommen',
        ),
        const _Spec('.', 'PUNCT', r'$.', 'punct', 4),
      ];
      final plan = await _plan(specs);
      expect(plan.result.findings, isEmpty);
      expect(plan.decisions.single.reason, 'unsupported-collective-agreement');
    },
  );

  test('valid source is preserved and correctly rechecked', () async {
    final specs = [..._modifier];
    specs[4] = const _Spec(
      'schlafen',
      'VERB',
      'VVFIN',
      'ROOT',
      4,
      morph: 'Mood=Ind|Number=Plur|Person=3|Tense=Pres|VerbForm=Fin',
      lemma: 'schlafen',
    );
    final plan = await _plan(specs);
    expect(plan.result.findings, isEmpty);
    expect(plan.decisions.single.reason, 'compatible-lexical-reading');
  });

  test(
    'productive von/vom phrases stay outside mechanical agreement',
    () async {
      for (final preposition in ['von', 'vom']) {
        final specs = [..._modifier];
        specs[2] = _Spec(
          preposition,
          'ADP',
          preposition == 'vom' ? 'APPRART' : 'APPR',
          'mnr',
          1,
        );
        specs[3] = _modifier[3].withText('Nachbarn');
        final plan = await _plan(specs);
        expect(plan.result.findings, isEmpty);
        expect(plan.decisions.single.reason, 'unsupported-partitive-context');
      }
    },
  );

  test('all noun alternatives veto a false Leiter correction', () async {
    final specs = [..._modifier];
    specs[1] = _modifier[1].withText('Leiter');
    specs[4] = const _Spec(
      'steht',
      'VERB',
      'VVFIN',
      'ROOT',
      4,
      morph: _verbMorph,
      lemma: 'stehen',
    );
    final plan = await _plan(specs);
    expect(plan.result.findings, isEmpty);
    expect(plan.decisions.single.action, 'preserved');
    expect(plan.decisions.single.reason, 'compatible-lexical-reading');
  });

  test(
    'model-selected number cannot override licensed subject number',
    () async {
      final specs = [..._modifier];
      specs[1] = const _Spec(
        'Katzen',
        'NOUN',
        'NN',
        'sb',
        4,
        morph: 'Case=Nom|Gender=Fem|Number=Sing',
        lemma: 'Katze',
      );
      final plan = await _plan(specs);
      expect(plan.result.findings, isEmpty);
      expect(plan.decisions.single.reason, 'model-lexicon-number-disagreement');
    },
  );

  test('unknown and personal words cause explicit abstention', () async {
    final specs = [..._modifier];
    specs[1] = _modifier[1].withText('Qudsbrand');
    final unknown = await _plan(specs);
    expect(unknown.result.findings, isEmpty);
    expect(unknown.decisions.single.reason, 'unknown-noun');
    final personal = await _plan(_modifier, personal: {'Garten'});
    expect(personal.result.findings, isEmpty);
    expect(personal.decisions.single.reason, 'personal-vocabulary');
  });

  test(
    'provider and existing noun-verb ignore IDs suppress the actual proposal',
    () async {
      for (final ignored in [
        {spacyNounVerbRuleId},
        {'de.grammar.noun-verb'},
      ]) {
        final plan = await _plan(_modifier, ignored: ignored);
        expect(plan.result.findings, isEmpty);
        expect(plan.decisions.single.reason, 'ignored-rule');
        expect(plan.decisions.single.action, 'suppressed');
        expect(plan.decisions.single.evidence['replacement'], 'schlafen');
      }
    },
  );

  test(
    'wrong lemma, mood, person and root shape never generate forms',
    () async {
      for (final verb in [
        const _Spec(
          'schläft',
          'VERB',
          'VVFIN',
          'ROOT',
          4,
          morph: _verbMorph,
          lemma: 'spielen',
        ),
        const _Spec(
          'schläft',
          'VERB',
          'VVIMP',
          'ROOT',
          4,
          morph: 'Mood=Imp|VerbForm=Fin',
          lemma: 'schlafen',
        ),
        const _Spec(
          'schläft',
          'VERB',
          'VVFIN',
          'ROOT',
          4,
          morph: 'Mood=Sub|Person=3|Tense=Pres|VerbForm=Fin',
          lemma: 'schlafen',
        ),
        const _Spec(
          'schläft',
          'VERB',
          'VVFIN',
          'ROOT',
          4,
          morph: 'Mood=Ind|Person=2|Tense=Pres|VerbForm=Fin',
          lemma: 'schlafen',
        ),
      ]) {
        final specs = [..._modifier];
        specs[4] = verb;
        expect((await _plan(specs)).result.findings, isEmpty);
      }
    },
  );

  test(
    'fronted object or extra nominal phrase cannot become a false subject',
    () async {
      final specs = <_Spec>[
        const _Spec('Die', 'DET', 'ART', 'nk', 1),
        const _Spec('Katzen', 'NOUN', 'NN', 'sb', 2, morph: _subjectMorph),
        const _Spec(
          'sieht',
          'VERB',
          'VVFIN',
          'ROOT',
          2,
          morph: _verbMorph,
          lemma: 'sehen',
        ),
        const _Spec('der', 'DET', 'ART', 'nk', 4),
        const _Spec(
          'Mann',
          'NOUN',
          'NN',
          'oa',
          2,
          morph: 'Case=Acc|Number=Sing',
        ),
        const _Spec('.', 'PUNCT', r'$.', 'punct', 2),
      ];
      // The synthetic parser deliberately swaps subject/object, as an adverse
      // analysis might. Surface ownership still blocks the wrong replacement.
      expect((await _plan(specs)).result.findings, isEmpty);
    },
  );

  test(
    'coordination, pronouns, names and unknown PP nouns are excluded',
    () async {
      for (final replacement in [
        const _Spec('Anna', 'PROPN', 'NE', 'sb', 4, morph: _subjectMorph),
        const _Spec('sie', 'PRON', 'PPER', 'sb', 4, morph: _subjectMorph),
        const _Spec('Katzen', 'NOUN', 'NN', 'cj', 4, morph: _subjectMorph),
      ]) {
        final specs = [..._modifier];
        specs[1] = replacement;
        expect((await _plan(specs)).result.findings, isEmpty);
      }
      final unknown = [..._modifier];
      unknown[3] = _modifier[3].withText('Qudsbrand');
      expect(
        (await _plan(unknown)).decisions.single.reason,
        'unknown-prepositional-noun',
      );
    },
  );

  test(
    'source identity and exact accepted native identity are mandatory',
    () async {
      final input = _input(_modifier);
      for (final wrong in [
        OfficeProofingRequest(
          documentId: 'other',
          blockId: input.request.blockId,
          revision: 7,
          text: input.request.text,
        ),
        OfficeProofingRequest(
          documentId: input.request.documentId,
          blockId: input.request.blockId,
          revision: 8,
          text: input.request.text,
        ),
        OfficeProofingRequest(
          documentId: input.request.documentId,
          blockId: input.request.blockId,
          revision: 7,
          text: input.request.text,
          startOffset: 1,
        ),
      ]) {
        final plan = await const SpacyGermanGrammarPlanner().plan(
          wrong,
          input.analysis,
        );
        expect(plan.result.status, OfficeProofingStatus.failed);
        expect(plan.decisions.single.reason, 'snapshot-mismatch');
      }
      final other = _input(_modifier, nativeSha: 'a' * 64);
      expect(
        (await const SpacyGermanGrammarPlanner().plan(
          other.request,
          other.analysis,
        )).decisions.single.reason,
        'runtime-mismatch',
      );
      // Grammar is qualified without named entities: a qualified build with
      // NER attached (capability mask 31) is a different runtime profile.
      for (final sha in spacyGrammarNativeSha256s) {
        final withNer = _input(_modifier, nativeSha: sha, capabilityMask: 31);
        expect(
          (await const SpacyGermanGrammarPlanner().plan(
            withNer.request,
            withNer.analysis,
          )).decisions.single.reason,
          'runtime-mismatch',
        );
      }
    },
  );

  test(
    'a re-signed host-bundled copy qualifies only by its measured code digest',
    () async {
      // Re-signing the qualified macOS library with a release identity
      // changes its file digest but not its code digest.
      final resigned = _input(
        _modifier,
        nativeSha: 'b' * 64,
        codeSha256: spacyGrammarMacosBundledCodeSha256,
      );
      final plan = await const SpacyGermanGrammarPlanner().plan(
        resigned.request,
        resigned.analysis,
      );
      expect(plan.result.status, OfficeProofingStatus.success);
      expect(plan.result.findings.single.replacements, ['schlafen']);
      // The exact qualified bytes still qualify with their code digest.
      final exact = _input(
        _modifier,
        nativeSha: spacyGrammarMacosBundledSha256,
        codeSha256: spacyGrammarMacosBundledCodeSha256,
      );
      expect(
        (await const SpacyGermanGrammarPlanner().plan(
          exact.request,
          exact.analysis,
        )).result.findings,
        hasLength(1),
      );
      // Different code, a missing code digest, or the unsigned-file digest
      // used as a code digest are all refused.
      for (final code in [
        'c' * 64,
        null,
        spacyGrammarMacosBundledUnsignedSha256,
      ]) {
        final other = _input(_modifier, nativeSha: 'b' * 64, codeSha256: code);
        expect(
          (await const SpacyGermanGrammarPlanner().plan(
            other.request,
            other.analysis,
          )).decisions.single.reason,
          'runtime-mismatch',
        );
      }
      // The capability profile is still enforced for re-signed copies.
      final withNer = _input(
        _modifier,
        nativeSha: 'b' * 64,
        codeSha256: spacyGrammarMacosBundledCodeSha256,
        capabilityMask: 31,
      );
      expect(
        (await const SpacyGermanGrammarPlanner().plan(
          withNer.request,
          withNer.analysis,
        )).decisions.single.reason,
        'runtime-mismatch',
      );
      expect(spacyGrammarCodeSha256s, {spacyGrammarMacosBundledCodeSha256});
    },
  );

  test('regional and historical locales remain unsupported', () async {
    final input = _input(_modifier);
    for (final locale in ['de-AT', 'de-CH', 'de-DE-1901', 'en-US']) {
      final request = OfficeProofingRequest(
        documentId: input.request.documentId,
        blockId: input.request.blockId,
        revision: 7,
        text: input.request.text,
        language: locale,
      );
      final plan = await const SpacyGermanGrammarPlanner().plan(
        request,
        input.analysis,
      );
      expect(plan.result.status, OfficeProofingStatus.unsupported);
      expect(plan.result.findings, isEmpty);
    }
  });

  test(
    'analysis failure remains an operational failure, not no grammar errors',
    () async {
      final input = _input(_modifier);
      final unavailable = LinguisticAnalysisResult.failure(
        request: input.analysis.request,
        status: LinguisticAnalysisStatus.unavailable,
        message: 'No native asset for this synthetic control.',
      );
      final plan = await const SpacyGermanGrammarPlanner().plan(
        input.request,
        unavailable,
      );
      expect(plan.result.status, OfficeProofingStatus.unavailable);
      expect(plan.result.findings, isEmpty);
      expect(plan.decisions.single.reason, 'analysis-unavailable');
    },
  );

  test(
    'the host merge keeps deterministic findings at a duplicate span',
    () async {
      final input = _input(_modifier);
      final plan = await const SpacyGermanGrammarPlanner().plan(
        input.request,
        input.analysis,
      );
      final model = plan.result.findings.single;
      final primary = OfficeProofingFinding.forRequest(
        input.request,
        providerId: 'german-writing',
        start: model.start,
        end: model.end,
        ruleId: 'de.grammar.noun-verb',
        message: 'Deterministic finding.',
        category: OfficeProofingCategory.grammar,
        replacements: model.replacements,
      );
      final merged = mergeOfficeProofingReports(
        primary: OfficeProofingReport(
          request: input.request,
          results: [
            OfficeProofingResult(
              request: input.request,
              providerId: 'german-writing',
              status: OfficeProofingStatus.success,
              findings: [primary],
            ),
          ],
        ),
        secondary: OfficeProofingReport(
          request: input.request,
          results: [plan.result],
        ),
      );
      expect(merged.findings, [primary]);
      expect(merged.results.last.findings, isEmpty);
    },
  );
}
