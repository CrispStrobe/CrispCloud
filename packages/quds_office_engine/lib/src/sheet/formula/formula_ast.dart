import '../model/sml_analysis.dart';
import '../model/sml_workbook.dart';
import 'formula_eval.dart';
import 'formula_functions.dart';

/// Enum FormulaTokenKind.
enum FormulaTokenKind {
  number,
  string,
  boolTrue,
  boolFalse,
  name,
  cell,
  range,
  op,
  comma,
  lparen,
  rparen,
  eof,
}

/// Class FormulaToken.
class FormulaToken {
  /// FormulaToken API.
  const FormulaToken(
    this.kind,
    this.lexeme, {
    this.number,
    this.start = 0,
    this.end = 0,
  });

  /// kind API.
  final FormulaTokenKind kind;

  /// lexeme API.
  final String lexeme;

  /// number API.
  final double? number;

  /// Offsets into the original formula string, including a leading `=`.
  final int start;

  /// end API.
  final int end;
}

/// Class FormulaNode.
sealed class FormulaNode {
  /// eval API.
  Object? eval(FormulaContext ctx);
}

/// Class FormulaContext.
class FormulaContext {
  /// FormulaContext API.
  FormulaContext({
    required this.workbook,
    required this.sheet,
    required this.origin,
    this.onCircular,
  });

  /// workbook API.
  final SmlWorkbook workbook;

  /// sheet API.
  final SmlWorksheet sheet;

  /// origin API.
  final SmlCellRef origin;

  /// Function API.
  final void Function(SmlCellRef ref)? onCircular;
  final Set<String> _stack = <String>{};

  /// LET bindings (uppercase name → value).
  final Map<String, Object?> lets = <String, Object?>{};

  /// valueOf API.
  Object? valueOf(SmlCellRef ref, {SmlWorksheet? onSheet}) {
    final SmlWorksheet target = onSheet ?? sheet;
    final String key = '${target.name}!${ref.a1}';
    if (!_stack.add(key)) {
      onCircular?.call(ref);
      return '#CIRC!';
    }
    try {
      final SmlCell cell = target.cell(ref);
      if (cell.formula != null &&
          cell.formula!.isNotEmpty &&
          (cell.value == null || cell.value == cell.formula)) {
        return evaluateFormula(cell.formula!, this);
      }
      return cell.value;
    } finally {
      _stack.remove(key);
    }
  }
}

/// Class LiteralNode.
class LiteralNode extends FormulaNode {
  /// LiteralNode API.
  LiteralNode(this.value);

  /// value API.
  final Object? value;

  @override
  /// eval API.
  Object? eval(FormulaContext ctx) {
    if (value is String) {
      final String key = (value as String).toUpperCase();
      if (ctx.lets.containsKey(key)) {
        return ctx.lets[key];
      }
    }
    return value;
  }
}

/// A spilled array written into adjacent cells (SEQUENCE).
class FormulaSpill {
  /// FormulaSpill API.
  FormulaSpill(this.rows);

  /// rows API.
  final List<List<Object?>> rows;
}

/// Resolves a workbook defined name.
class NamedRangeNode extends FormulaNode {
  /// NamedRangeNode API.
  NamedRangeNode(this.name);

  /// name API.
  final String name;

  @override
  Object? eval(FormulaContext ctx) {
    final String key = name.toUpperCase();
    if (ctx.lets.containsKey(key)) {
      return ctx.lets[key];
    }
    final SmlRange? table = SmlTable.resolveRef(ctx.sheet, name);
    if (table != null) {
      if (table.isSingleCell) {
        return ctx.valueOf(table.start);
      }
      return RangeNode(table).eval(ctx);
    }
    final SmlNamedRange? found = ctx.workbook.namedRange(name);
    if (found == null) {
      return '#NAME?';
    }
    final SmlWorksheet? sheet = ctx.workbook.sheetByName(found.sheetName);
    if (sheet == null) {
      return '#REF!';
    }
    if (found.range.isSingleCell) {
      return ctx.valueOf(found.range.start, onSheet: sheet);
    }
    return RangeNode(found.range, sheetName: found.sheetName).eval(ctx);
  }
}

/// Class CellNode.
class CellNode extends FormulaNode {
  /// CellNode API.
  CellNode(this.ref, {this.sheetName});

  /// ref API.
  final SmlCellRef ref;

  /// sheetName API.
  final String? sheetName;

  @override
  /// eval API.
  Object? eval(FormulaContext ctx) {
    final SmlWorksheet? sheet = sheetName == null
        ? ctx.sheet
        : ctx.workbook.sheetByName(sheetName!);
    return ctx.valueOf(ref, onSheet: sheet);
  }
}

/// Class RangeNode.
class RangeNode extends FormulaNode {
  /// RangeNode API.
  RangeNode(this.range, {this.sheetName});

  /// range API.
  final SmlRange range;

  /// sheetName API.
  final String? sheetName;

  @override
  /// eval API.
  Object? eval(FormulaContext ctx) {
    final SmlWorksheet? sheet = sheetName == null
        ? ctx.sheet
        : ctx.workbook.sheetByName(sheetName!);
    final List<Object?> values = <Object?>[];
    for (final SmlCellRef ref in range.cells) {
      values.add(ctx.valueOf(ref, onSheet: sheet));
    }
    return values;
  }
}

/// Class BinaryNode.
class BinaryNode extends FormulaNode {
  /// BinaryNode API.
  BinaryNode(this.op, this.left, this.right);

  /// op API.
  final String op;

  /// left API.
  final FormulaNode left;

  /// right API.
  final FormulaNode right;

  @override
  /// eval API.
  Object? eval(FormulaContext ctx) {
    final Object? a = left.eval(ctx);
    final Object? b = right.eval(ctx);
    if (op == '&') {
      return '${_str(a)}${_str(b)}';
    }
    final double? na = _num(a);
    final double? nb = _num(b);
    if (na == null || nb == null) {
      if (op == '=' || op == '<>') {
        final bool eq = _str(a) == _str(b);
        return op == '=' ? eq : !eq;
      }
      return '#VALUE!';
    }
    return switch (op) {
      '+' => na + nb,
      '-' => na - nb,
      '*' => na * nb,
      '/' => nb == 0 ? '#DIV/0!' : na / nb,
      '^' => _pow(na, nb),
      '=' => na == nb,
      '<>' => na != nb,
      '<' => na < nb,
      '<=' => na <= nb,
      '>' => na > nb,
      '>=' => na >= nb,
      _ => '#VALUE!',
    };
  }
}

/// Class UnaryNode.
class UnaryNode extends FormulaNode {
  /// UnaryNode API.
  UnaryNode(this.op, this.expr);

  /// op API.
  final String op;

  /// expr API.
  final FormulaNode expr;

  @override
  /// eval API.
  Object? eval(FormulaContext ctx) {
    final double? n = _num(expr.eval(ctx));
    if (n == null) {
      return '#VALUE!';
    }
    return op == '-' ? -n : n;
  }
}

/// Class CallNode.
class CallNode extends FormulaNode {
  /// CallNode API.
  CallNode(this.name, this.args);

  /// name API.
  final String name;

  /// args API.
  final List<FormulaNode> args;

  @override
  /// eval API.
  Object? eval(FormulaContext ctx) => FormulaFunctions.call(name, args, ctx);
}

/// asFormulaNumber helper.
double? asFormulaNumber(Object? v) => _num(v);

/// flattenNumbers helper.
List<double> flattenNumbers(Object? v) {
  /// out API.
  final List<double> out = <double>[];

  /// walk API.
  void walk(Object? x) {
    if (x is List) {
      for (final Object? i in x) {
        walk(i);
      }
      return;
    }
    final double? n = _num(x);
    if (n != null) {
      out.add(n);
    }
  }

  /// walk API.
  walk(v);
  return out;
}

/// flattenValues helper.
List<Object?> flattenValues(Object? v) {
  /// out API.
  final List<Object?> out = <Object?>[];

  /// walk API.
  void walk(Object? x) {
    if (x is List) {
      for (final Object? item in x) {
        walk(item);
      }
      return;
    }
    out.add(x);
  }

  /// walk API.
  walk(v);
  return out;
}

double? _num(Object? v) {
  if (v is num) {
    return v.toDouble();
  }
  if (v is bool) {
    return v ? 1 : 0;
  }
  if (v is String) {
    return double.tryParse(v);
  }
  if (v is List) {
    for (final Object? item in v) {
      final double? n = _num(item);
      if (n != null) {
        return n;
      }
    }
  }
  return null;
}

String _str(Object? v) => v == null ? '' : v.toString();

double _pow(double a, double b) {
  /// r API.
  var r = 1.0;

  /// exp API.
  final int exp = b.round();
  if (exp.toDouble() == b && exp >= 0 && exp < 40) {
    for (int i = 0; i < exp; i++) {
      r *= a;
    }
    return r;
  }
  // exp via exp(b*ln(a)) for positive a
  if (a <= 0) {
    return double.nan;
  }
  return _exp(b * _ln(a));
}

double _ln(double x) {
  if (x <= 0) {
    return double.nan;
  }

  /// y API.
  var y = x;

  /// k API.
  var k = 0;
  while (y > 1.5) {
    y /= 2.718281828459045;
    k++;
  }
  while (y < 0.7) {
    y *= 2.718281828459045;
    k--;
  }

  /// z API.
  final double z = (y - 1) / (y + 1);

  /// z2 API.
  final double z2 = z * z;

  /// term API.
  var term = z;

  /// sum API.
  var sum = 0.0;
  for (int n = 0; n < 12; n++) {
    sum += term / (2 * n + 1);
    term *= z2;
  }
  return 2 * sum + k;
}

double _exp(double x) {
  /// sum API.
  var sum = 1.0;

  /// term API.
  var term = 1.0;
  for (int n = 1; n < 20; n++) {
    term *= x / n;
    sum += term;
  }
  return sum;
}

/// formulaString helper.
String formulaString(Object? v) => _str(v);
