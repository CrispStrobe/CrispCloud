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

typedef _ArabicAdd =
    void Function(
      String ruleId,
      int start,
      int end,
      String message, {
      OfficeProofingCategory category,
      List<String> replacements,
    });

/// The text with harakat and tatweel removed, plus a map back to the source.
final class _ArabicBareText {
  _ArabicBareText(String text) : _sourceLength = text.length {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (ArabicWritingRulesProvider._mark.hasMatch(text[i])) continue;
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
  String _keepHarakat(int w, String to) {
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
        '(?<![$_l])[وف]?(?:يوم\\s+)?($days)(?![$_l])\\s*[،,]?\\s*'
        '(?:(?:الموافق|الماضي|المقبل|القادم|المنصرم)\\s*[،,]?\\s*)?'
        '($_digit{1,2})(?!$_digit)\\s*(?:من\\s+)?(?:شهر\\s+)?'
        '($_monthPattern)(?![$_l])'
        '(?:\\s*[(/]\\s*(?:$_monthPattern)\\s*\\)?)?'
        '\\s*[،,]?\\s*(?:(?:من\\s+)?(?:عام|سنة|العام)\\s+)?'
        '($_digit{4})(?!$_digit)(?!\\s*ه)',
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
        '(?<![$_l])[وفبل]?(?:عام|العام|سنة|السنة|(?:ال)?(?:ربيع|صيف|خريف|شتاء)|'
        '$_monthPattern)\\s+([12١٢]$_digit{4})(?![0-9٠-٩.,٫٬])'
        '(?!\\s*(?:$units)(?![$_l]))',
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

  static const List<_Phrase> _wordiness = <_Phrase>[
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
    _Phrase('في\\s+الوقت\\s+(?:الحالي|الراهن)', <String>['حاليًّا']),
    _Phrase('من\\s+أجل\\s+أن', <String>['لكي']),
  ];

  static const List<_Phrase> _usageExpressions = <_Phrase>[
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
  ];

  void _phraseList(
    String id,
    List<_Phrase> phrases,
    String fallback,
    OfficeProofingCategory category,
  ) {
    if (!enabled(id)) return;
    final String bare = bareText.bare;
    for (final _Phrase phrase in phrases) {
      final RegExp re = RegExp('(?<![$_l])(?:${phrase.pattern})(?![$_l])');
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
        '(?<![$_l])((?:[وف])?)سوف\\s+(س[يتنأ](?!ار)[$_l]+)',
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
      };

  /// Colloquial words that have no Standard Arabic homograph (authored).
  static const Map<String, List<String>> _colloquial = <String, List<String>>{
    'عشان': <String>['لأن', 'من أجل'],
    'علشان': <String>['لأن', 'من أجل'],
    'ليش': <String>['لماذا'],
    'ليه': <String>['لماذا'],
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
    'دابا': <String>['الآن'],
    'هسه': <String>['الآن'],
    'ايش': <String>['ماذا', 'ما'],
    'إيش': <String>['ماذا', 'ما'],
    'شنو': <String>['ماذا', 'ما'],
    'مفيش': <String>['لا يوجد'],
    'مافيش': <String>['لا يوجد'],
    'برضو': <String>['أيضًا'],
    'برضه': <String>['أيضًا'],
    'فين': <String>['أين'],
    'اللي': <String>['الذي', 'التي', 'الذين'],
    'امبارح': <String>['أمس'],
    'إمبارح': <String>['أمس'],
    'منيح': <String>['جيد'],
    'كويس': <String>['جيد'],
    'كويسة': <String>['جيدة'],
    'هيدا': <String>['هذا'],
    'هيدي': <String>['هذه'],
    'بزاف': <String>['كثيرًا'],
    'وايد': <String>['كثيرًا'],
    'علاش': <String>['لماذا'],
    'شحال': <String>['كم'],
    'مش': <String>['ليس', 'غير'],
    'بدي': <String>['أريد'],
    'بتاع': <String>[],
    'بتاعة': <String>[],
  };

  /// Unassimilated loanwords with an established Arabic equivalent.
  static const Map<String, List<String>> _loanwords = <String, List<String>>{
    'أوكي': <String>['حسنًا', 'موافق'],
    'اوكي': <String>['حسنًا', 'موافق'],
    'ميرسي': <String>['شكرًا'],
    'بليز': <String>['من فضلك'],
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
