import 'dart:convert';

/// A bounded, inert text preview of a catalog note, never a document import.
///
/// Common HTML entities are decoded once. Unknown named entities stay literal.
/// Attributes are ignored; resources and active/embedded content are omitted.
/// Ordinary HTML whitespace collapses, while plain notes and `<pre>` preserve
/// their authored whitespace. Block, list, table and explicit line boundaries
/// remain readable. Ambiguous or structurally malformed markup is refused.
final class ZoteroNotePreview {
  const ZoteroNotePreview._(this.plainText, this.hasOmittedContent);

  factory ZoteroNotePreview.fromHtml(String html) =>
      _NotePreviewParser(html).parse();

  final String plainText;
  final bool hasOmittedContent;
}

final class _NotePreviewParser {
  _NotePreviewParser(this.source);

  static const _maxBytes = 1024 * 1024;
  static const _maxTokens = 10000;
  static const _maxDepth = 64;
  static const _voidTags = <String>{
    'area',
    'base',
    'br',
    'col',
    'embed',
    'hr',
    'img',
    'input',
    'link',
    'meta',
    'param',
    'source',
    'track',
    'wbr',
  };
  static const _omittedTags = <String>{
    'script',
    'style',
    'head',
    'iframe',
    'object',
    'embed',
    'svg',
    'math',
    'template',
    'noscript',
    'canvas',
    'video',
    'audio',
    'img',
    'input',
    'link',
    'meta',
    'source',
    'track',
    'area',
    'base',
    'param',
  };
  static const _blocks = <String>{
    'address',
    'article',
    'aside',
    'blockquote',
    'div',
    'dl',
    'dt',
    'dd',
    'fieldset',
    'figcaption',
    'figure',
    'footer',
    'form',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'hgroup',
    'main',
    'nav',
    'ol',
    'p',
    'pre',
    'section',
    'ul',
    'li',
    'table',
    'thead',
    'tbody',
    'tfoot',
    'tr',
    'hr',
  };

  final String source;
  final _out = _PreviewTextBuilder();
  final _stack = <_PreviewElement>[];
  var _tokens = 0;
  var _hasMarkup = false;
  var _hasOmittedContent = false;

  ZoteroNotePreview parse() {
    if (source.length > _maxBytes || utf8.encode(source).length > _maxBytes) {
      throw const FormatException('This note is too large to preview.');
    }
    if (source.contains('\u0000')) throw _malformed();
    var offset = 0;
    while (offset < source.length) {
      final start = source.indexOf('<', offset);
      if (start < 0) {
        _text(source.substring(offset));
        break;
      }
      _text(source.substring(offset, start));
      if (source.startsWith('<!--', start)) {
        final end = source.indexOf('-->', start + 4);
        if (end < 0) throw _malformed();
        _token();
        offset = end + 3;
        continue;
      }
      if (source.startsWith('<!', start) || source.startsWith('<?', start)) {
        throw _malformed();
      }
      final tag = _readTag(start);
      if (tag == null) {
        _text('<');
        offset = start + 1;
        continue;
      }
      _token();
      offset = tag.end;
      if (tag.closing) {
        if (_stack.isEmpty || _stack.last.tag != tag.name) throw _malformed();
        final element = _stack.removeLast();
        if (!element.hidden) _boundary(tag.name);
        continue;
      }
      if (_stack.length >= _maxDepth) throw _tooComplex();
      final hidden =
          _stack.lastOrNull?.hidden == true || _omittedTags.contains(tag.name);
      final preformatted =
          _stack.lastOrNull?.preformatted == true || tag.name == 'pre';
      if (_omittedTags.contains(tag.name)) _hasOmittedContent = true;
      if (!hidden) {
        _boundary(tag.name);
        if (tag.name == 'br') _out.lineBreak();
      }
      if (tag.name == 'script' || tag.name == 'style') {
        // HTML does not self-close raw-text elements. Refuse the ambiguous
        // XHTML spelling instead of exposing their following content.
        if (tag.selfClosing) throw _malformed();
        offset = _skipRawText(tag.name, offset);
        continue;
      }
      if (!tag.selfClosing && !_voidTags.contains(tag.name)) {
        _stack.add(_PreviewElement(tag.name, hidden, preformatted));
      }
    }
    if (_stack.isNotEmpty) throw _malformed();
    return ZoteroNotePreview._(
      _hasMarkup
          ? _out.finish()
          : _decodeEntities(
              source,
            ).replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      _hasOmittedContent,
    );
  }

  void _token() {
    _hasMarkup = true;
    if (++_tokens > _maxTokens) throw _tooComplex();
  }

  void _text(String text) {
    if (_stack.lastOrNull?.hidden == true || text.isEmpty) return;
    _out.text(
      _decodeEntities(text),
      preformatted: _stack.lastOrNull?.preformatted == true,
    );
  }

  void _boundary(String name) {
    if (_blocks.contains(name)) _out.blockBreak();
    if (name == 'td' || name == 'th') _out.cellBreak();
  }

  int _skipRawText(String name, int offset) {
    while (offset < source.length) {
      final start = source.indexOf('</', offset);
      if (start < 0) throw _malformed();
      var end = start + 2;
      while (end < source.length && _nameChar(source.codeUnitAt(end))) {
        end++;
      }
      if (source.substring(start + 2, end).toLowerCase() == name) {
        final tag = _readTag(start);
        if (tag == null) throw _malformed();
        _token();
        return tag.end;
      }
      offset = end > start + 2 ? end : start + 2;
    }
    throw _malformed();
  }

  _PreviewTag? _readTag(int start) {
    var offset = start + 1;
    var closing = false;
    if (offset < source.length && source.codeUnitAt(offset) == 47) {
      closing = true;
      offset++;
    }
    if (offset >= source.length || !_letter(source.codeUnitAt(offset))) {
      return null;
    }
    final nameStart = offset++;
    while (offset < source.length && _nameChar(source.codeUnitAt(offset))) {
      offset++;
    }
    final name = source.substring(nameStart, offset).toLowerCase();
    var attributes = 0;
    while (offset < source.length) {
      final beforeSpace = offset;
      while (offset < source.length && _space(source.codeUnitAt(offset))) {
        offset++;
      }
      if (offset >= source.length) throw _malformed();
      final unit = source.codeUnitAt(offset);
      if (unit == 62) return _PreviewTag(name, offset + 1, closing, false);
      if (!closing &&
          unit == 47 &&
          offset + 1 < source.length &&
          source.codeUnitAt(offset + 1) == 62) {
        return _PreviewTag(name, offset + 2, false, true);
      }
      if (closing || beforeSpace == offset || !_attributeStart(unit)) {
        throw _malformed();
      }
      if (++attributes > 64) throw _tooComplex();
      offset++;
      while (offset < source.length && _nameChar(source.codeUnitAt(offset))) {
        offset++;
      }
      final afterName = offset;
      while (offset < source.length && _space(source.codeUnitAt(offset))) {
        offset++;
      }
      if (offset >= source.length) throw _malformed();
      if (source.codeUnitAt(offset) != 61) {
        // Keep the separator for the next Boolean or valued attribute.
        offset = afterName;
        continue;
      }
      offset++;
      while (offset < source.length && _space(source.codeUnitAt(offset))) {
        offset++;
      }
      if (offset >= source.length) throw _malformed();
      final quote = source.codeUnitAt(offset);
      if (quote == 34 || quote == 39) {
        offset++;
        final end = source.indexOf(String.fromCharCode(quote), offset);
        if (end < 0) throw _malformed();
        offset = end + 1;
      } else {
        final valueStart = offset;
        while (offset < source.length &&
            !_space(source.codeUnitAt(offset)) &&
            source.codeUnitAt(offset) != 62) {
          if (const <int>{
            34,
            39,
            60,
            61,
            96,
          }.contains(source.codeUnitAt(offset))) {
            throw _malformed();
          }
          offset++;
        }
        if (offset == valueStart) throw _malformed();
      }
    }
    throw _malformed();
  }

  static bool _letter(int unit) =>
      (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
  static bool _nameChar(int unit) =>
      _letter(unit) ||
      (unit >= 48 && unit <= 57) ||
      const <int>{45, 46, 58, 95}.contains(unit);
  static bool _attributeStart(int unit) =>
      _letter(unit) || unit == 58 || unit == 95;
  static bool _space(int unit) => const <int>{9, 10, 12, 13, 32}.contains(unit);
  static FormatException _malformed() => const FormatException(
    'This note contains markup that cannot be previewed safely.',
  );
  static FormatException _tooComplex() =>
      const FormatException('This note is too complex to preview.');
}

final class _PreviewTag {
  const _PreviewTag(this.name, this.end, this.closing, this.selfClosing);
  final String name;
  final int end;
  final bool closing;
  final bool selfClosing;
}

final class _PreviewElement {
  const _PreviewElement(this.tag, this.hidden, this.preformatted);
  final String tag;
  final bool hidden;
  final bool preformatted;
}

final class _PreviewTextBuilder {
  final _buffer = StringBuffer();
  int? _last;
  var _breaks = 0;
  var _explicitBreak = false;
  var _space = false;
  var _cell = false;

  void blockBreak() {
    if (_last != null && _last != 10 && _breaks == 0) _breaks = 1;
    _space = false;
    _cell = false;
  }

  void lineBreak() {
    _breaks++;
    _explicitBreak = true;
    _space = false;
    _cell = false;
  }

  void cellBreak() {
    if (_last != null && _last != 10 && _last != 9 && _breaks == 0) {
      _cell = true;
    }
    _space = false;
  }

  void text(String value, {required bool preformatted}) {
    if (preformatted) {
      if (value.isEmpty) return;
      _flush();
      _append(value.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
      return;
    }
    for (final match in RegExp(
      r'[\t\n\r\f ]+|[^\t\n\r\f ]+',
    ).allMatches(value)) {
      final token = match[0]!;
      if (_NotePreviewParser._space(token.codeUnitAt(0))) {
        _space = true;
      } else {
        _flush();
        _append(token);
      }
    }
  }

  void _flush() {
    if (_breaks > 0 && (_last != null || _explicitBreak)) {
      _append('\n' * _breaks);
    } else if (_last != null) {
      if (_cell) {
        _append('\t');
      } else if (_space && !_NotePreviewParser._space(_last!)) {
        _append(' ');
      }
    }
    _breaks = 0;
    _explicitBreak = false;
    _space = false;
    _cell = false;
  }

  void _append(String text) {
    if (text.isEmpty) return;
    _buffer.write(text);
    _last = text.codeUnitAt(text.length - 1);
  }

  String finish() {
    if (_explicitBreak) _flush();
    return _buffer.toString();
  }
}

String _decodeEntities(String text) => text.replaceAllMapped(
  RegExp(r'&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[A-Za-z][A-Za-z0-9]*);'),
  (match) {
    final entity = match[1]!;
    if (!entity.startsWith('#')) return _entities[entity] ?? match[0]!;
    final hex = entity.length > 2 && entity[1].toLowerCase() == 'x';
    final value = int.tryParse(
      entity.substring(hex ? 2 : 1),
      radix: hex ? 16 : 10,
    );
    if (value == null ||
        value <= 0 ||
        value > 0x10ffff ||
        (value >= 0xd800 && value <= 0xdfff) ||
        (value < 32 && value != 9 && value != 10 && value != 13)) {
      return '\uFFFD';
    }
    return String.fromCharCode(value);
  },
);

const _entities = <String, String>{
  'amp': '&',
  'AMP': '&',
  'lt': '<',
  'LT': '<',
  'gt': '>',
  'GT': '>',
  'quot': '"',
  'QUOT': '"',
  'apos': "'",
  'nbsp': '\u00A0',
  'ensp': '\u2002',
  'emsp': '\u2003',
  'thinsp': '\u2009',
  'ndash': '–',
  'mdash': '—',
  'lsquo': '‘',
  'rsquo': '’',
  'sbquo': '‚',
  'ldquo': '“',
  'rdquo': '”',
  'bdquo': '„',
  'bull': '•',
  'hellip': '…',
  'laquo': '«',
  'raquo': '»',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'deg': '°',
  'plusmn': '±',
  'times': '×',
  'divide': '÷',
  'minus': '−',
  'micro': 'µ',
  'middot': '·',
};
