// Tests for the clean-room, morphology-based (tier T2) Arabic grammar rules.
// Every sentence here was written for Quds; none is taken from another
// checker's examples. The analyses in arabic_grammar_fixture.dart were
// produced from these sentences by the reference camel_tools analyzer over
// Camel Morph MSA v1.0 (noprob); a few tests edit them to model ambiguity.
import 'package:quds_office_engine/src/proofing/arabic_morphology.dart';
import 'package:quds_office_engine/src/proofing/arabic_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

import 'arabic_grammar_fixture.dart';

/// Answers from a word table; records every request.
final class FakeArabicMorphology implements ArabicMorphology {
  FakeArabicMorphology(this.table, {this.available = true});

  final Map<String, List<ArabicAnalysis>> table;
  final bool available;
  final List<Set<String>> requests = <Set<String>>[];

  @override
  bool get isAvailable => available;

  @override
  Future<Map<String, List<ArabicAnalysis>>> analyzeWords(
    Iterable<String> words,
  ) async {
    requests.add(words.toSet());
    return <String, List<ArabicAnalysis>>{
      for (final String word in words)
        word: table[word] ?? const <ArabicAnalysis>[],
    };
  }
}

final Map<String, List<ArabicAnalysis>> fixture =
    <String, List<ArabicAnalysis>>{
      for (final MapEntry<String, List<String>> e
          in arabicGrammarFixture.entries)
        e.key: <ArabicAnalysis>[
          for (final String row in e.value)
            <String, String>{
              for (final (int i, String value) in row.split('|').indexed)
                if (value.isNotEmpty) arabicGrammarFixtureKeys[i]: value,
            },
        ],
    };

final Set<String> grammarIds = <String>{
  ...arabicGrammarDefaultRuleIds,
  ...arabicGrammarOptionalRuleIds,
};

Future<List<OfficeProofingFinding>> check(
  String text, {
  Set<String> optional = const <String>{},
  ArabicMorphology? morphology,
  Set<String> ignored = const <String>{},
  int startOffset = 0,
  bool grammarOnly = true,
}) async {
  final ArabicWritingRulesProvider provider = ArabicWritingRulesProvider(
    enabledOptionalRuleIds: optional,
    morphology: morphology ?? FakeArabicMorphology(fixture),
  );
  final OfficeProofingResult result = await provider.check(
    OfficeProofingRequest(
      documentId: 'arabic-document',
      blockId: 'paragraph',
      revision: 1,
      text: text,
      language: 'ar',
      startOffset: startOffset,
      ignoredRuleIds: ignored,
    ),
  );
  expect(result.status, OfficeProofingStatus.success);
  return <OfficeProofingFinding>[
    for (final OfficeProofingFinding f in result.findings)
      if (!grammarOnly || grammarIds.contains(f.ruleId)) f,
  ];
}

/// (sentence, rule id, original text of the finding, first replacement or
/// null when the rule offers advice only)
typedef Positive = (String, String, String, String?);

const List<Positive> defaultPositives = <Positive>[
  // ar.grammar.preposition-case
  (
    'تحدث المدير إلى المهندسون في الاجتماع.',
    'ar.grammar.preposition-case',
    'المهندسون',
    'المهندسين',
  ),
  (
    'أثنى المدير على المعلمون.',
    'ar.grammar.preposition-case',
    'المعلمون',
    'المعلمين',
  ),
  (
    'جلست مع الزميلان في المكتبة.',
    'ar.grammar.preposition-case',
    'الزميلان',
    'الزميلين',
  ),
  (
    'رحبنا بالمهندسون الجدد.',
    'ar.grammar.preposition-case',
    'بالمهندسون',
    'بالمهندسين',
  ),
  (
    'قدمت الشكر للمعلمون.',
    'ar.grammar.preposition-case',
    'للمعلمون',
    'للمعلمين',
  ),
  ('حصل على عشرون نقطة.', 'ar.grammar.preposition-case', 'عشرون', 'عشرين'),
  ('اطلعت على هذان التقريران.', 'ar.grammar.preposition-case', 'هذان', 'هذين'),
  ('عمل هناك في اثنا عشر شهرا.', 'ar.grammar.preposition-case', 'اثنا', 'اثني'),
  // harakat are kept in the replacement
  (
    'تحدّثَ المديرُ إلى المهندسونَ.',
    'ar.grammar.preposition-case',
    'المهندسونَ',
    'المهندسينَ',
  ),
  // ar.grammar.inna-case
  ('إن المهندسون بارعون.', 'ar.grammar.inna-case', 'المهندسون', 'المهندسين'),
  ('لعل الزميلان ينجحان.', 'ar.grammar.inna-case', 'الزميلان', 'الزميلين'),
  (
    'علمت أن المسافرون وصلوا.',
    'ar.grammar.inna-case',
    'المسافرون',
    'المسافرين',
  ),
  // ar.grammar.kana-predicate
  (
    'كانوا مجتهدون في عملهم.',
    'ar.grammar.kana-predicate',
    'مجتهدون',
    'مجتهدين',
  ),
  // ar.grammar.dual-demonstrative
  (
    'قرأت هذين الكتابان.',
    'ar.grammar.dual-demonstrative',
    'هذين الكتابان',
    'هذان الكتابان',
  ),
  (
    'إن هذان الكتابين مفيدان.',
    'ar.grammar.dual-demonstrative',
    'هذان الكتابين',
    'هذين الكتابين',
  ),
  // ar.grammar.jussive
  ('لم يمشي الطفل بعد.', 'ar.grammar.jussive', 'يمشي', 'يمش'),
  ('لم يدعو أحدا إلى الحفل.', 'ar.grammar.jussive', 'يدعو', 'يدع'),
  ('لم يسعى إلى المنصب.', 'ar.grammar.jussive', 'يسعى', 'يسع'),
  ('لم يقول الحقيقة.', 'ar.grammar.jussive', 'يقول', 'يقل'),
  ('الطلاب لم يذهبون إلى المدرسة.', 'ar.grammar.jussive', 'يذهبون', 'يذهبوا'),
  ('أنت لم تكتبين الدرس.', 'ar.grammar.jussive', 'تكتبين', 'تكتبي'),
  // ar.grammar.subjunctive
  ('لن يذهبون إلى السوق.', 'ar.grammar.subjunctive', 'يذهبون', 'يذهبوا'),
  ('يجب أن تكتبون الواجب.', 'ar.grammar.subjunctive', 'تكتبون', 'تكتبوا'),
  ('جاؤوا كي يتعلمون.', 'ar.grammar.subjunctive', 'يتعلمون', 'يتعلموا'),
  // ar.numeral.gender
  ('اشتريت ثلاثة سيارات.', 'ar.numeral.gender', 'ثلاثة', 'ثلاث'),
  ('جاء أربع رجال.', 'ar.numeral.gender', 'أربع', 'أربعة'),
  ('عملت سبعة ساعات.', 'ar.numeral.gender', 'سبعة', 'سبع'),
  ('فاز بثلاثة بطولات.', 'ar.numeral.gender', 'بثلاثة', 'بثلاث'),
  ('زرت ستة مدارس.', 'ar.numeral.gender', 'ستة', 'ست'),
  // ar.numeral.counted-number
  ('حضر عشرون طلاب.', 'ar.numeral.counted-number', 'طلاب', 'طالبًا'),
  ('مرت خمسة عشر أيام.', 'ar.numeral.counted-number', 'أيام', 'يومًا'),
  (
    'عمل في فريق يضم خمسة عشر مهندسون.',
    'ar.numeral.counted-number',
    'مهندسون',
    'مهندسًا',
  ),
  // ar.grammar.verb-preposition
  ('يبحث عليها منذ أيام.', 'ar.grammar.verb-preposition', 'عليها', 'عنها'),
];

const List<Positive> optionalPositives = <Positive>[
  // ar.grammar.la-past
  ('لا ذهبت إلى هناك.', 'ar.grammar.la-past', 'لا ذهبت', null),
  // ar.numeral.counted-case
  ('دفعنا ثلاثين دينار.', 'ar.numeral.counted-case', 'دينار', 'دينارًا'),
  // ar.usage.verb-preposition
  ('تخرجت من جامعة القاهرة.', 'ar.usage.verb-preposition', 'من', 'في'),
  ('يحوزون على الجوائز كل عام.', 'ar.usage.verb-preposition', 'على', null),
  ('يؤكدون على أهمية التعليم.', 'ar.usage.verb-preposition', 'على', null),
  // ar.usage.word-inflected
  ('يساهمان في المشروع.', 'ar.usage.word-inflected', 'يساهمان', null),
  ('يتواجدون في القاعة.', 'ar.usage.word-inflected', 'يتواجدون', null),
];

/// Valid sentences: no grammar finding with every rule enabled.
const List<String> validControls = <String>[
  'تحدث المدير إلى المهندسين في الاجتماع.',
  'سافرت إلى لبنان.',
  'كتب مقالا عن خلدون.',
  'رحبنا بالمهندسين الجدد.',
  'إن المهندسين بارعون.',
  'كانوا مجتهدين في عملهم.',
  'كان الطلاب المجتهدون حاضرين.',
  'كان المهندسون حاضرين.',
  'قرأت هذين الكتابين.',
  'هذان الكتابان مفيدان.',
  'لم يمش الطفل بعد.',
  'لم يذهبوا إلى المدرسة.',
  'لم يكتب الدرس.',
  'لن يذهبوا إلى السوق.',
  'لن يمشي وحده.',
  'اشتريت ثلاث سيارات.',
  'جاء أربعة رجال.',
  'جاء ثلاثة عشر رجلا.',
  'حضر عشرون طالبا.',
  'مرت خمسة أيام.',
  'دفعنا ثلاثين دينارا.',
  'لا يذهب إلى هناك.',
  'سألت عنه في المدرسة.',
  'يبحث عنها منذ أيام.',
  'تخرجت في جامعة القاهرة.',
  'أسهمنا في المشروع.',
];

/// Sentences the rules deliberately leave alone, each for a stated reason.
const List<(String, String)> reasonedControls = <(String, String)>[
  // "after" ends a clause: لم يصل بعدُ المسؤولون
  ('لم يصل بعد المسؤولون.', 'بعد is not in the preposition class'),
  ('من المعلمون في المدرسة؟', 'من is also "who"'),
  ('إنهم مهندسون بارعون.', 'the particle carries the subject pronoun'),
  ('لكن المهندسون رفضوا الخطة.', 'light لكنْ takes a nominative'),
  ('لِمَ يمشي وحده؟', 'vowelled لِمَ is "why"'),
  ('لم يمشي وحده؟', 'unvowelled لم in a question may be "why"'),
  ('علمت أن سيذهبون غدا.', 'a future prefix after light أنْ'),
  ('عقدنا ثلاثة اجتماعات.', 'feminine plural of a masculine singular'),
  ('عقدنا ثلاث اجتماعات.', 'feminine plural of a masculine singular'),
  ('أخذ خمس الطلاب الجائزة.', 'خمس is also the fraction'),
  ('لليد أربع أصابع.', 'إصبع is of either gender'),
  ('لليد أربعة أصابع.', 'إصبع is of either gender'),
  ('جاء خمس رجال.', 'خمس is also the fraction'),
  ('دفعنا عشرين ألف دينار.', 'the counted noun is in construct'),
  ('لا ذهبت ولا عدت.', 'repeated لا'),
  ('لا سمح الله بذلك.', 'a prayer'),
  ('لا زال المطر يهطل.', 'لا زال belongs to the usage rules'),
  ('سأل على الفور.', 'على without a pronoun starts an adverbial'),
  (
    'يؤكدون على هامش المؤتمر أن الخطة جاهزة.',
    'على هامش is an adverbial phrase',
  ),
  // Readings the analyzer offers keep these silent (no compatible-free
  // reading exists): كأنّ for كان, the verb كتب for كتب, أسال for يسألون.
  ('كان الطلاب مجتهدون.', 'كان may be كأنّ, whose predicate is nominative'),
  ('قرأت ثلاث كتب.', 'كتب is also a verb'),
  ('يسألون عليه في المدرسة.', 'يسألون is also a form of أسال'),
  ('وصلت رسالة من المهندسون.', 'من is also "who"'),
];

void main() {
  group('Arabic grammar rules (T2): positives', () {
    for (final (String text, String rule, String found, String? first)
        in defaultPositives) {
      test('$rule: $text', () async {
        final List<OfficeProofingFinding> findings = await check(text);
        expect(findings.map((OfficeProofingFinding f) => f.ruleId), <String>[
          rule,
        ], reason: 'exactly one grammar finding');
        final OfficeProofingFinding f = findings.single;
        expect(text.substring(f.start, f.end), found);
        if (first == null) {
          expect(f.replacements, isEmpty);
        } else {
          expect(f.replacements.first, first);
        }
      });
    }
    for (final (String text, String rule, String found, String? first)
        in optionalPositives) {
      test('$rule (opt-in): $text', () async {
        expect(await check(text), isEmpty, reason: 'off by default');
        final List<OfficeProofingFinding> findings = await check(
          text,
          optional: <String>{rule},
        );
        expect(findings.map((OfficeProofingFinding f) => f.ruleId), <String>[
          rule,
        ]);
        final OfficeProofingFinding f = findings.single;
        expect(text.substring(f.start, f.end), found);
        if (first == null) {
          expect(f.replacements, isEmpty);
        } else {
          expect(f.replacements.first, first);
        }
      });
    }
  });

  group('Arabic grammar rules (T2): controls', () {
    for (final String text in validControls) {
      test('valid: $text', () async {
        expect(
          await check(text, optional: arabicGrammarOptionalRuleIds),
          isEmpty,
        );
      });
    }
    for (final (String text, String reason) in reasonedControls) {
      test('silent ($reason): $text', () async {
        expect(
          await check(text, optional: arabicGrammarOptionalRuleIds),
          isEmpty,
        );
      });
    }
  });

  group('Arabic grammar rules (T2): the analysis set', () {
    const String sentence = 'تحدث المدير إلى المهندسون في الاجتماع.';

    test('one compatible analysis keeps a word silent', () async {
      final Map<String, List<ArabicAnalysis>> table =
          <String, List<ArabicAnalysis>>{
            ...fixture,
            'المهندسون': <ArabicAnalysis>[
              ...fixture['المهندسون']!,
              <String, String>{
                'lex': 'مُهَنْدِس',
                'pos': 'noun',
                'cas': 'g',
                'num': 'p',
                'form_num': 'p',
                'form_gen': 'm',
              },
            ],
          };
      expect(
        await check(sentence, morphology: FakeArabicMorphology(table)),
        isEmpty,
      );
    });

    test('an unknown word is never reported', () async {
      final Map<String, List<ArabicAnalysis>> table =
          <String, List<ArabicAnalysis>>{
            ...fixture,
            'المهندسون': const <ArabicAnalysis>[],
          };
      expect(
        await check(sentence, morphology: FakeArabicMorphology(table)),
        isEmpty,
      );
    });

    test('a proper-noun reading alone is an unknown name', () async {
      final Map<String, List<ArabicAnalysis>> table =
          <String, List<ArabicAnalysis>>{
            'يوكاتون': <ArabicAnalysis>[
              <String, String>{
                'lex': 'يوكات',
                'pos': 'noun_prop',
                'cas': 'n',
                'num': 'p',
                'form_num': 'p',
                'form_gen': 'm',
              },
            ],
          };
      expect(
        await check(
          'سافرنا إلى يوكاتون.',
          morphology: FakeArabicMorphology(table),
        ),
        isEmpty,
      );
    });

    test('a numeral before an ambiguous verb/noun stays silent', () async {
      // ثلاثة كتب is valid; ثلاث كتب is wrong, but كتب is also "he wrote"
      // (and كـ + تبّ). Keeping only the plural of كتاب makes it visible.
      final Map<String, List<ArabicAnalysis>> nounOnly =
          <String, List<ArabicAnalysis>>{
            ...fixture,
            'كتب': <ArabicAnalysis>[
              for (final ArabicAnalysis a in fixture['كتب']!)
                if (a['lex'] == 'كِتَاب') a,
            ],
          };
      expect(await check('قرأت ثلاث كتب.'), isEmpty);
      final List<OfficeProofingFinding> findings = await check(
        'قرأت ثلاث كتب.',
        morphology: FakeArabicMorphology(nounOnly),
      );
      expect(findings.single.ruleId, 'ar.numeral.gender');
      expect(findings.single.replacements, <String>['ثلاثة']);
    });

    test(
      'a replacement is offered only when the analyzer confirms it',
      () async {
        final Map<String, List<ArabicAnalysis>> table =
            <String, List<ArabicAnalysis>>{...fixture}..remove('المهندسين');
        final List<OfficeProofingFinding> findings = await check(
          sentence,
          morphology: FakeArabicMorphology(table),
        );
        expect(findings.single.ruleId, 'ar.grammar.preposition-case');
        expect(findings.single.replacements, isEmpty);
      },
    );
  });

  group('Arabic grammar rules (T2): integration', () {
    const String sentence = 'تحدث المدير إلى المهندسون في الاجتماع.';

    test('silent without an analyzer; T1 findings unchanged', () async {
      const String text =
          'تحدث المدير الى المهندسون في الاجتماع، لم يمشي الطفل.';
      final ArabicWritingRulesProvider plain = ArabicWritingRulesProvider();
      expect(plain.morphology, isA<UnavailableArabicMorphology>());
      final FakeArabicMorphology unavailable = FakeArabicMorphology(
        fixture,
        available: false,
      );
      final List<OfficeProofingFinding> without = await check(
        text,
        morphology: const UnavailableArabicMorphology(),
        grammarOnly: false,
      );
      final List<OfficeProofingFinding> withUnavailable = await check(
        text,
        morphology: unavailable,
        grammarOnly: false,
      );
      expect(unavailable.requests, isEmpty);
      expect(
        without.map((OfficeProofingFinding f) => f.ruleId),
        isNot(contains(startsWith('ar.grammar.'))),
      );
      expect(
        withUnavailable.map(
          (OfficeProofingFinding f) => (f.ruleId, f.start, f.end),
        ),
        without.map((OfficeProofingFinding f) => (f.ruleId, f.start, f.end)),
      );
      final List<OfficeProofingFinding> withAnalyzer = await check(
        text,
        grammarOnly: false,
      );
      // The analyzer adds grammar findings and removes none.
      for (final OfficeProofingFinding f in without) {
        expect(
          withAnalyzer.any(
            (OfficeProofingFinding g) =>
                g.ruleId == f.ruleId && g.start == f.start && g.end == f.end,
          ),
          isTrue,
        );
      }
      expect(
        withAnalyzer
            .where((OfficeProofingFinding f) => grammarIds.contains(f.ruleId))
            .map((OfficeProofingFinding f) => f.ruleId),
        containsAll(<String>[
          'ar.grammar.preposition-case',
          'ar.grammar.jussive',
        ]),
      );
    });

    test('only needed words are analyzed, in at most two calls', () async {
      final FakeArabicMorphology morphology = FakeArabicMorphology(fixture);
      await check(sentence, morphology: morphology);
      expect(morphology.requests.length, lessThanOrEqualTo(2));
      expect(morphology.requests.first, contains('المهندسون'));
      expect(morphology.requests.first, isNot(contains('المدير')));
    });

    test('ignored rule ids and offsets', () async {
      expect(
        await check(sentence, ignored: <String>{'ar.grammar.preposition-case'}),
        isEmpty,
      );
      final List<OfficeProofingFinding> shifted = await check(
        sentence,
        startOffset: 100,
      );
      expect(shifted.single.start, 100 + sentence.indexOf('المهندسون'));
      expect(shifted.single.end, shifted.single.start + 'المهندسون'.length);
    });

    test('protected spans are excluded', () async {
      expect(await check('`إلى المهندسون` في الشيفرة.'), isEmpty);
    });

    test('an opt-in usage rule does not repeat a T1 finding', () async {
      const String text = 'تخرجت من جامعة القاهرة.';
      final List<OfficeProofingFinding> both = await check(
        text,
        optional: <String>{'ar.usage.expression', 'ar.usage.verb-preposition'},
        grammarOnly: false,
      );
      final Iterable<OfficeProofingFinding> atMin = both.where(
        (OfficeProofingFinding f) =>
            f.start <= text.indexOf('من') && text.indexOf('من') < f.end,
      );
      expect(atMin.length, 1);
    });

    test('rule-id sets', () {
      expect(
        ArabicWritingRulesProvider.allRuleIds,
        containsAll(<String>{
          ...arabicGrammarDefaultRuleIds,
          ...arabicGrammarOptionalRuleIds,
        }),
      );
      expect(
        arabicGrammarDefaultRuleIds.intersection(arabicGrammarOptionalRuleIds),
        isEmpty,
      );
      final ArabicWritingRulesProvider provider = ArabicWritingRulesProvider(
        enabledOptionalRuleIds: <String>{
          'ar.grammar.la-past',
          'ar.grammar.jussive',
          'ar.grammar.kana-predicate',
        },
      );
      expect(provider.enabledOptionalRuleIds, <String>{'ar.grammar.la-past'});
      for (final ArabicVerbPrepositionForTesting e
          in arabicVerbPrepositionsForTesting()) {
        expect(<String>{
          'ar.grammar.verb-preposition',
          'ar.usage.verb-preposition',
        }, contains(e.ruleId));
        expect(e.lemma, isNot(matches(RegExp('[ً-ْ]'))));
      }
      expect(arabicInflectedUsageForTesting(), isNotEmpty);
    });
  });
}
