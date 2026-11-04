import '../model/sml_workbook.dart';
import 'formula_ast.dart';
import 'formula_eval.dart';

/// A cell or range reference inside a formula, with source offsets.
class FormulaRefSpan {
  /// FormulaRefSpan API.
  const FormulaRefSpan({
    required this.start,
    required this.end,
    required this.lexeme,
    required this.range,
    this.sheetName,
  });

  /// start API.
  final int start;

  /// end API.
  final int end;

  /// lexeme API.
  final String lexeme;

  /// range API.
  final SmlRange range;

  /// sheetName API.
  final String? sheetName;

  /// onSheet API.
  bool onSheet(String name) {
    if (sheetName == null || sheetName!.isEmpty) {
      return true;
    }
    return sheetName!.toLowerCase() == name.toLowerCase();
  }

  /// Stable key so `A1` and `$A$1` share a highlight color.
  String get colorKey {
    final int c0 = range.start.col < range.end.col
        ? range.start.col
        : range.end.col;
    final int c1 = range.start.col > range.end.col
        ? range.start.col
        : range.end.col;
    final int r0 = range.start.row < range.end.row
        ? range.start.row
        : range.end.row;
    final int r1 = range.start.row > range.end.row
        ? range.start.row
        : range.end.row;
    final String sheet = (sheetName ?? '').toLowerCase();
    return '$sheet!$c0,$r0:$c1,$r1';
  }
}

/// Moves the relative references of a formula, as Excel does when it fills a
/// formula down or across (and for `t="shared"` formulas in `.xlsx`).
abstract final class FormulaRefShift {
  static final RegExp _ref = RegExp(r'(\$?)([A-Za-z]{1,3})(\$?)(\d+)');

  /// [formula] with relative rows moved by [rows] and relative columns by
  /// [columns]. `$`-anchored parts stay put; references pushed off the sheet
  /// become `#REF!`.
  static String shift(String formula, {int rows = 0, int columns = 0}) {
    if (rows == 0 && columns == 0) {
      return formula;
    }
    final List<FormulaToken> tokens = FormulaLexer(formula).tokenize();
    final StringBuffer out = StringBuffer();
    var last = 0;
    for (var i = 0; i < tokens.length; i++) {
      final FormulaToken token = tokens[i];
      if (token.kind != FormulaTokenKind.cell &&
          token.kind != FormulaTokenKind.range) {
        continue;
      }
      // `LOG10(` lexes like a cell reference; it is a function call.
      if (i + 1 < tokens.length &&
          tokens[i + 1].kind == FormulaTokenKind.lparen) {
        continue;
      }
      if (token.start < last || token.end > formula.length) {
        continue;
      }
      final String source = formula.substring(token.start, token.end);
      final int bang = source.lastIndexOf('!');
      out
        ..write(formula.substring(last, token.start))
        ..write(source.substring(0, bang + 1))
        ..write(
          source
              .substring(bang + 1)
              .replaceAllMapped(_ref, (Match m) => _move(m, rows, columns)),
        );
      last = token.end;
    }
    out.write(formula.substring(last));
    return out.toString();
  }

  static String _move(Match m, int rows, int columns) {
    final bool fixedCol = m.group(1)!.isNotEmpty;
    final bool fixedRow = m.group(3)!.isNotEmpty;
    var col = 0;
    for (final int unit in m.group(2)!.toUpperCase().codeUnits) {
      col = col * 26 + (unit - 64);
    }
    var row = int.parse(m.group(4)!);
    if (!fixedCol) {
      col += columns;
    }
    if (!fixedRow) {
      row += rows;
    }
    if (col < 1 ||
        row < 1 ||
        col > SmlWorksheet.excelColumnCount ||
        row > SmlWorksheet.excelRowCount) {
      return '#REF!';
    }
    final StringBuffer letters = StringBuffer();
    var c = col;
    while (c > 0) {
      final int rem = (c - 1) % 26;
      letters.writeCharCode(65 + rem);
      c = (c - 1) ~/ 26;
    }
    final String name = letters.toString().split('').reversed.join();
    return '${m.group(1)}$name${m.group(3)}$row';
  }
}

/// Finds A1 / range tokens in a formula while it is being typed.
abstract final class FormulaRefScanner {
  /// scan API.
  static List<FormulaRefSpan> scan(String formula) {
    final String trimmed = formula.trimLeft();
    if (!trimmed.startsWith('=')) {
      return const <FormulaRefSpan>[];
    }
    final List<FormulaRefSpan> spans = <FormulaRefSpan>[];
    for (final FormulaToken token in FormulaLexer(formula).tokenize()) {
      if (token.kind != FormulaTokenKind.cell &&
          token.kind != FormulaTokenKind.range) {
        continue;
      }
      try {
        spans.add(
          FormulaRefSpan(
            start: token.start,
            end: token.end > token.start
                ? token.end
                : token.start + token.lexeme.length,
            lexeme: token.lexeme,
            range: _rangeOf(token.lexeme),
            sheetName: _sheetName(token.lexeme),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return spans;
  }

  static SmlRange _rangeOf(String lexeme) {
    final int bang = lexeme.lastIndexOf('!');
    return SmlRange.parse(bang >= 0 ? lexeme.substring(bang + 1) : lexeme);
  }

  static String? _sheetName(String lexeme) {
    final int bang = lexeme.lastIndexOf('!');
    if (bang < 0) {
      return null;
    }
    final String raw = lexeme.substring(0, bang);
    if (raw.length >= 2 && raw.startsWith("'") && raw.endsWith("'")) {
      return raw.substring(1, raw.length - 1).replaceAll("''", "'");
    }
    return raw;
  }
}
