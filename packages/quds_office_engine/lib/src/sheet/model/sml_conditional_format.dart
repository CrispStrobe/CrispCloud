import '../formula/formula_ast.dart';
import '../formula/formula_eval.dart';
import '../formula/formula_refs.dart';
import 'sml_analysis.dart';
import 'sml_workbook.dart';

/// The supported differential properties, without ordinary cell formatting.
/// Null means that no matching rule supplied that property.
class SmlConditionalStyle {
  const SmlConditionalStyle({
    this.fillRgb,
    this.fontRgb,
    this.dataBarFraction,
    this.dataBarColor,
    this.iconSetIndex,
    this.iconSetType,
  });

  final String? fillRgb;
  final String? fontRgb;
  final double? dataBarFraction;
  final String? dataBarColor;
  final int? iconSetIndex;
  final String? iconSetType;
}

/// Resolves conditional colors for one paint/export operation. Create a new
/// resolver after any workbook edit; its value and aggregate caches are local
/// to that operation. Evaluation never creates cells or changes formula caches.
class SmlConditionalResolver {
  SmlConditionalResolver({
    required this.sheet,
    SmlWorkbook? workbook,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _formulas = _ConditionalFormulas(
         workbook ?? SmlWorkbook(sheets: [sheet]),
       ) {
    final priorities = effectivePriorities(sheet.conditionalFormats);
    final order = List<int>.generate(priorities.length, (index) => index)
      ..sort((left, right) => priorities[left].compareTo(priorities[right]));
    _rules = [for (final index in order) sheet.conditionalFormats[index]];
  }

  final SmlWorksheet sheet;
  final DateTime Function() _now;
  final _ConditionalFormulas _formulas;
  late final List<SmlConditionalRule> _rules;
  final _styles = <(int, int), SmlConditionalStyle>{};
  final _aggregates = <SmlConditionalRule, _ConditionalAggregate>{};

  /// Shared with XLSX serialization so missing/duplicate/invalid priorities
  /// have the same deterministic precedence before and after a save.
  static List<int> effectivePriorities(List<SmlConditionalRule> rules) {
    const maximum = 0x7fffffff;
    bool valid(int? priority) =>
        priority != null && priority > 0 && priority <= maximum;
    final reserved = <int>{
      for (final rule in rules)
        if (valid(rule.priority)) rule.priority!,
    };
    var next = 1;
    for (final priority in reserved) {
      if (priority >= next) next = priority + 1;
    }
    final used = <int>{};
    final result = <int>[];
    for (final rule in rules) {
      final priority = rule.priority;
      if (priority != null && valid(priority) && used.add(priority)) {
        result.add(priority);
        continue;
      }
      if (next > maximum) next = 1;
      while (reserved.contains(next) || used.contains(next)) {
        next = next == maximum ? 1 : next + 1;
      }
      used.add(next);
      result.add(next++);
    }
    return result;
  }

  /// Includes absent cells in a painted region without materializing them.
  SmlConditionalStyle resolve(SmlCellRef ref) =>
      _styles.putIfAbsent((ref.col, ref.row), () {
        String? fill;
        String? font;
        double? dataBarFraction;
        String? dataBarColor;
        int? iconSetIndex;
        String? iconSetType;
        final cell = sheet.cellOrNull(ref) ?? SmlCell(ref: ref);
        for (final rule in _rules) {
          if (!rule.range.containsRef(ref)) continue;
          if (rule.kind == SmlConditionalKind.dataBar) {
            final fraction = _dataBarFraction(rule, cell);
            if (fraction != null) {
              dataBarFraction = fraction;
              dataBarColor = rule.dataBarColor;
            }
            if (rule.stopIfTrue) break;
            continue;
          }
          if (rule.kind == SmlConditionalKind.iconSet) {
            final index = _iconSetIndex(rule, cell);
            if (index != null) {
              iconSetIndex = index;
              iconSetType = rule.iconSetType;
            }
            if (rule.stopIfTrue) break;
            continue;
          }
          if (!matches(rule, cell)) continue;
          if (rule.fillRgb.isNotEmpty) fill ??= rule.fillRgb;
          if (rule.fontRgb.isNotEmpty) font ??= rule.fontRgb;
          if (rule.stopIfTrue) break;
        }
        return SmlConditionalStyle(
          fillRgb: fill,
          fontRgb: font,
          dataBarFraction: dataBarFraction,
          dataBarColor: dataBarColor,
          iconSetIndex: iconSetIndex,
          iconSetType: iconSetType,
        );
      });

  /// Evaluates the modeled rule kinds. Unsupported formulas and actual errors
  /// do not match. Formula references are relative to the range's top-left cell.
  double? _dataBarFraction(SmlConditionalRule rule, SmlCell cell) {
    final number = _number(_formulas.cellValue(sheet, cell));
    if (number == null) return null;
    final values = _aggregate(rule).numbers;
    if (values.isEmpty) return null;
    final stops = rule.colorScaleStops;
    var minimum = values.first;
    var maximum = values.last;
    if (stops.length >= 2) {
      final lower = stops.first.resolveThreshold(values);
      final upper = stops.last.resolveThreshold(values);
      if (lower == null || upper == null) return null;
      minimum = lower;
      maximum = upper;
    }
    if (maximum <= minimum) return null;
    return ((number - minimum) / (maximum - minimum)).clamp(0.0, 1.0);
  }

  int? _iconSetIndex(SmlConditionalRule rule, SmlCell cell) {
    final number = _number(_formulas.cellValue(sheet, cell));
    if (number == null) return null;
    final stops = rule.colorScaleStops;
    if (stops.isEmpty) return null;
    final values = _aggregate(rule).numbers;
    var index = 0;
    // The first entry identifies the lowest bucket; later entries delimit it.
    for (var i = 1; i < stops.length; i++) {
      final threshold = stops[i].resolveThreshold(values);
      if (threshold == null) return null;
      if (number >= threshold) index = i;
    }
    return index;
  }

  bool _matchesTimePeriod(SmlConditionalRule rule, double serial) {
    final cellDate = DateTime.utc(
      1899,
      12,
      30,
    ).add(Duration(days: serial.floor()));
    final now = _now();
    // Spreadsheet serials and period boundaries represent civil dates. Keep
    // the clock's calendar fields, but compare/arithmetic in UTC so timezone
    // offsets and daylight-saving transitions cannot move a boundary day.
    final today = DateTime.utc(now.year, now.month, now.day);
    bool sameDay(DateTime date, DateTime other) =>
        date.year == other.year &&
        date.month == other.month &&
        date.day == other.day;
    DateTime monthOffset(int months) =>
        DateTime.utc(today.year, today.month + months, 1);
    final weekStart = today.subtract(Duration(days: today.weekday % 7));
    return switch (rule.formula) {
      'today' => sameDay(cellDate, today),
      'yesterday' => sameDay(cellDate, today.subtract(const Duration(days: 1))),
      'tomorrow' => sameDay(cellDate, today.add(const Duration(days: 1))),
      'last7Days' =>
        !cellDate.isBefore(today.subtract(const Duration(days: 6))) &&
            !cellDate.isAfter(today),
      'thisWeek' =>
        !cellDate.isBefore(weekStart) &&
            cellDate.isBefore(weekStart.add(const Duration(days: 7))),
      'lastWeek' =>
        !cellDate.isBefore(weekStart.subtract(const Duration(days: 7))) &&
            cellDate.isBefore(weekStart),
      'nextWeek' =>
        !cellDate.isBefore(weekStart.add(const Duration(days: 7))) &&
            cellDate.isBefore(weekStart.add(const Duration(days: 14))),
      'thisMonth' =>
        cellDate.year == today.year && cellDate.month == today.month,
      'lastMonth' =>
        cellDate.year == monthOffset(-1).year &&
            cellDate.month == monthOffset(-1).month,
      'nextMonth' =>
        cellDate.year == monthOffset(1).year &&
            cellDate.month == monthOffset(1).month,
      _ => false,
    };
  }

  bool matches(SmlConditionalRule rule, SmlCell cell) {
    Object? formula(String source) => _formulas.evaluate(
      source,
      sheet,
      cell.ref,
      rows: cell.ref.row - rule.range.minRow,
      columns: cell.ref.col - rule.range.minCol,
    );
    if (rule.kind == SmlConditionalKind.expression) {
      final value = formula(rule.formula);
      return value is bool
          ? value
          : value is num && value.isFinite && value != 0;
    }
    final value = _formulas.cellValue(sheet, cell);
    if (value is FormulaErrorValue) return false;
    final text = value?.toString() ?? '';
    final number = _number(value);
    switch (rule.kind) {
      case SmlConditionalKind.expression:
      case SmlConditionalKind.colorScale:
      case SmlConditionalKind.dataBar:
      case SmlConditionalKind.iconSet:
        return false;
      case SmlConditionalKind.greaterThan:
      case SmlConditionalKind.greaterOrEqual:
      case SmlConditionalKind.lessThan:
      case SmlConditionalKind.lessOrEqual:
        final bound = _number(formula(rule.formula));
        if (number == null || bound == null) return false;
        return switch (rule.kind) {
          SmlConditionalKind.greaterThan => number > bound,
          SmlConditionalKind.greaterOrEqual => number >= bound,
          SmlConditionalKind.lessThan => number < bound,
          _ => number <= bound,
        };
      case SmlConditionalKind.equal:
      case SmlConditionalKind.notEqual:
        var bound = formula(rule.formula);
        // The compact rule API also accepts an unquoted text literal. Keep
        // that existing form when it is not an evaluable name or expression.
        if (bound is FormulaErrorValue &&
            _isUnquotedText(rule.formula) &&
            _formulas.workbook.definedName(rule.formula, onSheet: sheet) ==
                null) {
          bound = rule.formula;
        }
        if (bound is FormulaErrorValue ||
            bound is List ||
            bound is FormulaSpill) {
          return false;
        }
        final numericBound = _number(bound);
        final equal = number != null && numericBound != null
            ? number == numericBound
            : text == (bound?.toString() ?? '');
        return rule.kind == SmlConditionalKind.equal ? equal : !equal;
      case SmlConditionalKind.between:
      case SmlConditionalKind.notBetween:
        final lower = _number(formula(rule.formula));
        final upper = _number(formula(rule.formula2));
        if (number == null || lower == null || upper == null) return false;
        final between = number >= lower && number <= upper;
        return rule.kind == SmlConditionalKind.between ? between : !between;
      case SmlConditionalKind.contains:
        return text.toLowerCase().contains(rule.formula.toLowerCase());
      case SmlConditionalKind.beginsWith:
        return text.toLowerCase().startsWith(rule.formula.toLowerCase());
      case SmlConditionalKind.endsWith:
        return text.toLowerCase().endsWith(rule.formula.toLowerCase());
      case SmlConditionalKind.duplicate:
        return text.isNotEmpty && (_aggregate(rule).counts[text] ?? 0) > 1;
      case SmlConditionalKind.timePeriod:
        return number == null ? false : _matchesTimePeriod(rule, number);
      case SmlConditionalKind.top:
      case SmlConditionalKind.bottom:
      case SmlConditionalKind.topPercent:
      case SmlConditionalKind.bottomPercent:
      case SmlConditionalKind.aboveAverage:
      case SmlConditionalKind.belowAverage:
        if (number == null) return false;
        final values = _aggregate(rule).numbers;
        if (values.isEmpty) return false;
        if (rule.kind == SmlConditionalKind.aboveAverage ||
            rule.kind == SmlConditionalKind.belowAverage) {
          final mean = _aggregate(rule).mean;
          return rule.kind == SmlConditionalKind.aboveAverage
              ? number > mean
              : number < mean;
        }
        final percent =
            rule.kind == SmlConditionalKind.topPercent ||
            rule.kind == SmlConditionalKind.bottomPercent;
        final limit = percent
            ? ((values.length * rule.rank) / 100).ceil().clamp(1, values.length)
            : rule.rank.clamp(1, values.length);
        return rule.kind == SmlConditionalKind.top ||
                rule.kind == SmlConditionalKind.topPercent
            ? number >= values[values.length - limit]
            : number <= values[limit - 1];
    }
  }

  _ConditionalAggregate _aggregate(SmlConditionalRule rule) =>
      _aggregates.putIfAbsent(rule, () {
        final counts = <String, int>{};
        final numbers = <double>[];
        for (final cell in sheet.allCells) {
          if (!rule.range.containsRef(cell.ref)) continue;
          final value = _formulas.cellValue(sheet, cell);
          if (value is FormulaErrorValue) continue;
          final text = value?.toString() ?? '';
          if (text.isNotEmpty) counts[text] = (counts[text] ?? 0) + 1;
          final number = _number(value);
          if (number != null) numbers.add(number);
        }
        numbers.sort();
        return _ConditionalAggregate(counts, numbers);
      });

  static double? _number(Object? value) {
    final number = value is num
        ? value.toDouble()
        : value is bool
        ? (value ? 1.0 : 0.0)
        : value is String
        ? double.tryParse(value)
        : null;
    return number != null && number.isFinite ? number : null;
  }

  // Legacy equal/notEqual text literals are language-independent. Text that
  // contains formula syntax must be quoted; explicit references and declared
  // names retain their formula meaning, including errors/unsupported results.
  static bool _isUnquotedText(String source) =>
      source.isNotEmpty &&
      !RegExp(r'[\x00-\x1f=<>+*/^&():;,\[\]$!"-]').hasMatch(source) &&
      !RegExp(r'^[A-Za-z]{1,3}[0-9]+$').hasMatch(source.trim());
}

class _ConditionalAggregate {
  _ConditionalAggregate(this.counts, this.numbers);
  final Map<String, int> counts;
  final List<double> numbers;
  late final double mean = numbers.fold<double>(
    0,
    (sum, number) => sum + number / numbers.length,
  );
}

/// A bounded subset of the existing formula engine for painting. No dynamic
/// references, array generators, volatile functions or workbook writes.
class _ConditionalFormulas {
  _ConditionalFormulas(this.workbook);
  final SmlWorkbook workbook;
  final _values = <(SmlWorksheet, int, int), Object?>{};
  static const _unsupported = FormulaErrorValue('#VALUE!', isUnsupported: true);
  static const _functions = {
    'TRUE',
    'FALSE',
    'AND',
    'OR',
    'XOR',
    'NOT',
    'IF',
    'IFERROR',
    'IFNA',
    'ABS',
    'MOD',
    'INT',
    'ROUND',
    'ROUNDUP',
    'ROUNDDOWN',
    'SUM',
    'MIN',
    'MAX',
    'AVERAGE',
    'COUNT',
    'COUNTA',
    'COUNTBLANK',
    'ISBLANK',
    'ISNUMBER',
    'ISTEXT',
    'ISLOGICAL',
    'ISERROR',
    'ISERR',
    'ISNA',
    'LEN',
    'LOWER',
    'UPPER',
    'TRIM',
    'LEFT',
    'RIGHT',
    'MID',
    'EXACT',
    'FIND',
    'SEARCH',
    'ROW',
    'COLUMN',
    'ROWS',
    'COLUMNS',
  };

  Object? cellValue(SmlWorksheet sheet, SmlCell cell) =>
      _value(sheet, cell.ref, _ConditionalBudget(), supplied: cell);

  Object? evaluate(
    String source,
    SmlWorksheet sheet,
    SmlCellRef origin, {
    int rows = 0,
    int columns = 0,
  }) {
    if (source.length > 8192) return _unsupported;
    try {
      final shifted = FormulaRefShift.shift(
        source.trim(),
        rows: rows,
        columns: columns,
      );
      return _evaluate(shifted, sheet, origin, _ConditionalBudget());
    } on Object {
      return _unsupported;
    }
  }

  Object? _evaluate(
    String source,
    SmlWorksheet sheet,
    SmlCellRef origin,
    _ConditionalBudget budget,
  ) {
    if (source.length > 8192) return _unsupported;
    final tokens = FormulaLexer(source, strict: true).tokenize();
    if (tokens.length > 1024) return _unsupported;
    var depth = 0;
    for (final token in tokens) {
      if (token.kind == FormulaTokenKind.lparen && ++depth > 64) {
        return _unsupported;
      }
      if (token.kind == FormulaTokenKind.rparen) depth--;
    }
    final node = parseFormula(source);
    if (!_allowed(node, sheet)) return _unsupported;
    final context = FormulaContext(
      workbook: workbook,
      sheet: sheet,
      origin: origin,
      resolveCell: (target, ref) => _value(target, ref, budget),
    );
    return context.withErrorTypes(() => node.eval(context));
  }

  Object? _value(
    SmlWorksheet sheet,
    SmlCellRef ref,
    _ConditionalBudget budget, {
    SmlCell? supplied,
  }) {
    if (++budget.reads > 8192 || !_valid(ref)) return _unsupported;
    final key = (sheet, ref.col, ref.row);
    if (_values.containsKey(key)) return _values[key];
    if (budget.active.length >= 64) return _unsupported;
    if (!budget.active.add(key)) return const FormulaErrorValue('#CIRC!');
    try {
      final cell = supplied ?? sheet.cellOrNull(ref);
      Object? value = cell?.value;
      if (cell != null &&
          cell.formula?.isNotEmpty == true &&
          (value == null || value == cell.formula)) {
        value = _evaluate(cell.formula!.trim(), sheet, ref, budget);
      } else if (cell?.type == SmlCellType.error && value is String) {
        value = FormulaErrorValue(value);
      }
      _values[key] = value;
      return value;
    } on Object {
      return _unsupported;
    } finally {
      budget.active.remove(key);
    }
  }

  bool _allowed(FormulaNode node, SmlWorksheet sheet) => switch (node) {
    LiteralNode() => true,
    ExternalCellNode() => true,
    CellNode() => _valid(node.ref),
    RangeNode() => _rangeAllowed(node.range),
    WholeAxisRangeNode() => false,
    BinaryNode() => _allowed(node.left, sheet) && _allowed(node.right, sheet),
    UnaryNode() => _allowed(node.expr, sheet),
    CallNode() =>
      _functions.contains(node.name.toUpperCase()) &&
          node.args.every((arg) => _allowed(arg, sheet)),
    NamedRangeNode() => _nameAllowed(node, sheet),
  };

  bool _nameAllowed(NamedRangeNode node, SmlWorksheet sheet) {
    final table = node.sheetName == null
        ? SmlTable.resolveRef(sheet, node.name)
        : null;
    if (table != null) return _rangeAllowed(table);
    final name = node.resolve(workbook, sheet);
    return name is SmlNamedRange
        ? _rangeAllowed(name.range)
        : name is SmlFormulaName && name.formula.length <= 8192;
  }

  static bool _valid(SmlCellRef ref) =>
      ref.col >= 0 &&
      ref.row >= 0 &&
      ref.col < SmlWorksheet.excelColumnCount &&
      ref.row < SmlWorksheet.excelRowCount;
  static bool _rangeAllowed(SmlRange range) =>
      _valid(range.start) &&
      _valid(range.end) &&
      (range.maxCol - range.minCol + 1) * (range.maxRow - range.minRow + 1) <=
          4096;
}

class _ConditionalBudget {
  var reads = 0;
  final active = <(SmlWorksheet, int, int)>{};
}
