/// Numbers and money amounts in English words, for cheques, receipts, and
/// invoices (`AMOUNTWORDS(total, 'USD')`, `| words:USD`).
library;

import 'arabic_tafqeet.dart';

/// English names of a currency's main unit and subunit.
class EnglishCurrency {
  /// EnglishCurrency API.
  const EnglishCurrency({
    required this.code,
    required this.main,
    required this.mainPlural,
    required this.sub,
    required this.subPlural,
    required this.subunits,
  });

  /// ISO 4217 code (`USD`).
  final String code;

  /// `dollar`.
  final String main;

  /// `dollars`.
  final String mainPlural;

  /// `cent`.
  final String sub;

  /// `cents`.
  final String subPlural;

  /// Subunits per main unit (100, or 1000 for dinars such as LYD and KWD).
  final int subunits;
}

/// English words: `EnglishWords.amount(1250.5, 'USD')` →
/// `One thousand two hundred fifty US dollars and fifty cents only`.
abstract final class EnglishWords {
  static const List<String> _ones = <String>[
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];

  static const List<String> _tens = <String>[
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];

  static const List<String> _scales = <String>[
    '',
    'thousand',
    'million',
    'billion',
    'trillion',
  ];

  static const Map<String, (String, String, String, String)> _names =
      <String, (String, String, String, String)>{
        'LYD': ('Libyan dinar', 'Libyan dinars', 'dirham', 'dirhams'),
        'SAR': ('Saudi riyal', 'Saudi riyals', 'halala', 'halalas'),
        'AED': ('UAE dirham', 'UAE dirhams', 'fils', 'fils'),
        'KWD': ('Kuwaiti dinar', 'Kuwaiti dinars', 'fils', 'fils'),
        'BHD': ('Bahraini dinar', 'Bahraini dinars', 'fils', 'fils'),
        'OMR': ('Omani rial', 'Omani rials', 'baisa', 'baisas'),
        'QAR': ('Qatari riyal', 'Qatari riyals', 'dirham', 'dirhams'),
        'JOD': ('Jordanian dinar', 'Jordanian dinars', 'fils', 'fils'),
        'IQD': ('Iraqi dinar', 'Iraqi dinars', 'fils', 'fils'),
        'TND': ('Tunisian dinar', 'Tunisian dinars', 'millime', 'millimes'),
        'DZD': ('Algerian dinar', 'Algerian dinars', 'centime', 'centimes'),
        'MAD': ('Moroccan dirham', 'Moroccan dirhams', 'centime', 'centimes'),
        'EGP': ('Egyptian pound', 'Egyptian pounds', 'piastre', 'piastres'),
        'SDG': ('Sudanese pound', 'Sudanese pounds', 'piastre', 'piastres'),
        'SYP': ('Syrian pound', 'Syrian pounds', 'piastre', 'piastres'),
        'LBP': ('Lebanese pound', 'Lebanese pounds', 'piastre', 'piastres'),
        'TRY': ('Turkish lira', 'Turkish liras', 'kurus', 'kurus'),
        'YER': ('Yemeni rial', 'Yemeni rials', 'fils', 'fils'),
        'USD': ('US dollar', 'US dollars', 'cent', 'cents'),
        'EUR': ('euro', 'euros', 'cent', 'cents'),
        'GBP': ('pound sterling', 'pounds sterling', 'penny', 'pence'),
      };

  /// Currency for [code] (case-insensitive), or null. Subunits follow the
  /// Arabic table ([ArabicTafqeet.currency]) so both spell the same amount.
  static EnglishCurrency? currency(String code) {
    final String c = code.trim().toUpperCase();
    final (String, String, String, String)? n = _names[c];
    if (n == null) {
      return null;
    }
    return EnglishCurrency(
      code: c,
      main: n.$1,
      mainPlural: n.$2,
      sub: n.$3,
      subPlural: n.$4,
      subunits: ArabicTafqeet.currency(c)?.subunits ?? 100,
    );
  }

  /// Currency codes with English names.
  static Iterable<String> get currencyCodes => _names.keys;

  /// [n] in words, lower case (`one hundred twenty-three`).
  static String number(int n) {
    if (n < 0) {
      return 'minus ${number(-n)}';
    }
    if (n < 1000) {
      return _hundreds(n);
    }
    final List<String> parts = <String>[];
    var rest = n;
    var scale = 0;
    while (rest > 0) {
      final int chunk = rest % 1000;
      if (chunk > 0) {
        if (scale >= _scales.length) {
          throw TafqeetException('Cannot spell $n');
        }
        parts.insert(
          0,
          scale == 0
              ? _hundreds(chunk)
              : '${_hundreds(chunk)} ${_scales[scale]}',
        );
      }
      rest ~/= 1000;
      scale++;
    }
    return parts.join(' ');
  }

  /// [value] of [currencyCode] in words, capitalized, ending with ` only`
  /// unless [only] is false. Throws [TafqeetException] for an unknown
  /// currency or a non-finite value.
  static String amount(num value, String currencyCode, {bool only = true}) {
    final EnglishCurrency? cur = currency(currencyCode);
    if (cur == null) {
      throw TafqeetException('Unknown currency "$currencyCode"');
    }
    if (value.isNaN || value.isInfinite) {
      throw TafqeetException('Cannot spell $value');
    }
    final int total = (value.abs() * cur.subunits).round();
    final int whole = total ~/ cur.subunits;
    final int fraction = total % cur.subunits;
    final List<String> parts = <String>[];
    if (whole > 0 || fraction == 0) {
      parts.add('${number(whole)} ${whole == 1 ? cur.main : cur.mainPlural}');
    }
    if (fraction > 0) {
      parts.add(
        '${number(fraction)} ${fraction == 1 ? cur.sub : cur.subPlural}',
      );
    }
    final String body =
        '${value < 0 ? 'minus ' : ''}${parts.join(' and ')}${only ? ' only' : ''}';
    return body[0].toUpperCase() + body.substring(1);
  }

  static String _hundreds(int n) {
    final int h = n ~/ 100;
    final int rest = n % 100;
    final String tail = rest < 20
        ? _ones[rest]
        : rest % 10 == 0
        ? _tens[rest ~/ 10]
        : '${_tens[rest ~/ 10]}-${_ones[rest % 10]}';
    if (h == 0) {
      return tail;
    }
    return rest == 0 ? '${_ones[h]} hundred' : '${_ones[h]} hundred $tail';
  }
}
