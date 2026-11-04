/// Evaluation of report expressions against data, variables, and paging.
library;

import 'dart:math' as math;

import 'arabic_tafqeet.dart';
import 'english_words.dart';
import 'report_data.dart';
import 'report_expression.dart';
import 'report_format.dart';
import 'report_shape.dart';
import 'report_value.dart';

/// Host-provided function: `MYFN(a, b)` receives evaluated arguments.
typedef ReportFunction = ReportValue Function(List<ReportValue> arguments);

/// Values exposed as `System.*`.
class ReportSystemInfo {
  /// ReportSystemInfo API.
  const ReportSystemInfo({
    required this.now,
    this.pageNumber = 1,
    this.totalPages = 1,
    this.userName = '',
    this.reportName = '',
  });

  /// Generation timestamp.
  final DateTime now;

  /// 1-based page being laid out.
  final int pageNumber;

  /// Total page count (final after the second layout pass).
  final int totalPages;

  /// `System.UserName`.
  final String userName;

  /// `System.ReportName`.
  final String reportName;

  /// copyWith API.
  ReportSystemInfo copyWith({int? pageNumber, int? totalPages}) {
    return ReportSystemInfo(
      now: now,
      pageNumber: pageNumber ?? this.pageNumber,
      totalPages: totalPages ?? this.totalPages,
      userName: userName,
      reportName: reportName,
    );
  }
}

/// Current group while evaluating group bands and rows.
class ReportGroupInfo {
  /// ReportGroupInfo API.
  const ReportGroupInfo({
    required this.key,
    required this.rows,
    required this.index,
  });

  /// Group key value.
  final ReportValue key;

  /// Rows in this group.
  final List<ReportValue> rows;

  /// 0-based group ordinal.
  final int index;
}

/// Everything an expression can see.
///
/// Name resolution for a bare identifier: reserved roots (`System`,
/// `Variables`, `Data`, `Group`, `item`/`row`), then the current row's
/// fields, then root data fields, then variables.
class ReportScope {
  /// ReportScope API.
  const ReportScope({
    required this.data,
    required this.variables,
    required this.system,
    this.row,
    this.rowIndex = -1,
    this.group,
    this.aggregateRows,
    this.datasetPath,
    this.overrideDataset = false,
  });

  /// Root data object (`Data.*`).
  final ReportRecord data;

  /// Template + host variables (`Variables.*`).
  final ReportRecord variables;

  /// `System.*`.
  final ReportSystemInfo system;

  /// Current detail row (`item.*`, `row.*`), if any.
  final ReportValue? row;

  /// 0-based index of [row] within its data set.
  final int rowIndex;

  /// Current group, if any.
  final ReportGroupInfo? group;

  /// Rows that row-relative aggregates (`SUM(item.total)`) iterate.
  final List<ReportValue>? aggregateRows;

  /// Detail data set path (`items`).
  final String? datasetPath;

  /// When true, a path equal to [datasetPath] resolves to [aggregateRows]
  /// (group bands: `SUM(items.total)` is a subtotal).
  final bool overrideDataset;

  /// copyWith API.
  ReportScope copyWith({
    ReportSystemInfo? system,
    ReportValue? row,
    int? rowIndex,
    ReportGroupInfo? group,
    List<ReportValue>? aggregateRows,
    String? datasetPath,
    bool? overrideDataset,
    bool clearRow = false,
    bool clearGroup = false,
  }) {
    return ReportScope(
      data: data,
      variables: variables,
      system: system ?? this.system,
      row: clearRow ? null : (row ?? this.row),
      rowIndex: clearRow ? -1 : (rowIndex ?? this.rowIndex),
      group: clearGroup ? null : (group ?? this.group),
      aggregateRows: aggregateRows ?? this.aggregateRows,
      datasetPath: datasetPath ?? this.datasetPath,
      overrideDataset: overrideDataset ?? this.overrideDataset,
    );
  }
}

/// Evaluates [ReportExpression]s and interpolates [ReportTemplateText].
///
/// Built-in functions (case-insensitive):
///
/// - Aggregates: `SUM COUNT AVG MIN MAX DISTINCTCOUNT FIRST LAST`
/// - Arabic: `TAFQEET(amount, 'LYD' [, wrap])`, `NUMBERWORDS(n [, feminine])`
/// - Words in either language: `AMOUNTWORDS(amount, 'USD' [, 'en' | 'ar'])`
/// - Logic: `IF IIF COALESCE NVL ISNULL ISEMPTY AND OR NOT`
/// - Math: `ROUND FLOOR CEIL ABS MOD POWER SQRT`
/// - Text: `CONCAT UPPER LOWER TRIM LEN LEFT RIGHT SUBSTR REPLACE CONTAINS
///   STARTSWITH ENDSWITH PADLEFT JOIN`
/// - Dates: `NOW TODAY DATE YEAR MONTH DAY`
/// - Conversion / display: `NUMBER TEXT FORMAT`
class QudsExpressionEngine {
  /// QudsExpressionEngine API.
  QudsExpressionEngine({
    this.formatter = const ReportFormatter(),
    Map<String, ReportFunction>? functions,
  }) {
    if (functions != null) {
      for (final MapEntry<String, ReportFunction> e in functions.entries) {
        registerFunction(e.key, e.value);
      }
    }
  }

  /// formatter API.
  final ReportFormatter formatter;

  final Map<String, ReportFunction> _custom = <String, ReportFunction>{};

  static const Set<String> _aggregates = <String>{
    'SUM',
    'COUNT',
    'AVG',
    'AVERAGE',
    'MIN',
    'MAX',
    'DISTINCTCOUNT',
    'COUNTDISTINCT',
    'FIRST',
    'LAST',
  };

  static const Set<String> _builtins = <String>{
    ..._aggregates,
    'TAFQEET',
    'NUMBERWORDS',
    'AMOUNTWORDS',
    'IF',
    'IIF',
    'COALESCE',
    'NVL',
    'ISNULL',
    'ISEMPTY',
    'AND',
    'OR',
    'NOT',
    'ROUND',
    'FLOOR',
    'CEIL',
    'CEILING',
    'ABS',
    'MOD',
    'POWER',
    'SQRT',
    'CONCAT',
    'UPPER',
    'LOWER',
    'TRIM',
    'LEN',
    'LENGTH',
    'LEFT',
    'RIGHT',
    'SUBSTR',
    'MID',
    'REPLACE',
    'CONTAINS',
    'STARTSWITH',
    'ENDSWITH',
    'PADLEFT',
    'JOIN',
    'NOW',
    'TODAY',
    'DATE',
    'YEAR',
    'MONTH',
    'DAY',
    'NUMBER',
    'NUM',
    'TONUMBER',
    'TEXT',
    'STR',
    'TOSTRING',
    'FORMAT',
  };

  /// Adds a host function (`name` is case-insensitive).
  void registerFunction(String name, ReportFunction function) {
    _custom[name.toUpperCase()] = function;
  }

  /// True when [name] is a built-in or registered function.
  bool knowsFunction(String name) {
    final String upper = name.toUpperCase();
    return _builtins.contains(upper) || _custom.containsKey(upper);
  }

  /// Parses and evaluates [source].
  ReportValue evaluateSource(String source, ReportScope scope) =>
      evaluate(ReportExpression.parse(source), scope);

  /// Evaluates a parsed expression.
  ReportValue evaluate(ReportExpression expression, ReportScope scope) {
    try {
      return _eval(expression.root, scope);
    } on ReportExpressionException catch (e) {
      if (e.source != null) {
        rethrow;
      }
      throw ReportExpressionException(e.message, source: expression.source);
    }
  }

  /// True when [source] is a `{{ }}` template rather than a bare name.
  static bool isTemplate(String? source) => (source ?? '').contains('{{');

  /// True when a map label is a formula. A single column name stays an
  /// attribute lookup. `CONCAT(name, "\n", code)` and `Row.name` are formulas,
  /// as is any `{{ }}` template.
  static bool isLabelFormula(String? source) {
    final String s = (source ?? '').trim();
    if (s.isEmpty) {
      return false;
    }
    if (s.contains('{{')) {
      return true;
    }
    return !_plainName(s);
  }

  static bool _plainName(String s) {
    final int first = s.codeUnitAt(0);
    if (!_nameStart(first)) {
      return false;
    }
    for (int i = 1; i < s.length; i++) {
      final int c = s.codeUnitAt(i);
      if (!_nameStart(c) && (c < 0x30 || c > 0x39)) {
        return false;
      }
    }
    return true;
  }

  static bool _nameStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c > 0x7F;

  /// Caption of each category key when [labelField] is a formula.
  /// The first row for a key wins. A failing formula yields an empty caption
  /// so the map does not fall back to the region key.
  ///
  /// [shapes] supplies the map file's columns. They are written onto the
  /// matched row, so `name` and `Row.name` both read the region.
  Map<String, String> regionCaptions(
    String labelField,
    String? category,
    List<ReportValue> rows,
    ReportScope scope, {
    ReportShapeLayer? shapes,
  }) {
    final bool wrapped = labelField.contains('{{');
    final ReportTemplateText? template;
    final ReportExpression? expression;
    try {
      if (wrapped) {
        template = ReportTemplateText.parse(labelField);
        expression = null;
      } else {
        template = null;
        expression = ReportExpression.parse(labelField);
      }
    } on ReportExpressionException {
      return <String, String>{};
    }
    ReportExpression? cat;
    final String catSrc = (category ?? '').trim();
    if (catSrc.isNotEmpty) {
      try {
        cat = ReportExpression.parse(catSrc);
      } on ReportExpressionException {
        cat = null;
      }
    }
    final Map<String, String> out = <String, String>{};
    for (int r = 0; r < rows.length; r++) {
      final ReportScope rs = scope.copyWith(row: rows[r], rowIndex: r);
      final String key;
      try {
        key = cat == null ? '${r + 1}' : formatter.display(evaluate(cat, rs));
      } on ReportExpressionException {
        continue;
      }
      if (out.containsKey(key)) {
        continue;
      }
      final ReportScope labeled = scope.copyWith(
        row: _labelRow(rows[r], key, shapes),
        rowIndex: r,
      );
      var caption = '';
      try {
        caption = template != null
            ? interpolateParsed(template, labeled)
            : formatter.display(evaluate(expression!, labeled));
      } on ReportExpressionException {
        caption = '';
      }
      out[key] = caption;
    }
    return out;
  }

  /// Caption of every region when [field] is a calculated or stored column
  /// of the report rather than an attribute stored in the shape file.
  /// Keys are [ReportShapeFeature.key]. Empty when [field] is a formula or
  /// a real shape attribute.
  Map<String, String>? shapeFieldLabels({
    required String field,
    required ReportShapeLayer layer,
    required ReportDataSchema schema,
    ReportRecord? data,
    String? keyField,
  }) {
    final String name = field.trim();
    if (name.isEmpty || isLabelFormula(name)) {
      return null;
    }
    final bool onLayer = layer.fields.any(
      (String f) => f.toLowerCase() == name.toLowerCase(),
    );
    String? expression;
    for (final ReportDataTable table in schema.tables) {
      final ReportDataColumn? column = table.column(name);
      if (column != null && column.isCalculated) {
        expression = column.expression;
        break;
      }
    }
    if (expression == null && onLayer) {
      return null;
    }
    ReportExpression? parsed;
    if (expression != null) {
      try {
        parsed = ReportExpression.parse(expression);
      } on ReportExpressionException {
        return null;
      }
    }
    final List<ReportRecord> rows = parsed == null && data != null
        ? _recordsWith(data, name)
        : const <ReportRecord>[];
    if (parsed == null && rows.isEmpty) {
      return null;
    }
    final Map<String, String> out = <String, String>{};
    for (final ReportShapeFeature feature in layer.features) {
      if (parsed != null) {
        final ReportScope scope = ReportScope(
          data: data ?? ReportRecord.empty,
          variables: ReportRecord.empty,
          system: ReportSystemInfo(now: DateTime.utc(2020)),
          row: _featureRecord(feature, layer),
        );
        try {
          out[feature.key] = formatter.display(evaluate(parsed, scope));
        } on ReportExpressionException {
          out[feature.key] = '';
        }
        continue;
      }
      final ReportRecord? row = _rowForFeature(rows, feature, keyField);
      final ReportValue? cell = row?.field(name);
      if (cell != null && cell is! ReportNull) {
        out[feature.key] = formatter.display(cell);
      }
    }
    return out.isEmpty ? null : out;
  }

  List<ReportRecord> _recordsWith(ReportRecord root, String field) {
    final List<ReportRecord> out = <ReportRecord>[];
    void walk(ReportValue value, int depth) {
      if (depth > 6) {
        return;
      }
      if (value is ReportList) {
        final List<ReportRecord> records = <ReportRecord>[
          for (final ReportValue item in value.items)
            if (item is ReportRecord) item,
        ];
        if (records.any((ReportRecord r) => r.field(field) != null)) {
          out.addAll(records);
        }
        for (final ReportValue item in value.items) {
          walk(item, depth + 1);
        }
      } else if (value is ReportRecord) {
        for (final ReportValue child in value.fields.values) {
          walk(child, depth + 1);
        }
      }
    }

    walk(root, 0);
    return out;
  }

  ReportRecord? _rowForFeature(
    List<ReportRecord> rows,
    ReportShapeFeature feature,
    String? keyField,
  ) {
    final String key = feature.key.trim().toLowerCase();
    if (key.isEmpty) {
      return null;
    }
    final String named = (keyField ?? '').trim();
    if (named.isNotEmpty) {
      for (final ReportRecord row in rows) {
        final ReportValue? cell = row.field(named);
        if (cell != null && cell.displayText.trim().toLowerCase() == key) {
          return row;
        }
      }
    }
    for (final ReportRecord row in rows) {
      for (final ReportValue cell in row.fields.values) {
        if (cell is ReportNull) {
          continue;
        }
        if (cell.displayText.trim().toLowerCase() == key) {
          return row;
        }
      }
    }
    return null;
  }

  /// Label of one region from its own columns. Used when the chart's data
  /// set has no row for that region, so `Name` and `SHAPE_Area` still draw.
  String shapeCaption(
    String labelField,
    ReportShapeFeature feature,
    ReportShapeLayer layer,
  ) {
    final ReportScope scope = ReportScope(
      data: ReportRecord.empty,
      variables: ReportRecord.empty,
      system: ReportSystemInfo(now: DateTime.utc(2020)),
      row: _featureRecord(feature, layer),
    );
    try {
      if (labelField.contains('{{')) {
        return interpolate(labelField, scope);
      }
      return formatter.display(evaluateSource(labelField, scope));
    } on ReportExpressionException {
      return '';
    }
  }

  /// The data row with the matched region's attributes on top, so a label
  /// formula reads the map file by bare name or by `Row.`.
  ReportValue _labelRow(ReportValue row, String key, ReportShapeLayer? shapes) {
    if (shapes == null) {
      return row;
    }
    final ReportShapeFeature? feature = shapes.find(key);
    if (feature == null) {
      return row;
    }
    final Map<String, ReportValue> fields = <String, ReportValue>{};
    if (row is ReportRecord) {
      fields.addAll(row.fields);
    }
    fields.addAll(_featureRecord(feature, shapes).fields);
    return ReportRecord(fields);
  }

  ReportRecord _featureRecord(
    ReportShapeFeature feature,
    ReportShapeLayer layer,
  ) {
    final Map<String, ReportValue> fields = <String, ReportValue>{};
    final List<String> columns = layer.fields.isEmpty
        ? const <String>['key', 'label']
        : layer.fields;
    for (final String name in columns) {
      final String text = _shapeCell(feature, name);
      if (text.isEmpty) {
        continue;
      }
      fields[name] = ReportText(text);
    }
    if (!fields.keys.any((String n) => n.toLowerCase() == 'key')) {
      fields['key'] = ReportText(feature.key);
    }
    if (feature.label.isNotEmpty &&
        !fields.keys.any((String n) => n.toLowerCase() == 'label')) {
      fields['label'] = ReportText(feature.label);
    }
    return ReportRecord(fields);
  }

  static String _shapeCell(ReportShapeFeature feature, String name) {
    final String stored = feature.valueOf(name);
    if (stored.isNotEmpty) {
      return stored;
    }
    final String n = name.toLowerCase();
    if (n == 'key') {
      return feature.key;
    }
    if (n == 'label') {
      return feature.label;
    }
    return '';
  }

  /// Expands every `{{ }}` placeholder in [template].
  String interpolate(String template, ReportScope scope) =>
      interpolateParsed(ReportTemplateText.parse(template), scope);

  /// Expands a pre-parsed template.
  String interpolateParsed(ReportTemplateText template, ReportScope scope) {
    if (template.segments.length == 1) {
      final ReportTextSegment only = template.segments.first;
      if (only is ReportLiteralSegment) {
        return only.text;
      }
    }
    final StringBuffer out = StringBuffer();
    for (final ReportTextSegment segment in template.segments) {
      switch (segment) {
        case ReportLiteralSegment(:final String text):
          out.write(text);
        case ReportExpressionSegment(
          :final ReportExpression expression,
          :final String? format,
        ):
          out.write(formatter.format(evaluate(expression, scope), format));
      }
    }
    return out.toString();
  }

  /// Value of a single-placeholder template (`{{item.price}}`) or the
  /// interpolated text otherwise. Exporters use this to keep numbers typed.
  ReportValue valueOf(ReportTemplateText template, ReportScope scope) {
    final List<ReportTextSegment> segs = template.segments
        .where(
          (ReportTextSegment s) =>
              s is! ReportLiteralSegment || s.text.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (segs.length == 1) {
      final ReportTextSegment only = segs.first;
      if (only is ReportExpressionSegment && only.format == null) {
        return evaluate(only.expression, scope);
      }
    }
    return ReportText(interpolateParsed(template, scope));
  }

  ReportValue _eval(ReportExpr e, ReportScope scope) {
    switch (e) {
      case ReportLiteralExpr(:final ReportValue value):
        return value;
      case ReportIdentifierExpr(:final String name):
        final ReportValue? overridden = _datasetOverride(e, scope);
        if (overridden != null) {
          return overridden;
        }
        return _identifier(name, scope);
      case ReportMemberExpr(:final ReportExpr target, :final String name):
        final ReportValue? overridden = _datasetOverride(e, scope);
        if (overridden != null) {
          return overridden;
        }
        return _member(_eval(target, scope), name, scope);
      case ReportIndexExpr(:final ReportExpr target, :final ReportExpr index):
        return _index(_eval(target, scope), _eval(index, scope));
      case ReportUnaryExpr(:final ReportUnaryOp op, :final ReportExpr operand):
        final ReportValue v = _eval(operand, scope);
        return switch (op) {
          ReportUnaryOp.not => ReportBool(!v.truthy),
          ReportUnaryOp.plus =>
            v.asNumber == null
                ? ReportNull.instance
                : ReportNumber(v.asNumber!),
          ReportUnaryOp.negate =>
            v.asNumber == null
                ? ReportNull.instance
                : ReportNumber(-v.asNumber!),
        };
      case ReportBinaryExpr(
        :final ReportBinaryOp op,
        :final ReportExpr left,
        :final ReportExpr right,
      ):
        return _binary(op, left, right, scope);
      case ReportConditionalExpr(
        :final ReportExpr condition,
        :final ReportExpr whenTrue,
        :final ReportExpr whenFalse,
      ):
        return _eval(condition, scope).truthy
            ? _eval(whenTrue, scope)
            : _eval(whenFalse, scope);
      case ReportCallExpr(
        :final String name,
        :final List<ReportExpr> arguments,
      ):
        return _call(name, arguments, scope);
    }
  }

  ReportValue? _datasetOverride(ReportExpr e, ReportScope scope) {
    final String? path = scope.datasetPath;
    final List<ReportValue>? rows = scope.aggregateRows;
    if (!scope.overrideDataset || path == null || rows == null) {
      return null;
    }
    final String? dotted = ReportExpression.dottedPath(e);
    if (dotted == null) {
      return null;
    }
    final String d = dotted.toLowerCase();
    final String p = path.toLowerCase();
    if (d == p || d == 'data.$p') {
      return ReportList(rows);
    }
    return null;
  }

  static bool _isRowName(String name) {
    final String n = name.toLowerCase();
    return n == 'item' || n == 'row' || n == 'record';
  }

  static bool _isReservedRoot(String name) {
    final String n = name.toLowerCase();
    return n == 'system' ||
        n == 'variables' ||
        n == 'vars' ||
        n == 'var' ||
        n == 'data' ||
        n == 'group' ||
        _isRowName(n);
  }

  ReportValue _identifier(String name, ReportScope scope) {
    final String n = name.toLowerCase();
    switch (n) {
      case 'system':
        return _systemRecord(scope);
      case 'variables':
      case 'vars':
      case 'var':
        return scope.variables;
      case 'data':
        return scope.data;
      case 'group':
        return _groupRecord(scope);
    }
    if (_isRowName(n)) {
      return scope.row ?? ReportNull.instance;
    }
    final ReportValue? row = scope.row;
    if (row is ReportRecord) {
      final ReportValue? hit = row.field(name);
      if (hit != null) {
        return hit;
      }
    }
    return scope.data.field(name) ??
        scope.variables.field(name) ??
        ReportNull.instance;
  }

  ReportRecord _systemRecord(ReportScope scope) {
    final ReportSystemInfo s = scope.system;
    final DateTime now = s.now;
    return ReportRecord(<String, ReportValue>{
      'CurrentDate': ReportDate(DateTime(now.year, now.month, now.day)),
      'CurrentTime': ReportText(
        formatter.formatDate(now, formatter.defaults.timePattern),
      ),
      'CurrentDateTime': ReportDate(now),
      'Now': ReportDate(now),
      'Today': ReportDate(DateTime(now.year, now.month, now.day)),
      'PageNumber': ReportNumber(s.pageNumber),
      'TotalPages': ReportNumber(s.totalPages),
      'PageCount': ReportNumber(s.totalPages),
      'UserName': ReportText(s.userName),
      'ReportName': ReportText(s.reportName),
      'RowNumber': ReportNumber(scope.rowIndex + 1),
      'RowIndex': ReportNumber(scope.rowIndex),
      'RowCount': ReportNumber(scope.aggregateRows?.length ?? 0),
      'GroupNumber': ReportNumber((scope.group?.index ?? -1) + 1),
    });
  }

  ReportValue _groupRecord(ReportScope scope) {
    final ReportGroupInfo? g = scope.group;
    if (g == null) {
      return ReportNull.instance;
    }
    return ReportRecord(<String, ReportValue>{
      'Key': g.key,
      'Count': ReportNumber(g.rows.length),
      'Index': ReportNumber(g.index),
      'Number': ReportNumber(g.index + 1),
      'Rows': ReportList(g.rows),
    });
  }

  ReportValue _member(ReportValue target, String name, ReportScope scope) {
    switch (target) {
      case ReportRecord():
        return target.field(name) ?? ReportNull.instance;
      case ReportList(:final List<ReportValue> items):
        final String n = name.toLowerCase();
        final bool hasField = items.any(
          (ReportValue v) => v is ReportRecord && v.field(name) != null,
        );
        if (!hasField && (n == 'length' || n == 'count')) {
          return ReportNumber(items.length);
        }
        final int? idx = int.tryParse(name);
        if (idx != null && !hasField) {
          return idx >= 0 && idx < items.length
              ? items[idx]
              : ReportNull.instance;
        }
        return ReportList(<ReportValue>[
          for (final ReportValue item in items) _member(item, name, scope),
        ]);
      case ReportText(:final String value):
        final String n = name.toLowerCase();
        if (n == 'length') {
          return ReportNumber(value.length);
        }
        return ReportNull.instance;
      case ReportDate(:final DateTime value):
        return switch (name.toLowerCase()) {
          'year' => ReportNumber(value.year),
          'month' => ReportNumber(value.month),
          'day' => ReportNumber(value.day),
          'hour' => ReportNumber(value.hour),
          'minute' => ReportNumber(value.minute),
          _ => ReportNull.instance,
        };
      case ReportBinary(:final bytes):
        return name.toLowerCase() == 'length'
            ? ReportNumber(bytes.length)
            : ReportNull.instance;
      case ReportNull():
      case ReportNumber():
      case ReportBool():
        return ReportNull.instance;
    }
  }

  ReportValue _index(ReportValue target, ReportValue index) {
    if (target is ReportList) {
      final num? n = index.asNumber;
      if (n == null ||
          index is ReportText && num.tryParse(index.value) == null) {
        return _member(target, index.displayText, _emptyScope);
      }
      final int i = n.toInt();
      final int at = i < 0 ? target.items.length + i : i;
      return at >= 0 && at < target.items.length
          ? target.items[at]
          : ReportNull.instance;
    }
    if (target is ReportRecord) {
      return target.field(index.displayText) ?? ReportNull.instance;
    }
    if (target is ReportText) {
      final int? i = index.asNumber?.toInt();
      if (i == null || i < 0 || i >= target.value.length) {
        return ReportNull.instance;
      }
      return ReportText(target.value[i]);
    }
    return ReportNull.instance;
  }

  static final ReportScope _emptyScope = ReportScope(
    data: ReportRecord.empty,
    variables: ReportRecord.empty,
    system: ReportSystemInfo(now: DateTime.fromMillisecondsSinceEpoch(0)),
  );

  ReportValue _binary(
    ReportBinaryOp op,
    ReportExpr leftExpr,
    ReportExpr rightExpr,
    ReportScope scope,
  ) {
    if (op == ReportBinaryOp.and) {
      return ReportBool(
        _eval(leftExpr, scope).truthy && _eval(rightExpr, scope).truthy,
      );
    }
    if (op == ReportBinaryOp.or) {
      return ReportBool(
        _eval(leftExpr, scope).truthy || _eval(rightExpr, scope).truthy,
      );
    }
    if (op == ReportBinaryOp.coalesce) {
      final ReportValue l = _eval(leftExpr, scope);
      return _isEmpty(l) ? _eval(rightExpr, scope) : l;
    }
    final ReportValue a = _eval(leftExpr, scope);
    final ReportValue b = _eval(rightExpr, scope);
    switch (op) {
      case ReportBinaryOp.concat:
        return ReportText(_text(a) + _text(b));
      case ReportBinaryOp.add:
        if (a is ReportDate && b.asNumber != null) {
          return ReportDate(a.value.add(_days(b.asNumber!)));
        }
        if (_isTextual(a) || _isTextual(b)) {
          return ReportText(_text(a) + _text(b));
        }
        return _arith(a, b, (num x, num y) => x + y);
      case ReportBinaryOp.subtract:
        if (a is ReportDate && b is ReportDate) {
          return ReportNumber(a.value.difference(b.value).inHours / 24);
        }
        if (a is ReportDate && b.asNumber != null) {
          return ReportDate(a.value.subtract(_days(b.asNumber!)));
        }
        return _arith(a, b, (num x, num y) => x - y);
      case ReportBinaryOp.multiply:
        return _arith(a, b, (num x, num y) => x * y);
      case ReportBinaryOp.divide:
        final num? y = b.asNumber;
        if (y == null || y == 0) {
          return ReportNull.instance;
        }
        final num? x = a.asNumber;
        return x == null ? ReportNull.instance : ReportNumber(x / y);
      case ReportBinaryOp.modulo:
        final num? y = b.asNumber;
        if (y == null || y == 0) {
          return ReportNull.instance;
        }
        return _arith(a, b, (num x, num y) => x % y);
      case ReportBinaryOp.power:
        return _arith(a, b, (num x, num y) {
          final num r = math.pow(x, y);
          return r;
        });
      case ReportBinaryOp.equal:
        return ReportBool(reportValuesEqual(a, b));
      case ReportBinaryOp.notEqual:
        return ReportBool(!reportValuesEqual(a, b));
      case ReportBinaryOp.less:
        return ReportBool(compareReportValues(a, b) < 0);
      case ReportBinaryOp.lessOrEqual:
        return ReportBool(compareReportValues(a, b) <= 0);
      case ReportBinaryOp.greater:
        return ReportBool(compareReportValues(a, b) > 0);
      case ReportBinaryOp.greaterOrEqual:
        return ReportBool(compareReportValues(a, b) >= 0);
      case ReportBinaryOp.and:
      case ReportBinaryOp.or:
      case ReportBinaryOp.coalesce:
        return ReportNull.instance;
    }
  }

  static Duration _days(num days) =>
      Duration(milliseconds: (days * Duration.millisecondsPerDay).round());

  static bool _isTextual(ReportValue v) =>
      v is ReportText && num.tryParse(v.value.trim()) == null;

  String _text(ReportValue v) => formatter.display(v);

  static ReportValue _arith(
    ReportValue a,
    ReportValue b,
    num Function(num x, num y) f,
  ) {
    final num? x = a.isNull ? 0 : a.asNumber;
    final num? y = b.isNull ? 0 : b.asNumber;
    if (x == null || y == null) {
      return ReportNull.instance;
    }
    return ReportNumber(f(x, y));
  }

  static bool _isEmpty(ReportValue v) =>
      v is ReportNull ||
      (v is ReportText && v.value.isEmpty) ||
      (v is ReportList && v.items.isEmpty);

  bool _isRowRelative(ReportExpr expr, ReportScope scope) {
    for (final String id in ReportExpression.identifiers(expr)) {
      if (_isRowName(id)) {
        return true;
      }
      if (_isReservedRoot(id)) {
        continue;
      }
      if (scope.data.field(id) == null && scope.variables.field(id) == null) {
        return true;
      }
    }
    return false;
  }

  ReportValue _call(String name, List<ReportExpr> args, ReportScope scope) {
    if (_aggregates.contains(name)) {
      return _aggregate(name, args, scope);
    }
    switch (name) {
      case 'IF':
      case 'IIF':
        _arity(name, args, 2, 3);
        if (_eval(args[0], scope).truthy) {
          return _eval(args[1], scope);
        }
        return args.length > 2 ? _eval(args[2], scope) : ReportNull.instance;
      case 'COALESCE':
      case 'NVL':
      case 'ISNULL':
        if (name == 'ISNULL' && args.length == 1) {
          return ReportBool(_isEmpty(_eval(args[0], scope)));
        }
        for (final ReportExpr arg in args) {
          final ReportValue v = _eval(arg, scope);
          if (!_isEmpty(v)) {
            return v;
          }
        }
        return ReportNull.instance;
      case 'AND':
        return ReportBool(args.every((ReportExpr a) => _eval(a, scope).truthy));
      case 'OR':
        return ReportBool(args.any((ReportExpr a) => _eval(a, scope).truthy));
    }
    final List<ReportValue> v = <ReportValue>[
      for (final ReportExpr arg in args) _eval(arg, scope),
    ];
    final ReportFunction? custom = _custom[name];
    if (custom != null) {
      return custom(v);
    }
    return _builtin(name, v, scope);
  }

  ReportValue _aggregate(
    String name,
    List<ReportExpr> args,
    ReportScope scope,
  ) {
    final List<ReportValue>? rows = scope.aggregateRows;
    List<ReportValue> values;
    if (args.isEmpty) {
      if (name != 'COUNT') {
        throw ReportExpressionException('$name() needs an argument');
      }
      return ReportNumber(rows?.length ?? 0);
    }
    if (args.length > 1) {
      throw ReportExpressionException('$name() takes one argument');
    }
    final ReportExpr arg = args.first;
    if (rows != null && _isRowRelative(arg, scope)) {
      values = <ReportValue>[];
      for (int i = 0; i < rows.length; i++) {
        final ReportValue v = _eval(
          arg,
          scope.copyWith(row: rows[i], rowIndex: i),
        );
        if (v is ReportList) {
          values.addAll(v.flatten());
        } else {
          values.add(v);
        }
      }
    } else {
      final ReportValue v = _eval(arg, scope);
      values = v is ReportList ? v.flatten().toList() : <ReportValue>[v];
    }
    final List<ReportValue> present = values
        .where((ReportValue x) => !x.isNull)
        .toList(growable: false);
    switch (name) {
      case 'COUNT':
        return ReportNumber(present.length);
      case 'DISTINCTCOUNT':
      case 'COUNTDISTINCT':
        return ReportNumber(
          present.map((ReportValue x) => x.displayText).toSet().length,
        );
      case 'FIRST':
        return present.isEmpty ? ReportNull.instance : present.first;
      case 'LAST':
        return present.isEmpty ? ReportNull.instance : present.last;
      case 'MIN':
      case 'MAX':
        if (present.isEmpty) {
          return ReportNull.instance;
        }
        ReportValue best = present.first;
        for (final ReportValue x in present.skip(1)) {
          final int c = compareReportValues(x, best);
          if (name == 'MIN' ? c < 0 : c > 0) {
            best = x;
          }
        }
        return best;
    }
    num sum = 0;
    var count = 0;
    for (final ReportValue x in present) {
      final num? n = x.asNumber;
      if (n != null) {
        sum += n;
        count++;
      }
    }
    if (name == 'SUM') {
      return ReportNumber(sum);
    }
    return count == 0 ? ReportNull.instance : ReportNumber(sum / count);
  }

  static void _arity(String name, List<Object> args, int min, [int? max]) {
    final int hi = max ?? min;
    if (args.length < min || args.length > hi) {
      final String want = min == hi ? '$min' : '$min–$hi';
      throw ReportExpressionException(
        '$name() expects $want argument(s), got ${args.length}',
      );
    }
  }

  num _num(ReportValue v) => v.asNumber ?? 0;

  ReportValue _builtin(String name, List<ReportValue> a, ReportScope scope) {
    switch (name) {
      case 'TAFQEET':
        _arity(name, a, 1, 3);
        final num? amount = a[0].asNumber;
        if (amount == null) {
          return ReportNull.instance;
        }
        final String code = a.length > 1 ? a[1].displayText : 'LYD';
        final bool wrap = a.length < 3 || a[2].truthy;
        try {
          return ReportText(
            ArabicTafqeet.amount(
              amount,
              code,
              options: wrap ? const TafqeetOptions() : TafqeetOptions.plain,
            ),
          );
        } on TafqeetException catch (e) {
          throw ReportExpressionException(e.message);
        }
      case 'AMOUNTWORDS':
        _arity(name, a, 1, 3);
        final num? value = a[0].asNumber;
        if (value == null) {
          return ReportNull.instance;
        }
        final String currency = a.length > 1 ? a[1].displayText : 'USD';
        final bool arabic =
            a.length > 2 && a[2].displayText.trim().toLowerCase() == 'ar';
        try {
          return ReportText(
            arabic
                ? ArabicTafqeet.amount(value, currency)
                : EnglishWords.amount(value, currency),
          );
        } on TafqeetException catch (e) {
          throw ReportExpressionException(e.message);
        }
      case 'NUMBERWORDS':
        _arity(name, a, 1, 2);
        return ReportText(
          ArabicTafqeet.number(
            _num(a[0]).round(),
            feminine: a.length > 1 && a[1].truthy,
          ),
        );
      case 'ISEMPTY':
        _arity(name, a, 1);
        return ReportBool(_isEmpty(a[0]));
      case 'NOT':
        _arity(name, a, 1);
        return ReportBool(!a[0].truthy);
      case 'ROUND':
        _arity(name, a, 1, 2);
        final int digits = a.length > 1 ? _num(a[1]).toInt() : 0;
        final num x = _num(a[0]);
        final num f = math.pow(10, digits);
        final num r = (x * f).round() / f;
        return ReportNumber(digits <= 0 ? r.round() : r);
      case 'FLOOR':
        _arity(name, a, 1);
        return ReportNumber(_num(a[0]).floor());
      case 'CEIL':
      case 'CEILING':
        _arity(name, a, 1);
        return ReportNumber(_num(a[0]).ceil());
      case 'ABS':
        _arity(name, a, 1);
        return ReportNumber(_num(a[0]).abs());
      case 'MOD':
        _arity(name, a, 2);
        final num d = _num(a[1]);
        return d == 0 ? ReportNull.instance : ReportNumber(_num(a[0]) % d);
      case 'POWER':
        _arity(name, a, 2);
        return ReportNumber(math.pow(_num(a[0]), _num(a[1])));
      case 'SQRT':
        _arity(name, a, 1);
        return ReportNumber(math.sqrt(_num(a[0])));
      case 'CONCAT':
        return ReportText(a.map(_text).join());
      case 'UPPER':
        _arity(name, a, 1);
        return ReportText(_text(a[0]).toUpperCase());
      case 'LOWER':
        _arity(name, a, 1);
        return ReportText(_text(a[0]).toLowerCase());
      case 'TRIM':
        _arity(name, a, 1);
        return ReportText(_text(a[0]).trim());
      case 'LEN':
      case 'LENGTH':
        _arity(name, a, 1);
        final ReportValue x = a[0];
        return ReportNumber(x is ReportList ? x.items.length : _text(x).length);
      case 'LEFT':
        _arity(name, a, 2);
        final String s = _text(a[0]);
        return ReportText(
          s.substring(0, _num(a[1]).toInt().clamp(0, s.length)),
        );
      case 'RIGHT':
        _arity(name, a, 2);
        final String s = _text(a[0]);
        final int n = _num(a[1]).toInt().clamp(0, s.length);
        return ReportText(s.substring(s.length - n));
      case 'SUBSTR':
      case 'MID':
        _arity(name, a, 2, 3);
        final String s = _text(a[0]);
        final int start = _num(a[1]).toInt().clamp(0, s.length);
        final int len = a.length > 2
            ? _num(a[2]).toInt().clamp(0, s.length - start)
            : s.length - start;
        return ReportText(s.substring(start, start + len));
      case 'REPLACE':
        _arity(name, a, 3);
        return ReportText(_text(a[0]).replaceAll(_text(a[1]), _text(a[2])));
      case 'CONTAINS':
        _arity(name, a, 2);
        final ReportValue hay = a[0];
        if (hay is ReportList) {
          return ReportBool(
            hay.items.any((ReportValue x) => reportValuesEqual(x, a[1])),
          );
        }
        return ReportBool(_text(hay).contains(_text(a[1])));
      case 'STARTSWITH':
        _arity(name, a, 2);
        return ReportBool(_text(a[0]).startsWith(_text(a[1])));
      case 'ENDSWITH':
        _arity(name, a, 2);
        return ReportBool(_text(a[0]).endsWith(_text(a[1])));
      case 'PADLEFT':
        _arity(name, a, 2, 3);
        return ReportText(
          _text(
            a[0],
          ).padLeft(_num(a[1]).toInt(), a.length > 2 ? _text(a[2]) : ' '),
        );
      case 'JOIN':
        _arity(name, a, 1, 2);
        final ReportValue list = a[0];
        final String sep = a.length > 1 ? _text(a[1]) : ', ';
        if (list is ReportList) {
          return ReportText(list.flatten().map(_text).join(sep));
        }
        return ReportText(_text(list));
      case 'NOW':
        _arity(name, a, 0);
        return ReportDate(scope.system.now);
      case 'TODAY':
        _arity(name, a, 0);
        final DateTime n = scope.system.now;
        return ReportDate(DateTime(n.year, n.month, n.day));
      case 'DATE':
        if (a.length == 1) {
          final ReportValue x = a[0];
          if (x is ReportDate) {
            return x;
          }
          final DateTime? parsed = DateTime.tryParse(_text(x));
          return parsed == null ? ReportNull.instance : ReportDate(parsed);
        }
        _arity(name, a, 3);
        return ReportDate(
          DateTime(_num(a[0]).toInt(), _num(a[1]).toInt(), _num(a[2]).toInt()),
        );
      case 'YEAR':
      case 'MONTH':
      case 'DAY':
        _arity(name, a, 1);
        final ReportValue x = a[0];
        final DateTime? d = x is ReportDate
            ? x.value
            : DateTime.tryParse(_text(x));
        if (d == null) {
          return ReportNull.instance;
        }
        return ReportNumber(switch (name) {
          'YEAR' => d.year,
          'MONTH' => d.month,
          _ => d.day,
        });
      case 'NUMBER':
      case 'NUM':
      case 'TONUMBER':
        _arity(name, a, 1);
        final num? n = a[0].asNumber;
        return n == null ? ReportNull.instance : ReportNumber(n);
      case 'TEXT':
      case 'STR':
      case 'TOSTRING':
        _arity(name, a, 1, 2);
        return ReportText(
          a.length > 1 ? formatter.format(a[0], _text(a[1])) : _text(a[0]),
        );
      case 'FORMAT':
        _arity(name, a, 2);
        return ReportText(formatter.format(a[0], _text(a[1])));
    }
    throw ReportExpressionException('Unknown function $name()');
  }
}
