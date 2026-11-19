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
  ('اشترى شئ جديد.', 'ar.spelling.common', 'شئ', 'شيء'),
  ('نال الدكتوراة أمس.', 'ar.spelling.common', 'الدكتوراة', 'الدكتوراه'),
  ('لابد من الصبر.', 'ar.spelling.common', 'لابد', 'لا بد'),
  ('حضر رئيس الموسسة.', 'ar.spelling.common', 'الموسسة', 'المؤسسة'),
  ('كان الطريق طويلا والامر صعبا.', 'ar.spelling.common', 'والامر', 'والأمر'),
  ('إنتقل إلى المدينة.', 'ar.spelling.common', 'إنتقل', 'انتقل'),
  ('قرأ القاريء الكتاب.', 'ar.spelling.common', 'القاريء', 'القارئ'),
  ('أعلنت نتائج الأنتخابات.', 'ar.spelling.common', 'الأنتخابات', 'الانتخابات'),
  ('هذة فكرة جيدة.', 'ar.spelling.common', 'هذة', 'هذه'),
  ('حدث ذلك في لحضة.', 'ar.spelling.common', 'لحضة', 'لحظة'),
  ('نرجوا الهدوء.', 'ar.spelling.common', 'نرجوا', 'نرجو'),
  ('ومازال يعمل.', 'ar.spelling.common', 'ومازال', 'وما زال'),
  ('درس بالأضافة إلى عمله.', 'ar.spelling.common', 'بالأضافة', 'بالإضافة'),
  ('تكلم عن التفائل.', 'ar.spelling.common', 'التفائل', 'التفاؤل'),
  ('هذا جزئ صغير.', 'ar.spelling.common', 'جزئ', 'جزء'),
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
  ('سوف لن أتأخر.', 'ar.expression.error', 'سوف لن', 'لن'),
  ('سأل عن ما حدث.', 'ar.expression.error', 'عن ما', 'عمّا'),
  ('أكثر من ما توقعنا.', 'ar.expression.error', 'من ما', 'مما'),
  ('بادئ ذو بدء نشكركم.', 'ar.expression.error', 'بادئ ذو بدء', 'بادئ ذي بدء'),
  ('كما ذكرنا أنفا.', 'ar.expression.error', 'ذكرنا أنفا', 'ذكرنا آنفًا'),
  ('هذا غيظ من فيض.', 'ar.expression.error', 'غيظ من فيض', 'غيض من فيض'),
  (
    'على الرغم أنه تعب استمر.',
    'ar.expression.error',
    'على الرغم أنه',
    'على الرغم من أنه',
  ),
  ('عملوا جنب إلى جنب.', 'ar.expression.error', 'جنب إلى جنب', 'جنبًا إلى جنب'),
  // ar.register.colloquial
  ('ليش تأخرت اليوم؟', 'ar.register.colloquial', 'ليش', 'لماذا'),
  ('هيك قال المعلم.', 'ar.register.colloquial', 'هيك', 'هكذا'),
  ('وعشان كذا تأخرنا.', 'ar.register.colloquial', 'وعشان', 'ولأن'),
  ('أنا عايز أسافر.', 'ar.register.colloquial', 'عايز', 'أريد'),
  ('لسه ما وصل.', 'ar.register.colloquial', 'لسه', 'ما زال'),
  ('معلش تأخرت.', 'ar.register.colloquial', 'معلش', 'لا بأس'),
  ('هذا كتير عليه.', 'ar.register.colloquial', 'كتير', 'كثير'),
  ('ماكو ماء.', 'ar.register.colloquial', 'ماكو', 'لا يوجد'),
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
  ('أكد على أهمية التعليم.', 'ar.usage.expression', 'أكد على', 'أكد'),
  ('قال أنه سيحضر.', 'ar.usage.expression', 'قال أنه', 'قال إنه'),
  ('حدث ذلك على ضوء التقرير.', 'ar.usage.expression', 'على ضوء', 'في ضوء'),
  ('زار العديد من المدن.', 'ar.usage.expression', 'العديد من', 'كثير من'),
  ('انضم للفريق أمس.', 'ar.usage.expression', 'انضم للفريق', null),
  ('لعب دورا كبيرا.', 'ar.usage.expression', 'لعب', 'أدى'),
  ('سنناقش نفس الموضوع.', 'ar.usage.expression', 'نفس الموضوع', 'الموضوع نفسه'),
  ('تخرجت من الجامعة.', 'ar.usage.expression', 'تخرجت من', 'تخرجت في'),
  ('يؤثر على صحته.', 'ar.usage.expression', 'يؤثر على', 'يؤثر في'),
  ('ساهم الجميع في النجاح.', 'ar.usage.word', 'ساهم', 'أسهم'),
  ('هذا قرار هام.', 'ar.usage.word', 'هام', 'مهم'),
  ('عاش لوحده.', 'ar.usage.word', 'لوحده', 'وحده'),
  ('يعاني من مشاكل كثيرة.', 'ar.usage.word', 'مشاكل', 'مشكلات'),
  ('استلم الجائزة.', 'ar.usage.word', 'استلم', 'تسلّم'),
  ('يُعتبر هذا مهما.', 'ar.usage.word', 'يُعتبر', 'يُعدّ'),
  (
    'مما لا شك فيه أن العلم نافع.',
    'ar.style.wordiness',
    'مما لا شك فيه أن',
    'لا شك أن',
  ),
  ('وصلنا في نهاية المطاف.', 'ar.style.wordiness', 'في نهاية المطاف', 'أخيرًا'),
  ('تحسن الوضع بشكل كبير.', 'ar.style.wordiness', 'بشكل كبير', 'كثيرًا'),
  ('وبصورة عامة نجح.', 'ar.style.wordiness', 'وبصورة عامة', 'وعمومًا'),
  ('قام بزيارة المتحف.', 'ar.style.wordiness', 'قام بزيارة', 'زار'),
  ('قامت بتأسيس شركة.', 'ar.style.wordiness', 'قامت بتأسيس', 'أسّست'),
  ('الكتاب عبارة عن قصص.', 'ar.style.wordiness', 'عبارة عن ', ''),
  ('شكراً لك.', 'ar.style.tanwin-placement', 'شكراً', 'شكرًا'),
  ('أرسل لي إيميل.', 'ar.register.loanword', 'إيميل', 'بريد إلكتروني'),
  ('شاهدنا الفيديو معا.', 'ar.register.loanword', 'الفيديو', 'المقطع المرئي'),
  ('ركبنا الأوتوبيس.', 'ar.register.loanword', 'الأوتوبيس', 'الحافلة'),
  ('اشترى كاميرا.', 'ar.register.loanword', 'كاميرا', 'آلة تصوير'),
  ('خاض تجربة جديدة.', 'ar.hint.vowelling', 'تجربة', 'تَجْرِبة'),
  ('نجحت التجربة.', 'ar.hint.vowelling', 'التجربة', 'الت\u064E\u0651جْرِبة'),
  ('أعجبتني والقصة أيضا.', 'ar.hint.vowelling', 'والقصة', 'والقِصّة'),
  ('تعلم مهارة جديدة.', 'ar.hint.vowelling', 'مهارة', 'مَهارة'),
  ('وقعت معركة كبيرة.', 'ar.hint.vowelling', 'معركة', 'مَعْرَكة'),
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
  // proper names and valid words that resemble list entries
  'زار مبنى بلدية المدينة.',
  'وصل إلى مدينة كانو في نيجيريا.',
  'زار جزيرة فين الدنماركية.',
  'تحدث ديالو في المؤتمر.',
  'رواه ابن بكير عن الليث.',
  'عاش في دي وين سنوات.',
  'فاز الملاكم فازيك.',
  'يعرف من ما زال حيا.',
  'سافر إلى مدينة ليه.',
  'لعبت هيدي في الفيلم.',
  'أكد على أهمية التعليم.',
  'قال أنه سيحضر.',
  'تحسن الوضع بشكل كبير.',
  'شاهدنا الفيديو معا.',
];

/// Valid text for the opt-in rules, checked with every opt-in rule enabled.
const List<String> optionalControls = <String>[
  'قال إنه سيحضر.',
  'أكد أهمية التعليم.',
  'تخرج من البيت مسرعة.',
  'سعى ليحقق حلمه.',
  'زار المتحف.',
  'تحسن الوضع كثيرًا.',
  'شارك في المؤتمر نفسه.',
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
  group('semantic combining marks in phrase matching', () {
    for (final (String name, String mark) in <(String, String)>[
      ('maddah above', '\u0653'),
      ('hamza above', '\u0654'),
      ('hamza below', '\u0655'),
    ]) {
      test('phrase matching retains $name', () async {
        final String text = 'ا$markختار بين كتابين.';
        expect(
          await check(text, optional: <String>{'ar.usage.expression'}),
          isEmpty,
        );
      });
    }

    test(
      'precomposed phrase controls still produce the intended suggestion',
      () async {
        for (final String text in <String>[
          'أختار بين كتابين.',
          'أَختارُ بينَ كتابين.',
        ]) {
          final List<OfficeProofingFinding> findings = await check(
            text,
            optional: <String>{'ar.usage.expression'},
          );
          expect(findings, hasLength(1));
          expect(findings.single.ruleId, 'ar.usage.expression');
          expect(findings.single.replacements, <String>['أختار من بين']);
        }
      },
    );

    test('adjacent phrase keeps UTF-16 offsets after semantic marks', () async {
      const String text = '😀 ا\u0654ختار بين كتابين؛ درس كل حالة على حدى.';
      const int startOffset = 100;
      final List<OfficeProofingFinding> findings = await check(
        text,
        startOffset: startOffset,
        optional: <String>{'ar.usage.expression'},
      );
      expect(findings, hasLength(1));
      final OfficeProofingFinding finding = findings.single;
      expect(finding.ruleId, 'ar.expression.error');
      expect(finding.originalText, 'على حدى');
      expect(finding.start, startOffset + text.indexOf('على حدى'));
      expect(finding.end, finding.start + 'على حدى'.length);
      expect(finding.replacements, <String>['على حدة']);
      expect(
        text.replaceRange(
          finding.start - startOffset,
          finding.end - startOffset,
          finding.replacements.single,
        ),
        '😀 ا\u0654ختار بين كتابين؛ درس كل حالة على حدة.',
      );
    });
  });

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
            arabicExtendedOptionalRuleIds.length +
            arabicGrammarDefaultRuleIds.length +
            arabicGrammarOptionalRuleIds.length,
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

  group('integration token boundaries', () {
    for (final String text in <String>[
      'المعرف xسيما محفوظ.',
      'المعرف سيماbar محفوظ.',
      'المعرف _سيما محفوظ.',
      'المعرف x\u200Dسيما محفوظ.',
      'المعرف سيما\u0654 محفوظ.',
      'المعرف xسوف سيذهب.',
      'المعرف سوف سيذهبX.',
      'المعرف xالأحد 5 مارس 2020.',
      'المعرف الأحد 5 مارس 2020x.',
      'المعرف xعام 20244.',
      'المعرف عام 20244x.',
    ]) {
      test('does not rewrite part of a token: $text', () async {
        final List<OfficeProofingFinding> findings = await check(text);
        expect(
          findings.map((f) => '${f.ruleId}:${f.originalText}').toList(),
          isEmpty,
        );
      });
    }
  });

  group('word lists', () {
    final List<ArabicWordListForTesting> lists = arabicWordListsForTesting();

    test('lists keep their expanded sizes', () {
      final Map<String, int> sizes = <String, int>{
        for (final ArabicWordListForTesting l in lists)
          l.ruleId: l.entries.length,
      };
      expect(sizes['ar.spelling.common'], greaterThanOrEqualTo(600));
      expect(sizes['ar.hamza.initial'], greaterThanOrEqualTo(200));
      expect(sizes['ar.ta-marbuta.final'], greaterThanOrEqualTo(250));
      expect(sizes['ar.alif-maqsura.final'], greaterThanOrEqualTo(40));
      expect(sizes['ar.register.colloquial'], greaterThanOrEqualTo(140));
      expect(sizes['ar.register.loanword'], greaterThanOrEqualTo(200));
      expect(sizes['ar.usage.word'], greaterThanOrEqualTo(70));
      expect(sizes['ar.hint.vowelling'], greaterThanOrEqualTo(140));
      final Map<String, int> phrases = <String, int>{};
      for (final (String id, _, _) in arabicPhraseListsForTesting()) {
        phrases[id] = (phrases[id] ?? 0) + 1;
      }
      expect(phrases['ar.expression.error'], greaterThanOrEqualTo(30));
      expect(phrases['ar.usage.expression'], greaterThanOrEqualTo(100));
      expect(phrases['ar.style.wordiness'], greaterThanOrEqualTo(100));
    });

    test('keys are bare and suggestions are non-empty strings', () {
      final RegExp harakat = RegExp('[\u064B-\u0652\u0670\u0640]');
      for (final ArabicWordListForTesting l in lists) {
        for (final MapEntry<String, List<String>> e in l.entries.entries) {
          expect(harakat.hasMatch(e.key), isFalse, reason: e.key);
          for (final String r in e.value) {
            expect(r.trim(), isNotEmpty, reason: '${l.ruleId}:${e.key}');
            expect(r, isNot(e.key), reason: '${l.ruleId}:${e.key}');
          }
        }
      }
    });

    test('no suggestion is itself flagged by a default rule', () async {
      final ArabicWritingRulesProvider provider = ArabicWritingRulesProvider();
      final Map<String, String> suggestions = <String, String>{
        for (final ArabicWordListForTesting l in lists)
          for (final MapEntry<String, List<String>> e in l.entries.entries)
            for (final String r in e.value) r: '${l.ruleId}:${e.key}',
        for (final (String id, String pattern, List<String> replacements)
            in arabicPhraseListsForTesting())
          for (final String r in replacements)
            if (r.trim().isNotEmpty && !r.contains('{')) r: '$id:$pattern',
      };
      final List<String> failures = <String>[];
      for (final MapEntry<String, String> e in suggestions.entries) {
        final OfficeProofingResult result = await provider.check(
          OfficeProofingRequest(
            documentId: 'd',
            blockId: 'b',
            revision: 1,
            text: e.key,
            language: 'ar',
          ),
        );
        if (result.findings.isNotEmpty) {
          failures.add(
            '${e.value} -> ${e.key}: '
            '${result.findings.map((f) => f.ruleId).join(',')}',
          );
        }
      }
      expect(failures, isEmpty);
      expect(suggestions.length, greaterThan(1500));
    });

    test('no form is in two lists with conflicting suggestions', () {
      final Map<String, (String, List<String>)> seen =
          <String, (String, List<String>)>{};
      final List<String> conflicts = <String>[];
      for (final ArabicWordListForTesting l in lists) {
        for (final MapEntry<String, List<String>> e in l.entries.entries) {
          for (final String prefix in l.prefixes) {
            final Map<String, List<String>> forms = <String, List<String>>{
              '$prefix${e.key}': <String>[
                for (final String r in e.value) '$prefix$r',
              ],
              if (l.article)
                '$prefixال${e.key}': <String>[
                  for (final String r in e.value) '$prefixال$r',
                ],
            };
            for (final MapEntry<String, List<String>> f in forms.entries) {
              final (String, List<String>)? other = seen[f.key];
              if (other == null) {
                seen[f.key] = (l.ruleId, f.value);
              } else if (other.$1 != l.ruleId &&
                  other.$2.join('|') != f.value.join('|')) {
                conflicts.add(
                  '${f.key}: ${other.$1} ${other.$2} vs ${l.ruleId} ${f.value}',
                );
              }
            }
          }
        }
      }
      expect(conflicts, isEmpty);
    });

    test('every word list has positive cases', () {
      final Set<String> covered = <String>{
        for (final (_, String rule, _, _) in defaultPositives) rule,
        for (final (_, String rule, _, _) in optionalPositives) rule,
        // ar.hamza.initial, ar.ta-marbuta.final, ar.alif-maqsura.final and
        // ar.ya.final are covered in arabic_writing_rules_test.dart.
        'ar.hamza.initial',
        'ar.ta-marbuta.final',
        'ar.alif-maqsura.final',
        'ar.ya.final',
      };
      for (final ArabicWordListForTesting l in lists) {
        expect(covered, contains(l.ruleId));
      }
    });
  });
}
