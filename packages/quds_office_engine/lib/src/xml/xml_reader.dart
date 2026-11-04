import 'dart:convert';
import 'dart:typed_data';

/// Event kinds emitted by [XmlPullReader].
enum XmlEventType {
  none,
  xmlDeclaration,
  processingInstruction,
  comment,
  dtd,
  startElement,
  endElement,
  characters,
  cdata,
  endDocument,
}

/// Low-allocation XML 1.0 pull parser.
///
/// The reader walks the source with integer indexes and only allocates
/// [String] values when a property is read. Namespace prefixes are resolved
/// against a stack of `xmlns` declarations.
class XmlPullReader {
  /// XmlPullReader API.
  XmlPullReader(String source) : _source = _stripBom(source);

  /// fromBytes API.
  factory XmlPullReader.fromBytes(Uint8List bytes) {
    return XmlPullReader(utf8.decode(bytes, allowMalformed: false));
  }

  final String _source;
  int _pos = 0;

  /// none API.
  XmlEventType _type = XmlEventType.none;
  int _depth = 0;
  bool _emptyElement = false;
  bool _documentEnded = false;

  int _nameStart = 0;
  int _nameEnd = 0;
  int _localStart = 0;
  int _localEnd = 0;
  int _prefixStart = 0;
  int _prefixEnd = 0;
  int _textStart = 0;
  int _textEnd = 0;
  bool _textHasEntities = false;

  /// root API.
  final List<_NsScope> _nsStack = <_NsScope>[_NsScope.root()];
  final List<_AttrSlice> _attrs = <_AttrSlice>[];
  final List<String> _elementStack = <String>[];

  /// eventType API.
  XmlEventType get eventType => _type;

  /// depth API.
  int get depth => _depth;

  /// isEmptyElement API.
  bool get isEmptyElement =>
      _emptyElement && _type == XmlEventType.startElement;

  /// isWhitespace API.
  bool get isWhitespace {
    if (_type != XmlEventType.characters) {
      return false;
    }
    for (int i = _textStart; i < _textEnd; i++) {
      if (!_isXmlSpace(_source.codeUnitAt(i))) {
        return false;
      }
    }
    return true;
  }

  /// qualifiedName API.
  String get qualifiedName => _slice(_nameStart, _nameEnd);

  /// localName API.
  String get localName => _slice(_localStart, _localEnd);

  /// prefix API.
  String get prefix =>
      _prefixEnd > _prefixStart ? _slice(_prefixStart, _prefixEnd) : '';

  /// namespaceUri API.
  String get namespaceUri {
    if (_type != XmlEventType.startElement &&
        _type != XmlEventType.endElement) {
      return '';
    }
    return _resolvePrefix(prefix);
  }

  /// text API.
  String get text {
    if (_type == XmlEventType.characters || _type == XmlEventType.cdata) {
      if (_textHasEntities && _type == XmlEventType.characters) {
        return decodeXmlEntities(_source.substring(_textStart, _textEnd));
      }
      return _source.substring(_textStart, _textEnd);
    }
    if (_type == XmlEventType.comment ||
        _type == XmlEventType.processingInstruction ||
        _type == XmlEventType.dtd ||
        _type == XmlEventType.xmlDeclaration) {
      return _source.substring(_textStart, _textEnd);
    }
    return '';
  }

  /// attributeCount API.
  int get attributeCount => _attrs.length;

  /// Advances to the next event. Returns `false` after [XmlEventType.endDocument].
  bool next() {
    if (_documentEnded) {
      return false;
    }
    if (_emptyElement) {
      _emptyElement = false;
      _type = XmlEventType.endElement;
      if (_elementStack.isNotEmpty) {
        _elementStack.removeLast();
      }
      _depth = _elementStack.length;
      if (_nsStack.length > 1) {
        _nsStack.removeLast();
      }
      return true;
    }

    _attrs.clear();
    _emptyElement = false;
    _textHasEntities = false;
    _nameStart = _nameEnd = _localStart = _localEnd = 0;
    _prefixStart = _prefixEnd = 0;
    _textStart = _textEnd = 0;

    if (_pos >= _source.length) {
      _type = XmlEventType.endDocument;
      _documentEnded = true;
      return true;
    }

    final int ch = _source.codeUnitAt(_pos);
    if (ch == _lt) {
      _pos++;
      if (_pos >= _source.length) {
        throw XmlParseException('Unterminated tag', _pos);
      }
      final int nextCh = _source.codeUnitAt(_pos);
      if (nextCh == _slash) {
        _readEndElement();
      } else if (nextCh == _bang) {
        _readBang();
      } else if (nextCh == _quest) {
        _readPiOrDeclaration();
      } else {
        _readStartElement();
      }
      return true;
    }

    _readText();
    return true;
  }

  /// Skips whitespace-only character events until a tag or document end.
  bool nextTag() {
    while (next()) {
      if (_type == XmlEventType.characters && isWhitespace) {
        continue;
      }
      if (_type == XmlEventType.comment) {
        continue;
      }
      return _type != XmlEventType.endDocument;
    }
    return false;
  }

  /// Skips the current start-element and all of its descendants.
  void skip() {
    if (_type != XmlEventType.startElement) {
      return;
    }
    if (isEmptyElement) {
      next();
      return;
    }
    final int startDepth = _depth;
    while (next()) {
      if (_type == XmlEventType.endElement && _depth < startDepth) {
        return;
      }
      if (_type == XmlEventType.endDocument) {
        return;
      }
    }
  }

  /// attributeQualifiedName API.
  String attributeQualifiedName(int index) => _attrs[index].qualified(_source);

  /// attributeLocalName API.
  String attributeLocalName(int index) => _attrs[index].local(_source);

  /// attributePrefix API.
  String attributePrefix(int index) => _attrs[index].prefix(_source);

  /// attributeValue API.
  String attributeValue(int index) => _attrs[index].decodedValue(_source);

  /// attributeNamespace API.
  String attributeNamespace(int index) {
    final _AttrSlice attr = _attrs[index];
    if (attr.isXmlns) {
      return '';
    }
    final String pfx = attr.prefix(_source);
    if (pfx.isEmpty) {
      return '';
    }
    return _resolvePrefix(pfx);
  }

  /// getAttribute API.
  String? getAttribute(String localName, {String? namespaceUri}) {
    for (int i = 0; i < _attrs.length; i++) {
      final _AttrSlice attr = _attrs[i];
      if (attr.local(_source) != localName) {
        continue;
      }
      if (namespaceUri == null) {
        return attr.decodedValue(_source);
      }
      if (attributeNamespace(i) == namespaceUri) {
        return attr.decodedValue(_source);
      }
    }
    return null;
  }

  /// attributesAsMap API.
  Map<String, String> attributesAsMap() {
    final Map<String, String> map = <String, String>{};
    for (int i = 0; i < _attrs.length; i++) {
      map[attributeQualifiedName(i)] = attributeValue(i);
    }
    return map;
  }

  void _readStartElement() {
    _type = XmlEventType.startElement;
    _readQName();
    _skipSpaces();
    final _NsScope scope = _NsScope(_nsStack.last);
    while (_pos < _source.length) {
      final int ch = _source.codeUnitAt(_pos);
      if (ch == _gt) {
        _pos++;
        break;
      }
      if (ch == _slash) {
        _pos++;
        _expect(_gt, 'Expected > after / in empty element');
        _emptyElement = true;
        break;
      }
      _readAttribute(scope);
      _skipSpaces();
    }
    _nsStack.add(scope);
    _elementStack.add(qualifiedName);
    _depth = _elementStack.length;
  }

  void _readEndElement() {
    _type = XmlEventType.endElement;
    _pos++; // skip /
    _readQName();
    _skipSpaces();
    _expect(_gt, 'Expected > at end of closing tag');
    if (_elementStack.isEmpty) {
      throw XmlParseException('Unexpected end tag </$qualifiedName>', _pos);
    }
    final String open = _elementStack.removeLast();
    if (open != qualifiedName) {
      throw XmlParseException(
        'Mismatched end tag: expected </$open> but found </$qualifiedName>',
        _pos,
      );
    }
    _depth = _elementStack.length;
    if (_nsStack.length > 1) {
      _nsStack.removeLast();
    }
  }

  void _readQName() {
    _nameStart = _pos;
    _prefixStart = _pos;
    _prefixEnd = _pos;
    while (_pos < _source.length && _isNameChar(_source.codeUnitAt(_pos))) {
      if (_source.codeUnitAt(_pos) == _colon && _prefixEnd == _prefixStart) {
        _prefixEnd = _pos;
      }
      _pos++;
    }
    _nameEnd = _pos;
    if (_nameEnd == _nameStart) {
      throw XmlParseException('Expected qualified name', _pos);
    }
    if (_prefixEnd > _prefixStart) {
      _localStart = _prefixEnd + 1;
      _localEnd = _nameEnd;
    } else {
      _localStart = _nameStart;
      _localEnd = _nameEnd;
      _prefixStart = _prefixEnd = _nameStart;
    }
  }

  void _readAttribute(_NsScope scope) {
    final int qStart = _pos;
    int prefixEnd = qStart;
    while (_pos < _source.length && _isNameChar(_source.codeUnitAt(_pos))) {
      if (_source.codeUnitAt(_pos) == _colon && prefixEnd == qStart) {
        prefixEnd = _pos;
      }
      _pos++;
    }
    final int qEnd = _pos;
    if (qEnd == qStart) {
      throw XmlParseException('Expected attribute name', _pos);
    }
    _skipSpaces();
    _expect(_eq, 'Expected = after attribute name');
    _skipSpaces();
    final int quote = _source.codeUnitAt(_pos);
    if (quote != _quot && quote != _apos) {
      throw XmlParseException('Expected quoted attribute value', _pos);
    }
    _pos++;
    final int vStart = _pos;
    bool hasEntities = false;
    while (_pos < _source.length && _source.codeUnitAt(_pos) != quote) {
      if (_source.codeUnitAt(_pos) == _amp) {
        hasEntities = true;
      }
      _pos++;
    }
    final int vEnd = _pos;
    _expect(quote, 'Unterminated attribute value');

    final _AttrSlice attr = _AttrSlice(
      nameStart: qStart,
      nameEnd: qEnd,
      prefixEnd: prefixEnd == qStart ? qStart : prefixEnd,
      valueStart: vStart,
      valueEnd: vEnd,
      hasEntities: hasEntities,
    );
    _attrs.add(attr);

    final String qname = _source.substring(qStart, qEnd);
    final String value = attr.decodedValue(_source);
    if (qname == 'xmlns') {
      scope.declare('', value);
      attr.isXmlns = true;
    } else if (qname.startsWith('xmlns:')) {
      scope.declare(qname.substring(6), value);
      attr.isXmlns = true;
    }
  }

  void _readText() {
    _type = XmlEventType.characters;
    _textStart = _pos;
    while (_pos < _source.length && _source.codeUnitAt(_pos) != _lt) {
      if (_source.codeUnitAt(_pos) == _amp) {
        _textHasEntities = true;
      }
      _pos++;
    }
    _textEnd = _pos;
  }

  void _readBang() {
    _pos++; // !
    if (_startsWith('--')) {
      _pos += 2;
      _type = XmlEventType.comment;
      _textStart = _pos;
      final int end = _source.indexOf('-->', _pos);
      if (end < 0) {
        throw XmlParseException('Unterminated comment', _pos);
      }
      _textEnd = end;
      _pos = end + 3;
      return;
    }
    if (_startsWith('[CDATA[')) {
      _pos += 7;
      _type = XmlEventType.cdata;
      _textStart = _pos;
      final int end = _source.indexOf(']]>', _pos);
      if (end < 0) {
        throw XmlParseException('Unterminated CDATA', _pos);
      }
      _textEnd = end;
      _pos = end + 3;
      return;
    }
    if (_startsWith('DOCTYPE')) {
      _type = XmlEventType.dtd;
      _textStart = _pos;
      _skipToBalancedGt();
      _textEnd = _pos - 1;
      return;
    }
    throw XmlParseException('Unsupported declaration after <!', _pos);
  }

  void _readPiOrDeclaration() {
    _pos++; // ?
    final int nameStart = _pos;
    while (_pos < _source.length && _isNameChar(_source.codeUnitAt(_pos))) {
      _pos++;
    }
    final String target = _source.substring(nameStart, _pos);
    _skipSpaces();
    _textStart = _pos;
    final int end = _source.indexOf('?>', _pos);
    if (end < 0) {
      throw XmlParseException('Unterminated processing instruction', _pos);
    }
    _textEnd = end;
    _pos = end + 2;
    if (target == 'xml') {
      _type = XmlEventType.xmlDeclaration;
      _nameStart = nameStart;
      _nameEnd = nameStart + 3;
      _localStart = _nameStart;
      _localEnd = _nameEnd;
    } else {
      _type = XmlEventType.processingInstruction;
      _nameStart = nameStart;
      _nameEnd = nameStart + target.length;
      _localStart = _nameStart;
      _localEnd = _nameEnd;
    }
  }

  void _skipToBalancedGt() {
    int depth = 1;
    bool inQuote = false;
    int quote = 0;
    while (_pos < _source.length) {
      final int ch = _source.codeUnitAt(_pos);
      _pos++;
      if (inQuote) {
        if (ch == quote) {
          inQuote = false;
        }
        continue;
      }
      if (ch == _quot || ch == _apos) {
        inQuote = true;
        quote = ch;
        continue;
      }
      if (ch == _lt) {
        depth++;
      } else if (ch == _gt) {
        depth--;
        if (depth == 0) {
          return;
        }
      }
    }
    throw XmlParseException('Unterminated DOCTYPE', _pos);
  }

  String _resolvePrefix(String prefix) {
    if (prefix == 'xml') {
      return 'http://www.w3.org/XML/1998/namespace';
    }
    if (prefix == 'xmlns') {
      return 'http://www.w3.org/2000/xmlns/';
    }
    return _nsStack.last.resolve(prefix);
  }

  void _skipSpaces() {
    while (_pos < _source.length && _isXmlSpace(_source.codeUnitAt(_pos))) {
      _pos++;
    }
  }

  void _expect(int codeUnit, String message) {
    if (_pos >= _source.length || _source.codeUnitAt(_pos) != codeUnit) {
      throw XmlParseException(message, _pos);
    }
    _pos++;
  }

  bool _startsWith(String token) {
    if (_pos + token.length > _source.length) {
      return false;
    }
    return _source.startsWith(token, _pos);
  }

  /// substring API.
  String _slice(int start, int end) => _source.substring(start, end);

  static String _stripBom(String source) {
    if (source.isNotEmpty && source.codeUnitAt(0) == 0xFEFF) {
      return source.substring(1);
    }
    return source;
  }
}

/// Decodes XML predefined and numeric character entities.
String decodeXmlEntities(String raw) {
  /// amp API.
  final int amp = raw.indexOf('&');
  if (amp < 0) {
    return raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  /// out API.
  final StringBuffer out = StringBuffer();

  /// i API.
  int i = 0;
  while (i < raw.length) {
    final int nextAmp = raw.indexOf('&', i);
    if (nextAmp < 0) {
      out.write(raw.substring(i));
      break;
    }
    out.write(raw.substring(i, nextAmp));
    final int semi = raw.indexOf(';', nextAmp + 1);
    if (semi < 0) {
      throw XmlParseException('Unterminated entity', nextAmp);
    }
    final String body = raw.substring(nextAmp + 1, semi);
    out.writeCharCode(_entityCodePoint(body));
    i = semi + 1;
  }
  return out.toString().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

/// Encodes text for XML character data.
String encodeXmlText(String raw) {
  /// buffer API.
  final StringBuffer? buffer = _escape(
    raw,
    escapeApos: false,
    escapeQuot: false,
  );
  return buffer?.toString() ?? raw;
}

/// Encodes text for a double-quoted XML attribute.
String encodeXmlAttribute(String raw) {
  /// buffer API.
  final StringBuffer? buffer = _escape(
    raw,
    escapeApos: false,
    escapeQuot: true,
  );
  return buffer?.toString() ?? raw;
}

StringBuffer? _escape(
  String raw, {
  required bool escapeApos,
  required bool escapeQuot,
}) {
  /// buffer API.
  StringBuffer? buffer;
  for (int i = 0; i < raw.length; i++) {
    final int ch = raw.codeUnitAt(i);
    String? repl;
    switch (ch) {
      case _amp:
        repl = '&amp;';
      case _lt:
        repl = '&lt;';
      case _gt:
        repl = '&gt;';
      case _quot:
        if (escapeQuot) {
          repl = '&quot;';
        }
      case _apos:
        if (escapeApos) {
          repl = '&apos;';
        }
    }
    if (repl != null) {
      buffer ??= StringBuffer(raw.substring(0, i));
      buffer.write(repl);
    } else {
      buffer?.writeCharCode(ch);
    }
  }
  return buffer;
}

int _entityCodePoint(String body) {
  switch (body) {
    case 'lt':
      return _lt;
    case 'gt':
      return _gt;
    case 'amp':
      return _amp;
    case 'quot':
      return _quot;
    case 'apos':
      return _apos;
  }
  if (body.startsWith('#x') || body.startsWith('#X')) {
    return int.parse(body.substring(2), radix: 16);
  }
  if (body.startsWith('#')) {
    return int.parse(body.substring(1), radix: 10);
  }
  throw XmlParseException('Unknown entity &$body;', 0);
}

class _AttrSlice {
  _AttrSlice({
    required this.nameStart,
    required this.nameEnd,
    required this.prefixEnd,
    required this.valueStart,
    required this.valueEnd,
    required this.hasEntities,
  });

  /// nameStart API.
  final int nameStart;

  /// nameEnd API.
  final int nameEnd;

  /// prefixEnd API.
  final int prefixEnd;

  /// valueStart API.
  final int valueStart;

  /// valueEnd API.
  final int valueEnd;

  /// hasEntities API.
  final bool hasEntities;

  /// isXmlns API.
  bool isXmlns = false;

  /// qualified API.
  String qualified(String source) => source.substring(nameStart, nameEnd);

  /// local API.
  String local(String source) {
    if (prefixEnd > nameStart) {
      return source.substring(prefixEnd + 1, nameEnd);
    }
    return source.substring(nameStart, nameEnd);
  }

  /// prefix API.
  String prefix(String source) {
    if (prefixEnd > nameStart) {
      return source.substring(nameStart, prefixEnd);
    }
    return '';
  }

  /// decodedValue API.
  String decodedValue(String source) {
    final String raw = source.substring(valueStart, valueEnd);
    if (!hasEntities) {
      return raw;
    }
    return decodeXmlEntities(raw);
  }
}

class _NsScope {
  _NsScope(this.parent);

  /// root API.
  _NsScope.root() : parent = null {
    _map[''] = '';
  }

  /// parent API.
  final _NsScope? parent;
  final Map<String, String> _map = <String, String>{};

  /// declare API.
  void declare(String prefix, String uri) {
    _map[prefix] = uri;
  }

  /// resolve API.
  String resolve(String prefix) {
    final String? local = _map[prefix];
    if (local != null) {
      return local;
    }
    final _NsScope? up = parent;
    if (up == null) {
      return '';
    }
    return up.resolve(prefix);
  }
}

/// Thrown when the pull parser encounters malformed XML.
class XmlParseException implements Exception {
  /// XmlParseException API.
  XmlParseException(this.message, this.position);

  /// message API.
  final String message;

  /// position API.
  final int position;

  @override
  /// toString API.
  String toString() => 'XmlParseException: $message (at $position)';
}

bool _isXmlSpace(int ch) =>
    ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D;

bool _isNameChar(int ch) {
  return (ch >= 65 && ch <= 90) ||
      (ch >= 97 && ch <= 122) ||
      (ch >= 48 && ch <= 57) ||
      ch == 95 ||
      ch == 45 ||
      ch == 46 ||
      ch == 58 ||
      ch >= 0xC0;
}

const int _lt = 0x3C;
const int _gt = 0x3E;
const int _slash = 0x2F;
const int _bang = 0x21;
const int _quest = 0x3F;
const int _eq = 0x3D;
const int _quot = 0x22;
const int _apos = 0x27;
const int _amp = 0x26;
const int _colon = 0x3A;
