/// Sample data inferred from a template's bindings, for designer previews.
library;

import 'report_expression.dart';
import 'report_template.dart';

/// Builds plausible data for every binding a template uses, so a designer can
/// preview pagination, grouping, and totals before real data exists.
///
/// Row fields (`item.qty`, `SUM(items.total)`) become rows of the detail data
/// set; other paths (`invoiceNo`, `Data.customer.name`) become nested records.
/// Values follow the field name: `qty` → integers, `price` / `total` →
/// amounts (with `total = qty × price` when both exist), `date` → dates,
/// `category` / `groupBy` keys → a small set of repeating groups.
abstract final class ReportMockData {
  /// Data for [template] with [rows] detail rows.
  static Map<String, Object?> infer(
    ReportTemplate template, {
    int rows = 12,
    DateTime? now,
  }) {
    final _Bindings b = _Bindings.of(template);
    final DateTime today = now ?? DateTime(2026, 1, 1);
    final Map<String, Object?> data = <String, Object?>{};
    for (final String path in b.scalars) {
      _put(data, path.split('.'), _scalar(path, template.isRtl, today));
    }
    final List<String> fields = b.rowFields.toList()..sort();
    for (final String set in b.datasets) {
      _put(data, set.split('.'), <Map<String, Object?>>[
        for (int i = 0; i < rows; i++)
          _row(fields, i, b.groupFields, template.isRtl, today),
      ]);
    }
    return data;
  }

  /// Data-set paths (without a `Data.` prefix) used by [template].
  static List<String> datasets(ReportTemplate template) =>
      _Bindings.of(template).datasets.toList();

  /// Row field names used by [template] (`item.qty` → `qty`).
  static List<String> rowFields(ReportTemplate template) =>
      _Bindings.of(template).rowFields.toList()..sort();

  static void _put(Map<String, Object?> into, List<String> path, Object? v) {
    if (path.isEmpty) {
      return;
    }
    if (path.length == 1) {
      into[path.first] = v;
      return;
    }
    final Object? existing = into[path.first];
    final Map<String, Object?> child = existing is Map<String, Object?>
        ? existing
        : <String, Object?>{};
    into[path.first] = child;
    _put(child, path.sublist(1), v);
  }

  static Map<String, Object?> _row(
    List<String> fields,
    int i,
    Set<String> groupFields,
    bool rtl,
    DateTime today,
  ) {
    final Map<String, Object?> row = <String, Object?>{};
    String? qtyKey;
    String? priceKey;
    for (final String f in fields) {
      final String n = f.toLowerCase();
      if (groupFields.contains(f) || _isGroup(n)) {
        row[f] = rtl
            ? const <String>['أ', 'ب', 'ج'][(i ~/ 4) % 3]
            : const <String>['A', 'B', 'C'][(i ~/ 4) % 3];
        continue;
      }
      if (_isQuantity(n)) {
        qtyKey ??= f;
        row[f] = i % 5 + 1;
      } else if (_isUnitPrice(n)) {
        priceKey ??= f;
        row[f] = ((i % 7) + 1) * 12.5;
      } else {
        row[f] = _value(f, i, rtl, today);
      }
    }
    if (qtyKey != null && priceKey != null) {
      final num qty = row[qtyKey]! as num;
      final num price = row[priceKey]! as num;
      for (final String f in fields) {
        if (_isTotal(f.toLowerCase())) {
          row[f] = qty * price;
        }
      }
    }
    return row;
  }

  static Object? _scalar(String path, bool rtl, DateTime today) {
    final String leaf = path.split('.').last;
    final String n = leaf.toLowerCase();
    if (_isCode(n)) {
      final String letters = leaf.replaceAll(RegExp(r'[^A-Za-z]'), '');
      final String prefix = letters.length >= 3
          ? letters.substring(0, 3).toUpperCase()
          : 'DOC';
      return '$prefix-${today.year}-001';
    }
    return _value(leaf, 0, rtl, today);
  }

  static Object? _value(String field, int i, bool rtl, DateTime today) {
    final String n = field.toLowerCase();
    if (n.contains('month') && !_isAmount(n) && !_isTotal(n)) {
      return (rtl ? _monthsAr : _monthsEn)[i % 12];
    }
    if (_has(n, const <String>['region', 'branch', 'city'])) {
      return rtl
          ? const <String>['طرابلس', 'بنغازي', 'مصراتة', 'سبها'][i % 4]
          : const <String>['North', 'South', 'East', 'West'][i % 4];
    }
    if (_isDate(n)) {
      return today.subtract(Duration(days: i));
    }
    if (_isBool(n)) {
      return i.isEven;
    }
    if (_isQuantity(n)) {
      return i % 5 + 1;
    }
    if (_isUnitPrice(n) || _isTotal(n) || _isAmount(n)) {
      return ((i % 7) + 1) * 12.5;
    }
    if (n.contains('percent') || n.contains('rate')) {
      return 0.05 * ((i % 3) + 1);
    }
    if (_isCode(n)) {
      return 'P${(i + 1).toString().padLeft(2, '0')}';
    }
    if (n.contains('email')) {
      return 'user${i + 1}@example.com';
    }
    if (n.contains('phone') || n.contains('mobile')) {
      return '+218 91 000 ${(i + 100).toString()}';
    }
    if (_isName(n)) {
      return rtl ? 'صنف تجريبي ${i + 1}' : 'Sample item ${i + 1}';
    }
    return '$field ${i + 1}';
  }

  static const List<String> _monthsEn = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const List<String> _monthsAr = <String>[
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

  static bool _has(String n, List<String> keys) {
    for (final String k in keys) {
      if (n.contains(k)) {
        return true;
      }
    }
    return false;
  }

  static bool _isGroup(String n) =>
      _has(n, const <String>['category', 'group', 'section']) ||
      n == 'cat' ||
      n == 'type' ||
      n == 'kind';

  static bool _isQuantity(String n) =>
      _has(n, const <String>['qty', 'quantity', 'count', 'units', 'pieces']);

  static bool _isUnitPrice(String n) =>
      _has(n, const <String>['price', 'rate', 'cost', 'unit']);

  static bool _isTotal(String n) =>
      _has(n, const <String>['total', 'subtotal', 'net', 'gross', 'sum']);

  static bool _isAmount(String n) => _has(n, const <String>[
    'amount',
    'value',
    'tax',
    'vat',
    'discount',
    'balance',
    'paid',
    'due',
    'salary',
    'fee',
    'sales',
    'revenue',
    'profit',
    'expense',
    'stock',
    'target',
  ]);

  static bool _isDate(String n) =>
      _has(n, const <String>['date', 'time', 'day', 'created', 'updated']);

  static bool _isBool(String n) =>
      (n.startsWith('is') && n.length > 2) ||
      _has(n, const <String>['active', 'enabled', 'flag']);

  static bool _isCode(String n) =>
      _has(n, const <String>['code', 'sku', 'ref', 'serial', 'number']) ||
      n == 'id' ||
      n == 'no' ||
      n.endsWith('no') ||
      n.endsWith('id');

  static bool _isName(String n) => _has(n, const <String>[
    'name',
    'desc',
    'title',
    'item',
    'product',
    'label',
    'note',
  ]);
}

class _Bindings {
  _Bindings._(this._t);

  factory _Bindings.of(ReportTemplate t) => _Bindings._(t).._collect();

  final ReportTemplate _t;
  final Set<String> scalars = <String>{};
  final Set<String> rowFields = <String>{};
  final Set<String> groupFields = <String>{};
  final Set<String> datasets = <String>{};
  final List<String> _paths = <String>[];

  static const Set<String> _rowNames = <String>{'item', 'row', 'record'};
  static const Set<String> _reserved = <String>{
    'system',
    'variables',
    'vars',
    'var',
    'group',
  };

  void _collect() {
    for (final ReportBand band in _t.bands) {
      final String? set = band.dataSet;
      if (set != null && set.trim().isNotEmpty) {
        datasets.add(_stripData(set.trim()));
      }
      _expr(band.groupBy, groupKey: true);
      _expr(band.filter);
      _expr(band.visibleWhen);
      final String? sort = band.sortBy;
      if (sort != null) {
        try {
          for (final ({String source, bool? descending}) k
              in ReportExpression.sortKeys(sort)) {
            _expr(k.source);
          }
        } on ReportExpressionException {
          // Invalid sort specs are reported by validation, not here.
        }
      }
      for (final ReportElement e in band.elements) {
        _expr(e.visibleWhen);
        switch (e) {
          case ReportTextElement(:final String text):
            _text(text);
          case ReportImageElement(:final String source):
            if (source.contains('{{')) {
              _text(source);
            }
          case ReportBarcodeElement(:final String data):
            _text(data);
          case ReportShapeElement():
            break;
          case ReportChartElement():
            final String? chartSet = e.dataSet;
            if (chartSet != null && chartSet.trim().isNotEmpty) {
              datasets.add(_stripData(chartSet.trim()));
            }
            _text(e.title);
            _expr(e.category);
            for (final ReportChartSeries s in e.series) {
              _text(s.name);
              _expr(s.value);
            }
            for (final ReportChartPoint p in e.points) {
              _text(p.label);
              _expr(p.value);
            }
          case ReportCrosstabElement():
            final String? crossSet = e.dataSet;
            if (crossSet != null && crossSet.trim().isNotEmpty) {
              datasets.add(_stripData(crossSet.trim()));
            }
            _expr(e.rowField);
            _expr(e.columnField);
            _expr(e.valueField);
          case ReportSubreportElement():
            _expr(e.dataSet);
          case ReportTableElement():
            final String? tableSet = e.dataSet;
            if (tableSet != null && tableSet.trim().isNotEmpty) {
              datasets.add(_stripData(tableSet.trim()));
            }
            for (final ReportTableColumn c in e.columns) {
              _text(c.header);
            }
            for (final ReportTableCell c in <ReportTableCell>[
              ...e.cells,
              ...e.footerCells,
            ]) {
              _text(c.template);
            }
        }
      }
    }
    if (datasets.isEmpty && rowFields.isNotEmpty) {
      datasets.add('items');
    }
    for (final String path in _paths) {
      final List<String> parts = path.split('.');
      final String head = parts.first.toLowerCase();
      if (_rowNames.contains(head)) {
        if (parts.length > 1) {
          rowFields.add(parts[1]);
        }
        continue;
      }
      if (_reserved.contains(head)) {
        continue;
      }
      final String rest = _stripData(path);
      final String? set = _datasetOf(rest);
      if (set != null) {
        final String tail = rest.length > set.length
            ? rest.substring(set.length + 1)
            : '';
        if (tail.isNotEmpty) {
          rowFields.add(tail.split('.').first);
        }
        continue;
      }
      if (rest.isNotEmpty) {
        scalars.add(rest);
      }
    }
    if (datasets.isEmpty && rowFields.isNotEmpty) {
      datasets.add('items');
    }
    scalars.removeWhere((String s) => datasets.contains(s));
  }

  String? _datasetOf(String path) {
    for (final String set in datasets) {
      if (path == set || path.startsWith('$set.')) {
        return set;
      }
    }
    return null;
  }

  static String _stripData(String path) =>
      path.toLowerCase().startsWith('data.') ? path.substring(5) : path;

  void _text(String source) {
    if (!source.contains('{{')) {
      return;
    }
    try {
      for (final ReportExpression x in ReportTemplateText.parse(
        source,
      ).expressions) {
        _walk(x.root, _paths);
      }
    } on ReportExpressionException {
      // Malformed placeholders are reported by validation, not here.
    }
  }

  void _expr(String? source, {bool groupKey = false}) {
    if (source == null || source.trim().isEmpty) {
      return;
    }
    try {
      final ReportExpression x = ReportExpression.parse(source);
      final List<String> found = <String>[];
      _walk(x.root, found);
      _paths.addAll(found);
      if (groupKey) {
        for (final String p in found) {
          final List<String> parts = p.split('.');
          if (parts.length > 1 &&
              _rowNames.contains(parts.first.toLowerCase())) {
            groupFields.add(parts[1]);
          }
        }
      }
    } on ReportExpressionException {
      // Malformed expressions are reported by validation, not here.
    }
  }

  static void _walk(ReportExpr e, List<String> out) {
    final String? dotted = ReportExpression.dottedPath(e);
    if (dotted != null) {
      out.add(dotted);
      return;
    }
    switch (e) {
      case ReportLiteralExpr():
      case ReportIdentifierExpr():
        break;
      case ReportMemberExpr(:final ReportExpr target):
        _walk(target, out);
      case ReportIndexExpr(:final ReportExpr target, :final ReportExpr index):
        _walk(target, out);
        _walk(index, out);
      case ReportUnaryExpr(:final ReportExpr operand):
        _walk(operand, out);
      case ReportBinaryExpr(:final ReportExpr left, :final ReportExpr right):
        _walk(left, out);
        _walk(right, out);
      case ReportConditionalExpr(
        :final ReportExpr condition,
        :final ReportExpr whenTrue,
        :final ReportExpr whenFalse,
      ):
        _walk(condition, out);
        _walk(whenTrue, out);
        _walk(whenFalse, out);
      case ReportCallExpr(:final List<ReportExpr> arguments):
        for (final ReportExpr a in arguments) {
          _walk(a, out);
        }
    }
  }
}
