// Context disambiguation in the tier-T2 Arabic grammar rules: a word whose
// best reading in its sentence clearly leads is represented by that
// reading's analyses; otherwise every analysis is used, as before. The
// sentences are the ones arabic_grammar_rules_test.dart lists as silent
// because of an unlikely reading.
import 'package:quds_office_engine/src/proofing/arabic_morphology.dart';
import 'package:quds_office_engine/src/proofing/arabic_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

import 'arabic_grammar_rules_test.dart' show FakeArabicMorphology, fixture;

/// A fixture analyzer with a fake context model: for a word in [preferred],
/// the analyses the predicate accepts form the best candidate with score
/// [score]; the rest share 1 - score.
final class FakeContextMorphology implements ArabicContextMorphology {
  FakeContextMorphology(
    this.table, {
    this.preferred = const <String, bool Function(ArabicAnalysis)>{},
    this.score = 0.97,
    this.loaded = true,
  });

  final Map<String, List<ArabicAnalysis>> table;

  @override
  bool get isAvailable => true;

  @override
  Future<Map<String, List<ArabicAnalysis>>> analyzeWords(
    Iterable<String> words,
  ) => FakeArabicMorphology(table).analyzeWords(words);

  final Map<String, bool Function(ArabicAnalysis)> preferred;
  final double score;
  final bool loaded;
  final List<List<List<String>>> calls = <List<List<String>>>[];

  @override
  bool get canDisambiguate => loaded;

  @override
  Future<List<List<ArabicContextReading>>> disambiguate(
    List<List<String>> sentences,
  ) async {
    calls.add(sentences);
    return <List<ArabicContextReading>>[
      for (final List<String> s in sentences)
        <ArabicContextReading>[for (final String token in s) _reading(token)],
    ];
  }

  ArabicContextReading _reading(String token) {
    final List<ArabicAnalysis> analyses =
        table[token] ?? const <ArabicAnalysis>[];
    if (analyses.isEmpty) return ArabicContextReading.none;
    final bool Function(ArabicAnalysis)? best = preferred[token];
    final List<bool> top = <bool>[
      for (final ArabicAnalysis a in analyses) best == null || best(a),
    ];
    final bool split = top.contains(true) && top.contains(false);
    return ArabicContextReading(
      analyses,
      <double>[for (final bool t in top) split ? (t ? score : 1 - score) : 1.0],
      <int>[for (final bool t in top) split && !t ? 1 : 0],
    );
  }
}

Future<List<OfficeProofingFinding>> check(
  String text,
  ArabicMorphology morphology, {
  ArabicGrammarReading reading = ArabicGrammarReading.contextual,
}) async {
  final ArabicWritingRulesProvider provider = ArabicWritingRulesProvider(
    morphology: morphology,
    grammarReading: reading,
  );
  final OfficeProofingResult result = await provider.check(
    OfficeProofingRequest(
      documentId: 'arabic-document',
      blockId: 'paragraph',
      revision: 1,
      text: text,
      language: 'ar',
    ),
  );
  expect(result.status, OfficeProofingStatus.success);
  final Set<String> grammar = <String>{
    ...arabicGrammarDefaultRuleIds,
    ...arabicGrammarOptionalRuleIds,
  };
  return <OfficeProofingFinding>[
    for (final OfficeProofingFinding f in result.findings)
      if (grammar.contains(f.ruleId)) f,
  ];
}

bool kitabPlural(ArabicAnalysis a) => a['lex'] == 'كِتَاب';
bool kanaVerb(ArabicAnalysis a) => a['pos'] == 'verb';

void main() {
  group('context disambiguation', () {
    test('a confident noun reading reveals a numeral error', () async {
      final FakeContextMorphology m = FakeContextMorphology(
        fixture,
        preferred: <String, bool Function(ArabicAnalysis)>{'كتب': kitabPlural},
      );
      final List<OfficeProofingFinding> findings = await check(
        'قرأت ثلاث كتب.',
        m,
      );
      expect(findings.single.ruleId, 'ar.numeral.gender');
      expect(findings.single.replacements, <String>['ثلاثة']);
      // The whole sentence is one call, punctuation included.
      expect(m.calls.single, <List<String>>[
        <String>['قرأت', 'ثلاث', 'كتب', '.'],
      ]);
    });

    test('kana with confident verb and subject readings', () async {
      final List<OfficeProofingFinding> findings = await check(
        'كان الطلاب مجتهدون.',
        FakeContextMorphology(
          fixture,
          preferred: <String, bool Function(ArabicAnalysis)>{
            'كان': kanaVerb,
            'الطلاب': (ArabicAnalysis a) =>
                a.containsValue('Al_det') && a['stt'] == 'd',
          },
        ),
      );
      expect(findings.single.ruleId, 'ar.grammar.kana-predicate');
    });

    test('a reading below the margin keeps every analysis', () async {
      expect(
        await check(
          'قرأت ثلاث كتب.',
          FakeContextMorphology(
            fixture,
            preferred: <String, bool Function(ArabicAnalysis)>{
              'كتب': kitabPlural,
            },
            score: 0.9, // leads by 0.8 < 0.9
          ),
        ),
        isEmpty,
      );
    });

    test('the all-analyses mode ignores the model', () async {
      final FakeContextMorphology m = FakeContextMorphology(
        fixture,
        preferred: <String, bool Function(ArabicAnalysis)>{'كتب': kitabPlural},
      );
      expect(
        await check(
          'قرأت ثلاث كتب.',
          m,
          reading: ArabicGrammarReading.allAnalyses,
        ),
        isEmpty,
      );
      expect(m.calls, isEmpty);
    });

    test('without a loaded model every analysis is used', () async {
      final FakeContextMorphology m = FakeContextMorphology(
        fixture,
        preferred: <String, bool Function(ArabicAnalysis)>{'كتب': kitabPlural},
        loaded: false,
      );
      expect(await check('قرأت ثلاث كتب.', m), isEmpty);
      expect(m.calls, isEmpty);
    });

    test('a plain analyzer is unaffected by the contextual mode', () async {
      expect(
        await check('قرأت ثلاث كتب.', FakeArabicMorphology(fixture)),
        isEmpty,
      );
    });

    test('only sentences with a needed word are sent', () async {
      final FakeContextMorphology m = FakeContextMorphology(
        fixture,
        preferred: <String, bool Function(ArabicAnalysis)>{'كتب': kitabPlural},
      );
      await check('الجو جميل اليوم. قرأت ثلاث كتب.', m);
      expect(m.calls.single, <List<String>>[
        <String>['قرأت', 'ثلاث', 'كتب', '.'],
      ]);
    });

    test('a failing or malformed model falls back to every analysis', () async {
      expect(
        await check('قرأت ثلاث كتب.', _BrokenContextMorphology(fixture)),
        isEmpty,
      );
    });
  });

  group('arabicContextSentences', () {
    String tokens(String text) => <String>[
      for (final List<ArabicContextToken> s in arabicContextSentences(text))
        s.map((ArabicContextToken t) => t.text).join(' '),
    ].join(' | ');

    test('words, numbers, Latin and punctuation are tokens', () {
      expect(
        tokens('قرأتُ «الكتاب» عام 2024، وPython 3.12 أيضاً؟ نعم!\nسطر'),
        'قرأتُ « الكتاب » عام 2024 ، و Python 3.12 أيضاً ؟ | نعم ! | سطر',
      );
    });

    test('offsets cover the source text', () {
      const String text = 'في  البيت… ثم';
      for (final List<ArabicContextToken> s in arabicContextSentences(text)) {
        for (final ArabicContextToken t in s) {
          expect(text.substring(t.start, t.end), t.text);
        }
      }
      expect(tokens(text), 'في البيت … | ثم');
    });

    test('readings: best, margin and confident', () {
      final ArabicContextReading r = ArabicContextReading(
        const <ArabicAnalysis>[
          <String, String>{'pos': 'noun'},
          <String, String>{'pos': 'verb'},
          <String, String>{'pos': 'noun'},
        ],
        const <double>[0.96, 0.04, 0.96],
        const <int>[0, 1, 0],
      );
      expect(r.best.length, 2);
      expect(r.margin, closeTo(0.92, 1e-9));
      expect(r.confident(0.9), hasLength(2));
      expect(r.confident(0.95), isNull);
      expect(ArabicContextReading.none.confident(0), isNull);
    });
  });
}

final class _BrokenContextMorphology implements ArabicContextMorphology {
  _BrokenContextMorphology(this.table);
  final Map<String, List<ArabicAnalysis>> table;
  int calls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<Map<String, List<ArabicAnalysis>>> analyzeWords(
    Iterable<String> words,
  ) => FakeArabicMorphology(table).analyzeWords(words);

  @override
  bool get canDisambiguate => true;

  @override
  Future<List<List<ArabicContextReading>>> disambiguate(
    List<List<String>> sentences,
  ) async {
    if (calls++ == 0) throw StateError('model failed');
    return const <List<ArabicContextReading>>[];
  }
}
