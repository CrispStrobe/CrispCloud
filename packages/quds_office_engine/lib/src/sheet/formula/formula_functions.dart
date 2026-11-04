import 'dart:math' as math;

import '../model/sml_analysis.dart';
import '../model/sml_workbook.dart';
import 'formula_ast.dart';

/// Broad catalog of spreadsheet functions (Excel-like names; not full Excel).
abstract final class FormulaFunctions {
  /// call API.
  static Object? call(String name, List<FormulaNode> args, FormulaContext ctx) {
    final String n = stripFutureFunctionPrefix(name.toUpperCase());
    if (n == 'LET') {
      return _let(args, ctx);
    }
    final List<Object?> vals = args
        .map((FormulaNode a) => a.eval(ctx))
        .toList();
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
        return _round(_n1(vals) ?? 0, _n(vals, 1)?.toInt() ?? 0);
      case 'ROUNDUP':
        return _roundToward(_n1(vals) ?? 0, _n(vals, 1)?.toInt() ?? 0, true);
      case 'ROUNDDOWN':
        return _roundToward(_n1(vals) ?? 0, _n(vals, 1)?.toInt() ?? 0, false);
      case 'MOD':
        final double? a = _n(vals, 0);
        final double? b = _n(vals, 1);
        if (a == null || b == null || b == 0) return '#DIV/0!';
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
        return x == null || x < 0 ? '#NUM!' : _sqrt(x);
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
            ? '#DIV/0!'
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
        return _days(vals);
      case 'SHEET':
        return (ctx.workbook.sheets.indexOf(ctx.sheet) + 1).toDouble();
      case 'SHEETS':
        return ctx.workbook.sheets.length.toDouble();
      case 'IF':
        return _truth(vals.isEmpty ? null : vals[0])
            ? (vals.length > 1 ? vals[1] : true)
            : (vals.length > 2 ? vals[2] : false);
      case 'AND':
        return vals.every(_truth);
      case 'OR':
        return vals.any(_truth);
      case 'XOR':
        return vals.where(_truth).length.isOdd;
      case 'NOT':
        return !_truth(vals.isEmpty ? null : vals[0]);
      case 'TRUE':
        return true;
      case 'FALSE':
        return false;
      case 'IFERROR':
        return _isErr(vals.isEmpty ? null : vals[0])
            ? (vals.length > 1 ? vals[1] : 0)
            : vals[0];
      case 'IFNA':
        return vals.isNotEmpty && vals[0] == '#N/A'
            ? (vals.length > 1 ? vals[1] : 0)
            : vals[0];
      case 'IFS':
        for (int i = 0; i + 1 < vals.length; i += 2) {
          if (_truth(vals[i])) return vals[i + 1];
        }
        return '#N/A';
      case 'SWITCH':
        final Object? expr = vals.isEmpty ? null : vals[0];
        for (int i = 1; i + 1 < vals.length; i += 2) {
          if (formulaString(expr) == formulaString(vals[i])) return vals[i + 1];
        }
        return vals.length.isEven ? vals.last : '#N/A';
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
      case 'SUMIF':
        return _sumIf(ctx, args);
      case 'COUNTIF':
        return _countIf(ctx, args);
      case 'AVERAGEIF':
        return _avgIf(ctx, args);
      case 'SUMIFS':
        return _sumIfs(ctx, args);
      case 'COUNTIFS':
        return _countIfs(ctx, args);
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
        final int at = formulaString(vals.length > 1 ? vals[1] : '').indexOf(
          n == 'SEARCH'
              ? formulaString(vals[0]).toLowerCase()
              : formulaString(vals[0]),
        );
        return at < 0 ? '#VALUE!' : (at + 1).toDouble();
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
        return formulaString(vals[0]).replaceAll(
          formulaString(vals.length > 1 ? vals[1] : ''),
          formulaString(vals.length > 2 ? vals[2] : ''),
        );
      case 'REPT':
        return List<String>.filled(
          _n(vals, 1)?.toInt() ?? 0,
          formulaString(vals[0]),
        ).join();
      case 'VALUE':
        return asFormulaNumber(vals[0]) ?? '#VALUE!';
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
      case 'ADDRESS': {
        final int row = (_n(vals, 0) ?? 1).toInt();
        final int col = (_n(vals, 1) ?? 1).toInt();
        if (row < 1 || col < 1) {
          return '#VALUE!';
        }
        final int abs = (_n(vals, 2) ?? 1).toInt().clamp(1, 4);
        final bool a1 = vals.length < 4 || _truth(vals[3]);
        if (!a1) {
          return 'R${row}C$col';
        }
        final String letters = SmlCellRef(col - 1, row - 1).a1.replaceAll(
          RegExp(r'\d+'),
          '',
        );
        final bool absRow = abs == 1 || abs == 2;
        final bool absCol = abs == 1 || abs == 3;
        final String sheet =
            vals.length > 4 ? formulaString(vals[4]).trim() : '';
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
      case 'CELL': {
        final String info = formulaString(vals.isEmpty ? null : vals[0])
            .toLowerCase();
        SmlCellRef ref = ctx.origin;
        if (args.length > 1 && args[1] is CellNode) {
          ref = (args[1] as CellNode).ref;
        } else if (args.length > 1 && args[1] is RangeNode) {
          ref = (args[1] as RangeNode).range.start;
        }
        return switch (info) {
          'address' => ref.a1,
          'col' || 'column' => (ref.col + 1).toDouble(),
          'row' => (ref.row + 1).toDouble(),
          'contents' =>
            args.length > 1 ? vals[1] : ctx.sheet.cell(ref).value,
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
          _ => '#N/A',
        };
      }
      case 'INFO': {
        final String type = formulaString(vals.isEmpty ? null : vals[0])
            .toLowerCase();
        return switch (type) {
          'directory' => '',
          'numfile' => 1.0,
          'origin' => r'$A:$A$1',
          'osversion' => 'Quds',
          'recalc' => 'Automatic',
          'release' => 'QudsOffice',
          'system' => 'pcdos',
          'memavail' || 'memused' || 'totmem' => 0.0,
          _ => '#N/A',
        };
      }
      case 'FIXED': {
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
      case 'YEN': {
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
        return (i >= 1 && i < vals.length) ? vals[i] : '#VALUE!';
      case 'LOOKUP':
        return _lookup(vals);
      case 'ROW':
        return (vals.isEmpty
                ? ctx.origin.row
                : (args[0] is CellNode
                      ? (args[0] as CellNode).ref.row
                      : ctx.origin.row)) +
            1;
      case 'COLUMN':
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
        return _isErr(vals[0]);
      case 'ISNA':
        return vals[0] == '#N/A';
      case 'ISTEXT':
        return vals[0] is String;
      case 'ISNUMBER':
        return vals[0] is num;
      case 'ISLOGICAL':
        return vals[0] is bool;
      case 'ISNONTEXT':
        return vals[0] is! String;
      case 'NA':
        return '#N/A';
      case 'TYPE':
        final Object? t = vals[0];
        if (t is num) return 1;
        if (t is String) return 2;
        if (t is bool) return 4;
        if (_isErr(t)) return 16;
        return 64;
      case 'DATE':
        return DateTime(
              _n(vals, 0)?.toInt() ?? 1900,
              _n(vals, 1)?.toInt() ?? 1,
              _n(vals, 2)?.toInt() ?? 1,
            ).millisecondsSinceEpoch /
            86400000;
      case 'TODAY':
      case 'NOW':
        return DateTime.now().millisecondsSinceEpoch / 86400000;
      case 'YEAR':
        return _date(vals[0])?.year.toDouble() ?? '#VALUE!';
      case 'MONTH':
        return _date(vals[0])?.month.toDouble() ?? '#VALUE!';
      case 'DAY':
        return _date(vals[0])?.day.toDouble() ?? '#VALUE!';
      case 'HOUR':
        return _date(vals[0])?.hour.toDouble() ?? 0;
      case 'MINUTE':
        return _date(vals[0])?.minute.toDouble() ?? 0;
      case 'SECOND':
        return _date(vals[0])?.second.toDouble() ?? 0;
      case 'WEEKDAY':
        return ((_date(vals[0])?.weekday ?? 1) % 7) + 1;
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
        return _textFmt(vals);
      case 'INDIRECT':
        return _indirect(ctx, vals);
      case 'OFFSET':
        return _offset(ctx, args, vals);
      case 'EDATE':
        return _edate(vals);
      case 'EOMONTH':
        return _eomonth(vals);
      case 'NETWORKDAYS':
        return _networkdays(vals);
      case 'SEQUENCE':
        return _sequence(vals);
      default:
        // Aliases that share an implementation.
        if (_aliases.containsKey(n)) {
          return call(_aliases[n]!, args, ctx);
        }
        return '#NAME?';
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
    'NUMBERVALUE': 'VALUE',
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
    'COUNTIFS': 'COUNTIFS',
    'SUMIFS': 'SUMIFS',
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
        ? '#DIV/0!'
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
  static bool _isErr(Object? v) => v is String && v.startsWith('#');

  static int _clamp(int v, int max) => v < 0 ? 0 : (v > max ? max : v);

  static String _cap(String w) =>
      w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';

  static double _round(double x, int digits) {
    var f = 1.0;
    for (int i = 0; i < digits; i++) {
      f *= 10;
    }
    for (int i = 0; i < -digits; i++) {
      f /= 10;
    }
    return (x * f).round() / f;
  }

  static double _roundToward(double x, int digits, bool up) {
    var f = 1.0;
    for (int i = 0; i < digits.abs(); i++) {
      f *= 10;
    }
    if (digits < 0) {
      f = 1 / f;
    }
    final double s = x * f;
    return (up ? s.ceil() : s.truncate()) / f;
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
    if (n.length < 2 && !pop) return '#DIV/0!';
    if (n.isEmpty) return 0;
    final double avg = n.fold(0.0, (double s, double x) => s + x) / n.length;
    final double ss = n.fold(
      0.0,
      (double s, double x) => s + (x - avg) * (x - avg),
    );
    return ss / (pop ? n.length : n.length - 1);
  }

  static Object? _sumIf(FormulaContext ctx, List<FormulaNode> args) {
    if (args.isEmpty || args[0] is! RangeNode) return 0;
    final RangeNode range = args[0] as RangeNode;
    final String crit = args.length > 1 ? formulaString(args[1].eval(ctx)) : '';
    final RangeNode sumRange = args.length > 2 && args[2] is RangeNode
        ? args[2] as RangeNode
        : range;
    var s = 0.0;
    final List<SmlCellRef> keys = range.range.cells.toList();
    final List<SmlCellRef> sums = sumRange.range.cells.toList();
    for (int i = 0; i < keys.length && i < sums.length; i++) {
      final Object? v = ctx.valueOf(keys[i]);
      if (_matchCrit(v, crit)) {
        s += asFormulaNumber(ctx.valueOf(sums[i])) ?? 0;
      }
    }
    return s;
  }

  static Object? _countIf(FormulaContext ctx, List<FormulaNode> args) {
    if (args.isEmpty || args[0] is! RangeNode) return 0;
    final String crit = args.length > 1 ? formulaString(args[1].eval(ctx)) : '';
    var c = 0;
    for (final SmlCellRef ref in (args[0] as RangeNode).range.cells) {
      if (_matchCrit(ctx.valueOf(ref), crit)) c++;
    }
    return c.toDouble();
  }

  static Object? _avgIf(FormulaContext ctx, List<FormulaNode> args) {
    final Object? s = _sumIf(ctx, args);
    final Object? c = _countIf(ctx, args);
    if (s is num && c is num && c != 0) return s / c;
    return '#DIV/0!';
  }

  static Object? _sumIfs(FormulaContext ctx, List<FormulaNode> args) =>
      _sumIf(ctx, args);

  static Object? _countIfs(FormulaContext ctx, List<FormulaNode> args) =>
      _countIf(ctx, args);

  static bool _matchCrit(Object? value, String crit) {
    if (crit.startsWith('>=')) {
      return (asFormulaNumber(value) ?? 0) >=
          (double.tryParse(crit.substring(2)) ?? 0);
    }
    if (crit.startsWith('<=')) {
      return (asFormulaNumber(value) ?? 0) <=
          (double.tryParse(crit.substring(2)) ?? 0);
    }
    if (crit.startsWith('<>')) {
      return formulaString(value) != crit.substring(2);
    }
    if (crit.startsWith('>')) {
      return (asFormulaNumber(value) ?? 0) >
          (double.tryParse(crit.substring(1)) ?? 0);
    }
    if (crit.startsWith('<')) {
      return (asFormulaNumber(value) ?? 0) <
          (double.tryParse(crit.substring(1)) ?? 0);
    }
    if (crit.contains('*')) {
      final String re = RegExp.escape(crit).replaceAll('\\*', '.*');
      return RegExp('^$re\$').hasMatch(formulaString(value));
    }
    return formulaString(value) == crit ||
        asFormulaNumber(value) == double.tryParse(crit);
  }

  static Object? _vlookup(
    FormulaContext ctx,
    List<FormulaNode> args,
    bool horiz,
  ) {
    if (args.length < 3 || args[1] is! RangeNode) return '#N/A';
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
    return '#N/A';
  }

  static Object? _index(List<Object?> vals) {
    if (vals.isEmpty) return '#VALUE!';
    final List<Object?> arr = flattenValues(vals[0]);
    final int r = (_n(vals, 1)?.toInt() ?? 1) - 1;
    if (r < 0 || r >= arr.length) return '#REF!';
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
    return '#N/A';
  }

  static Object? _xlookup(List<Object?> vals) {
    final Object? found = _match(vals);
    if (found is! num) return found;
    final List<Object?> ret = flattenValues(
      vals.length > 2 ? vals[2] : vals[1],
    );
    final int i = found.toInt() - 1;
    return (i >= 0 && i < ret.length) ? ret[i] : '#N/A';
  }

  static Object? _lookup(List<Object?> vals) => _xlookup(vals);

  static DateTime? _date(Object? v) {
    if (v is DateTime) return v;
    final double? n = asFormulaNumber(v);
    if (n == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (n * 86400000).round(),
      isUtc: true,
    );
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

  static double _ln(double x) {
    if (x <= 0) return double.nan;
    var y = x;
    var k = 0;
    while (y > 1.5) {
      y /= 2.718281828459045;
      k++;
    }
    while (y < 0.7) {
      y *= 2.718281828459045;
      k--;
    }
    final double z = (y - 1) / (y + 1);
    var term = z;
    var sum = 0.0;
    final double z2 = z * z;
    for (int n = 0; n < 14; n++) {
      sum += term / (2 * n + 1);
      term *= z2;
    }
    return 2 * sum + k;
  }

  static double _exp(double x) {
    var sum = 1.0;
    var term = 1.0;
    for (int n = 1; n < 24; n++) {
      term *= x / n;
      sum += term;
    }
    return sum;
  }

  static double _powNum(double a, double b) {
    if (b == 0) return 1;
    if (b == 1) return a;
    final int exp = b.round();
    if (exp.toDouble() == b && exp >= 0 && exp < 40) {
      var r = 1.0;
      for (int i = 0; i < exp; i++) {
        r *= a;
      }
      return r;
    }
    if (a <= 0) return double.nan;
    return _exp(b * _ln(a));
  }

  static Object? _let(List<FormulaNode> args, FormulaContext ctx) {
    if (args.length < 3 || args.length.isEven) {
      return '#VALUE!';
    }
    final List<String> added = <String>[];
    try {
      for (int i = 0; i < args.length - 1; i += 2) {
        final FormulaNode nameNode = args[i];
        final String name = (nameNode is NamedRangeNode
                ? nameNode.name
                : formulaString(nameNode.eval(ctx)))
            .toUpperCase();
        if (name.isEmpty) {
          return '#VALUE!';
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
      return '#VALUE!';
    }
    final List<Object?> array = flattenValues(vals[0]);
    final List<Object?> include = flattenValues(vals[1]);
    if (array.isEmpty) {
      return '#CALC!';
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
      return '#CALC!';
    }
    if (out.length == 1) {
      return out.first;
    }
    return out.map(formulaString).join(',');
  }

  static Object? _unique(List<Object?> vals) {
    if (vals.isEmpty) {
      return '#VALUE!';
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
      return '#VALUE!';
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
        cmp = formulaString(a).toLowerCase().compareTo(
          formulaString(b).toLowerCase(),
        );
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

  static Object? _textFmt(List<Object?> vals) {
    if (vals.isEmpty) {
      return '';
    }
    final String fmt = vals.length > 1 ? formulaString(vals[1]) : '0';
    final double? n = asFormulaNumber(vals[0]);
    if (n == null) {
      return formulaString(vals[0]);
    }
    final String upper = fmt.toUpperCase();
    if (fmt.contains('%')) {
      return '${(n * 100).toStringAsFixed(fmt.contains('0.00') ? 2 : 0)}%';
    }
    if (upper.contains('YYYY') || upper.contains('YYYY-MM-DD')) {
      final DateTime? d = _date(n);
      if (d == null) {
        return formulaString(vals[0]);
      }
      final String mm = d.month.toString().padLeft(2, '0');
      final String dd = d.day.toString().padLeft(2, '0');
      return '${d.year}-$mm-$dd';
    }
    if (fmt.contains('0.00') || fmt.contains('#.##')) {
      return n.toStringAsFixed(2);
    }
    if (n == n.roundToDouble()) {
      return n.toInt().toString();
    }
    return n.toString();
  }

  static Object? _indirect(FormulaContext ctx, List<Object?> vals) {
    if (vals.isEmpty) {
      return '#REF!';
    }
    final String ref = formulaString(vals[0]).trim();
    try {
      if (ref.contains(':')) {
        return RangeNode(SmlRange.parse(ref)).eval(ctx);
      }
      return CellNode(SmlCellRef.parse(ref)).eval(ctx);
    } on Object {
      return '#REF!';
    }
  }

  static Object? _offset(
    FormulaContext ctx,
    List<FormulaNode> args,
    List<Object?> vals,
  ) {
    if (args.isEmpty) {
      return '#VALUE!';
    }
    SmlCellRef? origin;
    final FormulaNode first = args[0];
    if (first is CellNode) {
      origin = first.ref;
    } else if (first is RangeNode) {
      origin = first.range.start;
    } else if (first is NamedRangeNode) {
      final SmlNamedRange? named = ctx.workbook.namedRange(first.name);
      origin = named?.range.start;
    }
    if (origin == null) {
      return '#VALUE!';
    }
    final int rows = (_n(vals, 1) ?? 0).toInt();
    final int cols = (_n(vals, 2) ?? 0).toInt();
    final int height = vals.length > 3 ? (_n(vals, 3) ?? 1).toInt() : 1;
    final int width = vals.length > 4 ? (_n(vals, 4) ?? 1).toInt() : 1;
    final SmlCellRef start = SmlCellRef(origin.col + cols, origin.row + rows);
    if (height <= 1 && width <= 1) {
      return ctx.valueOf(start);
    }
    return RangeNode(
      SmlRange(
        start,
        SmlCellRef(start.col + width - 1, start.row + height - 1),
      ),
    ).eval(ctx);
  }

  static Object? _edate(List<Object?> vals) {
    final DateTime? d = _date(vals.isEmpty ? null : vals[0]);
    if (d == null) {
      return '#VALUE!';
    }
    final int months = (_n(vals, 1) ?? 0).toInt();
    final DateTime next = DateTime.utc(d.year, d.month + months, d.day);
    return next.millisecondsSinceEpoch / 86400000;
  }

  static Object? _eomonth(List<Object?> vals) {
    final DateTime? d = _date(vals.isEmpty ? null : vals[0]);
    if (d == null) {
      return '#VALUE!';
    }
    final int months = (_n(vals, 1) ?? 0).toInt();
    final DateTime next = DateTime.utc(d.year, d.month + months + 1, 0);
    return next.millisecondsSinceEpoch / 86400000;
  }

  static Object? _networkdays(List<Object?> vals) {
    final DateTime? start = _date(vals.isEmpty ? null : vals[0]);
    final DateTime? end = _date(vals.length < 2 ? null : vals[1]);
    if (start == null || end == null) {
      return '#VALUE!';
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
      return '#N/A';
    }
    final FormulaNode first = args.first;
    if (first is CellNode) {
      final SmlWorksheet? sheet = first.sheetName == null
          ? ctx.sheet
          : ctx.workbook.sheetByName(first.sheetName!);
      final String? formula = sheet?.cell(first.ref).formula;
      if (formula == null || formula.isEmpty) {
        return '#N/A';
      }
      return formula.startsWith('=') ? formula : '=$formula';
    }
    return '#N/A';
  }

  static Object? _transpose(List<FormulaNode> args, FormulaContext ctx) {
    if (args.isEmpty) {
      return '#VALUE!';
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
      return '#NUM!';
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

  static Object? _days(List<Object?> vals) {
    final DateTime? end = _date(vals.isEmpty ? null : vals[0]);
    final DateTime? start = _date(vals.length < 2 ? null : vals[1]);
    if (end == null || start == null) {
      return '#VALUE!';
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
