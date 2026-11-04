/// Arabic number-to-words (تفقيط) for amounts and currencies.
library;

/// Grammatical forms of a counted Arabic noun (معدود).
///
/// Each form already includes its adjective, e.g. `دينار ليبي`,
/// `ديناران ليبيان`, `دنانير ليبية`, `ديناراً ليبياً`.
class ArabicNounForms {
  /// ArabicNounForms API.
  const ArabicNounForms({
    required this.singular,
    required this.dual,
    required this.plural,
    required this.accusative,
    this.feminine = false,
  });

  /// Indeclinable noun (e.g. `يورو`) used in every position.
  const ArabicNounForms.invariant(String word, {this.feminine = false})
    : singular = word,
      dual = word,
      plural = word,
      accusative = word;

  /// Used after 1, after 100/1000 multiples, and after 101–102 style tails.
  final String singular;

  /// Used for exactly 2 (the numeral is dropped).
  final String dual;

  /// Used after 3–10 (جمع).
  final String plural;

  /// Used after 11–99 (تمييز منصوب).
  final String accusative;

  /// Noun gender. Masculine nouns take `ثلاثة`, feminine take `ثلاث`.
  final bool feminine;
}

/// Currency definition for [ArabicTafqeet] and `currency:` formats.
class ArabicCurrency {
  /// ArabicCurrency API.
  const ArabicCurrency({
    required this.code,
    required this.main,
    required this.sub,
    required this.subunits,
    required this.symbol,
  });

  /// ISO 4217 code (`LYD`).
  final String code;

  /// Main unit (`دينار ليبي`).
  final ArabicNounForms main;

  /// Fractional unit (`درهم`).
  final ArabicNounForms sub;

  /// Fractional units per main unit (1000 for LYD, 100 for SAR).
  final int subunits;

  /// Short display symbol (`د.ل`).
  final String symbol;

  /// Decimal digits implied by [subunits] (3 for 1000, 2 for 100).
  int get fractionDigits {
    var digits = 0;
    var n = subunits;
    while (n > 1) {
      n ~/= 10;
      digits++;
    }
    return digits;
  }
}

/// Output options for [ArabicTafqeet.amount].
class TafqeetOptions {
  /// TafqeetOptions API.
  const TafqeetOptions({
    this.prefix = 'فقط ',
    this.suffix = ' لا غير',
    this.includeFraction = true,
  });

  /// Plain words with no `فقط … لا غير` wrapper.
  static const TafqeetOptions plain = TafqeetOptions(prefix: '', suffix: '');

  /// Text before the amount (`فقط `).
  final String prefix;

  /// Text after the amount (` لا غير`).
  final String suffix;

  /// When false the fractional part is ignored.
  final bool includeFraction;
}

/// Thrown for unknown currency codes or out-of-range amounts.
class TafqeetException implements Exception {
  /// TafqeetException API.
  const TafqeetException(this.message);

  /// message API.
  final String message;

  @override
  String toString() => 'TafqeetException: $message';
}

/// Converts numbers to grammatical Arabic words.
///
/// ```dart
/// ArabicTafqeet.amount(1250.5, 'LYD');
/// // فقط ألف ومائتان وخمسون ديناراً ليبياً وخمسمائة درهم لا غير
/// ```
abstract final class ArabicTafqeet {
  static const List<String> _onesMasc = <String>[
    '',
    'واحد',
    'اثنان',
    'ثلاثة',
    'أربعة',
    'خمسة',
    'ستة',
    'سبعة',
    'ثمانية',
    'تسعة',
    'عشرة',
  ];

  static const List<String> _onesFem = <String>[
    '',
    'واحدة',
    'اثنتان',
    'ثلاث',
    'أربع',
    'خمس',
    'ست',
    'سبع',
    'ثماني',
    'تسع',
    'عشر',
  ];

  static const List<String> _tens = <String>[
    '',
    'عشرة',
    'عشرون',
    'ثلاثون',
    'أربعون',
    'خمسون',
    'ستون',
    'سبعون',
    'ثمانون',
    'تسعون',
  ];

  static const List<String> _hundreds = <String>[
    '',
    'مائة',
    'مائتان',
    'ثلاثمائة',
    'أربعمائة',
    'خمسمائة',
    'ستمائة',
    'سبعمائة',
    'ثمانمائة',
    'تسعمائة',
  ];

  static const List<ArabicNounForms> _scales = <ArabicNounForms>[
    ArabicNounForms(
      singular: 'ألف',
      dual: 'ألفان',
      plural: 'آلاف',
      accusative: 'ألفاً',
    ),
    ArabicNounForms(
      singular: 'مليون',
      dual: 'مليونان',
      plural: 'ملايين',
      accusative: 'مليوناً',
    ),
    ArabicNounForms(
      singular: 'مليار',
      dual: 'ملياران',
      plural: 'مليارات',
      accusative: 'ملياراً',
    ),
    ArabicNounForms(
      singular: 'تريليون',
      dual: 'تريليونان',
      plural: 'تريليونات',
      accusative: 'تريليوناً',
    ),
  ];

  static const ArabicNounForms _dirham = ArabicNounForms(
    singular: 'درهم',
    dual: 'درهمان',
    plural: 'دراهم',
    accusative: 'درهماً',
  );
  static const ArabicNounForms _fils = ArabicNounForms(
    singular: 'فلس',
    dual: 'فلسان',
    plural: 'فلوس',
    accusative: 'فلساً',
  );
  static const ArabicNounForms _qirsh = ArabicNounForms(
    singular: 'قرش',
    dual: 'قرشان',
    plural: 'قروش',
    accusative: 'قرشاً',
  );
  static const ArabicNounForms _cent = ArabicNounForms(
    singular: 'سنت',
    dual: 'سنتان',
    plural: 'سنتات',
    accusative: 'سنتاً',
  );
  static const ArabicNounForms _halala = ArabicNounForms(
    singular: 'هللة',
    dual: 'هللتان',
    plural: 'هللات',
    accusative: 'هللة',
    feminine: true,
  );
  static const ArabicNounForms _santim = ArabicNounForms(
    singular: 'سنتيم',
    dual: 'سنتيمان',
    plural: 'سنتيمات',
    accusative: 'سنتيماً',
  );
  static const ArabicNounForms _millime = ArabicNounForms(
    singular: 'مليم',
    dual: 'مليمان',
    plural: 'مليمات',
    accusative: 'مليماً',
  );
  static const ArabicNounForms _baisa = ArabicNounForms(
    singular: 'بيسة',
    dual: 'بيستان',
    plural: 'بيسات',
    accusative: 'بيسة',
    feminine: true,
  );
  static const ArabicNounForms _penny = ArabicNounForms(
    singular: 'بنس',
    dual: 'بنسان',
    plural: 'بنسات',
    accusative: 'بنساً',
  );

  static ArabicNounForms _dinar(
    String adjM,
    String adjDual,
    String adjPl,
    String adjAcc,
  ) => ArabicNounForms(
    singular: 'دينار $adjM',
    dual: 'ديناران $adjDual',
    plural: 'دنانير $adjPl',
    accusative: 'ديناراً $adjAcc',
  );

  static ArabicNounForms _riyal(
    String adjM,
    String adjDual,
    String adjPl,
    String adjAcc,
  ) => ArabicNounForms(
    singular: 'ريال $adjM',
    dual: 'ريالان $adjDual',
    plural: 'ريالات $adjPl',
    accusative: 'ريالاً $adjAcc',
  );

  static ArabicNounForms _lira(String adjF, String adjDual, String adjPl) =>
      ArabicNounForms(
        singular: 'ليرة $adjF',
        dual: 'ليرتان $adjDual',
        plural: 'ليرات $adjPl',
        accusative: 'ليرة $adjF',
        feminine: true,
      );

  static final Map<String, ArabicCurrency> _currencies =
      <String, ArabicCurrency>{
        'LYD': ArabicCurrency(
          code: 'LYD',
          main: _dinar('ليبي', 'ليبيان', 'ليبية', 'ليبياً'),
          sub: _dirham,
          subunits: 1000,
          symbol: 'د.ل',
        ),
        'SAR': ArabicCurrency(
          code: 'SAR',
          main: _riyal('سعودي', 'سعوديان', 'سعودية', 'سعودياً'),
          sub: _halala,
          subunits: 100,
          symbol: 'ر.س',
        ),
        'AED': const ArabicCurrency(
          code: 'AED',
          main: ArabicNounForms(
            singular: 'درهم إماراتي',
            dual: 'درهمان إماراتيان',
            plural: 'دراهم إماراتية',
            accusative: 'درهماً إماراتياً',
          ),
          sub: _fils,
          subunits: 100,
          symbol: 'د.إ',
        ),
        'KWD': ArabicCurrency(
          code: 'KWD',
          main: _dinar('كويتي', 'كويتيان', 'كويتية', 'كويتياً'),
          sub: _fils,
          subunits: 1000,
          symbol: 'د.ك',
        ),
        'BHD': ArabicCurrency(
          code: 'BHD',
          main: _dinar('بحريني', 'بحرينيان', 'بحرينية', 'بحرينياً'),
          sub: _fils,
          subunits: 1000,
          symbol: 'د.ب',
        ),
        'OMR': ArabicCurrency(
          code: 'OMR',
          main: _riyal('عماني', 'عمانيان', 'عمانية', 'عمانياً'),
          sub: _baisa,
          subunits: 1000,
          symbol: 'ر.ع',
        ),
        'QAR': ArabicCurrency(
          code: 'QAR',
          main: _riyal('قطري', 'قطريان', 'قطرية', 'قطرياً'),
          sub: _dirham,
          subunits: 100,
          symbol: 'ر.ق',
        ),
        'JOD': ArabicCurrency(
          code: 'JOD',
          main: _dinar('أردني', 'أردنيان', 'أردنية', 'أردنياً'),
          sub: _fils,
          subunits: 1000,
          symbol: 'د.أ',
        ),
        'IQD': ArabicCurrency(
          code: 'IQD',
          main: _dinar('عراقي', 'عراقيان', 'عراقية', 'عراقياً'),
          sub: _fils,
          subunits: 1000,
          symbol: 'د.ع',
        ),
        'TND': ArabicCurrency(
          code: 'TND',
          main: _dinar('تونسي', 'تونسيان', 'تونسية', 'تونسياً'),
          sub: _millime,
          subunits: 1000,
          symbol: 'د.ت',
        ),
        'DZD': ArabicCurrency(
          code: 'DZD',
          main: _dinar('جزائري', 'جزائريان', 'جزائرية', 'جزائرياً'),
          sub: _santim,
          subunits: 100,
          symbol: 'د.ج',
        ),
        'MAD': const ArabicCurrency(
          code: 'MAD',
          main: ArabicNounForms(
            singular: 'درهم مغربي',
            dual: 'درهمان مغربيان',
            plural: 'دراهم مغربية',
            accusative: 'درهماً مغربياً',
          ),
          sub: _santim,
          subunits: 100,
          symbol: 'د.م',
        ),
        'EGP': const ArabicCurrency(
          code: 'EGP',
          main: ArabicNounForms(
            singular: 'جنيه مصري',
            dual: 'جنيهان مصريان',
            plural: 'جنيهات مصرية',
            accusative: 'جنيهاً مصرياً',
          ),
          sub: _qirsh,
          subunits: 100,
          symbol: 'ج.م',
        ),
        'SDG': const ArabicCurrency(
          code: 'SDG',
          main: ArabicNounForms(
            singular: 'جنيه سوداني',
            dual: 'جنيهان سودانيان',
            plural: 'جنيهات سودانية',
            accusative: 'جنيهاً سودانياً',
          ),
          sub: _qirsh,
          subunits: 100,
          symbol: 'ج.س',
        ),
        'SYP': ArabicCurrency(
          code: 'SYP',
          main: _lira('سورية', 'سوريتان', 'سورية'),
          sub: _qirsh,
          subunits: 100,
          symbol: 'ل.س',
        ),
        'LBP': ArabicCurrency(
          code: 'LBP',
          main: _lira('لبنانية', 'لبنانيتان', 'لبنانية'),
          sub: _qirsh,
          subunits: 100,
          symbol: 'ل.ل',
        ),
        'TRY': ArabicCurrency(
          code: 'TRY',
          main: _lira('تركية', 'تركيتان', 'تركية'),
          sub: _qirsh,
          subunits: 100,
          symbol: '₺',
        ),
        'YER': ArabicCurrency(
          code: 'YER',
          main: _riyal('يمني', 'يمنيان', 'يمنية', 'يمنياً'),
          sub: _fils,
          subunits: 100,
          symbol: 'ر.ي',
        ),
        'USD': const ArabicCurrency(
          code: 'USD',
          main: ArabicNounForms(
            singular: 'دولار أمريكي',
            dual: 'دولاران أمريكيان',
            plural: 'دولارات أمريكية',
            accusative: 'دولاراً أمريكياً',
          ),
          sub: _cent,
          subunits: 100,
          symbol: r'$',
        ),
        'EUR': const ArabicCurrency(
          code: 'EUR',
          main: ArabicNounForms.invariant('يورو'),
          sub: _cent,
          subunits: 100,
          symbol: '€',
        ),
        'GBP': const ArabicCurrency(
          code: 'GBP',
          main: ArabicNounForms(
            singular: 'جنيه إسترليني',
            dual: 'جنيهان إسترلينيان',
            plural: 'جنيهات إسترلينية',
            accusative: 'جنيهاً إسترلينياً',
          ),
          sub: _penny,
          subunits: 100,
          symbol: '£',
        ),
      };

  /// Registered currency codes.
  static Iterable<String> get currencyCodes => _currencies.keys;

  /// Currency for [code] (case-insensitive), or null.
  static ArabicCurrency? currency(String code) =>
      _currencies[code.trim().toUpperCase()];

  /// Adds or replaces a currency definition.
  static void registerCurrency(ArabicCurrency currency) {
    _currencies[currency.code.toUpperCase()] = currency;
  }

  /// Words for an amount of [currencyCode], wrapped by [options].
  static String amount(
    num value,
    String currencyCode, {
    TafqeetOptions options = const TafqeetOptions(),
  }) {
    final ArabicCurrency? cur = currency(currencyCode);
    if (cur == null) {
      throw TafqeetException('Unknown currency "$currencyCode"');
    }
    if (value.isNaN || value.isInfinite) {
      throw TafqeetException('Cannot spell $value');
    }
    final bool negative = value < 0;
    final num abs = value.abs();
    final int scale = cur.subunits;
    final int totalSub = (abs * scale).round();
    final int whole = totalSub ~/ scale;
    final int fraction = options.includeFraction ? totalSub % scale : 0;
    final List<String> parts = <String>[];
    if (whole > 0 || fraction == 0) {
      parts.add(counted(whole, cur.main));
    }
    if (fraction > 0) {
      parts.add(counted(fraction, cur.sub));
    }
    final String body = parts.join(' و');
    final String signed = negative ? 'سالب $body' : body;
    return '${options.prefix}$signed${options.suffix}';
  }

  /// Number followed by the correct form of [noun] (`ثلاثة دنانير`).
  static String counted(int n, ArabicNounForms noun) {
    if (n < 0) {
      return 'سالب ${counted(-n, noun)}';
    }
    if (n == 0) {
      return 'صفر ${noun.singular}';
    }
    if (n == 1) {
      return '${noun.singular} ${noun.feminine ? 'واحدة' : 'واحد'}';
    }
    if (n == 2) {
      return noun.dual;
    }
    final int tail = n % 100;
    final String words = _construct(number(n, feminine: noun.feminine));
    if (tail >= 3 && tail <= 10) {
      return '$words ${noun.plural}';
    }
    if (tail >= 11) {
      return '$words ${noun.accusative}';
    }
    return '$words ${noun.singular}';
  }

  /// Bare words for [n] (no counted noun). [feminine] selects the gender of
  /// the implied noun for 1–19 and compound units.
  static String number(int n, {bool feminine = false}) {
    if (n < 0) {
      return 'سالب ${number(-n, feminine: feminine)}';
    }
    if (n == 0) {
      return 'صفر';
    }
    if (n >= 1000000000000000) {
      throw TafqeetException('Amount $n is out of range');
    }
    final List<int> groups = <int>[];
    var rest = n;
    while (rest > 0) {
      groups.add(rest % 1000);
      rest ~/= 1000;
    }
    final List<String> phrases = <String>[];
    for (int i = groups.length - 1; i >= 0; i--) {
      final int g = groups[i];
      if (g == 0) {
        continue;
      }
      if (i == 0) {
        phrases.add(_below1000(g, feminine: feminine));
      } else {
        phrases.add(_scaled(g, _scales[i - 1]));
      }
    }
    return phrases.join(' و');
  }

  static String _scaled(int count, ArabicNounForms scale) {
    if (count == 1) {
      return scale.singular;
    }
    if (count == 2) {
      return scale.dual;
    }
    final int tail = count % 100;
    if (count > 100 && (tail == 1 || tail == 2)) {
      return '${_hundreds[count ~/ 100]} و${tail == 1 ? scale.singular : scale.dual}';
    }
    final String words = _construct(_below1000(count, feminine: false));
    if (tail >= 3 && tail <= 10) {
      return '$words ${scale.plural}';
    }
    if (tail >= 11) {
      return '$words ${scale.accusative}';
    }
    return '$words ${scale.singular}';
  }

  /// Dual before a noun drops its nun: `مائتان` → `مائتا`, `ألفان` → `ألفا`.
  static String _construct(String words) {
    for (final String dual in <String>[
      'مائتان',
      'ألفان',
      'مليونان',
      'ملياران',
      'تريليونان',
    ]) {
      if (words.endsWith(dual)) {
        return words.substring(0, words.length - 1);
      }
    }
    return words;
  }

  static String _below1000(int n, {required bool feminine}) {
    final int h = n ~/ 100;
    final int r = n % 100;
    final List<String> parts = <String>[];
    if (h > 0) {
      parts.add(_hundreds[h]);
    }
    if (r > 0) {
      parts.add(_below100(r, feminine: feminine));
    }
    return parts.join(' و');
  }

  static String _below100(int n, {required bool feminine}) {
    if (n <= 10) {
      return feminine ? _onesFem[n] : _onesMasc[n];
    }
    if (n == 11) {
      return feminine ? 'إحدى عشرة' : 'أحد عشر';
    }
    if (n == 12) {
      return feminine ? 'اثنتا عشرة' : 'اثنا عشر';
    }
    if (n < 20) {
      final int u = n - 10;
      return feminine ? '${_onesFem[u]} عشرة' : '${_onesMasc[u]} عشر';
    }
    final int t = n ~/ 10;
    final int u = n % 10;
    if (u == 0) {
      return _tens[t];
    }
    final String unit = u == 1
        ? (feminine ? 'إحدى' : 'واحد')
        : (feminine ? _onesFem[u] : _onesMasc[u]);
    return '$unit و${_tens[t]}';
  }
}
