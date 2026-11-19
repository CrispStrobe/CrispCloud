// Tests for the clean-room T1 extension of the Arabic writing rules.
// Every sentence here was written for Quds; none is taken from another
// checker's examples.
import 'package:quds_office_engine/src/proofing/arabic_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

Future<List<OfficeProofingFinding>> check(
  String text, {
  Set<String> optional = const <String>{},
  int startOffset = 0,
  Set<String> ignored = const <String>{},
}) async {
  final ArabicWritingRulesProvider provider = ArabicWritingRulesProvider(
    enabledOptionalRuleIds: optional,
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
  return result.findings;
}

/// (sentence, rule id, original text of the finding, first replacement or
/// null when the rule offers advice only)
typedef Positive = (String, String, String, String?);

const List<Positive> defaultPositives = <Positive>[
  // ar.punctuation.doubled
  ('جاء أحمد،، وذهب علي.', 'ar.punctuation.doubled', '،،', '،'),
  ('انتهى الاجتماع.. ثم خرجنا.', 'ar.punctuation.doubled', '..', '.'),
  ('قرأ الكتاب؛؛ ثم نام.', 'ar.punctuation.doubled', '؛؛', '؛'),
  // ar.punctuation.unpaired
  (
    'قال المدير (في الاجتماع إن الخطة جاهزة.',
    'ar.punctuation.unpaired',
    '(',
    null,
  ),
  ('وصل الوفد في الموعد) ثم بدأ الحوار.', 'ar.punctuation.unpaired', ')', null),
  ('قال: «سنبدأ العمل غدا.', 'ar.punctuation.unpaired', '«', null),
  ('قال الشاعر: "العلم نور.', 'ar.punctuation.unpaired', '"', null),
  ('قال تعالى: ﴿اقرأ باسم ربك.', 'ar.punctuation.unpaired', '﴿', null),
  // ar.spacing.multiple
  ('ذهب الطالب  إلى المدرسة.', 'ar.spacing.multiple', '  ', ' '),
  // ar.spacing.after-sentence
  ('انتهى الدرس.وبدأت الاستراحة.', 'ar.spacing.after-sentence', '', ' '),
  ('هل فهمت؟نعم فهمت.', 'ar.spacing.after-sentence', '', ' '),
  // ar.spacing.run-together
  (
    'زرت المدرسةالجديدة أمس.',
    'ar.spacing.run-together',
    'المدرسةالجديدة',
    'المدرسة الجديدة',
  ),
  ('ذهبت إلىالسوق صباحا.', 'ar.spacing.run-together', 'إلىالسوق', 'إلى السوق'),
  // harakat stay with their letter; the space goes after them
  (
    'زرتُ المدرسةَالجديدةَ.',
    'ar.spacing.run-together',
    'المدرسةَالجديدةَ',
    'المدرسةَ الجديدةَ',
  ),
  // ar.spacing.theophoric
  ('جاء عبدالله مبكرا.', 'ar.spacing.theophoric', 'عبدالله', 'عبد الله'),
  ('سلمت على عبدالرحمن.', 'ar.spacing.theophoric', 'عبدالرحمن', 'عبد الرحمن'),
  ('ولعبدالعزيز كتاب.', 'ar.spacing.theophoric', 'ولعبدالعزيز', 'ولعبد العزيز'),
  // ar.hamza.maqsura-hamza
  ('جلسنا على شاطىء البحر.', 'ar.hamza.maqsura-hamza', 'شاطىء', 'شاطئ'),
  ('هذه مبادىء عامة.', 'ar.hamza.maqsura-hamza', 'مبادىء', 'مبادئ'),
  ('جلسنا على شاطِىء البحر.', 'ar.hamza.maqsura-hamza', 'شاطِىء', 'شاطِئ'),
  // ar.hamza.wasl-measure
  ('تم إستخدام الحاسوب.', 'ar.hamza.wasl-measure', 'إستخدام', 'استخدام'),
  ('بدأ الإجتماع صباحا.', 'ar.hamza.wasl-measure', 'الإجتماع', 'الاجتماع'),
  ('أعلن إنطلاق الحملة.', 'ar.hamza.wasl-measure', 'إنطلاق', 'انطلاق'),
  ('قدم إستقالته أمس.', 'ar.hamza.wasl-measure', 'إستقالته', 'استقالته'),
  ('وقعوا إتفاقية جديدة.', 'ar.hamza.wasl-measure', 'إتفاقية', 'اتفاقية'),
  ('شعر بالإضطراب.', 'ar.hamza.wasl-measure', 'بالإضطراب', 'بالاضطراب'),
  ('تم إسْتخدام الحاسوب.', 'ar.hamza.wasl-measure', 'إسْتخدام', 'اسْتخدام'),
  // ar.spelling.common
  ('هاذا الكتاب مفيد.', 'ar.spelling.common', 'هاذا', 'هذا'),
  ('لاكن الطقس بارد.', 'ar.spelling.common', 'لاكن', 'لكن'),
  ('وصلنا وقت الضهر.', 'ar.spelling.common', 'الضهر', 'الظهر'),
  ('وإسمه محمد.', 'ar.spelling.common', 'وإسمه', 'واسمه'),
  ('إسمُه محمد.', 'ar.spelling.common', 'إسمُه', 'اسمُه'),
  // ar.consistency.spelling
  (
    'قال المسؤول إن المسئولية مشتركة.',
    'ar.consistency.spelling',
    'المسئولية',
    'المسؤولية',
  ),
  ('دفع مائة دينار ثم مئة أخرى.', 'ar.consistency.spelling', 'مئة', 'مائة'),
  // ar.date.weekday
  ('وصل الوفد يوم الجمعة 5 مارس 2020.', 'ar.date.weekday', 'الجمعة', 'الخميس'),
  (
    'عقد الاجتماع الثلاثاء ١ كانون الثاني ٢٠٢٤.',
    'ar.date.weekday',
    'الثلاثاء',
    'الاثنين',
  ),
  (
    'افتتح المعرض السبت، 14 تموز (يوليو) 2023.',
    'ar.date.weekday',
    'السبت',
    'الجمعة',
  ),
  ('صدر القرار يوم الأحَد 5 مارس 2020.', 'ar.date.weekday', 'الأحَد', 'الخميس'),
  // ar.date.invalid-day
  ('سافر يوم الأحد 31 أبريل 2022.', 'ar.date.invalid-day', '31', null),
  ('موعد الأربعاء 29 فبراير 2023.', 'ar.date.invalid-day', '29', null),
  // ar.date.implausible-year
  ('ولد في عام 19995 في القاهرة.', 'ar.date.implausible-year', '19995', null),
  ('في مارس ٢٠٢٤٥ افتتح المعرض.', 'ar.date.implausible-year', '٢٠٢٤٥', null),
  // ar.grammar.hal-particle
  ('هل لم تسمع الخبر؟', 'ar.grammar.hal-particle', 'هل لم', 'ألم'),
  ('وهل لا يعرف الطريق؟', 'ar.grammar.hal-particle', 'وهل لا', 'أولا'),
  ('هل إنه قادم؟', 'ar.grammar.hal-particle', 'هل إنه', 'أإنه'),
  ('هل لو جاء لقابلته؟', 'ar.grammar.hal-particle', 'هل لو', null),
  // ar.redundancy.double-future
  ('سوف سيذهب إلى السوق.', 'ar.redundancy.double-future', 'سوف سيذهب', 'سيذهب'),
  (
    'سوفَ سيذهبُ إلى السوق.',
    'ar.redundancy.double-future',
    'سوفَ سيذهبُ',
    'سيذهبُ',
  ),
  // ar.redundancy.phrase
  ('حضر حوالي مئة شخص تقريبا.', 'ar.redundancy.phrase', ' تقريبا', ''),
  ('لم يحضر إلا أحمد فقط.', 'ar.redundancy.phrase', ' فقط', ''),
  ('صعد إلى الأعلى.', 'ar.redundancy.phrase', 'صعد إلى الأعلى', 'صعد'),
  (
    'نستعد للمستقبل القادم.',
    'ar.redundancy.phrase',
    'للمستقبل القادم',
    'للمستقبل',
  ),
  ('في حال إذا تأخرت فاتصل.', 'ar.redundancy.phrase', 'في حال إذا', 'في حال'),
  // ar.expression.error
  ('أحب الفاكهة سيما التفاح.', 'ar.expression.error', 'سيما', 'لا سيما'),
  (
    'سأزورك غدا إنشاء الله.',
    'ar.expression.error',
    'إنشاء الله',
    'إن شاء الله',
  ),
  ('درس كل حالة على حدى.', 'ar.expression.error', 'على حدى', 'على حدة'),
  // ar.register.colloquial
  ('ليش تأخرت اليوم؟', 'ar.register.colloquial', 'ليش', 'لماذا'),
  ('هيك قال المعلم.', 'ar.register.colloquial', 'هيك', 'هكذا'),
  ('وعشان كذا تأخرنا.', 'ar.register.colloquial', 'وعشان', 'ولأن'),
  // ar.repetition.content-word
  (
    'قرأت الكتاب الكتاب أمس.',
    'ar.repetition.content-word',
    'الكتاب الكتاب',
    'الكتاب',
  ),
];

const List<Positive> optionalPositives = <Positive>[
  ('بينما كان يمشي سقط.', 'ar.usage.baynama-initial', 'بينما', 'عندما'),
  ('طالما أنت هنا فلا تقلق.', 'ar.usage.talama', 'طالما', 'ما دام'),
  ('وطالما أنت هنا فلا تقلق.', 'ar.usage.talama', 'وطالما', 'وما دام'),
  ('إما أن تحضر أو تعتذر.', 'ar.usage.imma-aw', 'أو', 'وإما'),
  ('كلما قرأت كلما فهمت.', 'ar.usage.kullama-repeated', 'كلما ', ''),
  ('لم أره أبدا.', 'ar.usage.abadan-past', 'أبدا', 'قطّ'),
  ('لم أره أبدًا.', 'ar.usage.abadan-past', 'أبدًا', 'قطّ'),
  ('يختار بين أمرين.', 'ar.usage.expression', 'يختار بين', 'يختار من بين'),
  ('جلس بين أحمد وبين علي.', 'ar.usage.expression', 'وبين ', 'و'),
  ('لا زال المطر ينهمر.', 'ar.usage.expression', 'لا زال', 'ما زال'),
  ('يساعدون بعضهم البعض.', 'ar.usage.expression', 'بعضهم البعض', 'بعضهم بعضًا'),
  ('ساهم الجميع في النجاح.', 'ar.usage.word', 'ساهم', 'أسهم'),
  ('هذا قرار هام.', 'ar.usage.word', 'هام', 'مهم'),
  (
    'مما لا شك فيه أن العلم نافع.',
    'ar.style.wordiness',
    'مما لا شك فيه أن',
    'لا شك أن',
  ),
  ('الكتاب عبارة عن قصص.', 'ar.style.wordiness', 'عبارة عن ', ''),
  ('شكراً لك.', 'ar.style.tanwin-placement', 'شكراً', 'شكرًا'),
  ('أرسل لي إيميل.', 'ar.register.loanword', 'إيميل', 'بريد إلكتروني'),
  ('خاض تجربة جديدة.', 'ar.hint.vowelling', 'تجربة', 'تَجْرِبة'),
  ('نجحت التجربة.', 'ar.hint.vowelling', 'التجربة', 'الت\u064E\u0651جْرِبة'),
  ('أعجبتني والقصة أيضا.', 'ar.hint.vowelling', 'والقصة', 'والقِصّة'),
  ('ضل يعمل حتى المساء.', 'ar.hint.dad-za', 'ضل', 'ظل'),
];

/// Valid text for each default rule: no finding of any kind.
const List<String> defaultControls = <String>[
  'وهكذا انتهت القصة...',
  'قال (في الاجتماع) إن الخطة جاهزة.',
  '«العلم نور» كما قيل.',
  '»العلم نور« كما قيل في الكتاب.',
  'قال تعالى: ﴿اقرأ باسم ربك﴾.',
  'قال تعالى: ﴾اقرأ باسم ربك﴿.',
  '1) المقدمة 2) العرض',
  'أ) الفصل الأول',
  'شكرا لك :)',
  '«بداية اقتباس طويل يمتد إلى الفقرة التالية',
  'ذهب الطالب إلى المدرسة.',
  'قابلت د.محمد في الجامعة.',
  'راجع البقرة:255 في المصحف.',
  'زرت المدرسة الجديدة.',
  'جاء مستشفى الحي بالأطباء.',
  'جاء عبد الله مبكرا.',
  'قابلت عبدو في السوق.',
  'جلسنا على شاطئ البحر.',
  'لكل شيء سبب.',
  'زاد إنتاج المصنع.',
  'هذا إنسان طيب.',
  'أعلن إطلاق القمر.',
  'تقع إندونيسيا في آسيا.',
  'سافر إلى إسطنبول.',
  'وضع الإسطوانة في الجهاز.',
  'إنديانا ولاية أمريكية.',
  'أعلنت الشركة إستراتيجية جديدة.',
  'أعلنت الشركة استراتيجية جديدة واستخدمت أدوات حديثة.',
  'هذا الكتاب مفيد، لكن الطقس بارد.',
  'جاء يوم الإثنين.',
  'قال المسؤول إن المسؤولية مشتركة.',
  'قال المسئول إن المسئولية مشتركة.',
  'وصل الوفد يوم الخميس 5 مارس 2020.',
  'عقد الاجتماع الاثنين ١ كانون الثاني ٢٠٢٤.',
  'الجمعة 6 آذار 2020 موعد الافتتاح.',
  'الخميس 5 رمضان 1445 للهجرة موعد الإفطار.',
  'الخميس 29 فبراير 2024 يوم مميز.',
  'في مارس 12000 دولار من الأرباح.',
  'عام 2024 كان حافلا.',
  'عاش الإنسان هنا منذ سنة 10000 قبل الميلاد.',
  'ألم تسمع الخبر؟',
  'هل لاحظت التغيير؟',
  'هل سيحضر غدا؟',
  'سوف يذهب إلى السوق.',
  'سيذهب إلى السوق.',
  'سوف سيارته تصل.',
  'صعد إلى أعلى قمة في الجبل.',
  'حضر حوالي مئة شخص.',
  'أخذ الطالب الكتاب فقط.',
  'في حال تأخرت فاتصل.',
  'أحب الفاكهة ولا سيما التفاح.',
  'أحب الفاكهة لا سيما التفاح.',
  'ناقش الفيلسوف إنشاء الله العالم.',
  'درس كل حالة على حدة.',
  'لماذا تأخرت اليوم؟',
  'عزف على الكمان.',
  'ارتدى زيه الرسمي.',
  'تقدم خطوة خطوة.',
  'دخلوا واحدا واحدا.',
  'تقدمنا خطوةً خطوةً.',
  'شاهدت برنامجا على بي بي سي.',
  // opt-in rules stay silent by default
  'بينما كان يمشي سقط.',
  'لم أره أبدا.',
  'ساهم الجميع في النجاح.',
  'شكراً لك.',
  'خاض تجربة جديدة.',
  'ظل يعمل حتى المساء.',
  'ضل يعمل حتى المساء.',
];

/// Valid text for the opt-in rules, checked with every opt-in rule enabled.
const List<String> optionalControls = <String>[
  'قرأ أحمد بينما كتب علي.',
  'ذكرته طالما بالخير.',
  'إما أن تحضر وإما أن تعتذر.',
  'كلما قرأت فهمت.',
  'لن أنساه أبدا.',
  'جلس بيني وبين علي.',
  'ما زال المطر ينهمر.',
  'لا يزال المطر ينهمر.',
  'يساعد بعضهم بعضا.',
  'أسهم الجميع في النجاح.',
  'لا شك أن العلم نافع.',
  'شكرًا لك.',
  'شربنا ماءً باردا.',
  'أرسل لي بريدا إلكترونيا.',
  'خاض تَجْرِبة جديدة.',
  'ظل يعمل حتى المساء.',
];

void main() {
  void positives(List<Positive> cases, {required bool optional}) {
    for (final (String text, String rule, String original, String? first)
        in cases) {
      test('$rule: $text', () async {
        final List<OfficeProofingFinding> findings = await check(
          text,
          optional: optional ? <String>{rule} : const <String>{},
        );
        final List<OfficeProofingFinding> matching = <OfficeProofingFinding>[
          for (final OfficeProofingFinding f in findings)
            if (f.ruleId == rule) f,
        ];
        expect(
          matching,
          hasLength(1),
          reason: findings
              .map((f) => '${f.ruleId}:${f.originalText}')
              .join(', '),
        );
        final OfficeProofingFinding finding = matching.single;
        expect(finding.originalText, original);
        expect(text.substring(finding.start, finding.end), original);
        if (first == null) {
          expect(finding.replacements, isEmpty);
        } else {
          expect(finding.replacements.first, first);
        }
        expect(finding.message, isNotEmpty);
      });
    }
  }

  group('default T1 rules', () {
    positives(defaultPositives, optional: false);
    for (final String text in defaultControls) {
      test('control has no finding: $text', () async {
        final List<OfficeProofingFinding> findings = await check(text);
        expect(
          findings.map((f) => '${f.ruleId}:${f.originalText}').toList(),
          isEmpty,
        );
      });
    }
  });

  group('opt-in T1 rules', () {
    positives(optionalPositives, optional: true);
    for (final String text in optionalControls) {
      test('control has no finding with all opt-ins: $text', () async {
        final List<OfficeProofingFinding> findings = await check(
          text,
          optional: arabicExtendedOptionalRuleIds,
        );
        expect(
          findings.map((f) => '${f.ruleId}:${f.originalText}').toList(),
          isEmpty,
        );
      });
    }
    for (final (String text, String rule, _, _) in optionalPositives) {
      test('$rule is off by default: $text', () async {
        final List<OfficeProofingFinding> findings = await check(text);
        expect(findings.where((f) => f.ruleId == rule), isEmpty);
      });
    }

    test('long sentences are reported only above 80 words', () async {
      final String long = List<String>.generate(
        85,
        (int i) => i.isEven ? 'ذهب' : 'الولد',
      ).join(' ');
      final List<OfficeProofingFinding> findings = await check(
        '$long.',
        optional: <String>{'ar.style.long-sentence'},
      );
      expect(findings.single.ruleId, 'ar.style.long-sentence');
      expect(findings.single.start, 0);
      expect(findings.single.end, long.length);
      final List<OfficeProofingFinding> short = await check(
        '${long.split(' ').take(40).join(' ')}.',
        optional: <String>{'ar.style.long-sentence'},
      );
      expect(short, isEmpty);
      expect(await check('$long.'), isEmpty);
    });
  });

  group('conventions', () {
    test('every extended rule id has a positive case', () {
      final Set<String> seen = <String>{
        for (final (_, String rule, _, _) in defaultPositives) rule,
        for (final (_, String rule, _, _) in optionalPositives) rule,
        'ar.style.long-sentence',
      };
      expect(seen, <String>{
        ...arabicExtendedDefaultRuleIds,
        ...arabicExtendedOptionalRuleIds,
      });
      expect(
        arabicExtendedDefaultRuleIds.intersection(
          arabicExtendedOptionalRuleIds,
        ),
        isEmpty,
      );
      expect(
        ArabicWritingRulesProvider.allRuleIds.length,
        ArabicWritingRulesProvider.ruleIds.length +
            arabicExtendedDefaultRuleIds.length +
            arabicExtendedOptionalRuleIds.length,
      );
    });

    test('unknown or default rule ids cannot be "enabled"', () {
      final ArabicWritingRulesProvider provider = ArabicWritingRulesProvider(
        enabledOptionalRuleIds: <String>{
          'ar.hint.vowelling',
          'ar.date.weekday',
          'nonsense',
        },
      );
      expect(provider.enabledOptionalRuleIds, <String>{'ar.hint.vowelling'});
    });

    test('RTL offsets: original UTF-16 offsets plus startOffset', () async {
      // Latin, an emoji (surrogate pair) and harakat precede the finding.
      const String text = 'Quds 😀 قرأتُ الكتابَ ثم زرت المدرسةالجديدة.';
      final List<OfficeProofingFinding> findings = await check(
        text,
        startOffset: 100,
      );
      final OfficeProofingFinding finding = findings.single;
      expect(finding.ruleId, 'ar.spacing.run-together');
      expect(finding.start, 100 + text.indexOf('المدرسةالجديدة'));
      expect(finding.end, finding.start + 'المدرسةالجديدة'.length);
    });

    test('RTL offsets of a phrase found on the harakat-free text', () async {
      const String text = 'قالَ 😀 إنّه سيزورنا غدًا إنْشَاءُ اللهِ.';
      final List<OfficeProofingFinding> findings = await check(text);
      final OfficeProofingFinding finding = findings.single;
      expect(finding.ruleId, 'ar.expression.error');
      expect(finding.originalText, 'إنْشَاءُ اللهِ');
      expect(finding.start, text.indexOf('إنْشَاءُ'));
    });

    test('a date inside RTL text with Arabic-Indic digits', () async {
      const String text = 'أُقيم الحفل يوم الأحد ٥ مارس ٢٠٢٠ في المدينة.';
      final List<OfficeProofingFinding> findings = await check(text);
      expect(findings.single.ruleId, 'ar.date.weekday');
      expect(findings.single.start, text.indexOf('الأحد'));
      expect(findings.single.replacements, <String>['الخميس']);
    });

    test('links, email and code spans are excluded', () async {
      expect(
        await check('افتح https://example.com/المدرسةالجديدة(1 الآن.'),
        isEmpty,
      );
      expect(await check('نفذ `هاذا،، إستخدام` في الطرفية.'), isEmpty);
      expect(await check('راسل عبدالله@example.org اليوم.'), isEmpty);
    });

    test('ignored extended rule ids suppress findings', () async {
      final List<OfficeProofingFinding> findings = await check(
        'هاذا شاطىء جميل.',
        ignored: <String>{'ar.spelling.common'},
      );
      expect(findings.map((f) => f.ruleId), <String>['ar.hamza.maqsura-hamza']);
    });

    test('several opt-in rules can be enabled together', () async {
      final List<OfficeProofingFinding> findings = await check(
        'ساهم الجميع شكراً لهم.',
        optional: arabicExtendedOptionalRuleIds,
      );
      expect(findings.map((f) => f.ruleId).toSet(), <String>{
        'ar.usage.word',
        'ar.style.tanwin-placement',
      });
    });
  });
}
