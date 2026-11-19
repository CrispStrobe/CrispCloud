import 'package:characters/characters.dart';

import 'arabic_morphology.dart';
import 'office_proofing.dart';
import 'proofing_text_ranges.dart';

part 'arabic_extended_rules.dart';
part 'arabic_grammar_rules.dart';

/// Independently authored Modern Standard Arabic writing checks.
///
/// The word lists and messages were written for Quds from general knowledge
/// of standard Arabic orthography; no external rule set was used. Every
/// lexical rule is a closed, reviewable list: words whose correct form depends
/// on syntax or meaning are either offered with several suggestions or left
/// out (for example `علي` is also the name Ali, `فان` is also "perishing",
/// and `لان` is also the verb "became soft").
///
/// Matching ignores vowel marks and tatweel (U+0640), while combining madda
/// and hamza (U+0653–U+0655) remain part of the spelling. Findings always cover
/// the original source text and suggestions keep the writer's harakat,
/// replacing only the corrected letters. Offsets are original UTF-16 offsets;
/// the text is never rewritten. Lexical checks respect mixed-script token
/// boundaries. Links, email addresses and closed backtick spans are excluded.
class ArabicWritingRulesProvider extends OfficeProofingProvider {
  /// [enabledOptionalRuleIds] opts in to rules from
  /// [arabicExtendedOptionalRuleIds] (prescriptive usage, vowelling hints and
  /// other convention-dependent checks) and [arabicGrammarOptionalRuleIds];
  /// all other rules run by default.
  ///
  /// [morphology] feeds the morphology-based grammar rules
  /// (`arabic_grammar_rules.dart`); with the default
  /// [UnavailableArabicMorphology] those rules stay silent.
  ArabicWritingRulesProvider({
    Set<String> enabledOptionalRuleIds = const <String>{},
    this.morphology = const UnavailableArabicMorphology(),
  }) : enabledOptionalRuleIds = Set<String>.unmodifiable(
         enabledOptionalRuleIds.intersection(_optionalRuleIds),
       );

  final Set<String> enabledOptionalRuleIds;

  /// Morphological analyzer for the grammar rules.
  final ArabicMorphology morphology;

  static const Set<String> _optionalRuleIds = <String>{
    ...arabicExtendedOptionalRuleIds,
    ...arabicGrammarOptionalRuleIds,
  };
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

  /// Every rule id: the original set, the default-on extension and the
  /// opt-in extension (see `arabic_extended_rules.dart`).
  static const Set<String> allRuleIds = <String>{
    ...ruleIds,
    ...arabicExtendedDefaultRuleIds,
    ...arabicExtendedOptionalRuleIds,
    ...arabicGrammarDefaultRuleIds,
    ...arabicGrammarOptionalRuleIds,
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
    'انتما': <String>['أنتما'],
    'انتن': <String>['أنتن'],
    'اننا': <String>['أننا', 'إننا'],
    'انني': <String>['أنني', 'إنني'],
    'انك': <String>['أنك', 'إنك'],
    'انكم': <String>['أنكم', 'إنكم'],
    'انهم': <String>['أنهم', 'إنهم'],
    'انهما': <String>['أنهما', 'إنهما'],
    'لانهم': <String>['لأنهم'],
    'لانك': <String>['لأنك'],
    'لاننا': <String>['لأننا'],
    'لانني': <String>['لأنني'],
    'لاني': <String>['لأني'],
    'لانهما': <String>['لأنهما'],
    'والا': <String>['وإلا', 'وألا'],
    'اذن': <String>['إذن', 'أذن'],
    'واما': <String>['وأما', 'وإما'],
    'فاما': <String>['فأما', 'فإما'],
    'اينما': <String>['أينما'],
    'انما': <String>['إنما'],
    'وانما': <String>['وإنما'],
    'اليهما': <String>['إليهما'],
    'اليكم': <String>['إليكم'],
    'الينا': <String>['إلينا'],
    'اليهن': <String>['إليهن'],
    'اولا': <String>['أولا'],
    'اولى': <String>['أولى'],
    'واول': <String>['وأول'],
    'واكثر': <String>['وأكثر'],
    'واخرى': <String>['وأخرى'],
    'وايضا': <String>['وأيضا'],
    'وامام': <String>['وأمام'],
    'واين': <String>['وأين'],
    'وانه': <String>['وأنه', 'وإنه'],
    'وانها': <String>['وأنها', 'وإنها'],
    'وانهم': <String>['وأنهم', 'وإنهم'],
    'فانه': <String>['فإنه', 'فأنه'],
    'فانها': <String>['فإنها', 'فأنها'],
    'فانهم': <String>['فإنهم', 'فأنهم'],
    'لاجل': <String>['لأجل'],
    'لاول': <String>['لأول'],
    'لاكثر': <String>['لأكثر'],
    'احيانا': <String>['أحيانا'],
    'ابدا': <String>['أبدا'],
    'اخيرا': <String>['أخيرا'],
    'اثر': <String>['أثر', 'إثر'],
    'اجل': <String>['أجل'],
    'انذاك': <String>['آنذاك'],
    'اخذ': <String>['أخذ'],
    'اخذت': <String>['أخذت'],
    'ادى': <String>['أدى'],
    'ادت': <String>['أدت'],
    'اراد': <String>['أراد'],
    'ارادت': <String>['أرادت'],
    'اريد': <String>['أريد'],
    'ارسل': <String>['أرسل'],
    'ارسلت': <String>['أرسلت'],
    'اشار': <String>['أشار'],
    'اشارت': <String>['أشارت'],
    'اصبحت': <String>['أصبحت'],
    'اصبحوا': <String>['أصبحوا'],
    'اصدر': <String>['أصدر'],
    'اصدرت': <String>['أصدرت'],
    'اضاف': <String>['أضاف'],
    'اضافت': <String>['أضافت'],
    'اكد': <String>['أكد'],
    'اكدت': <String>['أكدت'],
    'اعلنت': <String>['أعلنت'],
    'امكن': <String>['أمكن'],
    'اجاب': <String>['أجاب'],
    'اجابت': <String>['أجابت'],
    'اجرى': <String>['أجرى'],
    'اجرت': <String>['أجرت'],
    'اكمل': <String>['أكمل'],
    'انهى': <String>['أنهى'],
    'القى': <String>['ألقى'],
    'اقام': <String>['أقام'],
    'اقامت': <String>['أقامت'],
    'اعاد': <String>['أعاد'],
    'اعادت': <String>['أعادت'],
    'اوضح': <String>['أوضح'],
    'اوضحت': <String>['أوضحت'],
    'اعرب': <String>['أعرب'],
    'اعطى': <String>['أعطى'],
    'اظن': <String>['أظن'],
    'اقول': <String>['أقول'],
    'استطيع': <String>['أستطيع'],
    'احب': <String>['أحب'],
    'اخر': <String>['آخر', 'أخر'],
    'اخير': <String>['أخير'],
    'اخيرة': <String>['أخيرة'],
    'اخبار': <String>['أخبار'],
    'اخت': <String>['أخت'],
    'اخي': <String>['أخي'],
    'اخوة': <String>['إخوة', 'أخوة'],
    'اخوان': <String>['إخوان', 'أخوان'],
    'اخطاء': <String>['أخطاء'],
    'ارض': <String>['أرض'],
    'اسرة': <String>['أسرة'],
    'اسس': <String>['أسس'],
    'اساس': <String>['أساس'],
    'اساسي': <String>['أساسي'],
    'اساسية': <String>['أساسية'],
    'اسبوع': <String>['أسبوع'],
    'اسابيع': <String>['أسابيع'],
    'اسعار': <String>['أسعار'],
    'اسلوب': <String>['أسلوب'],
    'اسماء': <String>['أسماء'],
    'اسلام': <String>['إسلام'],
    'اسلامي': <String>['إسلامي'],
    'اسلامية': <String>['إسلامية'],
    'اشارة': <String>['إشارة'],
    'اشخاص': <String>['أشخاص'],
    'اشياء': <String>['أشياء'],
    'اصل': <String>['أصل'],
    'اضافة': <String>['إضافة'],
    'اطار': <String>['إطار'],
    'اطفال': <String>['أطفال'],
    'اعداد': <String>['أعداد', 'إعداد'],
    'اعضاء': <String>['أعضاء'],
    'اعلى': <String>['أعلى'],
    'اعمال': <String>['أعمال'],
    'اغلب': <String>['أغلب'],
    'افضل': <String>['أفضل'],
    'افراد': <String>['أفراد'],
    'افكار': <String>['أفكار'],
    'الف': <String>['ألف'],
    'امر': <String>['أمر'],
    'امور': <String>['أمور'],
    'امير': <String>['أمير'],
    'اميرة': <String>['أميرة'],
    'امين': <String>['أمين', 'آمين'],
    'امة': <String>['أمة'],
    'امم': <String>['أمم'],
    'امن': <String>['أمن', 'آمن'],
    'انشاء': <String>['إنشاء'],
    'انتاج': <String>['إنتاج'],
    'انسان': <String>['إنسان'],
    'انجاز': <String>['إنجاز'],
    'ايام': <String>['أيام'],
    'اهل': <String>['أهل'],
    'اهلا': <String>['أهلا'],
    'اهمية': <String>['أهمية'],
    'اهداف': <String>['أهداف'],
    'احدى': <String>['إحدى'],
    'ادارة': <String>['إدارة'],
    'اذاعة': <String>['إذاعة'],
    'اصلاح': <String>['إصلاح'],
    'اعلام': <String>['إعلام', 'أعلام'],
    'اعلان': <String>['إعلان'],
    'امكانية': <String>['إمكانية'],
    'ايجاد': <String>['إيجاد'],
    'اقامة': <String>['إقامة'],
    'الغاء': <String>['إلغاء'],
    'احصاء': <String>['إحصاء'],
    'اجراء': <String>['إجراء', 'أجراء'],
    'اجراءات': <String>['إجراءات'],
    'اجابة': <String>['إجابة'],
    'ارسال': <String>['إرسال'],
    'اطلاق': <String>['إطلاق'],
    'اعادة': <String>['إعادة'],
    'اقرب': <String>['أقرب'],
    'اسرع': <String>['أسرع'],
    'اطول': <String>['أطول'],
    'اعظم': <String>['أعظم'],
    'اصغر': <String>['أصغر'],
    'ادنى': <String>['أدنى'],
    'اقصى': <String>['أقصى'],
    'اسفل': <String>['أسفل'],
    'اوسع': <String>['أوسع'],
    'اشد': <String>['أشد'],
    'احسن': <String>['أحسن'],
    'اجمل': <String>['أجمل'],
    'اوائل': <String>['أوائل'],
    'اواخر': <String>['أواخر'],
    'ابناء': <String>['أبناء'],
    'ابو': <String>['أبو'],
    'اية': <String>['آية', 'أية'],
    'اسيا': <String>['آسيا'],
    'اذار': <String>['آذار'],
    'ادم': <String>['آدم'],
    'امريكا': <String>['أمريكا'],
    'امريكي': <String>['أمريكي'],
    'امريكية': <String>['أمريكية'],
    'اوروبا': <String>['أوروبا'],
    'اوروبي': <String>['أوروبي'],
    'اوروبية': <String>['أوروبية'],
    'افريقيا': <String>['أفريقيا', 'إفريقيا'],
    'ايران': <String>['إيران'],
    'ايطاليا': <String>['إيطاليا'],
    'اسبانيا': <String>['إسبانيا'],
    'المانيا': <String>['ألمانيا'],
    'انجلترا': <String>['إنجلترا'],
    'اندونيسيا': <String>['إندونيسيا'],
    'اثيوبيا': <String>['إثيوبيا'],
    'اذربيجان': <String>['أذربيجان'],
    'افغانستان': <String>['أفغانستان'],
    'اوكرانيا': <String>['أوكرانيا'],
    'اسرائيل': <String>['إسرائيل'],
    'ابراهيم': <String>['إبراهيم'],
    'احمد': <String>['أحمد'],
    'اسماعيل': <String>['إسماعيل'],
    'اسحاق': <String>['إسحاق'],
    'اسامة': <String>['أسامة'],
    'ايمن': <String>['أيمن'],
    'اشرف': <String>['أشرف'],
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
    'مؤسس',
    'منظم',
    'مملك',
    'جمعي',
    'عاصم',
    'محافظ',
    'قري',
    'بلدي',
    'حرك',
    'ثور',
    'حرب',
    'معرك',
    'قو',
    'فتر',
    'مد',
    'سن',
    'صف',
    'ذاكر',
    'نظري',
    'عملي',
    'عمل',
    'قيم',
    'كمي',
    'نسب',
    'مساح',
    'طاق',
    'صناع',
    'زراع',
    'تجار',
    'سياح',
    'صح',
    'تربي',
    'تنمي',
    'رواي',
    'قصيد',
    'مجل',
    'صحيف',
    'جريد',
    'نشر',
    'شبك',
    'خدم',
    'رحل',
    'زيار',
    'هجر',
    'كتاب',
    'قراء',
    'عائل',
    'أسر',
    'مرأ',
    'فتا',
    'زكا',
    'مبارا',
    'نجا',
    'قنا',
    'مساوا',
    'معانا',
    'مأسا',
    'غاي',
    'بداي',
    'نهاي',
    'حماي',
    'رعاي',
    'ولاي',
    'هوي',
    'آي',
    'أهمي',
    'أغلبي',
    'أكثري',
    'أقلي',
    'حري',
    'ديمقراطي',
    'إنساني',
    'إسلامي',
    'مسيحي',
    'يهودي',
    'وطني',
    'دولي',
    'محلي',
    'عالمي',
    'اقتصادي',
    'اجتماعي',
    'ثقافي',
    'تاريخي',
    'علمي',
    'أدبي',
    'فني',
    'رسمي',
    'شعبي',
    'رئيسي',
    'أساسي',
    'مصري',
    'سوري',
    'سعودي',
    'عراقي',
    'لبناني',
    'فلسطيني',
    'أمريكي',
    'أوروبي',
    'بريطاني',
    'فرنسي',
    'إنجليزي',
    'متحد',
    'سابق',
    'لاحق',
    'قادم',
    'ماضي',
    'حالي',
    'تالي',
    'أخير',
    'ثاني',
    'ثالث',
    'رابع',
    'خامس',
    'كامل',
    'مختلف',
    'مختص',
    'مستقل',
    'مشترك',
    'متوسط',
    'مركزي',
    'شمالي',
    'جنوبي',
    'شرقي',
    'غربي',
    'مقدس',
    'مكرم',
    'منور',
    'كعب',
    'جمع',
    'ظاهر',
    'قاعد',
    'قاهر',
    'إسكندري',
    'خليف',
    'كلي',
    'شرط',
    'قياد',
    'رئاس',
    'وظيف',
    'خبر',
    'لحظ',
    'خط',
    'قم',
    'جن',
    'أم',
    'ملك',
    'أمير',
    'سيد',
    'زوج',
    'طفل',
    'سلط',
    'ثرو',
    'قضي',
    'أزم',
    'حادث',
    'كارث',
    'جريم',
    'محاكم',
    'محكم',
    'عقوب',
    'حمل',
    'صفق',
    'مجموع',
    'منظوم',
    'جه',
    'وجه',
    'ناحي',
    'وسيل',
    'رغب',
    'حاج',
    'فرص',
    'مهم',
    'خطو',
    'نقط',
    'لائح',
    'قائم',
    'صفح',
    'نسخ',
    'طبع',
    'ترجم',
    'لهج',
    'جمل',
    'عبار',
    'ثانوي',
    'ابتدائي',
    'إعدادي',
    'ساح',
    'حديق',
    'غاب',
    'بحير',
    'جزير',
    'شجر',
    'زهر',
    'ثمر',
    'بيئ',
    'طبيع',
    'حرار',
    'رطوب',
    'سرع',
    'دق',
    'جود',
    'تقني',
    'شاش',
    'لوح',
    'إجاب',
    'أسئل',
    'مقال',
    'مقدم',
    'خاتم',
    'نظر',
    'رؤي',
    'معرف',
    'ثق',
    'محب',
    'رحم',
    'نعم',
    'سعاد',
    'راح',
    'صداق',
    'علاق',
    'مسؤولي',
    'عدال',
    'حكم',
    'شجاع',
    'كرام',
    'سلام',
    'أمان',
    'قدر',
    'إراد',
    'تكلف',
    'ميزاني',
    'صحاف',
    'إذاع',
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
    'منتدي': 'منتدى',
    'المنتدي': 'المنتدى',
    'ملتقي': 'ملتقى',
    'الملتقي': 'الملتقى',
    'مقهي': 'مقهى',
    'المقهي': 'المقهى',
    'مأوي': 'مأوى',
    'المأوي': 'المأوى',
    'مغزي': 'مغزى',
    'المغزي': 'المغزى',
    'مصطفي': 'مصطفى',
    'موسي': 'موسى',
    'عيسي': 'عيسى',
    'مرتضي': 'مرتضى',
    'الكبري': 'الكبرى',
    'الصغري': 'الصغرى',
    'الأخري': 'الأخرى',
    'أخري': 'أخرى',
    'اخري': 'أخرى',
    'إحدي': 'إحدى',
    'احدي': 'إحدى',
    'الفصحي': 'الفصحى',
    'القصوي': 'القصوى',
    'الأقصي': 'الأقصى',
    'الاقصي': 'الأقصى',
    'الأعلي': 'الأعلى',
    'الأدني': 'الأدنى',
    'شتي': 'شتى',
    'فوضي': 'فوضى',
    'الفوضي': 'الفوضى',
    'الشكوي': 'الشكوى',
    'شكوي': 'شكوى',
    'فتوي': 'فتوى',
    'الفتوي': 'الفتوى',
    'جدوي': 'جدوى',
    'الجدوي': 'الجدوى',
    'نجوي': 'نجوى',
    'العدوي': 'العدوى',
    'الضحي': 'الضحى',
    'أنثي': 'أنثى',
    'الأنثي': 'الأنثى',
    'انثي': 'أنثى',
    'الانثي': 'الأنثى',
    'المتوفي': 'المتوفى',
    'متوفي': 'متوفى',
    'الحلوي': 'الحلوى',
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
  static const String _wordContinuation = r'\p{L}\p{M}\p{N}\p{Pc}\u200C\u200D';
  static final RegExp _word = RegExp(
    '(?<![$_wordContinuation])[$_letters][$_letters$_marks]*'
    '(?![$_wordContinuation])',
    unicode: true,
  );
  static final RegExp _mark = RegExp('[$_marks]');
  // Combining madda/hamza are letter distinctions, not optional vowels.
  static final RegExp _comparisonMark = RegExp(
    r'[\u064B-\u0652\u0656-\u065F\u0670\u0640]',
  );
  static final RegExp _arabicLetter = RegExp('[$_letters]');

  /// The bare spelling and, for each bare letter, its source offset.
  static (String, List<int>) _bare(String word) {
    final StringBuffer bare = StringBuffer();
    final List<int> positions = <int>[];
    for (int i = 0; i < word.length; i++) {
      final String unit = word[i];
      if (_comparisonMark.hasMatch(unit)) continue;
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
      '(?<![$_wordContinuation])و[\\u064B-\\u0652]?( +)'
      '(?=[$_letters][$_letters$_marks]*(?![$_wordContinuation]))',
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

    bool enabled(String ruleId) =>
        !request.ignoredRuleIds.contains(ruleId) &&
        (!_optionalRuleIds.contains(ruleId) ||
            enabledOptionalRuleIds.contains(ruleId));
    _ArabicExtendedRules(text, words, protected, add, enabled).run();

    if (morphology.isAvailable) {
      await _ArabicGrammarRules(
        text,
        words,
        morphology,
        add,
        enabled,
        (int start, int end) => findings.any(
          (OfficeProofingFinding f) =>
              f.start - request.startOffset < end &&
              start < f.end - request.startOffset,
        ),
      ).run();
      if (_disposed) {
        return OfficeProofingResult(
          request: request,
          providerId: id,
          status: OfficeProofingStatus.unavailable,
          message: 'Arabic writing provider is disposed.',
        );
      }
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
