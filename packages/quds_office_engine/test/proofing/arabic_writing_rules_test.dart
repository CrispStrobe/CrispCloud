import 'package:quds_office_engine/src/proofing/arabic_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest request(
  String text, {
  String language = 'ar',
  int startOffset = 0,
  Set<String> ignored = const <String>{},
}) => OfficeProofingRequest(
  documentId: 'arabic-document',
  blockId: 'paragraph',
  revision: 2,
  text: text,
  language: language,
  startOffset: startOffset,
  ignoredRuleIds: ignored,
);

Future<List<OfficeProofingFinding>> check(
  String text, {
  String language = 'ar',
  int startOffset = 0,
  Set<String> ignored = const <String>{},
}) async {
  final ArabicWritingRulesProvider provider = ArabicWritingRulesProvider();
  final OfficeProofingResult result = await provider.check(
    request(
      text,
      language: language,
      startOffset: startOffset,
      ignored: ignored,
    ),
  );
  expect(result.status, OfficeProofingStatus.success);
  return result.findings;
}

void main() {
  // (sentence, rule id, original text of the finding, first replacement)
  const List<(String, String, String, String)>
  positives = <(String, String, String, String)>[
    // ar.hamza.initial
    ('ذهب الولد الى البيت.', 'ar.hamza.initial', 'الى', 'إلى'),
    ('عاد اليه بعد ساعة.', 'ar.hamza.initial', 'اليه', 'إليه'),
    ('هل تريد الشاي او القهوة؟', 'ar.hamza.initial', 'او', 'أو'),
    ('سأحضر اذا سمح الوقت.', 'ar.hamza.initial', 'اذا', 'إذا'),
    ('واذا تأخرت فاتصل بي.', 'ar.hamza.initial', 'واذا', 'وإذا'),
    ('أعرف ان الطريق طويل.', 'ar.hamza.initial', 'ان', 'أن'),
    ('غاب لانه مريض.', 'ar.hamza.initial', 'لانه', 'لأنه'),
    ('اين الكتاب؟', 'ar.hamza.initial', 'اين', 'أين'),
    ('هذا اكبر بيت في الحي.', 'ar.hamza.initial', 'اكبر', 'أكبر'),
    ('جاء الطلاب ايضا.', 'ar.hamza.initial', 'ايضا', 'أيضا'),
    ('وقف امام الباب.', 'ar.hamza.initial', 'امام', 'أمام'),
    // harakat are matched loosely and kept in the suggestion
    ('ذهبَ الَى السوق.', 'ar.hamza.initial', 'الَى', 'إلَى'),
    ('قرأت اخبار اليوم.', 'ar.hamza.initial', 'اخبار', 'أخبار'),
    ('هذا افضل حل.', 'ar.hamza.initial', 'افضل', 'أفضل'),
    ('وصلت اخيرا إلى البيت.', 'ar.hamza.initial', 'اخيرا', 'أخيرا'),
    ('سافر إلى اسيا.', 'ar.hamza.initial', 'اسيا', 'آسيا'),
    ('قرأ اية من القرآن.', 'ar.hamza.initial', 'اية', 'آية'),
    ('غاب لانهم مرضى.', 'ar.hamza.initial', 'لانهم', 'لأنهم'),
    ('اكد الوزير الخبر.', 'ar.hamza.initial', 'اكد', 'أكد'),
    ('ابو بكر صديقه.', 'ar.hamza.initial', 'ابو', 'أبو'),
    ('فانه يعرف الطريق.', 'ar.hamza.initial', 'فانه', 'فإنه'),
    // ar.ta-marbuta.final
    ('ذهبت الى المدرسه صباحا.', 'ar.ta-marbuta.final', 'المدرسه', 'المدرسة'),
    ('درس في الجامعه سنوات.', 'ar.ta-marbuta.final', 'الجامعه', 'الجامعة'),
    ('عاد من المدينه الكبيرة.', 'ar.ta-marbuta.final', 'المدينه', 'المدينة'),
    ('عاد من المدينة الكبيره.', 'ar.ta-marbuta.final', 'الكبيره', 'الكبيرة'),
    ('ذهب بالسياره.', 'ar.ta-marbuta.final', 'بالسياره', 'بالسيارة'),
    ('كتب رسالة للحكومه.', 'ar.ta-marbuta.final', 'للحكومه', 'للحكومة'),
    ('يحب اللغه العربية.', 'ar.ta-marbuta.final', 'اللغه', 'اللغة'),
    ('يحب اللغة العربيه.', 'ar.ta-marbuta.final', 'العربيه', 'العربية'),
    ('زار القاهره.', 'ar.ta-marbuta.final', 'القاهره', 'القاهرة'),
    ('هذه المرحلة الثانيه.', 'ar.ta-marbuta.final', 'الثانيه', 'الثانية'),
    ('كان مفيدا للغايه.', 'ar.ta-marbuta.final', 'للغايه', 'للغاية'),
    ('تحدث عن الحريه.', 'ar.ta-marbuta.final', 'الحريه', 'الحرية'),
    // ar.alif-maqsura.final
    ('انتظر حتي الصباح.', 'ar.alif-maqsura.final', 'حتي', 'حتى'),
    ('متي يبدأ الدرس؟', 'ar.alif-maqsura.final', 'متي', 'متى'),
    ('نقل إلى المستشفي.', 'ar.alif-maqsura.final', 'المستشفي', 'المستشفى'),
    ('زار المسجد الأقصي.', 'ar.alif-maqsura.final', 'الأقصي', 'الأقصى'),
    ('شارك في المنتدي.', 'ar.alif-maqsura.final', 'المنتدي', 'المنتدى'),
    ('جلسنا في المقهي.', 'ar.alif-maqsura.final', 'المقهي', 'المقهى'),
    ('عمت الفوضي المكان.', 'ar.alif-maqsura.final', 'الفوضي', 'الفوضى'),
    // ar.ya.final
    ('الكتاب فى الحقيبة.', 'ar.ya.final', 'فى', 'في'),
    ('الرجل الذى جاء.', 'ar.ya.final', 'الذى', 'الذي'),
    ('هى معلمة.', 'ar.ya.final', 'هى', 'هي'),
    // ar.punctuation.arabic-mark
    ('جاء أحمد, وذهب علي.', 'ar.punctuation.arabic-mark', ',', '،'),
    ('هل أنت بخير?', 'ar.punctuation.arabic-mark', '?', '؟'),
    ('قرأ الكتاب; ثم نام.', 'ar.punctuation.arabic-mark', ';', '؛'),
    // ar.punctuation.space-before
    ('جاء أحمد ، وذهب علي.', 'ar.punctuation.space-before', ' ', ''),
    ('هل أنت بخير ؟', 'ar.punctuation.space-before', ' ', ''),
    // ar.punctuation.space-after
    ('جاء أحمد،وذهب علي.', 'ar.punctuation.space-after', '', ' '),
    // ar.style.tatweel
    ('هذا كتـــاب جميل.', 'ar.style.tatweel', 'ـــ', ''),
    // ar.repetition.word
    ('جلس في في الحديقة.', 'ar.repetition.word', 'في في', 'في'),
    (
      'هذا هو الكتاب الذي الذي قرأته.',
      'ar.repetition.word',
      'الذي الذي',
      'الذي',
    ),
    // ar.spacing.conjunction-waw
    ('جاء أحمد و هو يبتسم.', 'ar.spacing.conjunction-waw', 'و ', 'و'),
    ('اشترى خبزا و  حليبا.', 'ar.spacing.conjunction-waw', 'و  ', 'و'),
    // ar.digits.mixed
    ('ولد عام ١٩9٠.', 'ar.digits.mixed', '١٩9٠', '١٩٩٠'),
    ('الصفحة 1٢.', 'ar.digits.mixed', '1٢', '١٢'),
  ];

  for (final (String text, String rule, String original, String replacement)
      in positives) {
    test('$rule: $text', () async {
      final List<OfficeProofingFinding> findings = await check(text);
      final List<OfficeProofingFinding> matching = <OfficeProofingFinding>[
        for (final OfficeProofingFinding f in findings)
          if (f.ruleId == rule) f,
      ];
      expect(
        matching,
        hasLength(1),
        reason: findings.map((f) => f.ruleId).join(','),
      );
      final OfficeProofingFinding finding = matching.single;
      expect(finding.originalText, original);
      expect(text.substring(finding.start, finding.end), original);
      expect(finding.replacements.first, replacement);
      expect(finding.message, isNotEmpty);
    });
  }

  // Correct or deliberately ambiguous text: no finding at all.
  const List<String> controls = <String>[
    'ذهب الولد إلى المدرسة صباحا، ثم عاد إلى البيت.',
    'أعرف أن الطريق طويل، وإن كان ممتعا.',
    'قال ابن خلدون إن العمران البشري ضروري.',
    'استخدم اسم المستخدم وكلمة المرور.',
    'كتب المدرّس على السبورة ثم جلس.',
    // hamzat al-wasl words keep a plain alif
    'انطلق القطار في الموعد، واستمر السفر ساعتين.',
    'امرأة تقرأ كتابا في المكتبة.',
    // indefinite noun + possessive pronoun is not flagged (مدرسه = his teacher)
    'زار الطالب مدرسه في البيت.',
    // the name Ali and other words outside the closed lists
    'جاء علي مع أخيه.',
    'كل من عليها فان.',
    // emphatic repetition of content words is allowed
    'الجو جميل جدا جدا اليوم.',
    'تقدم رويدا رويدا.',
    // waw attached, and waw as a list letter
    'جاء أحمد وهو يبتسم.',
    'الخيارات: أ، ب، و.',
    // consistent digits
    'ولد عام ١٩٩٠، وفي عام 2024 تخرج.',
    'السعر 3,5 دينار.',
    // Latin text with Latin punctuation
    'He said: hello, world? Yes; indeed.',
    // links, email and code spans are protected
    'زر الموقع https://example.com/الى?x=1 الآن.',
    'راسل info@example.org اليوم.',
    'نفذ الأمر `فى الى` في الطرفية.',
    'الحياة جميلة والصلاة عماد الدين.',
    'الله أكبر.',
    'التوجيه والتنبيه مهمان.',
    // Combining hamza is part of the spelling, not an optional vowel mark.
    'ذهب ا\u0655لى البيت.',
    'ا\u0654نا في البيت.',
    // Arabic substrings in mixed-script identifiers are not prose words.
    'المعرف xالى واسم الىbar.',
    'المعرف 123الى وآخر الى123.',
    'القيمة _الى أو الى_.',
    'القيمة x\u200Dالى.',
    'fooو هو',
    'و المدرسهX',
    // لان is also the valid verb "became soft", not necessarily لأن.
    'لان الحديد بالحرارة.',
  ];
  for (final String text in controls) {
    test('control has no finding: $text', () async {
      final List<OfficeProofingFinding> findings = await check(text);
      expect(
        findings.map((f) => '${f.ruleId}:${f.originalText}').toList(),
        isEmpty,
      );
    });
  }

  test('ambiguous hamza words offer both spellings', () async {
    final List<OfficeProofingFinding> findings = await check(
      'قال ان الدرس سهل.',
    );
    expect(findings.single.replacements, <String>['أن', 'إن']);
    final List<OfficeProofingFinding> imam = await check(
      'صلى خلف امام المسجد.',
    );
    expect(imam.single.replacements, <String>['أمام', 'إمام']);
  });

  test('mixed digits offer both consistent spellings', () async {
    final List<OfficeProofingFinding> findings = await check('رقم 1٢3.');
    expect(findings.single.replacements, <String>['١٢٣', '123']);
  });

  test('offsets are original UTF-16 offsets plus startOffset', () async {
    const String text = 'مرحبا 😀 ذهب الى البيت.';
    final List<OfficeProofingFinding> findings = await check(
      text,
      startOffset: 100,
    );
    final OfficeProofingFinding finding = findings.single;
    expect(finding.start, 100 + text.indexOf('الى'));
    expect(finding.end, finding.start + 3);
  });

  for (final (String name, String text) in <(String, String)>[
    ('hamza above', 'ا\u0654ين الكتاب؟'),
    ('hamza below', 'ذهب ا\u0655لى البيت.'),
    ('maddah above', 'ا\u0653ن الأوان.'),
  ]) {
    test('correct decomposed $name remains unchanged', () async {
      final ArabicWritingRulesProvider provider = ArabicWritingRulesProvider();
      final OfficeProofingResult result = await provider.check(request(text));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.request.text, text);
      expect(result.findings, isEmpty);
    });
  }

  test('correction offsets preserve preceding decomposed spelling', () async {
    const String text =
        '😀 ا\u0653ن الأوان؛ ا\u0654ين الكتاب؟ ذهب ا\u0655لى المدرسه.';
    const int startOffset = 100;
    final List<OfficeProofingFinding> findings = await check(
      text,
      startOffset: startOffset,
    );
    final OfficeProofingFinding finding = findings.single;
    expect(finding.ruleId, 'ar.ta-marbuta.final');
    expect(finding.originalText, 'المدرسه');
    expect(finding.start, startOffset + text.indexOf('المدرسه'));
    expect(finding.end, finding.start + 'المدرسه'.length);
    expect(finding.replacements, <String>['المدرسة']);
    expect(
      text.replaceRange(
        finding.start - startOffset,
        finding.end - startOffset,
        finding.replacements.single,
      ),
      '😀 ا\u0653ن الأوان؛ ا\u0654ين الكتاب؟ ذهب ا\u0655لى المدرسة.',
    );
  });

  test('ignored rule ids suppress findings', () async {
    final List<OfficeProofingFinding> findings = await check(
      'ذهب الى المدرسه.',
      ignored: <String>{'ar.hamza.initial'},
    );
    expect(findings.map((f) => f.ruleId), <String>['ar.ta-marbuta.final']);
  });

  test('language support: Arabic-script Arabic only', () async {
    final ArabicWritingRulesProvider provider = ArabicWritingRulesProvider();
    expect(provider.supportsLanguage('ar'), isTrue);
    expect(provider.supportsLanguage('ar-SA'), isTrue);
    expect(provider.supportsLanguage('ar_EG'), isTrue);
    expect(provider.supportsLanguage('ar-Arab-MA'), isTrue);
    expect(provider.supportsLanguage('ar-Latn'), isFalse);
    expect(provider.supportsLanguage('de-DE'), isFalse);
    expect(provider.supportsLanguage('fa-IR'), isFalse);
    final OfficeProofingResult german = await provider.check(
      request('ذهب الى البيت.', language: 'de-DE'),
    );
    expect(german.status, OfficeProofingStatus.unsupported);
    expect(german.findings, isEmpty);
  });

  test('every rule id is declared', () async {
    final Set<String> seen = <String>{
      for (final (_, String rule, _, _) in positives) rule,
    };
    expect(seen, ArabicWritingRulesProvider.ruleIds);
  });

  // These marks form letters; erasing them can invent a missing-hamza error
  // and then preserve the original mark alongside a second, precomposed hamza.
  for (final (String mark, String text) in <(String, String)>[
    ('U+0653 madda', 'ا\u0653نا'),
    ('U+0654 hamza above', 'ا\u0654ن'),
    ('U+0655 hamza below', 'ا\u0655لى'),
  ]) {
    test('lexical matching preserves $mark', () async {
      final List<OfficeProofingFinding> findings = await check(text);
      expect(
        findings.map((f) => '${f.ruleId}:${f.replacements}').toList(),
        isEmpty,
      );
    });
  }

  test(
    'decomposed letters preserve adjacent correction UTF-16 offsets',
    () async {
      const String text = '😀 ا\u0655لى، الَى';
      final List<OfficeProofingFinding> findings = await check(
        text,
        startOffset: 100,
      );
      expect(findings, hasLength(1));
      final OfficeProofingFinding finding = findings.single;
      expect(finding.ruleId, 'ar.hamza.initial');
      expect(finding.originalText, 'الَى');
      expect(finding.start, 100 + text.indexOf('الَى'));
      expect(finding.end, 100 + text.length);
      expect(finding.replacements, <String>['إلَى']);
    },
  );

  test('semantic combining marks still allow punctuation checks', () async {
    final List<OfficeProofingFinding> findings = await check(
      'جاء النبا\u0654?',
    );
    expect(findings, hasLength(1));
    expect(findings.single.ruleId, 'ar.punctuation.arabic-mark');
    expect(findings.single.originalText, '?');
    expect(findings.single.replacements, <String>['؟']);
  });

  test('disposed provider is unavailable', () async {
    final ArabicWritingRulesProvider provider = ArabicWritingRulesProvider();
    await provider.dispose();
    final OfficeProofingResult result = await provider.check(
      request('ذهب الى البيت.'),
    );
    expect(result.status, OfficeProofingStatus.unavailable);
  });
}
