/// Display formats for report values (`format="currency:LYD"`).
library;

import 'arabic_tafqeet.dart';
import 'english_words.dart';
import 'report_value.dart';

/// Locale-ish defaults applied when a format omits details.
class ReportFormatDefaults {
  /// ReportFormatDefaults API.
  const ReportFormatDefaults({
    this.datePattern = 'yyyy/MM/dd',
    this.timePattern = 'HH:mm',
    this.dateTimePattern = 'yyyy/MM/dd HH:mm',
    this.decimalSeparator = '.',
    this.groupSeparator = ',',
    this.arabicDigits = false,
  });

  /// Pattern for `System.CurrentDate` and bare dates.
  final String datePattern;

  /// Pattern for `System.CurrentTime`.
  final String timePattern;

  /// Pattern for date-times.
  final String dateTimePattern;

  /// Decimal separator.
  final String decimalSeparator;

  /// Thousands separator.
  final String groupSeparator;

  /// Emit Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩).
  final bool arabicDigits;

  /// copyWith API.
  ReportFormatDefaults copyWith({
    String? datePattern,
    String? timePattern,
    String? dateTimePattern,
    String? decimalSeparator,
    String? groupSeparator,
    bool? arabicDigits,
  }) {
    return ReportFormatDefaults(
      datePattern: datePattern ?? this.datePattern,
      timePattern: timePattern ?? this.timePattern,
      dateTimePattern: dateTimePattern ?? this.dateTimePattern,
      decimalSeparator: decimalSeparator ?? this.decimalSeparator,
      groupSeparator: groupSeparator ?? this.groupSeparator,
      arabicDigits: arabicDigits ?? this.arabicDigits,
    );
  }
}

/// Formats [ReportValue]s for display.
///
/// Format specs (case-insensitive kind, optional `:argument`):
///
/// | Spec | Example output |
/// | --- | --- |
/// | `currency:LYD` | `1,250.500 د.ل` |
/// | `currencyCode:USD` | `1,250.50 USD` |
/// | `number`, `number:2`, `n2` | `1,250.50` |
/// | `integer` | `1,251` |
/// | `percent`, `percent:1` | `12.5%` |
/// | `date`, `date:dd/MM/yyyy` | `10/10/2026` |
/// | `dateAr:d MMMM yyyy` | `10 أكتوبر 2026` (Arabic names) |
/// | `time`, `datetime` | `14:30` |
/// | `tafqeet:LYD` | Arabic words |
/// | `words:USD` | English words |
/// | `upper`, `lower`, `trim` | text case |
/// | `#,##0.00`, `0.0` | custom numeric pattern |
class ReportFormatter {
  /// ReportFormatter API.
  const ReportFormatter({this.defaults = const ReportFormatDefaults()});

  /// defaults API.
  final ReportFormatDefaults defaults;

  /// Formats [value] using [spec]; a null/empty spec gives default display.
  String format(ReportValue value, [String? spec]) {
    final String s = spec?.trim() ?? '';
    if (s.isEmpty) {
      return display(value);
    }
    if (value is ReportNull) {
      return '';
    }
    final int colon = s.indexOf(':');
    final String kind = (colon < 0 ? s : s.substring(0, colon)).toLowerCase();
    final String arg = colon < 0 ? '' : s.substring(colon + 1).trim();
    switch (kind) {
      case 'currency':
      case 'money':
        return _currency(value, arg, symbol: true);
      case 'currencycode':
        return _currency(value, arg, symbol: false);
      case 'number':
      case 'numeric':
      case 'decimal':
        return _digits(
          formatNumber(
            value.asNumber ?? 0,
            decimals: arg.isEmpty ? 2 : int.tryParse(arg) ?? 2,
          ),
        );
      case 'integer':
      case 'int':
        return _digits(formatNumber(value.asNumber ?? 0, decimals: 0));
      case 'percent':
      case 'pct':
        final num n = value.asNumber ?? 0;
        return _digits(
          '${formatNumber(n * 100, decimals: arg.isEmpty ? 0 : int.tryParse(arg) ?? 0)}%',
        );
      case 'date':
        return _digits(
          formatDate(_asDate(value), arg.isEmpty ? defaults.datePattern : arg),
        );
      case 'datear':
        return _digits(
          formatDate(
            _asDate(value),
            arg.isEmpty ? defaults.datePattern : arg,
            arabic: true,
          ),
        );
      case 'time':
        return _digits(
          formatDate(_asDate(value), arg.isEmpty ? defaults.timePattern : arg),
        );
      case 'datetime':
        return _digits(
          formatDate(
            _asDate(value),
            arg.isEmpty ? defaults.dateTimePattern : arg,
          ),
        );
      case 'tafqeet':
        final num? n = value.asNumber;
        if (n == null) {
          return display(value);
        }
        return ArabicTafqeet.amount(n, arg.isEmpty ? 'LYD' : arg);
      case 'words':
        final num? amount = value.asNumber;
        if (amount == null) {
          return display(value);
        }
        return EnglishWords.amount(amount, arg.isEmpty ? 'USD' : arg);
      case 'upper':
        return display(value).toUpperCase();
      case 'lower':
        return display(value).toLowerCase();
      case 'trim':
        return display(value).trim();
      case 'text':
      case 'string':
        return display(value);
    }
    final RegExpMatch? shortNumber = RegExp(r'^[nN](\d+)$').firstMatch(s);
    if (shortNumber != null) {
      return _digits(
        formatNumber(
          value.asNumber ?? 0,
          decimals: int.parse(shortNumber.group(1)!),
        ),
      );
    }
    if (RegExp(r'^[#0,.\s%]+$').hasMatch(s)) {
      return _digits(_pattern(value.asNumber ?? 0, s));
    }
    if (value is ReportDate) {
      return _digits(formatDate(value.value, s));
    }
    return display(value);
  }

  /// Default display: dates use [ReportFormatDefaults.datePattern].
  String display(ReportValue value) {
    return switch (value) {
      ReportDate(:final DateTime value) => _digits(
        value.hour == 0 && value.minute == 0 && value.second == 0
            ? formatDate(value, defaults.datePattern)
            : formatDate(value, defaults.dateTimePattern),
      ),
      ReportNumber() => _digits(value.displayText),
      _ => value.displayText,
    };
  }

  /// Grouped fixed-point number (`1,234.50`).
  String formatNumber(num value, {int decimals = 2, bool group = true}) {
    if (value.isNaN || value.isInfinite) {
      return value.toString();
    }
    final bool negative = value < 0;
    final String fixed = value.abs().toStringAsFixed(decimals.clamp(0, 12));
    final int dot = fixed.indexOf('.');
    final String intPart = dot < 0 ? fixed : fixed.substring(0, dot);
    final String fracPart = dot < 0 ? '' : fixed.substring(dot + 1);
    final String grouped = group ? _group(intPart) : intPart;
    final String body = fracPart.isEmpty
        ? grouped
        : '$grouped${defaults.decimalSeparator}$fracPart';
    return negative && (value.abs() >= 0.5 * _pow10(-decimals))
        ? '-$body'
        : body;
  }

  /// Date pattern tokens: `yyyy yy MMMM MMM MM M dd d EEEE EEE HH H hh h mm m
  /// ss s a`. Text in single quotes is literal. [arabic] spells month and
  /// day names in Arabic and writes `ص`/`م` for AM/PM.
  String formatDate(DateTime date, String pattern, {bool arabic = false}) {
    const List<String> arMonths = <String>[
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    const List<String> arDays = <String>[
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    const List<String> months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const List<String> days = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    String two(int n) => n.toString().padLeft(2, '0');
    final StringBuffer out = StringBuffer();
    var i = 0;
    while (i < pattern.length) {
      final String ch = pattern[i];
      if (ch == "'") {
        final int end = pattern.indexOf("'", i + 1);
        if (end < 0) {
          out.write(pattern.substring(i + 1));
          break;
        }
        out.write(end == i + 1 ? "'" : pattern.substring(i + 1, end));
        i = end + 1;
        continue;
      }
      var run = 1;
      while (i + run < pattern.length && pattern[i + run] == ch) {
        run++;
      }
      final int hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
      switch (ch) {
        case 'y':
          out.write(
            run == 2
                ? two(date.year % 100)
                : date.year.toString().padLeft(run, '0'),
          );
        case 'M':
          out.write(switch (run) {
            1 => '${date.month}',
            2 => two(date.month),
            _ when arabic => arMonths[date.month - 1],
            3 => months[date.month - 1].substring(0, 3),
            _ => months[date.month - 1],
          });
        case 'd':
          out.write(run == 1 ? '${date.day}' : two(date.day));
        case 'E':
          final String day = (arabic ? arDays : days)[date.weekday - 1];
          out.write(run <= 3 && !arabic ? day.substring(0, 3) : day);
        case 'H':
          out.write(run == 1 ? '${date.hour}' : two(date.hour));
        case 'h':
          out.write(run == 1 ? '$hour12' : two(hour12));
        case 'm':
          out.write(run == 1 ? '${date.minute}' : two(date.minute));
        case 's':
          out.write(run == 1 ? '${date.second}' : two(date.second));
        case 'a':
          out.write(
            arabic
                ? (date.hour < 12 ? 'ص' : 'م')
                : (date.hour < 12 ? 'AM' : 'PM'),
          );
        default:
          out.write(ch * run);
      }
      i += run;
    }
    return out.toString();
  }

  String _currency(ReportValue value, String code, {required bool symbol}) {
    final num n = value.asNumber ?? 0;
    final ArabicCurrency? cur = code.isEmpty
        ? null
        : ArabicTafqeet.currency(code);
    final int decimals = cur?.fractionDigits ?? 2;
    final String amount = _digits(formatNumber(n, decimals: decimals));
    final String tag = cur == null
        ? code.toUpperCase()
        : (symbol ? cur.symbol : cur.code);
    if (tag.isEmpty) {
      return amount;
    }
    return '$amount $tag';
  }

  String _pattern(num value, String pattern) {
    final bool percent = pattern.contains('%');
    final num n = percent ? value * 100 : value;
    final String core = pattern.replaceAll('%', '').trim();
    final int dot = core.indexOf('.');
    final int decimals = dot < 0 ? 0 : core.length - dot - 1;
    final bool group = core.contains(',');
    final String intSpec = dot < 0 ? core : core.substring(0, dot);
    final int minInt = '0'.allMatches(intSpec).length;
    String body = formatNumber(n, decimals: decimals, group: group);
    if (minInt > 1) {
      final bool neg = body.startsWith('-');
      String digits = neg ? body.substring(1) : body;
      final int sep = digits.indexOf(defaults.decimalSeparator);
      final String whole = sep < 0 ? digits : digits.substring(0, sep);
      final String plain = whole.replaceAll(defaults.groupSeparator, '');
      if (plain.length < minInt) {
        final String padded = plain.padLeft(minInt, '0');
        digits =
            (group ? _group(padded) : padded) +
            (sep < 0 ? '' : digits.substring(sep));
      }
      body = neg ? '-$digits' : digits;
    }
    return percent ? '$body%' : body;
  }

  String _group(String digits) {
    if (digits.length <= 3 || defaults.groupSeparator.isEmpty) {
      return digits;
    }
    final StringBuffer out = StringBuffer();
    final int lead = digits.length % 3;
    if (lead > 0) {
      out.write(digits.substring(0, lead));
    }
    for (int i = lead; i < digits.length; i += 3) {
      if (out.isNotEmpty) {
        out.write(defaults.groupSeparator);
      }
      out.write(digits.substring(i, i + 3));
    }
    return out.toString();
  }

  String _digits(String text) {
    if (!defaults.arabicDigits) {
      return text;
    }
    final StringBuffer out = StringBuffer();
    for (final int cp in text.runes) {
      if (cp >= 0x30 && cp <= 0x39) {
        out.writeCharCode(0x0660 + cp - 0x30);
      } else {
        out.writeCharCode(cp);
      }
    }
    return out.toString();
  }

  static double _pow10(int exp) {
    var v = 1.0;
    if (exp >= 0) {
      for (int i = 0; i < exp; i++) {
        v *= 10;
      }
    } else {
      for (int i = 0; i < -exp; i++) {
        v /= 10;
      }
    }
    return v;
  }

  static DateTime _asDate(ReportValue value) {
    return switch (value) {
      ReportDate(:final DateTime value) => value,
      ReportText(:final String value) =>
        DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0),
      ReportNumber(:final num value) => DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
      ),
      _ => DateTime.fromMillisecondsSinceEpoch(0),
    };
  }
}
