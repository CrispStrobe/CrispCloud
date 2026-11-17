import 'sml_conditional_format.dart';
import 'sml_workbook.dart';

/// A defined name and its owner. [localSheetId] is a zero-based worksheet
/// index, not the worksheet's OOXML sheetId. Null denotes workbook scope.
abstract class SmlDefinedName {
  SmlDefinedName({
    required this.name,
    this.localSheetId,
    Map<String, String>? attributes,
  }) : attributes = attributes ?? <String, String>{};

  String name;
  int? localSheetId;

  /// Native metadata such as hidden/comment, excluding name and localSheetId.
  final Map<String, String> attributes;
  String get formula;
}

/// An absolute cell/range definition editable by the compact spreadsheet model.
class SmlNamedRange extends SmlDefinedName {
  /// SmlNamedRange API.
  SmlNamedRange({
    required super.name,
    required this.sheetName,
    required this.range,
    super.localSheetId,
    super.attributes,
  });

  /// sheetName API.
  String sheetName;

  /// range API.
  SmlRange range;

  /// a1 API.
  String get a1 => '${range.start.a1}:${range.end.a1}';

  @override
  String get formula {
    String absolute(SmlCellRef cell) => cell.a1.replaceFirstMapped(
      RegExp(r'^([A-Z]+)(\d+)$'),
      (match) => '\$${match[1]}\$${match[2]}',
    );
    final first = absolute(range.start);
    final ref = range.isSingleCell ? first : '$first:${absolute(range.end)}';
    return "'${sheetName.replaceAll("'", "''")}'!$ref";
  }
}

/// Retains native scalar or unmodeled definitions without pretending they are
/// ordinary cell ranges. Evaluation deliberately supports only scalar literals.
class SmlFormulaName extends SmlDefinedName {
  SmlFormulaName({
    required super.name,
    required this.formula,
    super.localSheetId,
    super.attributes,
  });

  @override
  String formula;
}

/// How a cell value is validated.
enum SmlValidationKind { list, whole, decimal, date, textLength, custom }

/// Comparison operator used by non-list data validations.
enum SmlValidationOperator {
  between,
  notBetween,
  equal,
  notEqual,
  greaterThan,
  lessThan,
  greaterThanOrEqual,
  lessThanOrEqual,
}

/// Data-validation rule on a range.
class SmlDataValidation {
  /// SmlDataValidation API.
  SmlDataValidation({
    required this.range,
    required this.kind,
    this.formula1 = '',
    this.formula2 = '',
    this.operator = SmlValidationOperator.between,
    this.allowBlank = true,
    this.promptTitle = '',
    this.prompt = '',
    this.errorTitle = '',
    this.error = '',
    this.errorStyle = 'stop',
    this.listSourceRange,
    this.listSourceSheet,
  });

  /// range API.
  SmlRange range;

  /// kind API.
  SmlValidationKind kind;

  /// formula1 API.
  String formula1;

  /// formula2 API.
  String formula2;

  /// operator API.
  SmlValidationOperator operator;

  /// allowBlank API.
  bool allowBlank;

  /// Input-message title.
  String promptTitle;

  /// Input-message text.
  String prompt;

  /// errorTitle API.
  String errorTitle;

  /// error API.
  String error;

  /// Excel error style: stop, warning or information.
  String errorStyle;

  /// Optional range-backed list source retained for native ODF links.
  SmlRange? listSourceRange;

  /// Optional worksheet name for [listSourceRange].
  String? listSourceSheet;

  /// listItems API.
  List<String> get listItems {
    if (kind != SmlValidationKind.list) {
      return const <String>[];
    }
    var source = formula1.trim();
    if (source.length >= 2 && source.startsWith('"') && source.endsWith('"')) {
      source = source.substring(1, source.length - 1).replaceAll('""', '"');
    }
    return source
        .split(RegExp(r'[,،]'))
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
  }

  /// accepts API.
  bool accepts(String raw) {
    if (raw.isEmpty) {
      return allowBlank;
    }
    switch (kind) {
      case SmlValidationKind.list:
        return listItems.any(
          (String item) => item.toLowerCase() == raw.toLowerCase(),
        );
      case SmlValidationKind.whole:
        final double? n = double.tryParse(raw);
        return n != null && n == n.truncateToDouble() && _inNumericBounds(n);
      case SmlValidationKind.decimal:
        final double? n = double.tryParse(raw);
        return n != null && _inNumericBounds(n);
      case SmlValidationKind.date:
        final value = _dateBound(raw);
        final lower = _dateBound(formula1);
        final upper = _dateBound(formula2);
        return value != null && _inBounds(value, lower, upper);
      case SmlValidationKind.textLength:
        return _inNumericBounds(raw.length.toDouble());
      case SmlValidationKind.custom:
        return raw.isNotEmpty;
    }
  }

  bool _inNumericBounds(double value) {
    final lower = double.tryParse(formula1);
    final upper = double.tryParse(formula2);
    return _inBounds(value, lower, upper);
  }

  bool _inBounds(double value, double? lower, double? upper) {
    switch (operator) {
      case SmlValidationOperator.between:
        return (lower == null || value >= lower) &&
            (upper == null || value <= upper);
      case SmlValidationOperator.notBetween:
        return (lower == null || value < lower) ||
            (upper == null || value > upper);
      case SmlValidationOperator.equal:
        return lower != null && value == lower;
      case SmlValidationOperator.notEqual:
        return lower != null && value != lower;
      case SmlValidationOperator.greaterThan:
        return lower != null && value > lower;
      case SmlValidationOperator.lessThan:
        return lower != null && value < lower;
      case SmlValidationOperator.greaterThanOrEqual:
        return lower != null && value >= lower;
      case SmlValidationOperator.lessThanOrEqual:
        return lower != null && value <= lower;
    }
  }

  double? _dateBound(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final serial = double.tryParse(text);
    if (serial != null) return serial;
    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ].*)?$',
    ).firstMatch(text);
    if (match == null) return null;
    try {
      final date = DateTime.utc(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
      return date.difference(DateTime.utc(1899, 12, 30)).inMilliseconds /
          86400000;
    } on ArgumentError {
      return null;
    }
  }
}

/// Conditional format kinds hosts can paint.
enum SmlConditionalKind {
  greaterThan,
  greaterOrEqual,
  lessThan,
  lessOrEqual,
  equal,
  notEqual,
  between,
  notBetween,
  duplicate,
  contains,
  beginsWith,
  endsWith,
  top,
  bottom,
  topPercent,
  bottomPercent,
  aboveAverage,
  belowAverage,

  /// A native formula predicate, evaluated within the supported bounded
  /// conditional-formula subset and retained in full for interchange.
  expression,

  /// Continuous color scale over the numeric cells in the range.
  colorScale,

  /// Proportional bar over the numeric cells in the range.
  dataBar,

  /// Bucketed icon marker over the numeric cells in the range.
  iconSet,
}

/// One threshold/color stop in an ODF/XLSX color scale.
class SmlColorScaleStop {
  /// SmlColorScaleStop API.
  const SmlColorScaleStop({
    required this.type,
    this.value = 0,
    required this.colorRgb,
  });

  /// ODF/XLSX threshold kind.
  final String type;

  /// Threshold value for number/percent/percentile stops.
  final double value;

  /// Six-digit RGB color without alpha.
  final String colorRgb;
}

/// One conditional-format rule.
class SmlConditionalRule {
  /// SmlConditionalRule API.
  SmlConditionalRule({
    required this.range,
    required this.kind,
    this.formula = '',
    this.formula2 = '',
    this.fillRgb = 'FFF2CC',
    this.fontRgb = '',
    this.rank = 10,
    List<SmlColorScaleStop>? colorScaleStops,
    this.dataBarColor = '638EC6',
    this.iconSetType = '3TrafficLights1',
    this.priority,
    this.stopIfTrue = false,
    this.dxfId,
  }) : colorScaleStops = colorScaleStops ?? <SmlColorScaleStop>[];

  /// range API.
  SmlRange range;

  /// kind API.
  SmlConditionalKind kind;

  /// formula API.
  String formula;

  /// formula2 API. The upper bound for between/notBetween rules.
  String formula2;

  /// fillRgb API.
  String fillRgb;

  /// fontRgb API.
  String fontRgb;

  /// Rank for top/bottom rules, or the percentage for percent variants.
  int rank;

  /// Threshold/color stops for [SmlConditionalKind.colorScale] or data bars.
  final List<SmlColorScaleStop> colorScaleStops;

  /// RGB color for a [SmlConditionalKind.dataBar] rule.
  String dataBarColor;

  /// Excel/ODF icon-set identifier for [SmlConditionalKind.iconSet].
  String iconSetType;

  /// Native rule priority, with lower positive values evaluated first.
  /// Missing or invalid priorities receive an unused positive Int32 value
  /// during XLSX serialization without mutating this model field.
  int? priority;

  /// Whether a matching native rule stops lower-priority rules.
  bool stopIfTrue;

  /// Generated differential-style id, assigned during serialization.
  int? dxfId;

  /// Whether this rule matches [cell] without changing workbook cells/caches.
  /// Supply [workbook] for cross-sheet references and defined names. Unsupported
  /// formulas safely return false; rendering shares a resolver for one pass.
  bool matches(SmlCell cell, SmlWorksheet sheet, {SmlWorkbook? workbook}) =>
      SmlConditionalResolver(
        sheet: sheet,
        workbook: workbook,
      ).matches(this, cell);
}

/// AutoFilter + sort on a worksheet range.
class SmlAutoFilter {
  /// SmlAutoFilter API.
  SmlAutoFilter({required this.range, Map<int, Set<String>>? hiddenValues})
    : hiddenValues = hiddenValues ?? <int, Set<String>>{};

  /// range API.
  SmlRange range;

  /// Column index (relative to [range.minCol]) → values hidden by the filter.
  final Map<int, Set<String>> hiddenValues;

  /// enabled API.
  bool get enabled => hiddenValues.values.any((Set<String> v) => v.isNotEmpty);

  /// isRowHidden API.
  bool isRowHidden(SmlWorksheet sheet, int row) {
    if (row < range.minRow || row > range.maxRow) {
      return false;
    }
    if (row == range.minRow) {
      return false;
    }
    for (final MapEntry<int, Set<String>> entry in hiddenValues.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final int col = range.minCol + entry.key;
      final String text = sheet.cell(SmlCellRef(col, row)).asString;
      if (entry.value.contains(text)) {
        return true;
      }
    }
    return false;
  }

  /// uniqueValues API.
  List<String> uniqueValues(SmlWorksheet sheet, int relativeCol) {
    final int col = range.minCol + relativeCol;
    final Set<String> values = <String>{};
    for (int r = range.minRow + 1; r <= range.maxRow; r++) {
      final String text = sheet.cellOrNull(SmlCellRef(col, r))?.asString ?? '';
      if (text.isNotEmpty) {
        values.add(text);
      }
    }
    final List<String> list = values.toList()..sort();
    return list;
  }
}

/// Sort one column inside a range.
class SmlSortKey {
  /// SmlSortKey API.
  const SmlSortKey({required this.column, this.ascending = true});

  /// Absolute column index.
  final int column;

  /// ascending API.
  final bool ascending;
}

/// Sort / filter / validate / paint helpers.
abstract final class SmlAnalysis {
  /// sort API.
  static void sort(SmlWorksheet sheet, SmlRange range, List<SmlSortKey> keys) {
    if (keys.isEmpty) {
      return;
    }
    final int header = range.minRow;
    final List<int> body = <int>[
      for (int r = header + 1; r <= range.maxRow; r++) r,
    ];
    body.sort((int a, int b) {
      for (final SmlSortKey key in keys) {
        final String left = sheet.cell(SmlCellRef(key.column, a)).asString;
        final String right = sheet.cell(SmlCellRef(key.column, b)).asString;
        final double? ln = double.tryParse(left);
        final double? rn = double.tryParse(right);
        final int cmp;
        if (ln != null && rn != null) {
          cmp = ln.compareTo(rn);
        } else {
          cmp = left.toLowerCase().compareTo(right.toLowerCase());
        }
        if (cmp != 0) {
          return key.ascending ? cmp : -cmp;
        }
      }
      return 0;
    });
    final List<Map<int, SmlCell>> snapshot = <Map<int, SmlCell>>[
      for (final int r in body)
        <int, SmlCell>{
          for (int c = range.minCol; c <= range.maxCol; c++)
            c: _copyCell(sheet.cell(SmlCellRef(c, r))),
        },
    ];
    for (int i = 0; i < body.length; i++) {
      final int dest = header + 1 + i;
      for (int c = range.minCol; c <= range.maxCol; c++) {
        final SmlCell src = snapshot[i][c]!;
        final SmlCell cell = sheet.cell(SmlCellRef(c, dest));
        cell
          ..type = src.type
          ..value = src.value
          ..formula = src.formula
          ..styleIndex = src.styleIndex
          ..hasExplicitStyleIndex = src.hasExplicitStyleIndex
          ..fillRgb = src.fillRgb
          ..hasExplicitFillColorEdit = src.hasExplicitFillColorEdit
          ..fontRgb = src.fontRgb
          ..hasExplicitFontColorEdit = src.hasExplicitFontColorEdit
          ..fontBold = src.fontBold
          ..fontSize = src.fontSize
          ..fontFamily = src.fontFamily
          ..horizontalAlign = src.horizontalAlign
          ..wrapText = src.wrapText
          ..borderRgb = src.borderRgb
          ..borderWidth = src.borderWidth
          ..locked = src.locked;
      }
    }
  }

  /// applyConditional API.
  static void applyConditional(SmlWorksheet sheet) {
    for (final SmlConditionalRule rule in sheet.conditionalFormats) {
      if (rule.kind == SmlConditionalKind.colorScale) {
        _applyColorScale(sheet, rule);
        continue;
      }
      for (final SmlCellRef ref in rule.range.cells) {
        final SmlCell cell = sheet.cell(ref);
        if (rule.matches(cell, sheet)) {
          if (rule.fillRgb.isNotEmpty) {
            cell.fillRgb = rule.fillRgb;
          }
          if (rule.fontRgb.isNotEmpty) {
            cell.fontRgb = rule.fontRgb;
          }
        }
      }
    }
  }

  static void _applyColorScale(SmlWorksheet sheet, SmlConditionalRule rule) {
    final stops = rule.colorScaleStops;
    if (stops.length < 2) return;
    final values = <double>[
      for (final ref in rule.range.cells) ?sheet.cellOrNull(ref)?.asNumber,
    ];
    if (values.isEmpty) return;
    final sorted = [...values]..sort();
    final minimum = sorted.first;
    final maximum = sorted.last;
    double threshold(SmlColorScaleStop stop) {
      return switch (stop.type) {
        'minimum' || 'min' => minimum,
        'maximum' || 'max' => maximum,
        'percent' => minimum + (maximum - minimum) * stop.value / 100,
        'percentile' =>
          sorted[((sorted.length - 1) * stop.value / 100).round()],
        _ => stop.value,
      };
    }

    final thresholds = [for (final stop in stops) threshold(stop)];
    for (final ref in rule.range.cells) {
      final cell = sheet.cellOrNull(ref);
      final value = cell?.asNumber;
      if (cell == null || value == null) continue;
      var index = 0;
      while (index + 1 < thresholds.length && value > thresholds[index + 1]) {
        index++;
      }
      index = index.clamp(0, thresholds.length - 2);
      final left = thresholds[index];
      final right = thresholds[index + 1];
      final t = right == left ? 0.0 : (value - left) / (right - left);
      cell.fillRgb = _interpolateColor(
        stops[index].colorRgb,
        stops[index + 1].colorRgb,
        t.clamp(0, 1),
      );
    }
  }

  static String _interpolateColor(String from, String to, double t) {
    int channel(String value, int index) =>
        int.parse(value.substring(index * 2, index * 2 + 2), radix: 16);
    final a = [for (var i = 0; i < 3; i++) channel(from, i)];
    final b = [for (var i = 0; i < 3; i++) channel(to, i)];
    return [
      for (var i = 0; i < 3; i++)
        (a[i] + (b[i] - a[i]) * t)
            .round()
            .clamp(0, 255)
            .toRadixString(16)
            .padLeft(2, '0'),
    ].join().toUpperCase();
  }

  /// removeDuplicates API.
  static int removeDuplicates(SmlWorksheet sheet, SmlRange range) {
    final Set<String> seen = <String>{};
    var removed = 0;
    for (int r = range.maxRow; r > range.minRow; r--) {
      final String key = <String>[
        for (int c = range.minCol; c <= range.maxCol; c++)
          sheet.cell(SmlCellRef(c, r)).asString,
      ].join('\u0001');
      if (!seen.add(key)) {
        for (int c = range.minCol; c <= range.maxCol; c++) {
          final SmlCell cell = sheet.cell(SmlCellRef(c, r));
          cell
            ..value = null
            ..formula = null;
        }
        removed++;
      }
    }
    return removed;
  }

  static SmlCell _copyCell(SmlCell src) {
    return SmlCell(
      ref: src.ref,
      type: src.type,
      value: src.value,
      formula: src.formula,
      styleIndex: src.styleIndex,
      hasExplicitStyleIndex: src.hasExplicitStyleIndex,
      horizontalAlign: src.horizontalAlign,
      fillRgb: src.fillRgb,
      hasExplicitFillColorEdit: src.hasExplicitFillColorEdit,
      fontRgb: src.fontRgb,
      hasExplicitFontColorEdit: src.hasExplicitFontColorEdit,
      fontBold: src.fontBold,
      fontSize: src.fontSize,
      borderRgb: src.borderRgb,
      borderWidth: src.borderWidth,
      locked: src.locked,
      hyperlink: src.hyperlink,
    );
  }

  /// Returns an error string when [text] violates a rule covering [ref].
  static String? validateInput(
    SmlWorksheet sheet,
    SmlCellRef ref,
    String text,
  ) {
    for (final SmlDataValidation rule in sheet.validations) {
      if (rule.range.containsRef(ref) && !rule.accepts(text)) {
        return rule.error.isEmpty
            ? 'This value does not match the data validation restrictions.'
            : rule.error;
      }
    }
    return null;
  }

  /// Fills empty cells in [range] from the first populated cell in each column.
  static void fillSeries(SmlWorksheet sheet, SmlRange range) {
    for (int c = range.minCol; c <= range.maxCol; c++) {
      SmlCell? seed;
      var seedRow = range.minRow;
      SmlCell? second;
      var secondRow = range.minRow;
      for (int r = range.minRow; r <= range.maxRow; r++) {
        final SmlCell cell = sheet.cell(SmlCellRef(c, r));
        if (!cell.hasContent) {
          continue;
        }
        if (seed == null) {
          seed = cell;
          seedRow = r;
        } else {
          second = cell;
          secondRow = r;
          break;
        }
      }
      if (seed == null) {
        continue;
      }
      final double? a = seed.asNumber;
      final double? b = second?.asNumber;
      final double step;
      if (a != null && b != null && secondRow != seedRow) {
        step = (b - a) / (secondRow - seedRow);
      } else if (a != null) {
        step = 1;
      } else {
        step = 0;
      }
      for (int r = seedRow + 1; r <= range.maxRow; r++) {
        final SmlCell cell = sheet.cell(SmlCellRef(c, r));
        if (cell.hasContent) {
          continue;
        }
        if (a != null) {
          cell
            ..type = SmlCellType.number
            ..formula = null
            ..value = a + step * (r - seedRow);
        } else {
          cell
            ..type = seed.type
            ..formula = null
            ..value = seed.value;
        }
      }
    }
  }
}

/// A cell comment (`comments.xml`).
class SmlComment {
  /// SmlComment API.
  SmlComment({
    required this.ref,
    required this.text,
    this.author = 'Quds Office',
  });

  /// ref API.
  SmlCellRef ref;

  /// text API.
  String text;

  /// author API.
  String author;
}

/// Worksheet protection flag.
class SmlSheetProtection {
  /// SmlSheetProtection API.
  SmlSheetProtection({
    this.enabled = true,
    this.allowSelectLocked = true,
    this.password = '',
  });

  /// enabled API.
  bool enabled;

  /// allowSelectLocked API.
  bool allowSelectLocked;

  /// Optional plaintext password checked by the host before unprotecting.
  String password;
}

/// An Excel Table (ListObject).
class SmlTable {
  /// SmlTable API.
  SmlTable({
    required this.name,
    required this.range,
    this.headerRow = true,
    this.bandedRows = true,
  });

  /// name API.
  String name;

  /// range API.
  SmlRange range;

  /// headerRow API.
  bool headerRow;

  /// bandedRows API.
  bool bandedRows;

  /// headerName API.
  String headerName(SmlWorksheet sheet, int col) {
    if (!range.contains(col, range.minRow)) {
      return '';
    }
    return sheet.cell(SmlCellRef(col, range.minRow)).asString;
  }

  /// dataRangeForColumn API.
  SmlRange? dataRangeForColumn(SmlWorksheet sheet, String header) {
    for (int c = range.minCol; c <= range.maxCol; c++) {
      if (headerName(sheet, c).toUpperCase() == header.toUpperCase()) {
        final int r0 = headerRow ? range.minRow + 1 : range.minRow;
        if (r0 > range.maxRow) {
          return SmlRange(
            SmlCellRef(c, range.minRow),
            SmlCellRef(c, range.minRow),
          );
        }
        return SmlRange(SmlCellRef(c, r0), SmlCellRef(c, range.maxRow));
      }
    }
    return null;
  }

  /// dataRange API.
  SmlRange get dataRange {
    final int r0 = headerRow ? range.minRow + 1 : range.minRow;
    if (r0 > range.maxRow) {
      return range;
    }
    return SmlRange(
      SmlCellRef(range.minCol, r0),
      SmlCellRef(range.maxCol, range.maxRow),
    );
  }

  /// resolveRef API.
  static SmlRange? resolveRef(SmlWorksheet sheet, String token) {
    final int bracket = token.indexOf('[');
    final String tableName = (bracket < 0 ? token : token.substring(0, bracket))
        .trim();
    final String column = bracket < 0
        ? ''
        : token
              .substring(
                bracket + 1,
                token.endsWith(']') ? token.length - 1 : token.length,
              )
              .trim();
    for (final SmlTable table in sheet.tables) {
      if (table.name.toUpperCase() != tableName.toUpperCase()) {
        continue;
      }
      if (column.isEmpty) {
        return table.dataRange;
      }
      return table.dataRangeForColumn(sheet, column);
    }
    return null;
  }
}

/// A compact pivot cache: one row field, one data field, SUM aggregation.
class SmlPivotTable {
  /// SmlPivotTable API.
  SmlPivotTable({
    required this.source,
    required this.rowField,
    required this.dataField,
    this.name = 'Pivot',
    this.sourceSheetName,
    this.sourcePartUri,
    this.cachePartUri,
  });

  /// Imported pivot/cache owners and source worksheet name.
  String? sourcePartUri;
  String? cachePartUri;
  String? sourceSheetName;

  /// Source range including a header row.
  SmlRange source;

  /// 0-based column inside [source] used as the row label.
  int rowField;

  /// 0-based column inside [source] summed into values.
  int dataField;

  /// name API.
  String name;

  /// Evaluates grouped sums: header row + one result row per distinct label.
  List<List<Object?>> evaluate(SmlWorksheet sheet) {
    final int labelCol = source.minCol + rowField;
    final int valueCol = source.minCol + dataField;
    final String labelHeader = sheet
        .cell(SmlCellRef(labelCol, source.minRow))
        .asString;
    final String valueHeader = sheet
        .cell(SmlCellRef(valueCol, source.minRow))
        .asString;
    final Map<String, double> sums = <String, double>{};
    for (int r = source.minRow + 1; r <= source.maxRow; r++) {
      final String label = sheet.cell(SmlCellRef(labelCol, r)).asString;
      if (label.isEmpty) {
        continue;
      }
      final double n = sheet.cell(SmlCellRef(valueCol, r)).asNumber ?? 0;
      sums[label] = (sums[label] ?? 0) + n;
    }
    final List<String> keys = sums.keys.toList()..sort();
    return <List<Object?>>[
      <Object?>[
        labelHeader.isEmpty ? 'Row' : labelHeader,
        'Sum of $valueHeader',
      ],
      for (final String key in keys) <Object?>[key, sums[key]],
    ];
  }

  /// Writes the evaluated cache starting at [origin].
  void materialize(SmlWorksheet sheet, SmlCellRef origin) {
    final List<List<Object?>> rows = evaluate(sheet);
    for (int r = 0; r < rows.length; r++) {
      for (int c = 0; c < rows[r].length; c++) {
        final SmlCell cell = sheet.cell(
          SmlCellRef(origin.col + c, origin.row + r),
        );
        final Object? value = rows[r][c];
        cell.formula = null;
        if (value is num) {
          cell.type = SmlCellType.number;
          cell.value = value;
        } else {
          cell.type = SmlCellType.string;
          cell.value = value?.toString() ?? '';
        }
      }
    }
  }
}
