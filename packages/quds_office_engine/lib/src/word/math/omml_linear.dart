import 'omml_document.dart';

/// UnicodeMath-style linear format used by Word's Linear / Professional toggle.
abstract final class OmmlLinear {
  /// parse API.
  static OmmlSeq parse(String source) {
    final _Parser parser = _Parser(source.trim());
    final OmmlSeq seq = parser.parseExpr();
    parser.skipSpaces();
    if (!parser.done && parser.peek().isNotEmpty) {
      seq.children.addAll(parser.parseExpr().children);
    }
    return seq;
  }

  /// write API.
  static String write(OmmlSeq root) => _Writer().seq(root);

  /// collectCodepoints API.
  static void collectCodepoints(OmmlSeq root, Set<int> cps) {
    for (final int cp in write(root).runes) {
      cps.add(cp);
    }
  }
}

class _Parser {
  _Parser(this.source);

  /// source API.
  final String source;
  int _i = 0;

  /// done API.
  bool get done => _i >= source.length;

  /// skipSpaces API.
  void skipSpaces() {
    while (_i < source.length && _isSpace(source.codeUnitAt(_i))) {
      _i++;
    }
  }

  /// peek API.
  String peek() {
    skipSpaces();
    if (_i >= source.length) {
      return '';
    }
    return source.substring(_i, _i + 1);
  }

  /// take API.
  String take() {
    skipSpaces();
    if (_i >= source.length) {
      return '';
    }
    final String ch = source.substring(_i, _i + 1);
    _i++;
    return ch;
  }

  /// eat API.
  bool eat(String expected) {
    skipSpaces();
    if (source.startsWith(expected, _i)) {
      _i += expected.length;
      return true;
    }
    return false;
  }

  /// parseExpr API.
  OmmlSeq parseExpr() {
    final OmmlSeq seq = OmmlSeq();
    skipSpaces();
    while (!done) {
      final String ch = peek();
      if (ch.isEmpty || ch == ')' || ch == ']' || ch == '}' || ch == ',') {
        break;
      }
      seq.children.addAll(parseAddend().children);
      final String op = peek();
      if (_isRelOrAdd(op)) {
        seq.children.add(OmmlText(text: take(), italic: false, normal: true));
      } else if (ch.isNotEmpty && !_startsAtom(op) && op != '/') {
        break;
      }
    }
    return seq;
  }

  /// parseAddend API.
  OmmlSeq parseAddend() {
    OmmlSeq left = parseUnary();
    while (peek() == '/') {
      take();
      final OmmlSeq right = parseJuxtaposed();
      left = OmmlSeq(
        children: <OmmlNode>[OmmlFrac(num: left, den: right)],
      );
    }
    return left;
  }

  /// Implicit product used as a fraction denominator (`/2a` → `2a`).
  OmmlSeq parseJuxtaposed() {
    final OmmlSeq seq = OmmlSeq();
    seq.children.addAll(parseUnary().children);
    while (!done) {
      final String ch = peek();
      if (ch.isEmpty ||
          ch == ')' ||
          ch == ']' ||
          ch == '}' ||
          ch == ',' ||
          ch == '/' ||
          _isRelOrAdd(ch)) {
        break;
      }
      if (!_startsAtom(ch)) {
        break;
      }
      seq.children.addAll(parseUnary().children);
    }
    return seq;
  }

  /// parseUnary API.
  OmmlSeq parseUnary() {
    skipSpaces();
    if (eat('√') || eat('sqrt')) {
      final OmmlSeq radicand = _groupedOrAtom();
      return OmmlSeq(children: <OmmlNode>[OmmlRad(e: radicand)]);
    }
    if (eat('\\sqrt')) {
      final OmmlSeq radicand = _groupedOrAtom();
      return OmmlSeq(children: <OmmlNode>[OmmlRad(e: radicand)]);
    }
    final String? nary = _tryNary();
    if (nary != null) {
      OmmlSeq? sub;
      OmmlSeq? sup;
      if (eat('_')) {
        sub = _groupedOrAtom();
      }
      if (eat('^')) {
        sup = _groupedOrAtom();
      }
      final OmmlSeq e = peek().isEmpty || _isRelOrAdd(peek()) || peek() == '/'
          ? OmmlSeq()
          : parseUnary();
      return OmmlSeq(
        children: <OmmlNode>[
          OmmlNary(
            chr: nary,
            sub: sub,
            sup: sup,
            e: e,
            hideSub: sub == null,
            hideSup: sup == null,
          ),
        ],
      );
    }
    return parseScript();
  }

  /// parseScript API.
  OmmlSeq parseScript() {
    final OmmlSeq base = parseAtom();
    OmmlSeq? sub;
    OmmlSeq? sup;
    if (eat('_')) {
      sub = _groupedOrAtom();
    }
    if (eat('^')) {
      sup = _groupedOrAtom();
    }
    if (sub == null && sup == null) {
      return base;
    }
    return OmmlSeq(
      children: <OmmlNode>[
        OmmlScript(
          base: base,
          sub: sub,
          sup: sup,
          kind: sub != null && sup != null
              ? OmmlScriptKind.subSup
              : (sup != null ? OmmlScriptKind.sup : OmmlScriptKind.sub),
        ),
      ],
    );
  }

  /// parseAtom API.
  OmmlSeq parseAtom() {
    skipSpaces();
    if (done) {
      return OmmlSeq();
    }
    if (eat('(')) {
      return _closeDelim('(', ')', ')');
    }
    if (eat('[')) {
      return _closeDelim('[', ']', ']');
    }
    if (eat('{')) {
      return _closeDelim('{', '}', '}');
    }
    if (eat('|')) {
      final OmmlSeq inner = parseExpr();
      eat('|');
      return OmmlSeq(
        children: <OmmlNode>[OmmlDelim(begChr: '|', endChr: '|', e: inner)],
      );
    }
    if (eat('\\')) {
      return _command();
    }
    final String? func = _tryFunction();
    if (func != null) {
      final OmmlSeq arg = peek() == '(' ? parseAtom() : _groupedOrAtom();
      return OmmlSeq(
        children: <OmmlNode>[OmmlFunc(name: func, e: arg)],
      );
    }
    if (_isDigit(peek())) {
      return OmmlSeq(
        children: <OmmlNode>[
          OmmlText(
            text: _takeWhile(_isDigitOrDot),
            italic: false,
            normal: true,
          ),
        ],
      );
    }
    final String ident = _takeIdent();
    if (ident.isNotEmpty) {
      return OmmlSeq(
        children: <OmmlNode>[
          OmmlText(
            text: ident,
            italic: _isMathItalic(ident),
            normal: !_isMathItalic(ident),
          ),
        ],
      );
    }
    final String ch = take();
    if (ch.isEmpty) {
      return OmmlSeq();
    }
    return OmmlSeq(
      children: <OmmlNode>[OmmlText(text: ch, italic: false, normal: true)],
    );
  }

  OmmlSeq _closeDelim(String beg, String end, String closer) {
    final OmmlSeq inner = parseExpr();
    eat(closer);
    return OmmlSeq(
      children: <OmmlNode>[OmmlDelim(begChr: beg, endChr: end, e: inner)],
    );
  }

  OmmlSeq _groupedOrAtom() {
    skipSpaces();
    if (peek() == '(' || peek() == '[' || peek() == '{') {
      return parseAtom();
    }
    return parseAtom();
  }

  OmmlSeq _command() {
    final String name = _takeWhile(_isAsciiLetter);
    switch (name) {
      case 'alpha':
        return _sym('α');
      case 'beta':
        return _sym('β');
      case 'gamma':
        return _sym('γ');
      case 'delta':
        return _sym('δ');
      case 'epsilon':
        return _sym('ε');
      case 'theta':
        return _sym('θ');
      case 'lambda':
        return _sym('λ');
      case 'mu':
        return _sym('μ');
      case 'pi':
        return _sym('π');
      case 'sigma':
        return _sym('σ');
      case 'phi':
        return _sym('φ');
      case 'omega':
        return _sym('ω');
      case 'Gamma':
        return _sym('Γ');
      case 'Delta':
        return _sym('Δ');
      case 'Theta':
        return _sym('Θ');
      case 'Lambda':
        return _sym('Λ');
      case 'Pi':
        return _sym('Π');
      case 'Sigma':
        return _sym('Σ');
      case 'Omega':
        return _sym('Ω');
      case 'infty':
      case 'inf':
        return _sym('∞', italic: false);
      case 'pm':
        return _sym('±', italic: false);
      case 'times':
        return _sym('×', italic: false);
      case 'cdot':
        return _sym('·', italic: false);
      case 'le':
      case 'leq':
        return _sym('≤', italic: false);
      case 'ge':
      case 'geq':
        return _sym('≥', italic: false);
      case 'ne':
      case 'neq':
        return _sym('≠', italic: false);
      case 'approx':
        return _sym('≈', italic: false);
      case 'rightarrow':
        return _sym('→', italic: false);
      case 'leftarrow':
        return _sym('←', italic: false);
      case 'sum':
        return OmmlSeq(
          children: <OmmlNode>[
            OmmlNary(chr: '∑', sub: OmmlSeq(), sup: OmmlSeq(), e: OmmlSeq()),
          ],
        );
      case 'int':
        return OmmlSeq(
          children: <OmmlNode>[
            OmmlNary(chr: '∫', hideSub: true, hideSup: true, e: OmmlSeq()),
          ],
        );
      case 'prod':
        return OmmlSeq(
          children: <OmmlNode>[
            OmmlNary(chr: '∏', sub: OmmlSeq(), sup: OmmlSeq(), e: OmmlSeq()),
          ],
        );
      case 'sin':
      case 'cos':
      case 'tan':
      case 'log':
      case 'ln':
      case 'lim':
        final OmmlSeq arg = peek() == '(' ? parseAtom() : OmmlSeq();
        if (name == 'lim') {
          return OmmlSeq(children: <OmmlNode>[OmmlLimLow(lim: arg)]);
        }
        return OmmlSeq(
          children: <OmmlNode>[OmmlFunc(name: name, e: arg)],
        );
      default:
        return OmmlSeq(
          children: <OmmlNode>[
            OmmlText(text: name, italic: false, normal: true),
          ],
        );
    }
  }

  /// italic API.
  OmmlSeq _sym(String text, {bool italic = true}) => OmmlSeq(
    children: <OmmlNode>[OmmlText(text: text, italic: italic, normal: !italic)],
  );

  String? _tryNary() {
    skipSpaces();
    if (eat('∫') || eat('\\int')) {
      return '∫';
    }
    if (eat('∑') || eat('\\sum')) {
      return '∑';
    }
    if (eat('∏') || eat('\\prod')) {
      return '∏';
    }
    if (eat('∮')) {
      return '∮';
    }
    return null;
  }

  String? _tryFunction() {
    skipSpaces();
    const List<String> names = <String>[
      'sin',
      'cos',
      'tan',
      'log',
      'ln',
      'lim',
    ];
    for (final String name in names) {
      if (source.startsWith(name, _i)) {
        final int after = _i + name.length;
        if (after >= source.length ||
            !_isAsciiLetter(source.substring(after, after + 1))) {
          _i = after;
          return name;
        }
      }
    }
    return null;
  }

  String _takeIdent() {
    skipSpaces();
    if (done) {
      return '';
    }
    final int cp = source.codeUnitAt(_i);
    if (_isAsciiLetter(source.substring(_i, _i + 1)) ||
        (cp >= 0x03B1 && cp <= 0x03C9) ||
        (cp >= 0x0391 && cp <= 0x03A9) ||
        source.substring(_i, _i + 1) == 'π' ||
        source.substring(_i, _i + 1) == '∞' ||
        source.substring(_i, _i + 1) == 'θ') {
      final String ch = source.substring(_i, _i + 1);
      _i++;
      return ch;
    }
    return '';
  }

  /// Function API.
  String _takeWhile(bool Function(String ch) pred) {
    final StringBuffer buf = StringBuffer();
    while (!done) {
      final String ch = source.substring(_i, _i + 1);
      if (!pred(ch)) {
        break;
      }
      buf.write(ch);
      _i++;
    }
    return buf.toString();
  }

  /// cu API.
  static bool _isSpace(int cu) => cu == 0x20 || cu == 0x09 || cu == 0x0A;

  static bool _isDigit(String ch) =>
      ch.isNotEmpty && ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;

  /// ch API.
  static bool _isDigitOrDot(String ch) => _isDigit(ch) || ch == '.';

  static bool _isAsciiLetter(String ch) {
    if (ch.isEmpty) {
      return false;
    }
    final int cu = ch.codeUnitAt(0);
    return (cu >= 0x41 && cu <= 0x5A) || (cu >= 0x61 && cu <= 0x7A);
  }

  static bool _isRelOrAdd(String ch) =>
      ch == '+' ||
      ch == '-' ||
      ch == '=' ||
      ch == '±' ||
      ch == '×' ||
      ch == '·' ||
      ch == '≠' ||
      ch == '≤' ||
      ch == '≥' ||
      ch == '≈' ||
      ch == '→' ||
      ch == '←';

  static bool _startsAtom(String ch) =>
      ch.isNotEmpty &&
      (ch == '(' ||
          ch == '[' ||
          ch == '{' ||
          ch == '|' ||
          ch == '\\' ||
          ch == '√' ||
          ch == '∫' ||
          ch == '∑' ||
          ch == '∏' ||
          ch == 'π' ||
          ch == '∞' ||
          ch == 'θ' ||
          _isDigit(ch) ||
          _isAsciiLetter(ch));

  static bool _isMathItalic(String text) {
    if (text.length != 1) {
      return false;
    }
    final int cp = text.runes.first;
    return (cp >= 0x41 && cp <= 0x5A) ||
        (cp >= 0x61 && cp <= 0x7A) ||
        (cp >= 0x03B1 && cp <= 0x03C9);
  }
}

class _Writer {
  /// seq API.
  String seq(OmmlSeq node) {
    final StringBuffer buf = StringBuffer();
    for (final OmmlNode child in node.children) {
      buf.write(nodeWrite(child));
    }
    return buf.toString();
  }

  /// nodeWrite API.
  String nodeWrite(OmmlNode node) {
    switch (node) {
      case OmmlSeq():
        return seq(node);
      case OmmlText():
        return node.text;
      case OmmlFrac():
        return '(${seq(node.num)})/(${seq(node.den)})';
      case OmmlScript():
        final StringBuffer buf = StringBuffer(seq(node.base));
        if (node.sub != null) {
          buf.write('_${_group(node.sub!)}');
        }
        if (node.sup != null) {
          buf.write('^${_group(node.sup!)}');
        }
        return buf.toString();
      case OmmlRad():
        if (node.deg == null || node.deg!.isEmpty) {
          return '√(${seq(node.e)})';
        }
        return '√(${seq(node.e)})';
      case OmmlNary():
        final StringBuffer buf = StringBuffer(node.chr);
        if (node.sub != null && !node.hideSub) {
          buf.write('_${_group(node.sub!)}');
        }
        if (node.sup != null && !node.hideSup) {
          buf.write('^${_group(node.sup!)}');
        }
        final String body = seq(node.e);
        if (body.isNotEmpty) {
          buf.write(' $body');
        }
        return buf.toString();
      case OmmlDelim():
        return '${node.begChr}${seq(node.e)}${node.endChr}';
      case OmmlMatrix():
        final StringBuffer buf = StringBuffer();
        for (int r = 0; r < node.rows.length; r++) {
          if (r > 0) {
            buf.write('@');
          }
          for (int c = 0; c < node.rows[r].length; c++) {
            if (c > 0) {
              buf.write('&');
            }
            buf.write(seq(node.rows[r][c]));
          }
        }
        return buf.toString();
      case OmmlAcc():
        return '${seq(node.e)}${node.chr}';
      case OmmlFunc():
        return '${node.name}(${seq(node.e)})';
      case OmmlLimLow():
        return 'lim_${_group(node.lim)} ${seq(node.e)}';
      case OmmlBar():
        return '¯(${seq(node.e)})';
    }
  }

  String _group(OmmlSeq node) {
    final String text = seq(node);
    if (text.length <= 1) {
      return text;
    }
    return '($text)';
  }
}
