/// Report expression syntax: lexer, parser, AST, and `{{ }}` interpolation.
library;

import 'report_value.dart';

/// Thrown for malformed expressions or evaluation failures.
class ReportExpressionException implements Exception {
  /// ReportExpressionException API.
  const ReportExpressionException(this.message, {this.source, this.position});

  /// message API.
  final String message;

  /// Expression text, when known.
  final String? source;

  /// Character offset into [source], when known.
  final int? position;

  @override
  String toString() {
    final StringBuffer b = StringBuffer('ReportExpressionException: $message');
    if (source != null) {
      b.write(' in "$source"');
    }
    if (position != null) {
      b.write(' at $position');
    }
    return b.toString();
  }
}

/// Unary operators.
enum ReportUnaryOp {
  /// `-x`
  negate,

  /// `+x`
  plus,

  /// `!x`, `NOT x`
  not,
}

/// Binary operators, lowest precedence last in the parser.
enum ReportBinaryOp {
  /// `a + b` (numeric add, or text concat when either side is text).
  add,

  /// `a - b`
  subtract,

  /// `a * b`
  multiply,

  /// `a / b`
  divide,

  /// `a % b`
  modulo,

  /// `a ^ b`
  power,

  /// `a & b` (always text concat).
  concat,

  /// `a == b`, `a = b`
  equal,

  /// `a != b`, `a <> b`
  notEqual,

  /// `a < b`
  less,

  /// `a <= b`
  lessOrEqual,

  /// `a > b`
  greater,

  /// `a >= b`
  greaterOrEqual,

  /// `a && b`, `a AND b`
  and,

  /// `a || b`, `a OR b`
  or,

  /// `a ?? b`
  coalesce,
}

/// Expression syntax tree.
sealed class ReportExpr {
  const ReportExpr();
}

/// Constant.
final class ReportLiteralExpr extends ReportExpr {
  /// ReportLiteralExpr API.
  const ReportLiteralExpr(this.value);

  /// value API.
  final ReportValue value;
}

/// Bare name (`item`, `System`, `total`).
final class ReportIdentifierExpr extends ReportExpr {
  /// ReportIdentifierExpr API.
  const ReportIdentifierExpr(this.name);

  /// name API.
  final String name;
}

/// `target.name`
final class ReportMemberExpr extends ReportExpr {
  /// ReportMemberExpr API.
  const ReportMemberExpr(this.target, this.name);

  /// target API.
  final ReportExpr target;

  /// name API.
  final String name;
}

/// `target[index]`
final class ReportIndexExpr extends ReportExpr {
  /// ReportIndexExpr API.
  const ReportIndexExpr(this.target, this.index);

  /// target API.
  final ReportExpr target;

  /// index API.
  final ReportExpr index;
}

/// Prefix operator.
final class ReportUnaryExpr extends ReportExpr {
  /// ReportUnaryExpr API.
  const ReportUnaryExpr(this.op, this.operand);

  /// op API.
  final ReportUnaryOp op;

  /// operand API.
  final ReportExpr operand;
}

/// Infix operator.
final class ReportBinaryExpr extends ReportExpr {
  /// ReportBinaryExpr API.
  const ReportBinaryExpr(this.op, this.left, this.right);

  /// op API.
  final ReportBinaryOp op;

  /// left API.
  final ReportExpr left;

  /// right API.
  final ReportExpr right;
}

/// `cond ? a : b`
final class ReportConditionalExpr extends ReportExpr {
  /// ReportConditionalExpr API.
  const ReportConditionalExpr(this.condition, this.whenTrue, this.whenFalse);

  /// condition API.
  final ReportExpr condition;

  /// whenTrue API.
  final ReportExpr whenTrue;

  /// whenFalse API.
  final ReportExpr whenFalse;
}

/// `NAME(args…)`
final class ReportCallExpr extends ReportExpr {
  /// ReportCallExpr API.
  const ReportCallExpr(this.name, this.arguments);

  /// Upper-cased function name.
  final String name;

  /// arguments API.
  final List<ReportExpr> arguments;
}

/// A parsed expression with its source text.
class ReportExpression {
  ReportExpression._(this.source, this.root);

  /// Parses [source]; throws [ReportExpressionException] on syntax errors.
  factory ReportExpression.parse(String source) {
    final _Parser parser = _Parser(source);
    return ReportExpression._(source, parser.parseAll());
  }

  /// source API.
  final String source;

  /// root API.
  final ReportExpr root;

  /// `a.b.c` for pure identifier/member chains, else null.
  static String? dottedPath(ReportExpr expr) {
    return switch (expr) {
      ReportIdentifierExpr(:final String name) => name,
      ReportMemberExpr(:final ReportExpr target, :final String name) => () {
        final String? head = dottedPath(target);
        return head == null ? null : '$head.$name';
      }(),
      _ => null,
    };
  }

  /// Every identifier root used by [expr] (depth-first).
  static Iterable<String> identifiers(ReportExpr expr) sync* {
    switch (expr) {
      case ReportLiteralExpr():
        break;
      case ReportIdentifierExpr(:final String name):
        yield name;
      case ReportMemberExpr(:final ReportExpr target):
        yield* identifiers(target);
      case ReportIndexExpr(:final ReportExpr target, :final ReportExpr index):
        yield* identifiers(target);
        yield* identifiers(index);
      case ReportUnaryExpr(:final ReportExpr operand):
        yield* identifiers(operand);
      case ReportBinaryExpr(:final ReportExpr left, :final ReportExpr right):
        yield* identifiers(left);
        yield* identifiers(right);
      case ReportConditionalExpr(
        :final ReportExpr condition,
        :final ReportExpr whenTrue,
        :final ReportExpr whenFalse,
      ):
        yield* identifiers(condition);
        yield* identifiers(whenTrue);
        yield* identifiers(whenFalse);
      case ReportCallExpr(:final List<ReportExpr> arguments):
        for (final ReportExpr arg in arguments) {
          yield* identifiers(arg);
        }
    }
  }

  /// Every function name called by [expr].
  static Iterable<String> functions(ReportExpr expr) sync* {
    switch (expr) {
      case ReportLiteralExpr():
      case ReportIdentifierExpr():
        break;
      case ReportMemberExpr(:final ReportExpr target):
        yield* functions(target);
      case ReportIndexExpr(:final ReportExpr target, :final ReportExpr index):
        yield* functions(target);
        yield* functions(index);
      case ReportUnaryExpr(:final ReportExpr operand):
        yield* functions(operand);
      case ReportBinaryExpr(:final ReportExpr left, :final ReportExpr right):
        yield* functions(left);
        yield* functions(right);
      case ReportConditionalExpr(
        :final ReportExpr condition,
        :final ReportExpr whenTrue,
        :final ReportExpr whenFalse,
      ):
        yield* functions(condition);
        yield* functions(whenTrue);
        yield* functions(whenFalse);
      case ReportCallExpr(
        :final String name,
        :final List<ReportExpr> arguments,
      ):
        yield name;
        for (final ReportExpr arg in arguments) {
          yield* functions(arg);
        }
    }
  }

  /// Splits a sort spec (`item.date desc, item.code`) at top-level commas.
  ///
  /// [descending] is null when the key has no `asc` / `desc` suffix.
  static List<({String source, bool? descending})> sortKeys(String spec) {
    final List<String> parts = <String>[];
    var depth = 0;
    int? quote;
    var start = 0;
    for (int i = 0; i < spec.length; i++) {
      final int c = spec.codeUnitAt(i);
      if (quote != null) {
        if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == 0x27 || c == 0x22) {
        quote = c;
      } else if (c == 0x28 || c == 0x5B) {
        depth++;
      } else if (c == 0x29 || c == 0x5D) {
        depth--;
      } else if (c == 0x2C && depth == 0) {
        parts.add(spec.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(spec.substring(start));
    final RegExp suffix = RegExp(r'\s+(asc|desc)$', caseSensitive: false);
    return <({String source, bool? descending})>[
      for (final String raw in parts)
        if (raw.trim().isNotEmpty)
          switch (suffix.firstMatch(raw.trim())) {
            null => (source: raw.trim(), descending: null),
            final RegExpMatch m => (
              source: raw.trim().substring(0, m.start).trim(),
              descending: m.group(1)!.toLowerCase() == 'desc',
            ),
          },
    ];
  }

  /// True when [expr] reads `System.PageNumber`/`TotalPages`/`PageCount`.
  static bool usesPaging(ReportExpr expr) {
    var found = false;
    void walk(ReportExpr e) {
      if (found) {
        return;
      }
      switch (e) {
        case ReportMemberExpr(:final ReportExpr target, :final String name):
          final String? head = dottedPath(target);
          if (head != null && head.toLowerCase() == 'system') {
            final String n = name.toLowerCase();
            if (n == 'pagenumber' || n == 'totalpages' || n == 'pagecount') {
              found = true;
              return;
            }
          }
          walk(target);
        case ReportIndexExpr(:final ReportExpr target, :final ReportExpr index):
          walk(target);
          walk(index);
        case ReportUnaryExpr(:final ReportExpr operand):
          walk(operand);
        case ReportBinaryExpr(:final ReportExpr left, :final ReportExpr right):
          walk(left);
          walk(right);
        case ReportConditionalExpr(
          :final ReportExpr condition,
          :final ReportExpr whenTrue,
          :final ReportExpr whenFalse,
        ):
          walk(condition);
          walk(whenTrue);
          walk(whenFalse);
        case ReportCallExpr(:final List<ReportExpr> arguments):
          arguments.forEach(walk);
        case ReportLiteralExpr():
        case ReportIdentifierExpr():
          break;
      }
    }

    walk(expr);
    return found;
  }

  @override
  String toString() => source;
}

/// One piece of an interpolated template string.
sealed class ReportTextSegment {
  const ReportTextSegment();
}

/// Literal text between expressions.
final class ReportLiteralSegment extends ReportTextSegment {
  /// ReportLiteralSegment API.
  const ReportLiteralSegment(this.text);

  /// text API.
  final String text;
}

/// `{{ expression | format }}`
final class ReportExpressionSegment extends ReportTextSegment {
  /// ReportExpressionSegment API.
  const ReportExpressionSegment(this.expression, {this.format});

  /// expression API.
  final ReportExpression expression;

  /// Optional format spec after a top-level `|`.
  final String? format;
}

/// Text with `{{ … }}` placeholders, parsed once and cached by source.
class ReportTemplateText {
  ReportTemplateText._(this.source, this.segments);

  static final Map<String, ReportTemplateText> _cache =
      <String, ReportTemplateText>{};

  /// Parses (or returns the cached parse of) [source].
  factory ReportTemplateText.parse(String source) {
    final ReportTemplateText? hit = _cache[source];
    if (hit != null) {
      return hit;
    }
    final ReportTemplateText parsed = ReportTemplateText._(
      source,
      _split(source),
    );
    if (_cache.length > 4096) {
      _cache.clear();
    }
    _cache[source] = parsed;
    return parsed;
  }

  /// source API.
  final String source;

  /// segments API.
  final List<ReportTextSegment> segments;

  /// True when there is at least one placeholder.
  bool get hasExpressions =>
      segments.any((ReportTextSegment s) => s is ReportExpressionSegment);

  /// True when any placeholder depends on page numbering.
  bool get usesPaging => segments.any(
    (ReportTextSegment s) =>
        s is ReportExpressionSegment &&
        ReportExpression.usesPaging(s.expression.root),
  );

  /// Expressions in order.
  Iterable<ReportExpression> get expressions sync* {
    for (final ReportTextSegment s in segments) {
      if (s is ReportExpressionSegment) {
        yield s.expression;
      }
    }
  }

  static List<ReportTextSegment> _split(String source) {
    final List<ReportTextSegment> out = <ReportTextSegment>[];
    final StringBuffer literal = StringBuffer();
    var i = 0;
    while (i < source.length) {
      final int open = source.indexOf('{{', i);
      if (open < 0) {
        literal.write(source.substring(i));
        break;
      }
      final int close = _findClose(source, open + 2);
      if (close < 0) {
        throw ReportExpressionException(
          'Unclosed "{{"',
          source: source,
          position: open,
        );
      }
      literal.write(source.substring(i, open));
      if (literal.isNotEmpty) {
        out.add(ReportLiteralSegment(literal.toString()));
        literal.clear();
      }
      final String inner = source.substring(open + 2, close);
      final int pipe = _topLevelPipe(inner);
      final String exprText = (pipe < 0 ? inner : inner.substring(0, pipe))
          .trim();
      final String? format = pipe < 0 ? null : inner.substring(pipe + 1).trim();
      if (exprText.isEmpty) {
        throw ReportExpressionException(
          'Empty placeholder',
          source: source,
          position: open,
        );
      }
      try {
        out.add(
          ReportExpressionSegment(
            ReportExpression.parse(exprText),
            format: format == null || format.isEmpty ? null : format,
          ),
        );
      } on ReportExpressionException catch (e) {
        throw ReportExpressionException(
          e.message,
          source: source,
          position: open + 2 + (e.position ?? 0),
        );
      }
      i = close + 2;
    }
    if (literal.isNotEmpty) {
      out.add(ReportLiteralSegment(literal.toString()));
    }
    return out;
  }

  static int _findClose(String s, int from) {
    int quote = 0;
    for (int i = from; i < s.length - 1; i++) {
      final int c = s.codeUnitAt(i);
      if (quote != 0) {
        if (c == 0x5C) {
          i++;
        } else if (c == quote) {
          quote = 0;
        }
        continue;
      }
      if (c == 0x27 || c == 0x22) {
        quote = c;
        continue;
      }
      if (c == 0x7D && s.codeUnitAt(i + 1) == 0x7D) {
        return i;
      }
    }
    return -1;
  }

  static int _topLevelPipe(String s) {
    int quote = 0;
    var depth = 0;
    for (int i = 0; i < s.length; i++) {
      final int c = s.codeUnitAt(i);
      if (quote != 0) {
        if (c == 0x5C) {
          i++;
        } else if (c == quote) {
          quote = 0;
        }
        continue;
      }
      switch (c) {
        case 0x27:
        case 0x22:
          quote = c;
        case 0x28:
        case 0x5B:
          depth++;
        case 0x29:
        case 0x5D:
          depth--;
        case 0x7C:
          final bool doubled =
              (i + 1 < s.length && s.codeUnitAt(i + 1) == 0x7C) ||
              (i > 0 && s.codeUnitAt(i - 1) == 0x7C);
          if (!doubled && depth == 0) {
            return i;
          }
      }
    }
    return -1;
  }
}

enum _Tok { number, string, ident, op, eof }

class _Token {
  const _Token(this.kind, this.text, this.pos, {this.number});

  final _Tok kind;
  final String text;
  final int pos;
  final num? number;
}

class _Lexer {
  _Lexer(this.src);

  final String src;
  int _i = 0;

  static const List<String> _ops = <String>[
    '&&',
    '||',
    '==',
    '!=',
    '<>',
    '<=',
    '>=',
    '??',
    '+',
    '-',
    '*',
    '/',
    '%',
    '^',
    '&',
    '<',
    '>',
    '=',
    '!',
    '(',
    ')',
    '[',
    ']',
    ',',
    '.',
    '?',
    ':',
  ];

  List<_Token> tokenize() {
    final List<_Token> out = <_Token>[];
    while (true) {
      _skipSpace();
      if (_i >= src.length) {
        out.add(_Token(_Tok.eof, '', _i));
        return out;
      }
      final int c = src.codeUnitAt(_i);
      final int start = _i;
      if (_isDigit(c) ||
          (c == 0x2E &&
              _i + 1 < src.length &&
              _isDigit(src.codeUnitAt(_i + 1)))) {
        out.add(_number(start));
        continue;
      }
      if (c == 0x27 || c == 0x22) {
        out.add(_string(c, start));
        continue;
      }
      if (_isIdentStart(c)) {
        while (_i < src.length && _isIdentPart(src.codeUnitAt(_i))) {
          _i++;
        }
        out.add(_Token(_Tok.ident, src.substring(start, _i), start));
        continue;
      }
      String? op;
      for (final String candidate in _ops) {
        if (src.startsWith(candidate, _i)) {
          op = candidate;
          break;
        }
      }
      if (op == null) {
        throw ReportExpressionException(
          'Unexpected character "${String.fromCharCode(c)}"',
          source: src,
          position: _i,
        );
      }
      _i += op.length;
      out.add(_Token(_Tok.op, op, start));
    }
  }

  _Token _number(int start) {
    while (_i < src.length && _isDigit(src.codeUnitAt(_i))) {
      _i++;
    }
    var isDouble = false;
    if (_i < src.length &&
        src.codeUnitAt(_i) == 0x2E &&
        _i + 1 < src.length &&
        _isDigit(src.codeUnitAt(_i + 1))) {
      isDouble = true;
      _i++;
      while (_i < src.length && _isDigit(src.codeUnitAt(_i))) {
        _i++;
      }
    }
    if (_i < src.length && (src.codeUnitAt(_i) | 0x20) == 0x65) {
      final int save = _i;
      _i++;
      if (_i < src.length &&
          (src.codeUnitAt(_i) == 0x2B || src.codeUnitAt(_i) == 0x2D)) {
        _i++;
      }
      if (_i < src.length && _isDigit(src.codeUnitAt(_i))) {
        isDouble = true;
        while (_i < src.length && _isDigit(src.codeUnitAt(_i))) {
          _i++;
        }
      } else {
        _i = save;
      }
    }
    final String text = src.substring(start, _i);
    final num value = isDouble ? double.parse(text) : int.parse(text);
    return _Token(_Tok.number, text, start, number: value);
  }

  _Token _string(int quote, int start) {
    _i++;
    final StringBuffer b = StringBuffer();
    while (_i < src.length) {
      final int c = src.codeUnitAt(_i);
      if (c == 0x5C && _i + 1 < src.length) {
        final int n = src.codeUnitAt(_i + 1);
        b.writeCharCode(switch (n) {
          0x6E => 0x0A,
          0x74 => 0x09,
          _ => n,
        });
        _i += 2;
        continue;
      }
      if (c == quote) {
        if (_i + 1 < src.length && src.codeUnitAt(_i + 1) == quote) {
          b.writeCharCode(quote);
          _i += 2;
          continue;
        }
        _i++;
        return _Token(_Tok.string, b.toString(), start);
      }
      b.writeCharCode(c);
      _i++;
    }
    throw ReportExpressionException(
      'Unterminated string',
      source: src,
      position: start,
    );
  }

  void _skipSpace() {
    while (_i < src.length) {
      final int c = src.codeUnitAt(_i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0xA0) {
        _i++;
      } else {
        break;
      }
    }
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24 ||
      c == 0x40 ||
      (c >= 0x80 && c != 0xA0);

  static bool _isIdentPart(int c) => _isIdentStart(c) || _isDigit(c);
}

class _Parser {
  _Parser(this.src) : _tokens = _Lexer(src).tokenize();

  final String src;
  final List<_Token> _tokens;
  int _p = 0;

  _Token get _peek => _tokens[_p];

  ReportExpr parseAll() {
    final ReportExpr e = _ternary();
    if (_peek.kind != _Tok.eof) {
      throw ReportExpressionException(
        'Unexpected "${_peek.text}"',
        source: src,
        position: _peek.pos,
      );
    }
    return e;
  }

  bool _isOp(String op) => _peek.kind == _Tok.op && _peek.text == op;

  bool _isWord(String word) =>
      _peek.kind == _Tok.ident && _peek.text.toLowerCase() == word;

  bool _accept(String op) {
    if (_isOp(op)) {
      _p++;
      return true;
    }
    return false;
  }

  void _expect(String op) {
    if (!_accept(op)) {
      throw ReportExpressionException(
        'Expected "$op" but found "${_peek.kind == _Tok.eof ? 'end' : _peek.text}"',
        source: src,
        position: _peek.pos,
      );
    }
  }

  ReportExpr _ternary() {
    final ReportExpr cond = _coalesce();
    if (_accept('?')) {
      final ReportExpr a = _ternary();
      _expect(':');
      final ReportExpr b = _ternary();
      return ReportConditionalExpr(cond, a, b);
    }
    return cond;
  }

  ReportExpr _coalesce() {
    ReportExpr left = _or();
    while (_accept('??')) {
      left = ReportBinaryExpr(ReportBinaryOp.coalesce, left, _or());
    }
    return left;
  }

  ReportExpr _or() {
    ReportExpr left = _and();
    while (true) {
      if (_accept('||')) {
      } else if (_isWord('or')) {
        _p++;
      } else {
        return left;
      }
      left = ReportBinaryExpr(ReportBinaryOp.or, left, _and());
    }
  }

  ReportExpr _and() {
    ReportExpr left = _equality();
    while (true) {
      if (_accept('&&')) {
      } else if (_isWord('and')) {
        _p++;
      } else {
        return left;
      }
      left = ReportBinaryExpr(ReportBinaryOp.and, left, _equality());
    }
  }

  ReportExpr _equality() {
    ReportExpr left = _comparison();
    while (true) {
      final ReportBinaryOp? op = switch (_peek.kind == _Tok.op
          ? _peek.text
          : '') {
        '==' || '=' => ReportBinaryOp.equal,
        '!=' || '<>' => ReportBinaryOp.notEqual,
        _ => null,
      };
      if (op == null) {
        return left;
      }
      _p++;
      left = ReportBinaryExpr(op, left, _comparison());
    }
  }

  ReportExpr _comparison() {
    ReportExpr left = _additive();
    while (true) {
      final ReportBinaryOp? op = switch (_peek.kind == _Tok.op
          ? _peek.text
          : '') {
        '<' => ReportBinaryOp.less,
        '<=' => ReportBinaryOp.lessOrEqual,
        '>' => ReportBinaryOp.greater,
        '>=' => ReportBinaryOp.greaterOrEqual,
        _ => null,
      };
      if (op == null) {
        return left;
      }
      _p++;
      left = ReportBinaryExpr(op, left, _additive());
    }
  }

  ReportExpr _additive() {
    ReportExpr left = _multiplicative();
    while (true) {
      final ReportBinaryOp? op = switch (_peek.kind == _Tok.op
          ? _peek.text
          : '') {
        '+' => ReportBinaryOp.add,
        '-' => ReportBinaryOp.subtract,
        '&' => ReportBinaryOp.concat,
        _ => null,
      };
      if (op == null) {
        return left;
      }
      _p++;
      left = ReportBinaryExpr(op, left, _multiplicative());
    }
  }

  ReportExpr _multiplicative() {
    ReportExpr left = _unary();
    while (true) {
      final ReportBinaryOp? op = switch (_peek.kind == _Tok.op
          ? _peek.text
          : '') {
        '*' => ReportBinaryOp.multiply,
        '/' => ReportBinaryOp.divide,
        '%' => ReportBinaryOp.modulo,
        _ => null,
      };
      if (op == null) {
        return left;
      }
      _p++;
      left = ReportBinaryExpr(op, left, _unary());
    }
  }

  ReportExpr _unary() {
    if (_accept('-')) {
      return ReportUnaryExpr(ReportUnaryOp.negate, _unary());
    }
    if (_accept('+')) {
      return ReportUnaryExpr(ReportUnaryOp.plus, _unary());
    }
    if (_accept('!')) {
      return ReportUnaryExpr(ReportUnaryOp.not, _unary());
    }
    if (_isWord('not')) {
      _p++;
      return ReportUnaryExpr(ReportUnaryOp.not, _unary());
    }
    return _power();
  }

  ReportExpr _power() {
    final ReportExpr base = _postfix();
    if (_accept('^')) {
      return ReportBinaryExpr(ReportBinaryOp.power, base, _unary());
    }
    return base;
  }

  ReportExpr _postfix() {
    ReportExpr e = _primary();
    while (true) {
      if (_accept('.')) {
        final _Token name = _peek;
        if (name.kind != _Tok.ident && name.kind != _Tok.number) {
          throw ReportExpressionException(
            'Expected a member name after "."',
            source: src,
            position: name.pos,
          );
        }
        _p++;
        e = ReportMemberExpr(e, name.text);
        continue;
      }
      if (_accept('[')) {
        final ReportExpr index = _ternary();
        _expect(']');
        e = ReportIndexExpr(e, index);
        continue;
      }
      return e;
    }
  }

  ReportExpr _primary() {
    final _Token t = _peek;
    switch (t.kind) {
      case _Tok.number:
        _p++;
        return ReportLiteralExpr(ReportNumber(t.number!));
      case _Tok.string:
        _p++;
        return ReportLiteralExpr(ReportText(t.text));
      case _Tok.ident:
        _p++;
        final String lower = t.text.toLowerCase();
        if (_isOp('(')) {
          _p++;
          final List<ReportExpr> args = <ReportExpr>[];
          if (!_isOp(')')) {
            do {
              args.add(_ternary());
            } while (_accept(','));
          }
          _expect(')');
          return ReportCallExpr(t.text.toUpperCase(), args);
        }
        if (lower == 'true') {
          return const ReportLiteralExpr(ReportBool(true));
        }
        if (lower == 'false') {
          return const ReportLiteralExpr(ReportBool(false));
        }
        if (lower == 'null') {
          return ReportLiteralExpr(ReportNull.instance);
        }
        return ReportIdentifierExpr(t.text);
      case _Tok.op:
        if (t.text == '(') {
          _p++;
          final ReportExpr inner = _ternary();
          _expect(')');
          return inner;
        }
        throw ReportExpressionException(
          'Unexpected "${t.text}"',
          source: src,
          position: t.pos,
        );
      case _Tok.eof:
        throw ReportExpressionException(
          'Unexpected end of expression',
          source: src,
          position: t.pos,
        );
    }
  }
}
