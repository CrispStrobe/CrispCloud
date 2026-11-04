/// Context-aware completions for `{{ }}` bindings and expressions.
library;

import 'arabic_tafqeet.dart';
import 'report_data.dart';
import 'report_template.dart';
import 'report_units.dart';

/// What a completion inserts.
enum ReportCompletionKind {
  /// Built-in or host function (`SUM(…)`).
  function,

  /// Root object (`Data`, `System`, `item`).
  root,

  /// Field of a record or row.
  field,

  /// List of rows (a dataset).
  dataset,

  /// Template variable.
  variable,

  /// `true` / `false` / `null`.
  keyword,

  /// Format spec after `|`.
  format,

  /// Currency code argument.
  currency,
}

/// One suggestion.
class ReportCompletionItem {
  /// ReportCompletionItem API.
  const ReportCompletionItem({
    required this.label,
    required this.insert,
    required this.kind,
    this.detail = '',
    this.caretBack = 0,
  });

  /// Text shown in the list.
  final String label;

  /// Replaces [ReportCompletionResult.start]..[ReportCompletionResult.end].
  final String insert;

  /// kind API.
  final ReportCompletionKind kind;

  /// Signature, description, or sample value.
  final String detail;

  /// Caret ends this many characters before the end of [insert]
  /// (inside the parentheses of a function).
  final int caretBack;
}

/// Suggestions for one caret position.
class ReportCompletionResult {
  /// ReportCompletionResult API.
  const ReportCompletionResult({
    required this.start,
    required this.end,
    required this.items,
  });

  /// Start of the replaced prefix.
  final int start;

  /// End of the replaced prefix (the caret).
  final int end;

  /// items API.
  final List<ReportCompletionItem> items;

  /// Text after applying [item] to [text], and the new caret.
  (String, int) apply(String text, ReportCompletionItem item) {
    final String out = text.replaceRange(start, end, item.insert);
    return (out, start + item.insert.length - item.caretBack);
  }
}

/// Built-in function documentation.
class ReportFunctionInfo {
  /// ReportFunctionInfo API.
  const ReportFunctionInfo(this.name, this.signature, this.description);

  /// name API.
  final String name;

  /// Argument list (`values`).
  final String signature;

  /// description API.
  final String description;
}

/// Computes completions from the template, the band being edited, and the
/// data the preview uses (field names come from real or mock rows).
class ReportCompleter {
  /// ReportCompleter API.
  const ReportCompleter({
    required this.template,
    this.band,
    this.data = const <String, Object?>{},
    this.hostFunctions = const <String>[],
    this.maxItems = 60,
    this.rowTable,
    this.rowSource,
    this.rowFieldsOnly = false,
  });

  /// template API.
  final ReportTemplate template;

  /// Band holding the edited element (row and group context).
  final ReportBand? band;

  /// Preview data (`Data.*`).
  final Map<String, Object?> data;

  /// Extra function names registered by the host.
  final List<String> hostFunctions;

  /// Cap on returned items.
  final int maxItems;

  /// Table whose columns a calculated field may name directly (`price`
  /// rather than `item.price`). Null outside that formula.
  final String? rowTable;

  /// Table that `Row` and `item` complete against. Null keeps the band's
  /// data set. A map label sets this to the map file's table.
  final String? rowSource;

  /// Roots are [rowTable]'s columns, `Row`, `Data`, `System`, and functions.
  /// Unrelated report records are left out.
  final bool rowFieldsOnly;

  /// Built-in functions in display order.
  static const List<ReportFunctionInfo> functions = <ReportFunctionInfo>[
    ReportFunctionInfo('SUM', 'values', 'Total of the values'),
    ReportFunctionInfo('COUNT', 'values', 'Number of non-empty values'),
    ReportFunctionInfo('AVG', 'values', 'Average'),
    ReportFunctionInfo('MIN', 'values', 'Smallest value'),
    ReportFunctionInfo('MAX', 'values', 'Largest value'),
    ReportFunctionInfo('DISTINCTCOUNT', 'values', 'Number of distinct values'),
    ReportFunctionInfo('FIRST', 'values', 'First value'),
    ReportFunctionInfo('LAST', 'values', 'Last value'),
    ReportFunctionInfo('TAFQEET', "amount, 'LYD'", 'Amount in Arabic words'),
    ReportFunctionInfo('NUMBERWORDS', 'n, feminine', 'Number in Arabic words'),
    ReportFunctionInfo(
      'AMOUNTWORDS',
      "amount, 'USD', 'en'",
      'Amount in English (or Arabic) words',
    ),
    ReportFunctionInfo('IF', 'condition, then, else', 'Conditional value'),
    ReportFunctionInfo('COALESCE', 'a, b, …', 'First non-empty value'),
    ReportFunctionInfo('ISEMPTY', 'value', 'True when null or blank'),
    ReportFunctionInfo('AND', 'a, b, …', 'All true'),
    ReportFunctionInfo('OR', 'a, b, …', 'Any true'),
    ReportFunctionInfo('NOT', 'value', 'Negation'),
    ReportFunctionInfo('ROUND', 'n, digits', 'Round to digits'),
    ReportFunctionInfo('FLOOR', 'n', 'Round down'),
    ReportFunctionInfo('CEIL', 'n', 'Round up'),
    ReportFunctionInfo('ABS', 'n', 'Absolute value'),
    ReportFunctionInfo('MOD', 'n, divisor', 'Remainder'),
    ReportFunctionInfo('POWER', 'n, exponent', 'Power'),
    ReportFunctionInfo('SQRT', 'n', 'Square root'),
    ReportFunctionInfo('FORMAT', "value, 'n2'", 'Format with a spec'),
    ReportFunctionInfo('CONCAT', 'a, b, …', 'Join texts'),
    ReportFunctionInfo('UPPER', 'text', 'Upper case'),
    ReportFunctionInfo('LOWER', 'text', 'Lower case'),
    ReportFunctionInfo('TRIM', 'text', 'Strip spaces'),
    ReportFunctionInfo('LEN', 'text', 'Length'),
    ReportFunctionInfo('LEFT', 'text, count', 'First characters'),
    ReportFunctionInfo('RIGHT', 'text, count', 'Last characters'),
    ReportFunctionInfo('SUBSTR', 'text, start, length', 'Part of a text'),
    ReportFunctionInfo('REPLACE', 'text, find, with', 'Replace all'),
    ReportFunctionInfo('CONTAINS', 'text, part', 'Text or list contains'),
    ReportFunctionInfo('STARTSWITH', 'text, part', 'Text starts with'),
    ReportFunctionInfo('ENDSWITH', 'text, part', 'Text ends with'),
    ReportFunctionInfo('PADLEFT', "text, width, '0'", 'Pad on the left'),
    ReportFunctionInfo('JOIN', "list, ', '", 'Join list values'),
    ReportFunctionInfo('NOW', '', 'Current date and time'),
    ReportFunctionInfo('TODAY', '', 'Current date'),
    ReportFunctionInfo('DATE', 'y, m, d', 'Build or parse a date'),
    ReportFunctionInfo('YEAR', 'date', 'Year of a date'),
    ReportFunctionInfo('MONTH', 'date', 'Month of a date'),
    ReportFunctionInfo('DAY', 'date', 'Day of a date'),
    ReportFunctionInfo('NUMBER', 'value', 'Convert to a number'),
    ReportFunctionInfo('TEXT', 'value', 'Convert to text'),
  ];

  static const List<(String, String)> _system = <(String, String)>[
    ('PageNumber', 'Current page'),
    ('TotalPages', 'Page count'),
    ('RowNumber', 'Row number (1-based)'),
    ('RowIndex', 'Row index (0-based)'),
    ('RowCount', 'Rows in scope'),
    ('CurrentDate', 'Today'),
    ('CurrentTime', 'Time of day'),
    ('CurrentDateTime', 'Date and time'),
    ('UserName', 'Current user'),
    ('ReportName', 'Template name'),
    ('GroupNumber', 'Group number'),
  ];

  static const List<(String, String)> _group = <(String, String)>[
    ('Key', 'Group value'),
    ('Count', 'Rows in the group'),
    ('Number', 'Group number (1-based)'),
    ('Index', 'Group index (0-based)'),
    ('Rows', 'Rows of the group'),
  ];

  /// Format specs with a sample of their output, offered after `|`.
  static List<(String, String)> get formats => _formats;

  static const List<(String, String)> _formats = <(String, String)>[
    ('n0', '1,235'),
    ('n2', '1,234.50'),
    ('n3', '1,234.500'),
    ('number:2', 'Two decimals'),
    ('integer', 'Whole number'),
    ('percent', '15%'),
    ('percent:1', '15.0%'),
    ('currency:LYD', '1,234.500 د.ل'),
    ('currency:USD', r'1,234.50 $'),
    ('currencyCode:USD', '1,234.50 USD'),
    ('tafqeet:LYD', 'Arabic words'),
    ('words:USD', 'English words'),
    ('date', 'Default date'),
    ('date:dd/MM/yyyy', '10/10/2026'),
    ('date:yyyy-MM-dd', '2026-10-10'),
    ('date:dd MMM yyyy', '10 Oct 2026'),
    ('dateAr:d MMMM yyyy', '10 أكتوبر 2026'),
    ('time', 'Default time'),
    ('datetime', 'Date and time'),
    ('#,##0.00', 'Custom pattern'),
    ('upper', 'Upper case'),
    ('lower', 'Lower case'),
    ('trim', 'Strip spaces'),
  ];

  static const List<String> _rowNames = <String>['item', 'row', 'record'];

  /// Suggestions at [caret] in [text]. Template text completes inside an
  /// open `{{`; with [expression] the whole text is an expression. Without
  /// [force], an empty prefix only completes right after `{{`, `(`, `,`,
  /// `.`, or `|`.
  ReportCompletionResult? complete(
    String text,
    int caret, {
    bool expression = false,
    bool force = false,
  }) {
    if (caret < 0 || caret > text.length) {
      return null;
    }
    int from = 0;
    if (!expression) {
      final int open = _openBinding(text, caret);
      if (open < 0) {
        return null;
      }
      from = open + 2;
    }
    final _Scan scan = _Scan.run(text, from, caret);
    if (scan.quote >= 0) {
      return _inString(text, caret, scan);
    }
    if (scan.pipe >= 0) {
      return _format(text, caret, scan.pipe + 1);
    }
    return _identifier(text, caret, from, force);
  }

  /// Format-spec suggestions for a field holding only a spec (`n2`).
  ReportCompletionResult? completeFormat(String text, int caret) =>
      caret < 0 || caret > text.length ? null : _format(text, caret, 0);

  // ---------------------------------------------------------------- context

  static int _openBinding(String text, int caret) {
    final int open = caret < 2 ? -1 : text.lastIndexOf('{{', caret - 2);
    if (open < 0) {
      return -1;
    }
    final int close = text.indexOf('}}', open + 2);
    if (close >= 0 && close + 2 <= caret) {
      return -1;
    }
    return open;
  }

  ReportCompletionResult? _inString(String text, int caret, _Scan scan) {
    final _Call? call = scan.calls.isEmpty ? null : scan.calls.last;
    if (call == null || call.argument != 1) {
      return null;
    }
    final int start = scan.quote + 1;
    final String prefix = text.substring(start, caret);
    final List<ReportCompletionItem> items;
    switch (call.name.toUpperCase()) {
      case 'TAFQEET' || 'AMOUNTWORDS':
        items = _currencies((String c) => c);
      case 'FORMAT':
        items = _formatItems();
      default:
        return null;
    }
    return _result(start, caret, prefix, items);
  }

  ReportCompletionResult? _format(String text, int caret, int afterPipe) {
    var start = afterPipe;
    while (start < caret && text.codeUnitAt(start) == 0x20) {
      start++;
    }
    final String prefix = text.substring(start, caret);
    final int colon = prefix.indexOf(':');
    if (colon > 0) {
      final String kind = prefix.substring(0, colon).toLowerCase();
      if (kind == 'currency' ||
          kind == 'currencycode' ||
          kind == 'tafqeet' ||
          kind == 'words') {
        final String head = prefix.substring(0, colon + 1);
        return _result(
          start,
          caret,
          prefix,
          _currencies((String c) => '$head$c'),
        );
      }
    }
    return _result(start, caret, prefix, _formatItems());
  }

  List<ReportCompletionItem> _formatItems() => <ReportCompletionItem>[
    for (final (String spec, String sample) in _formats)
      ReportCompletionItem(
        label: spec,
        insert: spec,
        kind: ReportCompletionKind.format,
        detail: sample,
      ),
  ];

  static List<ReportCompletionItem> _currencies(String Function(String) wrap) {
    final List<String> codes = <String>[
      ...ArabicTafqeet.currencyCodes,
      for (final String c in const <String>['USD', 'EUR', 'GBP'])
        if (!ArabicTafqeet.currencyCodes.contains(c)) c,
    ];
    return <ReportCompletionItem>[
      for (final String c in codes)
        ReportCompletionItem(
          label: wrap(c),
          insert: wrap(c),
          kind: ReportCompletionKind.currency,
        ),
    ];
  }

  static bool _identStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      (c >= 0x0600 && c <= 0x06FF);

  static bool _identPart(int c) => _identStart(c) || (c >= 0x30 && c <= 0x39);

  ReportCompletionResult? _identifier(
    String text,
    int caret,
    int from,
    bool force,
  ) {
    var i = caret;
    while (i > from) {
      final int c = text.codeUnitAt(i - 1);
      if (_identPart(c) || c == 0x2E) {
        i--;
      } else {
        break;
      }
    }
    final String token = text.substring(i, caret);
    if (token.isNotEmpty && !_identStart(token.codeUnitAt(0))) {
      return null;
    }
    if (token.contains('..')) {
      return null;
    }
    final int dot = token.lastIndexOf('.');
    final String prefix = dot < 0 ? token : token.substring(dot + 1);
    final List<String> parents = dot < 0
        ? const <String>[]
        : token.substring(0, dot).split('.');
    if (prefix.isEmpty && parents.isEmpty && !force) {
      var j = i;
      while (j > from && text.codeUnitAt(j - 1) == 0x20) {
        j--;
      }
      final bool trigger =
          j == from || const <int>{0x28, 0x2C}.contains(text.codeUnitAt(j - 1));
      if (!trigger) {
        return null;
      }
    }
    final int start = caret - prefix.length;
    final List<ReportCompletionItem> items = parents.isEmpty
        ? _roots()
        : _children(parents);
    final ReportCompletionResult? r = _result(start, caret, prefix, items);
    if (r != null &&
        r.items.length == 1 &&
        r.items.first.insert == prefix &&
        r.items.first.kind != ReportCompletionKind.function) {
      return null;
    }
    return r;
  }

  // ---------------------------------------------------------------- items

  String? get _rowDataset {
    final String? bound = rowSource?.trim();
    if (bound != null && bound.isNotEmpty) {
      return bound;
    }
    final ReportBand? b = band;
    final String? own = b?.dataSet;
    if (own != null && own.trim().isNotEmpty) {
      return own.trim();
    }
    for (final ReportBand d in template.bands) {
      if (d.kind == ReportBandKind.detail &&
          d.dataSet != null &&
          d.dataSet!.trim().isNotEmpty) {
        return d.dataSet!.trim();
      }
    }
    return null;
  }

  bool get _inGroup {
    final ReportBandKind? k = band?.kind;
    return k == ReportBandKind.groupHeader ||
        k == ReportBandKind.groupFooter ||
        (k == ReportBandKind.detail && band?.groupBy != null);
  }

  List<ReportCompletionItem> _roots() {
    final String? rows = _rowDataset;
    final String? table = rowTable?.trim();
    final List<ReportCompletionItem> bare = table == null || table.isEmpty
        ? const <ReportCompletionItem>[]
        : _bareRowFields(table);
    final Set<String> bareNames = <String>{
      for (final ReportCompletionItem i in bare) i.insert.toLowerCase(),
    };
    final List<ReportCompletionItem> out = <ReportCompletionItem>[
      ...bare,
      if (rowFieldsOnly && rows != null)
        ReportCompletionItem(
          label: 'Row',
          insert: 'Row',
          kind: ReportCompletionKind.root,
          detail: 'Map fields',
        )
      else if (rows != null)
        ReportCompletionItem(
          label: 'item',
          insert: 'item',
          kind: ReportCompletionKind.root,
          detail: 'Current row of $rows',
        ),
      const ReportCompletionItem(
        label: 'Data',
        insert: 'Data',
        kind: ReportCompletionKind.root,
        detail: 'Report data',
      ),
      const ReportCompletionItem(
        label: 'System',
        insert: 'System',
        kind: ReportCompletionKind.root,
        detail: 'Page, row, date',
      ),
      if (template.variables.isNotEmpty)
        const ReportCompletionItem(
          label: 'Variables',
          insert: 'Variables',
          kind: ReportCompletionKind.root,
          detail: 'Template variables',
        ),
      if (_inGroup)
        const ReportCompletionItem(
          label: 'Group',
          insert: 'Group',
          kind: ReportCompletionKind.root,
          detail: 'Current group',
        ),
      if (!rowFieldsOnly)
        for (final MapEntry<String, Object?> e in data.entries)
          if (!bareNames.contains(e.key.toLowerCase()))
            _valueItem(e.key, e.value),
      for (final ReportFunctionInfo f in functions)
        ReportCompletionItem(
          label: '${f.name}(${f.signature})',
          insert: '${f.name}()',
          kind: ReportCompletionKind.function,
          detail: f.description,
          caretBack: 1,
        ),
      for (final String f in hostFunctions)
        ReportCompletionItem(
          label: '${f.toUpperCase()}(…)',
          insert: '${f.toUpperCase()}()',
          kind: ReportCompletionKind.function,
          detail: 'Host function',
          caretBack: 1,
        ),
      for (final String k in const <String>['true', 'false', 'null'])
        ReportCompletionItem(
          label: k,
          insert: k,
          kind: ReportCompletionKind.keyword,
        ),
    ];
    return out;
  }

  /// Columns of [table], inserted as bare names. Reserved roots (`Data`,
  /// `item`, …) are left out: those names do not resolve to the column.
  List<ReportCompletionItem> _bareRowFields(String table) {
    final ReportDataTable? declared = template.dataSchema.table(table);
    final List<ReportCompletionItem> out = <ReportCompletionItem>[];
    final Set<String> seen = <String>{};
    void add(String name, String detail) {
      if (name.isEmpty || _reservedBare.contains(name.toLowerCase())) {
        return;
      }
      if (!seen.add(name.toLowerCase())) {
        return;
      }
      out.add(
        ReportCompletionItem(
          label: name,
          insert: name,
          kind: ReportCompletionKind.field,
          detail: detail,
        ),
      );
    }

    if (declared != null) {
      for (final ReportDataColumn c in declared.columns) {
        add(c.name, c.isCalculated ? '= ${c.expression!.trim()}' : c.type.name);
      }
    }
    final Object? row = _firstRow(_resolve(table));
    if (row is Map) {
      for (final MapEntry<Object?, Object?> e in row.entries) {
        add('${e.key}', _preview(e.value));
      }
    }
    return out;
  }

  static const Set<String> _reservedBare = <String>{
    'system',
    'variables',
    'vars',
    'var',
    'data',
    'group',
    'item',
    'row',
    'record',
  };

  /// Variables and folders directly under [folder] (`[]` is the top level,
  /// `['stats']` lists `stats.sum` as `sum`).
  List<ReportCompletionItem> _variablesUnder(List<String> folder) {
    final String prefix = folder.isEmpty
        ? ''
        : '${folder.join('.').toLowerCase()}.';
    final List<ReportCompletionItem> out = <ReportCompletionItem>[];
    final Map<String, int> subfolders = <String, int>{};
    for (final ReportVariable v in template.variables) {
      if (!v.name.toLowerCase().startsWith(prefix)) {
        continue;
      }
      final String rest = v.name.substring(prefix.length);
      final int dot = rest.indexOf('.');
      if (dot < 0) {
        out.add(
          ReportCompletionItem(
            label: rest,
            insert: rest,
            kind: ReportCompletionKind.variable,
            detail: v.description.isNotEmpty
                ? v.description
                : '${v.type.name} · ${v.value}',
          ),
        );
      } else {
        final String name = rest.substring(0, dot);
        subfolders[name] = (subfolders[name] ?? 0) + 1;
      }
    }
    return <ReportCompletionItem>[
      for (final MapEntry<String, int> f in subfolders.entries)
        ReportCompletionItem(
          label: f.key,
          insert: f.key,
          kind: ReportCompletionKind.field,
          detail: '${f.value} ${f.value == 1 ? 'variable' : 'variables'}',
        ),
      ...out,
    ];
  }

  List<ReportCompletionItem> _children(List<String> parents) {
    final String root = parents.first.toLowerCase();
    final List<String> rest = parents.sublist(1);
    switch (root) {
      case 'system':
        return rest.isNotEmpty
            ? const <ReportCompletionItem>[]
            : <ReportCompletionItem>[
                for (final (String n, String d) in _system)
                  ReportCompletionItem(
                    label: n,
                    insert: n,
                    kind: ReportCompletionKind.field,
                    detail: d,
                  ),
              ];
      case 'group':
        if (rest.isEmpty) {
          return <ReportCompletionItem>[
            for (final (String n, String d) in _group)
              ReportCompletionItem(
                label: n,
                insert: n,
                kind: ReportCompletionKind.field,
                detail: d,
              ),
          ];
        }
        if (rest.length == 1 && rest.first.toLowerCase() == 'rows') {
          return _withColumns(_fieldsOf(_resolve(_rowDataset)), _rowDataset);
        }
        return const <ReportCompletionItem>[];
      case 'variables' || 'vars' || 'var':
        return _variablesUnder(rest);
      case 'data':
        return _withColumns(_fieldsOf(_walk(data, rest)), rest.join('.'));
    }
    if (_rowNames.contains(root)) {
      return _withColumns(
        _fieldsOf(_walk(_firstRow(_resolve(_rowDataset)), rest)),
        rest.isEmpty ? _rowDataset : null,
      );
    }
    final Object? top = _lookup(data, parents.first);
    return _withColumns(
      top == null ? <ReportCompletionItem>[] : _fieldsOf(_walk(top, rest)),
      parents.join('.'),
    );
  }

  /// [items] plus the columns `<DataSchema>` declares for table [path] that
  /// the data does not carry (calculated columns, tables without rows yet).
  List<ReportCompletionItem> _withColumns(
    List<ReportCompletionItem> items,
    String? path,
  ) {
    final ReportDataTable? table = path == null || path.isEmpty
        ? null
        : template.dataSchema.table(path);
    if (table == null) {
      return items;
    }
    final Set<String> known = <String>{
      for (final ReportCompletionItem i in items) i.label.toLowerCase(),
    };
    final List<ReportCompletionItem> out = <ReportCompletionItem>[...items];
    for (final ReportDataColumn c in table.columns) {
      if (c.name.isEmpty || known.contains(c.name.toLowerCase())) {
        continue;
      }
      out.insert(
        out.length - (items.isNotEmpty && items.last.label == 'count' ? 1 : 0),
        ReportCompletionItem(
          label: c.name,
          insert: c.name,
          kind: ReportCompletionKind.field,
          detail: c.isCalculated ? '= ${c.expression!.trim()}' : c.type.name,
        ),
      );
    }
    return out;
  }

  Object? _resolve(String? path) {
    if (path == null) {
      return null;
    }
    final List<String> parts = path.split('.');
    if (parts.first.toLowerCase() == 'data') {
      parts.removeAt(0);
    }
    return _walk(data, parts);
  }

  static Object? _firstRow(Object? v) {
    if (v is List<Object?>) {
      for (final Object? x in v) {
        if (x is Map) {
          return x;
        }
      }
      return null;
    }
    return v;
  }

  static Object? _lookup(Object? v, String name) {
    if (v is Map) {
      final String n = name.toLowerCase();
      for (final MapEntry<Object?, Object?> e in v.entries) {
        if ('${e.key}'.toLowerCase() == n) {
          return e.value;
        }
      }
      return null;
    }
    if (v is List<Object?>) {
      return _lookup(_firstRow(v), name);
    }
    return null;
  }

  static Object? _walk(Object? from, List<String> parts) {
    Object? v = from;
    for (final String p in parts) {
      v = _lookup(v, p);
      if (v == null) {
        return null;
      }
    }
    return v;
  }

  List<ReportCompletionItem> _fieldsOf(Object? v) {
    final Object? record = v is List<Object?> ? _firstRow(v) : v;
    final List<ReportCompletionItem> out = <ReportCompletionItem>[];
    if (record is Map) {
      for (final MapEntry<Object?, Object?> e in record.entries) {
        out.add(_valueItem('${e.key}', e.value));
      }
    }
    if (v is List<Object?>) {
      out.add(
        ReportCompletionItem(
          label: 'count',
          insert: 'count',
          kind: ReportCompletionKind.field,
          detail: '${v.length} rows',
        ),
      );
    }
    return out;
  }

  static ReportCompletionItem _valueItem(String name, Object? v) {
    final ReportCompletionKind kind = v is List<Object?>
        ? ReportCompletionKind.dataset
        : ReportCompletionKind.field;
    return ReportCompletionItem(
      label: name,
      insert: name,
      kind: kind,
      detail: _preview(v),
    );
  }

  static String _preview(Object? v) {
    switch (v) {
      case null:
        return 'null';
      case num():
        return ReportUnits.trimNumber(v.toDouble(), decimals: 3);
      case bool():
        return '$v';
      case DateTime():
        return v.toIso8601String().split('T').first;
      case String():
        final String s = v.replaceAll('\n', ' ');
        return s.length > 28 ? '"${s.substring(0, 27)}…"' : '"$s"';
      case List<Object?>():
        return 'list · ${v.length} rows';
      case Map():
        return 'record';
    }
    return '$v';
  }

  ReportCompletionResult? _result(
    int start,
    int end,
    String prefix,
    List<ReportCompletionItem> items,
  ) {
    final String p = prefix.toLowerCase();
    final List<ReportCompletionItem> head = <ReportCompletionItem>[];
    final List<ReportCompletionItem> tail = <ReportCompletionItem>[];
    final Set<String> seen = <String>{};
    for (final ReportCompletionItem it in items) {
      if (!seen.add('${it.kind.index}|${it.insert}')) {
        continue;
      }
      final String l = it.insert.toLowerCase();
      if (l.startsWith(p)) {
        head.add(it);
      } else if (p.length >= 2 && l.contains(p)) {
        tail.add(it);
      }
    }
    final List<ReportCompletionItem> all = <ReportCompletionItem>[
      ...head,
      ...tail,
    ];
    if (all.isEmpty) {
      return null;
    }
    return ReportCompletionResult(
      start: start,
      end: end,
      items: all.length > maxItems ? all.sublist(0, maxItems) : all,
    );
  }
}

class _Call {
  _Call(this.name);

  final String name;
  var argument = 0;
}

class _Scan {
  _Scan._();

  /// Offset of the open quote when the caret is inside a string, else -1.
  var quote = -1;

  /// Offset of the last top-level format `|`, else -1.
  var pipe = -1;

  /// Open calls, innermost last (`''` for plain parentheses).
  final List<_Call> calls = <_Call>[];

  static _Scan run(String text, int from, int to) {
    final _Scan s = _Scan._();
    int quoteChar = 0;
    for (int i = from; i < to; i++) {
      final int c = text.codeUnitAt(i);
      if (quoteChar != 0) {
        if (c == 0x5C) {
          i++;
        } else if (c == quoteChar) {
          quoteChar = 0;
          s.quote = -1;
        }
        continue;
      }
      switch (c) {
        case 0x27 || 0x22:
          quoteChar = c;
          s.quote = i;
        case 0x28:
          var j = i;
          while (j > from && text.codeUnitAt(j - 1) == 0x20) {
            j--;
          }
          var k = j;
          while (k > from &&
              ReportCompleter._identPart(text.codeUnitAt(k - 1))) {
            k--;
          }
          s.calls.add(_Call(text.substring(k, j)));
        case 0x29:
          if (s.calls.isNotEmpty) {
            s.calls.removeLast();
          }
        case 0x2C:
          if (s.calls.isNotEmpty) {
            s.calls.last.argument++;
          }
        case 0x7C:
          final bool doubled =
              (i + 1 < to && text.codeUnitAt(i + 1) == 0x7C) ||
              (i > from && text.codeUnitAt(i - 1) == 0x7C);
          if (!doubled && s.calls.isEmpty) {
            s.pipe = i;
          }
      }
    }
    return s;
  }
}
