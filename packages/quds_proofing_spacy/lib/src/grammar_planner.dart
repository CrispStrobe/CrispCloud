import 'package:quds_office_engine/quds_office_engine.dart'
    show
        GermanAgreementFacts,
        GermanLiteralTextRanges,
        normalizeGermanWord,
        OfficeProofingCategory,
        OfficeProofingFinding,
        OfficeProofingRequest,
        OfficeProofingResult,
        OfficeProofingStatus,
        OfficeProofingTextRanges;

import 'analysis.dart';
import 'backend.dart';
import 'distribution.dart' show spacyGrammarMacosBundledSha256;

const spacyGrammarProviderId = 'spacy-german-grammar';
const spacyNounVerbRuleId = 'de.spacy.noun-verb';

/// The Linux x86-64/AVX2 build that first qualified this grammar candidate
/// (sealed W6 panel and W7 extension panel).
const spacyGrammarNativeSha256 =
    'ea89842ebf22c08508aff1cfbf18d78a107118af320523009616ff62b6e42977';

/// Every exact native build with recorded manual grammar qualification: the
/// Linux build above and the app-bundled macOS arm64 library
/// ([spacyGrammarMacosBundledSha256], qualified by replaying both consumed
/// panels with annotations and outcomes identical case by case).
/// Analysis may support other authenticated builds independently; grammar
/// never silently inherits a qualification. Each entry needs its own
/// evidence record in `spacyQualificationFor`.
const spacyGrammarNativeSha256s = <String>{
  spacyGrammarNativeSha256,
  spacyGrammarMacosBundledSha256,
};

final class SpacyGrammarDecision {
  SpacyGrammarDecision({
    required this.sentenceIndex,
    required this.start,
    required this.end,
    required this.action,
    required this.reason,
    Iterable<int> tokenIndices = const [],
    Map<String, Object?> evidence = const {},
  }) : tokenIndices = List<int>.unmodifiable(tokenIndices),
       evidence = _freezeMap(evidence);

  final int sentenceIndex;
  final int start;
  final int end;
  final String action;
  final String reason;
  final List<int> tokenIndices;
  final Map<String, Object?> evidence;

  Map<String, Object?> toJson() => {
    'sentence_index': sentenceIndex,
    'start_utf16': start,
    'end_utf16': end,
    'action': action,
    'reason': reason,
    'token_indices': tokenIndices,
    'evidence': evidence,
  };
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) =>
    Map<String, Object?>.unmodifiable({
      for (final entry in value.entries) entry.key: _freezeJson(entry.value),
    });

Object? _freezeJson(Object? value) {
  if (value is Map<String, Object?>) return _freezeMap(value);
  if (value is List) return List<Object?>.unmodifiable(value.map(_freezeJson));
  return value;
}

final class SpacyGrammarPlan {
  SpacyGrammarPlan({
    required this.result,
    required Iterable<SpacyGrammarDecision> decisions,
  }) : decisions = List<SpacyGrammarDecision>.unmodifiable(decisions);

  final OfficeProofingResult result;
  final List<SpacyGrammarDecision> decisions;
}

/// A pure Dart, explicit planner; it performs no inference and registers no
/// provider. It only proposes third-person present noun/verb agreement for a
/// closed single-sentence declarative subset with a reviewed finite root and one
/// licensed common-noun subject. The subject may have a bounded PP modifier,
/// or follow an approved initial adverb and finite verb. Ordinary subject-first
/// clauses remain admissible so the host can apply deterministic precedence.
///
/// Bare additional nominal phrases, coordination, pronouns, relatives,
/// subordinate clauses, quotations, quantity heads, von/vom phrases,
/// other moods/tenses, unknown nouns and
/// unresolved lexical readings cause abstention. This is not a general German
/// grammar checker, and a model-selected reading never erases alternatives.
final class SpacyGermanGrammarPlanner {
  const SpacyGermanGrammarPlanner();

  Future<SpacyGrammarPlan> plan(
    OfficeProofingRequest request,
    LinguisticAnalysisResult analysis, {
    Set<String> personalWords = const {},
  }) async {
    SpacyGrammarPlan unavailable(OfficeProofingStatus status, String reason) =>
        SpacyGrammarPlan(
          result: OfficeProofingResult(
            request: request,
            providerId: spacyGrammarProviderId,
            status: status,
            message: reason,
          ),
          decisions: [
            SpacyGrammarDecision(
              sentenceIndex: -1,
              start: 0,
              end: request.text.length,
              action: status == OfficeProofingStatus.unsupported
                  ? 'unsupported'
                  : 'failed',
              reason: reason,
            ),
          ],
        );

    if (request.language != 'de-DE') {
      return unavailable(
        OfficeProofingStatus.unsupported,
        'unsupported-locale',
      );
    }
    final source = analysis.request;
    if (source.text != request.text ||
        source.documentId != request.documentId ||
        source.blockId != request.blockId ||
        source.revision != request.revision ||
        source.locale != request.language ||
        source.startOffset != request.startOffset) {
      return unavailable(OfficeProofingStatus.failed, 'snapshot-mismatch');
    }
    if (!analysis.isSuccess) {
      return unavailable(switch (analysis.status) {
        LinguisticAnalysisStatus.unavailable =>
          OfficeProofingStatus.unavailable,
        LinguisticAnalysisStatus.unsupported =>
          OfficeProofingStatus.unsupported,
        _ => OfficeProofingStatus.failed,
      }, 'analysis-${analysis.status.name}');
    }
    final identity = analysis.identity;
    if (identity == null ||
        !spacyGrammarNativeSha256s.contains(identity.librarySha256) ||
        identity !=
            SpacyBackendIdentity(librarySha256: identity.librarySha256)) {
      return unavailable(OfficeProofingStatus.failed, 'runtime-mismatch');
    }
    if (analysis.sentences.length > 1) {
      return SpacyGrammarPlan(
        result: OfficeProofingResult(
          request: request,
          providerId: spacyGrammarProviderId,
          status: OfficeProofingStatus.success,
        ),
        decisions: [
          SpacyGrammarDecision(
            sentenceIndex: -1,
            start: 0,
            end: request.text.length,
            action: 'abstained',
            reason: 'multiple-sentences',
          ),
        ],
      );
    }
    final vocabulary = Set<String>.unmodifiable(
      personalWords.map((word) => normalizeGermanWord(word).toLowerCase()),
    );
    final protected = OfficeProofingTextRanges(request.text);
    final literals = GermanLiteralTextRanges(request.text);
    // Retain paragraph-wide protection even when the parser assigns quotation
    // punctuation outside its one selected sentence. Multi-sentence requests
    // are separately outside this candidate's structural scope.
    final quotedContext = _quoteCharacters.hasMatch(request.text);
    final decisions = <SpacyGrammarDecision>[];
    final findings = <OfficeProofingFinding>[];
    for (var index = 0; index < analysis.sentences.length; index++) {
      final sentence = analysis.sentences[index];
      final outcome = await _sentence(
        request,
        analysis,
        sentence,
        index,
        vocabulary,
        protected,
        literals,
        quotedContext,
      );
      decisions.add(outcome.decision);
      if (outcome.finding != null) findings.add(outcome.finding!);
    }
    if (analysis.sentences.isEmpty) {
      decisions.add(
        SpacyGrammarDecision(
          sentenceIndex: -1,
          start: 0,
          end: request.text.length,
          action: 'abstained',
          reason: 'empty-input',
        ),
      );
    }
    return SpacyGrammarPlan(
      result: OfficeProofingResult(
        request: request,
        providerId: spacyGrammarProviderId,
        status: OfficeProofingStatus.success,
        findings: findings,
      ),
      decisions: decisions,
    );
  }

  Future<({SpacyGrammarDecision decision, OfficeProofingFinding? finding})>
  _sentence(
    OfficeProofingRequest request,
    LinguisticAnalysisResult analysis,
    LinguisticSentence sentence,
    int sentenceIndex,
    Set<String> personalWords,
    OfficeProofingTextRanges protected,
    GermanLiteralTextRanges literals,
    bool quotedContext,
  ) async {
    final evidence = <String, Object?>{};
    final selected = <int>[];
    ({SpacyGrammarDecision decision, OfficeProofingFinding? finding}) done(
      String reason, {
      String action = 'abstained',
      OfficeProofingFinding? finding,
    }) => (
      decision: SpacyGrammarDecision(
        sentenceIndex: sentenceIndex,
        start: sentence.start,
        end: sentence.end,
        action: action,
        reason: reason,
        tokenIndices: selected,
        evidence: evidence,
      ),
      finding: finding,
    );

    if (quotedContext) return done('quoted-context');
    if (protected.overlaps(sentence.start, sentence.end) ||
        literals.overlaps(sentence.start, sentence.end)) {
      return done('protected-context');
    }
    final tokens = analysis.tokens
        .sublist(sentence.startToken, sentence.endToken)
        .where((token) => !token.isSpace)
        .toList(growable: false);
    if (tokens.length < 4 ||
        tokens.length > 48 ||
        sentence.text.length > 2048) {
      return done('sentence-limits');
    }
    if (_unsupportedCharacters.hasMatch(sentence.text) ||
        tokens.last.text != '.' ||
        tokens
            .take(tokens.length - 1)
            .any((token) => !_word.hasMatch(token.text))) {
      return done('unsupported-punctuation-or-source');
    }
    final words = tokens.sublist(0, tokens.length - 1);
    for (var index = 1; index < words.length; index++) {
      if (!_horizontal.hasMatch(
        request.text.substring(words[index - 1].end, words[index].start),
      )) {
        return done('unsupported-word-boundary');
      }
    }
    if (words.any(
      (token) =>
          personalWords.contains(normalizeGermanWord(token.text).toLowerCase()),
    )) {
      return done('personal-vocabulary');
    }
    if (words.any(
      (token) =>
          const {'PRON', 'PROPN', 'CCONJ', 'SCONJ'}.contains(token.pos) ||
          const {
            'cj',
            'cd',
            'rc',
            'oc',
            'cp',
            'ep',
            'expl',
          }.contains(token.dependency) ||
          token.text.toLowerCase() == 'es',
    )) {
      return done('unsupported-clause-or-reference');
    }
    final verbs = words
        .where((token) => token.pos == 'VERB' || token.pos == 'AUX')
        .toList(growable: false);
    if (verbs.length != 1) return done('not-one-finite-verb');
    final verb = verbs.single;
    selected.add(verb.index);
    evidence['verb'] = verb.toJson();
    if (verb.head != verb.index ||
        verb.dependency != 'ROOT' ||
        !const {'VVFIN', 'VAFIN', 'VMFIN'}.contains(verb.tag) ||
        !_feature(verb, 'VerbForm', 'Fin') ||
        !_feature(verb, 'Mood', 'Ind') ||
        !_feature(verb, 'Tense', 'Pres') ||
        !_feature(verb, 'Person', '3') ||
        verb.text != verb.text.toLowerCase()) {
      return done('unsupported-finite-analysis');
    }
    final subjects = words.where((token) => token.dependency == 'sb').toList();
    if (subjects.length != 1) return done('not-one-subject');
    final subject = subjects.single;
    selected.add(subject.index);
    evidence['subject'] = subject.toJson();
    if (subject.head != verb.index ||
        subject.pos != 'NOUN' ||
        subject.tag != 'NN' ||
        !_feature(subject, 'Case', 'Nom') ||
        subject.text == subject.text.toLowerCase()) {
      return done('unsupported-subject-analysis');
    }
    // Quantity/partitive heads can license semantic agreement with the group
    // they describe ("Eine Reihe von ... kommen"). Lexical noun number alone
    // cannot adjudicate this; the first planner deliberately excludes them.
    if (_nonMechanicalAgreementHeads.contains(subject.text.toLowerCase()) ||
        _nonMechanicalAgreementHeads.contains(subject.lemma.toLowerCase())) {
      return done('unsupported-collective-agreement');
    }
    final nounAt = words.indexOf(subject);
    var articleAt = nounAt - 1;
    final adjectives = <LinguisticToken>[];
    while (articleAt >= 0 && words[articleAt].tag == 'ADJA') {
      adjectives.insert(0, words[articleAt]);
      articleAt--;
    }
    if (articleAt < 0 || adjectives.length > 3) {
      return done('missing-determiner');
    }
    final article = words[articleAt];
    if (article.pos != 'DET' ||
        !const {'ART', 'PPOSAT', 'PDAT', 'PIAT'}.contains(article.tag) ||
        article.head != subject.index ||
        article.dependency != 'nk' ||
        adjectives.any(
          (token) => token.head != subject.index || token.dependency != 'nk',
        )) {
      return done('unsupported-noun-phrase');
    }
    selected.addAll([article.index, ...adjectives.map((token) => token.index)]);
    final verbAt = words.indexOf(verb);
    final pps = <List<LinguisticToken>>[];
    String construction;
    if (articleAt == 0 && verbAt > nounAt) {
      construction = 'subject-first';
      if (verbAt > nounAt + 1) {
        pps.add(words.sublist(nounAt + 1, verbAt));
        construction = 'subject-prepositional-modifier';
      }
    } else if (verbAt == 1 &&
        articleAt == 2 &&
        _initialAdverbs.contains(words.first.text.toLowerCase()) &&
        words.first.pos == 'ADV' &&
        words.first.head == verb.index &&
        words.first.dependency == 'mo') {
      construction = 'adverbial-inversion';
    } else {
      return done('unsupported-word-order');
    }
    final tailAt = verbAt > nounAt ? verbAt + 1 : nounAt + 1;
    var tail = tailAt;
    while (tail < words.length &&
        GermanAgreementFacts.isReviewedPredicateWord(words[tail].text) &&
        const {'ADV', 'ADJ', 'PART'}.contains(words[tail].pos) &&
        words[tail].head == verb.index &&
        const {'mo', 'pd', 'ng'}.contains(words[tail].dependency)) {
      tail++;
    }
    if (tail < words.length) pps.add(words.sublist(tail));
    // One complete prepositional phrase is the first candidate's limit. This
    // excludes unattached extra nouns, objects, copular nominal predicates,
    // chained modifiers and any potentially competing bare subject phrase.
    if (pps.length > 1) return done('multiple-prepositional-phrases');
    for (final pp in pps) {
      final reason = await _prepositionalPhrase(pp, verb, subject);
      if (reason != null) return done(reason);
    }
    // Every noun belongs either to the reviewed subject phrase or one complete
    // PP. This rejects fronted objects even if the model mislabels the subject.
    final coveredNouns = {subject.index, for (final pp in pps) pp.last.index};
    if (words.any(
      (token) => token.pos == 'NOUN' && !coveredNouns.contains(token.index),
    )) {
      return done('extra-nominal-phrase');
    }
    evidence['construction'] = construction;
    final lexical = await GermanAgreementFacts.nominativePhrase(
      determiner: article.text,
      noun: subject.text,
      adjectives: adjectives.map((token) => token.text).toList(growable: false),
    );
    evidence['noun_evidence'] = lexical.toJson();
    if (!lexical.ready) return done(lexical.reason);
    final readings = GermanAgreementFacts.reviewedPresentReadings(verb.text);
    evidence['verb_readings'] = readings
        .map((reading) => reading.toJson())
        .toList();
    if (readings.isEmpty) return done('unreviewed-verb');
    if (readings.any((reading) => reading.thirdPersonSubjunctive)) {
      return done('compatible-subjunctive-reading', action: 'preserved');
    }
    if (readings.any(
      (reading) =>
          !GermanAgreementFacts.sameForm(verb.text, reading.thirdSingular) &&
          !GermanAgreementFacts.sameForm(verb.text, reading.thirdPlural),
    )) {
      return done('unsupported-verb-surface');
    }
    if (readings.any(
      (reading) => lexical.numbers.any(
        (plural) =>
            GermanAgreementFacts.sameForm(verb.text, reading.forNumber(plural)),
      ),
    )) {
      return done('compatible-lexical-reading', action: 'preserved');
    }
    if (lexical.numbers.length != 1) return done('ambiguous-noun-number');
    final plural = lexical.numbers.single;
    if (!_feature(subject, 'Number', plural ? 'Plur' : 'Sing')) {
      return done('model-lexicon-number-disagreement');
    }
    if (readings.any((reading) => reading.infinitive != verb.lemma)) {
      return done('competing-verb-reading');
    }
    final targets = readings
        .map((reading) => reading.forNumber(plural))
        .toSet();
    if (targets.length != 1) return done('competing-verb-targets');
    final replacement = targets.single;
    evidence['replacement'] = replacement;
    evidence['replacement_provenance'] = 'quds-reviewed-present-paradigms';
    if (!GermanAgreementFacts.hasSourceBoundaries(
      request.text,
      verb.start,
      verb.end,
    )) {
      return done('non-grapheme-edit');
    }
    if (request.ignoredRuleIds.contains(spacyNounVerbRuleId) ||
        request.ignoredRuleIds.contains('de.grammar.noun-verb')) {
      return done('ignored-rule', action: 'suppressed');
    }
    return done(
      'reviewed-noun-verb-disagreement',
      action: 'proposed',
      finding: OfficeProofingFinding.forRequest(
        request,
        providerId: spacyGrammarProviderId,
        start: verb.start,
        end: verb.end,
        ruleId: spacyNounVerbRuleId,
        message:
            'Diese Verbform passt nicht zum lexikalisch eindeutigen Singular oder Plural des analysierten Subjekts.',
        category: OfficeProofingCategory.grammar,
        replacements: [replacement],
      ),
    );
  }
}

final _word = RegExp(r'^\p{L}[\p{L}\p{M}]*$', unicode: true);
final _horizontal = RegExp(r'^[ \t\u00a0\u202f]+$');
final _unsupportedCharacters = RegExp(r'[\u0000-\u001f\u007f\u00ad\uFFFC]');
final _quoteCharacters = RegExp(r'''["'„“”‚‘’«»‹›]''');
const _initialAdverbs = {
  'heute',
  'morgen',
  'jetzt',
  'hier',
  'dort',
  'bald',
  'oft',
  'immer',
  'selten',
  'wieder',
};
const _nonMechanicalAgreementHeads = {
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
  'fünftel',
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
  'heer',
  'art',
  'rest',
  'großteil',
};
const _prepositions = {
  'im',
  'am',
  'beim',
  'vom',
  'zum',
  'zur',
  'ins',
  'ans',
  'in',
  'an',
  'auf',
  'vor',
  'hinter',
  'neben',
  'unter',
  'über',
  'bei',
  'mit',
  'ohne',
  'nach',
  'zu',
  'von',
  'aus',
};

bool _feature(LinguisticToken token, String name, String value) =>
    token.morphology.split('|').contains('$name=$value');

Future<String?> _prepositionalPhrase(
  List<LinguisticToken> phrase,
  LinguisticToken verb,
  LinguisticToken subject,
) async {
  if (phrase.length < 2 || phrase.length > 6) return 'unsupported-phrase-tail';
  final preposition = phrase.first;
  final noun = phrase.last;
  // A finite noun list cannot close productive partitive constructions.
  // Withhold even ordinary possessive von/vom phrases in this first subset;
  // lexical number must not overrule licensed semantic group agreement.
  if (const {'von', 'vom'}.contains(preposition.text.toLowerCase())) {
    return 'unsupported-partitive-context';
  }
  if (!_prepositions.contains(preposition.text.toLowerCase()) ||
      preposition.pos != 'ADP' ||
      !const {'APPR', 'APPRART'}.contains(preposition.tag) ||
      !const {'mo', 'mnr'}.contains(preposition.dependency) ||
      (preposition.head != verb.index && preposition.head != subject.index) ||
      noun.pos != 'NOUN' ||
      noun.tag != 'NN' ||
      noun.head != preposition.index ||
      noun.dependency != 'nk' ||
      !(_feature(noun, 'Case', 'Dat') || _feature(noun, 'Case', 'Acc'))) {
    return 'unsupported-prepositional-analysis';
  }
  var at = 1;
  if (at < phrase.length - 1 && phrase[at].pos == 'DET') {
    final article = phrase[at++];
    if (article.head != noun.index || article.dependency != 'nk') {
      return 'unsupported-prepositional-determiner';
    }
  }
  while (at < phrase.length - 1) {
    final adjective = phrase[at++];
    if (adjective.pos != 'ADJ' ||
        adjective.tag != 'ADJA' ||
        adjective.head != noun.index ||
        adjective.dependency != 'nk' ||
        !GermanAgreementFacts.isReviewedAttributiveWord(adjective.text)) {
      return 'unsupported-prepositional-modifier';
    }
  }
  if (!await GermanAgreementFacts.hasKnownNoun(noun.text)) {
    return 'unknown-prepositional-noun';
  }
  return null;
}
