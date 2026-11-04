/// Typed values flowing through report expressions and data bindings.
library;

import 'dart:typed_data';

/// A value bound from report data or produced by an expression.
///
/// Host data (JSON-like `Map<String, Object?>` / `List<Object?>`) is converted
/// once at the boundary by [ReportValue.from]; the engine never passes
/// untyped objects around after that.
sealed class ReportValue {
  const ReportValue();

  /// Converts JSON-like host data into a typed tree.
  ///
  /// Supported: `null`, [num], [String], [bool], [DateTime], [ReportValue],
  /// `List`, `Iterable`, and `Map` (keys stringified). Any other object is
  /// converted with `toString()`.
  static ReportValue from(Object? value) {
    return switch (value) {
      null => ReportNull.instance,
      final ReportValue v => v,
      final num n => ReportNumber(n),
      final String s => ReportText(s),
      final bool b => ReportBool(b),
      final DateTime d => ReportDate(d),
      final Uint8List bytes => ReportBinary(bytes),
      final Map<Object?, Object?> m => ReportRecord(<String, ReportValue>{
        for (final MapEntry<Object?, Object?> e in m.entries)
          '${e.key}': ReportValue.from(e.value),
      }),
      final Iterable<Object?> items => ReportList(<ReportValue>[
        for (final Object? item in items) ReportValue.from(item),
      ]),
      _ => ReportText(value.toString()),
    };
  }

  /// True for [ReportNull].
  bool get isNull => this is ReportNull;

  /// Numeric view: numbers, numeric strings, booleans (1/0), dates (epoch ms).
  num? get asNumber;

  /// Truthiness used by `IF`, `&&`, `||`, and `!`.
  bool get truthy;

  /// Plain display text (no locale formatting).
  String get displayText;

  /// Back to plain Dart (for host callbacks and exporters).
  Object? toDart();
}

/// Absent / null value.
final class ReportNull extends ReportValue {
  const ReportNull._();

  /// Shared instance.
  static const ReportNull instance = ReportNull._();

  @override
  num? get asNumber => null;

  @override
  bool get truthy => false;

  @override
  String get displayText => '';

  @override
  Object? toDart() => null;

  @override
  bool operator ==(Object other) => other is ReportNull;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'null';
}

/// Integer or floating point number.
final class ReportNumber extends ReportValue {
  /// ReportNumber API.
  const ReportNumber(this.value);

  /// value API.
  final num value;

  @override
  num get asNumber => value;

  @override
  bool get truthy => value != 0 && !value.isNaN;

  @override
  String get displayText => formatPlainNumber(value);

  @override
  Object toDart() => value;

  /// `3.0` → `3`, `2.50` → `2.5`, keeps up to 10 significant decimals.
  static String formatPlainNumber(num value) {
    if (value is int) {
      return value.toString();
    }
    final double d = value.toDouble();
    if (d.isNaN || d.isInfinite) {
      return d.toString();
    }
    if (d == d.roundToDouble() && d.abs() < 1e15) {
      return d.round().toString();
    }
    String s = d.toStringAsFixed(10);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  @override
  bool operator ==(Object other) =>
      other is ReportNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => displayText;
}

/// Text value.
final class ReportText extends ReportValue {
  /// ReportText API.
  const ReportText(this.value);

  /// value API.
  final String value;

  @override
  num? get asNumber => num.tryParse(value.trim());

  @override
  bool get truthy {
    final String s = value.trim().toLowerCase();
    return s.isNotEmpty && s != 'false' && s != '0';
  }

  @override
  String get displayText => value;

  @override
  Object toDart() => value;

  @override
  bool operator ==(Object other) => other is ReportText && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Boolean value.
final class ReportBool extends ReportValue {
  /// ReportBool API.
  const ReportBool(this.value);

  /// value API.
  final bool value;

  @override
  num get asNumber => value ? 1 : 0;

  @override
  bool get truthy => value;

  @override
  String get displayText => value ? 'true' : 'false';

  @override
  Object toDart() => value;

  @override
  bool operator ==(Object other) => other is ReportBool && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => displayText;
}

/// Date / time value.
final class ReportDate extends ReportValue {
  /// ReportDate API.
  const ReportDate(this.value);

  /// value API.
  final DateTime value;

  @override
  num get asNumber => value.millisecondsSinceEpoch;

  @override
  bool get truthy => true;

  @override
  String get displayText {
    String two(int n) => n.toString().padLeft(2, '0');
    final DateTime d = value;
    final String date = '${d.year}-${two(d.month)}-${two(d.day)}';
    if (d.hour == 0 && d.minute == 0 && d.second == 0) {
      return date;
    }
    return '$date ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Object toDart() => value;

  @override
  bool operator ==(Object other) => other is ReportDate && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => displayText;
}

/// Raw bytes (images bound from data such as `{{Data.logo}}`).
final class ReportBinary extends ReportValue {
  /// ReportBinary API.
  const ReportBinary(this.bytes);

  /// bytes API.
  final Uint8List bytes;

  @override
  num get asNumber => bytes.length;

  @override
  bool get truthy => bytes.isNotEmpty;

  @override
  String get displayText => '[${bytes.length} bytes]';

  @override
  Object toDart() => bytes;

  @override
  String toString() => displayText;
}

/// Ordered list (data set rows, projections such as `items.total`).
final class ReportList extends ReportValue {
  /// ReportList API.
  const ReportList(this.items);

  /// items API.
  final List<ReportValue> items;

  /// Empty list.
  static const ReportList empty = ReportList(<ReportValue>[]);

  @override
  num? get asNumber => items.length == 1 ? items.first.asNumber : null;

  @override
  bool get truthy => items.isNotEmpty;

  @override
  String get displayText =>
      items.map((ReportValue v) => v.displayText).join(', ');

  @override
  Object toDart() => <Object?>[for (final ReportValue v in items) v.toDart()];

  /// Flattens nested lists into scalars.
  Iterable<ReportValue> flatten() sync* {
    for (final ReportValue v in items) {
      if (v is ReportList) {
        yield* v.flatten();
      } else {
        yield v;
      }
    }
  }

  @override
  String toString() => '[$displayText]';
}

/// Named fields (one data row, the root data object, `System`, `Variables`).
final class ReportRecord extends ReportValue {
  /// ReportRecord API.
  const ReportRecord(this.fields);

  /// fields API.
  final Map<String, ReportValue> fields;

  /// Empty record.
  static const ReportRecord empty = ReportRecord(<String, ReportValue>{});

  /// Field lookup: exact name first, then case-insensitive.
  ReportValue? field(String name) {
    final ReportValue? exact = fields[name];
    if (exact != null) {
      return exact;
    }
    final String lower = name.toLowerCase();
    for (final MapEntry<String, ReportValue> e in fields.entries) {
      if (e.key.toLowerCase() == lower) {
        return e.value;
      }
    }
    return null;
  }

  @override
  num? get asNumber => null;

  @override
  bool get truthy => fields.isNotEmpty;

  @override
  String get displayText => fields.entries
      .map(
        (MapEntry<String, ReportValue> e) => '${e.key}: ${e.value.displayText}',
      )
      .join(', ');

  @override
  Object toDart() => <String, Object?>{
    for (final MapEntry<String, ReportValue> e in fields.entries)
      e.key: e.value.toDart(),
  };

  @override
  String toString() => '{$displayText}';
}

/// Ordering used by `MIN`, `MAX`, comparisons, and group sorting.
///
/// Numbers compare numerically, dates chronologically, everything else by
/// display text. Nulls sort first.
int compareReportValues(ReportValue a, ReportValue b) {
  if (a is ReportNull || b is ReportNull) {
    if (a is ReportNull && b is ReportNull) {
      return 0;
    }
    return a is ReportNull ? -1 : 1;
  }
  if (a is ReportDate && b is ReportDate) {
    return a.value.compareTo(b.value);
  }
  final num? na = a is ReportText ? null : a.asNumber;
  final num? nb = b is ReportText ? null : b.asNumber;
  if (na != null && nb != null) {
    return na.compareTo(nb);
  }
  if ((a is ReportNumber || b is ReportNumber)) {
    final num? xa = a.asNumber;
    final num? xb = b.asNumber;
    if (xa != null && xb != null) {
      return xa.compareTo(xb);
    }
  }
  return a.displayText.compareTo(b.displayText);
}

/// Loose equality used by `==` in expressions (`'5' == 5` is true).
bool reportValuesEqual(ReportValue a, ReportValue b) {
  if (a is ReportNull || b is ReportNull) {
    return a is ReportNull && b is ReportNull;
  }
  if (a is ReportText && b is ReportText) {
    return a.value == b.value;
  }
  final num? na = a.asNumber;
  final num? nb = b.asNumber;
  if (na != null && nb != null && (a is! ReportText || b is! ReportText)) {
    return na == nb;
  }
  return a.displayText == b.displayText;
}
