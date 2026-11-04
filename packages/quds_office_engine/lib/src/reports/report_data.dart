/// Report data: the schema saved with a template (tables with typed and
/// calculated columns, scalar fields), the [ReportData] builder hosts use to
/// feed a report, and JSON / CSV conversion.
library;

import 'dart:convert';

import 'report_value.dart';

/// Thrown for malformed JSON or CSV data.
class ReportDataException implements Exception {
  /// ReportDataException API.
  const ReportDataException(this.message);

  /// message API.
  final String message;

  @override
  String toString() => 'ReportDataException: $message';
}

/// Column or field type. Text values fed by a host are converted to it
/// (`'12.5'` → 12.5, `'2026-10-12'` → a date).
enum ReportDataType {
  /// Free text.
  text,

  /// Integer or decimal number.
  number,

  /// `true` / `false`.
  boolean,

  /// Date or date-time.
  date;

  /// Parses an XML `type` value (case-insensitive aliases accepted).
  static ReportDataType? fromName(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'text' || 'string' || '' => ReportDataType.text,
        'number' ||
        'numeric' ||
        'decimal' ||
        'int' ||
        'integer' ||
        'double' => ReportDataType.number,
        'boolean' || 'bool' => ReportDataType.boolean,
        'date' || 'datetime' => ReportDataType.date,
        _ => null,
      };

  /// The narrowest type that fits every non-null value of [values].
  static ReportDataType infer(Iterable<Object?> values) {
    ReportDataType? out;
    for (final Object? v in values) {
      final ReportDataType? t = switch (v) {
        null => null,
        num() => ReportDataType.number,
        bool() => ReportDataType.boolean,
        DateTime() => ReportDataType.date,
        _ => ReportDataType.text,
      };
      if (t == null) {
        continue;
      }
      if (out != null && out != t) {
        return ReportDataType.text;
      }
      out = t;
    }
    return out ?? ReportDataType.text;
  }

  /// [value] converted to this type; values that do not convert are kept.
  Object? coerce(Object? value) {
    if (value == null) {
      return null;
    }
    switch (this) {
      case ReportDataType.text:
        return switch (value) {
          String() => value,
          DateTime() => value.toIso8601String(),
          num() || bool() => '$value',
          _ => value,
        };
      case ReportDataType.number:
        return switch (value) {
          num() => value,
          bool() => value ? 1 : 0,
          String() => parseNumber(value) ?? value,
          _ => value,
        };
      case ReportDataType.boolean:
        return switch (value) {
          bool() => value,
          num() => value != 0,
          String() => parseBool(value) ?? value,
          _ => value,
        };
      case ReportDataType.date:
        return switch (value) {
          DateTime() => value,
          String() => DateTime.tryParse(value.trim()) ?? value,
          _ => value,
        };
    }
  }

  /// Typed-value form of [coerce].
  ReportValue coerceValue(ReportValue value) => switch (value) {
    ReportList() || ReportRecord() || ReportBinary() || ReportNull() => value,
    _ => ReportValue.from(coerce(value.toDart())),
  };

  /// `1,250.5` → 1250.5; null when [text] is not a number.
  static num? parseNumber(String text) {
    final String s = text.trim().replaceAll(',', '').replaceAll(' ', '');
    if (s.isEmpty) {
      return null;
    }
    return int.tryParse(s) ?? double.tryParse(s);
  }

  /// `yes` / `no`, `true` / `false`, `1` / `0`, `on` / `off`.
  static bool? parseBool(String text) => switch (text.trim().toLowerCase()) {
    'true' || 'yes' || '1' || 'on' => true,
    'false' || 'no' || '0' || 'off' => false,
    _ => null,
  };
}

/// One column of a [ReportDataTable]. A column with an [expression] is
/// calculated for every row (`qty * price`) when the report is generated.
class ReportDataColumn {
  /// ReportDataColumn API.
  ReportDataColumn({
    required this.name,
    this.type = ReportDataType.text,
    this.expression,
    this.format,
    this.description = '',
  });

  /// Field name in each row (`item.<name>`).
  String name;

  /// type API.
  ReportDataType type;

  /// Row expression for a calculated column; null for a stored column.
  String? expression;

  /// Display format used by the data explorer (`n2`, `date:dd/MM/yyyy`).
  String? format;

  /// Shown to designers.
  String description;

  /// Whether the value comes from [expression].
  bool get isCalculated {
    final String? e = expression;
    return e != null && e.trim().isNotEmpty;
  }

  /// Deep copy.
  ReportDataColumn copy() => ReportDataColumn(
    name: name,
    type: type,
    expression: expression,
    format: format,
    description: description,
  );
}

/// A data set (`<Table name="items">`): the rows a detail band, table, or
/// chart repeats over.
class ReportDataTable {
  /// ReportDataTable API.
  ReportDataTable({
    required this.name,
    List<ReportDataColumn>? columns,
    this.description = '',
  }) : columns = columns ?? <ReportDataColumn>[];

  /// Data path of the rows (`items`, `invoice.lines`).
  String name;

  /// columns API.
  final List<ReportDataColumn> columns;

  /// Shown to designers.
  String description;

  /// Column named [name] (case-insensitive), or null.
  ReportDataColumn? column(String name) {
    final String lower = name.toLowerCase();
    for (final ReportDataColumn c in columns) {
      if (c.name.toLowerCase() == lower) {
        return c;
      }
    }
    return null;
  }

  /// Deep copy.
  ReportDataTable copy() => ReportDataTable(
    name: name,
    columns: <ReportDataColumn>[
      for (final ReportDataColumn c in columns) c.copy(),
    ],
    description: description,
  );
}

/// A single value outside the tables (`Data.customer.name`).
class ReportDataField {
  /// ReportDataField API.
  ReportDataField({
    required this.name,
    this.type = ReportDataType.text,
    this.description = '',
  });

  /// Dotted data path.
  String name;

  /// type API.
  ReportDataType type;

  /// Shown to designers.
  String description;

  /// Deep copy.
  ReportDataField copy() =>
      ReportDataField(name: name, type: type, description: description);
}

/// What a report expects from its data (`<DataSchema>`), saved with the
/// template so hosts and designers agree on names and types.
class ReportDataSchema {
  /// ReportDataSchema API.
  ReportDataSchema({
    List<ReportDataTable>? tables,
    List<ReportDataField>? fields,
  }) : tables = tables ?? <ReportDataTable>[],
       fields = fields ?? <ReportDataField>[];

  /// tables API.
  final List<ReportDataTable> tables;

  /// fields API.
  final List<ReportDataField> fields;

  /// Whether nothing is declared.
  bool get isEmpty => tables.isEmpty && fields.isEmpty;

  /// Table at data path [name] (case-insensitive, `Data.` optional).
  ReportDataTable? table(String name) {
    final String key = ReportData.normalizePath(name).toLowerCase();
    for (final ReportDataTable t in tables) {
      if (ReportData.normalizePath(t.name).toLowerCase() == key) {
        return t;
      }
    }
    return null;
  }

  /// Field at data path [name] (case-insensitive, `Data.` optional).
  ReportDataField? field(String name) {
    final String key = ReportData.normalizePath(name).toLowerCase();
    for (final ReportDataField f in fields) {
      if (ReportData.normalizePath(f.name).toLowerCase() == key) {
        return f;
      }
    }
    return null;
  }

  /// Deep copy.
  ReportDataSchema copy() => ReportDataSchema(
    tables: <ReportDataTable>[for (final ReportDataTable t in tables) t.copy()],
    fields: <ReportDataField>[for (final ReportDataField f in fields) f.copy()],
  );
}

/// JSON-like data a host feeds to a report: nested maps for records, lists
/// of maps for tables.
///
/// ```dart
/// final ReportData data = ReportData()
///   ..set('customer.name', 'Northwind Traders')
///   ..setTable('items', <Map<String, Object?>>[
///     <String, Object?>{'code': 'P01', 'qty': 2, 'price': 500},
///   ])
///   ..addRow('items', <String, Object?>{'code': 'P02', 'qty': 1, 'price': 90});
/// engine.exportToPdf(data.toMap());
/// ```
///
/// Paths are dotted (`invoice.customer.name`); a leading `Data.` is ignored.
class ReportData {
  /// Wraps [values] (not copied).
  ReportData([Map<String, Object?>? values])
    : values = values ?? <String, Object?>{};

  /// Parses a JSON object.
  ///
  /// Throws [ReportDataException] when [json] is not a JSON object.
  factory ReportData.fromJson(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw ReportDataException('Invalid JSON: ${e.message}');
    }
    final Object? value = fromJsonValue(decoded);
    if (value is! Map<String, Object?>) {
      throw const ReportDataException('JSON data must be an object');
    }
    return ReportData(value);
  }

  /// The data tree.
  final Map<String, Object?> values;

  static final RegExp _name = RegExp(
    r'^[A-Za-z_\u00C0-\uFFFF][A-Za-z0-9_\u00C0-\uFFFF]*$',
  );

  /// Whether [name] is a valid field, column, or path segment: a letter
  /// (Latin, Arabic, …) or `_` followed by letters, digits, or `_`.
  static bool isValidName(String name) => _name.hasMatch(name);

  /// Whether every dot-separated segment of [path] is [isValidName].
  static bool isValidPath(String path) {
    final String p = normalizePath(path);
    return p.isNotEmpty && p.split('.').every(isValidName);
  }

  /// [path] without a leading `Data.` and surrounding spaces.
  static String normalizePath(String path) {
    final String p = path.trim();
    return p.toLowerCase().startsWith('data.') ? p.substring(5) : p;
  }

  static List<String> _segments(String path) => <String>[
    for (final String s in normalizePath(path).split('.'))
      if (s.isNotEmpty) s,
  ];

  /// Value at [path], or null.
  Object? get(String path) => valueAt(values, path);

  /// Value at [path] inside [root], or null.
  static Object? valueAt(Map<String, Object?> root, String path) {
    Object? at = root;
    for (final String s in _segments(path)) {
      if (at is! Map<String, Object?>) {
        return null;
      }
      at = at[s];
    }
    return at;
  }

  /// Sets [path] to [value], creating parent records as needed.
  void set(String path, Object? value) {
    final List<String> segs = _segments(path);
    if (segs.isEmpty) {
      throw const ReportDataException('Empty data path');
    }
    Map<String, Object?> at = values;
    for (final String s in segs.take(segs.length - 1)) {
      final Object? next = at[s];
      if (next is Map<String, Object?>) {
        at = next;
      } else {
        final Map<String, Object?> created = <String, Object?>{};
        at[s] = created;
        at = created;
      }
    }
    at[segs.last] = value;
  }

  /// Removes [path]; returns whether it existed.
  bool remove(String path) {
    final List<String> segs = _segments(path);
    if (segs.isEmpty) {
      return false;
    }
    Object? at = values;
    for (final String s in segs.take(segs.length - 1)) {
      if (at is! Map<String, Object?>) {
        return false;
      }
      at = at[s];
    }
    if (at is! Map<String, Object?> || !at.containsKey(segs.last)) {
      return false;
    }
    at.remove(segs.last);
    return true;
  }

  /// Replaces the rows of table [path].
  void setTable(String path, Iterable<Map<String, Object?>> rows) =>
      set(path, <Map<String, Object?>>[
        for (final Map<String, Object?> r in rows) Map<String, Object?>.of(r),
      ]);

  /// Appends [row] to table [path] (created when missing).
  void addRow(String path, Map<String, Object?> row) {
    final List<Map<String, Object?>> list = rowsAt(values, path);
    list.add(Map<String, Object?>.of(row));
    set(path, list);
  }

  /// Rows of table [path] (a copy of the list; the row maps are shared).
  List<Map<String, Object?>> rows(String path) => rowsAt(values, path);

  /// Rows of table [path] inside [root]: the records of the list there.
  static List<Map<String, Object?>> rowsAt(
    Map<String, Object?> root,
    String path,
  ) {
    final Object? v = valueAt(root, path);
    return <Map<String, Object?>>[
      if (v is List<Object?>)
        for (final Object? r in v)
          if (r is Map<String, Object?>) r,
    ];
  }

  /// Deep-merges [other] into [values]; [other] wins on conflicts.
  void merge(Map<String, Object?> other) => _merge(values, other);

  static void _merge(Map<String, Object?> into, Map<String, Object?> other) {
    for (final MapEntry<String, Object?> e in other.entries) {
      final Object? mine = into[e.key];
      final Object? theirs = e.value;
      if (mine is Map<String, Object?> && theirs is Map<String, Object?>) {
        _merge(mine, theirs);
      } else {
        into[e.key] = copyValue(theirs);
      }
    }
  }

  /// Removes everything.
  void clear() => values.clear();

  /// Deep copy of [values].
  Map<String, Object?> toMap() => copyMap(values);

  /// Deep copy of a JSON-like map.
  static Map<String, Object?> copyMap(Map<String, Object?> map) =>
      <String, Object?>{
        for (final MapEntry<String, Object?> e in map.entries)
          e.key: copyValue(e.value),
      };

  /// Deep copy of a JSON-like value (maps and lists copied, leaves shared).
  static Object? copyValue(Object? v) => switch (v) {
    final Map<String, Object?> m => copyMap(m),
    final List<Object?> l => <Object?>[for (final Object? x in l) copyValue(x)],
    _ => v,
  };

  /// JSON text of [values]; dates are written as ISO 8601 strings.
  String toJson({bool pretty = false}) => encodeJson(values, pretty: pretty);

  /// JSON text of a data tree.
  static String encodeJson(Map<String, Object?> data, {bool pretty = false}) {
    final JsonEncoder encoder = pretty
        ? const JsonEncoder.withIndent('  ', _toEncodable)
        : const JsonEncoder(_toEncodable);
    return encoder.convert(data);
  }

  static Object? _toEncodable(Object? v) => switch (v) {
    DateTime() => v.toIso8601String(),
    ReportValue() => v.toDart(),
    _ => '$v',
  };

  /// Decoded JSON ([jsonDecode] output) as typed maps and lists.
  static Object? fromJsonValue(Object? v) => switch (v) {
    final Map<Object?, Object?> m => <String, Object?>{
      for (final MapEntry<Object?, Object?> e in m.entries)
        '${e.key}': fromJsonValue(e.value),
    },
    final List<Object?> l => <Object?>[
      for (final Object? x in l) fromJsonValue(x),
    ],
    _ => v,
  };
}

/// Comma-separated values: header row + data rows.
abstract final class ReportCsv {
  /// Cells of [text]. [delimiter] defaults to the most frequent of `,` `;`
  /// tab in the first line. Quoted cells may contain delimiters, `""`, and
  /// line breaks; a UTF-8 BOM is skipped.
  static List<List<String>> parse(String text, {String? delimiter}) {
    var s = text;
    if (s.startsWith('\uFEFF')) {
      s = s.substring(1);
    }
    final String sep = delimiter ?? _detect(s);
    final List<List<String>> out = <List<String>>[];
    List<String> row = <String>[];
    final StringBuffer cell = StringBuffer();
    var quoted = false;
    var i = 0;
    while (i < s.length) {
      final String c = s[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            cell.write('"');
            i += 2;
            continue;
          }
          quoted = false;
        } else {
          cell.write(c);
        }
        i++;
        continue;
      }
      if (c == '"' && cell.isEmpty) {
        quoted = true;
      } else if (c == sep) {
        row.add(cell.toString());
        cell.clear();
      } else if (c == '\n' || c == '\r') {
        row.add(cell.toString());
        cell.clear();
        if (row.length > 1 || row.first.isNotEmpty) {
          out.add(row);
        }
        row = <String>[];
        if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n') {
          i++;
        }
      } else {
        cell.write(c);
      }
      i++;
    }
    if (quoted) {
      throw const ReportDataException('Unterminated quoted CSV cell');
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      out.add(row);
    }
    return out;
  }

  static String _detect(String s) {
    final int nl = s.indexOf(RegExp(r'[\r\n]'));
    final String first = nl < 0 ? s : s.substring(0, nl);
    var best = ',';
    var count = -1;
    for (final String d in const <String>[',', ';', '\t']) {
      final int n = d.allMatches(first).length;
      if (n > count) {
        best = d;
        count = n;
      }
    }
    return best;
  }

  /// Rows keyed by the header cells. A column whose every non-empty cell is
  /// a number (or `true` / `false`, or an ISO date) gets that type; empty
  /// cells become null.
  ///
  /// Throws [ReportDataException] when there is no header row.
  static List<Map<String, Object?>> rows(String text, {String? delimiter}) {
    final List<List<String>> cells = parse(text, delimiter: delimiter);
    if (cells.isEmpty) {
      throw const ReportDataException('CSV has no header row');
    }
    final List<String> header = <String>[
      for (int i = 0; i < cells.first.length; i++)
        cells.first[i].trim().isEmpty
            ? 'column${i + 1}'
            : cells.first[i].trim(),
    ];
    final List<List<String>> body = cells.sublist(1);
    final List<ReportDataType> types = <ReportDataType>[
      for (int c = 0; c < header.length; c++)
        _columnType(<String>[
          for (final List<String> r in body)
            if (c < r.length && r[c].trim().isNotEmpty) r[c].trim(),
        ]),
    ];
    return <Map<String, Object?>>[
      for (final List<String> r in body)
        <String, Object?>{
          for (int c = 0; c < header.length; c++)
            header[c]: c >= r.length || r[c].trim().isEmpty
                ? null
                : types[c].coerce(r[c].trim()),
        },
    ];
  }

  static final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}([T ][\d:.]+Z?)?$');

  static ReportDataType _columnType(List<String> cells) {
    if (cells.isEmpty) {
      return ReportDataType.text;
    }
    if (cells.every((String c) => ReportDataType.parseNumber(c) != null)) {
      return ReportDataType.number;
    }
    if (cells.every(
      (String c) => const <String>['true', 'false'].contains(c.toLowerCase()),
    )) {
      return ReportDataType.boolean;
    }
    if (cells.every((String c) => _isoDate.hasMatch(c))) {
      return ReportDataType.date;
    }
    return ReportDataType.text;
  }

  /// [rows] as CSV text with a header row ([columns], else the keys of the
  /// rows in first-seen order).
  static String write(
    List<Map<String, Object?>> rows, {
    List<String>? columns,
    String delimiter = ',',
  }) {
    final List<String> cols =
        columns ??
        <String>[
          ...<String>{for (final Map<String, Object?> r in rows) ...r.keys},
        ];
    String cell(Object? v) {
      final String s = switch (v) {
        null => '',
        DateTime() => v.toIso8601String(),
        _ => '$v',
      };
      return s.contains(delimiter) ||
              s.contains('"') ||
              s.contains('\n') ||
              s.contains('\r')
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    }

    final StringBuffer b = StringBuffer()
      ..writeln(cols.map(cell).join(delimiter));
    for (final Map<String, Object?> r in rows) {
      b.writeln(
        <String>[for (final String c in cols) cell(r[c])].join(delimiter),
      );
    }
    return b.toString();
  }
}
