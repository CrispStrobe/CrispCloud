import 'package:characters/characters.dart';

import 'office_proofing.dart';
import 'proofing_text_ranges.dart';

/// Independently authored Modern Standard Arabic writing checks.
///
/// The word lists and messages were written for Quds from general knowledge
/// of standard Arabic orthography; no external rule set was used. Every
/// lexical rule is a closed, reviewable list: words whose correct form depends
/// on syntax or meaning are either offered with several suggestions or left
/// out (for example `علي` is also the name Ali, `فان` is also "perishing").
///
/// Matching ignores harakat (U+064B–U+065F, U+0670) and tatweel (U+0640), but
/// findings always cover the original source text and suggestions keep the
/// writer's harakat, replacing only the corrected letters. Offsets are
/// original UTF-16 offsets; the text is never rewritten. Links, email
/// addresses and closed backtick spans are excluded.
class ArabicWritingRulesProvider extends OfficeProofingProvider {
  bool _disposed = false;

  @override
  String get id => 'arabic-writing';

  /// Arabic in any region; another script subtag stays unsupported.
  @override
  bool supportsLanguage(String language) {
    final List<String> parts = normalizeProofingLanguage(language).split('-');
    if (parts.first != 'ar') return false;
    return parts.length < 2 || parts[1].length != 4 || parts[1] == 'arab';
  }

  static const Set<String> ruleIds = <String>{
    'ar.hamza.initial',
    'ar.ta-marbuta.final',
    'ar.alif-maqsura.final',
    'ar.ya.final',
    'ar.punctuation.arabic-mark',
    'ar.punctuation.space-before',
    'ar.punctuation.space-after',
    'ar.style.tatweel',
    'ar.repetition.word',
    'ar.spacing.conjunction-waw',
    'ar.digits.mixed',
  };

  /// Words that begin with hamzat al-qat' (bare spelling -> corrected
  /// spellings, most likely first). Words with hamzat al-wasl (ابن، اسم،
  /// امرأة، استخدام ...) are deliberately absent.
  static const Map<String, List<String>> _hamza = <String, List<String>>{
    'الى': <String>['إلى'],
    'اليه': <String>['إليه'],
    'اليها': <String>['إليها'],
    'اليهم': <String>['إليهم'],
    'اليك': <String>['إليك'],
    'او': <String>['أو'],
    'اذا': <String>['إذا'],
    'واذا': <String>['وإذا'],
    'فاذا': <String>['فإذا'],
    'اذ': <String>['إذ'],
    'ان': <String>['أن', 'إن'],
    'انه': <String>['أنه', 'إنه'],
    'انها': <String>['أنها', 'إنها'],
    'الا': <String>['إلا', 'ألا'],
    'اما': <String>['أما', 'إما'],
    'لان': <String>['لأن'],
    'لانه': <String>['لأنه'],
    'لانها': <String>['لأنها'],
    'اي': <String>['أي'],
    'اين': <String>['أين'],
    'انا': <String>['أنا', 'إنا'],
    'انت': <String>['أنت'],
    'انتم': <String>['أنتم'],
    'امام': <String>['أمام', 'إمام'],
    'اخرى': <String>['أخرى'],
    'اول': <String>['أول'],
    'اكثر': <String>['أكثر'],
    'اكبر': <String>['أكبر'],
    'اقل': <String>['أقل'],
    'احد': <String>['أحد'],
    'ايضا': <String>['أيضا'],
    'امس': <String>['أمس'],
    'اثناء': <String>['أثناء'],
    'اهم': <String>['أهم'],
    'اصبح': <String>['أصبح'],
    'اعلن': <String>['أعلن'],
  };

  /// Feminine nouns and adjectives (stem without the final ta marbuta).
  /// Only definite forms are checked: after the article a final ه cannot be
  /// the possessive pronoun (`مدرسه` may be "his teacher"; `المدرسه` cannot).
  static const Set<String> _taMarbutaStems = <String>{
    'مدرس',
    'جامع',
    'مدين',
    'حكوم',
    'شرك',
    'دول',
    'لغ',
    'كلم',
    'فكر',
    'ساع',
    'غرف',
    'سيار',
    'طاول',
    'مكتب',
    'قص',
    'رسال',
    'صور',
    'طريق',
    'مرحل',
    'مشكل',
    'حال',
    'منطق',
    'مسأل',
    'ثقاف',
    'سياس',
    'رياض',
    'حيا',
    'صلا',
    'طالب',
    'معلم',
    'جميل',
    'كبير',
    'صغير',
    'جديد',
    'قديم',
    'عربي',
    'عام',
    'خاص',
    'جمهوري',
    'وزار',
    'إدار',
    'تجرب',
    'دراس',
    'نتيج',
  };

  /// Article spellings, with the proclitics that may precede them.
  static const List<String> _articles = <String>[
    'ال',
    'وال',
    'فال',
    'بال',
    'كال',
    'لل',
    'ولل',
    'فلل',
  ];

  /// Final ي written for alif maqsura, where no other reading exists.
  static const Map<String, String> _alifMaqsura = <String, String>{
    'حتي': 'حتى',
    'متي': 'متى',
    'مستشفي': 'مستشفى',
    'المستشفي': 'المستشفى',
    'المدي': 'المدى',
    'ادني': 'أدنى',
  };

  /// Final ى written for ي (a regional convention, reported as style).
  static const Map<String, String> _finalYa = <String, String>{
    'فى': 'في',
    'الذى': 'الذي',
    'التى': 'التي',
    'هى': 'هي',
  };

  /// Closed-class words whose immediate repetition is almost always a slip.
  /// Emphatic repetition of content words (`جدا جدا`, `رويدا رويدا`) is
  /// intentionally not checked.
  static const Set<String> _repeatable = <String>{
    'في',
    'من',
    'إلى',
    'على',
    'عن',
    'أن',
    'إن',
    'التي',
    'الذي',
    'هذا',
    'هذه',
    'ذلك',
    'تلك',
    'مع',
    'ثم',
    'أو',
    'قد',
    'لقد',
    'كان',
    'هو',
    'هي',
    'لم',
    'لن',
    'حتى',
    'بين',
    'عند',
  };

  static const String _letters = r'ء-غف-يٱ-ۓ';
  static const String _marks = r'ً-ٰٟـ';
  static final RegExp _word = RegExp('[$_letters][$_letters$_marks]*');
  static final RegExp _mark = RegExp('[$_marks]');
  static final RegExp _arabicLetter = RegExp('[$_letters]');

  /// The bare spelling and, for each bare letter, its source offset.
  static (String, List<int>) _bare(String word) {
    final StringBuffer bare = StringBuffer();
    final List<int> positions = <int>[];
    for (int i = 0; i < word.length; i++) {
      final String unit = word[i];
      if (_mark.hasMatch(unit)) continue;
      bare.write(unit);
      positions.add(i);
    }
    return (bare.toString(), positions);
  }

  /// Replaces only the letters that differ, keeping the writer's harakat.
  static String? _respell(String word, String bare, List<int> at, String to) {
    if (to.length != bare.length) return null;
    final List<String> units = word.split('');
    for (int i = 0; i < bare.length; i++) {
      if (bare[i] != to[i]) units[at[i]] = to[i];
    }
    return units.join();
  }

  static Set<int> _graphemeBoundaries(String text) {
    final Set<int> boundaries = <int>{0};
    int end = 0;
    for (final String cluster in text.characters) {
      end += cluster.length;
      boundaries.add(end);
    }
    return boundaries;
  }

  static bool _arabicBefore(String text, int index) {
    int i = index - 1;
    while (i >= 0 && _mark.hasMatch(text[i])) {
      i--;
    }
    return i >= 0 && _arabicLetter.hasMatch(text[i]);
  }

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    if (_disposed || !supportsLanguage(request.language)) {
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: _disposed
            ? OfficeProofingStatus.unavailable
            : OfficeProofingStatus.unsupported,
        message: _disposed
            ? 'Arabic writing provider is disposed.'
            : 'Arabic writing checks support Arabic-script Arabic (ar).',
      );
    }
    final String text = request.text;
    final OfficeProofingTextRanges protected = OfficeProofingTextRanges(text);
    final Set<int> boundaries = _graphemeBoundaries(text);
    final List<OfficeProofingFinding> findings = <OfficeProofingFinding>[];

    void add(
      String ruleId,
      int start,
      int end,
      String message, {
      OfficeProofingCategory category = OfficeProofingCategory.grammar,
      List<String> replacements = const <String>[],
    }) {
      if (!boundaries.contains(start) ||
          !boundaries.contains(end) ||
          request.ignoredRuleIds.contains(ruleId) ||
          protected.overlaps(start, end)) {
        return;
      }
      findings.add(
        OfficeProofingFinding.forRequest(
          request,
          providerId: id,
          start: start,
          end: end,
          ruleId: ruleId,
          message: message,
          category: category,
          replacements: replacements,
        ),
      );
    }

    final List<RegExpMatch> words = _word.allMatches(text).toList();
    for (int w = 0; w < words.length; w++) {
      if (w % 512 == 511) {
        await Future<void>.delayed(Duration.zero);
        if (_disposed) {
          return OfficeProofingResult(
            request: request,
            providerId: id,
            status: OfficeProofingStatus.unavailable,
            message: 'Arabic writing provider is disposed.',
          );
        }
      }
      final RegExpMatch match = words[w];
      final String word = match.group(0)!;
      final (String bare, List<int> at) = _bare(word);

      List<String> respelled(Iterable<String> targets) => <String>[
        for (final String target in targets)
          if (_respell(word, bare, at, target) case final String value) value,
      ];

      final List<String>? hamza = _hamza[bare];
      if (hamza != null) {
        add(
          'ar.hamza.initial',
          match.start,
          match.end,
          hamza.length > 1
              ? 'تُكتب في أول هذه الكلمة همزة قطع؛ اختر الصيغة حسب السياق.'
              : 'تُكتب في أول هذه الكلمة همزة قطع.',
          category: OfficeProofingCategory.spelling,
          replacements: respelled(hamza),
        );
        continue;
      }
      final String? maqsura = _alifMaqsura[bare];
      if (maqsura != null) {
        add(
          'ar.alif-maqsura.final',
          match.start,
          match.end,
          'تُكتب هذه الكلمة بالألف المقصورة (ى) في آخرها.',
          category: OfficeProofingCategory.spelling,
          replacements: respelled(<String>[maqsura]),
        );
        continue;
      }
      final String? ya = _finalYa[bare];
      if (ya != null) {
        add(
          'ar.ya.final',
          match.start,
          match.end,
          'في الإملاء القياسي تُكتب هذه الكلمة بالياء (ي) في آخرها.',
          category: OfficeProofingCategory.style,
          replacements: respelled(<String>[ya]),
        );
        continue;
      }
      if (bare.endsWith('ه')) {
        for (final String article in _articles) {
          if (!bare.startsWith(article)) continue;
          final String stem = bare.substring(article.length, bare.length - 1);
          if (_taMarbutaStems.contains(stem)) {
            add(
              'ar.ta-marbuta.final',
              match.start,
              match.end,
              'تُكتب هذه الكلمة المعرّفة بالتاء المربوطة (ة) في آخرها.',
              category: OfficeProofingCategory.spelling,
              replacements: respelled(<String>[
                '${bare.substring(0, bare.length - 1)}ة',
              ]),
            );
            break;
          }
        }
      }
    }

    // Immediate repetition of a closed-class word (harakat-insensitive).
    for (int w = 1; w < words.length; w++) {
      final RegExpMatch previous = words[w - 1];
      final RegExpMatch current = words[w];
      final String gap = text.substring(previous.end, current.start);
      if (!RegExp(r'^[  ]+$').hasMatch(gap)) continue;
      final String bare = _bare(current.group(0)!).$1;
      if (bare != _bare(previous.group(0)!).$1 || !_repeatable.contains(bare)) {
        continue;
      }
      add(
        'ar.repetition.word',
        previous.start,
        current.end,
        'تكررت هذه الكلمة مرتين متتاليتين.',
        category: OfficeProofingCategory.style,
        replacements: <String>[previous.group(0)!],
      );
    }

    // Detached conjunction waw: `و هو` -> `وهو`.
    for (final RegExpMatch m in RegExp(
      '(?<![$_letters$_marks\\p{N}])و[\\u064B-\\u0652]?( +)(?=[$_letters])',
      unicode: true,
    ).allMatches(text)) {
      final String waw = m
          .group(0)!
          .substring(0, m.group(0)!.length - m.group(1)!.length);
      add(
        'ar.spacing.conjunction-waw',
        m.start,
        m.end,
        'تُكتب واو العطف متصلة بالكلمة التي بعدها.',
        category: OfficeProofingCategory.spelling,
        replacements: <String>[waw],
      );
    }

    // Latin punctuation after Arabic script.
    const Map<String, String> arabicMarks = <String, String>{
      ',': '،',
      ';': '؛',
      '?': '؟',
    };
    for (final RegExpMatch m in RegExp(r'[,;?]').allMatches(text)) {
      int before = m.start;
      while (before > 0 && text[before - 1] == ' ') {
        before--;
      }
      if (!_arabicBefore(text, before)) continue;
      // A digit after a comma is a number separator, not punctuation.
      if (m.end < text.length && RegExp(r'\d').hasMatch(text[m.end])) continue;
      add(
        'ar.punctuation.arabic-mark',
        m.start,
        m.end,
        'استخدم علامة الترقيم العربية «${arabicMarks[m.group(0)]}» في النص العربي.',
        category: OfficeProofingCategory.style,
        replacements: <String>[arabicMarks[m.group(0)]!],
      );
    }
    // Spaces before an Arabic punctuation mark.
    for (final RegExpMatch m in RegExp(r' +(?=[،؛؟])').allMatches(text)) {
      if (!_arabicBefore(text, m.start)) continue;
      add(
        'ar.punctuation.space-before',
        m.start,
        m.end,
        'لا توضع مسافة قبل علامة الترقيم.',
        category: OfficeProofingCategory.style,
        replacements: <String>[''],
      );
    }
    // A missing space after ، or ؛ before the next Arabic word.
    for (final RegExpMatch m in RegExp(
      '[،؛](?=[$_letters])',
    ).allMatches(text)) {
      add(
        'ar.punctuation.space-after',
        m.end,
        m.end,
        'ضع مسافة بعد علامة الترقيم.',
        category: OfficeProofingCategory.style,
        replacements: <String>[' '],
      );
    }

    // Tatweel (kashida) inside running text.
    for (final RegExpMatch m in RegExp(r'ـ+').allMatches(text)) {
      if (!_arabicBefore(text, m.start)) continue;
      add(
        'ar.style.tatweel',
        m.start,
        m.end,
        'التطويل (ـ) زخرفة خطية؛ يُحذف عادة من النص الجاري.',
        category: OfficeProofingCategory.style,
        replacements: <String>[''],
      );
    }

    // A number that mixes Western and Arabic-Indic digits.
    for (final RegExpMatch m in RegExp(
      r'[0-9٠-٩۰-۹](?:[0-9٠-٩۰-۹]|[.,٫٬](?=[0-9٠-٩۰-۹]))*',
    ).allMatches(text)) {
      final String number = m.group(0)!;
      final bool western = RegExp(r'[0-9]').hasMatch(number);
      final bool arabicIndic = RegExp(r'[٠-٩]').hasMatch(number);
      final bool persian = RegExp(r'[۰-۹]').hasMatch(number);
      if ((western ? 1 : 0) + (arabicIndic ? 1 : 0) + (persian ? 1 : 0) < 2) {
        continue;
      }
      String digits(int base) => String.fromCharCodes(
        number.runes.map((int r) {
          final int value = r >= 0x30 && r <= 0x39
              ? r - 0x30
              : r >= 0x660 && r <= 0x669
              ? r - 0x660
              : r >= 0x6F0 && r <= 0x6F9
              ? r - 0x6F0
              : -1;
          return value < 0 ? r : base + value;
        }),
      );
      add(
        'ar.digits.mixed',
        m.start,
        m.end,
        'يجمع هذا الرقم بين نوعين من الأرقام؛ وحّد طريقة كتابته.',
        category: OfficeProofingCategory.style,
        replacements: <String>[digits(0x660), digits(0x30)],
      );
    }

    findings.sort((a, b) => a.start.compareTo(b.start));
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: findings,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
