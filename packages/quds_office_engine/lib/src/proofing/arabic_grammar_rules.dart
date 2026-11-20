part of 'arabic_writing_rules.dart';

// Clean-room tier-T2 (morphology-based) extension of the Arabic writing
// rules.
//
// Written only from the abstract specification in
// docs/roadmaps/arabic-rule-spec.md (categories G2, G5, G6, G7, G8, G9, G10,
// G11, G15 and the lemma variant of S9/L3). Every closed word class, lexicon
// entry, message and example was authored for Quds from general knowledge of
// Modern Standard Arabic grammar; no external rule set, word list or error
// corpus was consulted.
//
// The rules read camel_tools-style analyses through [ArabicMorphology]. The
// analyses carry no ranking, so every rule follows one principle: a finding
// is reported only when NO analysis of the word(s) concerned is compatible
// with the grammatical requirement. With a context disambiguation model
// ([ArabicGrammarReading.contextual]), a word whose best reading in its
// sentence clearly leads is represented by that reading's analyses only; the
// principle then applies to them. A word the analyzer does not know (an
// empty analysis list) never produces a finding. Particles and number words
// are matched by their spelling (the analyzer normalizes hamza, so it cannot
// tell أنّ from إنْ); only the words whose form decides the case are judged
// from their analyses.

/// How the morphology-based rules read a word.
enum ArabicGrammarReading {
  /// Every analysis of a word: a rule reports only when no analysis is
  /// compatible (the behaviour before context disambiguation).
  allAnalyses,

  /// When the analyzer is an [ArabicContextMorphology] with a loaded model
  /// and a word's best reading in context leads the second by at least the
  /// provider's margin, only that reading's analyses; otherwise every
  /// analysis, as with [allAnalyses].
  contextual,
}

/// Default lead of the best context reading over the second before the
/// rules rely on it (on a probability scale: 0.9 means at least 0.95 against
/// 0.05).
const double arabicContextMinMargin = 0.9;

/// Morphology-based rule ids that run by default (when an analyzer is
/// installed).
const Set<String> arabicGrammarDefaultRuleIds = <String>{
  'ar.grammar.preposition-case',
  'ar.grammar.inna-case',
  'ar.grammar.kana-predicate',
  'ar.grammar.dual-demonstrative',
  'ar.grammar.jussive',
  'ar.grammar.subjunctive',
  'ar.numeral.gender',
  'ar.numeral.counted-number',
  'ar.grammar.verb-preposition',
};

/// Morphology-based rule ids that are prescriptive or less certain and run
/// only when the host enables them.
const Set<String> arabicGrammarOptionalRuleIds = <String>{
  'ar.grammar.la-past',
  'ar.numeral.counted-case',
  'ar.usage.verb-preposition',
  'ar.usage.word-inflected',
};

/// A verb that governs its object through a particular preposition, and a
/// preposition that is wrongly used with it. Exposed read-only for tests.
final class ArabicVerbPrepositionForTesting {
  const ArabicVerbPrepositionForTesting(
    this.lemma,
    this.wrong,
    this.right, {
    required this.ruleId,
    required this.message,
    this.pronounOnly = false,
  });

  /// The verb lemma without harakat, as the analyzer's `lex` spells it.
  final String lemma;

  /// The wrong preposition (independent spelling, no pronoun).
  final String wrong;

  /// The governed preposition, or the empty string for a direct object.
  final String right;
  final String ruleId;
  final String message;

  /// Only a preposition carrying a pronoun suffix is reported: without one
  /// it may start an adverbial phrase that does not depend on the verb.
  final bool pronounOnly;
}

/// The verb–preposition lexicon of `ar.grammar.verb-preposition` and
/// `ar.usage.verb-preposition`.
List<ArabicVerbPrepositionForTesting> arabicVerbPrepositionsForTesting() =>
    _ArabicGrammarRules._verbPrepositions;

/// Lemma-matched usage entries of `ar.usage.word-inflected` (lemma ->
/// preferred lemma). Exposed read-only for tests.
Map<String, String> arabicInflectedUsageForTesting() =>
    _ArabicGrammarRules._inflectedUsage;

typedef _ArabicReported = bool Function(int start, int end);

/// A replacement that is offered only if the analyzer confirms it.
final class _GrammarCandidate {
  const _GrammarCandidate(this.replacement, this.probe, this.accept);

  /// The text that replaces the finding's range.
  final String replacement;

  /// The single word whose analyses decide whether to offer it.
  final String probe;
  final bool Function(List<ArabicAnalysis> analyses) accept;
}

final class _GrammarFinding {
  _GrammarFinding(
    this.ruleId,
    this.start,
    this.end,
    this.message, {
    this.candidates = const <_GrammarCandidate>[],
    this.fixed = const <String>[],
  });
  final String ruleId;
  final int start;
  final int end;
  final String message;
  final List<_GrammarCandidate> candidates;

  /// Replacements that need no confirmation (closed-class words).
  final List<String> fixed;
}

final class _ArabicGrammarRules {
  _ArabicGrammarRules(
    this.text,
    this.words,
    this.morphology,
    this.add,
    this.enabled,
    this.reported, {
    this.contextual = false,
    this.contextMinMargin = arabicContextMinMargin,
  }) : bares = <String>[
         for (final RegExpMatch m in words)
           ArabicWritingRulesProvider._bare(m.group(0)!).$1,
       ];

  final String text;
  final List<RegExpMatch> words;
  final ArabicMorphology morphology;
  final _ArabicAdd add;
  final bool Function(String ruleId) enabled;
  final _ArabicReported reported;
  final List<String> bares;
  final bool contextual;
  final double contextMinMargin;

  /// Per word index: the analyses of its confident context reading.
  Map<int, List<ArabicAnalysis>> _confident =
      const <int, List<ArabicAnalysis>>{};

  static final RegExp _spaces = RegExp(r'^[  ]+$');
  static final RegExp _harakat = RegExp('[ً-ْٰـ]');

  Map<String, List<ArabicAnalysis>> _analyses =
      const <String, List<ArabicAnalysis>>{};
  final List<_GrammarFinding> _found = <_GrammarFinding>[];

  // ------------------------------------------------------------ word classes

  /// Independent prepositions (and adverbs that always take a genitive)
  /// whose next word cannot be nominative. من (also "who"), حتى (also a
  /// conjunction), منذ, بعد and قبل (both also adverbs ending a clause:
  /// "لم يصل بعدُ المسؤولون") and words that are also verbs (بين, عبر,
  /// حول, دون) are deliberately absent.
  static const Set<String> _prepositions = <String>{
    'في', 'ففي', 'وفي', //
    'إلى', 'الى', 'وإلى', 'والى', 'فإلى',
    'على', 'وعلى', 'فعلى',
    'عن', 'وعن', 'فعن',
    'مع', 'ومع', 'فمع',
    'لدى', 'ولدى',
    'عند', 'وعند', 'فعند',
  };

  /// Particles that make their subject accusative. Bare لكن is absent: its
  /// light form لكنْ is followed by a nominative. Forms with an attached
  /// pronoun are absent: the next word is then the predicate.
  static const Set<String> _inna = <String>{
    'إن', 'وإن', 'فإن', //
    'أن', 'وأن', 'فأن', 'بأن', 'لأن', 'ولأن', 'كأن', 'وكأن',
    'ليت', 'وليت', 'فليت', 'ياليت',
    'لعل', 'ولعل', 'فلعل',
    'لكنّ', 'ولكنّ',
  };

  /// Dual demonstratives: bare spelling -> nominative?
  static const Map<String, bool> _dualDemonstratives = <String, bool>{
    'هذان': true,
    'هاتان': true,
    'هذين': false,
    'هاتين': false,
  };
  static const Map<String, String> _dualDemonstrativeOther = <String, String>{
    'هذان': 'هذين',
    'هاتان': 'هاتين',
    'هذين': 'هذان',
    'هاتين': 'هاتان',
  };

  /// The jussive-governing "not" particle with its proclitics. لمّا is left
  /// out (it is also "when" before a past verb, and لِما "for what").
  static const Set<String> _lam = <String>{
    'لم', 'ولم', 'فلم', 'ألم', 'أولم', 'أفلم', //
  };

  /// Particles after which an imperfect verb is subjunctive. حتى (also
  /// followed by an indicative of the present) and ألا (also "lo") are
  /// left out.
  static const Set<String> _subjunctive = <String>{
    'لن', 'ولن', 'فلن', //
    'كي', 'لكي', 'ولكي', 'فلكي', 'كيلا', 'لكيلا',
    'أن', 'وأن', 'فأن', 'بأن', 'لأن', 'ولأن',
  };

  /// Numerals 3–10: bare spelling -> (value, carries ta marbuta).
  static const Map<String, (int, bool)> _units = <String, (int, bool)>{
    'ثلاث': (3, false),
    'ثلاثة': (3, true),
    'أربع': (4, false),
    'أربعة': (4, true),
    'اربع': (4, false),
    'اربعة': (4, true),
    'خمس': (5, false),
    'خمسة': (5, true),
    'ست': (6, false),
    'ستة': (6, true),
    'سبع': (7, false),
    'سبعة': (7, true),
    'ثمان': (8, false),
    'ثماني': (8, false),
    'ثمانية': (8, true),
    'تسع': (9, false),
    'تسعة': (9, true),
    'عشر': (10, false),
    'عشرة': (10, true),
  };
  static const Map<String, String> _unitOther = <String, String>{
    'ثلاث': 'ثلاثة',
    'ثلاثة': 'ثلاث',
    'أربع': 'أربعة',
    'أربعة': 'أربع',
    'اربع': 'اربعة',
    'اربعة': 'اربع',
    'خمس': 'خمسة',
    'خمسة': 'خمس',
    'ست': 'ستة',
    'ستة': 'ست',
    'سبع': 'سبعة',
    'سبعة': 'سبع',
    'ثمان': 'ثمانية',
    'ثماني': 'ثمانية',
    'ثمانية': 'ثماني',
    'تسع': 'تسعة',
    'تسعة': 'تسع',
    'عشر': 'عشرة',
    'عشرة': 'عشر',
  };
  static const List<String> _numeralPrefixes = <String>[
    '', 'و', 'ف', 'ب', 'ل', 'ك', 'وب', 'ول', 'فب', 'فل', 'وك', //
  ];

  /// Singular nouns without a feminine marker that are feminine or of
  /// either gender (body parts, natural phenomena and a few common words),
  /// plus masculine nouns with ta marbuta. The analyzer may tag their
  /// plurals with one gender only, so numeral gender is not judged for
  /// them (أربع أصابع and أربعة أصابع are both used).
  static const Set<String> _eitherGenderLemmas = <String>{
    'إصبع', 'أصبع', 'عين', 'أذن', 'ساق', 'قدم', 'كتف', 'كف', 'سن', 'ضلع', //
    'كبد', 'ذراع', 'عنق', 'لسان', 'نفس', 'روح', 'أرض', 'شمس', 'نار', 'دار',
    'ريح', 'حرب', 'بئر', 'كأس', 'عصا', 'طريق', 'سوق', 'سبيل', 'حال', 'سلاح',
    'سكين', 'فرس', 'ضبع', 'عقرب', 'أفعى', 'دلو', 'ملح', 'فلك', 'قوس', 'درع',
    'رحم', 'إبط', 'خمر', 'سماء', 'خليفة', 'علامة', 'رحالة', 'داعية', 'راوية',
    'نابغة', 'طاغية',
  };

  /// Units that combine with عشر/عشرة into 11–19.
  static const Set<String> _teenUnits = <String>{
    'أحد', 'احد', 'إحدى', 'احدى', 'اثنا', 'اثني', 'اثنتا', 'اثنتي', //
    'ثلاث', 'ثلاثة', 'أربع', 'أربعة', 'اربع', 'اربعة', 'خمس', 'خمسة',
    'ست', 'ستة', 'سبع', 'سبعة', 'ثمان', 'ثماني', 'ثمانية', 'تسع', 'تسعة',
  };

  /// Indefinite tens 20–90 (nominative and oblique spelling).
  static const Set<String> _tens = <String>{
    'عشرون', 'عشرين', 'ثلاثون', 'ثلاثين', 'أربعون', 'أربعين', //
    'اربعون', 'اربعين', 'خمسون', 'خمسين', 'ستون', 'ستين', 'سبعون',
    'سبعين', 'ثمانون', 'ثمانين', 'تسعون', 'تسعين',
  };

  /// Copular verbs (kana and her sisters that need no preceding negation),
  /// as plain lemmas.
  static const Set<String> _kanaLemmas = <String>{
    'كان', 'أصبح', 'أضحى', 'أمسى', 'بات', 'ظل', 'صار', 'ليس', //
  };

  /// Inflected forms of [_kanaLemmas] whose subject is an attached plural
  /// or dual pronoun.
  static const Set<String> _kanaPluralForms = <String>{
    'كانوا', 'كانا', 'كانتا', 'كن', 'كنتم', 'كنتما', 'كنا', //
    'يكونون', 'تكونون', 'يكونوا', 'تكونوا', 'يكونان', 'تكونان', 'يكونا',
    'نكون',
    'ليسوا', 'ليسا', 'ليستا', 'لسنا', 'لستم',
    'أصبحوا', 'أصبحا', 'أصبحنا', 'يصبحون', 'تصبحون', 'يصبحوا',
    'أضحوا', 'أمسوا', 'باتوا', 'ظلوا', 'يظلون', 'صاروا', 'يصيرون',
  };

  /// Third-person singular forms of [_kanaLemmas].
  static const Set<String> _kanaSingularForms = <String>{
    'كان', 'كانت', 'يكون', 'تكون', 'ليس', 'ليست', 'أصبح', 'أصبحت', //
    'يصبح', 'تصبح', 'أضحى', 'أضحت', 'أمسى', 'أمست', 'بات', 'باتت',
    'ظل', 'ظلت', 'يظل', 'تظل', 'صار', 'صارت', 'يصير', 'تصير',
  };

  /// Attached pronouns, in the order the prepositions combine with them.
  static const List<String> _pronouns = <String>[
    'ه', 'ها', 'هم', 'هما', 'هن', 'ك', 'كم', 'كما', 'كن', 'نا', 'ي', //
  ];

  /// The form of a preposition with an attached pronoun.
  static String _withPronoun(String preposition, String pronoun) {
    switch (preposition) {
      case 'على':
        return pronoun == 'ي' ? 'عليّ' : 'علي$pronoun';
      case 'إلى':
        return pronoun == 'ي' ? 'إليّ' : 'إلي$pronoun';
      case 'لدى':
        return pronoun == 'ي' ? 'لديّ' : 'لدي$pronoun';
      case 'في':
        return pronoun == 'ي' ? 'فيّ' : 'في$pronoun';
      case 'عن':
      case 'من':
        // The nun of the preposition merges with نا: عنّا، منّا.
        return '$preposition${pronoun == 'نا' ? 'ا' : pronoun}';
      default:
        return '$preposition$pronoun';
    }
  }

  /// Bare spelling of a preposition (+ pronoun) -> attached pronoun or ''.
  static Map<String, String> _prepositionForms(String preposition) {
    final Map<String, String> forms = <String, String>{preposition: ''};
    for (final String pronoun in _pronouns) {
      forms[ArabicWritingRulesProvider._bare(
            _withPronoun(preposition, pronoun),
          ).$1] =
          pronoun;
    }
    return forms;
  }

  static const String _defaultRule = 'ar.grammar.verb-preposition';
  static const String _usageRule = 'ar.usage.verb-preposition';

  /// Authored verb–preposition lexicon. Default entries are colloquial
  /// constructions; the opt-in entries follow the stricter standard.
  static const List<ArabicVerbPrepositionForTesting> _verbPrepositions =
      <ArabicVerbPrepositionForTesting>[
        ArabicVerbPrepositionForTesting(
          'سأل',
          'على',
          'عن',
          ruleId: _defaultRule,
          pronounOnly: true,
          message: '«سأل عليه» عامية؛ في الفصحى «سأل عنه».',
        ),
        ArabicVerbPrepositionForTesting(
          'بحث',
          'على',
          'عن',
          ruleId: _defaultRule,
          pronounOnly: true,
          message: '«بحث عليه» عامية؛ في الفصحى «بحث عنه».',
        ),
        ArabicVerbPrepositionForTesting(
          'فتش',
          'على',
          'عن',
          ruleId: _defaultRule,
          pronounOnly: true,
          message: '«فتّش عليه» بمعنى طلبه عامية؛ في الفصحى «فتّش عنه».',
        ),
        ArabicVerbPrepositionForTesting(
          'اتصل',
          'على',
          'ب',
          ruleId: _usageRule,
          message: '«اتصل» يتعدى بالباء: «اتصل به».',
        ),
        ArabicVerbPrepositionForTesting(
          'أكد',
          'على',
          '',
          ruleId: _usageRule,
          message: '«أكّد» يتعدى بنفسه: «أكّد الأمرَ».',
        ),
        ArabicVerbPrepositionForTesting(
          'أثر',
          'على',
          'في',
          ruleId: _usageRule,
          message: 'الأفصح «أثّر في».',
        ),
        ArabicVerbPrepositionForTesting(
          'حاز',
          'على',
          '',
          ruleId: _usageRule,
          message: '«حاز» يتعدى بنفسه: «حاز الجائزةَ».',
        ),
        ArabicVerbPrepositionForTesting(
          'تخرج',
          'من',
          'في',
          ruleId: _usageRule,
          message: 'الأفصح «تخرّج في» الجامعة.',
        ),
        ArabicVerbPrepositionForTesting(
          'أجاب',
          'على',
          'عن',
          ruleId: _usageRule,
          message: 'الأفصح «أجاب عن السؤال».',
        ),
        ArabicVerbPrepositionForTesting(
          'تعرف',
          'على',
          'إلى',
          ruleId: _usageRule,
          message: 'الأفصح «تعرّف إليه» أو «تعرّفه».',
        ),
        ArabicVerbPrepositionForTesting(
          'عرف',
          'على',
          'ب',
          ruleId: _usageRule,
          pronounOnly: true,
          message: '«عرّفه به» أو «عرّفه إليه»، لا «عليه».',
        ),
        ArabicVerbPrepositionForTesting(
          'تزوج',
          'من',
          '',
          ruleId: _usageRule,
          message: '«تزوّج» يتعدى بنفسه: «تزوّجها».',
        ),
        ArabicVerbPrepositionForTesting(
          'التقى',
          'مع',
          '',
          ruleId: _usageRule,
          message: '«التقى» يتعدى بنفسه: «التقى صديقَه».',
        ),
        ArabicVerbPrepositionForTesting(
          'زاد',
          'عن',
          'على',
          ruleId: _usageRule,
          message: '«زاد» يتعدى بـ«على»: «يزيد على المئة».',
        ),
        ArabicVerbPrepositionForTesting(
          'اعتذر',
          'على',
          'عن',
          ruleId: _usageRule,
          message: 'يُعتذر «عن» الخطأ و«إلى» الشخص.',
        ),
        ArabicVerbPrepositionForTesting(
          'اشتكى',
          'على',
          'من',
          ruleId: _usageRule,
          message: 'الأفصح «اشتكى منه» أو «شكاه».',
        ),
        ArabicVerbPrepositionForTesting(
          'قارن',
          'مع',
          'ب',
          ruleId: _usageRule,
          message: 'الأفصح «قارنه به».',
        ),
        ArabicVerbPrepositionForTesting(
          'دخل',
          'إلى',
          '',
          ruleId: _usageRule,
          message: '«دخل» يتعدى بنفسه: «دخل البيتَ».',
        ),
        ArabicVerbPrepositionForTesting(
          'استقال',
          'عن',
          'من',
          ruleId: _usageRule,
          message: 'يُستقال «من» المنصب.',
        ),
        ArabicVerbPrepositionForTesting(
          'تحدث',
          'حول',
          'عن',
          ruleId: _usageRule,
          message: '«تحدّث حول» ترجمة حرفية؛ الأفصح «تحدّث عن».',
        ),
        ArabicVerbPrepositionForTesting(
          'تكلم',
          'حول',
          'عن',
          ruleId: _usageRule,
          message: '«تكلّم حول» ترجمة حرفية؛ الأفصح «تكلّم عن».',
        ),
      ];

  /// Words after a preposition that begin an adverbial phrase rather than
  /// the verb's governed object ("أكّد على هامش المؤتمر").
  static const Map<String, Set<String>> _adverbialAfter = <String, Set<String>>{
    'على': <String>{
      'الفور', 'عجل', 'استحياء', 'انفراد', 'حدة', 'التوالي', 'مضض', //
      'سبيل', 'نحو', 'الأقل', 'الأرجح', 'الأغلب', 'الرغم', 'غرار', 'وجه',
      'مدى', 'مدار', 'حين', 'إثر', 'اثر', 'أثر', 'هامش', 'خلفية', 'ضوء',
      'لسان', 'الملأ', 'الهواء', 'الإطلاق', 'الدوام', 'أساس', 'صعيد',
      'مستوى', 'امتداد', 'طول', 'رأس', 'يد', 'يدي', 'حساب', 'هيئة', 'شكل',
      'إثره', 'أثره', 'حد', 'خلاف', 'العكس', 'النقيض', 'قدم', 'الأرض',
      'الصعيد', 'المستوى', 'الأكثر', 'التقريب', 'وقع', 'مسامع', 'عاتق',
      'عاتقه', 'مستواه',
    },
    'من': <String>{
      'جديد', 'جهة', 'جهته', 'قبل', 'خلال', 'أجل', 'حيث', 'ناحية', 'بين', //
      'دون', 'ضمن', 'ثم', 'بعد', 'جانب', 'جانبه', 'جانبها', 'أصل', 'طرف',
    },
    'عن': <String>{'طريق', 'قرب', 'كثب', 'بعد', 'عمد', 'كثير'},
    'إلى': <String>{'جانب', 'حد', 'حين', 'أن', 'غاية', 'جانبه'},
    'مع': <String>{'ذلك', 'بداية', 'مرور', 'نهاية', 'مطلع', 'حلول'},
    'حول': <String>{'العالم'},
  };

  /// Lemma-matched usage hints (lemma -> preferred lemma), extending the
  /// fixed forms of `ar.usage.word` to every inflection.
  static const Map<String, String> _inflectedUsage = <String, String>{
    'ساهم': 'أسهم',
    'تواجد': 'وُجد',
    'استلم': 'تسلّم',
    'احتار': 'حار',
    'توفر': 'توافر',
  };

  /// Cheap spelling filters that decide which words are worth analyzing for
  /// [_inflectedUsage].
  static final RegExp _inflectedUsageFilter = RegExp(
    'ساهم|واجد|ستلم|حتار|حتر|وفر',
  );

  // ---------------------------------------------------------------- helpers

  /// The lemma without harakat; ٱ (alif wasla) written as plain alif.
  static String _plain(String? lex) =>
      (lex ?? '').replaceAll(_harakat, '').replaceAll('ٱ', 'ا');

  static bool _adjacentPair(List<RegExpMatch> words, String text, int w) =>
      w > 0 &&
      w < words.length &&
      _spaces.hasMatch(text.substring(words[w - 1].end, words[w].start));

  bool _adjacent(int w) => _adjacentPair(words, text, w);

  /// The analyses a rule reasons over for word [w]: its confident context
  /// reading when there is one, otherwise every analysis.
  List<ArabicAnalysis> _of(int w) =>
      _confident[w] ??
      _analyses[words[w].group(0)!] ??
      const <ArabicAnalysis>[];

  /// Fills [_confident] for the words in [wanted] from the context model.
  Future<void> _disambiguate(Set<String> wanted) async {
    final ArabicMorphology analyzer = morphology;
    if (!contextual ||
        analyzer is! ArabicContextMorphology ||
        !analyzer.canDisambiguate) {
      return;
    }
    // Only the sentences holding a word some rule needs.
    final List<List<ArabicContextToken>> sentences = <List<ArabicContextToken>>[
      for (final List<ArabicContextToken> s in arabicContextSentences(text))
        if (s.any((ArabicContextToken t) => wanted.contains(t.text))) s,
    ];
    if (sentences.isEmpty) return;
    final List<List<ArabicContextReading>> readings;
    try {
      readings = await analyzer.disambiguate(<List<String>>[
        for (final List<ArabicContextToken> s in sentences)
          <String>[for (final ArabicContextToken t in s) t.text],
      ]);
    } on Object {
      return;
    }
    if (readings.length != sentences.length) return;
    final Map<int, ArabicContextReading> byStart =
        <int, ArabicContextReading>{};
    final Map<int, int> endOf = <int, int>{};
    for (int s = 0; s < sentences.length; s++) {
      if (readings[s].length != sentences[s].length) return;
      for (int t = 0; t < sentences[s].length; t++) {
        byStart[sentences[s][t].start] = readings[s][t];
        endOf[sentences[s][t].start] = sentences[s][t].end;
      }
    }
    final Map<int, List<ArabicAnalysis>> confident =
        <int, List<ArabicAnalysis>>{};
    for (int w = 0; w < words.length; w++) {
      final RegExpMatch match = words[w];
      if (!wanted.contains(match.group(0)) || endOf[match.start] != match.end) {
        continue;
      }
      final List<ArabicAnalysis>? best = byStart[match.start]?.confident(
        contextMinMargin,
      );
      if (best != null && best.isNotEmpty) confident[w] = best;
    }
    _confident = confident;
  }

  static bool _isProp(ArabicAnalysis a) => a['pos'] == 'noun_prop';

  static bool _hasClitics(ArabicAnalysis a) {
    for (final String key in const <String>[
      'prc0',
      'prc1',
      'prc2',
      'prc3',
      'enc0',
    ]) {
      final String? value = a[key];
      if (value != null && value != '0' && value != 'na') return true;
    }
    return false;
  }

  static bool _isNominal(ArabicAnalysis a) => const <String>{
    'noun',
    'adj',
    'noun_num',
    'adj_num',
    'noun_quant',
    'adj_comp',
    'noun_prop',
    'pron_dem',
  }.contains(a['pos']);

  /// Every analysis is a nominative noun whose case shows in the spelling:
  /// a sound dual or masculine plural ending in ـان/ـون, a dual numeral in
  /// construct (اثنا), or a dual demonstrative. At least one reading must be
  /// a common noun or adjective without a conjunction or question prefix:
  /// otherwise the word is an unknown name the analyzer inflected as a
  /// proper noun (يوكاتان) or split into unlikely clitics.
  static bool _visiblyNominative(List<ArabicAnalysis> analyses, String bare) {
    if (analyses.isEmpty) return false;
    final bool soundEnding = bare.endsWith('ون') || bare.endsWith('ان');
    bool plain = false;
    for (final ArabicAnalysis a in analyses) {
      if (a['cas'] != 'n' || !_isNominal(a)) return false;
      final bool soundForm =
          (soundEnding &&
              (a['form_num'] == 'd' ||
                  (a['form_num'] == 'p' && a['form_gen'] == 'm'))) ||
          (a['form_num'] == 'd' && _plain(a['lex']).startsWith('اثن')) ||
          (a['pos'] == 'pron_dem' && a['num'] == 'd');
      if (!soundForm) return false;
      if (!_isProp(a) &&
          (a['prc2'] ?? '0') == '0' &&
          (a['prc3'] ?? '0') == '0') {
        plain = true;
      }
    }
    if (!plain) return false;
    if (!bare.startsWith('ال')) return true;
    // A definite plural beside a proper-noun reading of the same stem
    // (السراجون beside the name سراج) may be a family or place name, which
    // keeps its form.
    final Set<String> common = <String>{
      for (final ArabicAnalysis a in analyses)
        if (!_isProp(a)) _plain(a['lex']),
    };
    return !analyses.any(
      (ArabicAnalysis a) => _isProp(a) && common.contains(_plain(a['lex'])),
    );
  }

  /// The oblique (accusative/genitive) spelling of a sound dual or masculine
  /// plural, or null when the ending is not recognized.
  static List<String> _obliqueSpellings(String bare) {
    final List<String> out = <String>[];
    if (bare.endsWith('ون') || bare.endsWith('ان')) {
      out.add('${bare.substring(0, bare.length - 2)}ين');
    }
    // Construct state, possibly with an attached pronoun: معلمو(هم).
    for (final String pronoun in <String>['', ..._pronouns]) {
      if (!bare.endsWith(pronoun)) continue;
      final String stem = bare.substring(0, bare.length - pronoun.length);
      if (stem.length < 3) continue;
      if (stem.endsWith('و') || stem.endsWith('ا')) {
        if (pronoun.isEmpty && (bare.endsWith('ون') || bare.endsWith('ان'))) {
          continue;
        }
        out.add('${stem.substring(0, stem.length - 1)}ي$pronoun');
      }
    }
    return out;
  }

  String _respelled(int w, String bareTarget) {
    final String word = words[w].group(0)!;
    final (String bare, List<int> at) = ArabicWritingRulesProvider._bare(word);
    return ArabicWritingRulesProvider._respell(word, bare, at, bareTarget) ??
        bareTarget;
  }

  Set<String> _lexes(List<ArabicAnalysis> analyses) => <String>{
    for (final ArabicAnalysis a in analyses) _plain(a['lex']),
  };

  // -------------------------------------------------------------------- run

  Future<void> run() async {
    if (!morphology.isAvailable) return;
    if (!<String>{
      ...arabicGrammarDefaultRuleIds,
      ...arabicGrammarOptionalRuleIds,
    }.any(enabled)) {
      return;
    }
    final Set<String> wanted = _wantedWords();
    if (wanted.isEmpty) return;
    try {
      _analyses = await morphology.analyzeWords(wanted);
    } on Object {
      return;
    }
    await _disambiguate(wanted);

    if (enabled('ar.grammar.preposition-case')) _prepositionCase();
    if (enabled('ar.grammar.inna-case')) _innaCase();
    if (enabled('ar.grammar.kana-predicate')) _kanaPredicate();
    if (enabled('ar.grammar.dual-demonstrative')) _dualDemonstrative();
    if (enabled('ar.grammar.jussive')) _jussive();
    if (enabled('ar.grammar.subjunctive')) _subjunctiveMood();
    if (enabled('ar.grammar.la-past')) _laPast();
    if (enabled('ar.numeral.gender')) _numeralGender();
    if (enabled('ar.numeral.counted-number') ||
        enabled('ar.numeral.counted-case')) {
      _countedNoun();
    }
    if (enabled(_defaultRule) || enabled(_usageRule)) _verbPreposition();
    if (enabled('ar.usage.word-inflected')) _inflectedWord();

    // Replacements are offered only when the analyzer accepts them.
    final Set<String> probes = <String>{
      for (final _GrammarFinding f in _found)
        for (final _GrammarCandidate c in f.candidates) c.probe,
    };
    Map<String, List<ArabicAnalysis>> checked =
        const <String, List<ArabicAnalysis>>{};
    if (probes.isNotEmpty) {
      try {
        checked = await morphology.analyzeWords(probes);
      } on Object {
        checked = const <String, List<ArabicAnalysis>>{};
      }
    }
    for (final _GrammarFinding f in _found) {
      final List<String> replacements = <String>[
        ...f.fixed,
        for (final _GrammarCandidate c in f.candidates)
          if (c.accept(checked[c.probe] ?? const <ArabicAnalysis>[]))
            c.replacement,
      ];
      add(
        f.ruleId,
        f.start,
        f.end,
        f.message,
        category: f.ruleId.startsWith('ar.usage.')
            ? OfficeProofingCategory.style
            : OfficeProofingCategory.grammar,
        replacements: <String>{...replacements}.toList(),
      );
    }
  }

  /// The surface words whose analyses some enabled rule needs.
  Set<String> _wantedWords() {
    final Set<String> wanted = <String>{};
    void next(int w) {
      if (w + 1 < words.length && _adjacent(w + 1)) {
        wanted.add(words[w + 1].group(0)!);
      }
    }

    final Set<String> verbPrepositionWords = <String>{
      for (final ArabicVerbPrepositionForTesting e in _verbPrepositions)
        if (enabled(e.ruleId)) ..._prepositionForms(e.wrong).keys,
    };
    for (int w = 0; w < words.length; w++) {
      final String bare = bares[w];
      if (enabled('ar.grammar.preposition-case')) {
        if (_prepositions.contains(bare)) next(w);
        if (_attachedArticleStem(bare) != null) wanted.add(words[w].group(0)!);
      }
      if (enabled('ar.grammar.inna-case') && _inna.contains(bare)) next(w);
      if (enabled('ar.grammar.kana-predicate')) {
        final String unprefixed = _withoutConjunction(bare);
        if (_kanaPluralForms.contains(unprefixed)) {
          wanted.add(words[w].group(0)!);
          next(w);
        }
        if (_kanaSingularForms.contains(unprefixed)) {
          wanted.add(words[w].group(0)!);
          next(w);
          if (w + 2 < words.length && _adjacent(w + 1) && _adjacent(w + 2)) {
            wanted.add(words[w + 2].group(0)!);
          }
        }
      }
      if (enabled('ar.grammar.dual-demonstrative') &&
          _dualDemonstratives.containsKey(_withoutConjunction(bare))) {
        next(w);
      }
      if (enabled('ar.grammar.jussive') && _lam.contains(bare)) next(w);
      if (enabled('ar.grammar.subjunctive') && _subjunctive.contains(bare)) {
        next(w);
      }
      if (enabled('ar.grammar.la-past') && bare == 'لا') next(w);
      if (enabled('ar.numeral.gender') && _unitOf(bare) != null) {
        wanted.add(words[w].group(0)!);
        next(w);
      }
      if ((enabled('ar.numeral.counted-number') ||
              enabled('ar.numeral.counted-case')) &&
          _countedAfter(w)) {
        next(w);
      }
      if (verbPrepositionWords.contains(bare) && w > 0 && _adjacent(w)) {
        wanted.add(words[w - 1].group(0)!);
      }
      if (enabled('ar.usage.word-inflected') &&
          _inflectedUsageFilter.hasMatch(bare)) {
        wanted.add(words[w].group(0)!);
      }
    }
    // Stems of words with an attached preposition and article (بالـ, للـ).
    if (enabled('ar.grammar.preposition-case')) {
      for (int w = 0; w < words.length; w++) {
        final (String, String)? split = _attachedArticleStem(bares[w]);
        if (split != null) wanted.add(split.$2);
      }
    }
    return wanted;
  }

  static String _withoutConjunction(String bare) =>
      bare.length > 3 && (bare.startsWith('و') || bare.startsWith('ف'))
      ? bare.substring(1)
      : bare;

  /// (prefix, stem) for a word written as preposition + article + noun:
  /// `بالمعلمون` -> (`ب`, `المعلمون`), `للمعلمون` -> (`ل`, `المعلمون`).
  static (String, String)? _attachedArticleStem(String bare) {
    for (final String conjunction in const <String>['', 'و', 'ف']) {
      if (!bare.startsWith(conjunction)) continue;
      final String rest = bare.substring(conjunction.length);
      if (rest.length < 7) continue;
      if (rest.startsWith('بال') || rest.startsWith('كال')) {
        return ('$conjunction${rest[0]}', rest.substring(1));
      }
      if (rest.startsWith('لل') && !rest.startsWith('للل')) {
        return ('$conjunction${'ل'}', 'ا${rest.substring(1)}');
      }
    }
    return null;
  }

  /// (bare numeral without prefix, prefix) when [bare] is a 3–10 numeral.
  static (String, String)? _unitOf(String bare) {
    for (final String prefix in _numeralPrefixes) {
      if (!bare.startsWith(prefix)) continue;
      final String rest = bare.substring(prefix.length);
      if (_units.containsKey(rest)) return (rest, prefix);
    }
    return null;
  }

  static String? _tensOf(String bare) {
    for (final String prefix in _numeralPrefixes) {
      if (!bare.startsWith(prefix)) continue;
      final String rest = bare.substring(prefix.length);
      if (_tens.contains(rest)) return rest;
    }
    return null;
  }

  /// Whether word [w] is the last word of a numeral 11–99, so the next word
  /// is its counted noun.
  bool _countedAfter(int w) {
    if (_tensOf(bares[w]) != null) return true;
    if ((bares[w] == 'عشر' || bares[w] == 'عشرة') && w > 0 && _adjacent(w)) {
      final (String, String)? unit = _unitOrTeen(bares[w - 1]);
      return unit != null;
    }
    return false;
  }

  static (String, String)? _unitOrTeen(String bare) {
    for (final String prefix in _numeralPrefixes) {
      if (!bare.startsWith(prefix)) continue;
      final String rest = bare.substring(prefix.length);
      if (_teenUnits.contains(rest)) return (rest, prefix);
    }
    return null;
  }

  // ------------------------------------------------------------------ rules

  /// G7: a sound dual or masculine plural directly after a preposition must
  /// be genitive (ـين, or ـي in construct).
  void _prepositionCase() {
    const String message =
        'بعد حرف الجر يأتي الاسم مجرورًا: المثنى وجمع المذكر السالم '
        'يُجرّان بالياء.';
    for (int w = 0; w + 1 < words.length; w++) {
      if (!_prepositions.contains(bares[w]) || !_adjacent(w + 1)) continue;
      _reportOblique('ar.grammar.preposition-case', w + 1, message, 'g');
    }
    // Attached preposition + article: بالمعلمون, للمهندسان.
    for (int w = 0; w < words.length; w++) {
      final (String, String)? split = _attachedArticleStem(bares[w]);
      if (split == null || _of(w).isNotEmpty) continue;
      final List<ArabicAnalysis> stem =
          _analyses[split.$2] ?? const <ArabicAnalysis>[];
      if (!_visiblyNominative(stem, split.$2)) continue;
      final Set<String> lexes = _lexes(stem);
      final String prefix = split.$1;
      _found.add(
        _GrammarFinding(
          'ar.grammar.preposition-case',
          words[w].start,
          words[w].end,
          message,
          candidates: <_GrammarCandidate>[
            for (final String oblique in _obliqueSpellings(split.$2))
              _GrammarCandidate(
                prefix.endsWith('ل')
                    ? '$prefix${oblique.substring(1)}'
                    : '$prefix$oblique',
                oblique,
                (List<ArabicAnalysis> a) => a.any(
                  (ArabicAnalysis x) =>
                      x['cas'] == 'g' && lexes.contains(_plain(x['lex'])),
                ),
              ),
          ],
        ),
      );
    }
  }

  /// Reports word [w] when it is visibly nominative; offers the oblique
  /// spelling the analyzer confirms with case [cas].
  void _reportOblique(String ruleId, int w, String message, String cas) {
    final List<ArabicAnalysis> analyses = _of(w);
    if (!_visiblyNominative(analyses, bares[w])) return;
    final Set<String> lexes = _lexes(analyses);
    final String bare = bares[w];
    _found.add(
      _GrammarFinding(
        ruleId,
        words[w].start,
        words[w].end,
        message,
        candidates: <_GrammarCandidate>[
          for (final String oblique in _obliqueSpellings(bare))
            _GrammarCandidate(
              _respelled(w, oblique),
              oblique,
              (List<ArabicAnalysis> a) => a.any(
                (ArabicAnalysis x) =>
                    x['cas'] == cas && lexes.contains(_plain(x['lex'])),
              ),
            ),
        ],
      ),
    );
  }

  /// G8: the subject directly after inna and her sisters is accusative.
  void _innaCase() {
    const String message =
        'اسم «إنّ» وأخواتها منصوب: المثنى وجمع المذكر السالم يُنصبان '
        'بالياء.';
    for (int w = 0; w + 1 < words.length; w++) {
      if (!_inna.contains(bares[w]) || !_adjacent(w + 1)) continue;
      // Pronoun subjects of a dual demonstrative are left to G2.
      final List<ArabicAnalysis> next = _of(w + 1);
      if (next.any((ArabicAnalysis a) => a['pos'] == 'pron_dem')) continue;
      _reportOblique('ar.grammar.inna-case', w + 1, message, 'a');
    }
  }

  /// G9 (visible part): the predicate of kana and her sisters is
  /// accusative. Two shapes only: a verb with an attached plural/dual
  /// subject followed directly by an indefinite nominative plural/dual
  /// (`كانوا مجتهدون`), and a singular verb + one definite word + such a
  /// word (`كان الطلاب مجتهدون`).
  void _kanaPredicate() {
    const String message =
        'خبر «كان» وأخواتها منصوب: المثنى وجمع المذكر السالم يُنصبان '
        'بالياء.';
    bool isKana(int w) {
      final List<ArabicAnalysis> analyses = <ArabicAnalysis>[
        for (final ArabicAnalysis a in _of(w))
          if (!_isProp(a)) a,
      ];
      return analyses.isNotEmpty &&
          analyses.every(
            (ArabicAnalysis a) =>
                a['pos'] == 'verb' && _kanaLemmas.contains(_plain(a['lex'])),
          );
    }

    bool indefinitePredicate(int w) {
      final List<ArabicAnalysis> analyses = _of(w);
      return _visiblyNominative(analyses, bares[w]) &&
          analyses.every((ArabicAnalysis a) => _isProp(a) || !_hasClitics(a));
    }

    for (int w = 0; w + 1 < words.length; w++) {
      final String bare = _withoutConjunction(bares[w]);
      if (_kanaPluralForms.contains(bare) &&
          _adjacent(w + 1) &&
          isKana(w) &&
          indefinitePredicate(w + 1)) {
        _reportOblique('ar.grammar.kana-predicate', w + 1, message, 'a');
        continue;
      }
      if (_kanaSingularForms.contains(bare) &&
          w + 2 < words.length &&
          _adjacent(w + 1) &&
          _adjacent(w + 2) &&
          isKana(w)) {
        final List<ArabicAnalysis> subject = _of(w + 1);
        final bool definite =
            subject.isNotEmpty &&
            subject.every(
              (ArabicAnalysis a) => _isNominal(a) && a['stt'] == 'd',
            );
        if (definite && indefinitePredicate(w + 2)) {
          _reportOblique('ar.grammar.kana-predicate', w + 2, message, 'a');
        }
      }
    }
  }

  /// G2: a dual demonstrative and the definite dual after it share a case.
  void _dualDemonstrative() {
    const String message =
        'اسم الإشارة المثنى والاسم بعده متطابقان في الإعراب: «هذان '
        'الكتابان» رفعًا، و«هذين الكتابين» نصبًا وجرًّا.';
    for (int w = 0; w + 1 < words.length; w++) {
      final String bare = bares[w];
      final String core = _withoutConjunction(bare);
      final bool? nominative = _dualDemonstratives[core];
      if (nominative == null || !_adjacent(w + 1)) continue;
      if (!bares[w + 1].startsWith('ال')) continue;
      final List<ArabicAnalysis> next = _of(w + 1);
      if (next.isEmpty ||
          !next.every((ArabicAnalysis a) => _isNominal(a) && a['num'] == 'd')) {
        continue;
      }
      // `u` (case left open) accompanies every unvowelled noun reading, so
      // only an explicit case counts.
      final Set<String> compatible = nominative
          ? const <String>{'n'}
          : const <String>{'a', 'g'};
      if (next.any((ArabicAnalysis a) => compatible.contains(a['cas']))) {
        continue;
      }
      final String prefix = bare.substring(0, bare.length - core.length);
      final String nounBare = bares[w + 1];
      final Set<String> lexes = _lexes(next);
      final String otherNoun = nominative
          ? (nounBare.endsWith('ين')
                ? '${nounBare.substring(0, nounBare.length - 2)}ان'
                : nounBare)
          : (nounBare.endsWith('ان')
                ? '${nounBare.substring(0, nounBare.length - 2)}ين'
                : nounBare);
      final String gap = text.substring(words[w].end, words[w + 1].start);
      _found.add(
        _GrammarFinding(
          'ar.grammar.dual-demonstrative',
          words[w].start,
          words[w + 1].end,
          message,
          fixed: <String>[
            '$prefix${_dualDemonstrativeOther[core]}$gap${words[w + 1].group(0)}',
          ],
          candidates: <_GrammarCandidate>[
            if (otherNoun != nounBare)
              _GrammarCandidate(
                '${words[w].group(0)}$gap${_respelled(w + 1, otherNoun)}',
                otherNoun,
                (List<ArabicAnalysis> a) => a.any(
                  (ArabicAnalysis x) =>
                      lexes.contains(_plain(x['lex'])) &&
                      (nominative
                          ? x['cas'] == 'n'
                          : (x['cas'] == 'a' || x['cas'] == 'g')),
                ),
              ),
          ],
        ),
      );
    }
  }

  /// Every analysis is an imperfect verb without the mood(s) in [moods]
  /// and without a future prefix.
  static bool _imperfectOnlyWithout(
    List<ArabicAnalysis> analyses,
    Set<String> moods,
  ) {
    if (analyses.isEmpty) return false;
    for (final ArabicAnalysis a in analyses) {
      if (a['pos'] != 'verb' || a['asp'] != 'i') return false;
      if (moods.contains(a['mod']) || a['mod'] == 'u') return false;
      if (a['prc1'] != null && a['prc1'] != '0' && a['prc1'] != 'na') {
        return false;
      }
    }
    return true;
  }

  /// Bare spellings of the five verbs without their final nun.
  static List<String> _withoutFiveVerbsNun(String bare) => <String>[
    if (bare.endsWith('ون')) '${bare.substring(0, bare.length - 1)}ا',
    if (bare.endsWith('ان')) bare.substring(0, bare.length - 1),
    if (bare.endsWith('ين') && bare.startsWith('ت'))
      bare.substring(0, bare.length - 1),
  ];

  /// G5: an imperfect verb after لم is jussive. Only spellings that no
  /// jussive analysis allows are reported (the five verbs keeping their
  /// nun, a kept weak final letter, a kept long vowel of a hollow verb).
  void _jussive() {
    const String message =
        'الفعل المضارع بعد «لم» مجزوم: تُحذف نون الأفعال الخمسة، ويُحذف '
        'حرف العلة من آخر الفعل المعتل، وتُحذف عين الأجوف الساكنة.';
    for (int w = 0; w + 1 < words.length; w++) {
      if (!_lam.contains(bares[w]) || !_adjacent(w + 1)) continue;
      // لِمَ ("why") written with its vowels.
      final String particle = words[w].group(0)!;
      if (particle.contains('َ', particle.indexOf('م')) ||
          particle.contains('ِ')) {
        continue;
      }
      if (_inQuestion(w)) continue;
      final List<ArabicAnalysis> verb = _of(w + 1);
      if (!_imperfectOnlyWithout(verb, const <String>{'j'})) continue;
      final String bare = bares[w + 1];
      final List<String> fiveVerbs = _withoutFiveVerbsNun(bare);
      final List<String> targets = <String>[
        ...fiveVerbs,
        if (fiveVerbs.isEmpty) ...<String>[
          if (RegExp('[يوى]\$').hasMatch(bare) && bare.length > 2)
            bare.substring(0, bare.length - 1),
          if (bare.length > 3 && 'اوي'.contains(bare[bare.length - 2]))
            '${bare.substring(0, bare.length - 2)}${bare[bare.length - 1]}',
        ],
      ];
      _found.add(
        _GrammarFinding(
          'ar.grammar.jussive',
          words[w + 1].start,
          words[w + 1].end,
          message,
          candidates: <_GrammarCandidate>[
            for (final String target in targets)
              _GrammarCandidate(
                _respelled(w + 1, target),
                target,
                (List<ArabicAnalysis> a) => _sameVerbInMood(verb, a, 'j'),
              ),
          ],
        ),
      );
    }
  }

  /// Whether [candidate] has an analysis in mood [mood] with the lemma,
  /// person, gender and number of one of the [original] analyses.
  static bool _sameVerbInMood(
    List<ArabicAnalysis> original,
    List<ArabicAnalysis> candidate,
    String mood,
  ) => candidate.any(
    (ArabicAnalysis x) =>
        x['pos'] == 'verb' &&
        x['mod'] == mood &&
        original.any(
          (ArabicAnalysis o) =>
              _plain(o['lex']) == _plain(x['lex']) &&
              o['per'] == x['per'] &&
              o['gen'] == x['gen'] &&
              o['num'] == x['num'],
        ),
  );

  /// Whether the sentence of word [w] ends with a question mark.
  bool _inQuestion(int w) {
    for (int i = words[w].end; i < text.length; i++) {
      final String c = text[i];
      if (c == '؟' || c == '?') return true;
      if (c == '.' || c == '!' || c == '\n') return false;
    }
    return false;
  }

  /// G5 extended to the subjunctive: the five verbs drop their nun after
  /// لن, كي and أن.
  void _subjunctiveMood() {
    const String message =
        'الفعل المضارع بعد «لن» و«كي» و«أن» منصوب: تُحذف نون الأفعال '
        'الخمسة.';
    for (int w = 0; w + 1 < words.length; w++) {
      if (!_subjunctive.contains(bares[w]) || !_adjacent(w + 1)) continue;
      final List<ArabicAnalysis> verb = _of(w + 1);
      if (!_imperfectOnlyWithout(verb, const <String>{'s'})) continue;
      final String bare = bares[w + 1];
      final List<String> targets = _withoutFiveVerbsNun(bare);
      if (targets.isEmpty) continue;
      _found.add(
        _GrammarFinding(
          'ar.grammar.subjunctive',
          words[w + 1].start,
          words[w + 1].end,
          message,
          candidates: <_GrammarCandidate>[
            for (final String target in targets)
              _GrammarCandidate(
                _respelled(w + 1, target),
                target,
                (List<ArabicAnalysis> a) => _sameVerbInMood(verb, a, 's'),
              ),
          ],
        ),
      );
    }
  }

  /// G6: لا directly before a past verb, outside the repeated construction
  /// and fixed prayers.
  void _laPast() {
    const String message =
        '«لا» لا تنفي الماضي إلا مكررة أو في الدعاء؛ استخدم «لم» مع '
        'المضارع أو «ما» مع الماضي.';
    for (int w = 0; w + 1 < words.length; w++) {
      if (bares[w] != 'لا' || !_adjacent(w + 1)) continue;
      final List<ArabicAnalysis> verb = _of(w + 1);
      if (verb.isEmpty ||
          !verb.every(
            (ArabicAnalysis a) => a['pos'] == 'verb' && a['asp'] == 'p',
          )) {
        continue;
      }
      // لا زال is handled by the usage rules; prayers name God after the
      // verb (لا سمح الله) or use fixed verbs.
      final Set<String> lexes = _lexes(verb);
      if (lexes.contains('زال') || lexes.contains('فض')) continue;
      bool repeated = false;
      for (int k = w + 2; k < words.length; k++) {
        if (!_sameSentence(w, k)) break;
        final String b = bares[k];
        if (b == 'الله' || b == 'ولا' || b == 'لا' || b == 'فلا') {
          repeated = true;
          break;
        }
      }
      if (repeated) continue;
      _found.add(
        _GrammarFinding(
          'ar.grammar.la-past',
          words[w].start,
          words[w + 1].end,
          message,
        ),
      );
    }
  }

  bool _sameSentence(int a, int b) {
    final String between = text.substring(words[a].end, words[b].start);
    return !RegExp(r'[.!?؟\n]').hasMatch(between);
  }

  /// Plural analyses that could be a counted noun (proper-name readings are
  /// ignored: a name cannot be counted). Null when some reading is not a
  /// plural noun, so the word may not be the counted noun at all.
  List<ArabicAnalysis>? _pluralNoun(int w) {
    final List<ArabicAnalysis> analyses = <ArabicAnalysis>[
      for (final ArabicAnalysis a in _of(w))
        if (!_isProp(a)) a,
    ];
    if (analyses.isEmpty) return null;
    for (final ArabicAnalysis a in analyses) {
      if ((a['pos'] != 'noun' && a['pos'] != 'adj') || a['num'] != 'p') {
        return null;
      }
      for (final String key in const <String>['prc0', 'prc1', 'prc2', 'prc3']) {
        final String? prc = a[key];
        if (prc != null && prc != '0' && prc != 'na') return null;
      }
    }
    return analyses;
  }

  /// G10: numerals 3–10 take the gender opposite to the counted noun's
  /// singular (the analyzer's functional gender of the plural).
  void _numeralGender() {
    for (int w = 0; w + 1 < words.length; w++) {
      final (String, String)? unit = _unitOf(bares[w]);
      if (unit == null || !_adjacent(w + 1)) continue;
      final (String numeral, String prefix) = unit;
      // Part of 11–19 (ثلاثة عشر) or 13–19's second half.
      if (bares[w + 1] == 'عشر' || bares[w + 1] == 'عشرة') continue;
      if ((numeral == 'عشر' || numeral == 'عشرة') &&
          w > 0 &&
          _adjacent(w) &&
          _unitOrTeen(bares[w - 1]) != null) {
        continue;
      }
      final bool hasTa = _units[numeral]!.$2;
      // The spelling decides: the analyzer adds clitic readings to every
      // numeral (أ + ربع). Short forms that are also fractions or other
      // nouns (خُمس, سُبع, تُسع, عُشر, ثمانٍ) and لست ("I am not") are
      // left out; the word must still have a numeral reading.
      if (const <String>{
            'خمس',
            'سبع',
            'تسع',
            'عشر',
            'ثمان',
          }.contains(numeral) ||
          (numeral == 'ست' && prefix.endsWith('ل'))) {
        continue;
      }
      if (!_of(w).any((ArabicAnalysis a) => a['pos'] == 'noun_num')) continue;
      final List<ArabicAnalysis>? noun = _pluralNoun(w + 1);
      if (noun == null ||
          noun.any(
            (ArabicAnalysis a) =>
                _eitherGenderLemmas.contains(_plain(a['lex'])),
          )) {
        continue;
      }
      bool allows(ArabicAnalysis a) {
        final String? gen = a['gen'];
        // A sound feminine plural (ـات): the analyzer's gender is not the
        // singular's (مجلدات, of the masculine مجلد, is tagged feminine), and
        // usage differs for the plural of a masculine singular (اجتماعات).
        // Only a lemma with ta marbuta is known to be feminine.
        if (a['pos'] == 'noun' &&
            a['form_num'] == 'p' &&
            a['form_gen'] == 'f') {
          return !_plain(a['lex']).endsWith('ة') || !hasTa;
        }
        if (gen == 'm') return hasTa;
        if (gen == 'f') return !hasTa;
        return true;
      }

      if (noun.any(allows)) continue;
      final String other = _unitOther[numeral]!;
      final String target = '$prefix$other';
      final String source = words[w].group(0)!;
      _found.add(
        _GrammarFinding(
          'ar.numeral.gender',
          words[w].start,
          words[w].end,
          hasTa
              ? 'العدد من ثلاثة إلى عشرة يخالف مفرد المعدود في التذكير '
                    'والتأنيث: مع المؤنث يأتي العدد بلا تاء («ثلاث سيارات»).'
              : 'العدد من ثلاثة إلى عشرة يخالف مفرد المعدود في التذكير '
                    'والتأنيث: مع المذكر يأتي العدد بالتاء («ثلاثة كتب»).',
          fixed: <String>[
            ArabicWritingRulesProvider._respell(
                  source,
                  bares[w],
                  ArabicWritingRulesProvider._bare(source).$2,
                  target,
                ) ??
                target,
          ],
        ),
      );
    }
  }

  /// G11: after 11–99 the counted noun is a singular indefinite accusative.
  /// `ar.numeral.counted-number` reports a plural; the opt-in
  /// `ar.numeral.counted-case` reports a singular without the accusative
  /// ending at the end of the phrase.
  void _countedNoun() {
    for (int w = 0; w + 1 < words.length; w++) {
      if (!_countedAfter(w) || !_adjacent(w + 1)) continue;
      final List<ArabicAnalysis>? plural = _pluralNoun(w + 1);
      if (plural != null) {
        if (!enabled('ar.numeral.counted-number')) continue;
        final Set<String> lexes = _lexes(plural);
        _found.add(
          _GrammarFinding(
            'ar.numeral.counted-number',
            words[w + 1].start,
            words[w + 1].end,
            'تمييز الأعداد من أحد عشر إلى تسعة وتسعين مفرد منصوب: '
                '«عشرون طالبًا»، «خمسة عشر كتابًا».',
            candidates: <_GrammarCandidate>[
              for (final String lemma in lexes)
                if (_accusativeIndefinite(lemma) case final String target)
                  _GrammarCandidate(
                    target,
                    target,
                    (List<ArabicAnalysis> a) => a.any(
                      (ArabicAnalysis x) =>
                          x['cas'] == 'a' &&
                          x['num'] == 's' &&
                          x['stt'] == 'i' &&
                          _plain(x['lex']) == lemma,
                    ),
                  ),
            ],
          ),
        );
        continue;
      }
      if (!enabled('ar.numeral.counted-case')) continue;
      // The phrase must end after the counted noun: a following noun could
      // make it a construct (عشرون ألفَ دولار).
      if (w + 2 < words.length && _adjacent(w + 2)) continue;
      final List<ArabicAnalysis> analyses = <ArabicAnalysis>[
        for (final ArabicAnalysis a in _of(w + 1))
          if (!_isProp(a)) a,
      ];
      if (analyses.isEmpty ||
          !analyses.every(
            (ArabicAnalysis a) =>
                (a['pos'] == 'noun' || a['pos'] == 'adj') &&
                a['num'] == 's' &&
                !_hasClitics(a),
          )) {
        continue;
      }
      if (analyses.any(
        (ArabicAnalysis a) => a['cas'] == 'a' && a['stt'] == 'i',
      )) {
        continue;
      }
      final Set<String> lexes = _lexes(analyses);
      _found.add(
        _GrammarFinding(
          'ar.numeral.counted-case',
          words[w + 1].start,
          words[w + 1].end,
          'تمييز الأعداد من أحد عشر إلى تسعة وتسعين منصوب منوّن: '
              '«عشرون طالبًا».',
          candidates: <_GrammarCandidate>[
            for (final String lemma in lexes)
              if (_accusativeIndefinite(lemma) case final String target)
                _GrammarCandidate(
                  target,
                  target,
                  (List<ArabicAnalysis> a) => a.any(
                    (ArabicAnalysis x) =>
                        x['cas'] == 'a' &&
                        x['stt'] == 'i' &&
                        _plain(x['lex']) == lemma,
                  ),
                ),
          ],
        ),
      );
    }
  }

  /// The indefinite accusative spelling of a singular lemma, or null when
  /// the ending is irregular (final alif, alif maqsura or hamza).
  static String? _accusativeIndefinite(String lemma) {
    if (lemma.length < 2) return null;
    if (lemma.endsWith('ة')) return '$lemmaً';
    if (RegExp('[اىءأإآ]\$').hasMatch(lemma)) return null;
    return '$lemmaًا';
  }

  /// G15: a verb followed by a preposition it does not govern.
  void _verbPreposition() {
    for (final ArabicVerbPrepositionForTesting entry in _verbPrepositions) {
      if (!enabled(entry.ruleId)) continue;
      final Map<String, String> forms = _prepositionForms(entry.wrong);
      for (int p = 1; p < words.length; p++) {
        final String? pronoun = forms[bares[p]];
        if (pronoun == null || !_adjacent(p)) continue;
        if (entry.pronounOnly && pronoun.isEmpty) continue;
        if (pronoun.isEmpty) {
          if (p + 1 >= words.length) continue;
          final Set<String> adverbial =
              _adverbialAfter[entry.wrong] ?? const <String>{};
          if (adverbial.contains(bares[p + 1])) continue;
        }
        final List<ArabicAnalysis> verb = <ArabicAnalysis>[
          for (final ArabicAnalysis a in _of(p - 1))
            if (!_isProp(a)) a,
        ];
        if (verb.isEmpty ||
            !verb.every(
              (ArabicAnalysis a) =>
                  a['pos'] == 'verb' && _plain(a['lex']) == entry.lemma,
            )) {
          continue;
        }
        final int start = words[p].start;
        final int end = words[p].end;
        if (reported(start, end) || reported(words[p - 1].start, end)) {
          continue;
        }
        final List<String> fixed = <String>[];
        if (entry.right.isNotEmpty) {
          if (pronoun.isNotEmpty) {
            fixed.add(_withPronoun(entry.right, pronoun));
          } else if (entry.right.length > 1) {
            fixed.add(entry.right);
          }
        }
        _found.add(
          _GrammarFinding(
            entry.ruleId,
            start,
            end,
            entry.message,
            fixed: fixed,
          ),
        );
      }
    }
  }

  /// S9/L3 lemma variant: every inflection of a verb whose lemma the strict
  /// standard replaces.
  void _inflectedWord() {
    for (int w = 0; w < words.length; w++) {
      if (!_inflectedUsageFilter.hasMatch(bares[w])) continue;
      final List<ArabicAnalysis> analyses = <ArabicAnalysis>[
        for (final ArabicAnalysis a in _of(w))
          if (!_isProp(a)) a,
      ];
      if (analyses.isEmpty || analyses.any((a) => a['pos'] != 'verb')) {
        continue;
      }
      final Set<String> lexes = _lexes(analyses);
      if (lexes.length != 1) continue;
      final String? preferred = _inflectedUsage[lexes.single];
      if (preferred == null) continue;
      if (reported(words[w].start, words[w].end)) continue;
      _found.add(
        _GrammarFinding(
          'ar.usage.word-inflected',
          words[w].start,
          words[w].end,
          'يُفضّل في الفصحى الدقيقة الفعل «$preferred» بدل «${lexes.single}» '
              'بتصريفه المناسب.',
        ),
      );
    }
  }
}
