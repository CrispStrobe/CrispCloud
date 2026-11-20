import 'dart:convert';

import 'office_macro_language.dart';
import 'office_macro_model.dart';
import 'office_operations.dart';

/// A source diagnostic from an explicitly invoked bounded VBA compiler.
/// Line and column are one-based UTF-16 positions in the supplied source.
class OfficeVbaCompileException extends OfficeMacroException {
  const OfficeVbaCompileException(
    super.code,
    super.message, {
    required this.moduleName,
    required this.entryPoint,
    required this.line,
    required this.column,
  });

  final String moduleName;
  final String entryPoint;
  final int line;
  final int column;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...super.toJson(),
    'moduleName': moduleName,
    'entryPoint': entryPoint,
    'line': line,
    'column': column,
  };
}

/// Compiles a finite, document-independent Excel VBA subset to native calls.
///
/// This is not a general VBA interpreter. All source is parsed and checked,
/// including unused procedures and branches. The selected parameterless Sub
/// and its bounded, nonrecursive helpers are evaluated. Expressions cannot
/// read the document or invoke external
/// code; explicitly qualified writes retain the ordinary runtime policy and
/// transaction boundary. Compilation has separate syntax, work, string, range,
/// operation, and encoded-output limits, including for loops emitting no calls.
class OfficeVbaMacroLanguage implements OfficeMacroLanguage {
  const OfficeVbaMacroLanguage();

  @override
  String get id => 'vba-excel';

  @override
  OfficeMacro compile(OfficeMacroSource source) {
    final context = _Context(source);
    if (source.format != OfficeMacroFormat.xlsx) {
      context.fail(
        const _Token(_TokenKind.end, '', 1, 1),
        'vba_unsupported',
        'vba-excel only targets spreadsheet documents.',
      );
    }
    return _compileVba(context);
  }
}

/// Compiles explicit paragraph writes from the bounded Word VBA dialect.
///
/// The language and resource limits are shared with [OfficeVbaMacroLanguage].
/// Word bindings select main-story paragraphs without reading document content.
/// Native plans retain the ordinary runtime policy and atomic save boundary.
class OfficeVbaWordMacroLanguage implements OfficeMacroLanguage {
  const OfficeVbaWordMacroLanguage();

  @override
  String get id => 'vba-word';

  @override
  OfficeMacro compile(OfficeMacroSource source) {
    final context = _Context(source, isWord: true);
    if (source.format != OfficeMacroFormat.docx) {
      context.fail(
        const _Token(_TokenKind.end, '', 1, 1),
        'vba_unsupported',
        'vba-word only targets word-processing documents.',
      );
    }
    return _compileVba(context);
  }
}

/// Compiles explicit slide and shape writes from the bounded PowerPoint dialect.
///
/// `ActivePresentation` in source denotes the presentation supplied to the
/// native session, never an ambient application or an embedded VBA project.
/// The language, diagnostics and aggregate limits are shared with Excel/Word.
class OfficeVbaPowerPointMacroLanguage implements OfficeMacroLanguage {
  const OfficeVbaPowerPointMacroLanguage();

  @override
  String get id => 'vba-powerpoint';

  @override
  OfficeMacro compile(OfficeMacroSource source) {
    final context = _Context(source, isPowerPoint: true);
    if (source.format != OfficeMacroFormat.pptx) {
      context.fail(
        const _Token(_TokenKind.end, '', 1, 1),
        'vba_unsupported',
        'vba-powerpoint only targets presentation documents.',
      );
    }
    return _compileVba(context);
  }
}

OfficeMacro _compileVba(_Context context) {
  final module = _Parser(context, _Lexer(context).scan()).parse();
  final checked = _Checker(context, module)..check();
  return _Evaluator(context, module, checked).compile();
}

const _maxTokens = 50000;
const _maxDepth = 64;
const _maxBlocks = 32;
const _maxStatements = 10000;
const _maxWork = 100000;
const _maxVariables = 256;
const _maxString = 32767;
const _maxSteps = 10000;
const _maxArguments = 16;
const _maxCalls = 32;
const _maxArrayElements = 4096;
const _maxActiveArrayElements = 16384;
const _maxActiveArrayStringUnits = 1048576;
const _maxExactInteger = 9007199254740991;
const _comparisonOperators = <String>{'=', '<>', '<', '>', '<=', '>='};
const _stringIntrinsics = <String>{'len', r'left$', r'right$', r'mid$'};
const _variantIntrinsics = <String>{
  'isempty',
  'isnull',
  'cbool',
  'cdbl',
  'clng',
  'cstr',
  'cvar',
};
const _wordConstants = <String, int>{
  'wdalignparagraphleft': 0,
  'wdalignparagraphcenter': 1,
  'wdalignparagraphright': 2,
  'wdalignparagraphjustify': 3,
  'wdunderlinenone': 0,
  'wdunderlinesingle': 1,
  'wdunderlinewords': 2,
  'wdunderlinedouble': 3,
  'wdunderlinedotted': 4,
  'wdunderlinethick': 6,
  'wdunderlinedash': 7,
  'wdunderlinedotdash': 9,
  'wdunderlinedotdotdash': 10,
  'wdunderlinewavy': 11,
  'wdunderlinedottedheavy': 20,
  'wdunderlinedashheavy': 23,
  'wdunderlinedotdashheavy': 25,
  'wdunderlinedotdotdashheavy': 26,
  'wdunderlinewavyheavy': 27,
  'wdunderlinedashlong': 39,
  'wdunderlinewavydouble': 43,
  'wdunderlinedashlongheavy': 55,
};
const _wordUnderlines = <int, String>{
  0: 'none',
  1: 'single',
  2: 'words',
  3: 'double',
  4: 'dotted',
  6: 'thick',
  7: 'dash',
  9: 'dotDash',
  10: 'dotDotDash',
  11: 'wave',
  20: 'dottedHeavy',
  23: 'dashedHeavy',
  25: 'dashDotHeavy',
  26: 'dashDotDotHeavy',
  27: 'wavyHeavy',
  39: 'dashLong',
  43: 'wavyDouble',
  55: 'dashLongHeavy',
};
const _wordReserved = <String>{
  'thisdocument',
  'activedocument',
  'document',
  'paragraph',
  'paragraphs',
  'wdalignparagraphleft',
  'wdalignparagraphcenter',
  'wdalignparagraphright',
  'wdalignparagraphjustify',
};
const _powerPointConstants = <String, int>{
  'msofalse': 0,
  'msotrue': -1,
  'msoctrue': 1,
  'msotristatemixed': -2,
  'msotristatetoggle': -3,
  'ppalignleft': 1,
  'ppaligncenter': 2,
  'ppalignright': 3,
  'ppalignjustify': 4,
  'ppaligndistribute': 5,
  'ppalignthaidistribute': 6,
  'ppalignjustifylow': 7,
  'ppalignmentmixed': -2,
};
const _powerPointReserved = <String>{
  'application',
  'activepresentation',
  'presentation',
  'slides',
  'slide',
  'shapes',
  'shape',
  'textframe',
  'textrange',
};

class _Context {
  const _Context(this.source, {this.isWord = false, this.isPowerPoint = false});
  final OfficeMacroSource source;
  final bool isWord;
  final bool isPowerPoint;
  bool get isExcel => !isWord && !isPowerPoint;

  OfficeMacroFormat get format => isWord
      ? OfficeMacroFormat.docx
      : isPowerPoint
      ? OfficeMacroFormat.pptx
      : OfficeMacroFormat.xlsx;

  Map<String, int> get constants => isWord
      ? _wordConstants
      : isPowerPoint
      ? _powerPointConstants
      : const <String, int>{};

  bool reserved(String name) =>
      _Checker._reserved.contains(name) ||
      constants.containsKey(name) ||
      (isWord && _wordReserved.contains(name)) ||
      (isPowerPoint && _powerPointReserved.contains(name));

  Never fail(
    _Token token,
    String code,
    String message,
  ) => throw OfficeVbaCompileException(
    code,
    '${source.moduleName}.${source.entryPoint}:${token.line}:${token.column}: $message',
    moduleName: source.moduleName,
    entryPoint: source.entryPoint,
    line: token.line,
    column: token.column,
  );

  Never unsupported(_Token token, String message) =>
      fail(token, 'vba_unsupported', message);

  Never limit(_Token token, String message) =>
      fail(token, 'vba_limit_exceeded', message);

  Never type(_Token token, String message) =>
      fail(token, 'vba_type_error', message);
}

enum _TokenKind { identifier, number, string, symbol, separator, end }

class _Token {
  const _Token(this.kind, this.text, this.line, this.column);
  final _TokenKind kind;
  final String text;
  final int line;
  final int column;
  String get lower => text.toLowerCase();
}

bool _letter(int code) =>
    (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
bool _digit(int code) => code >= 48 && code <= 57;
bool _horizontal(int code) => code == 32 || code == 9;

class _Lexer {
  _Lexer(this.context) : source = context.source.source;
  final _Context context;
  final String source;
  final List<_Token> tokens = <_Token>[];
  int offset = 0;
  int line = 1;
  int column = 1;
  bool statementStart = true;

  List<_Token> scan() {
    if (source.startsWith('\uFEFF')) offset++;
    while (offset < source.length) {
      final code = source.codeUnitAt(offset);
      if (_horizontal(code)) {
        _advance();
        continue;
      }
      if (code == 13 || code == 10) {
        final token = _Token(_TokenKind.separator, '\n', line, column);
        _newline();
        _add(token);
        statementStart = true;
        continue;
      }
      if (code == 39) {
        _comment();
        continue;
      }
      final start = offset;
      final startLine = line;
      final startColumn = column;
      _Token token(_TokenKind kind, String text) =>
          _Token(kind, text, startLine, startColumn);
      if (code == 95) {
        // VBA continuation is a space followed by underscore and a newline.
        if (offset == 0 ||
            !_horizontal(source.codeUnitAt(offset - 1)) ||
            statementStart) {
          context.fail(
            token(_TokenKind.symbol, '_'),
            'vba_syntax_error',
            'A continuation needs a preceding statement and whitespace.',
          );
        }
        _advance();
        while (offset < source.length &&
            _horizontal(source.codeUnitAt(offset))) {
          _advance();
        }
        if (offset == source.length ||
            (source.codeUnitAt(offset) != 13 &&
                source.codeUnitAt(offset) != 10)) {
          context.fail(
            token(_TokenKind.symbol, '_'),
            'vba_syntax_error',
            'A continuation must end at a newline.',
          );
        }
        _newline();
        if (offset == source.length) {
          context.fail(
            token(_TokenKind.symbol, '_'),
            'vba_syntax_error',
            'A continuation needs another source line.',
          );
        }
        continue;
      }
      if (code == 34) {
        _advance();
        final buffer = StringBuffer();
        var length = 0;
        var closed = false;
        while (offset < source.length) {
          final next = source.codeUnitAt(offset);
          if (next == 13 || next == 10) break;
          _advance();
          if (next == 34) {
            if (offset < source.length && source.codeUnitAt(offset) == 34) {
              _advance();
            } else {
              closed = true;
              break;
            }
          }
          if (++length > _maxString) {
            context.limit(
              token(_TokenKind.string, ''),
              'String literals exceed $_maxString code units.',
            );
          }
          buffer.writeCharCode(next);
        }
        if (!closed) {
          context.fail(
            token(_TokenKind.string, ''),
            'vba_syntax_error',
            'Unterminated string literal.',
          );
        }
        _add(token(_TokenKind.string, buffer.toString()));
        statementStart = false;
        continue;
      }
      if (_letter(code)) {
        _advance();
        while (offset < source.length) {
          final next = source.codeUnitAt(offset);
          if (!_letter(next) && !_digit(next) && next != 95) break;
          _advance();
        }
        var text = source.substring(start, offset);
        // Only the implemented String-returning intrinsics may carry a type
        // suffix. This does not admit suffixed variable or procedure names.
        if (offset < source.length &&
            source.codeUnitAt(offset) == 36 &&
            _stringIntrinsics.contains('${text.toLowerCase()}\$')) {
          _advance();
          text = source.substring(start, offset);
        }
        if (text.length > 128) {
          context.limit(
            token(_TokenKind.identifier, text),
            'Identifiers exceed 128 code units.',
          );
        }
        if (statementStart && text.toLowerCase() == 'rem') {
          _comment();
          continue;
        }
        _add(token(_TokenKind.identifier, text));
        statementStart = false;
        continue;
      }
      if (_digit(code) ||
          (code == 46 &&
              offset + 1 < source.length &&
              _digit(source.codeUnitAt(offset + 1)))) {
        while (offset < source.length && _digit(source.codeUnitAt(offset))) {
          _advance();
        }
        if (offset < source.length && source.codeUnitAt(offset) == 46) {
          _advance();
          while (offset < source.length && _digit(source.codeUnitAt(offset))) {
            _advance();
          }
        }
        if (offset < source.length &&
            (source.codeUnitAt(offset) == 69 ||
                source.codeUnitAt(offset) == 101)) {
          _advance();
          if (offset < source.length &&
              (source.codeUnitAt(offset) == 43 ||
                  source.codeUnitAt(offset) == 45)) {
            _advance();
          }
          final exponent = offset;
          while (offset < source.length && _digit(source.codeUnitAt(offset))) {
            _advance();
          }
          if (offset == exponent) {
            context.fail(
              token(_TokenKind.number, ''),
              'vba_syntax_error',
              'An exponent needs digits.',
            );
          }
        }
        _add(token(_TokenKind.number, source.substring(start, offset)));
        statementStart = false;
        continue;
      }
      if ('().,+-*/&=<>:'.contains(String.fromCharCode(code))) {
        _advance();
        if ((code == 60 || code == 62) && offset < source.length) {
          final next = source.codeUnitAt(offset);
          if (next == 61 || (code == 60 && next == 62)) _advance();
        }
        final text = source.substring(start, offset);
        _add(
          token(code == 58 ? _TokenKind.separator : _TokenKind.symbol, text),
        );
        statementStart = code == 58;
        continue;
      }
      context.unsupported(
        token(_TokenKind.symbol, String.fromCharCode(code)),
        'Unsupported character; variable type suffixes, dates, and directives are not supported.',
      );
    }
    _add(_Token(_TokenKind.end, '', line, column));
    return tokens;
  }

  void _advance() {
    offset++;
    column++;
  }

  void _newline() {
    if (source.codeUnitAt(offset++) == 13 &&
        offset < source.length &&
        source.codeUnitAt(offset) == 10) {
      offset++;
    }
    line++;
    column = 1;
  }

  void _comment() {
    while (offset < source.length &&
        source.codeUnitAt(offset) != 13 &&
        source.codeUnitAt(offset) != 10) {
      _advance();
    }
  }

  void _add(_Token token) {
    if (tokens.length >= _maxTokens) {
      context.limit(token, 'Source exceeds $_maxTokens tokens.');
    }
    tokens.add(token);
  }
}

enum _Kind {
  number,
  string,
  boolean,
  variant,
  worksheet,
  range,
  workbook,
  font,
  interior,
  document,
  paragraph,
  paragraphFormat,
  powerPointApplication,
  presentation,
  slides,
  slide,
  shapes,
  shape,
  textFrame,
  textRange,
  powerPointFont,
  powerPointColor,
  powerPointParagraphFormat,
  triState,
}

enum _Declared {
  long,
  doubleType,
  string,
  boolean,
  variant,
  worksheet,
  range,
  document,
  paragraph,
  presentation,
  slide,
  shape,
  textRange,
}

bool _objectType(_Declared type) =>
    type == _Declared.worksheet ||
    type == _Declared.range ||
    type == _Declared.document ||
    type == _Declared.paragraph ||
    type == _Declared.presentation ||
    type == _Declared.slide ||
    type == _Declared.shape ||
    type == _Declared.textRange;

const _powerPointObjectKinds = <_Kind>{
  _Kind.powerPointApplication,
  _Kind.presentation,
  _Kind.slides,
  _Kind.slide,
  _Kind.shapes,
  _Kind.shape,
  _Kind.textFrame,
  _Kind.textRange,
  _Kind.powerPointFont,
  _Kind.powerPointColor,
  _Kind.powerPointParagraphFormat,
};

// These are source values, never native JSON null or unbound object bindings.
enum _VariantState { empty, nullValue }

_Kind _kindOf(_Declared type) => switch (type) {
  _Declared.long || _Declared.doubleType => _Kind.number,
  _Declared.string => _Kind.string,
  _Declared.boolean => _Kind.boolean,
  _Declared.variant => _Kind.variant,
  _Declared.worksheet => _Kind.worksheet,
  _Declared.range => _Kind.range,
  _Declared.document => _Kind.document,
  _Declared.paragraph => _Kind.paragraph,
  _Declared.presentation => _Kind.presentation,
  _Declared.slide => _Kind.slide,
  _Declared.shape => _Kind.shape,
  _Declared.textRange => _Kind.textRange,
};

sealed class _Expr {
  const _Expr(this.token, this.depth);
  final _Token token;
  final int depth;
}

class _Literal extends _Expr {
  const _Literal(_Token token, this.value) : super(token, 1);
  final Object value;
}

class _Name extends _Expr {
  const _Name(_Token token) : super(token, 1);
}

class _WithValue extends _Expr {
  const _WithValue(_Token token) : super(token, 1);
}

class _Call extends _Expr {
  _Call(_Token token, this.arguments)
    : super(
        token,
        1 + arguments.fold<int>(0, (a, b) => a > b.depth ? a : b.depth),
      );
  final List<_Expr> arguments;
}

class _Member extends _Expr {
  _Member(_Token token, this.receiver, this.arguments)
    : super(
        token,
        1 +
            (arguments ?? const <_Expr>[]).fold<int>(
              receiver.depth,
              (a, b) => a > b.depth ? a : b.depth,
            ),
      );
  final _Expr receiver;
  final List<_Expr>? arguments;
}

class _Unary extends _Expr {
  _Unary(_Token token, this.operand) : super(token, operand.depth + 1);
  final _Expr operand;
}

class _Binary extends _Expr {
  _Binary(_Token token, this.left, this.right)
    : super(token, 1 + (left.depth > right.depth ? left.depth : right.depth));
  final _Expr left;
  final _Expr right;
}

sealed class _Statement {
  const _Statement(this.token);
  final _Token token;
}

class _Declaration extends _Statement {
  const _Declaration(
    super.token,
    this.type,
    this.isConst,
    this.initializer, {
    this.bounds,
    this.isDynamicArray = false,
  });
  final _Declared type;
  final bool isConst;
  final _Expr? initializer;
  final (_Expr, _Expr)? bounds;
  final bool isDynamicArray;
  bool get isArray => bounds != null || isDynamicArray;
}

class _ResizeTarget {
  const _ResizeTarget(this.name, this.bounds, this.type);
  final _Token name;
  final (_Expr, _Expr) bounds;
  final _Declared? type;
}

class _Resize extends _Statement {
  const _Resize(super.token, this.targets, this.preserve);
  final List<_ResizeTarget> targets;
  final bool preserve;
}

class _Erase extends _Statement {
  const _Erase(super.token, this.targets);
  final List<_Token> targets;
}

class _Assignment extends _Statement {
  const _Assignment(super.token, this.target, this.value, this.isSet);
  final _Expr target;
  final _Expr value;
  final bool isSet;
}

class _Clear extends _Statement {
  const _Clear(super.token, this.target);
  final _Member target;
}

class _InsertBefore extends _Statement {
  const _InsertBefore(super.token, this.target);
  final _Member target;
}

class _For extends _Statement {
  const _For(
    super.token,
    this.counter,
    this.start,
    this.end,
    this.step,
    this.body,
  );
  final _Token counter;
  final _Expr start;
  final _Expr end;
  final _Expr step;
  final List<_Statement> body;
}

class _ForEach extends _Statement {
  const _ForEach(super.token, this.counter, this.collection, this.body);
  final _Token counter;
  final _Expr collection;
  final List<_Statement> body;
}

class _ConditionalLoop extends _Statement {
  const _ConditionalLoop(
    super.token,
    this.body, {
    required this.isDo,
    this.condition,
    this.until = false,
    this.testAfter = false,
  });
  final List<_Statement> body;
  final bool isDo;
  final _Expr? condition;
  final bool until;
  final bool testAfter;
}

class _CaseMatch {
  const _CaseMatch(this.token, this.first, {this.last, this.operator = '='});
  final _Token token;
  final _Expr first;
  final _Expr? last;
  final String operator;
}

class _CaseBranch {
  const _CaseBranch(this.matches, this.body);
  final List<_CaseMatch> matches;
  final List<_Statement> body;
}

class _Select extends _Statement {
  const _Select(super.token, this.selector, this.branches, this.otherwise);
  final _Expr selector;
  final List<_CaseBranch> branches;
  final List<_Statement> otherwise;
}

class _With extends _Statement {
  const _With(super.token, this.target, this.body);
  final _Expr target;
  final List<_Statement> body;
}

class _If extends _Statement {
  const _If(super.token, this.branches, this.otherwise);
  final List<(_Expr, List<_Statement>)> branches;
  final List<_Statement> otherwise;
}

class _Invoke extends _Statement {
  const _Invoke(super.token, this.arguments);
  final List<_Expr> arguments;
}

enum _ExitKind { sub, function, forLoop, doLoop }

class _Exit extends _Statement {
  const _Exit(super.token, this.kind);
  final _ExitKind kind;
}

class _Parameter {
  const _Parameter(this.name, this.type);
  final _Token name;
  final _Declared type;
}

class _Procedure {
  const _Procedure(this.name, this.parameters, this.returnType, this.body);
  final _Token name;
  final List<_Parameter> parameters;
  final _Declared? returnType;
  final List<_Statement> body;
}

class _Module {
  const _Module(this.explicit, this.constants, this.procedures);
  final bool explicit;
  final List<_Declaration> constants;
  final Map<String, _Procedure> procedures;
}

class _Parser {
  _Parser(this.context, this.tokens);
  final _Context context;
  final List<_Token> tokens;
  int arrayBase = 0;
  int position = 0;
  int expressionDepth = 0;
  int statementCount = 0;
  final Set<String> arrayNames = <String>{};
  _Token get current => tokens[position];
  bool _is(String text) =>
      (current.kind == _TokenKind.identifier ||
          current.kind == _TokenKind.symbol) &&
      current.lower == text;
  bool _atEnd(String second) =>
      _is('end') && tokens[position + 1].lower == second;
  bool get _isComparison =>
      current.kind == _TokenKind.symbol &&
      _comparisonOperators.contains(current.text);

  _Module parse() {
    var explicit = false;
    var baseSpecified = false;
    var attribute = false;
    final constants = <_Declaration>[];
    final procedures = <String, _Procedure>{};
    _separators();
    while (current.kind != _TokenKind.end) {
      if (_take('option')) {
        if (procedures.isNotEmpty) {
          _syntax('Option statements must precede procedures.');
        }
        if (_take('explicit')) {
          if (explicit) _syntax('Option Explicit may occur only once.');
          explicit = true;
        } else if (_take('base')) {
          if (baseSpecified) _syntax('Option Base may occur only once.');
          if (current.kind != _TokenKind.number ||
              (current.text != '0' && current.text != '1')) {
            _syntax('Option Base requires the literal 0 or 1.');
          }
          arrayBase = current.text == '1' ? 1 : 0;
          baseSpecified = true;
          position++;
        } else {
          context.unsupported(
            current,
            'Only Option Explicit and Option Base are supported.',
          );
        }
        _endStatement();
      } else if (_take('attribute')) {
        if (procedures.isNotEmpty || attribute) {
          _syntax('Only one initial Attribute VB_Name is supported.');
        }
        _expect('vb_name');
        _expect('=');
        if (current.kind != _TokenKind.string) {
          _syntax('VB_Name needs a string literal.');
        }
        position++;
        attribute = true;
        _endStatement();
      } else if (_is('const')) {
        if (procedures.isNotEmpty) {
          _syntax('Module constants must precede procedures.');
        }
        constants.addAll(_declarations(true));
      } else {
        _take('public') || _take('private');
        final isFunction = _take('function');
        if (!isFunction && !_take('sub')) {
          context.unsupported(
            current,
            'Only Sub/Function procedures and module constants are supported.',
          );
        }
        final name = _identifier();
        if (context.reserved(name.lower)) {
          context.fail(
            name,
            'vba_name_error',
            'Reserved procedure name ${name.text}.',
          );
        }
        final parameters = _parameters();
        final returnType = isFunction ? _declaredType() : null;
        if (returnType != null && _objectType(returnType)) {
          context.unsupported(name, 'Functions may return scalar values only.');
        }
        _endStatement();
        final ending = isFunction ? 'function' : 'sub';
        arrayNames.clear();
        final body = _body(0, () => _atEnd(ending));
        _expect('end');
        _expect(ending);
        _endStatement();
        if (procedures.containsKey(name.lower)) {
          _syntax('Duplicate procedure ${name.text}.', name);
        }
        procedures[name.lower] = _Procedure(name, parameters, returnType, body);
      }
      _separators();
    }
    final entry = procedures[context.source.entryPoint.toLowerCase()];
    if (entry == null ||
        entry.returnType != null ||
        entry.parameters.isNotEmpty) {
      context.fail(
        entry?.name ?? current,
        'vba_entry_point',
        'No parameterless Sub named ${context.source.entryPoint}.',
      );
    }
    return _Module(explicit, constants, procedures);
  }

  List<_Parameter> _parameters() {
    if (!_take('(')) return const <_Parameter>[];
    final result = <_Parameter>[];
    if (!_is(')')) {
      do {
        if (result.length >= _maxArguments) {
          context.limit(
            current,
            'Procedures accept at most $_maxArguments parameters.',
          );
        }
        if (!_take('byval')) {
          context.unsupported(
            current,
            'Parameters require explicit ByVal; ByRef, Optional, and ParamArray are unsupported.',
          );
        }
        final name = _identifier();
        result.add(_Parameter(name, _declaredType()));
      } while (_take(','));
    }
    _expect(')');
    return result;
  }

  List<_Statement> _body(int depth, bool Function() stop) {
    if (depth > _maxBlocks) {
      context.limit(current, 'Blocks exceed $_maxBlocks nesting levels.');
    }
    final result = <_Statement>[];
    _separators();
    while (!stop()) {
      if (current.kind == _TokenKind.end) _syntax('Unterminated block.');
      if (++statementCount > _maxStatements) {
        context.limit(current, 'Source exceeds $_maxStatements statements.');
      }
      if (_is('dim') || _is('const')) {
        result.addAll(_declarations(_is('const')));
      } else if (_is('redim')) {
        final token = current;
        position++;
        final preserve = _take('preserve');
        final targets = <_ResizeTarget>[];
        do {
          if (targets.length >= _maxVariables) {
            context.limit(current, 'Too many ReDim targets.');
          }
          final name = _identifier();
          _expect('(');
          final bounds = _arrayDimensions(name);
          final type = _is('as') ? _declaredType() : null;
          targets.add(_ResizeTarget(name, bounds, type));
        } while (_take(','));
        _endStatement();
        result.add(_Resize(token, targets, preserve));
      } else if (_is('erase')) {
        final token = current;
        position++;
        final targets = <_Token>[];
        do {
          if (targets.length >= _maxVariables) {
            context.limit(current, 'Too many Erase targets.');
          }
          targets.add(_identifier());
        } while (_take(','));
        _endStatement();
        result.add(_Erase(token, targets));
      } else if (_is('exit')) {
        final token = current;
        position++;
        final kind = _take('sub')
            ? _ExitKind.sub
            : _take('function')
            ? _ExitKind.function
            : _take('for')
            ? _ExitKind.forLoop
            : _take('do')
            ? _ExitKind.doLoop
            : context.unsupported(
                current,
                'Only Exit Sub, Exit Function, Exit For, and Exit Do are supported.',
              );
        _endStatement();
        result.add(_Exit(token, kind));
      } else if (_is('call')) {
        position++;
        if (context.isWord) {
          final target = _postfix();
          if (target is _Member && target.token.lower == 'insertbefore') {
            if (target.arguments == null) {
              context.unsupported(
                target.token,
                'Call InsertBefore requires parenthesized arguments.',
              );
            }
            result.add(_InsertBefore(target.token, target));
          } else if (target is _Call) {
            result.add(_Invoke(target.token, target.arguments));
          } else if (target is _Name) {
            result.add(_Invoke(target.token, const <_Expr>[]));
          } else {
            context.unsupported(target.token, 'Unsupported Call target.');
          }
          _endStatement();
        } else {
          final name = _identifier();
          final arguments = _arguments() ?? const <_Expr>[];
          _endStatement();
          result.add(_Invoke(name, arguments));
        }
      } else if (_is('for')) {
        final token = current;
        position++;
        final each = _take('each');
        final counter = _identifier();
        _Expr? collection;
        _Expr? start;
        _Expr? end;
        _Expr? step;
        if (each) {
          _expect('in');
          collection = _expression();
        } else {
          _expect('=');
          start = _expression();
          _expect('to');
          end = _expression();
          step = _take('step') ? _expression() : _Literal(token, 1);
        }
        _endStatement();
        final body = _body(depth + 1, () => _is('next'));
        _expect('next');
        if (current.kind == _TokenKind.identifier) {
          final ending = _identifier();
          if (ending.lower != counter.lower) {
            _syntax('Next counter does not match For ${counter.text}.', ending);
          }
        }
        _endStatement();
        result.add(
          each
              ? _ForEach(token, counter, collection!, body)
              : _For(token, counter, start!, end!, step!, body),
        );
      } else if (_is('do')) {
        final token = current;
        position++;
        _Expr? condition;
        var until = false;
        if (_is('while') || _is('until')) {
          until = _take('until');
          if (!until) _expect('while');
          condition = _expression();
        }
        _endStatement();
        final body = _body(depth + 1, () => _is('loop'));
        _expect('loop');
        var testAfter = false;
        if (_is('while') || _is('until')) {
          if (condition != null) {
            _syntax('A Do loop may have a condition at Do or Loop, not both.');
          }
          testAfter = true;
          until = _take('until');
          if (!until) _expect('while');
          condition = _expression();
        }
        _endStatement();
        result.add(
          _ConditionalLoop(
            token,
            body,
            isDo: true,
            condition: condition,
            until: until,
            testAfter: testAfter,
          ),
        );
      } else if (_is('while')) {
        final token = current;
        position++;
        final condition = _expression();
        _endStatement();
        final body = _body(depth + 1, () => _is('wend'));
        _expect('wend');
        _endStatement();
        result.add(
          _ConditionalLoop(token, body, isDo: false, condition: condition),
        );
      } else if (_is('select')) {
        final token = current;
        if (depth + 1 > _maxBlocks) {
          context.limit(token, 'Blocks exceed $_maxBlocks nesting levels.');
        }
        position++;
        _expect('case');
        final selector = _expression();
        _endStatement();
        final branches = <_CaseBranch>[];
        var otherwise = <_Statement>[];
        var hasElse = false;
        while (!_atEnd('select')) {
          if (hasElse) _syntax('Case Else must be the final Case clause.');
          _expect('case');
          if (++statementCount > _maxStatements) {
            context.limit(
              current,
              'Source exceeds $_maxStatements statements.',
            );
          }
          if (_take('else')) {
            hasElse = true;
            _endStatement();
            otherwise = _body(depth + 1, () => _is('case') || _atEnd('select'));
          } else {
            final matches = <_CaseMatch>[];
            do {
              final token = current;
              if (_take('is') || _isComparison) {
                if (!_isComparison) {
                  _syntax('Case Is requires a supported comparison operator.');
                }
                final operator = current.text;
                position++;
                matches.add(
                  _CaseMatch(token, _expression(), operator: operator),
                );
              } else {
                final first = _expression();
                final last = _take('to') ? _expression() : null;
                matches.add(_CaseMatch(token, first, last: last));
              }
            } while (_take(','));
            _endStatement();
            final body = _body(
              depth + 1,
              () => _is('case') || _atEnd('select'),
            );
            branches.add(_CaseBranch(matches, body));
          }
        }
        _expect('end');
        _expect('select');
        _endStatement();
        result.add(_Select(token, selector, branches, otherwise));
      } else if (_is('with')) {
        final token = current;
        position++;
        final target = _expression();
        _endStatement();
        final body = _body(depth + 1, () => _atEnd('with'));
        _expect('end');
        _expect('with');
        _endStatement();
        result.add(_With(token, target, body));
      } else if (_is('if')) {
        final token = current;
        position++;
        final branches = <(_Expr, List<_Statement>)>[];
        var condition = _expression();
        _expect('then');
        _blockIfNewline();
        List<_Statement> branch() => _body(
          depth + 1,
          () => _is('elseif') || _is('else') || _atEnd('if'),
        );
        branches.add((condition, branch()));
        while (_take('elseif')) {
          condition = _expression();
          _expect('then');
          _blockIfNewline();
          branches.add((condition, branch()));
        }
        var otherwise = <_Statement>[];
        if (_take('else')) {
          _endStatement();
          otherwise = _body(depth + 1, () => _atEnd('if'));
        }
        _expect('end');
        _expect('if');
        _endStatement();
        result.add(_If(token, branches, otherwise));
      } else if (current.kind == _TokenKind.identifier &&
          !_is('set') &&
          !_is('let') &&
          !_is('worksheets') &&
          tokens[position + 1].text != '=' &&
          tokens[position + 1].text != '.' &&
          !_indexedAssignmentAhead()) {
        final name = _identifier();
        if (current.kind == _TokenKind.separator && current.text == ':') {
          context.unsupported(
            name,
            'Line labels are unsupported; use Call or empty parentheses for a zero-argument call before a colon.',
          );
        }
        final arguments = <_Expr>[];
        if (_is('(') && tokens[position + 1].text == ')') {
          position += 2;
        } else if (current.kind != _TokenKind.separator &&
            current.kind != _TokenKind.end) {
          do {
            if (arguments.length >= _maxArguments) {
              context.limit(
                current,
                'Calls accept at most $_maxArguments arguments.',
              );
            }
            arguments.add(_expression());
          } while (_take(','));
        }
        _endStatement();
        result.add(_Invoke(name, arguments));
      } else {
        final start = position;
        final token = current;
        final isSet = _take('set');
        final isLet = !isSet && _take('let');
        final target = _postfix();
        if (_take('=')) {
          final value = _expression();
          _endStatement();
          result.add(_Assignment(token, target, value, isSet));
        } else if (!isSet &&
            !isLet &&
            target is _Member &&
            target.token.lower == 'clearcontents') {
          _endStatement();
          result.add(_Clear(token, target));
        } else if (context.isWord &&
            !isSet &&
            !isLet &&
            target is _Member &&
            target.token.lower == 'insertbefore') {
          final arguments = target.arguments ?? <_Expr>[];
          if (target.arguments == null &&
              current.kind != _TokenKind.separator &&
              current.kind != _TokenKind.end) {
            do {
              if (arguments.length >= _maxArguments) {
                context.limit(
                  current,
                  'Calls accept at most $_maxArguments arguments.',
                );
              }
              arguments.add(_expression());
            } while (_take(','));
          }
          _endStatement();
          result.add(
            _InsertBefore(
              target.token,
              _bounded(_Member(target.token, target.receiver, arguments)),
            ),
          );
        } else if (!isSet &&
            !isLet &&
            token.kind == _TokenKind.identifier &&
            tokens[start + 1].text == '.' &&
            (tokens[start + 1].line != token.line ||
                tokens[start + 1].column > token.column + token.text.length)) {
          // Without an assignment, `Helper .Range("A1")` is a bare call
          // whose first argument uses the caller's With context. Reparse the
          // argument after the procedure name; ordinary `sheet .Range = ...`
          // assignments above retain their existing meaning.
          position = start + 1;
          final arguments = <_Expr>[];
          do {
            if (arguments.length >= _maxArguments) {
              context.limit(
                current,
                'Calls accept at most $_maxArguments arguments.',
              );
            }
            arguments.add(_expression());
          } while (_take(','));
          _endStatement();
          result.add(_Invoke(token, arguments));
        } else {
          context.unsupported(
            token,
            'Only assignments, procedure calls, ClearContents, With, supported loops, block If, Select Case, and supported Exit statements are supported.',
          );
        }
      }
      _separators();
    }
    return result;
  }

  void _blockIfNewline() {
    if (current.kind != _TokenKind.separator || current.text != '\n') {
      context.unsupported(
        current,
        'Use a block If with Then at the end of its line.',
      );
    }
    _endStatement();
  }

  bool _indexedAssignmentAhead() {
    // Without a declared array, `Helper (1) = 2` remains a bare call whose
    // argument is a parenthesized comparison. Only array names disambiguate
    // this otherwise identical token shape as an indexed assignment.
    if (!arrayNames.contains(current.lower) ||
        tokens[position + 1].text != '(') {
      return false;
    }
    var depth = 0;
    for (var index = position + 1; index < tokens.length; index++) {
      final token = tokens[index];
      if (token.kind == _TokenKind.end || token.kind == _TokenKind.separator) {
        return false;
      }
      if (token.kind == _TokenKind.symbol && token.text == '(') depth++;
      if (token.kind == _TokenKind.symbol &&
          token.text == ')' &&
          --depth == 0) {
        return tokens[index + 1].text == '=';
      }
    }
    return false;
  }

  List<_Declaration> _declarations(bool isConst) {
    position++;
    final result = <_Declaration>[];
    do {
      final name = _identifier();
      (_Expr, _Expr)? bounds;
      var isDynamicArray = false;
      if (_take('(')) {
        if (isConst) {
          context.unsupported(
            name,
            'Only local Dim arrays are supported; constants must be scalar.',
          );
        }
        if (_take(')')) {
          isDynamicArray = true;
        } else {
          bounds = _arrayDimensions(name);
        }
      }
      final type = _declaredType();
      if (bounds != null || isDynamicArray) arrayNames.add(name.lower);
      _Expr? initializer;
      if (isConst) {
        _expect('=');
        initializer = _expression();
      }
      result.add(
        _Declaration(
          name,
          type,
          isConst,
          initializer,
          bounds: bounds,
          isDynamicArray: isDynamicArray,
        ),
      );
      if (result.length > _maxVariables) {
        context.limit(name, 'Too many declarations.');
      }
    } while (_take(','));
    _endStatement();
    return result;
  }

  (_Expr, _Expr) _arrayDimensions(_Token name) {
    final first = _expression();
    final bounds = _take('to')
        ? (first, _expression())
        : (_Literal(name, arrayBase), first);
    if (_is(',')) {
      context.unsupported(name, 'Only one-dimensional arrays are supported.');
    }
    _expect(')');
    return bounds;
  }

  _Declared _declaredType() {
    if (!_take('as')) return _Declared.variant;
    final token = _identifier();
    return switch (token.lower) {
      'long' => _Declared.long,
      'double' => _Declared.doubleType,
      'string' => _Declared.string,
      'boolean' => _Declared.boolean,
      'variant' => _Declared.variant,
      'worksheet' when context.isExcel => _Declared.worksheet,
      'range' when !context.isPowerPoint => _Declared.range,
      'document' when context.isWord => _Declared.document,
      'paragraph' when context.isWord => _Declared.paragraph,
      'presentation' when context.isPowerPoint => _Declared.presentation,
      'slide' when context.isPowerPoint => _Declared.slide,
      'shape' when context.isPowerPoint => _Declared.shape,
      'textrange' when context.isPowerPoint => _Declared.textRange,
      _ => context.unsupported(
        token,
        context.isPowerPoint
            ? 'Supported declarations are Long, Double, String, Boolean, Variant, Presentation, Slide, Shape, and TextRange.'
            : context.isWord
            ? 'Supported declarations are Long, Double, String, Boolean, Variant, Document, Paragraph, and Range.'
            : 'Supported declarations are Long, Double, String, Boolean, Variant, Worksheet, and Range.',
      ),
    };
  }

  static const _precedence = <String, int>{
    'xor': 1,
    'or': 2,
    'and': 3,
    '=': 4,
    '<>': 4,
    '<': 4,
    '>': 4,
    '<=': 4,
    '>=': 4,
    '&': 5,
    '+': 6,
    '-': 6,
    '*': 7,
    '/': 7,
  };

  _Expr _expression([int minimum = 1]) {
    if (++expressionDepth > _maxDepth) {
      context.limit(current, 'Expressions exceed $_maxDepth nesting levels.');
    }
    _Expr left;
    if (_is('+') || _is('-') || _is('not')) {
      final token = current;
      position++;
      left = _bounded(_Unary(token, _expression(token.lower == 'not' ? 4 : 8)));
    } else {
      left = _postfix();
    }
    while (true) {
      final precedence =
          current.kind == _TokenKind.identifier ||
              current.kind == _TokenKind.symbol
          ? _precedence[current.lower]
          : null;
      if (precedence == null || precedence < minimum) break;
      final token = current;
      position++;
      left = _bounded(_Binary(token, left, _expression(precedence + 1)));
    }
    expressionDepth--;
    return left;
  }

  _Expr _postfix() {
    final token = current;
    _Expr result;
    if (_take('(')) {
      result = _expression();
      _expect(')');
    } else if (_take('.')) {
      final member = _identifier();
      result = _bounded(_Member(member, _WithValue(token), _arguments()));
    } else if (token.kind == _TokenKind.string) {
      position++;
      result = _Literal(token, token.text);
    } else if (token.kind == _TokenKind.number) {
      position++;
      final value = num.tryParse(token.text);
      if (value == null || !value.isFinite || value.abs() > _maxExactInteger) {
        context.limit(
          token,
          'Numeric literals must be finite with magnitude at most 2^53-1.',
        );
      }
      result = _Literal(token, value);
    } else if (token.kind == _TokenKind.identifier) {
      position++;
      if (token.lower == 'true' || token.lower == 'false') {
        result = _Literal(token, token.lower == 'true');
      } else if (token.lower == 'empty' || token.lower == 'null') {
        result = _Literal(
          token,
          token.lower == 'empty'
              ? _VariantState.empty
              : _VariantState.nullValue,
        );
      } else {
        final arguments = _arguments();
        result = arguments == null
            ? _Name(token)
            : _bounded(_Call(token, arguments));
      }
    } else {
      _syntax('Expected a supported expression.');
    }
    while (_take('.')) {
      final member = _identifier();
      result = _bounded(_Member(member, result, _arguments()));
    }
    return result;
  }

  List<_Expr>? _arguments() {
    if (!_take('(')) return null;
    final result = <_Expr>[];
    if (!_is(')')) {
      do {
        if (result.length >= _maxArguments) {
          context.limit(
            current,
            'Calls accept at most $_maxArguments arguments.',
          );
        }
        result.add(_expression());
      } while (_take(','));
    }
    _expect(')');
    return result;
  }

  T _bounded<T extends _Expr>(T expression) {
    if (expression.depth > _maxDepth) {
      context.limit(
        expression.token,
        'Expressions exceed $_maxDepth syntax levels.',
      );
    }
    return expression;
  }

  _Token _identifier() {
    if (current.kind != _TokenKind.identifier) {
      _syntax('Expected an identifier.');
    }
    return tokens[position++];
  }

  bool _take(String text) {
    if (!_is(text)) return false;
    position++;
    return true;
  }

  void _expect(String text) {
    if (!_take(text)) _syntax('Expected "$text".');
  }

  void _endStatement() {
    if (current.kind == _TokenKind.end) return;
    if (current.kind != _TokenKind.separator) {
      _syntax('Unexpected token; the statement must end here.');
    }
    _separators();
  }

  void _separators() {
    while (current.kind == _TokenKind.separator) {
      position++;
    }
  }

  Never _syntax(String message, [_Token? token]) =>
      context.fail(token ?? current, 'vba_syntax_error', message);
}

class _Symbol {
  const _Symbol(
    this.type,
    this.isConst,
    this.token, {
    this.array,
    this.isDynamicArray = false,
    this.initializer,
  });
  final _Declared type;
  final bool isConst;
  final _Token token;
  final _ArrayBounds? array;
  final bool isDynamicArray;
  bool get isArray => array != null || isDynamicArray;
  final _Expr? initializer;
}

class _ArrayBounds {
  const _ArrayBounds(this.lower, this.upper);
  final int lower;
  final int upper;
  int get length => upper - lower + 1;
}

/// Static object-shape validation also visits branches that will not execute.
/// It admits no document getter or unknown callable into the evaluator.
class _Checker {
  _Checker(this.context, this.module);
  final _Context context;
  final _Module module;
  final Map<String, _Symbol> globals = <String, _Symbol>{};
  final Map<String, Map<String, _Symbol>> locals =
      <String, Map<String, _Symbol>>{};
  Map<String, _Symbol> symbols = <String, _Symbol>{};
  final List<_Kind> withKinds = <_Kind>[];
  final Set<String> counters = <String>{};
  final Set<String> eachCounters = <String>{};
  final Map<_Symbol, Object> constantValues = <_Symbol, Object>{};
  int constantWork = 0;
  int doDepth = 0;
  final Map<String, Set<String>> calls = <String, Set<String>>{};
  late _Procedure currentProcedure;
  static const _reserved = <String>{
    ..._stringIntrinsics,
    ..._variantIntrinsics,
    'sub',
    'end',
    'dim',
    'const',
    'as',
    'set',
    'let',
    'for',
    'to',
    'step',
    'next',
    'with',
    'if',
    'then',
    'else',
    'elseif',
    'true',
    'false',
    'not',
    'and',
    'or',
    'xor',
    'option',
    'explicit',
    'attribute',
    'public',
    'private',
    'thisworkbook',
    'worksheets',
    'range',
    'cells',
    'rgb',
    'lbound',
    'ubound',
    'empty',
    'null',
    'nothing',
    'application',
    'activesheet',
    'activeworkbook',
    'selection',
    'rem',
    'boolean',
    'double',
    'long',
    'string',
    'variant',
    'worksheet',
    'function',
    'call',
    'new',
    'on',
    'error',
    'resume',
    'exit',
    'while',
    'wend',
    'do',
    'loop',
    'select',
    'case',
    'is',
    'until',
    'each',
    'in',
    'byref',
    'byval',
    'optional',
    'paramarray',
    'addressof',
    'alias',
    'any',
    'declare',
    'enum',
    'erase',
    'event',
    'friend',
    'implements',
    'lib',
    'me',
    'redim',
    'raiseevent',
    'static',
    'stop',
    'type',
    'withevents',
    'class',
  };

  void check() {
    symbols = globals;
    for (final declaration in module.constants) {
      _declare(declaration);
    }
    for (final procedure in module.procedures.values) {
      currentProcedure = procedure;
      calls[procedure.name.lower] = <String>{};
      symbols = <String, _Symbol>{...globals};
      withKinds.clear();
      counters.clear();
      eachCounters.clear();
      doDepth = 0;
      for (final parameter in procedure.parameters) {
        _declare(_Declaration(parameter.name, parameter.type, false, null));
      }
      if (procedure.returnType case final returnType?) {
        // Only this implicit result variable may share a procedure name.
        if (symbols.length >= _maxVariables) {
          context.limit(
            procedure.name,
            'The function result exceeds the visible variable limit.',
          );
        }
        symbols[procedure.name.lower] = _Symbol(
          returnType,
          false,
          procedure.name,
        );
      }
      var executable = false;
      for (final statement in procedure.body) {
        if (statement is _Declaration) {
          if (executable) {
            context.unsupported(
              statement.token,
              'Declarations must precede executable statements in this subset.',
            );
          }
          _declare(statement);
        } else {
          executable = true;
        }
      }
      _implicit(procedure.body);
      _statements(procedure.body);
      locals[procedure.name.lower] = Map<String, _Symbol>.of(symbols);
    }
    _checkCallGraph();
  }

  void _checkCallGraph() {
    // Remove leaves iteratively. Recursive DFS would itself overflow on hostile
    // source before a long or cyclic call graph could receive a diagnostic.
    final remaining = <String, int>{};
    final callers = <String, List<String>>{};
    final depths = <String, int>{};
    final ready = <String>[];
    for (final entry in calls.entries) {
      remaining[entry.key] = entry.value.length;
      depths[entry.key] = 1;
      if (entry.value.isEmpty) ready.add(entry.key);
      for (final target in entry.value) {
        (callers[target] ??= <String>[]).add(entry.key);
      }
    }
    for (var index = 0; index < ready.length; index++) {
      final name = ready[index];
      for (final caller in callers[name] ?? const <String>[]) {
        final candidate = depths[name]! + 1;
        if (candidate > depths[caller]!) depths[caller] = candidate;
        remaining[caller] = remaining[caller]! - 1;
        if (remaining[caller] == 0) ready.add(caller);
      }
    }
    if (ready.length != calls.length) {
      final name = remaining.entries
          .firstWhere((entry) => entry.value != 0)
          .key;
      context.unsupported(
        module.procedures[name]!.name,
        'Recursive procedure calls are unsupported, including unused paths.',
      );
    }
    for (final entry in depths.entries) {
      if (entry.value > _maxCalls) {
        context.limit(
          module.procedures[entry.key]!.name,
          'Procedure call chains may contain at most $_maxCalls active frames.',
        );
      }
    }
  }

  void _declare(_Declaration declaration) {
    final name = declaration.token.lower;
    if (context.reserved(name) ||
        symbols.containsKey(name) ||
        module.procedures.containsKey(name)) {
      context.fail(
        declaration.token,
        'vba_name_error',
        'Reserved or duplicate variable ${declaration.token.text}.',
      );
    }
    if (symbols.length >= _maxVariables) {
      context.limit(
        declaration.token,
        'A procedure may have at most $_maxVariables visible variables.',
      );
    }
    if (declaration.isConst) {
      if (_objectType(declaration.type)) {
        context.type(declaration.token, 'Constants must be scalar.');
      }
      final initializer = declaration.initializer!;
      _constant(initializer);
      _assignable(
        declaration.type,
        _expression(initializer),
        initializer.token,
      );
    }
    if (declaration.isArray) {
      if (_objectType(declaration.type)) {
        context.unsupported(
          declaration.token,
          'Array elements must be scalar.',
        );
      }
    }
    _ArrayBounds? array;
    if (declaration.bounds case final bounds?) {
      final lower = _arrayBound(bounds.$1);
      final upper = _arrayBound(bounds.$2);
      if (lower > upper) {
        context.type(
          declaration.token,
          'An array lower bound exceeds its upper bound.',
        );
      }
      array = _ArrayBounds(lower, upper);
      if (array.length > _maxArrayElements) {
        context.limit(
          declaration.token,
          'An array may contain at most $_maxArrayElements elements.',
        );
      }
    }
    symbols[name] = _Symbol(
      declaration.type,
      declaration.isConst,
      declaration.token,
      array: array,
      isDynamicArray: declaration.isDynamicArray,
      initializer: declaration.initializer,
    );
  }

  int _arrayBound(_Expr expression) {
    _constant(expression);
    _compatible(_Kind.number, _expression(expression), expression.token);
    // Resolve only constants actually used by a bound. Dependency discovery is
    // iterative; a long chain of prior constants must not multiply AST depth
    // on the host stack. Declaration order is already a topological order.
    final needed = <_Symbol>{};
    final pending = <_Expr>[expression];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      switch (current) {
        case _Name():
          if (context.constants.containsKey(current.token.lower)) {
            break;
          }
          final symbol = _symbol(current.token);
          if (!constantValues.containsKey(symbol) && needed.add(symbol)) {
            pending.add(symbol.initializer!);
          }
        case _Unary():
          pending.add(current.operand);
        case _Binary():
          pending.add(current.left);
          pending.add(current.right);
        default:
          break;
      }
    }
    final evaluator = _Evaluator(context, module, this)..work = constantWork;
    for (final entry in symbols.entries) {
      final symbol = entry.value;
      if (needed.contains(symbol)) {
        constantValues[symbol] = evaluator._convert(
          symbol.type,
          evaluator._evaluate(symbol.initializer!),
          symbol.token,
        );
      }
      if (constantValues[symbol] case final value?) {
        evaluator.values[entry.key] = value;
      }
    }
    final result = evaluator._integer(
      evaluator._evaluate(expression),
      expression.token,
    );
    constantWork = evaluator.work;
    if (result < -2147483648 || result > 2147483647) {
      context.type(
        expression.token,
        'Array bounds must be signed 32-bit integers.',
      );
    }
    return result;
  }

  void _constant(_Expr expression) {
    switch (expression) {
      case _Literal():
        if (expression.value is _VariantState) {
          context.unsupported(
            expression.token,
            'Empty and Null are source values, not supported Const expressions.',
          );
        }
        break;
      case _Name():
        if (!(symbols[expression.token.lower]?.isConst ?? false) &&
            !context.constants.containsKey(expression.token.lower)) {
          context.unsupported(
            expression.token,
            'Const expressions may only refer to previously declared constants.',
          );
        }
      case _Unary():
        _constant(expression.operand);
      case _Binary():
        _constant(expression.left);
        _constant(expression.right);
      default:
        context.unsupported(
          expression.token,
          'Const expressions cannot call functions or access objects.',
        );
    }
  }

  void _implicit(List<_Statement> statements) {
    for (final statement in statements) {
      _Token? variable;
      switch (statement) {
        case _Assignment(target: final _Name target):
          variable = target.token;
        case _For():
          variable = statement.counter;
          _implicit(statement.body);
        case _ForEach():
          variable = statement.counter;
          _implicit(statement.body);
        case _ConditionalLoop():
          _implicit(statement.body);
        case _Select():
          for (final branch in statement.branches) {
            _implicit(branch.body);
          }
          _implicit(statement.otherwise);
        case _With():
          _implicit(statement.body);
        case _If():
          for (final branch in statement.branches) {
            _implicit(branch.$2);
          }
          _implicit(statement.otherwise);
        default:
          break;
      }
      if (variable != null && !symbols.containsKey(variable.lower)) {
        if (module.explicit ||
            context.reserved(variable.lower) ||
            module.procedures.containsKey(variable.lower)) {
          context.fail(
            variable,
            'vba_name_error',
            'Undeclared or reserved variable ${variable.text}.',
          );
        }
        if (symbols.length >= _maxVariables) {
          context.limit(variable, 'Too many variables.');
        }
        symbols[variable.lower] = _Symbol(_Declared.variant, false, variable);
      }
    }
  }

  void _statements(List<_Statement> statements, {bool nested = false}) {
    for (final statement in statements) {
      switch (statement) {
        case _Declaration():
          if (nested) {
            context.unsupported(
              statement.token,
              'Declarations inside control-flow blocks are unsupported.',
            );
          }
        case _Resize():
          for (final target in statement.targets) {
            final symbol = _symbol(target.name);
            if (!symbol.isDynamicArray) {
              context.unsupported(
                target.name,
                'ReDim requires a local dynamic array declared with Dim name().',
              );
            }
            if (target.type != null && target.type != symbol.type) {
              context.type(
                target.name,
                'ReDim cannot change the declared element type.',
              );
            }
            for (final bound in <_Expr>[target.bounds.$1, target.bounds.$2]) {
              _compatible(_Kind.number, _expression(bound), bound.token);
            }
          }
        case _Erase():
          for (final target in statement.targets) {
            if (!_symbol(target).isArray) {
              context.type(target, 'Erase requires a declared local array.');
            }
          }
        case _Assignment():
          final valueKind = _expression(statement.value);
          if (statement.target case final _Name target) {
            final symbol = _symbol(target.token);
            if (symbol.isArray) {
              context.unsupported(
                target.token,
                'Whole-array assignment is unsupported; use an element subscript.',
              );
            }
            if (symbol.isConst ||
                (counters.contains(target.token.lower) &&
                    !eachCounters.contains(target.token.lower))) {
              context.unsupported(
                target.token,
                'Constants and active For counters cannot be assigned.',
              );
            }
            final object = _objectType(symbol.type);
            if (statement.isSet != object) {
              context.type(
                target.token,
                'Set is required exactly for supported declared object variables.',
              );
            }
            _assignable(symbol.type, valueKind, statement.value.token);
          } else if (statement.target case final _Call target) {
            if (statement.isSet) {
              context.unsupported(
                target.token,
                'Array elements are scalar and cannot use Set.',
              );
            }
            final symbol = _symbol(target.token);
            if (!symbol.isArray) {
              context.unsupported(
                target.token,
                'Indexed assignments require a declared array.',
              );
            }
            _arrayIndex(target);
            _assignable(symbol.type, valueKind, statement.value.token);
          } else if (statement.target case final _Member target) {
            if (statement.isSet) {
              context.unsupported(
                target.token,
                'Set only supports declared object variables.',
              );
            }
            final expected = _writeKind(target);
            _compatible(expected, valueKind, statement.value.token);
          } else {
            context.unsupported(
              statement.target.token,
              'Unsupported assignment target.',
            );
          }
        case _Clear():
          if (!context.isExcel) {
            context.unsupported(
              statement.target.token,
              'ClearContents belongs to the Excel object model.',
            );
          }
          _arguments(statement.target, 0, allowProperty: true);
          if (_expression(statement.target.receiver) != _Kind.range) {
            context.type(
              statement.token,
              'ClearContents requires an explicit Range.',
            );
          }
        case _InsertBefore():
          final arguments = _arguments(statement.target, 1);
          if (_expression(statement.target.receiver) != _Kind.range) {
            context.type(
              statement.target.token,
              'InsertBefore requires an explicit Word Range.',
            );
          }
          _compatible(
            _Kind.string,
            _expression(arguments.single),
            arguments.single.token,
          );
        case _For():
          final counter = _symbol(statement.counter);
          if (counter.isConst ||
              counter.isArray ||
              (counter.type != _Declared.long &&
                  counter.type != _Declared.variant)) {
            context.type(
              statement.counter,
              'For requires a mutable Long or Variant counter.',
            );
          }
          if (!counters.add(statement.counter.lower)) {
            context.unsupported(
              statement.counter,
              'Nested loops must use distinct counters.',
            );
          }
          for (final value in <_Expr>[
            statement.start,
            statement.end,
            statement.step,
          ]) {
            _compatible(_Kind.number, _expression(value), value.token);
          }
          _statements(statement.body, nested: true);
          counters.remove(statement.counter.lower);
        case _ForEach():
          final counter = _symbol(statement.counter);
          final collection = statement.collection;
          final isArray =
              collection is _Name &&
              (symbols[collection.token.lower]?.isArray ?? false);
          if (!context.isExcel && !isArray) {
            context.unsupported(
              collection.token,
              'Document collections cannot be enumerated without live reads.',
            );
          }
          if (!isArray && _expression(collection) != _Kind.range) {
            context.type(
              collection.token,
              'For Each requires a local array or explicit Range.',
            );
          }
          if (counter.isConst ||
              counter.isArray ||
              counter.type != (isArray ? _Declared.variant : _Declared.range)) {
            context.type(
              statement.counter,
              isArray
                  ? 'For Each over an array requires a mutable Variant variable.'
                  : 'For Each over a Range requires a mutable Range variable.',
            );
          }
          if (!counters.add(statement.counter.lower)) {
            context.unsupported(
              statement.counter,
              'Nested loops must use distinct counters.',
            );
          }
          eachCounters.add(statement.counter.lower);
          _statements(statement.body, nested: true);
          eachCounters.remove(statement.counter.lower);
          counters.remove(statement.counter.lower);
        case _ConditionalLoop():
          if (statement.condition case final condition?) {
            _compatible(_Kind.boolean, _expression(condition), condition.token);
          }
          if (statement.isDo) doDepth++;
          _statements(statement.body, nested: true);
          if (statement.isDo) doDepth--;
        case _Select():
          final selector = _expression(statement.selector);
          _scalar(selector, statement.selector.token);
          for (final branch in statement.branches) {
            for (final match in branch.matches) {
              final first = _expression(match.first);
              _comparisonKinds(selector, first, match.token);
              if (match.last case final last?) {
                final lastKind = _expression(last);
                _comparisonKinds(selector, lastKind, last.token);
                _comparisonKinds(first, lastKind, last.token);
                _rangeKind(selector, statement.selector.token);
                _rangeKind(first, match.first.token);
                _rangeKind(lastKind, last.token);
              }
            }
            _statements(branch.body, nested: true);
          }
          _statements(statement.otherwise, nested: true);
        case _With():
          final kind = _expression(statement.target);
          final wordObject =
              context.isWord &&
              (kind == _Kind.document ||
                  kind == _Kind.paragraph ||
                  kind == _Kind.font ||
                  kind == _Kind.paragraphFormat);
          final powerPointObject =
              context.isPowerPoint && _powerPointObjectKinds.contains(kind);
          if (kind != _Kind.worksheet &&
              kind != _Kind.range &&
              !wordObject &&
              !powerPointObject) {
            context.type(
              statement.token,
              context.isPowerPoint
                  ? 'With requires an explicitly bound PowerPoint object.'
                  : context.isWord
                  ? 'With requires a Document, Paragraph, Range, Font, or ParagraphFormat.'
                  : 'With requires a Worksheet or Range.',
            );
          }
          withKinds.add(kind);
          _statements(statement.body, nested: true);
          withKinds.removeLast();
        case _If():
          for (final branch in statement.branches) {
            _compatible(_Kind.boolean, _expression(branch.$1), branch.$1.token);
            _statements(branch.$2, nested: true);
          }
          _statements(statement.otherwise, nested: true);
        case _Invoke():
          _procedureCall(
            statement.token,
            statement.arguments,
            needsResult: false,
          );
        case _Exit():
          final allowed = switch (statement.kind) {
            _ExitKind.sub => currentProcedure.returnType == null,
            _ExitKind.function => currentProcedure.returnType != null,
            _ExitKind.forLoop => counters.isNotEmpty,
            _ExitKind.doLoop => doDepth > 0,
          };
          if (!allowed) {
            context.unsupported(
              statement.token,
              'Exit does not match an enclosing procedure, For loop, or Do loop.',
            );
          }
      }
    }
  }

  _Procedure _procedureCall(
    _Token token,
    List<_Expr> arguments, {
    required bool needsResult,
  }) {
    final procedure = module.procedures[token.lower];
    if (procedure == null) {
      context.unsupported(
        token,
        'Unknown or unsupported procedure ${token.text}.',
      );
    }
    if (needsResult && procedure.returnType == null) {
      context.type(
        token,
        'A Sub cannot be used as a value; use a scalar Function.',
      );
    }
    _count(token, arguments, procedure.parameters.length);
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      _assignable(
        procedure.parameters[index].type,
        _expression(argument),
        argument.token,
      );
    }
    calls[currentProcedure.name.lower]!.add(procedure.name.lower);
    return procedure;
  }

  _Kind _writeKind(_Member target) {
    _arguments(target, 0, allowProperty: true);
    final receiver = _expression(target.receiver);
    final property = target.token.lower;
    if (context.isPowerPoint) {
      if (receiver == _Kind.textRange && property == 'text') {
        return _Kind.string;
      }
      if (receiver == _Kind.powerPointFont) {
        if (property == 'bold' ||
            property == 'italic' ||
            property == 'underline') {
          return _Kind.triState;
        }
        if (property == 'name') return _Kind.string;
        if (property == 'size') return _Kind.number;
      }
      if (receiver == _Kind.powerPointColor && property == 'rgb') {
        return _Kind.number;
      }
      if (receiver == _Kind.powerPointParagraphFormat &&
          property == 'alignment') {
        return _Kind.number;
      }
      if (receiver == _Kind.shape &&
          const <String>{
            'left',
            'top',
            'width',
            'height',
            'rotation',
          }.contains(property)) {
        return _Kind.number;
      }
      context.unsupported(
        target.token,
        'Unsupported writable PowerPoint property ${target.token.text}.',
      );
    }
    if (context.isWord) {
      if (receiver == _Kind.font) {
        if (property == 'bold' ||
            property == 'italic' ||
            property == 'strikethrough') {
          return _Kind.boolean;
        }
        if (property == 'size' ||
            property == 'color' ||
            property == 'underline') {
          return _Kind.number;
        }
        if (property == 'name') return _Kind.string;
      } else if (receiver == _Kind.paragraphFormat) {
        if (property == 'keeptogether' || property == 'pagebreakbefore') {
          return _Kind.boolean;
        }
        if (const <String>{
          'alignment',
          'spacebefore',
          'spaceafter',
          'leftindent',
          'rightindent',
          'firstlineindent',
        }.contains(property)) {
          return _Kind.number;
        }
      }
      context.unsupported(
        target.token,
        'Unsupported writable Word property ${target.token.text}.',
      );
    }
    if (receiver == _Kind.range) {
      if (property == 'value' || property == 'value2') return _Kind.variant;
      if (property == 'formula') return _Kind.string;
    } else if (receiver == _Kind.font) {
      if (property == 'bold') return _Kind.boolean;
      if (property == 'size' || property == 'color') return _Kind.number;
    } else if (receiver == _Kind.interior && property == 'color') {
      return _Kind.number;
    }
    context.unsupported(
      target.token,
      'Unsupported writable property ${target.token.text}.',
    );
  }

  _Kind _expression(_Expr expression) {
    switch (expression) {
      case _Literal():
        return expression.value is _VariantState
            ? _Kind.variant
            : expression.value is num
            ? _Kind.number
            : expression.value is bool
            ? _Kind.boolean
            : _Kind.string;
      case _Name():
        if (context.constants.containsKey(expression.token.lower)) {
          return _Kind.number;
        }
        if (context.isPowerPoint) {
          if (expression.token.lower == 'activepresentation') {
            return _Kind.presentation;
          }
          if (expression.token.lower == 'application') {
            return _Kind.powerPointApplication;
          }
          if (expression.token.lower == 'thisworkbook' ||
              expression.token.lower == 'thisdocument') {
            context.unsupported(
              expression.token,
              'The selected object belongs to another Office application.',
            );
          }
        }
        if (context.isWord) {
          if (expression.token.lower == 'thisdocument') return _Kind.document;
          if (_wordConstants.containsKey(expression.token.lower)) {
            return _Kind.number;
          }
          if (expression.token.lower == 'thisworkbook') {
            context.unsupported(
              expression.token,
              'ThisWorkbook belongs to the Excel object model.',
            );
          }
        } else if (context.isExcel &&
            expression.token.lower == 'thisworkbook') {
          return _Kind.workbook;
        }
        final symbol = _symbol(expression.token);
        if (symbol.isArray) {
          context.type(
            expression.token,
            'An array needs an element subscript; whole-array values are unsupported.',
          );
        }
        return _kindOf(symbol.type);
      case _WithValue():
        if (withKinds.isEmpty) {
          context.unsupported(
            expression.token,
            'A leading dot requires an enclosing With block.',
          );
        }
        return withKinds.last;
      case _Call():
        if ((symbols[expression.token.lower]?.isArray ?? false)) {
          return _arrayIndex(expression);
        }
        if (_stringIntrinsics.contains(expression.token.lower)) {
          return _stringIntrinsic(expression);
        }
        if (_variantIntrinsics.contains(expression.token.lower)) {
          _count(expression.token, expression.arguments, 1);
          final argument = expression.arguments.single;
          _scalar(_expression(argument), argument.token);
          return switch (expression.token.lower) {
            'isempty' || 'isnull' || 'cbool' => _Kind.boolean,
            'cdbl' || 'clng' => _Kind.number,
            'cstr' => _Kind.string,
            _ => _Kind.variant,
          };
        }
        if (expression.token.lower == 'lbound' ||
            expression.token.lower == 'ubound') {
          if (expression.arguments.isEmpty || expression.arguments.length > 2) {
            context.type(
              expression.token,
              '${expression.token.text} requires an array and an optional dimension.',
            );
          }
          _arraySymbol(expression.arguments.first);
          if (expression.arguments.length == 2) {
            final dimension = expression.arguments[1];
            _compatible(_Kind.number, _expression(dimension), dimension.token);
          }
          return _Kind.number;
        }
        if (expression.token.lower == 'worksheets') {
          if (!context.isExcel) {
            context.unsupported(
              expression.token,
              'Worksheets belongs to the Excel object model.',
            );
          }
          _count(expression.token, expression.arguments, 1);
          final kind = _expression(expression.arguments.single);
          if (kind != _Kind.string &&
              kind != _Kind.number &&
              kind != _Kind.variant) {
            context.type(
              expression.token,
              'Worksheets needs a name or one-based index.',
            );
          }
          return _Kind.worksheet;
        }
        if (expression.token.lower == 'rgb') {
          _count(expression.token, expression.arguments, 3);
          for (final argument in expression.arguments) {
            _compatible(_Kind.number, _expression(argument), argument.token);
          }
          return _Kind.number;
        }
        return _kindOf(
          _procedureCall(
            expression.token,
            expression.arguments,
            needsResult: true,
          ).returnType!,
        );
      case _Member():
        final receiver = _expression(expression.receiver);
        final name = expression.token.lower;
        if (context.isPowerPoint) {
          return _powerPointMember(expression, receiver);
        }
        if (context.isWord) {
          if (receiver == _Kind.document && name == 'paragraphs') {
            final argument = _arguments(expression, 1).single;
            _compatible(_Kind.number, _expression(argument), argument.token);
            return _Kind.paragraph;
          }
          if (receiver == _Kind.paragraph && name == 'range') {
            _arguments(expression, 0, allowProperty: true);
            return _Kind.range;
          }
          if (receiver == _Kind.range &&
              (name == 'font' || name == 'paragraphformat')) {
            _arguments(expression, 0, allowProperty: true);
            return name == 'font' ? _Kind.font : _Kind.paragraphFormat;
          }
          context.unsupported(
            expression.token,
            'Unsupported Word object member or document read: ${expression.token.text}.',
          );
        }
        if (receiver == _Kind.workbook && name == 'worksheets') {
          final arguments = _arguments(expression, 1);
          final kind = _expression(arguments.single);
          if (kind != _Kind.string &&
              kind != _Kind.number &&
              kind != _Kind.variant) {
            context.type(
              expression.token,
              'Worksheets needs a name or one-based index.',
            );
          }
          return _Kind.worksheet;
        }
        if (receiver == _Kind.worksheet &&
            (name == 'range' || name == 'cells')) {
          final arguments = _arguments(expression, name == 'range' ? 1 : 2);
          for (final argument in arguments) {
            _compatible(
              name == 'range' ? _Kind.string : _Kind.number,
              _expression(argument),
              argument.token,
            );
          }
          return _Kind.range;
        }
        if (receiver == _Kind.range && (name == 'font' || name == 'interior')) {
          _arguments(expression, 0, allowProperty: true);
          return name == 'font' ? _Kind.font : _Kind.interior;
        }
        if (receiver == _Kind.range && (name == 'row' || name == 'column')) {
          _arguments(expression, 0, allowProperty: true);
          return _Kind.number;
        }
        context.unsupported(
          expression.token,
          'Unsupported object member or document read: ${expression.token.text}.',
        );
      case _Unary():
        final expected = expression.token.lower == 'not'
            ? _Kind.boolean
            : _Kind.number;
        final operand = _expression(expression.operand);
        _compatible(expected, operand, expression.operand.token);
        // A Variant operand may be Null. Preserve that possible result so a
        // nested expression behaves like the same value stored in a Variant.
        return operand == _Kind.variant ? _Kind.variant : expected;
      case _Binary():
        final left = _expression(expression.left);
        final right = _expression(expression.right);
        final operator = expression.token.lower;
        final nullable = left == _Kind.variant || right == _Kind.variant;
        if (operator == '&') {
          _scalar(left, expression.left.token);
          _scalar(right, expression.right.token);
          return nullable ? _Kind.variant : _Kind.string;
        }
        if (const <String>{'and', 'or', 'xor'}.contains(operator)) {
          _compatible(_Kind.boolean, left, expression.left.token);
          _compatible(_Kind.boolean, right, expression.right.token);
          return nullable ? _Kind.variant : _Kind.boolean;
        }
        if (_comparisonOperators.contains(operator)) {
          _comparisonKinds(left, right, expression.token);
          return nullable ? _Kind.variant : _Kind.boolean;
        }
        _compatible(_Kind.number, left, expression.left.token);
        _compatible(_Kind.number, right, expression.right.token);
        return nullable ? _Kind.variant : _Kind.number;
    }
  }

  _Kind _powerPointMember(_Member expression, _Kind receiver) {
    final name = expression.token.lower;
    if (receiver == _Kind.powerPointApplication &&
        name == 'activepresentation') {
      _arguments(expression, 0, allowProperty: true);
      return _Kind.presentation;
    }
    if (receiver == _Kind.presentation && name == 'slides') {
      if (expression.arguments == null) return _Kind.slides;
      _powerPointSelector(expression, shape: false);
      return _Kind.slide;
    }
    if (receiver == _Kind.slides && name == 'item') {
      _powerPointSelector(expression, shape: false);
      return _Kind.slide;
    }
    if (receiver == _Kind.slide && name == 'shapes') {
      if (expression.arguments == null) return _Kind.shapes;
      _powerPointSelector(expression, shape: true);
      return _Kind.shape;
    }
    if (receiver == _Kind.shapes && name == 'item') {
      _powerPointSelector(expression, shape: true);
      return _Kind.shape;
    }
    if (receiver == _Kind.shape && name == 'textframe') {
      _arguments(expression, 0, allowProperty: true);
      return _Kind.textFrame;
    }
    if (receiver == _Kind.textFrame && name == 'textrange') {
      _arguments(expression, 0, allowProperty: true);
      return _Kind.textRange;
    }
    if (receiver == _Kind.textRange &&
        (name == 'font' || name == 'paragraphformat')) {
      _arguments(expression, 0, allowProperty: true);
      return name == 'font'
          ? _Kind.powerPointFont
          : _Kind.powerPointParagraphFormat;
    }
    if (receiver == _Kind.powerPointFont && name == 'color') {
      _arguments(expression, 0, allowProperty: true);
      return _Kind.powerPointColor;
    }
    context.unsupported(
      expression.token,
      'Unsupported PowerPoint object member or document read: ${expression.token.text}.',
    );
  }

  void _powerPointSelector(_Member expression, {required bool shape}) {
    final argument = _arguments(expression, 1).single;
    final kind = _expression(argument);
    if (kind != _Kind.number &&
        kind != _Kind.variant &&
        !(shape && kind == _Kind.string)) {
      context.type(
        argument.token,
        shape
            ? 'Shapes requires a one-based index or an exact shape name.'
            : 'Slides requires a one-based index.',
      );
    }
  }

  _Symbol _symbol(_Token token) =>
      symbols[token.lower] ??
      context.fail(
        token,
        'vba_name_error',
        'Unknown name ${token.text}; active selections, default members, and undeclared reads are unsupported.',
      );

  _Symbol _arraySymbol(_Expr expression) {
    if (expression is! _Name) {
      context.type(
        expression.token,
        'A declared local array name is required.',
      );
    }
    final symbol = _symbol(expression.token);
    if (!symbol.isArray) {
      context.type(expression.token, 'A declared local array is required.');
    }
    return symbol;
  }

  _Kind _arrayIndex(_Call expression) {
    _count(expression.token, expression.arguments, 1);
    final index = expression.arguments.single;
    _compatible(_Kind.number, _expression(index), index.token);
    return _kindOf(_symbol(expression.token).type);
  }

  _Kind _stringIntrinsic(_Call expression) {
    final name = expression.token.lower;
    final arguments = expression.arguments;
    if (name == r'mid$') {
      if (arguments.length < 2 || arguments.length > 3) {
        context.type(
          expression.token,
          '${expression.token.text} requires a string, start, and optional length.',
        );
      }
    } else {
      _count(expression.token, arguments, name == 'len' ? 1 : 2);
    }
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      _compatible(
        index == 0 ? _Kind.string : _Kind.number,
        _expression(argument),
        argument.token,
      );
    }
    return name == 'len' ? _Kind.number : _Kind.string;
  }

  List<_Expr> _arguments(
    _Member member,
    int count, {
    bool allowProperty = false,
  }) {
    final arguments = member.arguments;
    if (arguments == null && !(allowProperty && count == 0)) {
      context.type(member.token, '${member.token.text} needs arguments.');
    }
    // Property getter syntax must not accidentally become an invocation.
    if (allowProperty &&
        arguments != null &&
        member.token.lower != 'clearcontents') {
      context.unsupported(member.token, 'Property arguments are unsupported.');
    }
    _count(member.token, arguments ?? const <_Expr>[], count);
    return arguments ?? const <_Expr>[];
  }

  void _count(_Token token, List<_Expr> arguments, int count) {
    if (arguments.length != count) {
      context.type(token, '${token.text} requires $count argument(s).');
    }
  }

  void _assignable(_Declared type, _Kind value, _Token token) =>
      _compatible(_kindOf(type), value, token);

  void _compatible(_Kind expected, _Kind value, _Token token) {
    if (expected == _Kind.triState) {
      if (value == _Kind.boolean ||
          value == _Kind.number ||
          value == _Kind.variant) {
        return;
      }
      context.type(
        token,
        'A Boolean or exact msoTrue/msoFalse value is required.',
      );
    }
    if (expected == _Kind.variant) {
      _scalar(value, token);
    } else if (expected != value &&
        (value != _Kind.variant ||
            expected == _Kind.worksheet ||
            expected == _Kind.range ||
            expected == _Kind.document ||
            expected == _Kind.paragraph ||
            _powerPointObjectKinds.contains(expected))) {
      // Scalar Variant values may defer scalar checks until evaluation, but
      // cannot ever carry object bindings, including in unexecuted code.
      context.type(
        token,
        'Implicit conversion from ${value.name} to ${expected.name} is unsupported.',
      );
    }
  }

  void _scalar(_Kind kind, _Token token) {
    if (kind != _Kind.string &&
        kind != _Kind.number &&
        kind != _Kind.boolean &&
        kind != _Kind.variant) {
      context.type(
        token,
        'A scalar value is required; object default members are unsupported.',
      );
    }
  }

  void _comparisonKinds(_Kind left, _Kind right, _Token token) {
    _scalar(left, token);
    _scalar(right, token);
    if (left != right && left != _Kind.variant && right != _Kind.variant) {
      context.type(token, 'Comparisons require matching scalar types.');
    }
  }

  void _rangeKind(_Kind kind, _Token token) {
    if (kind != _Kind.number && kind != _Kind.string && kind != _Kind.variant) {
      context.type(token, 'Case To ranges require numbers or strings.');
    }
  }
}

class _Uninitialized {
  const _Uninitialized();
}

class _Array {
  _Array(this.bounds, this.type, this.elements);
  _Array.unallocated(this.type) : bounds = null, elements = <Object>[];
  _ArrayBounds? bounds;
  final _Declared type;
  List<Object> elements;
  int stringUnits = 0;
  int locks = 0;
}

class _Workbook {
  const _Workbook();
}

class _Worksheet {
  const _Worksheet(this.selector);
  final Object selector;
}

class _Range {
  const _Range(
    this.sheet,
    this.minRow,
    this.minColumn,
    this.maxRow,
    this.maxColumn,
  );
  final _Worksheet sheet;
  final int minRow;
  final int minColumn;
  final int maxRow;
  final int maxColumn;
}

class _Font {
  const _Font(this.range);
  final _Range range;
}

class _Interior {
  const _Interior(this.range);
  final _Range range;
}

class _WordDocument {
  const _WordDocument();
}

class _WordParagraph {
  const _WordParagraph(this.index);
  final int index;
}

class _WordRange {
  const _WordRange(this.paragraph);
  final _WordParagraph paragraph;
}

class _WordFont {
  const _WordFont(this.range);
  final _WordRange range;
}

class _WordParagraphFormat {
  const _WordParagraphFormat(this.range);
  final _WordRange range;
}

class _PowerPointApplication {
  const _PowerPointApplication();
}

class _Presentation {
  const _Presentation();
}

class _Slides {
  const _Slides();
}

class _Slide {
  const _Slide(this.index);
  final int index;
}

class _Shapes {
  const _Shapes(this.slide);
  final _Slide slide;
}

class _Shape {
  const _Shape(this.slide, this.selector);
  final _Slide slide;
  final Object selector;
}

class _TextFrame {
  const _TextFrame(this.shape);
  final _Shape shape;
}

class _TextRange {
  const _TextRange(this.shape);
  final _Shape shape;
}

class _PowerPointFont {
  const _PowerPointFont(this.range);
  final _TextRange range;
}

class _PowerPointColor {
  const _PowerPointColor(this.range);
  final _TextRange range;
}

class _PowerPointParagraphFormat {
  const _PowerPointParagraphFormat(this.range);
  final _TextRange range;
}

sealed class _ExecutionFrame {}

class _BodyFrame extends _ExecutionFrame {
  _BodyFrame(this.statements);
  final List<_Statement> statements;
  int position = 0;
}

class _WithFrame extends _ExecutionFrame {}

class _ConditionalFrame extends _ExecutionFrame {
  _ConditionalFrame(this.loop);
  final _ConditionalLoop loop;
  bool afterBody = false;
}

class _ForFrame extends _ExecutionFrame {
  _ForFrame(this.loop, this.type, this.counter, this.step, this.remaining);
  final _For loop;
  final _Declared type;
  int counter;
  final int step;
  int remaining;
  bool afterBody = false;
}

class _ForEachFrame extends _ExecutionFrame {
  _ForEachFrame(this.loop, this.collection, this.length);
  final _ForEach loop;
  final Object collection;
  final int length;
  int index = 0;
}

class _Evaluator {
  _Evaluator(this.context, this.module, this.checker);
  final _Context context;
  final _Module module;
  final _Checker checker;
  final List<OfficeMacroStep> steps = <OfficeMacroStep>[];
  Map<String, Object> values = <String, Object>{};
  List<Object> withValues = <Object>[];
  Map<String, _Symbol> symbols = <String, _Symbol>{};
  Map<String, Object> globalValues = <String, Object>{};
  int activeCalls = 0;
  int activeArrayElements = 0;
  int activeArrayStringUnits = 0;
  int work = 0;
  int encodedBytes = 0;

  OfficeMacro compile() {
    work = checker.constantWork;
    final procedure =
        module.procedures[context.source.entryPoint.toLowerCase()]!;
    symbols = checker.globals;
    final fullName = '${context.source.moduleName}.${procedure.name.text}';
    final name = fullName.length <= 128 ? fullName : procedure.name.text;
    encodedBytes = utf8
        .encode(
          jsonEncode(<String, Object?>{
            'version': 1,
            'name': name,
            'format': context.format.name,
            'steps': <Object?>[],
          }),
        )
        .length;
    for (final entry in symbols.entries) {
      values[entry.key] = _default(entry.value.type);
    }
    for (final declaration in module.constants) {
      _initialize(declaration);
    }
    globalValues = Map<String, Object>.of(values);
    _invoke(procedure, const <Object>[], procedure.name, needsResult: false);
    try {
      return OfficeMacro(name: name, format: context.format, steps: steps);
    } on OfficeMacroException catch (error) {
      if (error.code == 'limit_exceeded') {
        context.limit(procedure.name, error.message);
      }
      rethrow;
    }
  }

  Object _invoke(
    _Procedure procedure,
    List<Object> arguments,
    _Token token, {
    required bool needsResult,
  }) {
    _tick(token);
    if (activeCalls >= _maxCalls) {
      context.limit(token, 'Procedure calls exceed $_maxCalls active frames.');
    }
    final callerValues = values;
    final callerSymbols = symbols;
    final callerWithValues = withValues;
    final callerArrayElements = activeArrayElements;
    final callerArrayStringUnits = activeArrayStringUnits;
    activeCalls++;
    symbols = checker.locals[procedure.name.lower]!;
    values = <String, Object>{...globalValues};
    withValues = <Object>[];
    try {
      for (final entry in symbols.entries) {
        _tick(entry.value.token);
        if (!globalValues.containsKey(entry.key)) {
          values[entry.key] = _default(entry.value.type);
        }
      }
      for (var index = 0; index < arguments.length; index++) {
        final parameter = procedure.parameters[index];
        values[parameter.name.lower] = _convert(
          parameter.type,
          arguments[index],
          token,
        );
      }
      _execute(procedure.body);
      if (needsResult) {
        return values[procedure.name.lower]!;
      }
      return const _Uninitialized();
    } finally {
      values = callerValues;
      symbols = callerSymbols;
      withValues = callerWithValues;
      activeArrayElements = callerArrayElements;
      activeArrayStringUnits = callerArrayStringUnits;
      activeCalls--;
    }
  }

  Object _default(_Declared type) => switch (type) {
    _Declared.long => 0,
    _Declared.doubleType => 0.0,
    _Declared.string => '',
    _Declared.boolean => false,
    _Declared.variant => _VariantState.empty,
    _ => const _Uninitialized(),
  };

  void _initialize(_Declaration declaration) {
    if (declaration.isDynamicArray) {
      values[declaration.token.lower] = _Array.unallocated(declaration.type);
      return;
    }
    if (symbols[declaration.token.lower]!.array case final bounds?) {
      final count = bounds.length;
      if (count > _maxActiveArrayElements - activeArrayElements) {
        context.limit(
          declaration.token,
          'Active procedures may contain at most $_maxActiveArrayElements array elements.',
        );
      }
      _charge(count, declaration.token);
      activeArrayElements += count;
      values[declaration.token.lower] = _Array(
        bounds,
        declaration.type,
        List<Object>.filled(count, _default(declaration.type)),
      );
      return;
    }
    if (declaration.initializer != null) {
      values[declaration.token.lower] = _convert(
        declaration.type,
        _evaluate(declaration.initializer!),
        declaration.token,
      );
    }
  }

  void _tick(_Token token) {
    _charge(1, token);
  }

  void _charge(int amount, _Token token) {
    if (amount > _maxWork - work) {
      context.limit(
        token,
        'Compilation exceeds $_maxWork work units (evaluation, statements, array elements, and copied string units).',
      );
    }
    work += amount;
  }

  _ExitKind? _execute(List<_Statement> statements) {
    // Block nesting must not multiply the host call stack by procedure depth.
    // Explicit continuations also identify exactly which loop owns an exit.
    final frames = <_ExecutionFrame>[_BodyFrame(statements)];
    final initialWithDepth = withValues.length;
    try {
      while (frames.isNotEmpty) {
        final frame = frames.last;
        if (frame is _WithFrame) {
          frames.removeLast();
          withValues.removeLast();
          continue;
        }
        if (frame is _ForFrame) {
          if (frame.afterBody) {
            frame.counter += frame.step;
            values[frame.loop.counter.lower] = _convert(
              frame.type,
              frame.counter,
              frame.loop.counter,
            );
          }
          if (frame.remaining == 0) {
            frames.removeLast();
            continue;
          }
          _tick(frame.loop.token);
          frame.remaining--;
          frame.afterBody = true;
          frames.add(_BodyFrame(frame.loop.body));
          continue;
        }
        if (frame is _ForEachFrame) {
          if (frame.index == frame.length) {
            frames.removeLast();
            _releaseArrayLock(frame);
            continue;
          }
          _tick(frame.loop.token);
          final collection = frame.collection;
          final Object value;
          if (collection is _Array) {
            value = _initialized(
              collection.elements[frame.index],
              frame.loop.counter,
            );
          } else {
            final range = collection as _Range;
            final columns = range.maxColumn - range.minColumn + 1;
            final row = range.minRow + frame.index ~/ columns;
            final column = range.minColumn + frame.index % columns;
            value = _Range(range.sheet, row, column, row, column);
          }
          values[frame.loop.counter.lower] = value;
          frame.index++;
          frames.add(_BodyFrame(frame.loop.body));
          continue;
        }
        if (frame is _ConditionalFrame) {
          final loop = frame.loop;
          if (frame.afterBody && loop.testAfter && !_continues(loop)) {
            frames.removeLast();
            continue;
          }
          // Charge every attempt, including unconditional empty loops and
          // failed pretests. Procedure calls share this same budget.
          _tick(loop.token);
          if (!loop.testAfter && !_continues(loop)) {
            frames.removeLast();
            continue;
          }
          frame.afterBody = true;
          frames.add(_BodyFrame(loop.body));
          continue;
        }
        final body = frame as _BodyFrame;
        if (body.position == body.statements.length) {
          frames.removeLast();
          continue;
        }
        final statement = body.statements[body.position++];
        _tick(statement.token);
        switch (statement) {
          case _Declaration():
            _initialize(statement);
          case _Resize():
            for (final target in statement.targets) {
              _resize(target, preserve: statement.preserve);
            }
          case _Erase():
            for (final target in statement.targets) {
              _erase(target);
            }
          case _Assignment():
            if (statement.target case final _Call target) {
              final array = values[target.token.lower]! as _Array;
              final index = _arrayOffset(array, target.arguments.single);
              final value = _evaluate(statement.value);
              _writeArrayElement(array, index, value, target.token);
              break;
            }
            final value = _evaluate(statement.value);
            if (statement.target case final _Name name) {
              values[name.token.lower] = _convert(
                symbols[name.token.lower]!.type,
                value,
                name.token,
              );
            } else {
              _write(statement.target as _Member, value);
            }
          case _Clear():
            final range = _evaluate(statement.target.receiver) as _Range;
            _emitRange(range, 'cellValue', <String, Object?>{
              'value': null,
            }, statement.token);
          case _InsertBefore():
            final range = _evaluate(statement.target.receiver) as _WordRange;
            final value = _evaluate(statement.target.arguments!.single);
            final text = _wordText(value, statement.target.token);
            _emitWord(range, 'replaceText', <String, Object?>{
              'start': 0,
              'end': 0,
              'text': text,
            }, statement.target.token);
          case _With():
            withValues.add(_evaluate(statement.target));
            frames.add(_WithFrame());
            frames.add(_BodyFrame(statement.body));
          case _If():
            var selected = statement.otherwise;
            for (final branch in statement.branches) {
              if (_condition(_evaluate(branch.$1), branch.$1.token)) {
                selected = branch.$2;
                break;
              }
            }
            frames.add(_BodyFrame(selected));
          case _ConditionalLoop():
            frames.add(_ConditionalFrame(statement));
          case _Select():
            final selector = _evaluate(statement.selector);
            var selected = statement.otherwise;
            var matched = false;
            for (final branch in statement.branches) {
              for (final match in branch.matches) {
                if (_caseMatches(selector, match)) {
                  selected = branch.body;
                  matched = true;
                  break;
                }
              }
              if (matched) break;
            }
            frames.add(_BodyFrame(selected));
          case _For():
            frames.add(_startFor(statement));
          case _ForEach():
            frames.add(_startForEach(statement));
          case _Invoke():
            final arguments = <Object>[
              for (final argument in statement.arguments) _evaluate(argument),
            ];
            _invoke(
              module.procedures[statement.token.lower]!,
              arguments,
              statement.token,
              needsResult: false,
            );
          case _Exit():
            if (!_leaveLoop(frames, statement.kind)) return statement.kind;
        }
      }
      return null;
    } finally {
      // Also restore context if expression evaluation or a budget check fails.
      withValues.length = initialWithDepth;
      for (final frame in frames) {
        _releaseArrayLock(frame);
      }
    }
  }

  _ForFrame _startFor(_For loop) {
    final start = _loopInteger(_evaluate(loop.start), loop.start.token);
    final end = _loopInteger(_evaluate(loop.end), loop.end.token);
    final step = _loopInteger(_evaluate(loop.step), loop.step.token);
    if (step == 0) {
      context.unsupported(
        loop.step.token,
        'Step 0 is unsupported because it does not bound iteration.',
      );
    }
    final count = step > 0
        ? (start > end ? 0 : (end - start) ~/ step + 1)
        : (start < end ? 0 : (start - end) ~/ -step + 1);
    if (count > _maxWork - work) {
      context.limit(
        loop.token,
        'For loop exceeds the remaining compilation work budget.',
      );
    }
    final type = symbols[loop.counter.lower]!.type;
    values[loop.counter.lower] = _convert(type, start, loop.counter);
    return _ForFrame(loop, type, start, step, count);
  }

  _ForEachFrame _startForEach(_ForEach loop) {
    final collection = _evaluate(loop.collection);
    final int length;
    if (collection is _Array) {
      _allocatedBounds(collection, loop.collection.token);
      length = collection.elements.length;
    } else {
      final range = collection as _Range;
      length =
          (range.maxRow - range.minRow + 1) *
          (range.maxColumn - range.minColumn + 1);
    }
    if (length > _maxWork - work) {
      context.limit(
        loop.token,
        'For Each exceeds the remaining compilation work budget.',
      );
    }
    if (collection is _Array) collection.locks++;
    return _ForEachFrame(loop, collection, length);
  }

  void _releaseArrayLock(_ExecutionFrame frame) {
    if (frame is _ForEachFrame && frame.collection is _Array) {
      (frame.collection as _Array).locks--;
    }
  }

  bool _leaveLoop(List<_ExecutionFrame> frames, _ExitKind kind) {
    if (kind != _ExitKind.forLoop && kind != _ExitKind.doLoop) return false;
    while (frames.isNotEmpty) {
      final frame = frames.removeLast();
      if (frame is _WithFrame) withValues.removeLast();
      _releaseArrayLock(frame);
      if (kind == _ExitKind.forLoop &&
          (frame is _ForFrame || frame is _ForEachFrame)) {
        return true;
      }
      if (kind == _ExitKind.doLoop &&
          frame is _ConditionalFrame &&
          frame.loop.isDo) {
        return true;
      }
    }
    return false;
  }

  bool _continues(_ConditionalLoop loop) {
    final condition = loop.condition;
    if (condition == null) return true;
    return _condition(_evaluate(condition), condition.token) != loop.until;
  }

  bool _caseMatches(Object selector, _CaseMatch match) {
    _tick(match.token);
    final first = _evaluate(match.first);
    final last = match.last;
    if (last == null) {
      return _condition(
        _compare(match.operator, selector, first, match.token),
        match.token,
      );
    }
    _rangeValue(selector, match.token);
    _rangeValue(first, match.first.token);
    final lower = _compare('>=', selector, first, match.token);
    // VBA defines a range as two comparisons joined by eager And. Evaluate
    // the upper endpoint even when the lower comparison does not match.
    final upperValue = _evaluate(last);
    _rangeValue(upperValue, last.token);
    final upper = _compare('<=', selector, upperValue, last.token);
    return _condition(lower, match.token) && _condition(upper, match.token);
  }

  void _rangeValue(Object value, _Token token) {
    if (value is! num && value is! String && value is! _VariantState) {
      context.type(token, 'Case To ranges require numbers or strings.');
    }
  }

  Object _evaluate(_Expr expression) {
    _tick(expression.token);
    switch (expression) {
      case _Literal():
        return expression.value;
      case _Name():
        final constant = context.constants[expression.token.lower];
        if (constant != null) return constant;
        if (context.isPowerPoint) {
          if (expression.token.lower == 'activepresentation') {
            return const _Presentation();
          }
          if (expression.token.lower == 'application') {
            return const _PowerPointApplication();
          }
        }
        if (context.isWord) {
          if (expression.token.lower == 'thisdocument') {
            return const _WordDocument();
          }
        } else if (context.isExcel &&
            expression.token.lower == 'thisworkbook') {
          return const _Workbook();
        }
        final value = values[expression.token.lower]!;
        return _initialized(value, expression.token);
      case _WithValue():
        return withValues.last;
      case _Call():
        if (values[expression.token.lower] case final _Array array) {
          return _initialized(
            array.elements[_arrayOffset(array, expression.arguments.single)],
            expression.token,
          );
        }
        if (expression.token.lower == 'lbound' ||
            expression.token.lower == 'ubound') {
          final array = _evaluate(expression.arguments.first) as _Array;
          final bounds = _allocatedBounds(array, expression.token);
          if (expression.arguments.length == 2) {
            final dimension = expression.arguments[1];
            if (_integer(_evaluate(dimension), dimension.token) != 1) {
              context.fail(
                dimension.token,
                'vba_subscript_out_of_range',
                'One-dimensional arrays require dimension 1.',
              );
            }
          }
          return expression.token.lower == 'lbound'
              ? bounds.lower
              : bounds.upper;
        }
        final arguments = <Object>[
          for (final argument in expression.arguments) _evaluate(argument),
        ];
        if (_stringIntrinsics.contains(expression.token.lower)) {
          return _stringIntrinsic(expression, arguments);
        }
        if (_variantIntrinsics.contains(expression.token.lower)) {
          return _variantIntrinsic(expression, arguments.single);
        }
        if (expression.token.lower == 'worksheets') {
          return _sheet(arguments.single, expression.token);
        }
        if (expression.token.lower == 'rgb') {
          return _rgb(arguments, expression.token);
        }
        return _invoke(
          module.procedures[expression.token.lower]!,
          arguments,
          expression.token,
          needsResult: true,
        );
      case _Member():
        final receiver = _evaluate(expression.receiver);
        final arguments = <Object>[
          for (final argument in expression.arguments ?? const <_Expr>[])
            _evaluate(argument),
        ];
        if (context.isPowerPoint) {
          return _evaluatePowerPointMember(expression, receiver, arguments);
        }
        if (context.isWord) {
          if (receiver is _WordDocument) {
            final index = _integer(arguments.single, expression.token);
            if (index < 1) {
              context.type(
                expression.token,
                'Paragraphs requires a positive one-based index.',
              );
            }
            return _WordParagraph(index - 1);
          }
          if (receiver is _WordParagraph) return _WordRange(receiver);
          final range = receiver as _WordRange;
          return expression.token.lower == 'font'
              ? _WordFont(range)
              : _WordParagraphFormat(range);
        }
        if (receiver is _Workbook) {
          return _sheet(arguments.single, expression.token);
        }
        if (receiver is _Worksheet) {
          if (expression.token.lower == 'range') {
            return _range(
              receiver,
              _string(arguments.single, expression.token),
              expression.token,
            );
          }
          final row = _integer(arguments[0], expression.token);
          final column = _integer(arguments[1], expression.token);
          _coordinates(row, column, expression.token);
          return _Range(receiver, row, column, row, column);
        }
        final range = receiver as _Range;
        if (expression.token.lower == 'row') return range.minRow;
        if (expression.token.lower == 'column') return range.minColumn;
        return expression.token.lower == 'font'
            ? _Font(range)
            : _Interior(range);
      case _Unary():
        final value = _evaluate(expression.operand);
        if (value == _VariantState.nullValue) return value;
        if (expression.token.lower == 'not') {
          return !_boolean(value, expression.token);
        }
        final number = _arithmeticNumber(value, expression.token);
        return _finite(
          expression.token.lower == '-' ? -number : number,
          expression.token,
        );
      case _Binary():
        // VBA And/Or are eager, so both operands are evaluated.
        final left = _evaluate(expression.left);
        final right = _evaluate(expression.right);
        final operator = expression.token.lower;
        if (operator == '&') {
          if (left == _VariantState.nullValue &&
              right == _VariantState.nullValue) {
            return _VariantState.nullValue;
          }
          final a = _scalarString(left, expression.token);
          final b = _scalarString(right, expression.token);
          if (a.length > _maxString - b.length) {
            context.limit(
              expression.token,
              'Concatenation exceeds $_maxString code units.',
            );
          }
          return a + b;
        }
        if (const <String>{'and', 'or', 'xor'}.contains(operator)) {
          return _logical(operator, left, right, expression.token);
        }
        if (_comparisonOperators.contains(operator)) {
          return _compare(operator, left, right, expression.token);
        }
        // Use floating-point intermediates before checking the safe-integer
        // magnitude. Native Dart int multiplication can wrap before a later
        // range check; JS has no equivalent 64-bit integer arithmetic.
        // Validate non-Null operands before propagation: Null does not admit
        // unsupported String/Boolean arithmetic into this bounded dialect.
        final a = left == _VariantState.nullValue
            ? null
            : _arithmeticNumber(left, expression.token).toDouble();
        final b = right == _VariantState.nullValue
            ? null
            : _arithmeticNumber(right, expression.token).toDouble();
        if (a == null || b == null) return _VariantState.nullValue;
        if (operator == '/' && b == 0) {
          context.fail(
            expression.token,
            'vba_arithmetic_error',
            'Division by zero.',
          );
        }
        final result = _finite(switch (operator) {
          '+' => a + b,
          '-' => a - b,
          '*' => a * b,
          _ => a / b,
        }, expression.token);
        return result == result.truncateToDouble() ? result.toInt() : result;
    }
  }

  Object _evaluatePowerPointMember(
    _Member expression,
    Object receiver,
    List<Object> arguments,
  ) {
    if (receiver is _PowerPointApplication) return const _Presentation();
    if (receiver is _Presentation || receiver is _Slides) {
      if (expression.arguments == null) return const _Slides();
      return _Slide(_powerPointIndex(arguments.single, expression.token));
    }
    if (receiver is _Slide || receiver is _Shapes) {
      final slide = receiver is _Slide ? receiver : (receiver as _Shapes).slide;
      if (expression.arguments == null) return _Shapes(slide);
      final value = arguments.single;
      final Object selector = value is String
          ? _powerPointText(value, expression.token, name: true)
          : _powerPointIndex(value, expression.token);
      return _Shape(slide, selector);
    }
    if (receiver is _Shape) return _TextFrame(receiver);
    if (receiver is _TextFrame) return _TextRange(receiver.shape);
    if (receiver is _TextRange) {
      return expression.token.lower == 'font'
          ? _PowerPointFont(receiver)
          : _PowerPointParagraphFormat(receiver);
    }
    if (receiver is _PowerPointFont) return _PowerPointColor(receiver.range);
    context.unsupported(expression.token, 'Unsupported PowerPoint binding.');
  }

  int _powerPointIndex(Object value, _Token token) {
    final index = _integer(value, token);
    if (index < 1 || index > 2147483647) {
      context.type(
        token,
        'A positive one-based signed Long index is required.',
      );
    }
    return index - 1;
  }

  Object _compare(String operator, Object left, Object right, _Token token) {
    if (left == _VariantState.nullValue || right == _VariantState.nullValue) {
      return _VariantState.nullValue;
    }
    if (left == _VariantState.empty) left = _emptyComparisonValue(right);
    if (right == _VariantState.empty) right = _emptyComparisonValue(left);
    final int comparison;
    if (left is num && right is num) {
      // Dart compareTo distinguishes signed zero; VBA numeric equality and
      // ordering do not distinguish -0.0 from 0.0.
      comparison = left == right ? 0 : left.compareTo(right);
    } else if (left is String && right is String) {
      comparison = left.compareTo(right);
    } else if (left is bool && right is bool) {
      // VBA True is -1 and False is 0 when ordering Booleans.
      comparison = (left ? -1 : 0).compareTo(right ? -1 : 0);
    } else {
      context.type(token, 'Comparisons require matching scalar types.');
    }
    return switch (operator) {
      '=' => comparison == 0,
      '<>' => comparison != 0,
      '<' => comparison < 0,
      '>' => comparison > 0,
      '<=' => comparison <= 0,
      _ => comparison >= 0,
    };
  }

  Object _emptyComparisonValue(Object other) => other is String
      ? ''
      : other is bool
      ? false
      : 0;

  num _arithmeticNumber(Object value, _Token token) =>
      value == _VariantState.empty ? 0 : _number(value, token);

  Object _logical(String operator, Object left, Object right, _Token token) {
    final a = left == _VariantState.nullValue ? null : _boolean(left, token);
    final b = right == _VariantState.nullValue ? null : _boolean(right, token);
    if (operator == 'and') {
      if (a == false || b == false) return false;
      return a == null || b == null ? _VariantState.nullValue : true;
    }
    if (operator == 'or') {
      if (a == true || b == true) return true;
      return a == null || b == null ? _VariantState.nullValue : false;
    }
    return a == null || b == null ? _VariantState.nullValue : a != b;
  }

  bool _condition(Object value, _Token token) =>
      value is _VariantState ? false : _boolean(value, token);

  Object _initialized(Object value, _Token token) {
    if (value is _Uninitialized) {
      context.unsupported(
        token,
        'Uninitialized objects (Nothing) are unsupported; bind with Set before reading.',
      );
    }
    return value;
  }

  int _arrayOffset(_Array array, _Expr expression) {
    final index = _integer(_evaluate(expression), expression.token);
    final bounds = _allocatedBounds(array, expression.token);
    if (index < bounds.lower || index > bounds.upper) {
      context.fail(
        expression.token,
        'vba_subscript_out_of_range',
        'Array subscript $index is outside ${bounds.lower}..${bounds.upper}.',
      );
    }
    return index - bounds.lower;
  }

  void _writeArrayElement(_Array array, int index, Object value, _Token token) {
    final converted = _convert(array.type, value, token);
    final previous = array.elements[index];
    final previousUnits = previous is String ? previous.length : 0;
    final nextUnits = converted is String ? converted.length : 0;
    if (nextUnits >
        _maxActiveArrayStringUnits - activeArrayStringUnits + previousUnits) {
      context.limit(
        token,
        'Strings in active array elements exceed $_maxActiveArrayStringUnits UTF-16 code units.',
      );
    }
    // Count occupied string units per slot, even when Dart shares a String
    // object. This portable bound is independent of host allocation details.
    activeArrayStringUnits += nextUnits - previousUnits;
    array.stringUnits += nextUnits - previousUnits;
    array.elements[index] = converted;
  }

  _ArrayBounds _allocatedBounds(_Array array, _Token token) =>
      array.bounds ??
      context.fail(
        token,
        'vba_subscript_out_of_range',
        'The dynamic array has no allocated bounds; use ReDim before accessing it.',
      );

  void _unlocked(_Array array, _Token token) {
    if (array.locks != 0) {
      context.fail(
        token,
        'vba_array_locked',
        'An array being enumerated by For Each cannot be resized or erased.',
      );
    }
  }

  int _dynamicBound(_Expr expression) {
    final bound = _integer(_evaluate(expression), expression.token);
    if (bound < -2147483648 || bound > 2147483647) {
      context.type(
        expression.token,
        'Array bounds must be signed 32-bit integers.',
      );
    }
    return bound;
  }

  void _resize(_ResizeTarget target, {required bool preserve}) {
    final array = values[target.name.lower]! as _Array;
    _unlocked(array, target.name);
    // Each bound is evaluated exactly once, left to right. Bound helpers use
    // isolated locals and share the caller's compilation budget.
    final lower = _dynamicBound(target.bounds.$1);
    final upper = _dynamicBound(target.bounds.$2);
    if (lower > upper) {
      context.type(
        target.name,
        'An array lower bound exceeds its upper bound.',
      );
    }
    final bounds = _ArrayBounds(lower, upper);
    final count = bounds.length;
    if (count > _maxArrayElements) {
      context.limit(
        target.name,
        'An array may contain at most $_maxArrayElements elements.',
      );
    }
    if (preserve && array.bounds != null && lower != array.bounds!.lower) {
      context.fail(
        target.name,
        'vba_subscript_out_of_range',
        'ReDim Preserve cannot change the lower bound.',
      );
    }
    final oldCount = array.elements.length;
    if (count > _maxActiveArrayElements - activeArrayElements + oldCount) {
      context.limit(
        target.name,
        'Active procedures may contain at most $_maxActiveArrayElements array elements.',
      );
    }
    final copied = preserve ? (oldCount < count ? oldCount : count) : 0;
    // Charge allocation, retirement and preserved copies before allocating.
    // Repeated small resizes cannot reset or escape the aggregate work limit.
    _charge(count + oldCount + copied, target.name);
    final elements = List<Object>.filled(count, _default(array.type));
    var stringUnits = 0;
    for (var index = 0; index < copied; index++) {
      final value = array.elements[index];
      elements[index] = value;
      if (value is String) stringUnits += value.length;
    }
    activeArrayElements += count - oldCount;
    activeArrayStringUnits += stringUnits - array.stringUnits;
    array.bounds = bounds;
    array.elements = elements;
    array.stringUnits = stringUnits;
  }

  void _erase(_Token target) {
    final array = values[target.lower]! as _Array;
    _unlocked(array, target);
    final count = array.elements.length;
    // An unallocated target still consumes work, including in a target list.
    _charge(count + 1, target);
    activeArrayStringUnits -= array.stringUnits;
    array.stringUnits = 0;
    if (symbols[target.lower]!.isDynamicArray) {
      activeArrayElements -= count;
      array.bounds = null;
      array.elements = <Object>[];
    } else {
      array.elements = List<Object>.filled(count, _default(array.type));
    }
  }

  Object _convert(_Declared type, Object value, _Token token) {
    final typedScalar =
        type == _Declared.long ||
        type == _Declared.doubleType ||
        type == _Declared.string ||
        type == _Declared.boolean;
    if (typedScalar && value == _VariantState.nullValue) {
      _invalidNull(token);
    }
    if (typedScalar && value == _VariantState.empty) return _default(type);
    switch (type) {
      case _Declared.long:
        final number = _integer(value, token);
        if (number < -2147483648 || number > 2147483647) {
          context.type(
            token,
            'Long assignment overflows its signed 32-bit range.',
          );
        }
        return number;
      case _Declared.doubleType:
        return _number(value, token).toDouble();
      case _Declared.string:
        return _string(value, token);
      case _Declared.boolean:
        return _boolean(value, token);
      case _Declared.variant:
        if (value is! String &&
            value is! num &&
            value is! bool &&
            value is! _VariantState) {
          context.type(token, 'Variant bindings support scalar values only.');
        }
        return value is num ? _finite(value, token) : value;
      case _Declared.worksheet:
        if (value is! _Worksheet) {
          context.type(token, 'Set requires a Worksheet.');
        }
        return value;
      case _Declared.range:
        if (context.isWord ? value is! _WordRange : value is! _Range) {
          context.type(token, 'Set requires a Range.');
        }
        return value;
      case _Declared.document:
        if (value is! _WordDocument) {
          context.type(token, 'Set requires a Document.');
        }
        return value;
      case _Declared.paragraph:
        if (value is! _WordParagraph) {
          context.type(token, 'Set requires a Paragraph.');
        }
        return value;
      case _Declared.presentation:
        if (value is! _Presentation) {
          context.type(token, 'Set requires a Presentation.');
        }
        return value;
      case _Declared.slide:
        if (value is! _Slide) {
          context.type(token, 'Set requires a Slide.');
        }
        return value;
      case _Declared.shape:
        if (value is! _Shape) {
          context.type(token, 'Set requires a Shape.');
        }
        return value;
      case _Declared.textRange:
        if (value is! _TextRange) {
          context.type(token, 'Set requires a TextRange.');
        }
        return value;
    }
  }

  Never _invalidNull(_Token token) => context.fail(
    token,
    'vba_invalid_use_of_null',
    'Null cannot be converted to a typed scalar or published as a cell value; handle it explicitly with IsNull.',
  );

  Object _variantIntrinsic(_Call expression, Object value) {
    final name = expression.token.lower;
    final token = expression.arguments.single.token;
    if (name == 'isempty') return value == _VariantState.empty;
    if (name == 'isnull') return value == _VariantState.nullValue;
    if (name == 'cvar') return _convert(_Declared.variant, value, token);
    if (value == _VariantState.nullValue) _invalidNull(token);
    if (name == 'cstr') {
      if (value == _VariantState.empty) return '';
      if (value is String) {
        // Charge even an identity conversion: callers must not bypass the
        // shared copy-work limit by repeatedly converting a large String.
        _charge(value.length, token);
        return value;
      }
      if (value is bool) {
        _charge(value ? 4 : 5, token);
        return value ? 'True' : 'False';
      }
      return _invariantNumberString(_number(value, token), token);
    }
    if (name == 'cbool') {
      if (value == _VariantState.empty) return false;
      if (value is bool) return value;
      if (value is String) {
        final text = _conversionText(value, token);
        final lower = text.toLowerCase();
        if (lower == 'true') return true;
        if (lower == 'false') return false;
        return _parseConversionNumber(text, token) != 0;
      }
      return _number(value, token) != 0;
    }
    final number = _conversionNumber(value, token);
    if (name == 'cdbl') return number.toDouble();
    // Explicit CLng follows ties-to-even. Ordinary Long assignment still
    // requires an exact integer and does not acquire this coercion.
    final lower = number.floor();
    final fraction = number - lower;
    final rounded = fraction < 0.5
        ? lower
        : fraction > 0.5
        ? lower + 1
        : lower.isEven
        ? lower
        : lower + 1;
    if (rounded < -2147483648 || rounded > 2147483647) {
      context.type(
        token,
        'CLng overflows its signed 32-bit range after rounding.',
      );
    }
    return rounded;
  }

  num _conversionNumber(Object value, _Token token) {
    if (value == _VariantState.empty) return 0;
    if (value is bool) return value ? -1 : 0;
    if (value is String) {
      return _parseConversionNumber(_conversionText(value, token), token);
    }
    return _number(value, token);
  }

  String _conversionText(String value, _Token token) {
    // Charge before scanning, substring allocation, case folding or parsing.
    _charge(value.length, token);
    bool whitespace(int unit) => unit == 32 || (unit >= 9 && unit <= 13);
    var start = 0;
    var end = value.length;
    while (start < end && whitespace(value.codeUnitAt(start))) {
      start++;
    }
    while (end > start && whitespace(value.codeUnitAt(end - 1))) {
      end--;
    }
    return value.substring(start, end);
  }

  static final _conversionNumberPattern = RegExp(
    r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$',
  );

  num _parseConversionNumber(String text, _Token token) {
    // This deliberately accepts invariant ASCII decimal/exponent syntax only.
    // Host locale, currency/grouping separators and base prefixes are absent.
    final match = _conversionNumberPattern.firstMatch(text);
    if (match == null || match.end != text.length) {
      context.type(
        token,
        'Explicit numeric conversion requires an invariant ASCII decimal or exponent string.',
      );
    }
    final value = double.tryParse(text);
    if (value == null) {
      context.type(token, 'The string is not a supported numeric value.');
    }
    return _finite(value, token);
  }

  String _invariantNumberString(num value, _Token token) {
    if (value == value.truncateToDouble()) {
      final integer = value.toInt();
      // Portable integers have at most 16 decimal digits plus a sign.
      _charge(17, token);
      return integer.toString();
    }
    final magnitude = value.abs().toDouble();
    var scientific = '';
    // Find the fewest significant digits that round-trip to this binary64
    // value. Using one explicit formatting algorithm avoids Dart/JavaScript
    // defaults choosing different fixed/scientific cutoffs. Each candidate
    // is bounded (17 digits, exponent, sign), charged before allocation.
    for (var precision = 1; precision <= 17; precision++) {
      _charge(32, token);
      scientific = magnitude.toStringAsExponential(precision - 1);
      if (double.parse(scientific) == magnitude) break;
    }
    final separator = scientific.indexOf('e');
    final exponent = int.parse(scientific.substring(separator + 1));
    var digits = scientific.substring(0, separator).replaceAll('.', '');
    while (digits.length > 1 && digits.endsWith('0')) {
      digits = digits.substring(0, digits.length - 1);
    }
    final sign = value < 0 ? '-' : '';
    if (exponent < -6) {
      final length =
          sign.length +
          digits.length +
          (digits.length > 1 ? 1 : 0) +
          1 +
          exponent.toString().length;
      _charge(length, token);
      final mantissa = digits.length == 1
          ? digits
          : '${digits[0]}.${digits.substring(1)}';
      return '$sign${mantissa}e$exponent';
    }
    final point = exponent + 1;
    if (point <= 0) {
      _charge(sign.length + 2 - point + digits.length, token);
      return '${sign}0.${'0' * -point}$digits';
    }
    if (point >= digits.length) {
      _charge(sign.length + point, token);
      return '$sign$digits${'0' * (point - digits.length)}';
    }
    _charge(sign.length + digits.length + 1, token);
    return '$sign${digits.substring(0, point)}.${digits.substring(point)}';
  }

  num _finite(num value, _Token token) {
    if (!value.isFinite || value.abs() > _maxExactInteger) {
      context.limit(
        token,
        'Arithmetic exceeds finite, portable numeric bounds.',
      );
    }
    return value;
  }

  num _number(Object value, _Token token) {
    if (value is! num) {
      context.type(
        token,
        'A number is required; scalar coercions are unsupported.',
      );
    }
    return _finite(value, token);
  }

  int _integer(Object value, _Token token) {
    final number = _number(value, token);
    if (number.abs() > _maxExactInteger ||
        number != number.truncateToDouble()) {
      context.type(
        token,
        'An exact integer is required; rounding is unsupported.',
      );
    }
    return number.toInt();
  }

  int _loopInteger(Object value, _Token token) {
    final number = _integer(value, token);
    if (number < -2147483648 || number > 2147483647) {
      context.type(
        token,
        'For bounds and Step must be signed 32-bit integers.',
      );
    }
    return number;
  }

  String _string(Object value, _Token token) {
    if (value is! String) {
      context.type(
        token,
        'A string is required; scalar coercions are unsupported.',
      );
    }
    return value;
  }

  Object _stringIntrinsic(_Call expression, List<Object> arguments) {
    final text = _string(arguments.first, expression.arguments.first.token);
    final name = expression.token.lower;
    if (name == 'len') return text.length;

    final second = _stringIndex(
      arguments[1],
      expression.arguments[1].token,
      isStart: name == r'mid$',
    );
    // Validate an explicit length even when start is beyond the input. All
    // argument expressions have already been evaluated once, in source order.
    final requested = name == r'mid$'
        ? arguments.length == 3
              ? _stringIndex(arguments[2], expression.arguments[2].token)
              : text.length
        : second;
    final start = name == r'mid$' ? second - 1 : 0;
    final available = start < text.length ? text.length - start : 0;
    final count = requested < available ? requested : available;
    // Charge the actual result, including full-input slices, before allocating.
    // Dart String indices are UTF-16 units on both the VM and JavaScript.
    _charge(count, expression.token);
    if (count == 0) return '';
    final offset = name == r'right$' ? text.length - count : start;
    return text.substring(offset, offset + count);
  }

  int _stringIndex(Object value, _Token token, {bool isStart = false}) {
    final index = _integer(value, token);
    final minimum = isStart ? 1 : 0;
    if (index < minimum || index > 2147483647) {
      context.type(
        token,
        isStart
            ? 'String start must be a one-based signed 32-bit integer.'
            : 'String length must be a nonnegative signed 32-bit integer.',
      );
    }
    return index;
  }

  bool _boolean(Object value, _Token token) {
    if (value is! bool) {
      context.type(
        token,
        'A Boolean is required; numeric coercions and bitwise logic are unsupported.',
      );
    }
    return value;
  }

  String _scalarString(Object value, _Token token) {
    if (value is _VariantState) return '';
    if (value is String) return value;
    if (value is bool) return value ? 'True' : 'False';
    if (value is num) {
      return value == value.truncateToDouble()
          ? value.toInt().toString()
          : value.toString();
    }
    context.type(token, 'Concatenation requires scalar operands.');
  }

  _Worksheet _sheet(Object value, _Token token) {
    if (value is String) {
      if (value.isEmpty || value.length > 31) {
        context.type(token, 'Worksheet names must contain 1..31 code units.');
      }
      return _Worksheet(value);
    }
    final index = _integer(value, token);
    if (index < 1 || index > 2147483647) {
      context.type(token, 'Worksheet indexes are one-based positive integers.');
    }
    return _Worksheet(index - 1);
  }

  int _rgb(List<Object> arguments, _Token token) {
    final components = <int>[];
    for (final argument in arguments) {
      final number = _integer(argument, token);
      if (number < 0) context.type(token, 'RGB components cannot be negative.');
      components.add(number > 255 ? 255 : number);
    }
    return components[0] + components[1] * 256 + components[2] * 65536;
  }

  void _coordinates(int row, int column, _Token token) {
    if (row < 1 || row > 1048576 || column < 1 || column > 16384) {
      context.type(token, 'Cell coordinates must be within A1:XFD1048576.');
    }
  }

  _Range _range(_Worksheet sheet, String address, _Token token) {
    if (address.length > 32) {
      context.unsupported(
        token,
        'Only bounded A1 cell or rectangular addresses are supported.',
      );
    }
    final match = RegExp(
      r'^\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6})(?::\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6}))?$',
    ).firstMatch(address);
    if (match == null) {
      context.unsupported(
        token,
        'Use A1 cells or rectangles; names, unions, whole rows/columns, and qualified strings are unsupported.',
      );
    }
    int column(String letters) {
      var result = 0;
      for (final code in letters.toUpperCase().codeUnits) {
        result = result * 26 + code - 64;
      }
      return result;
    }

    final row1 = int.parse(match.group(2)!);
    final col1 = column(match.group(1)!);
    final row2 = int.parse(match.group(4) ?? match.group(2)!);
    final col2 = column(match.group(3) ?? match.group(1)!);
    _coordinates(row1, col1, token);
    _coordinates(row2, col2, token);
    return _Range(
      sheet,
      row1 < row2 ? row1 : row2,
      col1 < col2 ? col1 : col2,
      row1 > row2 ? row1 : row2,
      col1 > col2 ? col1 : col2,
    );
  }

  void _write(_Member target, Object value) {
    final receiver = _evaluate(target.receiver);
    final property = target.token.lower;
    if (context.isPowerPoint) {
      _writePowerPoint(receiver, property, value, target.token);
      return;
    }
    if (context.isWord) {
      _writeWord(receiver, property, value, target.token);
      return;
    }
    if (receiver is _Range) {
      if (property == 'formula') {
        final formula = _string(value, target.token);
        if (!formula.startsWith('=') || formula.length == 1) {
          context.unsupported(
            target.token,
            'Formula assignments require a nonempty formula beginning with =.',
          );
        }
        _emitRange(receiver, 'cellFormula', <String, Object?>{
          'formula': formula,
        }, target.token);
      } else {
        if (value == _VariantState.nullValue) _invalidNull(target.token);
        if (value is! String &&
            value is! num &&
            value is! bool &&
            value != _VariantState.empty) {
          context.type(
            target.token,
            'Value/Value2 supports scalar strings, numbers, Booleans, and Empty.',
          );
        }
        // Excel can reinterpret these as formulas. Do not silently preserve a
        // literal where native Excel would execute a formula.
        if (value is String && value.startsWith('=')) {
          context.unsupported(
            target.token,
            'Use Formula for strings beginning with =.',
          );
        }
        _emitRange(receiver, 'cellValue', <String, Object?>{
          'value': value == _VariantState.empty ? null : value,
        }, target.token);
      }
    } else if (receiver is _Font) {
      final String field;
      final Object normalized;
      if (property == 'bold') {
        field = 'bold';
        normalized = _boolean(value, target.token);
      } else if (property == 'size') {
        field = 'size';
        final size = _number(value, target.token);
        if (size < 1 || size > 409) {
          context.type(target.token, 'Font.Size must be in 1..409 points.');
        }
        normalized = size;
      } else {
        field = 'color';
        normalized = _color(value, target.token);
      }
      _emitRange(receiver.range, 'cellFormat', <String, Object?>{
        field: normalized,
      }, target.token);
    } else {
      _emitRange((receiver as _Interior).range, 'cellFormat', <String, Object?>{
        'fill': _color(value, target.token),
      }, target.token);
    }
  }

  void _writePowerPoint(
    Object receiver,
    String property,
    Object value,
    _Token token,
  ) {
    if (receiver is _TextRange) {
      _emitPowerPoint(receiver.shape, 'shapeText', <String, Object?>{
        'text': _powerPointText(value, token),
      }, token);
      return;
    }
    if (receiver is _Shape) {
      final number = _number(value, token);
      final field = switch (property) {
        'left' => 'x',
        'top' => 'y',
        _ => property,
      };
      final scale = property == 'rotation' ? 60000 : 12700;
      // DrawingML coordinates and rotations must remain representable after
      // native unit conversion on both the VM and JavaScript. Bound the XML
      // integer to a signed Long before the native operation rounds it.
      if ((number.toDouble() * scale).abs() > 2147483647 ||
          ((property == 'width' || property == 'height') && number < 0.01)) {
        context.type(
          token,
          'Geometry requires finite points/degrees within signed Long native units; dimensions must be at least 0.01 points.',
        );
      }
      _emitPowerPoint(receiver, 'shapeGeometry', <String, Object?>{
        field: number,
      }, token);
      return;
    }
    if (receiver is _PowerPointFont) {
      final String field;
      final Object normalized;
      if (property == 'bold' ||
          property == 'italic' ||
          property == 'underline') {
        field = property;
        normalized = _powerPointTriState(value, token);
      } else if (property == 'name') {
        field = 'font';
        final family = _powerPointText(value, token, name: true);
        if (family.trim().isEmpty ||
            family.length > 255 ||
            family.contains('\u007f')) {
          context.type(
            token,
            'PowerPoint Font.Name requires a non-whitespace typeface name of at most 255 UTF-16 units, without control characters.',
          );
        }
        normalized = family;
      } else {
        field = 'size';
        final points = _number(value, token);
        final hundredths = points * 100;
        if (points < 1 || points > 4000 || hundredths.round() / 100 != points) {
          context.type(
            token,
            'PowerPoint Font.Size requires exact hundredth-points in 1..4000.',
          );
        }
        normalized = points;
      }
      _emitPowerPoint(receiver.range.shape, 'shapeFormat', <String, Object?>{
        field: normalized,
      }, token);
      return;
    }
    if (receiver is _PowerPointColor) {
      _emitPowerPoint(receiver.range.shape, 'shapeFormat', <String, Object?>{
        'color': _color(value, token),
      }, token);
      return;
    }
    final format = receiver as _PowerPointParagraphFormat;
    final alignment = _integer(value, token);
    if (alignment < 1 || alignment > 4) {
      context.unsupported(
        token,
        'Only ppAlignLeft, ppAlignCenter, ppAlignRight and ppAlignJustify are supported.',
      );
    }
    _emitPowerPoint(format.range.shape, 'shapeFormat', <String, Object?>{
      'alignment': const <String>[
        'left',
        'center',
        'right',
        'justify',
      ][alignment - 1],
    }, token);
  }

  bool _powerPointTriState(Object value, _Token token) {
    if (value is bool) return value;
    final state = _integer(value, token);
    if (state != 0 && state != -1) {
      context.type(
        token,
        'Only Boolean values or msoTrue (-1) and msoFalse (0) are supported; mixed and toggle states require live reads.',
      );
    }
    return state == -1;
  }

  String _powerPointText(Object value, _Token token, {bool name = false}) {
    final text = _string(value, token);
    _charge(text.length, token);
    _nativeString(text, token);
    if (name && text.isEmpty) {
      context.type(token, 'Font and shape names require a nonempty String.');
    }
    for (var index = 0; index < text.length; index++) {
      final unit = text.codeUnitAt(index);
      if ((unit < 0x20 && (unit != 9 || name)) ||
          unit == 0xfffe ||
          unit == 0xffff) {
        context.type(
          token,
          name
              ? 'Font and shape names require XML-safe text without tabs or line breaks.'
              : 'TextRange.Text requires XML-safe single-paragraph text; tabs are allowed but line breaks are unsupported.',
        );
      }
    }
    return text;
  }

  void _emitPowerPoint(
    _Shape shape,
    String operation,
    Map<String, Object?> fields,
    _Token token,
  ) {
    if (steps.length >= _maxSteps) {
      context.limit(
        token,
        'PowerPoint writes exceed $_maxSteps emitted operations.',
      );
    }
    _emitNative('pptx.$operation', <String, Object?>{
      'topLevel': true,
      'slide': shape.slide.index,
      if (shape.selector is String)
        'shapeName': shape.selector
      else
        'shape': shape.selector,
      ...fields,
    }, token);
  }

  void _writeWord(
    Object receiver,
    String property,
    Object value,
    _Token token,
  ) {
    if (receiver is _WordFont) {
      final String field;
      final Object normalized;
      if (property == 'bold' ||
          property == 'italic' ||
          property == 'strikethrough') {
        field = property == 'strikethrough' ? 'strike' : property;
        normalized = _boolean(value, token);
      } else if (property == 'underline') {
        field = 'underline';
        final underline = _wordUnderlines[_integer(value, token)];
        if (underline == null) {
          context.unsupported(token, 'Unsupported WdUnderline value.');
        }
        normalized = underline;
      } else if (property == 'name') {
        field = 'font';
        normalized = _wordText(value, token, fontName: true);
      } else if (property == 'size') {
        field = 'size';
        final size = _number(value, token);
        final halfPoints = size * 2;
        if (size < 0.5 ||
            size > 1638 ||
            halfPoints != halfPoints.truncateToDouble()) {
          context.type(
            token,
            'Word Font.Size requires exact half-points in 0.5..1638.',
          );
        }
        normalized = size;
      } else {
        field = 'color';
        normalized = _color(value, token);
      }
      _emitWord(receiver.range, 'runFormat', <String, Object?>{
        field: normalized,
      }, token);
      return;
    }
    final format = receiver as _WordParagraphFormat;
    if (property == 'keeptogether' || property == 'pagebreakbefore') {
      _emitWord(format.range, 'paragraphFormat', <String, Object?>{
        property == 'keeptogether' ? 'keepTogether' : 'pageBreakBefore':
            _boolean(value, token),
      }, token);
      return;
    }
    if (property == 'leftindent' ||
        property == 'rightindent' ||
        property == 'firstlineindent') {
      final points = _number(value, token);
      final twips = points * 20;
      if (twips.abs() > 2147483647 || twips.round() / 20 != points) {
        context.type(
          token,
          'Paragraph indents require exact twentieth-points within signed Long twips.',
        );
      }
      _emitWord(format.range, 'paragraphFormat', <String, Object?>{
        if (property == 'firstlineindent') ...<String, Object?>{
          'firstLine': points < 0 ? 0 : points,
          'hanging': points < 0 ? -points : 0,
        } else
          property == 'leftindent' ? 'left' : 'right': points,
      }, token);
      return;
    }
    final String field;
    final Object normalized;
    if (property == 'alignment') {
      final alignment = _integer(value, token);
      if (alignment < 0 || alignment > 3) {
        context.unsupported(
          token,
          'Only left, center, right, and justified paragraph alignment are supported.',
        );
      }
      field = 'alignment';
      normalized = const <String>[
        'left',
        'center',
        'right',
        'justify',
      ][alignment];
    } else {
      final points = _number(value, token);
      final twips = points * 20;
      if (points < 0 ||
          twips > 2147483647 ||
          twips != twips.truncateToDouble()) {
        context.type(
          token,
          'Paragraph spacing requires nonnegative exact twentieth-points with at most 2147483647 twips.',
        );
      }
      field = property == 'spacebefore' ? 'before' : 'after';
      normalized = points;
    }
    _emitWord(format.range, 'paragraphFormat', <String, Object?>{
      field: normalized,
    }, token);
  }

  String _wordText(Object value, _Token token, {bool fontName = false}) {
    final text = _string(value, token);
    // Bound publication scans/copies before validating or encoding a string.
    _charge(text.length, token);
    _nativeString(text, token);
    if (fontName && text.isEmpty) {
      context.type(token, 'Font.Name requires a nonempty String.');
    }
    for (var index = 0; index < text.length; index++) {
      final unit = text.codeUnitAt(index);
      if ((unit < 0x20 && unit != 9) ||
          unit == 0xfffe ||
          unit == 0xffff ||
          (fontName && unit == 9)) {
        context.type(
          token,
          fontName
              ? 'Font.Name requires XML-safe text without tabs or line breaks.'
              : 'InsertBefore requires XML-safe single-paragraph text; tabs are allowed but line breaks are unsupported.',
        );
      }
    }
    return text;
  }

  void _emitWord(
    _WordRange range,
    String operation,
    Map<String, Object?> fields,
    _Token token,
  ) {
    if (steps.length >= _maxSteps) {
      context.limit(token, 'Word writes exceed $_maxSteps emitted operations.');
    }
    _emitNative('docx.$operation', <String, Object?>{
      'paragraph': range.paragraph.index,
      ...fields,
    }, token);
  }

  String _color(Object value, _Token token) {
    final color = _integer(value, token);
    if (color < 0 || color > 0xFFFFFF) {
      context.unsupported(
        token,
        'Only explicit RGB colors are supported; system colors and palettes are unsupported.',
      );
    }
    String hex(int component) =>
        component.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '${hex(color & 255)}${hex((color >> 8) & 255)}${hex((color >> 16) & 255)}';
  }

  void _nativeString(Object? value, _Token token) {
    if (value is! String) return;
    for (var index = 0; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (unit < 0xd800 || unit > 0xdfff) continue;
      final paired =
          unit <= 0xdbff &&
          index + 1 < value.length &&
          value.codeUnitAt(index + 1) >= 0xdc00 &&
          value.codeUnitAt(index + 1) <= 0xdfff;
      if (!paired) {
        context.type(
          token,
          context.isPowerPoint
              ? 'Native PowerPoint writes require well-formed UTF-16; isolated surrogates cannot be published losslessly.'
              : context.isWord
              ? 'Native Word writes require well-formed UTF-16; isolated surrogates cannot be published losslessly.'
              : 'Native spreadsheet writes require well-formed UTF-16; isolated surrogates cannot be published losslessly.',
        );
      }
      index++;
    }
  }

  void _emitRange(
    _Range range,
    String operation,
    Map<String, Object?> fields,
    _Token token,
  ) {
    final rows = range.maxRow - range.minRow + 1;
    final columns = range.maxColumn - range.minColumn + 1;
    final remaining = _maxSteps - steps.length;
    if (columns > remaining || rows > remaining ~/ columns) {
      context.limit(
        token,
        'Range expansion exceeds $_maxSteps emitted operations.',
      );
    }
    // Source expressions may split/recombine UTF-16 pairs, but the workbook
    // serializer cannot publish isolated surrogates without replacing them.
    // Check each template string once before expanding its native operations.
    _nativeString(range.sheet.selector, token);
    for (final value in fields.values) {
      _nativeString(value, token);
    }
    for (var row = range.minRow; row <= range.maxRow; row++) {
      for (var column = range.minColumn; column <= range.maxColumn; column++) {
        final arguments = <String, Object?>{
          'sheet': range.sheet.selector,
          'cell': '${_columnLetters(column)}$row',
          ...fields,
        };
        _emitNative('xlsx.$operation', arguments, token);
      }
    }
  }

  void _emitNative(String tool, Map<String, Object?> arguments, _Token token) {
    _tick(token);
    final json = <String, Object?>{'tool': tool, 'arguments': arguments};
    final bytes =
        utf8.encode(jsonEncode(json)).length + (steps.isEmpty ? 0 : 1);
    if (bytes > macroJsonByteLimit - encodedBytes) {
      context.limit(token, 'Compiled native JSON exceeds 1 MiB.');
    }
    encodedBytes += bytes;
    steps.add(OfficeMacroStep(tool: tool, arguments: arguments));
  }

  String _columnLetters(int column) {
    var remaining = column;
    var result = '';
    while (remaining > 0) {
      remaining--;
      result = String.fromCharCode(65 + remaining % 26) + result;
      remaining ~/= 26;
    }
    return result;
  }
}
