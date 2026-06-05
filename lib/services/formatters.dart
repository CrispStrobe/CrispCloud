// lib/services/formatters.dart
//
// Locale-aware formatting helpers for file sizes, dates, numbers, and
// transfer speeds.  All formatting is implemented in pure Dart — no
// dependency on the `intl` package — to keep the binary lightweight.
//
// The original non-locale helpers from lib/utils/formatters.dart are
// re-exported here for callers that only need the simple versions.

export '../utils/formatters.dart';

// ---------------------------------------------------------------------------
// LocaleFormats — static lookup table for per-locale formatting rules
// ---------------------------------------------------------------------------

/// Holds the formatting conventions for a single locale.
class _LocaleSpec {
  /// Separator between thousands groups (e.g. ',' or '.' or ' ').
  final String thousands;

  /// Separator between integer and fractional parts (e.g. '.' or ',').
  final String decimal;

  /// strftime-style date format pattern (tokens: MM dd yyyy).
  final String datePattern;

  /// Whether to use 12-hour (AM/PM) time format.
  final bool use12h;

  /// Unit suffix used for bytes (e.g. 'MB' vs 'Mo' in French).
  final String Function(String unit) unitLabel;

  const _LocaleSpec({
    required this.thousands,
    required this.decimal,
    required this.datePattern,
    required this.use12h,
    required this.unitLabel,
  });
}

String _identity(String u) => u;
String _frenchUnit(String u) {
  const map = {
    'B': 'o',
    'KB': 'Ko',
    'MB': 'Mo',
    'GB': 'Go',
    'TB': 'To',
  };
  return map[u] ?? u;
}

/// Maps locale codes (BCP-47 language subtag) to their formatting rules.
///
/// Unknown locale codes fall back silently to English conventions.
class LocaleFormats {
  LocaleFormats._();

  static const Map<String, _LocaleSpec> _specs = {
    'en': _LocaleSpec(
      thousands: ',',
      decimal: '.',
      datePattern: 'MM/dd/yyyy',
      use12h: true,
      unitLabel: _identity,
    ),
    'de': _LocaleSpec(
      thousands: '.',
      decimal: ',',
      datePattern: 'dd.MM.yyyy',
      use12h: false,
      unitLabel: _identity,
    ),
    'fr': _LocaleSpec(
      thousands: '\u202f', // narrow no-break space
      decimal: ',',
      datePattern: 'dd/MM/yyyy',
      use12h: false,
      unitLabel: _frenchUnit,
    ),
    'es': _LocaleSpec(
      thousands: '.',
      decimal: ',',
      datePattern: 'dd/MM/yyyy',
      use12h: false,
      unitLabel: _identity,
    ),
    'pt': _LocaleSpec(
      thousands: '.',
      decimal: ',',
      datePattern: 'dd/MM/yyyy',
      use12h: false,
      unitLabel: _identity,
    ),
    'ja': _LocaleSpec(
      thousands: ',',
      decimal: '.',
      datePattern: 'yyyy/MM/dd',
      use12h: false,
      unitLabel: _identity,
    ),
    'zh': _LocaleSpec(
      thousands: ',',
      decimal: '.',
      datePattern: 'yyyy年MM月dd日',
      use12h: false,
      unitLabel: _identity,
    ),
  };

  /// Returns the [_LocaleSpec] for [locale], falling back to English.
  ///
  /// [locale] may be a full BCP-47 tag like "en-US" or just "en"; only the
  /// primary language subtag is used.
  static _LocaleSpec _specFor(String locale) {
    final lang = locale.split(RegExp(r'[-_]')).first.toLowerCase();
    return _specs[lang] ?? _specs['en']!;
  }

  // ── Public accessors ──────────────────────────────────────────────────────

  /// Decimal separator for [locale] ('.' or ',').
  static String decimalSeparator(String locale) =>
      _specFor(locale).decimal;

  /// Thousands separator for [locale] (',', '.', or ' ').
  static String thousandsSeparator(String locale) =>
      _specFor(locale).thousands;

  /// Date format pattern for [locale] (e.g. 'MM/dd/yyyy').
  static String datePattern(String locale) =>
      _specFor(locale).datePattern;

  /// Whether [locale] uses 12-hour (AM/PM) time format.
  static bool uses12hTime(String locale) =>
      _specFor(locale).use12h;

  /// Returns the locale-appropriate byte-unit label for [unit].
  ///
  /// Example: 'MB' → 'Mo' in French.
  static String unitLabel(String locale, String unit) =>
      _specFor(locale).unitLabel(unit);
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Formats [value] with [decimals] decimal places using locale separators,
/// with optional thousands grouping.
String _formatNumber(
  double value,
  String locale, {
  int decimals = 1,
  bool groupThousands = true,
}) {
  final spec = LocaleFormats._specFor(locale);

  // Split into integer and fractional parts.
  // Work in absolute-value space to avoid sign-related issues with
  // Dart's truncating integer division and modulo.
  final factor = decimals > 0 ? _pow10(decimals) : 1;
  final absRounded = (value.abs() * factor).round();
  final intPart = absRounded ~/ factor;
  final fracPart = absRounded % factor;

  // Build integer string with optional thousands grouping.
  String intStr = intPart.toString();
  if (groupThousands && intStr.length > 3) {
    final buf = StringBuffer();
    final offset = intStr.length % 3;
    if (offset > 0) buf.write(intStr.substring(0, offset));
    for (var i = offset; i < intStr.length; i += 3) {
      if (buf.isNotEmpty) buf.write(spec.thousands);
      buf.write(intStr.substring(i, i + 3));
    }
    intStr = buf.toString();
  }

  final sign = value < 0 ? '-' : '';

  if (decimals <= 0) return '$sign$intStr';

  final fracStr = fracPart.toString().padLeft(decimals, '0');
  return '$sign$intStr${spec.decimal}$fracStr';
}

int _pow10(int exp) {
  var result = 1;
  for (var i = 0; i < exp; i++) result *= 10;
  return result;
}

/// Formats a [DateTime] according to a date-pattern string.
///
/// Recognised tokens: yyyy, MM, dd.
String _applyDatePattern(String pattern, DateTime date) {
  return pattern
      .replaceAll('yyyy', date.year.toString().padLeft(4, '0'))
      .replaceAll('MM', date.month.toString().padLeft(2, '0'))
      .replaceAll('dd', date.day.toString().padLeft(2, '0'));
}

/// Formats a [DateTime] time according to locale 12h/24h preference.
String _formatTime(DateTime date, String locale) {
  final spec = LocaleFormats._specFor(locale);
  if (spec.use12h) {
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final period = date.hour < 12 ? 'AM' : 'PM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $period';
  } else {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

// ---------------------------------------------------------------------------
// Public locale-aware API
// ---------------------------------------------------------------------------

/// Format [bytes] into a human-readable size string using locale conventions.
///
/// Examples:
///   formatBytesLocale(1294029, 'en')  →  "1,234.5 MB"   (approx)
///   formatBytesLocale(1294029, 'de')  →  "1.234,5 MB"
///   formatBytesLocale(1294029, 'fr')  →  "1 234,5 Mo"
String formatBytesLocale(int bytes, String locale) {
  if (bytes < 0) bytes = 0;

  final spec = LocaleFormats._specFor(locale);

  String _fmt(double value, String unit) {
    final formatted = _formatNumber(value, locale, decimals: 1);
    return '$formatted ${spec.unitLabel(unit)}';
  }

  if (bytes < 1024) return '$bytes ${spec.unitLabel('B')}';
  if (bytes < 1024 * 1024) {
    return _fmt(bytes / 1024, 'KB');
  }
  if (bytes < 1024 * 1024 * 1024) {
    return _fmt(bytes / (1024 * 1024), 'MB');
  }
  if (bytes < 1024 * 1024 * 1024 * 1024) {
    return _fmt(bytes / (1024 * 1024 * 1024), 'GB');
  }
  return _fmt(bytes / (1024 * 1024 * 1024 * 1024), 'TB');
}

/// Format [date] as a short date string appropriate for [locale].
///
/// Unlike [formatDate] (which uses relative terms like "Today"), this always
/// returns an absolute date formatted according to locale conventions.
///
/// Returns an empty string for a null [date].
String formatDateLocale(DateTime? date, String locale) {
  if (date == null) return '';
  final pattern = LocaleFormats._specFor(locale).datePattern;
  return _applyDatePattern(pattern, date);
}

/// Format [date] as a full date+time string appropriate for [locale].
///
/// Returns an empty string for a null [date].
String formatDateFullLocale(DateTime? date, String locale) {
  if (date == null) return '';
  final datePart = formatDateLocale(date, locale);
  final timePart = _formatTime(date, locale);
  return '$datePart $timePart';
}

/// Format [number] with locale-aware decimal and thousands separators.
///
/// [decimals] controls the number of fractional digits (default 2).
String formatNumberLocale(
  double number,
  String locale, {
  int decimals = 2,
}) {
  return _formatNumber(number, locale, decimals: decimals);
}

/// Format a transfer speed ([bytesPerSecond]) using locale conventions.
///
/// Equivalent to [formatBytesLocale] with a '/s' suffix.
String formatSpeedLocale(double bytesPerSecond, String locale) {
  if (bytesPerSecond <= 0) {
    final spec = LocaleFormats._specFor(locale);
    return '0 ${spec.unitLabel('B')}/s';
  }
  return '${formatBytesLocale(bytesPerSecond.round(), locale)}/s';
}
