import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../model/sml_analysis.dart';
import '../model/sml_workbook.dart';
import '../styles/sml_styles.dart';
import 'formula_ast.dart';
import 'formula_date_input.dart';
import 'formula_eval.dart';

/// Broad catalog of spreadsheet functions (Excel-like names; not full Excel).
abstract final class FormulaFunctions {
  /// call API.
  static Object? call(String name, List<FormulaNode> args, FormulaContext ctx) {
    final typed = ctx.tracksErrorTypes;
    Object? evaluate() => ctx.finiteScalar(_call(name, args, ctx));
    final result = typed ? evaluate() : ctx.withErrorTypes(evaluate);
    return typed ? result : FormulaErrorValue.unwrap(result);
  }

  static Object? _call(
    String name,
    List<FormulaNode> args,
    FormulaContext ctx,
  ) {
    final String n = stripFutureFunctionPrefix(name.toUpperCase());
    if (n == 'LET') {
      return _let(args, ctx);
    }
    if (n == 'OFFSET') {
      // The first argument supplies an address, not its current value. Reading
      // it would invent dependencies (including self-cycles) outside the
      // offset's actual target range.
      final vals = <Object?>[
        null,
        for (final arg in args.skip(1)) arg.eval(ctx),
      ];
      final unsupported = FormulaErrorValue.unsupportedIn(vals);
      if (unsupported != null) return unsupported;
      final errors = flattenValues(vals).whereType<FormulaErrorValue>();
      if (errors.isNotEmpty) return errors.first;
      return _offset(ctx, args, vals);
    }
    // Branching functions consume errors intentionally and evaluate only the
    // selected expression. An unused opaque name must not block a known result.
    if (n == 'IF') {
      final condition = args.isEmpty ? null : args[0].eval(ctx);
      final unsupported = FormulaErrorValue.unsupportedIn(condition);
      if (unsupported != null) return unsupported;
      if (condition is FormulaErrorValue) return condition;
      if (condition is List || condition is FormulaSpill) {
        return ctx.error('#VALUE!');
      }
      final selected = _truth(condition) ? 1 : 2;
      return args.length > selected ? args[selected].eval(ctx) : selected == 1;
    }
    if (n == 'IFERROR' || n == 'IFNA') {
      final value = args.isEmpty ? null : args[0].eval(ctx);
      // Missing evaluator capability is not a genuine Excel error that a
      // fallback can safely replace. Preserve its provenance for cache policy.
      final unsupported = FormulaErrorValue.unsupportedIn(value);
      if (unsupported != null) return unsupported;
      final fallback =
          _isErr(value, ctx) &&
          (n == 'IFERROR' || formulaString(value) == '#N/A');
      return fallback ? (args.length > 1 ? args[1].eval(ctx) : 0) : value;
    }
    if (n == 'SUMIFS' || n == 'COUNTIFS') {
      return _conditionalAggregate(ctx, args, sum: n == 'SUMIFS');
    }
    if (n == 'SUMIF' || n == 'COUNTIF' || n == 'AVERAGEIF') {
      return _conditionalSingle(ctx, args, operation: n);
    }
    final List<Object?> vals = args
        .map((FormulaNode a) => a.eval(ctx))
        .toList();
    // Missing capability is never a native Excel error or ordinary text that
    // COUNT, ISERROR, lookups, Boolean or text functions may consume safely.
    final unsupported = FormulaErrorValue.unsupportedIn(vals);
    if (unsupported != null) return unsupported;
    // Aggregators must not ignore native errors as nonnumeric text, and text
    // functions must not turn them into ordinary strings. Error-looking text
    // remains text, including when returned by a named scalar constant.
    if (ctx.tracksErrorTypes &&
        <String>{
          'AND',
          'OR',
          'XOR',
          'NOT',
          'SUM',
          'AVERAGE',
          'MIN',
          'MAX',
          'PRODUCT',
          'SUMPRODUCT',
          'SUMSQ',
          'ABS',
          'ROUND',
          'ROUNDUP',
          'ROUNDDOWN',
          'MOD',
          'POWER',
          'POW',
          'SQRT',
          'EXP',
          'LN',
          'LOG',
          'LOG10',
          'SIGN',
          'INT',
          'TRUNC',
          'CEILING',
          'FLOOR',
          'EVEN',
          'ODD',
          'FACT',
          'GCD',
          'LCM',
          'QUOTIENT',
          'MROUND',
          'MEDIAN',
          'AVEDEV',
          'STDEV',
          'STDEVP',
          'VAR',
          'VARP',
          'RANDBETWEEN',
          'IRR',
          'TIME',
          'DAYS',
          'VALUE',
          'NUMBERVALUE',
          'CHAR',
          'CODE',
          'UNICHAR',
          'UNICODE',
          'LEN',
          'FIND',
          'SEARCH',
          'N',
          'ADDRESS',
          'FIXED',
          'DOLLAR',
          'RMB',
          'YEN',
          'BAHTTEXT',
          'DATE',
          'YEAR',
          'MONTH',
          'DAY',
          'HOUR',
          'MINUTE',
          'SECOND',
          'WEEKDAY',
          'PV',
          'FV',
          'PMT',
          'NPV',
          'SIN',
          'COS',
          'TAN',
          'EDATE',
          'EOMONTH',
          'NETWORKDAYS',
          'SEQUENCE',
          'CONCAT',
          'CONCATENATE',
          'TEXTJOIN',
          'LEFT',
          'RIGHT',
          'MID',
          'UPPER',
          'LOWER',
          'PROPER',
          'TRIM',
          'CLEAN',
          'REPLACE',
          'SUBSTITUTE',
          'REPT',
          'TEXT',
          'T',
        }.contains(n)) {
      final errors = flattenValues(vals).whereType<FormulaErrorValue>();
      if (errors.isNotEmpty) return errors.first;
    }
    switch (n) {
      case 'SUM':
        return _sum(vals);
      case 'AVERAGE':
        return _avg(vals);
      case 'MIN':
        return _minmax(vals, true);
      case 'MAX':
        return _minmax(vals, false);
      case 'ABS':
        return _n1(vals)?.abs();
      case 'ROUND':
        return _rounded(_n1(vals) ?? 0, _n(vals, 1) ?? 0, 0);
      case 'ROUNDUP':
        return _rounded(_n1(vals) ?? 0, _n(vals, 1) ?? 0, 1);
      case 'ROUNDDOWN':
        return _rounded(_n1(vals) ?? 0, _n(vals, 1) ?? 0, -1);
      case 'MOD':
        final double? a = _n(vals, 0);
        final double? b = _n(vals, 1);
        if (a == null || b == null || b == 0) {
          return const FormulaErrorValue('#DIV/0!');
        }
        if (!a.isFinite || !b.isFinite || !(a / b).isFinite) {
          return const FormulaErrorValue('#NUM!');
        }
        return a - b * (a / b).floor();
      case 'PRODUCT':
        return flattenNumbers(
          vals,
        ).fold<double>(1, (double p, double x) => p * x);
      case 'POWER':
      case 'POW':
        return _powNum(_n(vals, 0) ?? 0, _n(vals, 1) ?? 0);
      case 'SQRT':
        final double? x = _n1(vals);
        return x == null || x < 0 ? const FormulaErrorValue('#NUM!') : _sqrt(x);
      case 'PI':
        return 3.141592653589793;
      case 'EXP':
        return _exp(_n1(vals) ?? 0);
      case 'LN':
        return _ln(_n1(vals) ?? 0);
      case 'LOG':
        return _ln(_n1(vals) ?? 0) / _ln(_n(vals, 1) ?? 10);
      case 'LOG10':
        return _ln(_n1(vals) ?? 0) / _ln(10);
      case 'SIGN':
        final double? s = _n1(vals);
        return s == null ? 0 : (s > 0 ? 1 : (s < 0 ? -1 : 0));
      case 'INT':
        return _n1(vals)?.floorToDouble();
      case 'TRUNC':
        return _n1(vals)?.truncateToDouble();
      case 'CEILING':
        return _n1(vals)?.ceilToDouble();
      case 'FLOOR':
        return _n1(vals)?.floorToDouble();
      case 'EVEN':
        return _evenOdd(_n1(vals) ?? 0, true);
      case 'ODD':
        return _evenOdd(_n1(vals) ?? 0, false);
      case 'FACT':
        return _fact(_n1(vals)?.toInt() ?? 0);
      case 'GCD':
        return _gcd(flattenNumbers(vals).map((double e) => e.toInt()).toList());
      case 'LCM':
        return _lcm(flattenNumbers(vals).map((double e) => e.toInt()).toList());
      case 'QUOTIENT':
        final double? qa = _n(vals, 0);
        final double? qb = _n(vals, 1);
        return (qa == null || qb == null || qb == 0)
            ? const FormulaErrorValue('#DIV/0!')
            : (qa / qb).truncate();
      case 'MROUND':
        final double? m = _n(vals, 1);
        if (m == null || m == 0) return 0;
        return ((_n1(vals) ?? 0) / m).round() * m;
      case 'SUMPRODUCT':
        return _sumproduct(vals);
      case 'SUMSQ':
        return flattenNumbers(
          vals,
        ).fold<double>(0, (double s, double x) => s + x * x);
      case 'MEDIAN':
        return _median(flattenNumbers(vals));
      case 'AVEDEV':
        return _avedev(flattenNumbers(vals));
      case 'STDEV':
      case 'STDEVP':
        return _stdev(flattenNumbers(vals), n == 'STDEVP');
      case 'VAR':
      case 'VARP':
        return _variance(flattenNumbers(vals), n == 'VARP');
      case 'RAND':
        return math.Random().nextDouble();
      case 'RANDBETWEEN':
        final int lo = _n(vals, 0)?.toInt() ?? 0;
        final int hi = _n(vals, 1)?.toInt() ?? lo;
        if (hi <= lo) {
          return lo.toDouble();
        }
        return (lo + math.Random().nextInt(hi - lo + 1)).toDouble();
      case 'FORMULATEXT':
        return _formulatext(args, ctx);
      case 'TRANSPOSE':
        return _transpose(args, ctx);
      case 'IRR':
        return _irr(vals);
      case 'TIME':
        return _time(vals);
      case 'DAYS':
        return _days(vals, ctx.workbook.uses1904Dates);
      case 'SHEET':
        if (args.firstOrNull is ExternalCellNode) {
          throw UnsupportedError('SHEET metadata for external references');
        }
        return (ctx.workbook.sheets.indexOf(ctx.sheet) + 1).toDouble();
      case 'SHEETS':
        if (args.firstOrNull is ExternalCellNode) {
          throw UnsupportedError('SHEETS metadata for external references');
        }
        return ctx.workbook.sheets.length.toDouble();
      case 'AND':
      case 'OR':
      case 'XOR':
        final logical = <bool>[];
        for (var i = 0; i < vals.length; i++) {
          final value = vals[i];
          final reference =
              args[i] is CellNode ||
              args[i] is ExternalCellNode ||
              args[i] is RangeNode ||
              args[i] is NamedRangeNode;
          for (final item in flattenValues(value)) {
            // Logical aggregators ignore empty/text cells in references.
            if ((value is List || reference) &&
                (item == null || item is String)) {
              continue;
            }
            final boolean = _logicalScalar(item);
            if (boolean == null) return ctx.error('#VALUE!');
            logical.add(boolean);
          }
        }
        if (logical.isEmpty) return ctx.error('#VALUE!');
        return n == 'AND'
            ? logical.every((value) => value)
            : n == 'OR'
            ? logical.any((value) => value)
            : logical.where((value) => value).length.isOdd;
      case 'NOT':
        if (vals.length != 1 || vals[0] is List || vals[0] is FormulaSpill) {
          return ctx.error('#VALUE!');
        }
        final boolean = _logicalScalar(vals[0]);
        return boolean == null ? ctx.error('#VALUE!') : !boolean;
      case 'TRUE':
        return true;
      case 'FALSE':
        return false;
      case 'IFS':
        for (int i = 0; i + 1 < vals.length; i += 2) {
          if (_truth(vals[i])) return vals[i + 1];
        }
        return const FormulaErrorValue('#N/A');
      case 'SWITCH':
        final Object? expr = vals.isEmpty ? null : vals[0];
        for (int i = 1; i + 1 < vals.length; i += 2) {
          if (formulaString(expr) == formulaString(vals[i])) return vals[i + 1];
        }
        return vals.length.isEven ? vals.last : const FormulaErrorValue('#N/A');
      case 'COUNT':
        return flattenNumbers(vals).length.toDouble();
      case 'COUNTA':
        return flattenValues(
          vals,
        ).where((Object? v) => v != null && v != '').length.toDouble();
      case 'COUNTBLANK':
        return flattenValues(
          vals,
        ).where((Object? v) => v == null || v == '').length.toDouble();
      case 'CONCATENATE':
      case 'CONCAT':
        return vals.map(formulaString).join();
      case 'LEFT':
        return formulaString(vals[0]).substring(
          0,
          _clamp(_n(vals, 1)?.toInt() ?? 1, formulaString(vals[0]).length),
        );
      case 'RIGHT':
        final String s = formulaString(vals[0]);
        final int k = _clamp(_n(vals, 1)?.toInt() ?? 1, s.length);
        return s.substring(s.length - k);
      case 'MID':
        final String m = formulaString(vals[0]);
        final int start = ((_n(vals, 1)?.toInt() ?? 1) - 1).clamp(0, m.length);
        final int len = _n(vals, 2)?.toInt() ?? 0;
        return m.substring(start, (start + len).clamp(0, m.length));
      case 'LEN':
        return formulaString(vals[0]).length.toDouble();
      case 'TRIM':
        return formulaString(vals[0]).trim().replaceAll(RegExp(r'\s+'), ' ');
      case 'UPPER':
        return formulaString(vals[0]).toUpperCase();
      case 'LOWER':
        return formulaString(vals[0]).toLowerCase();
      case 'PROPER':
        return formulaString(vals[0]).split(' ').map(_cap).join(' ');
      case 'EXACT':
        return formulaString(vals[0]) ==
            formulaString(vals.length > 1 ? vals[1] : '');
      case 'FIND':
      case 'SEARCH':
        return _findText(vals, wildcard: n == 'SEARCH');
      case 'REPLACE':
        final String base = formulaString(vals[0]);
        final int rs = ((_n(vals, 1)?.toInt() ?? 1) - 1).clamp(0, base.length);
        final int rl = _n(vals, 2)?.toInt() ?? 0;
        return base.replaceRange(
          rs,
          (rs + rl).clamp(0, base.length),
          formulaString(vals.length > 3 ? vals[3] : ''),
        );
      case 'SUBSTITUTE':
        return _substitute(vals);
      case 'REPT':
        return List<String>.filled(
          _n(vals, 1)?.toInt() ?? 0,
          formulaString(vals[0]),
        ).join();
      case 'VALUE':
        return asFormulaNumber(vals[0]) ?? const FormulaErrorValue('#VALUE!');
      case 'NUMBERVALUE':
        return _numberValue(
          vals,
          ctx.workbook.uses1904Dates,
          ctx.workbook.formulaLocale ?? Intl.getCurrentLocale(),
        );
      case 'CHAR':
        return String.fromCharCode(_n1(vals)?.toInt() ?? 0);
      case 'CODE':
        return formulaString(vals[0]).isEmpty
            ? 0.0
            : formulaString(vals[0]).codeUnitAt(0).toDouble();
      case 'UNICHAR':
        return String.fromCharCode(_n1(vals)?.toInt() ?? 0);
      case 'UNICODE':
        return formulaString(vals[0]).isEmpty
            ? 0.0
            : formulaString(vals[0]).runes.first.toDouble();
      case 'CLEAN':
        return formulaString(vals[0]).replaceAll(RegExp(r'[\x00-\x1F]'), '');
      case 'T':
        return vals[0] is String ? vals[0] : '';
      case 'HYPERLINK':
        // Display text is the friendly name when provided; else the link.
        if (vals.length > 1 && vals[1] != null && '${vals[1]}'.isNotEmpty) {
          return formulaString(vals[1]);
        }
        return formulaString(vals.isEmpty ? null : vals[0]);
      case 'ADDRESS':
        {
          final int row = (_n(vals, 0) ?? 1).toInt();
          final int col = (_n(vals, 1) ?? 1).toInt();
          if (row < 1 || col < 1) {
            return const FormulaErrorValue('#VALUE!');
          }
          final int abs = (_n(vals, 2) ?? 1).toInt().clamp(1, 4);
          final bool a1 = vals.length < 4 || _truth(vals[3]);
          if (!a1) {
            return 'R${row}C$col';
          }
          final String letters = SmlCellRef(
            col - 1,
            row - 1,
          ).a1.replaceAll(RegExp(r'\d+'), '');
          final bool absRow = abs == 1 || abs == 2;
          final bool absCol = abs == 1 || abs == 3;
          final String sheet = vals.length > 4
              ? formulaString(vals[4]).trim()
              : '';
          final String cell =
              '${absCol ? '\$' : ''}$letters${absRow ? '\$' : ''}$row';
          if (sheet.isEmpty) {
            return cell;
          }
          final String quoted = sheet.contains(' ') || sheet.contains("'")
              ? "'${sheet.replaceAll("'", "''")}'"
              : sheet;
          return '$quoted!$cell';
        }
      case 'CELL':
        {
          final String info = formulaString(
            vals.isEmpty ? null : vals[0],
          ).toLowerCase();
          SmlCellRef ref = ctx.origin;
          if (args.length > 1 && args[1] is ExternalCellNode) {
            throw UnsupportedError('CELL metadata for external references');
          }
          if (args.length > 1 && args[1] is CellNode) {
            ref = (args[1] as CellNode).ref;
          } else if (args.length > 1 && args[1] is RangeNode) {
            ref = (args[1] as RangeNode).range.start;
          }
          return switch (info) {
            'address' => ref.a1,
            'col' || 'column' => (ref.col + 1).toDouble(),
            'row' => (ref.row + 1).toDouble(),
            'contents' => args.length > 1 ? vals[1] : ctx.sheet.cell(ref).value,
            // The engine consumes workbook bytes without a file location.
            // Preserve any imported path result when recalculating.
            'filename' || 'dateiname' => const FormulaErrorValue(
              '#VALUE!',
              isUnsupported: true,
            ),
            'type' => () {
              final Object? v = args.length > 1
                  ? vals[1]
                  : ctx.sheet.cell(ref).value;
              if (v == null || v == '') {
                return 'b';
              }
              if (v is String) {
                return 'l';
              }
              return 'v';
            }(),
            _ => const FormulaErrorValue('#N/A'),
          };
        }
      case 'INFO':
        {
          final String type = formulaString(
            vals.isEmpty ? null : vals[0],
          ).toLowerCase();
          return switch (type) {
            'directory' => '',
            'numfile' => 1.0,
            'origin' => r'$A:$A$1',
            'osversion' => 'Quds',
            'recalc' => 'Automatic',
            'release' => 'QudsOffice',
            'system' => 'pcdos',
            'memavail' || 'memused' || 'totmem' => 0.0,
            _ => const FormulaErrorValue('#N/A'),
          };
        }
      case 'FIXED':
        {
          final double n = _n(vals, 0) ?? 0;
          final int decimals = (_n(vals, 1) ?? 2).toInt().clamp(0, 15);
          final bool noCommas = vals.length > 2 && _truth(vals[2]);
          var text = n.toStringAsFixed(decimals);
          if (!noCommas) {
            text = _withThousands(text);
          }
          return text;
        }
      case 'DOLLAR':
      case 'RMB':
      case 'YEN':
        {
          final double n = _n(vals, 0) ?? 0;
          final int decimals = (_n(vals, 1) ?? 2).toInt().clamp(0, 15);
          final String upper = name.toUpperCase();
          final String symbol = (upper == 'YEN' || upper == 'RMB') ? '¥' : r'$';
          final String body = _withThousands(n.abs().toStringAsFixed(decimals));
          return n < 0 ? '-$symbol$body' : '$symbol$body';
        }
      case 'ASC':
      case 'PHONETIC':
        return formulaString(vals.isEmpty ? null : vals[0]);
      case 'BAHTTEXT':
        // Limited stub: numeric Thai baht wording is out of scope.
        final double n = _n(vals, 0) ?? 0;
        return n.toStringAsFixed(2);
      case 'N':
        return asFormulaNumber(vals[0]) ?? 0;
      case 'TEXTJOIN':
        final String delim = formulaString(vals[0]);
        final bool skip = _truth(vals.length > 1 ? vals[1] : true);
        final Iterable<Object?> rest = flattenValues(vals.skip(2).toList());
        return rest
            .where((Object? v) => !skip || (v != null && v != ''))
            .map(formulaString)
            .join(delim);
      case 'VLOOKUP':
        return _vlookup(ctx, args, false);
      case 'HLOOKUP':
        return _vlookup(ctx, args, true);
      case 'INDEX':
        return _index(vals);
      case 'MATCH':
        return _match(vals);
      case 'XLOOKUP':
        return _xlookup(vals);
      case 'FILTER':
        return _filter(vals);
      case 'UNIQUE':
        return _unique(vals);
      case 'SORT':
        return _sortFn(vals);
      case 'CHOOSE':
        final int i = _n1(vals)?.toInt() ?? 1;
        return (i >= 1 && i < vals.length)
            ? vals[i]
            : const FormulaErrorValue('#VALUE!');
      case 'LOOKUP':
        return _lookup(vals);
      case 'ROW':
        if (args.firstOrNull case ExternalCellNode(:final ref)) {
          return ref.row + 1;
        }
        return (vals.isEmpty
                ? ctx.origin.row
                : (args[0] is CellNode
                      ? (args[0] as CellNode).ref.row
                      : ctx.origin.row)) +
            1;
      case 'COLUMN':
        if (args.firstOrNull case ExternalCellNode(:final ref)) {
          return ref.col + 1;
        }
        return (vals.isEmpty
                ? ctx.origin.col
                : (args[0] is CellNode
                      ? (args[0] as CellNode).ref.col
                      : ctx.origin.col)) +
            1;
      case 'ROWS':
        return args.isNotEmpty && args[0] is RangeNode
            ? ((args[0] as RangeNode).range.end.row -
                          (args[0] as RangeNode).range.start.row)
                      .abs() +
                  1
            : 1;
      case 'COLUMNS':
        return args.isNotEmpty && args[0] is RangeNode
            ? ((args[0] as RangeNode).range.end.col -
                          (args[0] as RangeNode).range.start.col)
                      .abs() +
                  1
            : 1;
      case 'ISBLANK':
        return vals[0] == null || vals[0] == '';
      case 'ISERROR':
      case 'ISERR':
        return _isErr(vals[0], ctx);
      case 'ISNA':
        return (_isErr(vals[0], ctx) && formulaString(vals[0]) == '#N/A');
      case 'ISTEXT':
        return vals[0] is String;
      case 'ISNUMBER':
        return vals[0] is num;
      case 'ISLOGICAL':
        return vals[0] is bool;
      case 'ISNONTEXT':
        return vals[0] is! String;
      case 'NA':
        return const FormulaErrorValue('#N/A');
      case 'TYPE':
        final Object? t = vals[0];
        if (t is num) return 1;
        if (t is String) return 2;
        if (t is bool) return 4;
        if (_isErr(t, ctx)) return 16;
        return 64;
      case 'DATE':
        final year = _n(vals, 0)?.toInt();
        final month = _n(vals, 1)?.toInt();
        final day = _n(vals, 2)?.toInt();
        if (year == null || month == null || day == null || year < 0) {
          return const FormulaErrorValue('#NUM!');
        }
        final adjustedYear = year < 1900 ? year + 1900 : year;
        final use1904 = ctx.workbook.uses1904Dates;
        if (!use1904 && adjustedYear == 1900 && month == 2 && day == 29) {
          return 60.0;
        }
        return _dateSerial(DateTime.utc(adjustedYear, month, day), use1904);
      case 'TODAY':
      case 'NOW':
        final now = DateTime.now();
        final localClock = DateTime.utc(
          now.year,
          now.month,
          now.day,
          now.hour,
          now.minute,
          now.second,
          now.millisecond,
        );
        final serial = _dateSerial(localClock, ctx.workbook.uses1904Dates);
        return n == 'TODAY' ? serial.floorToDouble() : serial;
      case 'YEAR':
      case 'MONTH':
      case 'DAY':
      case 'HOUR':
      case 'MINUTE':
      case 'SECOND':
      case 'WEEKDAY':
        return _datePart(n, vals.firstOrNull, ctx.workbook.uses1904Dates);
      case 'PV':
      case 'FV':
      case 'PMT':
        return _fin(n, vals);
      case 'NPV':
        return _npv(vals);
      case 'SIN':
        return math.sin(_n1(vals) ?? 0);
      case 'COS':
        return math.cos(_n1(vals) ?? 0);
      case 'TAN':
        return math.tan(_n1(vals) ?? 0);
      case 'TEXT':
        return _textFmt(
          vals,
          ctx.workbook.uses1904Dates,
          ctx.workbook.formulaLocale ?? Intl.getCurrentLocale(),
        );
      case 'INDIRECT':
        return _indirect(ctx, vals);
      case 'EDATE':
        return _edate(vals, ctx.workbook.uses1904Dates);
      case 'EOMONTH':
        return _eomonth(vals, ctx.workbook.uses1904Dates);
      case 'NETWORKDAYS':
        return _networkdays(vals, ctx.workbook.uses1904Dates);
      case 'SEQUENCE':
        return _sequence(vals);
      default:
        // Aliases that share an implementation.
        if (_aliases.containsKey(n)) {
          return call(_aliases[n]!, args, ctx);
        }
        return const FormulaErrorValue('#NAME?', isUnsupported: true);
    }
  }

  /// Drops the `_xlfn.` / `_xlws.` prefixes Excel stores on functions added
  /// after Excel 2007 (`_xlfn.CONCAT`, `_xlfn._xlws.FILTER`). The formula text
  /// keeps them, so files round-trip unchanged.
  static String stripFutureFunctionPrefix(String name) {
    var n = name;
    for (final String prefix in const <String>['_XLFN.', '_XLWS.']) {
      if (n.toUpperCase().startsWith(prefix)) {
        n = n.substring(prefix.length);
      }
    }
    return n;
  }

  static const Map<String, String> _aliases = <String, String>{
    'SUMX2MY2': 'SUMSQ',
    'SUMX2PY2': 'SUMSQ',
    'AVERAGEA': 'AVERAGE',
    'MAXA': 'MAX',
    'MINA': 'MIN',
    'COUNTA': 'COUNTA',
    'COUNTBLANK': 'COUNTBLANK',
    'STDEV.S': 'STDEV',
    'STDEV.P': 'STDEVP',
    'VAR.S': 'VAR',
    'VAR.P': 'VARP',
    'CEILING.MATH': 'CEILING',
    'FLOOR.MATH': 'FLOOR',
    'ISO.CEILING': 'CEILING',
    'ROUNDUP': 'ROUNDUP',
    'ROUNDDOWN': 'ROUNDDOWN',
    'CONCAT': 'CONCATENATE',
    'UNICHAR': 'UNICHAR',
    'UNICODE': 'UNICODE',
    'ERROR.TYPE': 'TYPE',
    'ISERR': 'ISERROR',
    'AREAS': 'ROWS',
    'DBCS': 'UPPER',
    'FINDB': 'FIND',
    'LEFTB': 'LEFT',
    'RIGHTB': 'RIGHT',
    'MIDB': 'MID',
    'LENB': 'LEN',
    'REPLACEB': 'REPLACE',
    'SEARCHB': 'SEARCH',
    'DATEVALUE': 'DATE',
    'TIMEVALUE': 'NOW',
    'WORKDAY': 'DATE',
    'DATEDIF': 'DAY',
    'YEARFRAC': 'YEAR',
    'DAYS360': 'DAY',
    'ISOWEEKNUM': 'WEEKDAY',
    'WEEKNUM': 'WEEKDAY',
    'NPER': 'PMT',
    'RATE': 'PMT',
    'MIRR': 'NPV',
    'CUMIPMT': 'PMT',
    'CUMPRINC': 'PMT',
    'IPMT': 'PMT',
    'PPMT': 'PMT',
    'EFFECT': 'POWER',
    'NOMINAL': 'POWER',
    'ACCRINT': 'SUM',
    'COMBIN': 'FACT',
    'PERMUT': 'FACT',
    'COMBINA': 'FACT',
    'PERMUTATIONA': 'FACT',
    'SERIESSUM': 'SUM',
    'SUBTOTAL': 'SUM',
    'AGGREGATE': 'SUM',
    'MAXIFS': 'MAX',
    'MINIFS': 'MIN',
    'AVERAGEIFS': 'AVERAGEIF',
    'XMATCH': 'MATCH',
    'FILTER': 'FILTER',
    'SORT': 'SORT',
    'UNIQUE': 'UNIQUE',
    'RANDARRAY': 'RAND',
  };

  static double _sum(List<Object?> vals) =>
      flattenNumbers(vals).fold(0, (double s, double x) => s + x);

  static Object? _avg(List<Object?> vals) {
    final List<double> n = flattenNumbers(vals);
    return n.isEmpty
        ? const FormulaErrorValue('#DIV/0!')
        : n.fold(0.0, (double s, double x) => s + x) / n.length;
  }

  static Object? _minmax(List<Object?> vals, bool min) {
    final List<double> n = flattenNumbers(vals);
    if (n.isEmpty) return 0;
    var m = n.first;
    for (final double x in n) {
      if (min ? x < m : x > m) m = x;
    }
    return m;
  }

  static double? _n1(List<Object?> vals) =>
      vals.isEmpty ? null : asFormulaNumber(vals[0]);

  static double? _n(List<Object?> vals, int i) =>
      i < vals.length ? asFormulaNumber(vals[i]) : null;

  static bool? _logicalScalar(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value.isFinite ? value != 0 : null;
    if (value is String) {
      if (value.toUpperCase() == 'TRUE') return true;
      if (value.toUpperCase() == 'FALSE') return false;
    }
    return null;
  }

  static bool _truth(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.isNotEmpty && v != 'FALSE';
    return v != null;
  }

  static String _withThousands(String fixed) {
    final bool neg = fixed.startsWith('-');
    final String raw = neg ? fixed.substring(1) : fixed;
    final List<String> parts = raw.split('.');
    final String intPart = parts[0];
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) {
        out.write(',');
      }
      out.write(intPart[i]);
    }
    final String body = parts.length > 1 ? '$out.${parts[1]}' : '$out';
    return neg ? '-$body' : body;
  }

  /// startsWith API.
  static bool _isErr(Object? v, FormulaContext ctx) =>
      v is FormulaErrorValue ||
      (!ctx.tracksErrorTypes && v is String && v.startsWith('#'));

  static final _numberWhitespace = RegExp(r'\s');
  static final _numberText = RegExp(
    r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$',
  );

  static Object _numberValue(
    List<Object?> args,
    bool use1904,
    String localeName,
  ) {
    const invalid = FormulaErrorValue('#VALUE!');
    if (args.isEmpty || args.length > 3) return invalid;
    if (args.any((arg) => arg is List || arg is FormulaSpill)) {
      return const FormulaErrorValue('#VALUE!', isUnsupported: true);
    }
    final locale =
        Intl.verifiedLocale(
          localeName,
          NumberFormat.localeExists,
          onFailure: (_) => 'en_US',
        ) ??
        'en_US';
    final separators = NumberFormat.decimalPattern(locale).symbols;
    String firstCharacter(int index, String fallback) {
      final value = index < args.length ? args[index] : null;
      if (value == null) return fallback;
      final text = formulaString(value);
      return text.isEmpty ? '' : String.fromCharCode(text.runes.first);
    }

    final decimal = firstCharacter(1, separators.DECIMAL_SEP);
    final group = firstCharacter(2, separators.GROUP_SEP);
    if (decimal.isEmpty || group.isEmpty || decimal == group) return invalid;
    final value = args.first;
    if (value is num) return value;

    final raw = formulaString(value);
    var text = raw.replaceAll(_numberWhitespace, '');
    var percentEnd = text.length;
    while (percentEnd > 0 && text.codeUnitAt(percentEnd - 1) == 0x25) {
      percentEnd--;
    }
    final percentCount = text.length - percentEnd;
    text = text.substring(0, percentEnd);
    if (text.isEmpty) return 0.0;

    final result =
        _parseExplicitNumber(text, decimal, group) ??
        _parseRegionalNumber(
          text,
          separators.DECIMAL_SEP,
          separators.GROUP_SEP,
        ) ??
        _numberValueDate(raw, percentCount, locale, group, use1904);
    if (result == null || !result.isFinite) return invalid;
    // Scale in chunks so a long percent suffix cannot overflow its divisor.
    var scaled = result;
    var remaining = percentCount;
    while (remaining > 0 && scaled != 0) {
      final count = math.min(remaining, 100);
      scaled /= math.pow(100, count);
      remaining -= count;
    }
    return scaled;
  }

  static double? _parseExplicitNumber(
    String text,
    String decimal,
    String group,
  ) {
    final parts = text.split(decimal);
    if (parts.length > 2 || (parts.length == 2 && parts.last.contains(group))) {
      return null;
    }
    final whole = parts.first.replaceAll(group, '');
    if (decimal != '.' &&
        (whole.contains('.') ||
            (parts.length == 2 && parts.last.contains('.')))) {
      return null;
    }
    final number = parts.length == 1 ? whole : '$whole.${parts.last}';
    return _numberText.hasMatch(number) ? double.tryParse(number) : null;
  }

  static double? _parseRegionalNumber(
    String text,
    String decimal,
    String group,
  ) {
    // Apply the ordinary regional grouping only to explicitly grouped numbers.
    // In particular, a short German 1.2 may be a calendar date instead.
    final d = RegExp.escape(decimal);
    final g = RegExp.escape(group);
    if (!RegExp(
      '^[+-]?[0-9]{1,3}(?:(?:$g[0-9]{3})+|$g[0-9]{4})(?:$d[0-9]+)?(?:[eE][+-]?[0-9]+)?\$',
    ).hasMatch(text)) {
      return null;
    }
    return _parseExplicitNumber(text, decimal, group);
  }

  static double? _numberValueDate(
    String raw,
    int percentCount,
    String locale,
    String group,
    bool use1904,
  ) {
    final dateText = percentCount == 0
        ? raw
        : raw.replaceFirst(RegExp(r'(?:%\s*)+$'), '');
    final parsed = parseFormulaDateInput(
      dateText.replaceAll(group, ''),
      locale,
    );
    if (parsed == null) return null;
    if (parsed.time != null) return parsed.time;
    final date = parsed.date!;
    if (parsed.fictitiousLeapDay) return use1904 ? null : 60;
    final serial = _dateSerial(date, use1904);
    return serial < 0 ? null : serial;
  }

  static Object _findText(List<Object?> args, {required bool wildcard}) {
    const invalid = FormulaErrorValue('#VALUE!');
    if (args.length < 2 || args.length > 3) return invalid;
    final needle = formulaString(args[0]);
    final text = formulaString(args[1]);
    final position = args.length == 3 ? _n(args, 2)?.toInt() : 1;
    // FIND can match the empty string just beyond the final character.
    final maxPosition = text.length + (wildcard ? 0 : 1);
    if (position == null || position <= 0 || position > maxPosition) {
      return invalid;
    }
    final start = position - 1;
    final at = wildcard
        ? _searchWildcard(needle, text, start)
        : text.indexOf(needle, start);
    return at < 0 ? invalid : (at + 1).toDouble();
  }

  static int _searchWildcard(String pattern, String text, int start) {
    // Split on unescaped stars. Each remaining segment has a fixed length,
    // so choosing its earliest match avoids backtracking across stars.
    final segments = <String>[];
    final segment = StringBuffer();
    final chars = pattern.runes.toList();
    for (var i = 0; i < chars.length; i++) {
      final char = chars[i];
      if (char == 0x2a) {
        segments.add(segment.toString());
        segment.clear();
      } else if (char == 0x3f) {
        segment.write('.');
      } else if (char == 0x7e) {
        if (i + 1 < chars.length) {
          segment.write(RegExp.escape(String.fromCharCode(chars[++i])));
        }
      } else {
        segment.write(RegExp.escape(String.fromCharCode(char)));
      }
    }
    segments.add(segment.toString());

    var offset = start;
    var first = start;
    for (var i = 0; i < segments.length; i++) {
      if (segments[i].isEmpty) continue;
      final regexp = RegExp(segments[i], caseSensitive: false, dotAll: true);
      final match = regexp.allMatches(text, offset).firstOrNull;
      if (match == null) return -1;
      if (i == 0) first = match.start;
      offset = match.end;
    }
    return first;
  }

  static Object _substitute(List<Object?> args) {
    const invalid = FormulaErrorValue('#VALUE!');
    if (args.length < 3 || args.length > 4) return invalid;
    final text = formulaString(args[0]);
    final previous = formulaString(args[1]);
    final replacement = formulaString(args[2]);
    if (args.length == 3) {
      return previous.isEmpty ? text : text.replaceAll(previous, replacement);
    }
    final instance = args[3] is bool ? null : _n(args, 3)?.toInt();
    if (instance == null || instance < 1) return invalid;
    if (previous.isEmpty) return text;

    var count = 0;
    for (final match in previous.allMatches(text)) {
      if (++count == instance) {
        return text.replaceRange(match.start, match.end, replacement);
      }
    }
    return text;
  }

  static int _clamp(int v, int max) => v < 0 ? 0 : (v > max ? max : v);

  static String _cap(String w) =>
      w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';

  // Decimal precision is deliberately bounded to the finite double scale.
  // Validate before integer conversion or scaling; a formula may supply the
  // digit count through a referenced cell, not just a literal argument.
  static Object _rounded(double x, double requestedDigits, int direction) {
    if (!x.isFinite ||
        !requestedDigits.isFinite ||
        requestedDigits.abs() >= 309) {
      return const FormulaErrorValue('#NUM!');
    }
    final digits = requestedDigits.truncate();
    final factor = math.pow(10.0, digits).toDouble();
    final scaled = x * factor;
    if (!scaled.isFinite) {
      // At this magnitude, finer decimal rounding cannot change the double.
      return x;
    }
    final double rounded;
    if (direction > 0) {
      rounded = scaled == 0 && x != 0
          ? (x > 0 ? 1.0 : -1.0)
          : scaled >= 0
          ? scaled.ceilToDouble()
          : scaled.floorToDouble();
    } else if (direction < 0) {
      rounded = scaled.truncateToDouble();
    } else {
      rounded = scaled.roundToDouble();
    }
    final result = rounded / factor;
    return result.isFinite ? result : const FormulaErrorValue('#NUM!');
  }

  static double _evenOdd(double x, bool even) {
    var n = x.ceil();
    if (even && n.isOdd) n++;
    if (!even && n.isEven) n++;
    return n.toDouble();
  }

  static double _fact(int n) {
    if (n < 0) return double.nan;
    var r = 1.0;
    for (int i = 2; i <= n && i <= 170; i++) {
      r *= i;
    }
    return r;
  }

  static int _gcd(List<int> xs) {
    var g = xs.isEmpty ? 0 : xs.first.abs();
    for (final int x in xs) {
      var a = g;
      var b = x.abs();
      while (b != 0) {
        final int t = a % b;
        a = b;
        b = t;
      }
      g = a;
    }
    return g;
  }

  static int _lcm(List<int> xs) {
    var l = 1;
    for (final int x in xs) {
      if (x == 0) return 0;
      l = (l ~/ _gcd(<int>[l, x.abs()])) * x.abs();
    }
    return l;
  }

  static double _sumproduct(List<Object?> vals) {
    final List<List<double>> arrays = vals
        .map((Object? v) => flattenNumbers(<Object?>[v]))
        .toList();
    if (arrays.isEmpty) return 0;
    final int n = arrays
        .map((List<double> a) => a.length)
        .reduce((int a, int b) => a < b ? a : b);
    var s = 0.0;
    for (int i = 0; i < n; i++) {
      var p = 1.0;
      for (final List<double> a in arrays) {
        p *= a[i];
      }
      s += p;
    }
    return s;
  }

  static Object? _median(List<double> n) {
    if (n.isEmpty) return 0;
    n.sort();
    final int m = n.length ~/ 2;
    return n.length.isOdd ? n[m] : (n[m - 1] + n[m]) / 2;
  }

  static Object? _avedev(List<double> n) {
    if (n.isEmpty) return 0;
    final double avg = n.fold(0.0, (double s, double x) => s + x) / n.length;
    return n.fold(0.0, (double s, double x) => s + (x - avg).abs()) / n.length;
  }

  static Object? _stdev(List<double> n, bool pop) {
    final Object? v = _variance(n, pop);
    return v is num ? _sqrt(v.toDouble()) : v;
  }

  static Object? _variance(List<double> n, bool pop) {
    if (n.length < 2 && !pop) return const FormulaErrorValue('#DIV/0!');
    if (n.isEmpty) return 0;
    final double avg = n.fold(0.0, (double s, double x) => s + x) / n.length;
    final double ss = n.fold(
      0.0,
      (double s, double x) => s + (x - avg) * (x - avg),
    );
    return ss / (pop ? n.length : n.length - 1);
  }

  static Object? _conditionalSingle(
    FormulaContext ctx,
    List<FormulaNode> args, {
    required String operation,
  }) {
    const invalid = FormulaErrorValue('#VALUE!');
    final countOnly = operation == 'COUNTIF';
    if (args.length < 2 || args.length > (countOnly ? 2 : 3)) {
      return invalid;
    }
    final keys = _conditionalRange(ctx, args[0]);
    if (keys is FormulaErrorValue) return keys;
    if (keys is! ({SmlRange range, SmlWorksheet sheet})) return invalid;
    final criterion = args[1].eval(ctx);
    if (criterion is FormulaErrorValue) return criterion;
    if (criterion is List || criterion is FormulaSpill) {
      return const FormulaErrorValue('#VALUE!', isUnsupported: true);
    }
    final matches = _compileCriterion(criterion ?? 0);
    final nums = args.length == 3 ? _conditionalRange(ctx, args[2]) : keys;
    if (nums is FormulaErrorValue) return nums;
    if (nums is! ({SmlRange range, SmlWorksheet sheet})) return invalid;

    var count = 0;
    var total = 0.0;
    for (final key in keys.range.cells) {
      final value = ctx.valueOf(key, onSheet: keys.sheet);
      if (value is FormulaErrorValue && value.isUnsupported) return value;
      if (!matches(value)) continue;
      if (countOnly) {
        count++;
        continue;
      }
      // Excel aligns the numeric range's upper-left cell and uses the
      // criteria range's shape, even when a different size was supplied.
      final target = SmlCellRef(
        nums.range.minCol + key.col - keys.range.minCol,
        nums.range.minRow + key.row - keys.range.minRow,
      );
      if (!_validCell(target)) return const FormulaErrorValue('#REF!');
      final operand = ctx.valueOf(target, onSheet: nums.sheet);
      if (operand is FormulaErrorValue) return operand;
      if (operand is num) {
        total += operand;
        count++;
      }
    }
    return switch (operation) {
      'COUNTIF' => count.toDouble(),
      'AVERAGEIF' =>
        count == 0 ? const FormulaErrorValue('#DIV/0!') : total / count,
      _ => total,
    };
  }

  static Object? _conditionalAggregate(
    FormulaContext ctx,
    List<FormulaNode> args, {
    required bool sum,
  }) {
    const invalid = FormulaErrorValue('#VALUE!');
    final first = sum ? 1 : 0;
    final criteriaArgs = args.length - first;
    if (criteriaArgs < 2 || criteriaArgs > 254 || criteriaArgs.isOdd) {
      return invalid;
    }

    final ranges = <({SmlRange range, SmlWorksheet sheet})>[];
    final tests = <bool Function(Object?)>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (i < first || (i - first).isEven) {
        final reference = _conditionalRange(ctx, arg);
        if (reference is FormulaErrorValue) return reference;
        if (reference is! ({SmlRange range, SmlWorksheet sheet})) {
          return invalid;
        }
        if (ranges.isNotEmpty) {
          final a = ranges.first.range;
          final b = reference.range;
          if (a.maxRow - a.minRow != b.maxRow - b.minRow ||
              a.maxCol - a.minCol != b.maxCol - b.minCol) {
            return invalid;
          }
        }
        ranges.add(reference);
      } else {
        final criterion = arg.eval(ctx);
        if (criterion is FormulaErrorValue) return criterion;
        if (criterion is List || criterion is FormulaSpill) {
          // Array criteria can return spilled results. The scalar evaluator
          // must leave any saved result of that formula intact.
          return const FormulaErrorValue('#VALUE!', isUnsupported: true);
        }
        tests.add(_compileCriterion(criterion ?? 0));
      }
    }

    final shape = ranges.first.range;
    Object? valueAt(int index, int col, int row) {
      final ref = ranges[index];
      return ctx.valueOf(
        SmlCellRef(ref.range.minCol + col, ref.range.minRow + row),
        onSheet: ref.sheet,
      );
    }

    var total = 0.0;
    for (var row = 0; row <= shape.maxRow - shape.minRow; row++) {
      for (var col = 0; col <= shape.maxCol - shape.minCol; col++) {
        var matches = true;
        for (var i = 0; i < tests.length; i++) {
          final candidate = valueAt(first + i, col, row);
          if (candidate is FormulaErrorValue && candidate.isUnsupported) {
            return candidate;
          }
          if (!tests[i](candidate)) {
            matches = false;
            break;
          }
        }
        if (!matches) continue;
        if (!sum) {
          total++;
          continue;
        }
        final candidate = valueAt(0, col, row);
        if (candidate is FormulaErrorValue) return candidate;
        if (candidate is num) total += candidate.toDouble();
      }
    }
    return total;
  }

  static Object? _conditionalRange(FormulaContext ctx, FormulaNode node) {
    switch (node) {
      case RangeNode(:final range, :final sheetName):
        return _onWorksheet(ctx, range, sheetName);
      case CellNode(:final ref, :final sheetName):
        return _onWorksheet(ctx, SmlRange(ref, ref), sheetName);
      case ExternalCellNode():
        return const FormulaErrorValue('#VALUE!', isUnsupported: true);
      case NamedRangeNode(:final name, :final sheetName):
        if (sheetName == null) {
          if (ctx.lets.containsKey(name.toUpperCase())) {
            return const FormulaErrorValue('#VALUE!', isUnsupported: true);
          }
          final table = SmlTable.resolveRef(ctx.sheet, name);
          if (table != null) return (range: table, sheet: ctx.sheet);
        }
        final definition = node.resolve(ctx.workbook, ctx.sheet);
        if (definition is SmlNamedRange) {
          return _onWorksheet(ctx, definition.range, definition.sheetName);
        }
        final value = node.eval(ctx);
        return value is FormulaErrorValue ? value : null;
      case CallNode():
        // Functions such as INDEX can produce Excel references. This
        // evaluator only exposes their values, so preserve the cached result.
        return const FormulaErrorValue('#VALUE!', isUnsupported: true);
      default:
        return null;
    }
  }

  static Object _onWorksheet(
    FormulaContext ctx,
    SmlRange range,
    String? sheetName,
  ) {
    final sheet = sheetName == null
        ? ctx.sheet
        : ctx.workbook.sheetByName(sheetName);
    return sheet == null
        ? const FormulaErrorValue('#REF!')
        : (range: range, sheet: sheet);
  }

  static final _criteriaOperator = RegExp(r'^(<>|>=|<=|=|>|<)');

  static bool Function(Object?) _compileCriterion(Object criterion) {
    var op = '=';
    var text = formulaString(criterion);
    final match = criterion is String
        ? _criteriaOperator.firstMatch(text)
        : null;
    if (match != null) {
      op = match.group(0)!;
      text = text.substring(match.end);
    }
    final lower = text.toLowerCase();
    final isEquality = op == '=' || op == '<>';
    final number = double.tryParse(text);
    final bool? logical = switch (lower) {
      'true' => true,
      'false' => false,
      _ => null,
    };
    bool ordered(int comparison) => switch (op) {
      '>' => comparison > 0,
      '>=' => comparison >= 0,
      '<' => comparison < 0,
      '<=' => comparison <= 0,
      _ => false,
    };

    if (number != null && number.isFinite) {
      if (!isEquality) {
        return (value) => value is num && ordered(value.compareTo(number));
      }
      return (value) =>
          (op == '=') ==
          ((value is num
                  ? value
                  : value is String
                  ? double.tryParse(value)
                  : null) ==
              number);
    }
    if (logical != null && isEquality) {
      return (value) => (op == '=') == (value == logical);
    }
    if (isEquality) {
      final wildcard = _criterionWildcard(lower);
      return (value) {
        final candidate = value is String
            ? value.toLowerCase()
            : value is FormulaErrorValue
            ? value.code.toLowerCase()
            : null;
        final matches = text.isEmpty
            ? value == null || value == ''
            : wildcard != null
            ? value is String && wildcard(candidate!)
            : candidate == lower;
        return (op == '=') == matches;
      };
    }
    return (value) =>
        value is String && ordered(value.toLowerCase().compareTo(lower));
  }

  static bool Function(String)? _criterionWildcard(String pattern) {
    if (!pattern.contains(RegExp(r'[?*~]'))) return null;
    const star = -1;
    const any = -2;
    final tokens = <int>[];
    final patternRunes = pattern.runes.toList();
    for (var i = 0; i < patternRunes.length; i++) {
      final rune = patternRunes[i];
      if (rune == 0x7e &&
          i + 1 < patternRunes.length &&
          const {0x7e, 0x2a, 0x3f}.contains(patternRunes[i + 1])) {
        tokens.add(patternRunes[++i]);
      } else {
        tokens.add(switch (rune) {
          0x2a => star,
          0x3f => any,
          _ => rune,
        });
      }
    }
    return (text) {
      final runes = text.runes.toList();
      var patternIndex = 0;
      var textIndex = 0;
      var lastStar = -1;
      var starEnd = 0;
      while (textIndex < runes.length) {
        final token = patternIndex < tokens.length
            ? tokens[patternIndex]
            : null;
        if (token == star) {
          lastStar = patternIndex++;
          starEnd = textIndex;
        } else if (token == any || token == runes[textIndex]) {
          patternIndex++;
          textIndex++;
        } else if (lastStar >= 0) {
          patternIndex = lastStar + 1;
          textIndex = ++starEnd;
        } else {
          return false;
        }
      }
      while (patternIndex < tokens.length && tokens[patternIndex] == star) {
        patternIndex++;
      }
      return patternIndex == tokens.length;
    };
  }

  static Object? _vlookup(
    FormulaContext ctx,
    List<FormulaNode> args,
    bool horiz,
  ) {
    if (args.length < 3 || args[1] is! RangeNode) {
      return const FormulaErrorValue('#N/A');
    }
    final Object? key = args[0].eval(ctx);
    final RangeNode table = args[1] as RangeNode;
    final int index = (asFormulaNumber(args[2].eval(ctx)) ?? 1).toInt();
    final List<SmlCellRef> cells = table.range.cells.toList();
    final int cols = (table.range.end.col - table.range.start.col).abs() + 1;
    final int rows = (table.range.end.row - table.range.start.row).abs() + 1;
    if (horiz) {
      for (int c = 0; c < cols; c++) {
        if (formulaString(
              ctx.valueOf(
                SmlCellRef(table.range.start.col + c, table.range.start.row),
              ),
            ) ==
            formulaString(key)) {
          return ctx.valueOf(
            SmlCellRef(
              table.range.start.col + c,
              table.range.start.row + index - 1,
            ),
          );
        }
      }
    } else {
      for (int r = 0; r < rows; r++) {
        if (formulaString(
              ctx.valueOf(
                SmlCellRef(table.range.start.col, table.range.start.row + r),
              ),
            ) ==
            formulaString(key)) {
          return ctx.valueOf(
            SmlCellRef(
              table.range.start.col + index - 1,
              table.range.start.row + r,
            ),
          );
        }
      }
    }
    cells.length;
    return const FormulaErrorValue('#N/A');
  }

  static Object? _index(List<Object?> vals) {
    if (vals.isEmpty) return const FormulaErrorValue('#VALUE!');
    final List<Object?> arr = flattenValues(vals[0]);
    final int r = (_n(vals, 1)?.toInt() ?? 1) - 1;
    if (r < 0 || r >= arr.length) return const FormulaErrorValue('#REF!');
    return arr[r];
  }

  static Object? _match(List<Object?> vals) {
    final Object? key = vals[0];
    final List<Object?> arr = flattenValues(
      vals.length > 1 ? vals[1] : <Object?>[],
    );
    for (int i = 0; i < arr.length; i++) {
      if (formulaString(arr[i]) == formulaString(key)) {
        return (i + 1).toDouble();
      }
    }
    return const FormulaErrorValue('#N/A');
  }

  static Object? _xlookup(List<Object?> vals) {
    final Object? found = _match(vals);
    if (found is! num) return found;
    final List<Object?> ret = flattenValues(
      vals.length > 2 ? vals[2] : vals[1],
    );
    final int i = found.toInt() - 1;
    return (i >= 0 && i < ret.length)
        ? ret[i]
        : const FormulaErrorValue('#N/A');
  }

  static Object? _lookup(List<Object?> vals) => _xlookup(vals);

  static final _serialEpoch = DateTime.utc(1899, 12, 31);
  static final _serialEpoch1904 = DateTime.utc(1904);

  static DateTime? _date(Object? value, bool use1904) {
    if (value is DateTime) return value;
    final serial = asFormulaNumber(value);
    if (serial == null || !serial.isFinite || serial < 0 || serial > 2958465) {
      return null;
    }
    final epoch = use1904 ? _serialEpoch1904 : _serialEpoch;
    final days = use1904 || serial < 60 ? serial : serial - 1;
    return epoch.add(Duration(milliseconds: (days * 86400000).round()));
  }

  static double _dateSerial(DateTime date, bool use1904) {
    final epoch = use1904 ? _serialEpoch1904 : _serialEpoch;
    final serial = date.difference(epoch).inMilliseconds / 86400000;
    return use1904 || serial < 60 ? serial : serial + 1;
  }

  static Object _datePart(String name, Object? value, bool use1904) {
    final date = _date(value ?? 0, use1904);
    if (date == null) return const FormulaErrorValue('#VALUE!');
    final serial = value is num
        ? value.floor()
        : value == null
        ? 0
        : null;
    final leapDay = !use1904 && serial == 60;
    final dayZero = !use1904 && serial == 0;
    return switch (name) {
      'YEAR' => dayZero ? 1900.0 : date.year.toDouble(),
      'MONTH' => dayZero ? 1.0 : date.month.toDouble(),
      'DAY' =>
        dayZero
            ? 0.0
            : leapDay
            ? 29.0
            : date.day.toDouble(),
      'HOUR' => date.hour.toDouble(),
      'MINUTE' => date.minute.toDouble(),
      'SECOND' => date.second.toDouble(),
      _ =>
        (date.weekday + (!use1904 && serial != null && serial < 60 ? -1 : 0)) %
                7 +
            1,
    };
  }

  static Object? _fin(String name, List<Object?> vals) {
    final double rate = _n(vals, 0) ?? 0;
    final double nper = _n(vals, 1) ?? 0;
    final double pmt = _n(vals, 2) ?? 0;
    final double pv = _n(vals, 3) ?? 0;
    if (name == 'PMT') {
      if (rate == 0) return nper == 0 ? 0 : -pv / nper;
      final double f = _powNum(1 + rate, nper);
      return -pv * rate * f / (f - 1);
    }
    if (name == 'FV') {
      return -pv * _powNum(1 + rate, nper) - pmt * nper;
    }
    return pv;
  }

  static Object? _npv(List<Object?> vals) {
    final double rate = _n(vals, 0) ?? 0;
    var s = 0.0;
    final List<double> cfs = flattenNumbers(vals.skip(1).toList());
    for (int i = 0; i < cfs.length; i++) {
      s += cfs[i] / _powNum(1 + rate, i + 1);
    }
    return s;
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    var g = x;
    for (int i = 0; i < 20; i++) {
      g = 0.5 * (g + x / g);
    }
    return g;
  }

  static double _ln(double x) => x.isFinite && x > 0 ? math.log(x) : double.nan;

  static double _exp(double x) => x.isFinite ? math.exp(x) : double.nan;

  static double _powNum(double a, double b) =>
      a.isFinite && b.isFinite ? math.pow(a, b).toDouble() : double.nan;

  static Object? _let(List<FormulaNode> args, FormulaContext ctx) {
    if (args.length < 3 || args.length.isEven) {
      return const FormulaErrorValue('#VALUE!');
    }
    final List<String> added = <String>[];
    try {
      for (int i = 0; i < args.length - 1; i += 2) {
        final FormulaNode nameNode = args[i];
        final String name =
            (nameNode is NamedRangeNode
                    ? nameNode.name
                    : formulaString(nameNode.eval(ctx)))
                .toUpperCase();
        if (name.isEmpty) {
          return const FormulaErrorValue('#VALUE!');
        }
        ctx.lets[name] = args[i + 1].eval(ctx);
        added.add(name);
      }
      return args.last.eval(ctx);
    } finally {
      for (final String name in added) {
        ctx.lets.remove(name);
      }
    }
  }

  static Object? _filter(List<Object?> vals) {
    if (vals.length < 2) {
      return const FormulaErrorValue('#VALUE!');
    }
    final List<Object?> array = flattenValues(vals[0]);
    final List<Object?> include = flattenValues(vals[1]);
    if (array.isEmpty) {
      return const FormulaErrorValue('#CALC!');
    }
    final List<Object?> out = <Object?>[];
    for (int i = 0; i < array.length; i++) {
      final Object? flag = i < include.length
          ? include[i]
          : (include.isEmpty ? false : include.last);
      if (_truth(flag)) {
        out.add(array[i]);
      }
    }
    if (out.isEmpty) {
      return const FormulaErrorValue('#CALC!');
    }
    if (out.length == 1) {
      return out.first;
    }
    return out.map(formulaString).join(',');
  }

  static Object? _unique(List<Object?> vals) {
    if (vals.isEmpty) {
      return const FormulaErrorValue('#VALUE!');
    }
    final List<Object?> array = flattenValues(vals);
    final List<Object?> out = <Object?>[];
    final Set<String> seen = <String>{};
    for (final Object? item in array) {
      if (seen.add(formulaString(item).toLowerCase())) {
        out.add(item);
      }
    }
    if (out.isEmpty) {
      return '';
    }
    if (out.length == 1) {
      return out.first;
    }
    return out.map(formulaString).join(',');
  }

  static Object? _sortFn(List<Object?> vals) {
    if (vals.isEmpty) {
      return const FormulaErrorValue('#VALUE!');
    }
    final List<Object?> array = flattenValues(vals[0]);
    final bool ascending = vals.length < 2 || _truth(vals[1]);
    array.sort((Object? a, Object? b) {
      final double? an = asFormulaNumber(a);
      final double? bn = asFormulaNumber(b);
      final int cmp;
      if (an != null && bn != null) {
        cmp = an.compareTo(bn);
      } else {
        cmp = formulaString(
          a,
        ).toLowerCase().compareTo(formulaString(b).toLowerCase());
      }
      return ascending ? cmp : -cmp;
    });
    if (array.isEmpty) {
      return '';
    }
    if (array.length == 1) {
      return array.first;
    }
    return array.map(formulaString).join(',');
  }

  static Object? _textFmt(List<Object?> vals, bool use1904, String locale) {
    if (vals.isEmpty) {
      return '';
    }
    final String fmt = vals.length > 1 ? formulaString(vals[1]) : '0';
    final double? n = asFormulaNumber(vals[0]);
    if (n == null) {
      return formulaString(vals[0]);
    }
    if (!n.isFinite) return const FormulaErrorValue('#VALUE!');
    final germanSyntax = RegExp(
      r'^de([-_]|$)',
      caseSensitive: false,
    ).hasMatch(locale);
    final format = _dateTextFormat(fmt, germanSyntax);
    if (format != null) {
      if (format.invalid) return const FormulaErrorValue('#VALUE!');
      final date = _date(n, use1904);
      if (date == null) return const FormulaErrorValue('#VALUE!');
      final serial = n.floor();
      final firstDay = !use1904 && serial == 0;
      final leapDay = !use1904 && serial == 60;
      return formatExcelDate(
        firstDay ? date.add(const Duration(days: 1)) : date,
        format.mask,
        germanNames: format.germanNames,
        lowercaseMonthIsMinute: format.germanSyntax,
        serial: n,
        calendarDay: firstDay ? 0 : (leapDay ? 29 : null),
        calendarWeekday: !use1904 && serial < 60
            ? (date.weekday + 5) % 7 + 1
            : null,
      );
    }
    if (fmt == '@' || germanSyntax && fmt.toLowerCase() == 'standard') {
      final plain = formulaString(n);
      return germanSyntax ? plain.replaceFirst('.', ',') : plain;
    }
    if (fmt.toLowerCase() == 'general') {
      return germanSyntax
          ? const FormulaErrorValue('#VALUE!')
          : formulaString(n);
    }
    final formatted = applyNumberFormat(
      n,
      fmt,
      decimalSeparator: germanSyntax ? ',' : '.',
      groupSeparator: germanSyntax ? '.' : ',',
    );
    if (formatted.startsWith('RED:') && fmt.contains('[Red]')) {
      return formatted.substring(4);
    }
    return formatted;
  }

  static final _dateMaskParts = RegExp(r'\\.|"[^"]*"|\[[^\]]*\]|[a-zA-Z]+');
  static final _dateTokens = RegExp(r'^[ymdhs]+$', caseSensitive: false);
  static final _germanDateTokens = RegExp(
    r'^[jtmdyhs]+$',
    caseSensitive: false,
  );

  static ({String mask, bool germanNames, bool germanSyntax, bool invalid})?
  _dateTextFormat(String input, bool germanSyntax) {
    var hasDateTokens = false;
    var germanNames = false;
    var foreignDateToken = false;
    final localSyntax =
        germanSyntax ||
        _dateMaskParts.allMatches(input).any((match) {
          final token = match[0]!;
          return _germanDateTokens.hasMatch(token) &&
              RegExp(r'jj|tt', caseSensitive: false).hasMatch(token);
        });
    final mask = input.replaceAllMapped(_dateMaskParts, (match) {
      final token = match[0]!;
      final lower = token.toLowerCase();
      if (lower == r'[$-407]' || lower == r'[$-de-de]') {
        germanNames = true;
      }
      if (const {'[h]', '[hh]', '[m]', '[mm]', '[s]', '[ss]'}.contains(lower)) {
        hasDateTokens = true;
      }
      final tokenPattern = localSyntax ? _germanDateTokens : _dateTokens;
      if (!tokenPattern.hasMatch(token)) return token;
      hasDateTokens = true;
      if (!localSyntax) return token;
      return token.replaceAllMapped(
        RegExp(r'j+|t+|d+|y+', caseSensitive: false),
        (part) {
          final code = part[0]!;
          final letter = code[0].toLowerCase();
          if (letter == 'd' || letter == 'y') foreignDateToken = true;
          return switch (letter) {
            'j' => code.length >= 4 ? 'yyyy' : 'yy',
            't' => List.filled(code.length, 'd').join(),
            _ => '"$code"',
          };
        },
      );
    });
    if (!hasDateTokens) return null;
    final separators = input.replaceAll(_dateMaskParts, '');
    if (RegExp(r'[0#?]').hasMatch(separators) &&
        !RegExp(r's+[.,]0{1,3}$', caseSensitive: false).hasMatch(input)) {
      return null;
    }
    final invalid =
        foreignDateToken &&
        (separators.contains('/') || RegExp(r'\[\$-[^\]]+\]').hasMatch(input));
    return (
      mask: mask,
      germanNames: germanNames,
      germanSyntax: localSyntax,
      invalid: invalid,
    );
  }

  static Object? _indirect(FormulaContext ctx, List<Object?> vals) {
    if (vals.isEmpty) {
      return const FormulaErrorValue('#REF!');
    }
    final errors = flattenValues(vals).whereType<FormulaErrorValue>();
    if (errors.isNotEmpty) return errors.first;
    if (vals.length > 1 && !_truth(vals[1])) {
      return const FormulaErrorValue(
        '#ERROR! R1C1 INDIRECT is not evaluated',
        isUnsupported: true,
      );
    }
    final String ref = formulaString(vals[0]).trim();
    if (ref.contains('[') || ref.contains(']')) {
      return const FormulaErrorValue(
        '#ERROR! External or structured INDIRECT references are not evaluated',
        isUnsupported: true,
      );
    }
    if (ref.startsWith('=')) return const FormulaErrorValue('#REF!');
    try {
      final target = parseFormula(ref);
      if (target is CellNode) {
        if (!_validCell(target.ref)) return const FormulaErrorValue('#REF!');
        return target.eval(ctx);
      }
      if (target is RangeNode) {
        if (!_validCell(target.range.start) || !_validCell(target.range.end)) {
          return const FormulaErrorValue('#REF!');
        }
        return target.eval(ctx);
      }
      if (target is NamedRangeNode) {
        final definition = target.resolve(ctx.workbook, ctx.sheet);
        if (definition is SmlNamedRange) return target.eval(ctx);
        if (definition is SmlFormulaName) {
          return const FormulaErrorValue(
            '#ERROR! Computed INDIRECT names are not evaluated',
            isUnsupported: true,
          );
        }
      }
      return const FormulaErrorValue('#REF!');
    } on UnsupportedError catch (error) {
      return FormulaErrorValue('#ERROR! $error', isUnsupported: true);
    } on Object {
      return const FormulaErrorValue('#REF!');
    }
  }

  static bool _validCell(SmlCellRef ref) =>
      ref.col >= 0 && ref.col < 16384 && ref.row >= 0 && ref.row < 1048576;

  static Object? _offset(
    FormulaContext ctx,
    List<FormulaNode> args,
    List<Object?> vals,
  ) {
    if (args.isEmpty) {
      return const FormulaErrorValue('#VALUE!');
    }
    SmlRange? range;
    SmlWorksheet? target = ctx.sheet;
    final FormulaNode first = args[0];
    if (first is ExternalCellNode) {
      throw UnsupportedError('OFFSET of external references');
    }
    if (first is CellNode) {
      range = SmlRange(first.ref, first.ref);
      target = first.sheetName == null
          ? ctx.sheet
          : ctx.workbook.sheetByName(first.sheetName!);
    } else if (first is RangeNode) {
      range = first.range;
      target = first.sheetName == null
          ? ctx.sheet
          : ctx.workbook.sheetByName(first.sheetName!);
    } else if (first is NamedRangeNode) {
      final definition = first.resolve(ctx.workbook, ctx.sheet);
      if (first.sheetName != null || definition?.localSheetId != null) {
        // OFFSET requires dynamic target dependencies beyond a name's range.
        // Do not accidentally extend it by the new scoped-name parser.
        throw UnsupportedError('OFFSET of scoped names is not evaluated');
      }
      final SmlNamedRange? named = ctx.workbook.namedRange(first.name);
      range = named?.range;
      target = named == null ? null : ctx.workbook.sheetByName(named.sheetName);
    }
    if (range == null) {
      return const FormulaErrorValue('#VALUE!');
    }
    if (target == null) return const FormulaErrorValue('#REF!');
    final origin = SmlCellRef(range.minCol, range.minRow);
    final int rows = (_n(vals, 1) ?? 0).toInt();
    final int cols = (_n(vals, 2) ?? 0).toInt();
    final int height = vals.length > 3
        ? (_n(vals, 3) ?? 1).toInt()
        : range.maxRow - range.minRow + 1;
    final int width = vals.length > 4
        ? (_n(vals, 4) ?? 1).toInt()
        : range.maxCol - range.minCol + 1;
    final SmlCellRef start = SmlCellRef(origin.col + cols, origin.row + rows);
    final end = SmlCellRef(start.col + width - 1, start.row + height - 1);
    if (height <= 0 || width <= 0 || !_validCell(start) || !_validCell(end)) {
      return const FormulaErrorValue('#REF!');
    }
    if (height == 1 && width == 1) {
      return ctx.valueOf(start, onSheet: target);
    }
    return RangeNode(SmlRange(start, end), sheetName: target.name).eval(ctx);
  }

  static Object? _edate(List<Object?> vals, bool use1904) {
    final DateTime? d = _date(vals.isEmpty ? null : vals[0], use1904);
    if (d == null) {
      return const FormulaErrorValue('#VALUE!');
    }
    final int months = (_n(vals, 1) ?? 0).toInt();
    final int endDay = DateTime.utc(d.year, d.month + months + 1, 0).day;
    final DateTime next = DateTime.utc(
      d.year,
      d.month + months,
      math.min(d.day, endDay),
    );
    return _dateSerial(next, use1904);
  }

  static Object? _eomonth(List<Object?> vals, bool use1904) {
    final DateTime? d = _date(vals.isEmpty ? null : vals[0], use1904);
    if (d == null) {
      return const FormulaErrorValue('#VALUE!');
    }
    final int months = (_n(vals, 1) ?? 0).toInt();
    final DateTime next = DateTime.utc(d.year, d.month + months + 1, 0);
    return _dateSerial(next, use1904);
  }

  static Object? _networkdays(List<Object?> vals, bool use1904) {
    final DateTime? start = _date(vals.isEmpty ? null : vals[0], use1904);
    final DateTime? end = _date(vals.length < 2 ? null : vals[1], use1904);
    if (start == null || end == null) {
      return const FormulaErrorValue('#VALUE!');
    }
    DateTime a = start;
    DateTime b = end;
    var sign = 1;
    if (a.isAfter(b)) {
      final DateTime tmp = a;
      a = b;
      b = tmp;
      sign = -1;
    }
    var count = 0;
    var cursor = DateTime.utc(a.year, a.month, a.day);
    final DateTime last = DateTime.utc(b.year, b.month, b.day);
    while (!cursor.isAfter(last)) {
      if (cursor.weekday <= DateTime.friday) {
        count++;
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return count * sign;
  }

  static Object? _formulatext(List<FormulaNode> args, FormulaContext ctx) {
    if (args.isEmpty) {
      return const FormulaErrorValue('#N/A');
    }
    final FormulaNode first = args.first;
    if (first is ExternalCellNode) {
      throw UnsupportedError('FORMULATEXT of external references');
    }
    if (first is CellNode) {
      final SmlWorksheet? sheet = first.sheetName == null
          ? ctx.sheet
          : ctx.workbook.sheetByName(first.sheetName!);
      final String? formula = sheet?.cell(first.ref).formula;
      if (formula == null || formula.isEmpty) {
        return const FormulaErrorValue('#N/A');
      }
      return formula.startsWith('=') ? formula : '=$formula';
    }
    return const FormulaErrorValue('#N/A');
  }

  static Object? _transpose(List<FormulaNode> args, FormulaContext ctx) {
    if (args.isEmpty) {
      return const FormulaErrorValue('#VALUE!');
    }
    final FormulaNode first = args.first;
    if (first is! RangeNode) {
      return first.eval(ctx);
    }
    final SmlRange range = first.range;
    final int rows = range.maxRow - range.minRow + 1;
    final int cols = range.maxCol - range.minCol + 1;
    final SmlWorksheet? sheet = first.sheetName == null
        ? ctx.sheet
        : ctx.workbook.sheetByName(first.sheetName!);
    final List<List<Object?>> grid = <List<Object?>>[
      for (int c = 0; c < cols; c++)
        <Object?>[
          for (int r = 0; r < rows; r++)
            ctx.valueOf(
              SmlCellRef(range.minCol + c, range.minRow + r),
              onSheet: sheet,
            ),
        ],
    ];
    if (grid.length == 1 && grid.first.length == 1) {
      return grid.first.first;
    }
    return FormulaSpill(grid);
  }

  static Object? _irr(List<Object?> vals) {
    final List<double> flows = flattenNumbers(vals);
    if (flows.length < 2) {
      return const FormulaErrorValue('#NUM!');
    }
    var rate = 0.1;
    for (int i = 0; i < 40; i++) {
      var npv = 0.0;
      var deriv = 0.0;
      for (int t = 0; t < flows.length; t++) {
        final double den = math.pow(1 + rate, t).toDouble();
        npv += flows[t] / den;
        if (t > 0) {
          deriv -= t * flows[t] / (den * (1 + rate));
        }
      }
      if (deriv.abs() < 1e-12) {
        break;
      }
      final double next = rate - npv / deriv;
      if ((next - rate).abs() < 1e-8) {
        return next;
      }
      rate = next;
    }
    return rate;
  }

  static Object? _time(List<Object?> vals) {
    final double h = _n(vals, 0) ?? 0;
    final double m = _n(vals, 1) ?? 0;
    final double s = _n(vals, 2) ?? 0;
    return ((h + m / 60 + s / 3600) / 24) % 1;
  }

  static Object? _days(List<Object?> vals, bool use1904) {
    final DateTime? end = _date(vals.isEmpty ? null : vals[0], use1904);
    final DateTime? start = _date(vals.length < 2 ? null : vals[1], use1904);
    if (end == null || start == null) {
      return const FormulaErrorValue('#VALUE!');
    }
    return end.difference(start).inDays.toDouble();
  }

  static Object? _sequence(List<Object?> vals) {
    final int rows = (_n(vals, 0) ?? 1).toInt().clamp(1, 100);
    final int cols = (vals.length > 1 ? (_n(vals, 1) ?? 1) : 1).toInt().clamp(
      1,
      50,
    );
    final double start = _n(vals, 2) ?? 1;
    final double step = _n(vals, 3) ?? 1;
    var value = start;
    final List<List<Object?>> grid = <List<Object?>>[];
    for (int r = 0; r < rows; r++) {
      final List<Object?> row = <Object?>[];
      for (int c = 0; c < cols; c++) {
        row.add(value);
        value += step;
      }
      grid.add(row);
    }
    if (rows == 1 && cols == 1) {
      return grid.first.first;
    }
    return FormulaSpill(grid);
  }
}
