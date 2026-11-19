part of 'arabic_writing_rules.dart';

// Clean-room tier-T1 extension of the Arabic writing rules.
//
// Written only from the abstract specification in
// docs/roadmaps/arabic-rule-spec.md (categories, not content). Every word
// list, message and example here was authored for Quds from general
// knowledge of Modern Standard Arabic; no external rule set, word list or
// corpus of errors was consulted. T1 means closed word classes and string
// context only: there is no morphology lexicon and no part-of-speech tagger,
// so every rule is deliberately conservative.

/// Extended T1 rule ids that run by default.
const Set<String> arabicExtendedDefaultRuleIds = <String>{
  'ar.punctuation.doubled',
  'ar.punctuation.unpaired',
  'ar.spacing.multiple',
  'ar.spacing.after-sentence',
  'ar.spacing.run-together',
  'ar.spacing.theophoric',
  'ar.hamza.maqsura-hamza',
  'ar.hamza.wasl-measure',
  'ar.spelling.common',
  'ar.consistency.spelling',
  'ar.date.weekday',
  'ar.date.invalid-day',
  'ar.date.implausible-year',
  'ar.grammar.hal-particle',
  'ar.redundancy.double-future',
  'ar.redundancy.phrase',
  'ar.expression.error',
  'ar.register.colloquial',
  'ar.repetition.content-word',
};

/// Extended T1 rule ids that are prescriptive, noisy or convention-dependent
/// and therefore run only when the host enables them explicitly.
const Set<String> arabicExtendedOptionalRuleIds = <String>{
  'ar.usage.baynama-initial',
  'ar.usage.talama',
  'ar.usage.imma-aw',
  'ar.usage.kullama-repeated',
  'ar.usage.abadan-past',
  'ar.usage.expression',
  'ar.usage.word',
  'ar.style.wordiness',
  'ar.style.long-sentence',
  'ar.style.tanwin-placement',
  'ar.register.loanword',
  'ar.hint.vowelling',
  'ar.hint.dad-za',
};

/// One list-driven word table, exposed read-only for tests and audits.
///
/// [entries] maps a bare spelling to its suggestions; the rule also matches
/// each entry after any of [prefixes] (and, when [article] is set, after the
/// article).
final class ArabicWordListForTesting {
  const ArabicWordListForTesting(
    this.ruleId,
    this.entries, {
    this.prefixes = const <String>[''],
    this.article = false,
  });
  final String ruleId;
  final Map<String, List<String>> entries;
  final List<String> prefixes;
  final bool article;
}

/// Every list-driven word table of [ArabicWritingRulesProvider].
List<ArabicWordListForTesting> arabicWordListsForTesting() =>
    <ArabicWordListForTesting>[
      const ArabicWordListForTesting(
        'ar.hamza.initial',
        ArabicWritingRulesProvider._hamza,
      ),
      ArabicWordListForTesting(
        'ar.ta-marbuta.final',
        <String, List<String>>{
          for (final String stem in ArabicWritingRulesProvider._taMarbutaStems)
            'ال$stemه': <String>['ال$stemة'],
        },
        prefixes: const <String>['', 'و', 'ف', 'ب', 'ك'],
      ),
      ArabicWordListForTesting('ar.alif-maqsura.final', <String, List<String>>{
        for (final MapEntry<String, String> e
            in ArabicWritingRulesProvider._alifMaqsura.entries)
          e.key: <String>[e.value],
      }),
      ArabicWordListForTesting('ar.ya.final', <String, List<String>>{
        for (final MapEntry<String, String> e
            in ArabicWritingRulesProvider._finalYa.entries)
          e.key: <String>[e.value],
      }),
      const ArabicWordListForTesting(
        'ar.spelling.common',
        _ArabicExtendedRules._commonSpelling,
        prefixes: <String>['', 'و', 'ف', 'ب', 'ل', 'ك'],
      ),
      const ArabicWordListForTesting(
        'ar.register.colloquial',
        _ArabicExtendedRules._colloquial,
        prefixes: <String>['', 'و', 'ف'],
      ),
      const ArabicWordListForTesting(
        'ar.register.loanword',
        _ArabicExtendedRules._loanwords,
        prefixes: <String>['', 'و', 'ف'],
      ),
      const ArabicWordListForTesting(
        'ar.usage.word',
        _ArabicExtendedRules._usageWords,
        prefixes: <String>['', 'و', 'ف'],
      ),
      const ArabicWordListForTesting(
        'ar.hint.vowelling',
        _ArabicExtendedRules._vowelling,
        prefixes: <String>['', 'و', 'ف', 'ب', 'ك'],
        article: true,
      ),
      const ArabicWordListForTesting(
        'ar.hint.dad-za',
        _ArabicExtendedRules._dadZa,
        prefixes: <String>['', 'و', 'ف'],
      ),
    ];

/// Every phrase list as (rule id, bare-text pattern, replacements); `{n}`
/// in a replacement stands for a matched group.
List<(String, String, List<String>)> arabicPhraseListsForTesting() =>
    <(String, String, List<String>)>[
      for (final (String id, List<_Phrase> phrases)
          in <(String, List<_Phrase>)>[
            ('ar.redundancy.phrase', _ArabicExtendedRules._redundancy),
            ('ar.style.wordiness', _ArabicExtendedRules._wordiness),
            ('ar.usage.expression', _ArabicExtendedRules._usageExpressions),
            ('ar.expression.error', _ArabicExtendedRules._expressionErrors),
          ])
        for (final _Phrase p in phrases) (id, p.pattern, p.replacements),
    ];

typedef _ArabicAdd =
    void Function(
      String ruleId,
      int start,
      int end,
      String message, {
      OfficeProofingCategory category,
      List<String> replacements,
    });

/// The text with optional harakat and tatweel removed, mapped to the source.
/// Combining maddah and hamza retain their spelling identity, as in `_bare`.
final class _ArabicBareText {
  _ArabicBareText(String text) : _sourceLength = text.length {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (ArabicWritingRulesProvider._comparisonMark.hasMatch(text[i])) {
        continue;
      }
      buffer.write(text[i]);
      _map.add(i);
    }
    bare = buffer.toString();
  }

  final int _sourceLength;
  final List<int> _map = <int>[];
  late final String bare;

  int start(int bareIndex) =>
      bareIndex >= _map.length ? _sourceLength : _map[bareIndex];

  /// Source end for a bare end: trailing harakat stay inside the range.
  int end(int bareIndex) =>
      bareIndex >= _map.length ? _sourceLength : _map[bareIndex];
}

enum _PhraseSpan {
  /// The whole match is replaced.
  whole,

  /// The last word and the whitespace before it are deleted.
  deleteTail,

  /// The last word plus the whitespace after it is replaced.
  lastWordWithFollowingSpace,

  /// The whole match plus the whitespace after it is replaced.
  wholeWithFollowingSpace,
}

/// A bare-text pattern (no harakat) with literal replacements. `{n}` in a
/// replacement is the bare text of group n.
final class _Phrase {
  const _Phrase(
    this.pattern,
    this.replacements, {
    this.span = _PhraseSpan.whole,
    this.message,
  });
  final String pattern;
  final List<String> replacements;
  final _PhraseSpan span;
  final String? message;
}

final class _ArabicExtendedRules {
  _ArabicExtendedRules(
    this.text,
    this.words,
    this.protected,
    this.add,
    this.enabled,
  ) : bares = <String>[
        for (final RegExpMatch m in words)
          ArabicWritingRulesProvider._bare(m.group(0)!).$1,
      ],
      bareText = _ArabicBareText(text) {
    int sentence = 0;
    int w = 0;
    for (int i = 0; i <= text.length && w < words.length; i++) {
      while (w < words.length && words[w].start <= i) {
        sentenceOf.add(sentence);
        w++;
      }
      if (i < text.length && _sentenceEnd.hasMatch(text[i])) sentence++;
    }
  }

  final String text;
  final List<RegExpMatch> words;
  final OfficeProofingTextRanges protected;
  final _ArabicAdd add;
  final bool Function(String ruleId) enabled;
  final List<String> bares;
  final _ArabicBareText bareText;
  final List<int> sentenceOf = <int>[];

  static const String _l = ArabicWritingRulesProvider._letters;
  static const String _tokenContinuation =
      ArabicWritingRulesProvider._wordContinuation;
  static final RegExp _sentenceEnd = RegExp(r'[.!?؟\n]');
  static final RegExp _spaces = RegExp(r'^[ \u00A0]+$');
  static final RegExp _tanwin = RegExp('[\u064B-\u064D]');

  void run() {
    _doubledPunctuation();
    _unpaired();
    _whitespace();
    _letterShapes();
    _consistency();
    _dates();
    _particles();
    _phrases();
    _tables();
    _contentRepetition();
    _longSentences();
  }

  // ---------------------------------------------------------------- helpers

  /// The words are separated by plain spaces only.
  bool _adjacent(int w) =>
      w > 0 &&
      _spaces.hasMatch(text.substring(words[w - 1].end, words[w].start));

  bool _sentenceStart(int w) => w == 0 || sentenceOf[w] != sentenceOf[w - 1];

  static bool _hasMarks(String word) =>
      ArabicWritingRulesProvider._mark.hasMatch(word);

  /// Rewrites with the writer's harakat when the letter count is unchanged.
  /// A suggestion that carries its own harakat is returned as authored.
  String _keepHarakat(int w, String to) {
    if (_hasMarks(to)) return to;
    final (String bare, List<int> at) = ArabicWritingRulesProvider._bare(
      words[w].group(0)!,
    );
    return ArabicWritingRulesProvider._respell(
          words[w].group(0)!,
          bare,
          at,
          to,
        ) ??
        to;
  }

  // ------------------------------------------------- P3 doubled punctuation

  void _doubledPunctuation() {
    const String id = 'ar.punctuation.doubled';
    if (!enabled(id)) return;
    for (final RegExpMatch m in RegExp(
      r'([،,؛;])\1+|(?<!\.)\.\.(?!\.)',
    ).allMatches(text)) {
      int before = m.start;
      while (before > 0 && text[before - 1] == ' ') {
        before--;
      }
      if (!ArabicWritingRulesProvider._arabicBefore(text, before)) continue;
      final String mark = m.group(0)![0];
      add(
        id,
        m.start,
        m.end,
        mark == '.'
            ? 'نقطتان متتاليتان: اكتب نقطة واحدة، أو ثلاث نقاط إن قصدت علامة الحذف.'
            : 'علامة ترقيم مكررة؛ تكفي علامة واحدة.',
        category: OfficeProofingCategory.style,
        replacements: mark == '.' ? const <String>['.', '...'] : <String>[mark],
      );
    }
  }

  // ---------------------------------------------- P4 unpaired brackets/quotes

  void _unpaired() {
    const String id = 'ar.punctuation.unpaired';
    if (!enabled(id)) return;
    // Fixed direction: brackets are mirrored by the bidi algorithm, so the
    // logical opener is always the same code point.
    const Map<String, String> fixed = <String, String>{
      '(': ')',
      '[': ']',
      '{': '}',
    };
    // Pairs typed in either order in right-to-left text: the first glyph seen
    // in the paragraph is taken as the opener.
    const List<(String, String)> eitherOrder = <(String, String)>[
      ('«', '»'),
      ('\uFD3F', '\uFD3E'), // ornate parentheses ﴿ ﴾
      ('\u201C', '\u201D'), // curly double quotes
    ];
    final Map<String, String> closers = <String, String>{};
    final Map<String, String> openers = <String, String>{...fixed};
    for (final (String a, String b) in eitherOrder) {
      final int ia = text.indexOf(a);
      final int ib = text.indexOf(b);
      if (ia < 0 && ib < 0) continue;
      if (ib >= 0 && (ia < 0 || ib < ia)) {
        openers[b] = a;
      } else {
        openers[a] = b;
      }
    }
    openers.forEach((String open, String close) => closers[close] = open);

    final List<int> stack = <int>[];
    final List<int> unmatched = <int>[];
    final List<int> straight = <int>[];
    for (int i = 0; i < text.length; i++) {
      final String c = text[i];
      if (protected.overlaps(i, i + 1)) continue;
      if (c == '"') {
        straight.add(i);
      } else if (openers.containsKey(c)) {
        stack.add(i);
      } else if (closers.containsKey(c)) {
        final String open = closers[c]!;
        final int at = stack.lastIndexWhere((int s) => text[s] == open);
        if (at >= 0) {
          // Openers left above the partner were never closed.
          unmatched.addAll(stack.sublist(at + 1));
          stack.removeRange(at, stack.length);
        } else if (!_enumerationCloser(i)) {
          unmatched.add(i);
        }
      }
    }
    unmatched.addAll(stack);
    if (straight.length.isOdd) unmatched.add(straight.last);
    // A paragraph that opens with a quotation mark and never closes it is
    // the multi-paragraph quotation convention.
    final String lead = text.trimLeft();
    final int leadAt = text.length - lead.length;
    for (final int i in unmatched) {
      final String c = text[i];
      final bool quote =
          c == '"' || c == '«' || c == '»' || c == '\u201C' || c == '\u201D';
      if (quote && i == leadAt) continue;
      add(
        id,
        i,
        i + 1,
        quote
            ? 'علامة التنصيص هذه بلا نظير في الفقرة؛ راجع موضع الإغلاق أو الفتح.'
            : 'هذا القوس بلا نظير في الفقرة؛ راجع موضع الإغلاق أو الفتح.',
        category: OfficeProofingCategory.style,
      );
    }
  }

  /// `1)` / `أ)` list labels and `:)` emoticons close nothing.
  bool _enumerationCloser(int i) {
    final String before = text.substring(i < 6 ? 0 : i - 6, i);
    return RegExp(
      r'(?:^|\s)(?:[0-9٠-٩]{1,3}|\p{L})$|[:;]-?$',
      unicode: true,
    ).hasMatch(before);
  }

  // ------------------------------------------------------ P5 whitespace

  void _whitespace() {
    const String multiple = 'ar.spacing.multiple';
    if (enabled(multiple)) {
      for (final RegExpMatch m in RegExp(
        r'(?<=\S)[ \u00A0]{2,}(?=\S)',
      ).allMatches(text)) {
        // A detached waw before the gap is reported by its own rule.
        if (m.start >= 1 &&
            text[m.start - 1] == 'و' &&
            (m.start == 1 ||
                !RegExp(
                  '[$_l${ArabicWritingRulesProvider._marks}]',
                ).hasMatch(text[m.start - 2]))) {
          continue;
        }
        add(
          multiple,
          m.start,
          m.end,
          'مسافات متعددة بين الكلمتين؛ تكفي مسافة واحدة.',
          category: OfficeProofingCategory.style,
          replacements: const <String>[' '],
        );
      }
    }
    const String after = 'ar.spacing.after-sentence';
    if (enabled(after)) {
      for (final RegExpMatch m in RegExp('[.!؟:](?=[$_l])').allMatches(text)) {
        if (!ArabicWritingRulesProvider._arabicBefore(text, m.start)) continue;
        // Single-letter abbreviations such as `د.` or `ص.ب` stay as written.
        final RegExpMatch? token = RegExp(
          '[$_l${ArabicWritingRulesProvider._marks}]+\$',
        ).firstMatch(text.substring(0, m.start));
        if (token != null &&
            ArabicWritingRulesProvider._bare(token.group(0)!).$1.length == 1) {
          continue;
        }
        add(
          after,
          m.end,
          m.end,
          'ضع مسافة بعد علامة الترقيم وقبل الكلمة التالية.',
          category: OfficeProofingCategory.style,
          replacements: const <String>[' '],
        );
      }
    }
  }

  // --------------------- S5, S6, T1-a, T1-b and S2 generative (per word)

  /// Names of God that follow `عبد` in compound names (authored list).
  static const Set<String> _divineNames = <String>{
    'الله',
    'الرحمن',
    'الرحيم',
    'الملك',
    'القدوس',
    'السلام',
    'المؤمن',
    'العزيز',
    'الجبار',
    'الخالق',
    'الباري',
    'البارئ',
    'المصور',
    'الغفار',
    'الوهاب',
    'الرزاق',
    'الفتاح',
    'العليم',
    'اللطيف',
    'الحليم',
    'العظيم',
    'الغفور',
    'الشكور',
    'الكريم',
    'الحكيم',
    'الودود',
    'المجيد',
    'الحميد',
    'الحق',
    'القوي',
    'الحي',
    'القيوم',
    'الواحد',
    'الصمد',
    'القادر',
    'النور',
    'الهادي',
    'الرشيد',
    'الصبور',
    'الستار',
    'الباسط',
    'الجليل',
    'الرؤوف',
    'الغني',
    'المعطي',
    'المنعم',
    'الإله',
    'الحافظ',
    'السميع',
    'البصير',
    'العلي',
    'الكبير',
    'الأحد',
    'المحسن',
    'المعين',
    'الباقي',
    'الرافع',
  };

  static const String _c = 'ءأؤئبتثجحخدذرزسشصضطظعغفقكلمنهوي';
  static final RegExp _measureVII = RegExp('^إن[$_c][$_c]ا[$_c]\$');
  static final RegExp _measureVIII = RegExp('^إ[$_c][تطد][$_c]ا[$_c]\$');
  static final RegExp _measureX = RegExp('^إست[$_c][$_c]ا[$_c]\$');
  static final RegExp _measureXHollow = RegExp('^إست[$_c]ا[$_c]\$');

  /// Measure VIII verbal nouns of first-weak roots (assimilated to تّ).
  static const Set<String> _assimilatedVIII = <String>{
    'إتصال',
    'إتفاق',
    'إتحاد',
    'إتجاه',
    'إتخاذ',
    'إتهام',
    'إتساع',
    'إتضاح',
    'إتكال',
    'إتزان',
  };

  /// Real words with an initial hamzat al-qat' that fit a template shape.
  static const Set<String> _measureExceptions = <String>{'إسطوان'};

  static const List<String> _measureSuffixes = <String>[
    'اتهم',
    'اتها',
    'اته',
    'تهم',
    'تها',
    'تنا',
    'يات',
    'يين',
    'يون',
    'هما',
    'ات',
    'ية',
    'يا',
    'ته',
    'تي',
    'ها',
    'هم',
    'هن',
    'كم',
    'نا',
    'ة',
    'ي',
    'ه',
    'ك',
    '',
  ];
  static const List<String> _measurePrefixes = <String>[
    'وبال',
    'فبال',
    'وال',
    'فال',
    'بال',
    'كال',
    'ولل',
    'فلل',
    'لل',
    'ال',
    'وب',
    'فب',
    'ول',
    'فل',
    'و',
    'ف',
    'ب',
    'ل',
    'ك',
    '',
  ];

  bool _waslMeasure(String core) {
    for (final String suffix in _measureSuffixes) {
      if (!core.endsWith(suffix)) continue;
      final String stem = core.substring(0, core.length - suffix.length);
      if (stem.length < 5 || _measureExceptions.contains(stem)) continue;
      if (_assimilatedVIII.contains(stem) ||
          _measureVII.hasMatch(stem) ||
          _measureVIII.hasMatch(stem) ||
          _measureX.hasMatch(stem)) {
        return true;
      }
      if (_measureXHollow.hasMatch(stem) && suffix.startsWith(RegExp('[ةت]'))) {
        return true;
      }
    }
    return false;
  }

  void _letterShapes() {
    const String maqsuraHamza = 'ar.hamza.maqsura-hamza';
    const String runTogether = 'ar.spacing.run-together';
    const String theophoric = 'ar.spacing.theophoric';
    const String wasl = 'ar.hamza.wasl-measure';
    const String tanwin = 'ar.style.tanwin-placement';
    for (int w = 0; w < words.length; w++) {
      final String word = words[w].group(0)!;
      final int start = words[w].start;
      final int end = words[w].end;
      final (String bare, List<int> at) = ArabicWritingRulesProvider._bare(
        word,
      );

      // S5: ى followed by a free hamza where ئ is meant (شاطىء → شاطئ).
      final int mh = bare.indexOf('ىء');
      if (mh >= 0 && enabled(maqsuraHamza)) {
        final int y = at[mh];
        final int h = at[mh + 1];
        add(
          maqsuraHamza,
          start,
          end,
          'تُكتب الهمزة هنا على نبرة (ئ)، لا ألفًا مقصورة تليها همزة.',
          category: OfficeProofingCategory.spelling,
          replacements: <String>[
            '${word.substring(0, y)}ئ${word.substring(y + 1, h)}'
                '${word.substring(h + 1)}',
          ],
        );
      }

      // S6: a final-only letter inside a word signals a missing space.
      if (enabled(runTogether)) {
        final List<int> splits = <int>[
          for (int k = 0; k < bare.length - 1; k++)
            if (bare[k] == 'ة' || (bare[k] == 'ى' && bare[k + 1] != 'ء')) k,
        ];
        if (splits.isNotEmpty) {
          final StringBuffer fixed = StringBuffer();
          int from = 0;
          for (final int k in splits) {
            fixed.write(word.substring(from, at[k + 1]));
            fixed.write(' ');
            from = at[k + 1];
          }
          fixed.write(word.substring(from));
          add(
            runTogether,
            start,
            end,
            'لا تقع التاء المربوطة ولا الألف المقصورة إلا في آخر الكلمة؛ '
            'يبدو أن مسافة سقطت هنا.',
            category: OfficeProofingCategory.spelling,
            replacements: <String>[fixed.toString()],
          );
        }
      }

      // T1-b: `عبدالله` → `عبد الله` for listed names of God.
      if (enabled(theophoric)) {
        final RegExpMatch? m = RegExp(
          r'^([وف]?[بلك]?)عبد(ال.+)$',
        ).firstMatch(bare);
        if (m != null && _divineNames.contains(m.group(2))) {
          final int split = at[m.group(1)!.length + 3];
          add(
            theophoric,
            start,
            end,
            'يُكتب «عبد» منفصلًا عن الاسم الذي يليه في الأسماء المركبة.',
            category: OfficeProofingCategory.style,
            replacements: <String>[
              '${word.substring(0, split)} ${word.substring(split)}',
            ],
          );
        }
      }

      // S2 generative: verbal nouns of measures VII, VIII and X begin with
      // hamzat al-wasl (`إستخدام` → `استخدام`).
      if (enabled(wasl)) {
        for (final String prefix in _measurePrefixes) {
          if (!bare.startsWith(prefix)) continue;
          final String core = bare.substring(prefix.length);
          if (!core.startsWith('إ') || !_waslMeasure(core)) continue;
          final int alif = at[prefix.length];
          add(
            wasl,
            start,
            end,
            'مصدر الفعل الخماسي والسداسي يبدأ بهمزة وصل، فتُكتب ألفه بلا همزة.',
            category: OfficeProofingCategory.spelling,
            replacements: <String>[
              '${word.substring(0, alif)}ا${word.substring(alif + 1)}',
            ],
          );
          break;
        }
      }

      // T1-a (opt-in): tanwin fath written after the seat alif.
      if (enabled(tanwin) &&
          bare.length >= 2 &&
          bare.endsWith('ا') &&
          word.substring(at.last).contains('\u064B')) {
        final int alif = at.last;
        final String tail = word.substring(alif + 1).replaceAll('\u064B', '');
        add(
          tanwin,
          start,
          end,
          'لتنوين الفتح رسمان شائعان؛ هذه القاعدة الاختيارية توحّده على الحرف '
          'الذي قبل الألف.',
          category: OfficeProofingCategory.style,
          replacements: <String>['${word.substring(0, alif)}\u064Bا$tail'],
        );
      }
    }
  }

  // ---------------------------------------- S8 consistency within a paragraph

  /// Pairs of accepted spellings of the same word (first, second).
  static const List<List<(String, String)>> _variantGroups =
      <List<(String, String)>>[
        <(String, String)>[
          ('مسؤول', 'مسئول'),
          ('مسؤولة', 'مسئولة'),
          ('مسؤولون', 'مسئولون'),
          ('مسؤولين', 'مسئولين'),
          ('مسؤولو', 'مسئولو'),
          ('مسؤولي', 'مسئولي'),
          ('مسؤولية', 'مسئولية'),
          ('مسؤوليات', 'مسئوليات'),
        ],
        <(String, String)>[('شؤون', 'شئون')],
        <(String, String)>[('رؤوس', 'رءوس')],
        <(String, String)>[
          ('مئة', 'مائة'),
          ('مئتان', 'مائتان'),
          ('مئتين', 'مائتين'),
          ('مئتا', 'مائتا'),
          ('مئتي', 'مائتي'),
          ('ثلاثمئة', 'ثلاثمائة'),
          ('أربعمئة', 'أربعمائة'),
          ('خمسمئة', 'خمسمائة'),
          ('ستمئة', 'ستمائة'),
          ('سبعمئة', 'سبعمائة'),
          ('ثمانمئة', 'ثمانمائة'),
          ('تسعمئة', 'تسعمائة'),
        ],
        <(String, String)>[('داود', 'داوود')],
        <(String, String)>[
          ('تلفزيون', 'تليفزيون'),
          ('تلفزيوني', 'تليفزيوني'),
          ('تلفزيونية', 'تليفزيونية'),
        ],
        <(String, String)>[
          ('أمريكا', 'أميركا'),
          ('أمريكي', 'أميركي'),
          ('أمريكية', 'أميركية'),
          ('أمريكيون', 'أميركيون'),
          ('أمريكيين', 'أميركيين'),
        ],
        <(String, String)>[
          ('أوروبا', 'أوربا'),
          ('أوروبي', 'أوربي'),
          ('أوروبية', 'أوربية'),
          ('أوروبيون', 'أوربيون'),
          ('أوروبيين', 'أوربيين'),
        ],
        <(String, String)>[
          ('إنجلترا', 'إنكلترا'),
          ('إنجليز', 'إنكليز'),
          ('إنجليزي', 'إنكليزي'),
          ('إنجليزية', 'إنكليزية'),
        ],
        <(String, String)>[('كمبيوتر', 'كومبيوتر')],
      ];

  static final Map<String, (int, int, String)> _variants = () {
    final Map<String, (int, int, String)> map = <String, (int, int, String)>{};
    for (int g = 0; g < _variantGroups.length; g++) {
      for (final (String a, String b) in _variantGroups[g]) {
        map[a] = (g, 0, b);
        map[b] = (g, 1, a);
      }
    }
    return map;
  }();

  void _consistency() {
    const String id = 'ar.consistency.spelling';
    if (!enabled(id)) return;
    final Map<int, (int, String)> first = <int, (int, String)>{};
    for (int w = 0; w < words.length; w++) {
      final String bare = bares[w];
      for (final String prefix in _measurePrefixes) {
        if (!bare.startsWith(prefix)) continue;
        final (int, int, String)? hit =
            _variants[bare.substring(prefix.length)];
        if (hit == null) continue;
        final (int group, int side, String other) = hit;
        final (int, String)? seen = first[group];
        if (seen == null) {
          first[group] = (side, bare);
        } else if (seen.$1 != side) {
          add(
            id,
            words[w].start,
            words[w].end,
            'وردت هذه الكلمة في الفقرة نفسها بصورة إملائية أخرى «${seen.$2}»؛ '
            'كلتاهما مقبولة، لكن وحّد الكتابة.',
            category: OfficeProofingCategory.spelling,
            replacements: <String>[_keepHarakat(w, '$prefix$other')],
          );
        }
        break;
      }
    }
  }

  // ------------------------------------------------------- M1 / M2 dates

  static const Map<String, int> _weekdays = <String, int>{
    'الاثنين': DateTime.monday,
    'الإثنين': DateTime.monday,
    'الثلاثاء': DateTime.tuesday,
    'الأربعاء': DateTime.wednesday,
    'الاربعاء': DateTime.wednesday,
    'الخميس': DateTime.thursday,
    'الجمعة': DateTime.friday,
    'السبت': DateTime.saturday,
    'الأحد': DateTime.sunday,
    'الاحد': DateTime.sunday,
  };
  static const Map<int, String> _weekdayNames = <int, String>{
    DateTime.monday: 'الاثنين',
    DateTime.tuesday: 'الثلاثاء',
    DateTime.wednesday: 'الأربعاء',
    DateTime.thursday: 'الخميس',
    DateTime.friday: 'الجمعة',
    DateTime.saturday: 'السبت',
    DateTime.sunday: 'الأحد',
  };

  /// Gregorian month names in the Egyptian/Gulf, Levantine and Maghrebi
  /// series (authored from general knowledge).
  static const Map<String, int> _months = <String, int>{
    'يناير': 1,
    'كانون الثاني': 1,
    'جانفي': 1,
    'فبراير': 2,
    'شباط': 2,
    'فيفري': 2,
    'مارس': 3,
    'آذار': 3,
    'أبريل': 4,
    'ابريل': 4,
    'إبريل': 4,
    'نيسان': 4,
    'أفريل': 4,
    'مايو': 5,
    'أيار': 5,
    'ماي': 5,
    'مايس': 5,
    'يونيو': 6,
    'يونيه': 6,
    'حزيران': 6,
    'جوان': 6,
    'يوليو': 7,
    'يوليه': 7,
    'تموز': 7,
    'جويلية': 7,
    'يوليوز': 7,
    'أغسطس': 8,
    'اغسطس': 8,
    'آب': 8,
    'أوت': 8,
    'غشت': 8,
    'سبتمبر': 9,
    'أيلول': 9,
    'شتنبر': 9,
    'أكتوبر': 10,
    'اكتوبر': 10,
    'تشرين الأول': 10,
    'نوفمبر': 11,
    'تشرين الثاني': 11,
    'نونبر': 11,
    'ديسمبر': 12,
    'كانون الأول': 12,
    'دجنبر': 12,
  };

  static final String _monthPattern =
      (_months.keys.toList()..sort((a, b) => b.length.compareTo(a.length)))
          .map((String m) => m.replaceAll(' ', r'\s+'))
          .join('|');

  static const String _digit = '[0-9٠-٩]';

  static int _number(String digits) => int.parse(
    String.fromCharCodes(
      digits.runes.map((int r) => r >= 0x660 && r <= 0x669 ? r - 0x630 : r),
    ),
  );

  static String _monthKey(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ');

  void _dates() {
    const String weekday = 'ar.date.weekday';
    const String invalid = 'ar.date.invalid-day';
    const String year = 'ar.date.implausible-year';
    final String bare = bareText.bare;
    if (enabled(weekday) || enabled(invalid)) {
      final String days = _weekdays.keys.join('|');
      final RegExp date = RegExp(
        '(?<![$_tokenContinuation])[وف]?(?:يوم\\s+)?($days)(?![$_tokenContinuation])\\s*[،,]?\\s*'
        '(?:(?:الموافق|الماضي|المقبل|القادم|المنصرم)\\s*[،,]?\\s*)?'
        '($_digit{1,2})(?!$_digit)\\s*(?:من\\s+)?(?:شهر\\s+)?'
        '($_monthPattern)(?![$_tokenContinuation])'
        '(?:\\s*[(/]\\s*(?:$_monthPattern)\\s*\\)?)?'
        '\\s*[،,]?\\s*(?:(?:من\\s+)?(?:عام|سنة|العام)\\s+)?'
        '($_digit{4})(?![$_tokenContinuation])(?!\\s*ه)',
        unicode: true,
      );
      for (final RegExpMatch m in date.allMatches(bare)) {
        final String all = m.group(0)!;
        final int dayIndex = all.indexOf(m.group(1)!);
        final int numberIndex = all.indexOf(
          m.group(2)!,
          dayIndex + m.group(1)!.length,
        );
        final int y = _number(m.group(4)!);
        final int month = _months[_monthKey(m.group(3)!)]!;
        final int d = _number(m.group(2)!);
        if (y < 1800 || y > 2200 || d < 1) continue;
        final int daysInMonth = DateTime.utc(y, month + 1, 0).day;
        if (d > daysInMonth) {
          if (enabled(invalid)) {
            add(
              invalid,
              bareText.start(m.start + numberIndex),
              bareText.end(m.start + numberIndex + m.group(2)!.length),
              'هذا التاريخ غير موجود: الشهر لا يتجاوز $daysInMonth يومًا.',
              category: OfficeProofingCategory.grammar,
            );
          }
          continue;
        }
        final int actual = DateTime.utc(y, month, d).weekday;
        if (actual == _weekdays[m.group(1)!] || !enabled(weekday)) continue;
        add(
          weekday,
          bareText.start(m.start + dayIndex),
          bareText.end(m.start + dayIndex + m.group(1)!.length),
          'هذا التاريخ يوافق يوم ${_weekdayNames[actual]}، لا اليوم المذكور.',
          category: OfficeProofingCategory.grammar,
          replacements: <String>[_weekdayNames[actual]!],
        );
      }
    }
    if (enabled(year)) {
      const String units =
          'دولار|دينار|درهم|ريال|جنيه|يورو|ليرة|شخص|نسمة|طن|متر|كيلو|برميل|'
          'وحدة|سهم|قطعة|مرة|عامل|زائر|حالة|ق|قبل';
      final RegExp implausible = RegExp(
        '(?<![$_tokenContinuation])[وفبل]?(?:عام|العام|سنة|السنة|(?:ال)?(?:ربيع|صيف|خريف|شتاء)|'
        '$_monthPattern)\\s+([12١٢]$_digit{4})(?![$_tokenContinuation.,٫٬])'
        '(?!\\s*(?:$units)(?![$_tokenContinuation]))',
        unicode: true,
      );
      for (final RegExpMatch m in implausible.allMatches(bare)) {
        final int at = m.start + m.group(0)!.lastIndexOf(m.group(1)!);
        add(
          year,
          bareText.start(at),
          bareText.end(at + 5),
          'عدد من خمسة أرقام في موضع السنة؛ هل المقصود سنة من أربعة أرقام؟',
          category: OfficeProofingCategory.grammar,
        );
      }
    }
  }

  // ------------------------------------ G14 hal, G13 position particles

  static const Set<String> _afterHal = <String>{
    'لا',
    'لم',
    'لن',
    'ليس',
    'ليست',
    'ليسوا',
    'ليسا',
    'لست',
    'لستم',
    'لسنا',
    'إن',
    'إنه',
    'إنها',
    'إنهم',
    'إنك',
    'إنكم',
    'إننا',
    'إني',
    'إذا',
    'لو',
  };

  void _particles() {
    const String hal = 'ar.grammar.hal-particle';
    const String baynama = 'ar.usage.baynama-initial';
    const String talama = 'ar.usage.talama';
    const String immaAw = 'ar.usage.imma-aw';
    const String kullama = 'ar.usage.kullama-repeated';
    const String abadan = 'ar.usage.abadan-past';
    for (int w = 0; w < words.length; w++) {
      final String bare = bares[w];

      if (w + 1 < words.length &&
          enabled(hal) &&
          _adjacent(w + 1) &&
          const <String>{'هل', 'وهل', 'فهل'}.contains(bare) &&
          _afterHal.contains(bares[w + 1])) {
        final String next = bares[w + 1];
        final String proclitic = bare.substring(0, bare.length - 2);
        add(
          hal,
          words[w].start,
          words[w + 1].end,
          'لا تدخل «هل» على النفي ولا على «إنّ» ولا على أدوات الشرط؛ '
          'استعمل همزة الاستفهام.',
          category: OfficeProofingCategory.grammar,
          replacements: next == 'لو'
              ? const <String>[]
              : <String>['أ$proclitic$next'],
        );
      }

      if (_sentenceStart(w) && bare == 'بينما' && enabled(baynama)) {
        add(
          baynama,
          words[w].start,
          words[w].end,
          '«بينما» في أول الجملة بمعنى «عندما» أسلوب مختلف فيه؛ '
          'يُفضَّل «عندما» أو «في حين» بعد الجملة الرئيسة.',
          category: OfficeProofingCategory.style,
          replacements: const <String>['عندما', 'في حين'],
        );
      }

      if (_sentenceStart(w) &&
          const <String>{'طالما', 'وطالما', 'فطالما'}.contains(bare) &&
          enabled(talama)) {
        final String proclitic = bare.substring(0, bare.length - 5);
        add(
          talama,
          words[w].start,
          words[w].end,
          '«طالما» في الأصل بمعنى «كثيرًا ما»؛ للشرط الزمني يُفضَّل «ما دام».',
          category: OfficeProofingCategory.style,
          replacements: <String>['$procliticما دام'],
        );
      }

      if (bare == 'إما' && enabled(immaAw)) {
        for (int k = w + 1; k < words.length && k <= w + 12; k++) {
          if (sentenceOf[k] != sentenceOf[w]) break;
          if (bares[k] == 'وإما' || bares[k] == 'إما') break;
          if (bares[k] == 'أو' || bares[k] == 'او') {
            add(
              immaAw,
              words[k].start,
              words[k].end,
              'تُكرَّر «إمّا» في الأسلوب الفصيح: «إمّا … وإمّا».',
              category: OfficeProofingCategory.style,
              replacements: const <String>['وإما'],
            );
            break;
          }
        }
      }

      if (bare == 'كلما' && enabled(kullama)) {
        for (int k = w + 1; k < words.length && k <= w + 15; k++) {
          if (sentenceOf[k] != sentenceOf[w]) break;
          if (bares[k] == 'كلما') {
            int end = words[k].end;
            while (end < text.length && text[end] == ' ') {
              end++;
            }
            add(
              kullama,
              words[k].start,
              end,
              'لا تُكرَّر «كلّما» في جواب الشرط؛ تكفي في أول الجملة.',
              category: OfficeProofingCategory.style,
              replacements: const <String>[''],
            );
            break;
          }
        }
      }

      if (bare == 'لم' && enabled(abadan)) {
        for (int k = w + 1; k < words.length && k <= w + 6; k++) {
          if (sentenceOf[k] != sentenceOf[w]) break;
          if (const <String>{'لن', 'لا'}.contains(bares[k])) break;
          if (bares[k] == 'أبدا' || bares[k] == 'ابدا') {
            add(
              abadan,
              words[k].start,
              words[k].end,
              '«أبدًا» لاستغراق المستقبل؛ لنفي الماضي يُستعمل «قطّ».',
              category: OfficeProofingCategory.style,
              replacements: const <String>['قطّ'],
            );
            break;
          }
        }
      }
    }
  }

  // ------------------------------------- L2, L6 phrases on the bare text

  static const String _w = r'[^\s.،,؛;؟?!]+';

  static const List<_Phrase> _redundancy = <_Phrase>[
    _Phrase(
      '(?:حوالي|حوالى|قرابة|زهاء)\\s+(?:$_w\\s+){0,3}?تقريبا',
      <String>[''],
      span: _PhraseSpan.deleteTail,
      message: 'تكرار لمعنى التقريب؛ تكفي إحدى الكلمتين.',
    ),
    _Phrase(
      'إلا\\s+(?:$_w\\s+){0,3}?فقط',
      <String>[''],
      span: _PhraseSpan.deleteTail,
      message: 'أسلوب الحصر بـ«إلا» يغني عن «فقط».',
    ),
    _Phrase(
      '((?:[وف])?(?:صعد|صعدت|صعدوا|يصعد|تصعد|يصعدون|ارتفع|ارتفعت|يرتفع))'
      '\\s+إلى\\s+(?:ال)?أعلى(?=\\s*(?:[.،,؛;؟?!]|\$))',
      <String>['{1}'],
      message: 'الصعود لا يكون إلا إلى أعلى؛ يكفي الفعل وحده.',
    ),
    _Phrase(
      '((?:[وف])?(?:نزل|نزلت|نزلوا|ينزل|تنزل|ينزلون|هبط|هبطت|يهبط|تهبط))'
      '\\s+إلى\\s+(?:ال)?أسفل(?=\\s*(?:[.،,؛;؟?!]|\$))',
      <String>['{1}'],
      message: 'النزول لا يكون إلا إلى أسفل؛ يكفي الفعل وحده.',
    ),
    _Phrase(
      '((?:[وفبلك]|وب|فب|ول|فل)?(?:ال|لل)?مستقبل)\\s+(?:ال)?قادم',
      <String>['{1}'],
      message: 'المستقبل قادم بطبيعته؛ الوصف زائد.',
    ),
    _Phrase('((?:[وفبلك])?(?:ال|لل)?(?:هدية|هدايا))\\s+(?:ال)?مجانية', <String>[
      '{1}',
    ], message: 'الهدية مجانية بطبيعتها؛ الوصف زائد.'),
    _Phrase(
      '((?:[وفبلك])?(?:ال|لل)?مفاجأة)\\s+(?:ال)?غير\\s+(?:ال)?متوقعة',
      <String>['{1}'],
      message: 'المفاجأة غير متوقعة بطبيعتها؛ الوصف زائد.',
    ),
    _Phrase(
      '[وفب]?نفس\\s+$_w\\s+(?:ذاته|ذاتها|نفسه|نفسها)',
      <String>[''],
      span: _PhraseSpan.deleteTail,
      message: 'توكيد مكرر: «نفس» و«ذاته/نفسه» بمعنى واحد.',
    ),
    _Phrase('(في\\s+حال(?:ة)?)\\s+(?:إذا|إن|لو)', <String>[
      '{1}',
      'إذا',
    ], message: '«في حال» تغني عن أداة الشرط بعدها.'),
  ];

  static final List<_Phrase> _wordiness = <_Phrase>[
    _Phrase('((?:[وف])?)مما\\s+لا\\s+شك\\s+فيه\\s+(أن|أنه|أنها)', <String>[
      '{1}لا شك {2}',
    ]),
    _Phrase('من\\s+الجدير\\s+بالذكر\\s+(أن|أنه|أنها)', <String>['يُذكر {1}']),
    _Phrase(
      '((?:على\\s+|ب)?(?:ال)?رغم\\s+من|رغم)\\s+حقيقة\\s+(أن|أنه|أنها)',
      <String>['{1} {2}'],
    ),
    _Phrase('نظرا\\s+لحقيقة\\s+(أن|أنه|أنها)', <String>['نظرا ل{1}']),
    _Phrase('بسبب\\s+حقيقة\\s+(أن|أنه|أنها)', <String>['ل{1}']),
    _Phrase(
      'عبارة\\s+عن',
      <String>[''],
      span: _PhraseSpan.wholeWithFollowingSpace,
      message: '«عبارة عن» حشو في الغالب؛ احذفها أو أخبر بالاسم مباشرة.',
    ),
    _Phrase('في\\s+الوقت\\s+(?:الحالي|الراهن|الحاضر)', <String>['حاليًّا']),
    _Phrase('من\\s+أجل\\s+أن', <String>['لكي']),
    _Phrase('في\\s+نهاية\\s+المطاف', <String>['أخيرًا', 'في النهاية']),
    _Phrase('في\\s+الآونة\\s+الأخيرة', <String>['مؤخرًا']),
    _Phrase('في\\s+بعض\\s+الأحيان', <String>['أحيانًا']),
    _Phrase('في\\s+كثير\\s+من\\s+الأحيان', <String>['كثيرًا', 'غالبًا']),
    _Phrase('في\\s+(?:أغلب|معظم)\\s+الأحيان', <String>['غالبًا']),
    _Phrase('في\\s+المستقبل\\s+القريب', <String>['قريبًا']),
    _Phrase('حتى\\s+هذه\\s+اللحظة', <String>['حتى الآن']),
    _Phrase('إلى\\s+حد\\s+كبير', <String>['كثيرًا']),
    _Phrase('عدد\\s+كبير\\s+من', <String>['كثير من']),
    _Phrase('عدد\\s+قليل\\s+من', <String>['قليل من']),
    _Phrase('(?:ال)?غالبية\\s+العظمى\\s+من', <String>['معظم', 'أغلب']),
    _Phrase('في\\s+واقع\\s+الأمر', <String>['في الواقع']),
    _Phrase('تجدر\\s+الإشارة\\s+إلى\\s+(أن|أنه|أنها)', <String>['يُذكر {1}']),
    _Phrase('لا\\s+يخفى\\s+على\\s+أحد\\s+(أن|أنه|أنها)', <String>['معلوم {1}']),
    _Phrase('بناء\\s+على\\s+ذلك', <String>['لذلك']),
    _Phrase('في\\s+ظل\\s+الظروف\\s+(?:الحالية|الراهنة)', <String>['حاليًّا']),
    ..._adverbialPhrases,
    ..._lightVerbPhrases,
  ];

  /// `بشكل/بصورة` + adjective, where one adverb or prepositional phrase
  /// says the same (authored list: adjective stem, replacement).
  static const List<(String, String)> _adverbials = <(String, String)>[
    ('عام', 'عمومًا'),
    ('خاص', 'خصوصًا'),
    ('كبير', 'كثيرًا'),
    ('مستمر', 'باستمرار'),
    ('دائم', 'دائمًا'),
    ('سريع', 'بسرعة'),
    ('جيد', 'جيدًا'),
    ('واضح', 'بوضوح'),
    ('مباشر', 'مباشرةً'),
    ('كامل', 'تمامًا'),
    ('نهائي', 'نهائيًّا'),
    ('تدريجي', 'تدريجيًّا'),
    ('رسمي', 'رسميًّا'),
    ('فعال', 'بفعالية'),
    ('أساسي', 'أساسًا'),
    ('يومي', 'يوميًّا'),
    ('دوري', 'دوريًّا'),
    ('جزئي', 'جزئيًّا'),
    ('تلقائي', 'تلقائيًّا'),
    ('مؤقت', 'مؤقتًا'),
    ('مفاجئ', 'فجأةً'),
    ('خاطئ', 'خطأً'),
    ('مستقل', 'باستقلال'),
    ('منتظم', 'بانتظام'),
    ('سلبي', 'سلبًا'),
    ('إيجابي', 'إيجابًا'),
  ];

  static final List<_Phrase> _adverbialPhrases = <_Phrase>[
    for (final (String stem, String adverb) in _adverbials)
      _Phrase('((?:[وف])?)(?:بشكل|بصورة|بصفة)\\s+$stemة?', <String>[
        '{1}$adverb',
      ]),
  ];

  /// `قام بـ` + verbal noun, which the verb itself expresses (authored list:
  /// verbal noun; past masculine, past feminine, present masculine and
  /// present feminine of the verb).
  static const List<(String, List<String>)> _lightVerbs =
      <(String, List<String>)>[
        ('زيارة', <String>['زار', 'زارت', 'يزور', 'تزور']),
        ('إعداد', <String>['أعدّ', 'أعدّت', 'يُعدّ', 'تُعدّ']),
        ('تأسيس', <String>['أسّس', 'أسّست', 'يؤسّس', 'تؤسّس']),
        ('إنشاء', <String>['أنشأ', 'أنشأت', 'يُنشئ', 'تُنشئ']),
        ('كتابة', <String>['كتب', 'كتبت', 'يكتب', 'تكتب']),
        ('تطوير', <String>['طوّر', 'طوّرت', 'يطوّر', 'تطوّر']),
        ('نشر', <String>['نشر', 'نشرت', 'ينشر', 'تنشر']),
        ('تقديم', <String>['قدّم', 'قدّمت', 'يقدّم', 'تقدّم']),
        ('إصدار', <String>['أصدر', 'أصدرت', 'يُصدر', 'تُصدر']),
        ('تصميم', <String>['صمّم', 'صمّمت', 'يصمّم', 'تصمّم']),
        ('دراسة', <String>['درس', 'درست', 'يدرس', 'تدرس']),
        ('شراء', <String>['اشترى', 'اشترت', 'يشتري', 'تشتري']),
        ('بناء', <String>['بنى', 'بنت', 'يبني', 'تبني']),
        ('تسجيل', <String>['سجّل', 'سجّلت', 'يسجّل', 'تسجّل']),
        ('تأليف', <String>['ألّف', 'ألّفت', 'يؤلّف', 'تؤلّف']),
        ('إخراج', <String>['أخرج', 'أخرجت', 'يُخرج', 'تُخرج']),
        ('تمثيل', <String>['مثّل', 'مثّلت', 'يمثّل', 'تمثّل']),
        ('تدريب', <String>['درّب', 'درّبت', 'يدرّب', 'تدرّب']),
        ('اختيار', <String>['اختار', 'اختارت', 'يختار', 'تختار']),
        ('إطلاق', <String>['أطلق', 'أطلقت', 'يُطلق', 'تُطلق']),
      ];

  static final List<_Phrase> _lightVerbPhrases = <_Phrase>[
    for (final (String noun, List<String> verbs) in _lightVerbs)
      for (final (int i, String auxiliary) in const <String>[
        'قام',
        'قامت',
        'يقوم',
        'تقوم',
      ].indexed)
        _Phrase(
          '((?:[وف])?)$auxiliary\\s+ب$noun(?![$_l])',
          <String>['{1}${verbs[i]}'],
          message:
              'الفعل «${verbs[i]}» يغني عن «$auxiliary بـ$noun»، '
              'ما لم يكن المصدر موصوفًا.',
        ),
  ];

  static final List<_Phrase> _usageExpressions = <_Phrase>[
    _Phrase(
      '((?:[وف])?(?:اختار|اختارت|اختاروا|يختار|تختار|نختار|أختار|يختارون|'
      'اختر|اختاري|اختيار|الاختيار|باختيار|للاختيار))\\s+بين',
      <String>['{1} من بين'],
      message: 'الاختيار يكون «من» أشياء أو «أحدَ» أمرين، لا «بين» على الأفصح.',
    ),
    _Phrase(
      'بين\\s+(?:$_w\\s+){1,3}?وبين',
      <String>['و'],
      span: _PhraseSpan.lastWordWithFollowingSpace,
      message: 'لا تُكرَّر «بين» مع الاسم الظاهر؛ تُكرَّر مع الضمير فقط.',
    ),
    _Phrase('لمدة(?=\\s)', <String>[
      'مدة',
    ], message: 'ظرف المدة يُنصب مباشرة؛ اللام قبل «مدة» زائدة على الأفصح.'),
    _Phrase(
      '((?:[وف])?)لا\\s*(زال|زالت|زالوا|زلت|زلنا)',
      <String>['{1}ما {2}'],
      message:
          '«لا» مع الماضي للدعاء؛ لمعنى الاستمرار استعمل «ما زال» '
          'أو «لا يزال».',
    ),
    _Phrase('(بعض(?:هم|ها|هما|نا|كم|هن))\\s+البعض', <String>[
      '{1} بعضًا',
    ], message: 'الأفصح «بعضهم بعضًا» بلا «ال» على «بعض».'),
    _Phrase('كما\\s+و(أن|إن)', <String>[
      'كما {1}',
    ], message: 'الواو بين «كما» و«أنّ» زائدة.'),
    _Phrase('((?:[وف])?)على\\s+ضوء', <String>[
      '{1}في ضوء',
    ], message: 'الأفصح «في ضوء»؛ «على ضوء» ترجمة حرفية.'),
    _Phrase('((?:[وف])?)(ب)?العديد\\s+من', <String>[
      '{1}{2}كثير من',
      '{1}{2}عدد من',
    ], message: '«العديد» بمعنى المعدود؛ الأفصح «كثير من» أو «عدد من».'),
    _Phrase('((?:[وف])?)للعديد\\s+من', <String>[
      '{1}لكثير من',
    ], message: '«العديد» بمعنى المعدود؛ الأفصح «كثير من» أو «عدد من».'),
    _Phrase('((?:[وف])?)بالرغم\\s+من', <String>[
      '{1}على الرغم من',
    ], message: 'الأشهر في الفصحى «على الرغم من».'),
    _Phrase('حيث\\s+أن(ه|ها|هم|هما|نا|ني|ك|كم)?', <String>[
      'حيث إن{1}',
    ], message: 'تُكسر همزة «إنّ» بعد «حيث».'),
    _Phrase(
      '((?:[وف])?(?:قال|قالت|قالوا|يقول|تقول|يقولون|أقول|نقول|القول))'
      '\\s+أن(ه|ها|هم|هما|نا|ني|ك|كم)?',
      <String>['{1} إن{2}'],
      message: 'تُكسر همزة «إنّ» بعد القول.',
    ),
    _Phrase(
      '((?:[وف])?(?:أكد|أكدت|أكدوا|يؤكد|تؤكد|يؤكدون|نؤكد|أؤكد|التأكيد|'
      'تأكيد|تأكيده|تأكيدها))\\s+على',
      <String>['{1}'],
      message: '«أكّد» يتعدى بنفسه: «أكّد الأمرَ».',
    ),
    _Phrase(
      '((?:[وف])?(?:أثر|أثرت|أثروا|يؤثر|تؤثر|يؤثرون|التأثير|تأثير|تأثيره|'
      'تأثيرها|تأثيرات|التأثيرات))\\s+على',
      <String>['{1} في'],
      message: 'الأفصح «أثّر في».',
    ),
    _Phrase('((?:[وف])?(?:حاز|حازت|حازوا|يحوز|تحوز))\\s+على', <String>[
      '{1}',
    ], message: '«حاز» يتعدى بنفسه: «حاز الجائزةَ».'),
    _Phrase(
      '((?:[وف])?(?:تخرجت|تخرجوا|يتخرج|تتخرج|يتخرجون|التخرج))\\s+من',
      <String>['{1} في'],
      message: 'الأفصح «تخرّج في» الجامعة.',
    ),
    _Phrase('((?:[وف])?[يت]?)نوه(ت|وا)?\\s+إلى', <String>[
      '{1}نبه{2} إلى',
    ], message: '«نوّه به» أثنى عليه؛ للتنبيه يُستعمل «نبّه إلى».'),
    _Phrase('((?:[وف])?)التنويه\\s+إلى', <String>[
      '{1}التنبيه إلى',
    ], message: '«نوّه به» أثنى عليه؛ للتنبيه يُستعمل «نبّه إلى».'),
    _Phrase('لا\\s+يجب\\s+أن', <String>[
      'يجب ألا',
    ], message: 'المقصود وجوب النفي لا نفي الوجوب: «يجب ألّا».'),
    _Phrase(
      '(?:مقارنة|بالمقارنة|المقارنة|قارن|قارنت|يقارن|تقارن|نقارن)\\s+مع',
      <String>['ب'],
      span: _PhraseSpan.lastWordWithFollowingSpace,
      message: 'الأفصح «قارنه به» و«مقارنةً بـ».',
    ),
    _Phrase(
      '((?:[وف])?(?:دخل|دخلت|دخلوا|يدخل|تدخل|يدخلون|الدخول|دخول))\\s+إلى',
      <String>['{1}'],
      message: '«دخل» يتعدى بنفسه: «دخل البيتَ».',
    ),
    _Phrase('((?:[وف])?)لعب(?=\\s+(?:دورا|الدور|دور)(?![$_l]))', <String>[
      '{1}أدى',
    ], message: '«لعب دورًا» ترجمة حرفية؛ الأفصح «أدّى دورًا».'),
    _Phrase('((?:[وف])?)لعبت(?=\\s+(?:دورا|الدور|دور)(?![$_l]))', <String>[
      '{1}أدت',
    ], message: '«لعب دورًا» ترجمة حرفية؛ الأفصح «أدّى دورًا».'),
    _Phrase('((?:[وف])?)لعبوا(?=\\s+(?:دورا|الدور|دور)(?![$_l]))', <String>[
      '{1}أدوا',
    ], message: '«لعب دورًا» ترجمة حرفية؛ الأفصح «أدّى دورًا».'),
    _Phrase('((?:[وف])?)يلعب(?=\\s+(?:دورا|الدور|دور)(?![$_l]))', <String>[
      '{1}يؤدي',
    ], message: '«لعب دورًا» ترجمة حرفية؛ الأفصح «أدّى دورًا».'),
    _Phrase('((?:[وف])?)تلعب(?=\\s+(?:دورا|الدور|دور)(?![$_l]))', <String>[
      '{1}تؤدي',
    ], message: '«لعب دورًا» ترجمة حرفية؛ الأفصح «أدّى دورًا».'),
    _Phrase('((?:[وف])?)يلعبون(?=\\s+(?:دورا|الدور|دور)(?![$_l]))', <String>[
      '{1}يؤدون',
    ], message: '«لعب دورًا» ترجمة حرفية؛ الأفصح «أدّى دورًا».'),
    _Phrase('((?:[وفبل])?)كافة(?=\\s+ال)', <String>[
      '{1}جميع',
    ], message: '«كافّة» تأتي حالًا بعد الاسم: «الناس كافّةً»، لا مضافة.'),
    _Phrase(
      'ليس\\s+فقط',
      <String>[],
      message: '«ليس فقط … بل» ترجمة حرفية؛ الأفصح «لا … فحسب، بل …».',
    ),
    _Phrase('بعين\\s+الاعتبار', <String>[
      'في الحسبان',
      'في الاعتبار',
    ], message: '«أخذ بعين الاعتبار» ترجمة حرفية؛ الأفصح «في الحسبان».'),
    _Phrase('((?:[وف])?)كنتيجة', <String>[
      '{1}نتيجةً',
    ], message: 'الكاف هنا ترجمة حرفية لـ«as»؛ الأفصح النصب على الحال.'),
    _Phrase('((?:[وف])?)كبديل', <String>[
      '{1}بديلًا',
    ], message: 'الكاف هنا ترجمة حرفية لـ«as»؛ الأفصح النصب على الحال.'),
    _Phrase('((?:[وف])?)كمثال', <String>[
      '{1}مثالًا',
    ], message: 'الكاف هنا ترجمة حرفية لـ«as»؛ الأفصح النصب على الحال.'),
    _Phrase('((?:[وف])?)كجزء\\s+من', <String>[
      '{1}جزءًا من',
    ], message: 'الكاف هنا ترجمة حرفية لـ«as»؛ الأفصح النصب على الحال.'),
    _Phrase('(لا\\s*بد)\\s+و\\s*(أن|أنه|أنها)', <String>[
      '{1} {2}',
    ], message: 'الواو بين «لا بدّ» و«أنّ» زائدة.'),
    _Phrase('((?:لا\\s+سيما|خاصة))\\s+و\\s*(أن|أنه|أنها)', <String>[
      '{1} {2}',
    ], message: 'الواو قبل «أنّ» هنا زائدة.'),
    _Phrase('حتى\\s+و\\s*لو', <String>[
      'ولو',
      'حتى لو',
    ], message: 'الجمع بين «حتى» والواو قبل «لو» زائد.'),
    _Phrase(
      'سواء\\s+(?:(?!أم(?![$_l]))$_w\\s+){1,5}?أو',
      <String>['أم '],
      span: _PhraseSpan.lastWordWithFollowingSpace,
      message: 'يُعطف بعد «سواء» بـ«أم» على الأفصح.',
    ),
    _Phrase('عاجلا\\s+أو\\s+آجلا', <String>[
      'عاجلًا أم آجلًا',
    ], message: 'العبارة المأثورة «عاجلًا أم آجلًا».'),
    _Phrase('وجه\\s+لوجه', <String>[
      'وجهًا لوجه',
    ], message: 'العبارة «وجهًا لوجه» بنصب الأولى.'),
    _Phrase('يوم\\s+بعد\\s+يوم', <String>[
      'يومًا بعد يوم',
    ], message: 'العبارة «يومًا بعد يوم» بنصب الأولى.'),
    _Phrase('(?<!من\\s)جراء', <String>[
      'من جراء',
    ], message: '«جرّاء» تُستعمل مع «مِن»: «من جرّاء».'),
    _Phrase('في\\s+إطار', <String>[
      'في',
      'ضمن',
    ], message: '«في إطار» حشو في الغالب؛ تكفي «في» أو «ضمن».'),
    _Phrase(
      '((?:[وف])?)(?:تم|تمت|يتم|تتم|سيتم|ستتم)(?=\\s+[$_l])',
      <String>[],
      message:
          'الفعل المبني للمجهول أوجز غالبًا من «تمّ» + المصدر '
          '(«تمّ افتتاح المعرض» ← «افتُتح المعرض»).',
    ),
    _Phrase(
      '((?:[وفب])?)نفس\\s+(ال$_w)(?!\\s+(?:ذاته|ذاتها|نفسه|نفسها))',
      <String>['{1}{2} نفسه', '{1}{2} نفسها'],
      message: 'إن كانت «نفس» للتوكيد فالأفصح أن تأتي بعد الاسم: «الشيء نفسه».',
    ),
    _Phrase(
      '((?:[وف])?(?:أجاب|أجابت|أجابوا|يجيب|تجيب|يجيبون|الإجابة|إجابة|'
      'للإجابة))\\s+على',
      <String>['{1} عن'],
      message: 'الأفصح «أجاب عن السؤال».',
    ),
    _Phrase(
      '((?:[وف])?(?:تعرف|تعرفت|تعرفوا|يتعرف|تتعرف|نتعرف|أتعرف|التعرف|'
      'للتعرف))\\s+على',
      <String>['{1} إلى'],
      message: 'الأفصح «تعرّف إليه» أو «تعرّفه».',
    ),
    _Phrase(
      '((?:[وف])?(?:تزوج|تزوجت|تزوجوا|يتزوج|تتزوج|يتزوجون))\\s+من',
      <String>['{1}'],
      message: '«تزوّج» يتعدى بنفسه: «تزوّجها».',
    ),
    _Phrase(
      '((?:[وف])?(?:التقى|التقت|التقوا|يلتقي|تلتقي|يلتقون))\\s+ب'
      '(?!(?:ه|ها|هم|هما|هن|ك|كم|نا|ي)(?![$_l]))($_w)',
      <String>['{1} {2}'],
      message: '«التقى» يتعدى بنفسه: «التقى صديقَه».',
    ),
    _Phrase('((?:[وف])?(?:يزيد|تزيد|زاد|زادت|يزيدون|زيادة))\\s+عن', <String>[
      '{1} على',
    ], message: '«زاد» يتعدى بـ«على»: «يزيد على المئة».'),
    _Phrase('((?:[وف])?)بدلا\\s+عن', <String>[
      '{1}بدلًا من',
    ], message: 'الأفصح «بدلًا من».'),
    _Phrase('((?:[وف])?)عدا\\s+عن', <String>[
      '{1}عدا',
      '{1}فضلًا عن',
    ], message: '«عدا» تستغني عن «عن».'),
    _Phrase('بالمئة|بالمائة', <String>[
      'في المئة',
    ], message: 'الأفصح «في المئة».'),
    _Phrase(
      '((?:[وف])?(?:قال|قالت|قالوا|يقول|تقول|يقولون))\\s+بأن(ه|ها|هم)?',
      <String>['{1} إن{2}'],
      message: 'بعد القول تأتي «إنّ» المكسورة بلا باء.',
    ),
    _Phrase('إذ\\s+أن(ه|ها|هم|هما|نا|ني|ك|كم)?', <String>[
      'إذ إن{1}',
    ], message: 'تُكسر همزة «إنّ» بعد «إذ».'),
    _Phrase('شتان\\s+ما\\s+بين', <String>[
      'شتان بين',
      'شتان ما',
    ], message: 'الأفصح «شتّان بين» أو «شتّان ما»، لا الجمع بينهما.'),
    _Phrase('((?:[وف])?)من\\s+ضمن', <String>[
      '{1}ضمن',
      '{1}من بين',
    ], message: '«ضمن» تغني عن «من» قبلها.'),
    _Phrase('عن\\s+طريق\\s+الخطأ', <String>[
      'خطأً',
      'سهوًا',
    ], message: '«عن طريق الخطأ» ترجمة حرفية؛ الأفصح «خطأً» أو «سهوًا».'),
    _Phrase(
      '((?:[وف])?)لاقى(?=\\s+(?:نجاحا|رواجا|استحسانا|إقبالا|ترحيبا|حتفه)(?![$_l]))',
      <String>['{1}لقي'],
      message: '«لاقاه» قابله؛ لمعنى الإصابة والوجدان الأفصح «لقي».',
    ),
    _Phrase(
      '((?:[وف])?)لاقت(?=\\s+(?:نجاحا|رواجا|استحسانا|إقبالا|ترحيبا|حتفها)(?![$_l]))',
      <String>['{1}لقيت'],
      message: '«لاقاه» قابله؛ لمعنى الإصابة والوجدان الأفصح «لقي».',
    ),
    _Phrase('(يكاد|تكاد|نكاد|أكاد|يكادون|تكادون)\\s+لا', <String>[
      'لا {1}',
    ], message: 'يتقدم النفي على «كاد»: «لا يكاد يُرى».'),
    _Phrase('((?:[وف])?(?:كاد|كادت|كادوا|يكاد|تكاد|يكادون))\\s+أن', <String>[
      '{1}',
    ], message: 'الأكثر في خبر «كاد» أن يأتي بلا «أن».'),
    _Phrase('((?:[وف])?(?:سبق|سبقت|يسبق))\\s+و\\s*(أن)', <String>[
      '{1} {2}',
    ], message: 'الواو بين «سبق» و«أن» زائدة.'),
    _Phrase(
      '((?:[وف])?(?:اتصل|اتصلت|اتصلوا|يتصل|تتصل|يتصلون|الاتصال))\\s+على\\s+($_w)',
      <String>['{1} ب{2}'],
      message: '«اتصل» يتعدى بالباء: «اتصل به».',
    ),
    _Phrase('تعاطى\\s+مع', <String>[
      'تعامل مع',
    ], message: '«تعاطى» تناول؛ لمعنى التعامل الأفصح «تعامل مع».'),
    _Phrase('تعاطت\\s+مع', <String>[
      'تعاملت مع',
    ], message: '«تعاطى» تناول؛ لمعنى التعامل الأفصح «تعامل مع».'),
    _Phrase('يتعاطى\\s+مع', <String>[
      'يتعامل مع',
    ], message: '«تعاطى» تناول؛ لمعنى التعامل الأفصح «تعامل مع».'),
    _Phrase('التعاطي\\s+مع', <String>[
      'التعامل مع',
    ], message: '«تعاطى» تناول؛ لمعنى التعامل الأفصح «تعامل مع».'),
    _Phrase('خصوصا\\s+و\\s*(أن|أنه|أنها)', <String>[
      'خصوصًا {1}',
    ], message: 'الواو قبل «أنّ» هنا زائدة.'),
    _Phrase('حتى\\s+و\\s*إن', <String>[
      'وإن',
      'حتى إن',
    ], message: 'الجمع بين «حتى» والواو قبل «إن» زائد.'),
    _Phrase('أكثر\\s+من\\s+أي\\s+وقت\\s+مضى', <String>[
      'أكثر من ذي قبل',
    ], message: 'ترجمة حرفية؛ الأفصح «أكثر من ذي قبل».'),
    ..._toIlaPhrases,
  ];

  /// Verbs (with their verbal nouns) that take `إلى`, but are often written
  /// with a lam before a definite noun (`انضم للفريق`). Only the definite
  /// `لل` form is matched: before an indefinite word the lam may mean
  /// purpose (`سعى ليحقق`). Advice only, because `لل` also absorbs a
  /// noun-initial lam (`للغة` = لـ + اللغة).
  static const List<String> _toIla = <String>[
    'احتاج|احتاجت|احتاجوا|يحتاج|تحتاج|نحتاج|أحتاج|يحتاجون|بحاجة|حاجة|الحاجة',
    'استمع|استمعت|استمعوا|يستمع|تستمع|نستمع|أستمع|يستمعون|الاستماع',
    'انضم|انضمت|انضموا|ينضم|تنضم|ينضمون|الانضمام|انضمام|بالانضمام',
    'أشار|أشارت|أشاروا|يشير|تشير|يشيرون|الإشارة|إشارة',
    'توصل|توصلت|توصلوا|يتوصل|تتوصل|التوصل',
    'انتمى|انتمت|ينتمي|تنتمي|ينتمون|الانتماء|انتماء',
    'يهدف|تهدف|يهدفون|تهدفان',
    'سعى|سعت|سعوا|يسعى|تسعى|يسعون|السعي',
    'لجأ|لجأت|لجؤوا|يلجأ|تلجأ|يلجؤون|اللجوء|لجوء',
    'بالإضافة|إضافة',
    'تحول|تحولت|تحولوا|يتحول|تتحول|يتحولون|التحول',
    'تطرق|تطرقت|يتطرق|تتطرق|التطرق',
    'اضطر|اضطرت|اضطروا|يضطر|تضطر|يضطرون',
    'افتقر|افتقرت|يفتقر|تفتقر|يفتقرون|الافتقار|افتقار',
    'استند|استندت|يستند|تستند|يستندون|استنادا|بالاستناد',
    'يرجع|ترجع|يرجعون|يعود|تعود|يعودون',
    'يميل|تميل|يميلون',
    'أحال|أحالت|يحيل|تحيل|إحالة|الإحالة',
    'نظر|نظرت|ينظر|تنظر|ينظرون|بالنظر',
    'أساء|أساءت|يسيء|تسيء|الإساءة|إساءة',
    'أصغى|يصغي|تصغي|الإصغاء',
    'بادر|بادرت|بادروا|يبادر|تبادر|يبادرون',
    'سارع|سارعت|سارعوا|يسارع|يسارعون',
    'تطلع|تطلعت|يتطلع|تتطلع|يتطلعون|التطلع',
    'اشتاق|اشتاقت|يشتاق|تشتاق|أشتاق|نشتاق|الاشتياق|اشتياق',
    'أضاف|أضافت|يضيف|تضيف|يضيفون',
    'اهتدى|اهتدت|يهتدي|تهتدي',
    'نزح|نزحت|نزحوا|ينزح|تنزح|ينزحون|النزوح',
    'أوعز|أوعزت|يوعز',
    'ارتقى|ارتقت|يرتقي|ترتقي',
    'بالنسبة',
    'نظرا',
  ];

  static final List<_Phrase> _toIlaPhrases = <_Phrase>[
    for (final String forms in _toIla)
      _Phrase(
        '(?:[وف])?(?:$forms)\\s+لل$_w',
        <String>[],
        message:
            'يتعدى هذا الفعل بـ«إلى» على الأفصح: «${forms.split('|').first} '
            'إلى ال…» لا «${forms.split('|').first} لل…».',
      ),
  ];

  static const List<_Phrase> _expressionErrors = <_Phrase>[
    _Phrase('(?<!لا\\s{0,3})سيما', <String>[
      'لا سيما',
    ], message: 'التعبير الصحيح «لا سيّما» بإثبات «لا».'),
    _Phrase('(?:إنشاء|انشاء)\\s+الله(?=\\s*(?:[.،,؛;؟?!]|\$|تعالى))', <String>[
      'إن شاء الله',
    ], message: '«إنشاء» بمعنى الخلق؛ عبارة المشيئة تُكتب «إن شاء الله».'),
    _Phrase('على\\s+حدى', <String>[
      'على حدة',
    ], message: 'تُكتب «على حِدَة» بالتاء المربوطة.'),
    _Phrase('على\\s+حدا', <String>[
      'على حدة',
    ], message: 'تُكتب «على حِدَة» بالتاء المربوطة.'),
    _Phrase('((?:[وف])?)سوف\\s+(?:لن|لا)', <String>[
      '{1}لن',
    ], message: '«سوف» لا تسبق أداة النفي؛ لنفي المستقبل تُستعمل «لن».'),
    _Phrase('عن\\s+ما', <String>[
      'عمّا',
    ], message: 'تُدغم نون «عن» في «ما» فتُكتبان كلمة واحدة: «عمّا».'),
    _Phrase('عن\\s+من', <String>[
      'عمّن',
    ], message: 'تُدغم نون «عن» في «مَن» فتُكتبان كلمة واحدة: «عمّن».'),
    _Phrase(
      'من\\s+ما(?!\\s+(?:زال|زالت|زالوا|يزال|تزال|يزالون|دام|دامت|فتئ|برح|انفك))',
      <String>['مما'],
      message: 'تُدغم نون «مِن» في «ما» فتُكتبان كلمة واحدة: «ممّا».',
    ),
    _Phrase(
      '(?!بادئ\\s+ذي\\s+بدء(?![$_l]))(?:بادئ|باديء)\\s+(?:ذو|ذا|ذي)\\s+(?:بدء|بدئ|بدأ)',
      <String>['بادئ ذي بدء'],
      message: 'العبارة الثابتة «بادئَ ذي بَدْء».',
    ),
    _Phrase('حجرة\\s+عثرة', <String>[
      'حجر عثرة',
    ], message: 'العبارة «حَجَر عَثْرة»؛ «الحُجرة» هي الغرفة.'),
    _Phrase('لا\\s+محال', <String>[
      'لا محالة',
    ], message: 'العبارة «لا مَحالة» بالتاء المربوطة.'),
    _Phrase('الآن\\s+وصاعدا', <String>[
      'الآن فصاعدًا',
    ], message: 'العبارة «من الآن فصاعدًا» بالفاء.'),
    _Phrase('غيظ\\s+من\\s+فيض', <String>[
      'غيض من فيض',
    ], message: '«الغَيْض» هو القليل؛ «الغيظ» هو الغضب.'),
    _Phrase('(?:الأنف|الانف)\\s+الذكر', <String>[
      'الآنف الذكر',
    ], message: '«الآنف» بالمدّ بمعنى السابق؛ «الأنف» عضو الشم.'),
    _Phrase(
      '((?:[وف])?(?:المذكور|المذكورة|المذكورين|المذكورون|ذكرنا|ذكرناه|أشرنا|أسلفنا))\\s+[أا]نفا',
      <String>['{1} آنفًا'],
      message: '«آنفًا» بالمدّ بمعنى قبل قليل؛ «أنفًا» عضو الشم.',
    ),
    _Phrase('جنب\\s+إلى\\s+جنب', <String>[
      'جنبًا إلى جنب',
    ], message: 'العبارة الثابتة «جنبًا إلى جنب» بنصب الأولى.'),
    _Phrase('(على\\s+|ب)أيه\\s+حال', <String>[
      '{1}أية حال',
    ], message: 'تُكتب «أيّة» بالتاء المربوطة في هذه العبارة.'),
    _Phrase('الله\\s+علية\\s+وسلم', <String>[
      'الله عليه وسلم',
    ], message: 'ضمير الغائب «عليه» يُكتب بالهاء.'),
    _Phrase('علية\\s+السلام', <String>[
      'عليه السلام',
    ], message: 'ضمير الغائب «عليه» يُكتب بالهاء.'),
    _Phrase('(رضي|رحمه)\\s+الله\\s+(?:عنة|علية)', <String>[
      '{1} الله عنه',
    ], message: 'ضمير الغائب يُكتب بالهاء.'),
    _Phrase('مسقط\\s+راس', <String>[
      'مسقط رأس',
    ], message: '«رأس» بهمزة على الألف.'),
    _Phrase('راس\\s+(المال|السنة|الهرم)', <String>[
      'رأس {1}',
    ], message: '«رأس» بهمزة على الألف.'),
    _Phrase('آن\\s+ذاك', <String>['آنذاك'], message: '«آنذاك» كلمة واحدة.'),
    _Phrase('بين\\s+الحين\\s+والأخر', <String>[
      'بين الحين والآخر',
    ], message: 'العبارة «بين الحين والآخَر» بالمدّ.'),
    _Phrase('رغم\\s+عن', <String>[
      'رغمًا عن',
    ], message: 'العبارة «رغمًا عن» بالنصب، أو «رغم» بلا «عن».'),
    _Phrase('هلم\\s+جرى', <String>[
      'هلم جرا',
    ], message: 'العبارة «هلمّ جرًّا» بالألف.'),
    _Phrase('إلى\\s+آخرة(?=\\s*(?:[.،,؛;؟?!)]|\$))', <String>[
      'إلى آخره',
    ], message: '«إلى آخره» بضمير الغائب؛ «الآخرة» دار البقاء.'),
    _Phrase('((?:على\\s+ال|بال)رغم)\\s+(أن|أنه|أنها|أنهم)', <String>[
      '{1} من {2}',
    ], message: '«على الرغم» تحتاج إلى «من» قبل «أنّ».'),
    _Phrase('بالإضافة\\s+على', <String>[
      'بالإضافة إلى',
    ], message: '«الإضافة» تتعدى بـ«إلى».'),
    _Phrase('علاوة\\s+عن', <String>[
      'علاوة على',
    ], message: '«علاوة» تتعدى بـ«على».'),
    _Phrase('بغض\\s+النظر\\s+على', <String>[
      'بغض النظر عن',
    ], message: '«بغضّ النظر» تتعدى بـ«عن».'),
  ];

  /// Compiled phrase patterns, shared across checks.
  static final Map<String, RegExp> _phraseRegExps = <String, RegExp>{};

  void _phraseList(
    String id,
    List<_Phrase> phrases,
    String fallback,
    OfficeProofingCategory category,
  ) {
    if (!enabled(id)) return;
    final String bare = bareText.bare;
    for (final _Phrase phrase in phrases) {
      final RegExp re = _phraseRegExps.putIfAbsent(
        phrase.pattern,
        () => RegExp(
          '(?<![$_tokenContinuation])(?:${phrase.pattern})(?![$_tokenContinuation])',
          unicode: true,
        ),
      );
      for (final RegExpMatch m in re.allMatches(bare)) {
        final List<String> replacements = <String>[
          for (final String r in phrase.replacements)
            r.replaceAllMapped(
              RegExp(r'\{(\d)\}'),
              (Match g) => (m.group(int.parse(g.group(1)!)) ?? '').replaceAll(
                RegExp(r'\s+'),
                ' ',
              ),
            ),
        ];
        int bs = m.start;
        int be = m.end;
        final String all = m.group(0)!;
        switch (phrase.span) {
          case _PhraseSpan.whole:
            break;
          case _PhraseSpan.deleteTail:
            bs = m.start + RegExp(r'\s+\S+$').firstMatch(all)!.start;
          case _PhraseSpan.lastWordWithFollowingSpace:
            bs = m.start + RegExp(r'\S+$').firstMatch(all)!.start;
            while (be < bare.length && bare[be] == ' ') {
              be++;
            }
          case _PhraseSpan.wholeWithFollowingSpace:
            while (be < bare.length && bare[be] == ' ') {
              be++;
            }
        }
        add(
          id,
          bareText.start(bs),
          phrase.span == _PhraseSpan.whole ||
                  phrase.span == _PhraseSpan.deleteTail
              ? bareText.end(be)
              : bareText.start(be),
          phrase.message ?? fallback,
          category: category,
          replacements: replacements,
        );
      }
    }
  }

  void _phrases() {
    final bool doubleFuture = enabled('ar.redundancy.double-future');
    if (doubleFuture) {
      for (final RegExpMatch m in RegExp(
        '(?<![$_tokenContinuation])((?:[وف])?)سوف\\s+'
        '(س[يتنأ](?!ار)[$_l]+)(?![$_tokenContinuation])',
        unicode: true,
      ).allMatches(bareText.bare)) {
        final int verb = m.start + m.group(0)!.lastIndexOf(m.group(2)!);
        final int start = bareText.start(m.start);
        final int verbStart = bareText.start(verb);
        final int verbRest = bareText.start(verb + 1);
        final int end = bareText.end(m.end);
        add(
          'ar.redundancy.double-future',
          start,
          end,
          'علامتا استقبال معًا: استعمل «سوف» أو السين، لا كلتيهما.',
          category: OfficeProofingCategory.grammar,
          replacements: <String>[
            '${m.group(1)}${text.substring(verbStart, end)}',
            '${m.group(1)}سوف ${text.substring(verbRest, end)}',
          ],
        );
      }
    }
    _phraseList(
      'ar.redundancy.phrase',
      _redundancy,
      'في العبارة تكرار للمعنى.',
      OfficeProofingCategory.style,
    );
    _phraseList(
      'ar.style.wordiness',
      _wordiness,
      'عبارة مطوّلة يمكن اختصارها.',
      OfficeProofingCategory.style,
    );
    _phraseList(
      'ar.usage.expression',
      _usageExpressions,
      'تعبير مختلف فيه؛ هذا هو الأفصح.',
      OfficeProofingCategory.style,
    );
    _phraseList(
      'ar.expression.error',
      _expressionErrors,
      'خطأ في عبارة ثابتة.',
      OfficeProofingCategory.spelling,
    );
  }

  // ---------------------- word tables (S9 frozen, L3, L4, L7, S10)

  /// Frozen misspellings with a single correct form.
  static const Map<String, List<String>> _commonSpelling =
      <String, List<String>>{
        'هاذا': <String>['هذا'],
        'هاذه': <String>['هذه'],
        'هاذان': <String>['هذان'],
        'هاذين': <String>['هذين'],
        'ذالك': <String>['ذلك'],
        'هاكذا': <String>['هكذا'],
        'هاؤلاء': <String>['هؤلاء'],
        'هاولاء': <String>['هؤلاء'],
        'هؤولاء': <String>['هؤلاء'],
        'لاكن': <String>['لكن'],
        'لاكنه': <String>['لكنه'],
        'لاكنها': <String>['لكنها'],
        'لاكني': <String>['لكني'],
        'لاكننا': <String>['لكننا'],
        'ألذي': <String>['الذي'],
        'ألتي': <String>['التي'],
        'ألذين': <String>['الذين'],
        'إنشالله': <String>['إن شاء الله'],
        'انشالله': <String>['إن شاء الله'],
        'ماشاءالله': <String>['ما شاء الله'],
        'ماشالله': <String>['ما شاء الله'],
        'اللة': <String>['الله'],
        'الضهر': <String>['الظهر'],
        'الضلام': <String>['الظلام'],
        'انتضار': <String>['انتظار'],
        'إنتضار': <String>['انتظار'],
        'محضوظ': <String>['محظوظ'],
        'ضروف': <String>['ظروف'],
        'الضروف': <String>['الظروف'],
        'مضلوم': <String>['مظلوم'],
        'شيئ': <String>['شيء'],
        'مسؤل': <String>['مسؤول'],
        'إمرأة': <String>['امرأة'],
        'إبن': <String>['ابن'],
        'إبنة': <String>['ابنة'],
        'إسم': <String>['اسم'],
        'إسمه': <String>['اسمه'],
        'إسمها': <String>['اسمها'],
        'إثنان': <String>['اثنان'],
        'إثنين': <String>['اثنين'],
        'إثنتان': <String>['اثنتان'],
        'إثنتين': <String>['اثنتين'],
        'إنتهى': <String>['انتهى'],
        'إنتهت': <String>['انتهت'],
        'إستطاع': <String>['استطاع'],
        'إستطاعت': <String>['استطاعت'],
        'إستمر': <String>['استمر'],
        'إستمرت': <String>['استمرت'],
        'إجتمع': <String>['اجتمع'],
        'إجتمعت': <String>['اجتمعت'],
        'إنتقل': <String>['انتقل'],
        'إنتقلت': <String>['انتقلت'],
        'إعتبر': <String>['اعتبر'],
        'إستخدم': <String>['استخدم'],
        'شئ': <String>['شيء'],
        'الشئ': <String>['الشيء'],
        'الشيئ': <String>['الشيء'],
        'جزئ': <String>['جزء', 'جزيء'],
        'بطيئ': <String>['بطيء'],
        'مليئ': <String>['مليء'],
        'بريئ': <String>['بريء'],
        'جريئ': <String>['جريء'],
        'مجيئ': <String>['مجيء'],
        'رديئ': <String>['رديء'],
        'مضيئ': <String>['مضيء'],
        'دنيئ': <String>['دنيء'],
        'مفاجاة': <String>['مفاجأة'],
        'المفاجاة': <String>['المفاجأة'],
        'مكافاة': <String>['مكافأة'],
        'المكافاة': <String>['المكافأة'],
        'مكافاءة': <String>['مكافأة'],
        'منشاة': <String>['منشأة'],
        'المنشاة': <String>['المنشأة'],
        'هيأة': <String>['هيئة'],
        'الهيأة': <String>['الهيئة'],
        'تفائل': <String>['تفاؤل', 'تفاءل'],
        'التفائل': <String>['التفاؤل'],
        'تشائم': <String>['تشاؤم', 'تشاءم'],
        'التشائم': <String>['التشاؤم'],
        'تسائل': <String>['تساءل', 'تساؤل'],
        'يتسائل': <String>['يتساءل'],
        'تتسائل': <String>['تتساءل'],
        'تسائلات': <String>['تساؤلات'],
        'التسائلات': <String>['التساؤلات'],
        'تضائل': <String>['تضاءل'],
        'يتضائل': <String>['يتضاءل'],
        'اجرائات': <String>['إجراءات'],
        'إجرائات': <String>['إجراءات'],
        'الاجرائات': <String>['الإجراءات'],
        'الإجرائات': <String>['الإجراءات'],
        'قرائة': <String>['قراءة'],
        'القرائة': <String>['القراءة'],
        'قراة': <String>['قراءة'],
        'برائة': <String>['براءة'],
        'البرائة': <String>['البراءة'],
        'كفائة': <String>['كفاءة'],
        'الكفائة': <String>['الكفاءة'],
        'اسائة': <String>['إساءة'],
        'إسائة': <String>['إساءة'],
        'اضائة': <String>['إضاءة'],
        'إضائة': <String>['إضاءة'],
        'انشائات': <String>['إنشاءات'],
        'إنشائات': <String>['إنشاءات'],
        'موسسة': <String>['مؤسسة'],
        'الموسسة': <String>['المؤسسة'],
        'موسسات': <String>['مؤسسات'],
        'الموسسات': <String>['المؤسسات'],
        'موتمر': <String>['مؤتمر'],
        'الموتمر': <String>['المؤتمر'],
        'موتمرات': <String>['مؤتمرات'],
        'موشر': <String>['مؤشر'],
        'الموشر': <String>['المؤشر'],
        'موشرات': <String>['مؤشرات'],
        'موخرا': <String>['مؤخرا'],
        'موكد': <String>['مؤكد'],
        'موثر': <String>['مؤثر'],
        'موثرة': <String>['مؤثرة'],
        'موهل': <String>['مؤهل'],
        'موهلات': <String>['مؤهلات'],
        'موامرة': <String>['مؤامرة'],
        'الموامرة': <String>['المؤامرة'],
        'روساء': <String>['رؤساء'],
        'الروساء': <String>['الرؤساء'],
        'رؤوساء': <String>['رؤساء'],
        'الرؤوساء': <String>['الرؤساء'],
        'سوال': <String>['سؤال'],
        'السوال': <String>['السؤال'],
        'يوكد': <String>['يؤكد'],
        'توكد': <String>['تؤكد'],
        'يوثر': <String>['يؤثر'],
        'ماساة': <String>['مأساة'],
        'الماساة': <String>['المأساة'],
        'مازق': <String>['مأزق'],
        'المازق': <String>['المأزق'],
        'ماكولات': <String>['مأكولات'],
        'مسالة': <String>['مسألة'],
        'المسالة': <String>['المسألة'],
        'مبدا': <String>['مبدأ'],
        'المبدا': <String>['المبدأ'],
        'منشا': <String>['منشأ'],
        'المنشا': <String>['المنشأ'],
        'تاثير': <String>['تأثير'],
        'التاثير': <String>['التأثير'],
        'تاكيد': <String>['تأكيد'],
        'التاكيد': <String>['التأكيد'],
        'تاسيس': <String>['تأسيس'],
        'التاسيس': <String>['التأسيس'],
        'تامين': <String>['تأمين'],
        'التامين': <String>['التأمين'],
        'تاخير': <String>['تأخير'],
        'التاخير': <String>['التأخير'],
        'تاخر': <String>['تأخر'],
        'تاثر': <String>['تأثر'],
        'تاهل': <String>['تأهل'],
        'هاديء': <String>['هادئ'],
        'الهاديء': <String>['الهادئ'],
        'شاطيء': <String>['شاطئ'],
        'الشاطيء': <String>['الشاطئ'],
        'قاريء': <String>['قارئ'],
        'القاريء': <String>['القارئ'],
        'ناشيء': <String>['ناشئ'],
        'طاريء': <String>['طارئ'],
        'الطواريء': <String>['الطوارئ'],
        'مباديء': <String>['مبادئ'],
        'لاجيء': <String>['لاجئ'],
        'اللاجيء': <String>['اللاجئ'],
        'موانيء': <String>['موانئ'],
        'الموانيء': <String>['الموانئ'],
        'شواطيء': <String>['شواطئ'],
        'مفاجيء': <String>['مفاجئ'],
        'دافيء': <String>['دافئ'],
        'خاطيء': <String>['خاطئ'],
        'الخاطيء': <String>['الخاطئ'],
        'دايما': <String>['دائما'],
        'قايمة': <String>['قائمة'],
        'القايمة': <String>['القائمة'],
        'رايع': <String>['رائع'],
        'رايعة': <String>['رائعة'],
        'جايزة': <String>['جائزة'],
        'الجايزة': <String>['الجائزة'],
        'طايرة': <String>['طائرة'],
        'الطايرة': <String>['الطائرة'],
        'فايدة': <String>['فائدة'],
        'الفايدة': <String>['الفائدة'],
        'عايلة': <String>['عائلة'],
        'العايلة': <String>['العائلة'],
        'سايق': <String>['سائق'],
        'السايق': <String>['السائق'],
        'نايب': <String>['نائب'],
        'دايرة': <String>['دائرة'],
        'الدايرة': <String>['الدائرة'],
        'الجزاير': <String>['الجزائر'],
        'رسايل': <String>['رسائل'],
        'الرسايل': <String>['الرسائل'],
        'وسايل': <String>['وسائل'],
        'الوسايل': <String>['الوسائل'],
        'الامر': <String>['الأمر'],
        'الاخرى': <String>['الأخرى'],
        'الاخر': <String>['الآخر', 'الأخر'],
        'الاخير': <String>['الأخير'],
        'الاخيرة': <String>['الأخيرة'],
        'الاول': <String>['الأول'],
        'الاولى': <String>['الأولى'],
        'الارض': <String>['الأرض'],
        'الانسان': <String>['الإنسان'],
        'الاسلام': <String>['الإسلام'],
        'الاسلامي': <String>['الإسلامي'],
        'الاسلامية': <String>['الإسلامية'],
        'الاعلام': <String>['الإعلام', 'الأعلام'],
        'الادارة': <String>['الإدارة'],
        'الانتاج': <String>['الإنتاج'],
        'الاوروبي': <String>['الأوروبي'],
        'الاوروبية': <String>['الأوروبية'],
        'الامريكي': <String>['الأمريكي'],
        'الامريكية': <String>['الأمريكية'],
        'الافريقي': <String>['الأفريقي', 'الإفريقي'],
        'الاسرائيلي': <String>['الإسرائيلي'],
        'الاسرة': <String>['الأسرة'],
        'الاهل': <String>['الأهل'],
        'الاب': <String>['الأب', 'الآب'],
        'الام': <String>['الأم', 'آلام'],
        'الاخ': <String>['الأخ'],
        'الاخت': <String>['الأخت'],
        'الاطباء': <String>['الأطباء'],
        'الامراض': <String>['الأمراض'],
        'الاعمال': <String>['الأعمال'],
        'الاموال': <String>['الأموال'],
        'الاراضي': <String>['الأراضي'],
        'الاحزاب': <String>['الأحزاب'],
        'الاحداث': <String>['الأحداث'],
        'الاخبار': <String>['الأخبار'],
        'الاشخاص': <String>['الأشخاص'],
        'الاشياء': <String>['الأشياء'],
        'الافكار': <String>['الأفكار'],
        'الايام': <String>['الأيام'],
        'الاسبوع': <String>['الأسبوع'],
        'الاسعار': <String>['الأسعار'],
        'الاطفال': <String>['الأطفال'],
        'الافلام': <String>['الأفلام'],
        'الالعاب': <String>['الألعاب'],
        'الاعضاء': <String>['الأعضاء'],
        'الامير': <String>['الأمير'],
        'الاميرة': <String>['الأميرة'],
        'الامام': <String>['الإمام', 'الأمام'],
        'الامة': <String>['الأمة'],
        'الامم': <String>['الأمم'],
        'الامن': <String>['الأمن'],
        'الاساسي': <String>['الأساسي'],
        'الاساسية': <String>['الأساسية'],
        'الاكبر': <String>['الأكبر'],
        'الاكثر': <String>['الأكثر'],
        'الافضل': <String>['الأفضل'],
        'الاقل': <String>['الأقل'],
        'الاردن': <String>['الأردن'],
        'الامارات': <String>['الإمارات'],
        'الانجليزية': <String>['الإنجليزية'],
        'الاسكندرية': <String>['الإسكندرية'],
        'الانترنت': <String>['الإنترنت'],
        'الاعلان': <String>['الإعلان'],
        'الاطار': <String>['الإطار'],
        'الاجراءات': <String>['الإجراءات'],
        'الاصلاح': <String>['الإصلاح'],
        'الاحد': <String>['الأحد'],
        'الاربعاء': <String>['الأربعاء'],
        'الان': <String>['الآن'],
        'الأن': <String>['الآن'],
        'الاف': <String>['آلاف'],
        'الاية': <String>['الآية'],
        'الاداب': <String>['الآداب'],
        'الاثار': <String>['الآثار'],
        'الالات': <String>['الآلات'],
        'الاراء': <String>['الآراء'],
        'الاخرين': <String>['الآخرين'],
        'الاخرون': <String>['الآخرون'],
        'الاباء': <String>['الآباء'],
        'الامال': <String>['الآمال'],
        'إبنه': <String>['ابنه'],
        'إبنها': <String>['ابنها'],
        'إبني': <String>['ابني'],
        'إبنك': <String>['ابنك'],
        'إبنهم': <String>['ابنهم'],
        'إبنته': <String>['ابنته'],
        'الإبن': <String>['الابن'],
        'الأبن': <String>['الابن'],
        'الإبنة': <String>['الابنة'],
        'الأبنة': <String>['الابنة'],
        'إسمي': <String>['اسمي'],
        'إسمك': <String>['اسمك'],
        'إسمهم': <String>['اسمهم'],
        'الإسم': <String>['الاسم'],
        'الأسم': <String>['الاسم'],
        'إثنا': <String>['اثنا'],
        'إثنتا': <String>['اثنتا'],
        'إثنتي': <String>['اثنتي'],
        'أثنان': <String>['اثنان'],
        'أثنين': <String>['اثنين'],
        'الأثنين': <String>['الاثنين'],
        'أمرأة': <String>['امرأة'],
        'إمرأته': <String>['امرأته'],
        'أمرأته': <String>['امرأته'],
        'أقتصاد': <String>['اقتصاد'],
        'الأقتصاد': <String>['الاقتصاد'],
        'الأقتصادية': <String>['الاقتصادية'],
        'أجتماع': <String>['اجتماع'],
        'الأجتماع': <String>['الاجتماع'],
        'الأجتماعية': <String>['الاجتماعية'],
        'أنتخابات': <String>['انتخابات'],
        'الأنتخابات': <String>['الانتخابات'],
        'أستخدام': <String>['استخدام'],
        'الأستخدام': <String>['الاستخدام'],
        'أحتلال': <String>['احتلال'],
        'الأحتلال': <String>['الاحتلال'],
        'أستقلال': <String>['استقلال'],
        'الأستقلال': <String>['الاستقلال'],
        'أتفاق': <String>['اتفاق'],
        'الأتفاق': <String>['الاتفاق'],
        'أتفاقية': <String>['اتفاقية'],
        'الأتفاقية': <String>['الاتفاقية'],
        'أختيار': <String>['اختيار'],
        'الأختيار': <String>['الاختيار'],
        'أنتشار': <String>['انتشار'],
        'أنتظار': <String>['انتظار'],
        'الأنتظار': <String>['الانتظار'],
        'أبتدائي': <String>['ابتدائي'],
        'أبتدائية': <String>['ابتدائية'],
        'الأبتدائية': <String>['الابتدائية'],
        'أمتحان': <String>['امتحان'],
        'الأمتحان': <String>['الامتحان'],
        'أستثمار': <String>['استثمار'],
        'الأستثمار': <String>['الاستثمار'],
        'أستقرار': <String>['استقرار'],
        'الأستقرار': <String>['الاستقرار'],
        'أتصال': <String>['اتصال'],
        'الأتصال': <String>['الاتصال'],
        'أتصالات': <String>['اتصالات'],
        'الأتصالات': <String>['الاتصالات'],
        'أهتمام': <String>['اهتمام'],
        'الأهتمام': <String>['الاهتمام'],
        'أعتماد': <String>['اعتماد'],
        'الأعتماد': <String>['الاعتماد'],
        'أنتقال': <String>['انتقال'],
        'الأنتقال': <String>['الانتقال'],
        'أستمرار': <String>['استمرار'],
        'الأستمرار': <String>['الاستمرار'],
        'إنتظر': <String>['انتظر'],
        'إنتظرت': <String>['انتظرت'],
        'إنتشر': <String>['انتشر'],
        'إنتشرت': <String>['انتشرت'],
        'إنتخب': <String>['انتخب'],
        'إنتخبت': <String>['انتخبت'],
        'إنطلق': <String>['انطلق'],
        'إنطلقت': <String>['انطلقت'],
        'إنسحب': <String>['انسحب'],
        'إنسحبت': <String>['انسحبت'],
        'إنضم': <String>['انضم'],
        'إنضمت': <String>['انضمت'],
        'إنفجر': <String>['انفجر'],
        'إنفجرت': <String>['انفجرت'],
        'إنهار': <String>['انهار'],
        'إنهارت': <String>['انهارت'],
        'إنقطع': <String>['انقطع'],
        'إنقطعت': <String>['انقطعت'],
        'إنتصر': <String>['انتصر'],
        'إنتصرت': <String>['انتصرت'],
        'إنتقد': <String>['انتقد'],
        'إنعقد': <String>['انعقد'],
        'إنعقدت': <String>['انعقدت'],
        'إنفصل': <String>['انفصل'],
        'إنفصلت': <String>['انفصلت'],
        'إنقسم': <String>['انقسم'],
        'إنقسمت': <String>['انقسمت'],
        'إنتمى': <String>['انتمى'],
        'إحتل': <String>['احتل'],
        'إحتلت': <String>['احتلت'],
        'إحتفل': <String>['احتفل'],
        'إحتفلت': <String>['احتفلت'],
        'إحتاج': <String>['احتاج'],
        'إحترق': <String>['احترق'],
        'إعترف': <String>['اعترف'],
        'إعترفت': <String>['اعترفت'],
        'إعتمد': <String>['اعتمد'],
        'إعتمدت': <String>['اعتمدت'],
        'إعتقد': <String>['اعتقد'],
        'إعتبرت': <String>['اعتبرت'],
        'إقترح': <String>['اقترح'],
        'إقترحت': <String>['اقترحت'],
        'إكتشف': <String>['اكتشف'],
        'إكتشفت': <String>['اكتشفت'],
        'إختار': <String>['اختار'],
        'إختارت': <String>['اختارت'],
        'إختلف': <String>['اختلف'],
        'إختلفت': <String>['اختلفت'],
        'إختفى': <String>['اختفى'],
        'إرتفع': <String>['ارتفع'],
        'إرتفعت': <String>['ارتفعت'],
        'إشترك': <String>['اشترك'],
        'إشتركت': <String>['اشتركت'],
        'إشترى': <String>['اشترى'],
        'إشترت': <String>['اشترت'],
        'إشتهر': <String>['اشتهر'],
        'إشتهرت': <String>['اشتهرت'],
        'إضطر': <String>['اضطر'],
        'إضطرت': <String>['اضطرت'],
        'إقتصر': <String>['اقتصر'],
        'إلتقى': <String>['التقى'],
        'إلتقت': <String>['التقت'],
        'إلتزم': <String>['التزم'],
        'إلتزمت': <String>['التزمت'],
        'إمتد': <String>['امتد'],
        'إمتدت': <String>['امتدت'],
        'إمتلك': <String>['امتلك'],
        'إزداد': <String>['ازداد'],
        'إزدادت': <String>['ازدادت'],
        'إبتسم': <String>['ابتسم'],
        'إبتعد': <String>['ابتعد'],
        'إبتكر': <String>['ابتكر'],
        'إتخذ': <String>['اتخذ'],
        'إتخذت': <String>['اتخذت'],
        'إتفق': <String>['اتفق'],
        'إتفقت': <String>['اتفقت'],
        'إتصل': <String>['اتصل'],
        'إتصلت': <String>['اتصلت'],
        'إتجه': <String>['اتجه'],
        'إتجهت': <String>['اتجهت'],
        'إتهم': <String>['اتهم'],
        'إتهمت': <String>['اتهمت'],
        'إستقر': <String>['استقر'],
        'إستقرت': <String>['استقرت'],
        'إستعمل': <String>['استعمل'],
        'إستخدمت': <String>['استخدمت'],
        'إستولى': <String>['استولى'],
        'إستقبل': <String>['استقبل'],
        'إستقبلت': <String>['استقبلت'],
        'إستمع': <String>['استمع'],
        'إستسلم': <String>['استسلم'],
        'إستعاد': <String>['استعاد'],
        'إستعادت': <String>['استعادت'],
        'إستغرق': <String>['استغرق'],
        'إستفاد': <String>['استفاد'],
        'إستهدف': <String>['استهدف'],
        'إستمروا': <String>['استمروا'],
        'إيضا': <String>['أيضا'],
        'ايظا': <String>['أيضا'],
        'أيظا': <String>['أيضا'],
        'إيظا': <String>['أيضا'],
        'إستاذ': <String>['أستاذ'],
        'الإستاذ': <String>['الأستاذ'],
        'أسلام': <String>['إسلام'],
        'الأسلام': <String>['الإسلام'],
        'أسلامي': <String>['إسلامي'],
        'الأسلامي': <String>['الإسلامي'],
        'أسلامية': <String>['إسلامية'],
        'الأسلامية': <String>['الإسلامية'],
        'أنتاج': <String>['إنتاج'],
        'الأنتاج': <String>['الإنتاج'],
        'أدارة': <String>['إدارة'],
        'الأدارة': <String>['الإدارة'],
        'أنسان': <String>['إنسان'],
        'الأنسان': <String>['الإنسان'],
        'أمكانية': <String>['إمكانية'],
        'الأمكانية': <String>['الإمكانية'],
        'أمكانيات': <String>['إمكانيات'],
        'الأمكانيات': <String>['الإمكانيات'],
        'أنجاز': <String>['إنجاز'],
        'أنجازات': <String>['إنجازات'],
        'أصلاح': <String>['إصلاح'],
        'الأصلاح': <String>['الإصلاح'],
        'أضافة': <String>['إضافة'],
        'الأضافة': <String>['الإضافة'],
        'أضافي': <String>['إضافي'],
        'أضافية': <String>['إضافية'],
        'الأضافية': <String>['الإضافية'],
        'أشارة': <String>['إشارة'],
        'الأشارة': <String>['الإشارة'],
        'أعلان': <String>['إعلان'],
        'الأعلان': <String>['الإعلان'],
        'أنشاء': <String>['إنشاء', 'أنشأ'],
        'الأنشاء': <String>['الإنشاء'],
        'أجابة': <String>['إجابة'],
        'الأجابة': <String>['الإجابة'],
        'أعادة': <String>['إعادة'],
        'الأعادة': <String>['الإعادة'],
        'أقامة': <String>['إقامة'],
        'الأقامة': <String>['الإقامة'],
        'أرسال': <String>['إرسال'],
        'الأرسال': <String>['الإرسال'],
        'أطلاق': <String>['إطلاق'],
        'الأطلاق': <String>['الإطلاق'],
        'ألغاء': <String>['إلغاء'],
        'الألغاء': <String>['الإلغاء'],
        'أيجاد': <String>['إيجاد'],
        'أحصاء': <String>['إحصاء'],
        'الأحصاء': <String>['الإحصاء'],
        'أسرائيل': <String>['إسرائيل'],
        'أيران': <String>['إيران'],
        'أيطاليا': <String>['إيطاليا'],
        'أسبانيا': <String>['إسبانيا'],
        'أبراهيم': <String>['إبراهيم'],
        'أسماعيل': <String>['إسماعيل'],
        'أنجلترا': <String>['إنجلترا'],
        'أندونيسيا': <String>['إندونيسيا'],
        'أنجليزي': <String>['إنجليزي'],
        'أنجليزية': <String>['إنجليزية'],
        'الأنجليزية': <String>['الإنجليزية'],
        'إحمد': <String>['أحمد'],
        'إسامة': <String>['أسامة'],
        'إكثر': <String>['أكثر'],
        'إفضل': <String>['أفضل'],
        'إكبر': <String>['أكبر'],
        'إول': <String>['أول'],
        'إخرى': <String>['أخرى'],
        'إيام': <String>['أيام'],
        'إحد': <String>['أحد'],
        'إصبح': <String>['أصبح'],
        'إعلن': <String>['أعلن'],
        'إين': <String>['أين'],
        'إو': <String>['أو'],
        'هذة': <String>['هذه'],
        'هاذة': <String>['هذه'],
        'عندة': <String>['عنده'],
        'نفسة': <String>['نفسه'],
        'ذاتة': <String>['ذاته'],
        'كأنة': <String>['كأنه'],
        'لأنة': <String>['لأنه'],
        'وجة': <String>['وجه'],
        'اتجاة': <String>['اتجاه'],
        'الاتجاة': <String>['الاتجاه'],
        'انتباة': <String>['انتباه'],
        'الانتباة': <String>['الانتباه'],
        'اشتباة': <String>['اشتباه'],
        'مياة': <String>['مياه'],
        'المياة': <String>['المياه'],
        'توجية': <String>['توجيه'],
        'التوجية': <String>['التوجيه'],
        'تنبية': <String>['تنبيه'],
        'تشبية': <String>['تشبيه'],
        'ترفية': <String>['ترفيه'],
        'الترفية': <String>['الترفيه'],
        'فقية': <String>['فقيه'],
        'الفقة': <String>['الفقه'],
        'شبية': <String>['شبيه'],
        'وجية': <String>['وجيه'],
        'نزية': <String>['نزيه'],
        'تافة': <String>['تافه'],
        'يواجة': <String>['يواجه'],
        'تواجة': <String>['تواجه'],
        'يشبة': <String>['يشبه'],
        'تشبة': <String>['تشبه'],
        'انتبة': <String>['انتبه'],
        'دكتوراة': <String>['دكتوراه'],
        'الدكتوراة': <String>['الدكتوراه'],
        'التوراه': <String>['التوراة'],
        'ضلم': <String>['ظلم'],
        'الضلم': <String>['الظلم'],
        'ضالم': <String>['ظالم'],
        'الضالم': <String>['الظالم'],
        'ضهر': <String>['ظهر'],
        'ضاهرة': <String>['ظاهرة'],
        'الضاهرة': <String>['الظاهرة'],
        'نضام': <String>['نظام'],
        'النضام': <String>['النظام'],
        'تنضيم': <String>['تنظيم'],
        'التنضيم': <String>['التنظيم'],
        'محافضة': <String>['محافظة'],
        'المحافضة': <String>['المحافظة'],
        'لحضة': <String>['لحظة'],
        'اللحضة': <String>['اللحظة'],
        'ملاحضة': <String>['ملاحظة'],
        'الملاحضة': <String>['الملاحظة'],
        'ملحوض': <String>['ملحوظ'],
        'عضيم': <String>['عظيم'],
        'عضيمة': <String>['عظيمة'],
        'العضيم': <String>['العظيم'],
        'يضهر': <String>['يظهر'],
        'تضهر': <String>['تظهر'],
        'مضاهرة': <String>['مظاهرة'],
        'المضاهرة': <String>['المظاهرة'],
        'مضهر': <String>['مظهر'],
        'المضهر': <String>['المظهر'],
        'انتضر': <String>['انتظر'],
        'ينتضر': <String>['ينتظر'],
        'تنتضر': <String>['تنتظر'],
        'ظابط': <String>['ضابط'],
        'الظابط': <String>['الضابط'],
        'ظروري': <String>['ضروري'],
        'الظروري': <String>['الضروري'],
        'ظرورة': <String>['ضرورة'],
        'الظرورة': <String>['الضرورة'],
        'ظعيف': <String>['ضعيف'],
        'الظعيف': <String>['الضعيف'],
        'مظبوط': <String>['مضبوط'],
        'ظمير': <String>['ضمير'],
        'الظمير': <String>['الضمير'],
        'ظوء': <String>['ضوء'],
        'الظوء': <String>['الضوء'],
        'مريظ': <String>['مريض'],
        'المريظ': <String>['المريض'],
        'رياظة': <String>['رياضة'],
        'الرياظة': <String>['الرياضة'],
        'الأرظ': <String>['الأرض'],
        'بغظ': <String>['بغض'],
        'اللذي': <String>['الذي'],
        'اللتي': <String>['التي'],
        'إلاه': <String>['إله'],
        'الإلاه': <String>['الإله'],
        'اولائك': <String>['أولئك'],
        'أولائك': <String>['أولئك'],
        'لاكنهم': <String>['لكنهم'],
        'لاكنك': <String>['لكنك'],
        'هكذى': <String>['هكذا'],
        'لاسيما': <String>['لا سيما'],
        'إنشاءالله': <String>['إن شاء الله'],
        'انشاءالله': <String>['إن شاء الله'],
        'الحمدلله': <String>['الحمد لله'],
        'الحمدالله': <String>['الحمد لله'],
        'جزاكالله': <String>['جزاك الله'],
        'سبحانالله': <String>['سبحان الله'],
        'بإذنالله': <String>['بإذن الله'],
        'لاشك': <String>['لا شك'],
        'لابد': <String>['لا بد'],
        'لاشيء': <String>['لا شيء'],
        'بلاشك': <String>['بلا شك'],
        'مالم': <String>['ما لم'],
        'مابين': <String>['ما بين'],
        'مابعد': <String>['ما بعد'],
        'ماقبل': <String>['ما قبل'],
        'مازال': <String>['ما زال'],
        'مازالت': <String>['ما زالت'],
        'مازالوا': <String>['ما زالوا'],
        'ماتزال': <String>['ما تزال'],
        'مايزال': <String>['ما يزال'],
        'مادام': <String>['ما دام'],
        'مادامت': <String>['ما دامت'],
        'ماهو': <String>['ما هو'],
        'ماهي': <String>['ما هي'],
        'لايوجد': <String>['لا يوجد'],
        'لاتوجد': <String>['لا توجد'],
        'لايمكن': <String>['لا يمكن'],
        'لايزال': <String>['لا يزال'],
        'لاتزال': <String>['لا تزال'],
        'لايجوز': <String>['لا يجوز'],
        'لايكون': <String>['لا يكون'],
        'لاتكون': <String>['لا تكون'],
        'أبوظبي': <String>['أبو ظبي'],
        'ابوظبي': <String>['أبو ظبي'],
        'هلمجرا': <String>['هلم جرا'],
        'قالو': <String>['قالوا'],
        'ذهبو': <String>['ذهبوا'],
        'قامو': <String>['قاموا'],
        'أصبحو': <String>['أصبحوا'],
        'عملو': <String>['عملوا'],
        'رجعو': <String>['رجعوا'],
        'يكونو': <String>['يكونوا'],
        'تكونو': <String>['تكونوا'],
        'يقولو': <String>['يقولوا'],
        'نرجوا': <String>['نرجو'],
        'أرجوا': <String>['أرجو'],
        'ارجوا': <String>['أرجو'],
        'ندعوا': <String>['ندعو'],
        'أدعوا': <String>['أدعو'],
        'نشكوا': <String>['نشكو'],
        'أشكوا': <String>['أشكو'],
      };

  /// Colloquial words that have no Standard Arabic homograph (authored).
  static const Map<String, List<String>> _colloquial = <String, List<String>>{
    'عشان': <String>['لأن', 'من أجل'],
    'علشان': <String>['لأن', 'من أجل'],
    'ليش': <String>['لماذا'],
    'شلون': <String>['كيف'],
    'ازاي': <String>['كيف'],
    'إزاي': <String>['كيف'],
    'كيفاش': <String>['كيف'],
    'هيك': <String>['هكذا'],
    'كده': <String>['هكذا'],
    'هلق': <String>['الآن'],
    'هلأ': <String>['الآن'],
    'دلوقتي': <String>['الآن'],
    'دلوقت': <String>['الآن'],
    'هسه': <String>['الآن'],
    'ايش': <String>['ماذا', 'ما'],
    'إيش': <String>['ماذا', 'ما'],
    'شنو': <String>['ماذا', 'ما'],
    'مفيش': <String>['لا يوجد'],
    'مافيش': <String>['لا يوجد'],
    'برضو': <String>['أيضًا'],
    'برضه': <String>['أيضًا'],
    'اللي': <String>['الذي', 'التي', 'الذين'],
    'امبارح': <String>['أمس'],
    'إمبارح': <String>['أمس'],
    'منيح': <String>['جيد'],
    'كويس': <String>['جيد'],
    'كويسة': <String>['جيدة'],
    'هيدا': <String>['هذا'],
    'بزاف': <String>['كثيرًا'],
    'وايد': <String>['كثيرًا'],
    'علاش': <String>['لماذا'],
    'شحال': <String>['كم'],
    'مش': <String>['ليس', 'غير'],
    'بدي': <String>['أريد'],
    'بتاع': <String>[],
    'بتاعة': <String>[],
    'عايز': <String>['أريد', 'يريد'],
    'عايزة': <String>['أريد', 'تريد'],
    'عاوز': <String>['أريد', 'يريد'],
    'عاوزة': <String>['أريد', 'تريد'],
    'عايزين': <String>['نريد', 'يريدون'],
    'عاوزين': <String>['نريد', 'يريدون'],
    'لسه': <String>['ما زال', 'بعد'],
    'لسا': <String>['ما زال', 'بعد'],
    'امتى': <String>['متى'],
    'إمتى': <String>['متى'],
    'إيمتى': <String>['متى'],
    'منين': <String>['من أين'],
    'إزيك': <String>['كيف حالك'],
    'ازاى': <String>['كيف'],
    'إزاى': <String>['كيف'],
    'شوية': <String>['قليلًا'],
    'بتاعي': <String>[],
    'بتاعك': <String>[],
    'بتاعه': <String>[],
    'بتاعها': <String>[],
    'بتوع': <String>[],
    'إحنا': <String>['نحن'],
    'احنا': <String>['نحن'],
    'إنتو': <String>['أنتم'],
    'انتو': <String>['أنتم'],
    'إنتي': <String>['أنت'],
    'انتي': <String>['أنت'],
    'بقولك': <String>['أقول لك'],
    'ياريت': <String>['ليت'],
    'النهارده': <String>['اليوم'],
    'النهاردة': <String>['اليوم'],
    'نهارده': <String>['اليوم'],
    'دلوقتى': <String>['الآن'],
    'تاني': <String>['ثانٍ', 'مرة أخرى'],
    'كتير': <String>['كثير'],
    'كتيرة': <String>['كثيرة'],
    'تلاتة': <String>['ثلاثة'],
    'تلات': <String>['ثلاث'],
    'تمانية': <String>['ثمانية'],
    'ايوه': <String>['نعم'],
    'أيوه': <String>['نعم'],
    'أيوة': <String>['نعم'],
    'ايوة': <String>['نعم'],
    'لأ': <String>['لا'],
    'معلش': <String>['لا بأس'],
    'معلهش': <String>['لا بأس'],
    'ياللا': <String>['هيا'],
    'لوين': <String>['إلى أين'],
    'كيفك': <String>['كيف حالك'],
    'منشان': <String>['من أجل'],
    'مشان': <String>['من أجل'],
    'كرمال': <String>['من أجل'],
    'هونيك': <String>['هناك'],
    'هلقد': <String>['هكذا'],
    'هالقد': <String>['هكذا'],
    'عنجد': <String>['حقًّا'],
    'أديش': <String>['كم'],
    'اديش': <String>['كم'],
    'قديش': <String>['كم'],
    'زلمة': <String>['رجل'],
    'هيدول': <String>['هؤلاء'],
    'بدك': <String>['تريد'],
    'شنهو': <String>['ما هو'],
    'شنهي': <String>['ما هي'],
    'اشنو': <String>['ماذا'],
    'هسع': <String>['الآن'],
    'هسة': <String>['الآن'],
    'اكو': <String>['يوجد'],
    'ماكو': <String>['لا يوجد'],
    'يبي': <String>['يريد'],
    'تبي': <String>['تريد'],
    'دحين': <String>['الآن'],
    'هالحين': <String>['الآن'],
    'هذول': <String>['هؤلاء'],
    'هذولا': <String>['هؤلاء'],
    'ديال': <String>[],
    'ديالي': <String>[],
    'ديالك': <String>[],
    'مزيان': <String>['جيد', 'جميل'],
    'مزيانة': <String>['جيدة', 'جميلة'],
    'والو': <String>['لا شيء'],
    'هادشي': <String>['هذا'],
    'داكشي': <String>['ذلك'],
    'بلاصة': <String>['مكان'],
    'دروك': <String>['الآن'],
    'برشة': <String>['كثيرًا'],
    'شنية': <String>['ماذا'],
    'شنوة': <String>['ماذا'],
    'كيفاه': <String>['كيف'],
    'وقتاش': <String>['متى'],
    'لحالو': <String>['وحده'],
    'مبلا': <String>['بلى'],
    'شايف': <String>['ترى', 'أرى'],
    'شايفة': <String>['ترين', 'أرى'],
    'مبارح': <String>['أمس'],
    'شفيك': <String>['ما بك'],
    'كلش': <String>['جدًّا'],
    'شكد': <String>['كم'],
    'اشلون': <String>['كيف'],
    'إشلون': <String>['كيف'],
    'بيقول': <String>['يقول'],
    'بتقول': <String>['تقول'],
    'بيعمل': <String>['يعمل'],
    'بيعرف': <String>['يعرف'],
    'هيروح': <String>['سيذهب'],
    'هيكون': <String>['سيكون'],
    'معايا': <String>['معي'],
    'معاك': <String>['معك'],
    'منيحة': <String>['جيدة'],
    'هادا': <String>['هذا'],
    'بس': <String>['لكن', 'فقط'],
  };

  /// Unassimilated loanwords with an established Arabic equivalent.
  static const Map<String, List<String>> _loanwords = <String, List<String>>{
    'أوكي': <String>['حسنًا', 'موافق'],
    'اوكي': <String>['حسنًا', 'موافق'],
    'ميرسي': <String>['شكرًا'],
    'إيميل': <String>['بريد إلكتروني'],
    'ايميل': <String>['بريد إلكتروني'],
    'الإيميل': <String>['البريد الإلكتروني'],
    'الايميل': <String>['البريد الإلكتروني'],
    'موبايل': <String>['هاتف محمول'],
    'الموبايل': <String>['الهاتف المحمول'],
    'سيستم': <String>['نظام'],
    'السيستم': <String>['النظام'],
    'بروجكت': <String>['مشروع'],
    'بروجيكت': <String>['مشروع'],
    'ميتينغ': <String>['اجتماع'],
    'ميتنج': <String>['اجتماع'],
    'داونلود': <String>['تنزيل'],
    'أونلاين': <String>['عبر الإنترنت'],
    'اونلاين': <String>['عبر الإنترنت'],
    'لابتوب': <String>['حاسوب محمول'],
    'اللابتوب': <String>['الحاسوب المحمول'],
    'كمبيوتر': <String>['حاسوب'],
    'الكمبيوتر': <String>['الحاسوب'],
    'تليفون': <String>['هاتف'],
    'التليفون': <String>['الهاتف'],
    'باص': <String>['حافلة'],
    'الباص': <String>['الحافلة'],
    'تاكسي': <String>['سيارة أجرة'],
    'فيديو': <String>['مقطع مرئي'],
    'الفيديو': <String>['المقطع المرئي'],
    'كاميرا': <String>['آلة تصوير'],
    'الكاميرا': <String>['آلة التصوير'],
    'راديو': <String>['مذياع'],
    'الراديو': <String>['المذياع'],
    'تلفون': <String>['هاتف'],
    'التلفون': <String>['الهاتف'],
    'تلفزيون': <String>['تلفاز'],
    'التلفزيون': <String>['التلفاز'],
    'تليفزيون': <String>['تلفاز'],
    'التليفزيون': <String>['التلفاز'],
    'كومبيوتر': <String>['حاسوب'],
    'الكومبيوتر': <String>['الحاسوب'],
    'ميكروفون': <String>['مكبر صوت', 'لاقط صوت'],
    'الميكروفون': <String>['مكبر الصوت', 'لاقط الصوت'],
    'سندويتش': <String>['شطيرة'],
    'ساندويتش': <String>['شطيرة'],
    'السندويتش': <String>['الشطيرة'],
    'بنطلون': <String>['سروال'],
    'البنطلون': <String>['السروال'],
    'جاكيت': <String>['سترة'],
    'الجاكيت': <String>['السترة'],
    'شامبو': <String>['غسول الشعر'],
    'كافيه': <String>['مقهى'],
    'الكافيه': <String>['المقهى'],
    'ريموت': <String>['جهاز التحكم'],
    'موتور': <String>['محرك'],
    'الموتور': <String>['المحرك'],
    'التاكسي': <String>['سيارة الأجرة'],
    'أوتوبيس': <String>['حافلة'],
    'اوتوبيس': <String>['حافلة'],
    'الأوتوبيس': <String>['الحافلة'],
    'ماتش': <String>['مباراة'],
    'الماتش': <String>['المباراة'],
    'كابتن': <String>['قائد'],
    'الكابتن': <String>['القائد'],
    'السوبرماركت': <String>['المتجر'],
    'سوبرماركت': <String>['متجر'],
    'كومنت': <String>['تعليق'],
    'كومنتات': <String>['تعليقات'],
    'تويت': <String>['تغريدة'],
    'هاشتاج': <String>['وسم'],
    'هاشتاغ': <String>['وسم'],
    'الهاشتاج': <String>['الوسم'],
    'الهاشتاغ': <String>['الوسم'],
    'باسوورد': <String>['كلمة المرور'],
    'باسورد': <String>['كلمة المرور'],
    'يوزر': <String>['مستخدم'],
    'لوجو': <String>['شعار'],
    'لوغو': <String>['شعار'],
    'اللوجو': <String>['الشعار'],
    'اللوغو': <String>['الشعار'],
    'لينك': <String>['رابط'],
    'اللينك': <String>['الرابط'],
    'أبلود': <String>['رفع'],
    'ابلود': <String>['رفع'],
    'سيرفر': <String>['خادم'],
    'السيرفر': <String>['الخادم'],
    'سوفتوير': <String>['برمجيات'],
    'هاردوير': <String>['عتاد'],
    'أبليكيشن': <String>['تطبيق'],
    'ابليكيشن': <String>['تطبيق'],
    'ماوس': <String>['فأرة'],
    'الماوس': <String>['الفأرة'],
    'كيبورد': <String>['لوحة مفاتيح'],
    'الكيبورد': <String>['لوحة المفاتيح'],
    'سكانر': <String>['ماسح ضوئي'],
    'برنتر': <String>['طابعة'],
    'البرنتر': <String>['الطابعة'],
    'فايل': <String>['ملف'],
    'الفايل': <String>['الملف'],
    'فولدر': <String>['مجلد'],
    'الفولدر': <String>['المجلد'],
    'ميديا': <String>['إعلام', 'وسائط'],
    'الميديا': <String>['الإعلام', 'الوسائط'],
    'تابلت': <String>['حاسوب لوحي'],
    'فيزا': <String>['تأشيرة'],
    'الفيزا': <String>['التأشيرة'],
    'باسبور': <String>['جواز سفر'],
    'باسبورت': <String>['جواز سفر'],
    'أوتيل': <String>['فندق'],
    'اوتيل': <String>['فندق'],
    'الأوتيل': <String>['الفندق'],
    'الاوتيل': <String>['الفندق'],
    'ريسبشن': <String>['استقبال'],
    'منيو': <String>['قائمة الطعام'],
    'المنيو': <String>['قائمة الطعام'],
    'شيف': <String>['طاهٍ', 'رئيس الطهاة'],
    'الشيف': <String>['الطاهي'],
    'جاتوه': <String>['كعكة'],
    'بروفيسور': <String>['أستاذ'],
    'بروفسور': <String>['أستاذ'],
    'البروفيسور': <String>['الأستاذ'],
    'سكرتير': <String>['أمين سر'],
    'سكرتيرة': <String>['أمينة سر'],
    'بيزنس': <String>['أعمال'],
    'بزنس': <String>['أعمال'],
    'ماركة': <String>['علامة تجارية'],
    'الماركة': <String>['العلامة التجارية'],
    'ستايل': <String>['أسلوب', 'طراز'],
    'موديل': <String>['طراز'],
    'الموديل': <String>['الطراز'],
    'بلكونة': <String>['شرفة'],
    'البلكونة': <String>['الشرفة'],
    'أسانسير': <String>['مصعد'],
    'اسانسير': <String>['مصعد'],
    'الأسانسير': <String>['المصعد'],
    'كوبري': <String>['جسر'],
    'الكوبري': <String>['الجسر'],
    'جراج': <String>['مرآب'],
    'كراج': <String>['مرآب'],
    'الجراج': <String>['المرآب'],
    'الكراج': <String>['المرآب'],
    'تيكيت': <String>['تذكرة'],
    'كاش': <String>['نقدًا'],
    'الكاش': <String>['النقد'],
    'كارت': <String>['بطاقة'],
    'الكارت': <String>['البطاقة'],
    'كوبون': <String>['قسيمة'],
    'بروشور': <String>['نشرة'],
    'كتالوج': <String>['دليل'],
    'الكتالوج': <String>['الدليل'],
    'كونسرت': <String>['حفلة موسيقية'],
    'ميوزك': <String>['موسيقى'],
    'ترند': <String>['رائج'],
    'تريند': <String>['رائج'],
    'أوفلاين': <String>['دون اتصال'],
    'اوفلاين': <String>['دون اتصال'],
    'ويكند': <String>['عطلة نهاية الأسبوع'],
    'الويكند': <String>['عطلة نهاية الأسبوع'],
    'ديدلاين': <String>['موعد نهائي'],
    'بريك': <String>['استراحة'],
    'تيست': <String>['اختبار'],
    'كورس': <String>['دورة'],
    'الكورس': <String>['الدورة'],
    'سيمينار': <String>['ندوة'],
    'تارجت': <String>['هدف'],
    'فيدباك': <String>['تغذية راجعة'],
    'أوكيه': <String>['حسنًا', 'موافق'],
    'اوكيه': <String>['حسنًا', 'موافق'],
    'ثانكس': <String>['شكرًا'],
    'ثانكيو': <String>['شكرًا'],
    'شوبينغ': <String>['تسوق'],
    'شوبنج': <String>['تسوق'],
    'شات': <String>['دردشة'],
    'الشات': <String>['الدردشة'],
    'إيميلات': <String>['رسائل إلكترونية'],
    'ايميلات': <String>['رسائل إلكترونية'],
    'فلاشة': <String>['ذاكرة محمولة'],
    'ديسكتوب': <String>['حاسوب مكتبي'],
    'أكشن': <String>['إثارة'],
    'فاميلي': <String>['عائلة'],
    'جروب': <String>['مجموعة'],
    'الجروب': <String>['المجموعة'],
    'بارتي': <String>['حفلة'],
    'سبونسر': <String>['راعٍ'],
    'ماركتينج': <String>['تسويق'],
    'ماركتنج': <String>['تسويق'],
    'سيلز': <String>['مبيعات'],
    'مانجر': <String>['مدير'],
    'مانيجر': <String>['مدير'],
    'إنترفيو': <String>['مقابلة'],
    'انترفيو': <String>['مقابلة'],
    'كاريير': <String>['مسيرة مهنية'],
    'باكيت': <String>['علبة'],
    'شنطة': <String>['حقيبة'],
    'الشنطة': <String>['الحقيبة'],
    'كنبة': <String>['أريكة'],
    'الكنبة': <String>['الأريكة'],
    'ترابيزة': <String>['طاولة', 'منضدة'],
    'طرابيزة': <String>['طاولة', 'منضدة'],
    'أباجورة': <String>['مصباح'],
    'تواليت': <String>['مرحاض', 'دورة مياه'],
    'بيجاما': <String>['منامة'],
    'كرافتة': <String>['ربطة عنق'],
    'بارفان': <String>['عطر'],
    'برفان': <String>['عطر'],
    'ماكينة': <String>['آلة'],
    'الماكينة': <String>['الآلة'],
    'أوتوماتيك': <String>['آلي', 'تلقائي'],
    'اوتوماتيك': <String>['آلي', 'تلقائي'],
    'أوتوماتيكي': <String>['آلي', 'تلقائي'],
    'أوتوماتيكيا': <String>['تلقائيًّا'],
    'تكنيك': <String>['تقنية'],
    'ستاند': <String>['منصة', 'حامل'],
    'كونترول': <String>['تحكم'],
    'سيكيوريتي': <String>['أمن'],
    'روتين': <String>['رتابة'],
  };

  /// Single words whose use a strict standard considers a misuse.
  static const Map<String, List<String>> _usageWords = <String, List<String>>{
    'سويا': <String>['معًا'],
    'تواجد': <String>['وُجد', 'حضر'],
    'يتواجد': <String>['يوجد'],
    'تتواجد': <String>['توجد'],
    'يتواجدون': <String>['يوجدون'],
    'التواجد': <String>['الوجود'],
    'بتواجد': <String>['بوجود'],
    'متواجد': <String>['موجود'],
    'متواجدة': <String>['موجودة'],
    'متواجدون': <String>['موجودون'],
    'متواجدين': <String>['موجودين'],
    'المتواجدون': <String>['الموجودون'],
    'المتواجدين': <String>['الموجودين'],
    'مبروك': <String>['مبارك'],
    'ساهم': <String>['أسهم'],
    'ساهمت': <String>['أسهمت'],
    'ساهموا': <String>['أسهموا'],
    'يساهم': <String>['يسهم'],
    'تساهم': <String>['تسهم'],
    'يساهمون': <String>['يسهمون'],
    'هام': <String>['مهم'],
    'هامة': <String>['مهمة'],
    'الهام': <String>['المهم'],
    'الهامة': <String>['المهمة'],
    'مدراء': <String>['مديرون', 'مديرين'],
    'المدراء': <String>['المديرون', 'المديرين'],
    'لوحده': <String>['وحده'],
    'لوحدها': <String>['وحدها'],
    'لوحدهم': <String>['وحدهم'],
    'لوحدي': <String>['وحدي'],
    'لوحدك': <String>['وحدك'],
    'لوحدنا': <String>['وحدنا'],
    'أخصائي': <String>['اختصاصي'],
    'الأخصائي': <String>['الاختصاصي'],
    'أخصائية': <String>['اختصاصية'],
    'أخصائيون': <String>['اختصاصيون'],
    'أخصائيين': <String>['اختصاصيين'],
    'الأخصائيين': <String>['الاختصاصيين'],
    'إخصائي': <String>['اختصاصي'],
    'مصداقية': <String>['صدقية'],
    'المصداقية': <String>['الصدقية'],
    'استلم': <String>['تسلّم'],
    'استلمت': <String>['تسلّمت'],
    'استلموا': <String>['تسلّموا'],
    'يستلم': <String>['يتسلّم'],
    'تستلم': <String>['تتسلّم'],
    'يستلمون': <String>['يتسلّمون'],
    'استلام': <String>['تسلّم'],
    'الاستلام': <String>['التسلّم'],
    'باستلام': <String>['بتسلّم'],
    'احتار': <String>['حار', 'تحيّر'],
    'محتار': <String>['حائر', 'متحيّر'],
    'محتارة': <String>['حائرة', 'متحيّرة'],
    'مشاكل': <String>['مشكلات'],
    'المشاكل': <String>['المشكلات'],
    'كفوء': <String>['كفء'],
    'إمكانيات': <String>['إمكانات'],
    'الإمكانيات': <String>['الإمكانات'],
    'نوايا': <String>['نيّات'],
    'النوايا': <String>['النيّات'],
    'فعاليات': <String>['أنشطة'],
    'الفعاليات': <String>['الأنشطة'],
    'شيق': <String>['شائق'],
    'شيقة': <String>['شائقة'],
    'بالصدفة': <String>['مصادفةً'],
    'حوالي': <String>['نحو', 'قرابة'],
    'حوالى': <String>['نحو', 'قرابة'],
    'يعتبر': <String>['يُعدّ', 'يَعُدّ'],
    'تعتبر': <String>['تُعدّ', 'تَعُدّ'],
    'يعتبرون': <String>['يُعدّون', 'يَعُدّون'],
    'تعتبرون': <String>['تُعدّون', 'تَعُدّون'],
    'كالتالي': <String>['كما يلي', 'كما يأتي'],
    'بالتالي': <String>['لذلك', 'من ثم'],
    'توفر': <String>['توافر'],
    'يتوفر': <String>['يتوافر'],
    'تتوفر': <String>['تتوافر'],
    'متوفر': <String>['متوافر'],
    'متوفرة': <String>['متوافرة'],
    'المتوفرة': <String>['المتوافرة'],
    'يستأهل': <String>['يستحق'],
  };

  /// Words commonly mispronounced or ambiguous without vowels (authored).
  static const Map<String, List<String>> _vowelling = <String, List<String>>{
    'تجربة': <String>['تَجْرِبة'],
    'دعاية': <String>['دِعاية'],
    'حضارة': <String>['حَضارة'],
    'خبرة': <String>['خِبْرة'],
    'ثروة': <String>['ثَرْوة'],
    'مرونة': <String>['مُرونة'],
    'رخصة': <String>['رُخْصة'],
    'قرية': <String>['قَرْية'],
    'ثقة': <String>['ثِقة'],
    'سهولة': <String>['سُهولة'],
    'بطولة': <String>['بُطولة'],
    'شجاعة': <String>['شَجاعة'],
    'خطة': <String>['خُطّة'],
    'نخبة': <String>['نُخْبة'],
    'قدوة': <String>['قُدْوة'],
    'قصة': <String>['قِصّة'],
    'قمة': <String>['قِمّة'],
    'قطاع': <String>['قِطاع'],
    'مشكلة': <String>['مُشْكِلة'],
    'سلطة': <String>['سُلْطة', 'سَلَطة'],
    'مهارة': <String>['مَهارة'],
    'ولادة': <String>['وِلادة'],
    'وزارة': <String>['وِزارة'],
    'حماية': <String>['حِماية'],
    'رعاية': <String>['رِعاية'],
    'زراعة': <String>['زِراعة'],
    'صناعة': <String>['صِناعة'],
    'تجارة': <String>['تِجارة'],
    'كتابة': <String>['كِتابة'],
    'قراءة': <String>['قِراءة'],
    'دراسة': <String>['دِراسة'],
    'رسالة': <String>['رِسالة'],
    'هواية': <String>['هِواية'],
    'نهاية': <String>['نِهاية'],
    'بداية': <String>['بِداية'],
    'كفاءة': <String>['كَفاءة'],
    'سفارة': <String>['سِفارة'],
    'إمارة': <String>['إِمارة'],
    'خلافة': <String>['خِلافة'],
    'ضيافة': <String>['ضِيافة'],
    'قيادة': <String>['قِيادة'],
    'سياحة': <String>['سِياحة'],
    'رئاسة': <String>['رِئاسة'],
    'سياسة': <String>['سِياسة'],
    'حراسة': <String>['حِراسة'],
    'صيانة': <String>['صِيانة'],
    'عبادة': <String>['عِبادة'],
    'دقة': <String>['دِقّة'],
    'رقة': <String>['رِقّة'],
    'عزة': <String>['عِزّة'],
    'شدة': <String>['شِدّة'],
    'صحة': <String>['صِحّة'],
    'حصة': <String>['حِصّة'],
    'فكرة': <String>['فِكْرة'],
    'ذروة': <String>['ذِرْوة', 'ذُرْوة'],
    'رحلة': <String>['رِحْلة'],
    'سرعة': <String>['سُرْعة'],
    'ثقافة': <String>['ثَقافة'],
    'كرامة': <String>['كَرامة'],
    'سلامة': <String>['سَلامة'],
    'زيارة': <String>['زِيارة'],
    'ضمانة': <String>['ضَمانة'],
    'هيمنة': <String>['هَيْمَنة'],
    'دولة': <String>['دَوْلة'],
    'منحة': <String>['مِنْحة'],
    'محنة': <String>['مِحْنة'],
    'نعمة': <String>['نِعْمة'],
    'حكمة': <String>['حِكْمة'],
    'خدمة': <String>['خِدْمة'],
    'هجرة': <String>['هِجْرة'],
    'ثورة': <String>['ثَوْرة'],
    'نسبة': <String>['نِسْبة'],
    'وحدة': <String>['وَحْدة'],
    'عملة': <String>['عُمْلة'],
    'لعبة': <String>['لُعْبة'],
    'غرفة': <String>['غُرْفة'],
    'رقعة': <String>['رُقْعة'],
    'بقعة': <String>['بُقْعة'],
    'منطقة': <String>['مِنْطَقة'],
    'مكتبة': <String>['مَكْتَبة'],
    'مقبرة': <String>['مَقْبَرة'],
    'محكمة': <String>['مَحْكَمة'],
    'معركة': <String>['مَعْرَكة'],
    'مجزرة': <String>['مَجْزَرة'],
    'مرحلة': <String>['مَرْحَلة'],
    'مزرعة': <String>['مَزْرَعة'],
    'مطبعة': <String>['مَطْبَعة'],
    'مصنع': <String>['مَصْنَع'],
    'مسرح': <String>['مَسْرَح'],
    'مخزن': <String>['مَخْزَن'],
    'مرصد': <String>['مَرْصَد'],
    'منبر': <String>['مِنْبَر'],
    'مجهر': <String>['مِجْهَر'],
    'معطف': <String>['مِعْطَف'],
    'مقص': <String>['مِقَصّ'],
    'مصعد': <String>['مِصْعَد'],
    'مكنسة': <String>['مِكْنَسة'],
    'ملعقة': <String>['مِلْعَقة'],
    'مظلة': <String>['مِظَلّة'],
    'مروحة': <String>['مِرْوَحة'],
    'مقود': <String>['مِقْوَد'],
    'مسبح': <String>['مَسْبَح'],
    'بحيرة': <String>['بُحَيْرة'],
    'جزيرة': <String>['جَزيرة'],
    'خريطة': <String>['خَريطة'],
    'حكومة': <String>['حُكومة'],
    'رجولة': <String>['رُجولة'],
    'طفولة': <String>['طُفولة'],
    'أمومة': <String>['أُمومة'],
    'عضوية': <String>['عُضْوِيّة'],
    'سيرة': <String>['سِيرة'],
    'ميزة': <String>['مِيزة'],
    'حيرة': <String>['حَيْرة'],
    'بيئة': <String>['بِيئة'],
    'هيئة': <String>['هَيْئة'],
    'شريحة': <String>['شَريحة'],
    'وجبة': <String>['وَجْبة'],
    'كلية': <String>['كُلّيّة', 'كُلْيَة'],
    'عقد': <String>['عَقْد', 'عِقْد', 'عُقَد'],
    'ملك': <String>['مَلِك', 'مُلْك', 'مِلْك'],
    'نشأة': <String>['نَشْأة'],
    'دهشة': <String>['دَهْشة'],
    'زحمة': <String>['زَحْمة'],
    'بصمة': <String>['بَصْمة'],
    'قرعة': <String>['قُرْعة'],
    'هدنة': <String>['هُدْنة'],
    'غربة': <String>['غُرْبة'],
    'رغبة': <String>['رَغْبة'],
    'رهبة': <String>['رَهْبة'],
    'خطبة': <String>['خُطْبة', 'خِطْبة'],
    'شركة': <String>['شَرِكة'],
    'وهلة': <String>['وَهْلة'],
    'نزهة': <String>['نُزْهة'],
    'جرعة': <String>['جُرْعة'],
    'حقبة': <String>['حِقْبة'],
    'برهة': <String>['بُرْهة'],
    'فسحة': <String>['فُسْحة'],
    'هوية': <String>['هُوِيّة'],
    'كمية': <String>['كَمّيّة'],
    'نوعية': <String>['نَوْعِيّة'],
    'آلية': <String>['آلِيّة'],
    'أولوية': <String>['أَوْلَوِيّة'],
    'سخرية': <String>['سُخْرِيّة'],
    'حرية': <String>['حُرّيّة'],
    'رؤية': <String>['رُؤْية'],
    'ميزانية': <String>['مِيزانِيّة'],
  };

  /// Rare words that differ from a frequent word only in ض/ظ. Both are real
  /// words, so this is a verification hint; only the rarer member is
  /// flagged, because the frequent one is almost always intended.
  static const Map<String, List<String>> _dadZa = <String, List<String>>{
    'ضل': <String>['ظل'],
    'نضرة': <String>['نظرة'],
    'ناضر': <String>['ناظر'],
    'حض': <String>['حظ'],
    'ضن': <String>['ظن'],
  };

  static const String _sunLetters = 'تثدذرزسشصضطظلن';

  /// `ال` + a vowelled noun, with shadda on a sun letter.
  static String _withArticle(String vowelled) {
    if (!_sunLetters.contains(vowelled[0])) return 'ال$vowelled';
    // Shadda goes after the letter's short vowel (Unicode canonical order).
    int k = 1;
    while (k < vowelled.length &&
        RegExp('[\u064B-\u0650]').hasMatch(vowelled[k])) {
      k++;
    }
    return 'ال${vowelled.substring(0, k)}\u0651${vowelled.substring(k)}';
  }

  void _table(
    String id,
    Map<String, List<String>> table,
    String Function(String bare) message,
    OfficeProofingCategory category, {
    List<String> prefixes = const <String>['', 'و', 'ف'],
    bool article = false,
    bool unvowelledOnly = false,
  }) {
    if (!enabled(id)) return;
    for (int w = 0; w < words.length; w++) {
      final String bare = bares[w];
      if (unvowelledOnly && _hasMarks(words[w].group(0)!)) continue;
      for (final String prefix in prefixes) {
        if (!bare.startsWith(prefix)) continue;
        String core = bare.substring(prefix.length);
        bool definite = false;
        if (!table.containsKey(core) && article && core.startsWith('ال')) {
          core = core.substring(2);
          definite = true;
        }
        final List<String>? hit = table[core];
        if (hit == null) continue;
        add(
          id,
          words[w].start,
          words[w].end,
          message(core),
          category: category,
          replacements: <String>[
            for (final String r in hit)
              _keepHarakat(w, '$prefix${definite ? _withArticle(r) : r}'),
          ],
        );
        break;
      }
    }
  }

  void _tables() {
    _table(
      'ar.spelling.common',
      _commonSpelling,
      (_) => 'خطأ إملائي شائع في هذه الكلمة.',
      OfficeProofingCategory.spelling,
      prefixes: const <String>['', 'و', 'ف', 'ب', 'ل', 'ك'],
    );
    _table(
      'ar.register.colloquial',
      _colloquial,
      (_) => 'كلمة عامية؛ في الفصحى تُستعمل الكلمة المقترحة.',
      OfficeProofingCategory.style,
    );
    _table(
      'ar.register.loanword',
      _loanwords,
      (_) => 'كلمة دخيلة لها مقابل عربي مستعمل.',
      OfficeProofingCategory.style,
    );
    _table(
      'ar.usage.word',
      _usageWords,
      (_) => 'استعمال مختلف فيه؛ يُفضِّله المدققون بالصيغة المقترحة.',
      OfficeProofingCategory.style,
    );
    _table(
      'ar.hint.vowelling',
      _vowelling,
      (_) => 'كلمة يشيع الخطأ في نطقها أو تلتبس بغيرها؛ قد يفيد ضبطها بالشكل.',
      OfficeProofingCategory.style,
      prefixes: const <String>['', 'و', 'ف', 'ب', 'ك'],
      article: true,
      unvowelledOnly: true,
    );
    _table(
      'ar.hint.dad-za',
      _dadZa,
      (String core) =>
          'تحقّق من الحرف: هل المقصود «${_dadZa[core]!.first}»؟ «$core» كلمة أخرى بمعنى مختلف.',
      OfficeProofingCategory.spelling,
    );
  }

  // ------------------------------------------- L8 content-word repetition

  static const Set<String> _reduplicated = <String>{
    'خطوة',
    'كلمة',
    'لا',
    'نعم',
    'كلا',
    'بلى',
    'هيا',
    'آه',
    'أه',
    'الله',
  };

  void _contentRepetition() {
    const String id = 'ar.repetition.content-word';
    if (!enabled(id)) return;
    for (int w = 1; w < words.length; w++) {
      final String bare = bares[w];
      if (!_adjacent(w) || bare != bares[w - 1] || bare.length < 3) continue;
      // Closed-class words have their own rule; accusative and tanwin
      // reduplication (`رويدا رويدا`, `خطوةً خطوة`) is distributive.
      // Two-letter tokens are mostly spelled-out Latin initials (`بي بي سي`).
      if (ArabicWritingRulesProvider._repeatable.contains(bare) ||
          _reduplicated.contains(bare) ||
          bare.endsWith('ا') ||
          _tanwin.hasMatch(words[w - 1].group(0)!)) {
        continue;
      }
      add(
        id,
        words[w - 1].start,
        words[w].end,
        'تكررت هذه الكلمة مرتين متتاليتين؛ احذف إحداهما إن لم يكن التكرار مقصودًا.',
        category: OfficeProofingCategory.style,
        replacements: <String>[words[w - 1].group(0)!],
      );
    }
  }

  // ------------------------------------------------- L9 long sentences

  static const int longSentenceWords = 80;

  void _longSentences() {
    const String id = 'ar.style.long-sentence';
    if (!enabled(id)) return;
    int first = 0;
    for (int w = 1; w <= words.length; w++) {
      if (w < words.length && sentenceOf[w] == sentenceOf[first]) continue;
      final int count = w - first;
      if (count > longSentenceWords) {
        add(
          id,
          words[first].start,
          words[w - 1].end,
          'جملة طويلة ($count كلمة)؛ قد يسهل فهمها إذا قُسِّمت.',
          category: OfficeProofingCategory.style,
        );
      }
      first = w;
    }
  }
}
