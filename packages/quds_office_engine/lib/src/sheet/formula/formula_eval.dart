import '../model/sml_workbook.dart';
import 'dep_graph.dart';
import 'formula_ast.dart';

/// Tokenizes an Excel formula (leading `=` optional).
class FormulaLexer {
  /// FormulaLexer API.
  FormulaLexer(String source)
    : _src = source.startsWith('=') ? source.substring(1) : source,
      _base = source.startsWith('=') ? 1 : 0;

  final String _src;
  final int _base;
  int _i = 0;

  int get _raw => _base + _i;

  /// tokenize API.
  List<FormulaToken> tokenize() {
    final List<FormulaToken> tokens = <FormulaToken>[];
    while (!_done) {
      _skipWs();
      if (_done) {
        break;
      }
      final int ch = _src.codeUnitAt(_i);
      if (ch == 0x22) {
        tokens.add(_string());
      } else if (ch == 0x27) {
        tokens.add(_quotedSheetRef());
      } else if (_isDigit(ch) || (ch == 0x2E && _peekIsDigit())) {
        tokens.add(_number());
      } else if (_isIdentStart(ch)) {
        tokens.add(_nameOrRef());
      } else if (ch == 0x28) {
        final int start = _raw;
        _i++;
        tokens.add(
          FormulaToken(FormulaTokenKind.lparen, '(', start: start, end: _raw),
        );
      } else if (ch == 0x29) {
        final int start = _raw;
        _i++;
        tokens.add(
          FormulaToken(FormulaTokenKind.rparen, ')', start: start, end: _raw),
        );
      } else if (ch == 0x2C || ch == 0x3B) {
        final int start = _raw;
        _i++;
        tokens.add(
          FormulaToken(FormulaTokenKind.comma, ',', start: start, end: _raw),
        );
      } else {
        tokens.add(_operator());
      }
    }
    tokens.add(FormulaToken(FormulaTokenKind.eof, '', start: _raw, end: _raw));
    return tokens;
  }

  /// length API.
  bool get _done => _i >= _src.length;

  void _skipWs() {
    while (!_done && _src.codeUnitAt(_i) == 0x20) {
      _i++;
    }
  }

  bool _peekIsDigit() =>
      _i + 1 < _src.length && _isDigit(_src.codeUnitAt(_i + 1));

  FormulaToken _string() {
    final int rawStart = _raw;
    _i++;
    final int start = _i;
    while (!_done && _src.codeUnitAt(_i) != 0x22) {
      _i++;
    }
    final String value = _src.substring(start, _i);
    if (!_done) {
      _i++;
    }
    return FormulaToken(
      FormulaTokenKind.string,
      value,
      start: rawStart,
      end: _raw,
    );
  }

  FormulaToken _number() {
    final int start = _i;
    final int rawStart = _raw;
    while (!_done &&
        (_isDigit(_src.codeUnitAt(_i)) || _src.codeUnitAt(_i) == 0x2E)) {
      _i++;
    }
    if (!_done &&
        (_src.codeUnitAt(_i) == 0x65 || _src.codeUnitAt(_i) == 0x45)) {
      _i++;
      if (!_done &&
          (_src.codeUnitAt(_i) == 0x2B || _src.codeUnitAt(_i) == 0x2D)) {
        _i++;
      }
      while (!_done && _isDigit(_src.codeUnitAt(_i))) {
        _i++;
      }
    }
    final String lex = _src.substring(start, _i);
    return FormulaToken(
      FormulaTokenKind.number,
      lex,
      number: double.parse(lex),
      start: rawStart,
      end: _raw,
    );
  }

  FormulaToken _quotedSheetRef() {
    final int rawStart = _raw;
    _i++;
    final StringBuffer name = StringBuffer();
    while (!_done) {
      final int ch = _src.codeUnitAt(_i);
      if (ch == 0x27) {
        _i++;
        if (!_done && _src.codeUnitAt(_i) == 0x27) {
          name.write("'");
          _i++;
          continue;
        }
        break;
      }
      name.writeCharCode(ch);
      _i++;
    }
    if (_done || _src.codeUnitAt(_i) != 0x21) {
      return FormulaToken(
        FormulaTokenKind.name,
        name.toString(),
        start: rawStart,
        end: _raw,
      );
    }
    _i++;
    return _classifyRef(
      "'${name.toString()}'!${_readA1()}",
      start: rawStart,
      end: _raw,
    );
  }

  FormulaToken _nameOrRef() {
    final int start = _i;
    final int rawStart = _raw;
    while (!_done && _isIdentPart(_src.codeUnitAt(_i))) {
      _i++;
    }
    if (!_done && _src[_i] == '[') {
      while (!_done && _src[_i] != ']') {
        _i++;
      }
      if (!_done && _src[_i] == ']') {
        _i++;
      }
    }
    return _classifyRef(_src.substring(start, _i), start: rawStart, end: _raw);
  }

  String _readA1() {
    final int start = _i;
    while (!_done && _isA1Part(_src.codeUnitAt(_i))) {
      _i++;
    }
    return _src.substring(start, _i);
  }

  /// start API.
  FormulaToken _classifyRef(String lex, {int start = 0, int end = 0}) {
    final String upper = lex.toUpperCase();
    if (upper == 'TRUE') {
      return FormulaToken(
        FormulaTokenKind.boolTrue,
        'TRUE',
        start: start,
        end: end,
      );
    }
    if (upper == 'FALSE') {
      return FormulaToken(
        FormulaTokenKind.boolFalse,
        'FALSE',
        start: start,
        end: end,
      );
    }
    if (_rangePattern.hasMatch(lex)) {
      return FormulaToken(FormulaTokenKind.range, lex, start: start, end: end);
    }
    if (_cellPattern.hasMatch(lex)) {
      return FormulaToken(FormulaTokenKind.cell, lex, start: start, end: end);
    }
    return FormulaToken(FormulaTokenKind.name, lex, start: start, end: end);
  }

  FormulaToken _operator() {
    final int rawStart = _raw;
    if (_i + 1 < _src.length) {
      final String two = _src.substring(_i, _i + 2);
      if (two == '<=' || two == '>=' || two == '<>') {
        _i += 2;
        return FormulaToken(
          FormulaTokenKind.op,
          two,
          start: rawStart,
          end: _raw,
        );
      }
    }
    final String one = _src[_i];
    _i++;
    return FormulaToken(FormulaTokenKind.op, one, start: rawStart, end: _raw);
  }

  /// RegExp API.
  static final RegExp _cellPattern = RegExp(
    r"^((?:'[^']+'|[^!]+)!)?\$?[A-Za-z]+\$?\d+$",
  );

  /// RegExp API.
  static final RegExp _rangePattern = RegExp(
    r"^((?:'[^']+'|[^!]+)!)?\$?[A-Za-z]+\$?\d+:\$?[A-Za-z]+\$?\d+$",
  );

  /// RegExp API.
  static final RegExp _unicodeLetter = RegExp(r'\p{L}', unicode: true);

  static bool _isDigit(int ch) => ch >= 0x30 && ch <= 0x39;
  static bool _isAlpha(int ch) =>
      (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122);
  static bool _isIdentStart(int ch) =>
      _isAlpha(ch) || ch == 0x24 || ch == 0x5F || _isLetter(ch);
  static bool _isIdentPart(int ch) =>
      _isIdentStart(ch) ||
      _isDigit(ch) ||
      ch == 0x21 ||
      ch == 0x3A ||
      ch == 0x2E;
  static bool _isA1Part(int ch) =>
      _isAlpha(ch) || _isDigit(ch) || ch == 0x24 || ch == 0x3A;
  static bool _isLetter(int ch) =>
      ch > 127 && _unicodeLetter.hasMatch(String.fromCharCode(ch));
}

/// Pratt / recursive-descent parser.
class FormulaParser {
  /// FormulaParser API.
  FormulaParser(this._tokens);

  final List<FormulaToken> _tokens;
  int _i = 0;

  /// parse API.
  FormulaNode parse() => _expr(0);

  FormulaToken get _cur => _tokens[_i];

  FormulaToken _eat() => _tokens[_i++];

  FormulaNode _expr(int minBp) {
    FormulaNode left = _prefix();
    while (true) {
      final FormulaToken tok = _cur;
      if (tok.kind != FormulaTokenKind.op) {
        break;
      }
      if (tok.lexeme == '%') {
        if (60 < minBp) {
          break;
        }
        _eat();
        left = BinaryNode('/', left, LiteralNode(100));
        continue;
      }
      final int? lbp = _lbp(tok.lexeme);
      if (lbp == null || lbp < minBp) {
        break;
      }
      _eat();
      final FormulaNode right = _expr(lbp + (tok.lexeme == '^' ? 0 : 1));
      if (tok.lexeme == ':') {
        left = _rangeJoin(left, right);
      } else {
        left = BinaryNode(tok.lexeme, left, right);
      }
    }
    return left;
  }

  FormulaNode _prefix() {
    final FormulaToken tok = _eat();
    switch (tok.kind) {
      case FormulaTokenKind.number:
        return LiteralNode(tok.number);
      case FormulaTokenKind.string:
        return LiteralNode(tok.lexeme);
      case FormulaTokenKind.boolTrue:
        return LiteralNode(true);
      case FormulaTokenKind.boolFalse:
        return LiteralNode(false);
      case FormulaTokenKind.cell:
        return _cell(tok.lexeme);
      case FormulaTokenKind.range:
        return _range(tok.lexeme);
      case FormulaTokenKind.name:
        if (_cur.kind == FormulaTokenKind.lparen) {
          _eat();
          final List<FormulaNode> args = <FormulaNode>[];
          if (_cur.kind != FormulaTokenKind.rparen) {
            args.add(_expr(0));
            while (_cur.kind == FormulaTokenKind.comma) {
              _eat();
              args.add(_expr(0));
            }
          }
          if (_cur.kind == FormulaTokenKind.rparen) {
            _eat();
          }
          return CallNode(tok.lexeme.toUpperCase(), args);
        }
        return NamedRangeNode(tok.lexeme);
      case FormulaTokenKind.lparen:
        final FormulaNode inner = _expr(0);
        if (_cur.kind == FormulaTokenKind.rparen) {
          _eat();
        }
        return inner;
      case FormulaTokenKind.op:
        if (tok.lexeme == '-' || tok.lexeme == '+') {
          return UnaryNode(tok.lexeme, _expr(70));
        }
        throw FormatException('Unexpected operator ${tok.lexeme}');
      default:
        throw FormatException('Unexpected token ${tok.lexeme}');
    }
  }

  static FormulaNode _cell(String lex) {
    final int bang = lex.lastIndexOf('!');
    if (bang >= 0) {
      return CellNode(
        SmlCellRef.parse(lex.substring(bang + 1)),
        sheetName: _sheetName(lex.substring(0, bang)),
      );
    }
    return CellNode(SmlCellRef.parse(lex));
  }

  static FormulaNode _range(String lex) {
    final int bang = lex.lastIndexOf('!');
    if (bang >= 0) {
      return RangeNode(
        SmlRange.parse(lex.substring(bang + 1)),
        sheetName: _sheetName(lex.substring(0, bang)),
      );
    }
    return RangeNode(SmlRange.parse(lex));
  }

  static FormulaNode _rangeJoin(FormulaNode left, FormulaNode right) {
    if (left is CellNode && right is CellNode) {
      return RangeNode(
        SmlRange(left.ref, right.ref),
        sheetName: left.sheetName ?? right.sheetName,
      );
    }
    throw const FormatException('Invalid range');
  }

  static String _sheetName(String raw) {
    if (raw.length >= 2 && raw.startsWith("'") && raw.endsWith("'")) {
      return raw.substring(1, raw.length - 1).replaceAll("''", "'");
    }
    return raw;
  }

  static int? _lbp(String op) {
    return switch (op) {
      '=' || '<>' || '<' || '>' || '<=' || '>=' => 10,
      '&' => 20,
      '+' || '-' => 30,
      '*' || '/' => 40,
      '^' => 50,
      ':' => 60,
      _ => null,
    };
  }
}

/// parseFormula helper.
FormulaNode parseFormula(String source) =>
    FormulaParser(FormulaLexer(source).tokenize()).parse();

/// evaluateFormula helper.
Object? evaluateFormula(String source, FormulaContext ctx) {
  try {
    return parseFormula(source).eval(ctx);
  } on Object catch (e) {
    return '#ERROR! $e';
  }
}

/// Class FormulaEvaluator.
class FormulaEvaluator {
  /// evaluate API.
  static Object? evaluate(String source, FormulaContext ctx) =>
      evaluateFormula(source, ctx);

  /// evaluateCell API.
  static Object? evaluateCell(
    SmlWorkbook book,
    SmlWorksheet sheet,
    SmlCell cell,
  ) {
    if (cell.formula == null || cell.formula!.isEmpty) {
      return cell.value;
    }
    if (cell.value != null && cell.value != cell.formula) {
      return cell.value;
    }
    return evaluateFormula(
      cell.formula!,
      FormulaContext(workbook: book, sheet: sheet, origin: cell.ref),
    );
  }

  /// Writes a typed value or formula into [cell] and caches the result.
  static void applyInput(
    SmlWorkbook book,
    SmlWorksheet sheet,
    SmlCell cell,
    String text,
  ) {
    final String trimmed = text.trim();
    if (trimmed.startsWith('=')) {
      cell.formula = trimmed;
      cell.type = SmlCellType.formula;
      final Object? result = evaluateFormula(
        trimmed,
        FormulaContext(workbook: book, sheet: sheet, origin: cell.ref),
      );
      if (result is FormulaSpill) {
        _writeSpill(sheet, cell.ref, result);
        cell.value = result.rows.isEmpty || result.rows.first.isEmpty
            ? 0
            : result.rows.first.first;
      } else {
        cell.value = result;
      }
      return;
    }
    if (trimmed.isEmpty) {
      cell.formula = null;
      cell.type = SmlCellType.string;
      cell.value = null;
      return;
    }
    final double? n = double.tryParse(trimmed);
    if (n != null) {
      cell.formula = null;
      cell.type = SmlCellType.number;
      cell.value = n == n.roundToDouble() ? n.toInt() : n;
      return;
    }
    final String upper = trimmed.toUpperCase();
    if (upper == 'TRUE' || upper == 'FALSE') {
      cell.formula = null;
      cell.type = SmlCellType.boolean;
      cell.value = upper == 'TRUE';
      return;
    }
    cell.formula = null;
    cell.type = SmlCellType.string;
    cell.value = text;
  }

  /// recalculate API.
  static List<String> recalculate(SmlWorkbook book) =>
      FormulaDepGraph(book).recalculate();

  static void _writeSpill(
    SmlWorksheet sheet,
    SmlCellRef origin,
    FormulaSpill spill,
  ) {
    for (int r = 0; r < spill.rows.length; r++) {
      for (int c = 0; c < spill.rows[r].length; c++) {
        if (r == 0 && c == 0) {
          continue;
        }
        final SmlCell target = sheet.cell(
          SmlCellRef(origin.col + c, origin.row + r),
        );
        target.formula = null;
        final Object? value = spill.rows[r][c];
        if (value is num) {
          target.type = SmlCellType.number;
          target.value = value;
        } else {
          target.type = SmlCellType.string;
          target.value = value?.toString() ?? '';
        }
      }
    }
  }
}
