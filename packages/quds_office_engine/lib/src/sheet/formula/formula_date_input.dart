/// Calendar or clock input accepted by the regional NUMBERVALUE fallback.
typedef FormulaDateInput = ({
  DateTime? date,
  double? time,
  bool fictitiousLeapDay,
});

final _clockInput = RegExp(r'^(\d{1,5}):(\d{1,2})(?::(\d{1,2}))?$');
final _numericDate = RegExp(
  r'^(\d{1,4})\s*[-/.]\s*(\d{1,4})(?:\s*[-/.]\s*(\d{1,4}))?$',
);
final _namedDate = RegExp(r'^(\d{1,2})[\s./-]*([a-zäöü]+)[\s./-]*(\d{1,4})$');
final _namedMonthYear = RegExp(r'^([a-zäöü]+)[\s./-]+(\d{1,4})$');

const _monthNames = [
  {'jan', 'january', 'januar', 'jän', 'jänner'},
  {'feb', 'february', 'februar'},
  {'mar', 'march', 'mär', 'märz', 'mrz'},
  {'apr', 'april'},
  {'may', 'mai'},
  {'jun', 'june', 'juni'},
  {'jul', 'july', 'juli'},
  {'aug', 'august'},
  {'sep', 'sept', 'september'},
  {'oct', 'october', 'okt', 'oktober'},
  {'nov', 'november'},
  {'dec', 'december', 'dez', 'dezember'},
];

/// Reads a conventional local date when explicit decimal parsing failed.
/// Period-separated dates are recognized only with German regional syntax.
FormulaDateInput? parseFormulaDateInput(String raw, String locale) {
  if (raw.length > 96) return null;
  final text = raw.trim().toLowerCase();
  final clock = _clockInput.firstMatch(text);
  if (clock != null) {
    final hours = int.parse(clock[1]!);
    final minutes = int.parse(clock[2]!);
    final seconds = int.tryParse(clock[3] ?? '') ?? 0;
    return (
      date: null,
      time: (hours * 3600 + minutes * 60 + seconds) / 86400,
      fictitiousLeapDay: false,
    );
  }

  final language = locale.split(RegExp('[-_]')).first.toLowerCase();
  if (language != 'de' && language != 'en') return null;
  final german = language == 'de';
  int monthNumber(String name) =>
      _monthNames.indexWhere((pair) => pair.contains(name)) + 1;
  final named = _namedDate.firstMatch(text);
  if (named != null) {
    return _validatedDate(
      int.parse(named[3]!),
      monthNumber(named[2]!),
      int.parse(named[1]!),
    );
  }
  final monthYear = _namedMonthYear.firstMatch(text);
  if (monthYear != null) {
    return _validatedDate(
      int.parse(monthYear[2]!),
      monthNumber(monthYear[1]!),
      1,
    );
  }

  if (!german && text.contains('.')) return null;
  final numeric = _numericDate.firstMatch(text);
  if (numeric == null) return null;
  final first = int.parse(numeric[1]!);
  final second = int.parse(numeric[2]!);
  final third = int.tryParse(numeric[3] ?? '');
  if (numeric[1]!.length == 4) {
    return third == null ? null : _validatedDate(first, second, third);
  }
  if (third == null && numeric[2]!.length == 4) {
    return text.contains('.') ? null : _validatedDate(second, first, 1);
  }
  final monthFirst = RegExp(
    r'^en(?:[_-]US)?$',
    caseSensitive: false,
  ).hasMatch(locale);
  final year = third ?? DateTime.now().year;
  final month = monthFirst ? first : second;
  final day = monthFirst ? second : first;
  return _validatedDate(year, month, day);
}

FormulaDateInput? _validatedDate(int year, int month, int day) {
  if (year < 100) year += year < 30 ? 2000 : 1900;
  if (year < 1900 || year > 9999 || month < 1 || month > 12 || day < 1) {
    return null;
  }
  final fictitiousLeapDay = year == 1900 && month == 2 && day == 29;
  final date = DateTime.utc(year, month, fictitiousLeapDay ? 28 : day);
  if (!fictitiousLeapDay && (date.month != month || date.day != day)) {
    return null;
  }
  return (date: date, time: null, fictitiousLeapDay: fictitiousLeapDay);
}
