import 'dart:convert';

import '../word/model/wml_document.dart';
import '../word/properties/wml_properties.dart';
import '../xml/xml_reader.dart';

/// An inert text span from a Zotero XHTML result.
///
/// These are supported character properties, not executable HTML or CSS.
final class ZoteroTextSpan {
  const ZoteroTextSpan({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.smallCaps = false,
    this.verticalAlign = WmlVertAlign.baseline,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool smallCaps;
  final WmlVertAlign verticalAlign;
}

/// A bounded, inert rendering of Zotero's formatted XHTML.
///
/// Supports bold, italic, underline, strike-through, small caps, subscript and
/// superscript.
/// Links are retained as text; resources, scripts and stylesheets are never
/// loaded or evaluated. Arbitrary CSS and paragraph layout are not
/// implemented. [unsupportedFormatting] reports fixed labels for those limits.
///
/// The input must be a well-formed XHTML fragment, with common HTML entities
/// and an unclosed HTML `<br>` also accepted. Malformed markup is rejected so
/// callers can retain an existing field instead of silently losing its text.
final class ZoteroFormattedText {
  ZoteroFormattedText._(
    List<ZoteroTextSpan> spans,
    Set<String> unsupported,
    List<int> paragraphBreakOffsets,
  ) : spans = List<ZoteroTextSpan>.unmodifiable(spans),
      unsupportedFormatting = Set<String>.unmodifiable(unsupported),
      paragraphBreakOffsets = List<int>.unmodifiable(paragraphBreakOffsets),
      plainText = spans.map((span) => span.text).join();

  factory ZoteroFormattedText.fromHtml(String html) => _parse(html);

  final List<ZoteroTextSpan> spans;
  final String plainText;
  final Set<String> unsupportedFormatting;

  /// UTF-16 offsets of structural block delimiters in [plainText]. Each points
  /// at one newline. Explicit `<br>` line breaks remain inside their paragraph.
  /// Outer wrappers and trailing block boundaries do not create empty entries.
  final List<int> paragraphBreakOffsets;

  /// A single atomic Word run can carry this result without losing emphasis.
  bool get hasUniformCharacterFormatting {
    if (spans.length < 2) return true;
    final first = spans.first;
    return spans.every(
      (span) =>
          span.bold == first.bold &&
          span.italic == first.italic &&
          span.underline == first.underline &&
          span.strike == first.strike &&
          span.smallCaps == first.smallCaps &&
          span.verticalAlign == first.verticalAlign,
    );
  }

  /// Builds independent Word runs, retaining the host's base font and color.
  /// Character emphasis is supplied by the result, including explicit resets.
  List<WmlRun> toRuns({WmlRunProps? baseProperties}) => <WmlRun>[
    for (final span in spans)
      WmlRun(
        text: span.text,
        properties: (baseProperties?.copy() ?? WmlRunProps())
          ..bold = span.bold
          ..italic = span.italic
          ..underline = span.underline ? WmlUnderline.single : WmlUnderline.none
          ..strike = span.strike
          ..smallCaps = span.smallCaps
          ..vertAlign = span.verticalAlign,
      ),
  ];

  /// Independent paragraph runs split only at structural block boundaries.
  /// The delimiter becomes a paragraph boundary; soft line breaks and all
  /// character formatting, including small-capital resets, remain in runs.
  List<List<WmlRun>> toParagraphRuns({WmlRunProps? baseProperties}) {
    final result = <List<WmlRun>>[<WmlRun>[]];
    var offset = 0;
    var breakIndex = 0;
    for (final run in toRuns(baseProperties: baseProperties)) {
      var start = 0;
      while (breakIndex < paragraphBreakOffsets.length &&
          paragraphBreakOffsets[breakIndex] < offset + run.text.length) {
        final end = paragraphBreakOffsets[breakIndex++] - offset;
        if (end > start) {
          result.last.add(
            WmlRun(
              text: run.text.substring(start, end),
              properties: run.properties.copy(),
            ),
          );
        }
        result.add(<WmlRun>[]);
        start = end + 1;
      }
      if (start < run.text.length) {
        result.last.add(
          WmlRun(
            text: run.text.substring(start),
            properties: run.properties.copy(),
          ),
        );
      }
      offset += run.text.length;
    }
    return result;
  }

  static const _maxBytes = 8 * 1024 * 1024;
  static const _maxDepth = 64;
  static const _maxElements = 50000;

  static ZoteroFormattedText _parse(String html) {
    if (html.length > _maxBytes || utf8.encode(html).length > _maxBytes) {
      throw const FormatException('The formatted reference is too large.');
    }
    for (final rune in html.runes) {
      if (!_xmlCharacter(rune)) throw _malformed();
    }
    final normalized = _normalize(html);
    final reader = XmlPullReader(
      '<quds-zotero-result>$normalized</quds-zotero-result>',
    );
    final stack = <_ElementState>[];
    final out = _TextBuilder();
    final unsupported = <String>{};
    var elements = 0;
    try {
      while (reader.next()) {
        switch (reader.eventType) {
          case XmlEventType.startElement:
            if (++elements > _maxElements || stack.length > _maxDepth) {
              throw const FormatException(
                'The formatted reference is too complex.',
              );
            }
            if (reader.attributeCount > 64) throw _malformed();
            final attributes = <String, String>{};
            for (var i = 0; i < reader.attributeCount; i++) {
              final name = reader.attributeQualifiedName(i);
              if (attributes.containsKey(name)) throw _malformed();
              attributes[name] = reader.attributeValue(i);
            }
            final tag = reader.localName.toLowerCase();
            final parent = stack.lastOrNull;
            final hidden = parent?.hidden == true || _discard.contains(tag);
            final classes = (attributes['class'] ?? '').split(RegExp(r'\s+'));
            final role = _role(tag, classes);
            var style = parent?.style ?? const _Style();
            if (parent?.hidden != true && _embeddedTags.contains(tag)) {
              unsupported.add('embedded content');
            }
            if (!hidden) {
              style = _style(
                tag,
                attributes['style'] ?? '',
                style,
                unsupported,
              );
              if (role == _Role.block) out.blockBreak();
              if (tag == 'br') out.lineBreak();
              if (classes.any(
                const <String>{
                  'csl-indent',
                  'csl-left-margin',
                  'csl-right-inline',
                }.contains,
              )) {
                unsupported.add('paragraph layout');
              }
              if (_layoutTags.contains(tag)) {
                unsupported.add('paragraph layout');
              }
              if (_unsupportedTags.contains(tag)) {
                unsupported.add('unsupported inline style');
              }
            }
            stack.add(_ElementState(style: style, role: role, hidden: hidden));
          case XmlEventType.endElement:
            if (stack.isEmpty) throw _malformed();
            final state = stack.removeLast();
            if (!state.hidden) {
              if (state.role == _Role.block) out.blockBreak();
              if (state.role == _Role.leftMargin) out.space();
            }
          case XmlEventType.characters:
          case XmlEventType.cdata:
            if (stack.isEmpty) throw _malformed();
            if (!stack.last.hidden) out.text(reader.text, stack.last.style);
          case XmlEventType.xmlDeclaration:
          case XmlEventType.processingInstruction:
          case XmlEventType.dtd:
            throw _malformed();
          case XmlEventType.none:
          case XmlEventType.comment:
          case XmlEventType.endDocument:
            break;
        }
      }
      if (stack.isNotEmpty) throw _malformed();
      return ZoteroFormattedText._(
        out.finish(),
        unsupported,
        out.paragraphBreakOffsets,
      );
    } on XmlParseException {
      throw _malformed();
    } on RangeError {
      throw _malformed();
    }
  }

  static const _discard = <String>{
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
    'img',
    'link',
    'meta',
    'input',
    'source',
  };
  static const _layoutTags = <String>{'table', 'tr', 'td', 'th', 'ul', 'ol'};
  static const _embeddedTags = <String>{
    'iframe',
    'object',
    'embed',
    'svg',
    'math',
    'img',
  };
  static const _unsupportedTags = <String>{
    'small',
    'big',
    'pre',
    'font',
    'tt',
    'code',
    'samp',
    'kbd',
    'mark',
    'center',
  };

  static String _normalize(String html) {
    final out = StringBuffer();
    var offset = 0;
    void fragment(String value) {
      if (value.contains(']]>')) throw _malformed();
      out.write(
        value
            .replaceAllMapped(
              RegExp(r'&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[A-Za-z][A-Za-z0-9]*);'),
              _entity,
            )
            .replaceAll(RegExp(r'<br\s*>', caseSensitive: false), '<br/>'),
      );
    }

    // Entity and HTML-void normalization must not rewrite literal CDATA or
    // ignored comments. In particular CDATA containing "&amp;" means those
    // five characters, not an encoded ampersand.
    var scan = 0;
    while (scan < html.length) {
      final start = html.indexOf('<', scan);
      if (start < 0) break;
      final comment = html.startsWith('<!--', start);
      final cdata = html.startsWith('<![CDATA[', start);
      if (!comment && !cdata) {
        scan = start + 1;
        continue;
      }
      final contentStart = start + (comment ? 4 : 9);
      final end = html.indexOf(comment ? '-->' : ']]>', contentStart);
      if (end < 0) throw _malformed();
      if (comment && html.substring(contentStart, end).contains('--')) {
        throw _malformed();
      }
      fragment(html.substring(offset, start));
      out.write(html.substring(start, end + 3));
      offset = end + 3;
      scan = offset;
    }
    fragment(html.substring(offset));
    return out.toString();
  }

  static _Role _role(String tag, List<String> classes) {
    if (classes.contains('csl-left-margin')) return _Role.leftMargin;
    if (classes.contains('csl-right-inline')) return _Role.inline;
    if (classes.contains('csl-block') ||
        classes.contains('csl-entry') ||
        classes.contains('csl-indent')) {
      return _Role.block;
    }
    return const <String>{
          'div',
          'p',
          'li',
          'blockquote',
          'tr',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
        }.contains(tag)
        ? _Role.block
        : _Role.inline;
  }

  static _Style _style(
    String tag,
    String css,
    _Style parent,
    Set<String> unsupported,
  ) {
    var bold = parent.bold;
    var italic = parent.italic;
    var underline = parent.underline;
    var strike = parent.strike;
    var smallCaps = parent.smallCaps;
    var verticalAlign = parent.verticalAlign;
    if (tag == 'b' || tag == 'strong') bold = true;
    if (tag == 'i' || tag == 'em') italic = true;
    if (tag == 'u') underline = true;
    if (tag == 's' || tag == 'strike' || tag == 'del') strike = true;
    if (tag == 'sup') verticalAlign = WmlVertAlign.superscript;
    if (tag == 'sub') verticalAlign = WmlVertAlign.subscript;
    for (final declaration in css.split(';')) {
      if (declaration.trim().isEmpty) continue;
      final colon = declaration.indexOf(':');
      if (colon < 1) {
        unsupported.add('unsupported inline style');
        continue;
      }
      final name = declaration.substring(0, colon).trim().toLowerCase();
      final value = declaration.substring(colon + 1).trim().toLowerCase();
      switch (name) {
        case 'font-style':
          if (const ['italic', 'oblique', 'normal'].contains(value)) {
            italic = value != 'normal';
          } else {
            unsupported.add('unsupported inline style');
          }
        case 'font-weight':
          final weight = int.tryParse(value);
          if (value == 'bold' || value == 'bolder') {
            bold = true;
          } else if (value == 'normal' || value == 'lighter') {
            bold = false;
          } else if (weight != null &&
              weight >= 100 &&
              weight <= 900 &&
              weight % 100 == 0) {
            bold = weight >= 600;
          } else {
            unsupported.add('unsupported inline style');
          }
        case 'text-decoration':
        case 'text-decoration-line':
          final values = value.split(RegExp(r'\s+'));
          if (values.every(
            const ['none', 'underline', 'line-through'].contains,
          )) {
            underline = values.contains('underline');
            strike = values.contains('line-through');
          } else {
            unsupported.add('unsupported inline style');
          }
        case 'vertical-align':
          switch (value) {
            case 'sup':
            case 'super':
              verticalAlign = WmlVertAlign.superscript;
            case 'sub':
              verticalAlign = WmlVertAlign.subscript;
            case 'baseline':
              verticalAlign = WmlVertAlign.baseline;
            default:
              unsupported.add('unsupported inline style');
          }
        case 'font-variant':
        case 'font-variant-caps':
          if (value == 'small-caps' || value == 'normal') {
            smallCaps = value == 'small-caps';
          } else {
            unsupported.add('unsupported inline style');
          }
        case 'line-height':
        case 'text-indent':
        case 'text-align':
        case 'margin':
        case 'margin-left':
        case 'margin-right':
        case 'margin-top':
        case 'margin-bottom':
        case 'padding':
        case 'padding-left':
        case 'padding-right':
        case 'display':
          unsupported.add('paragraph layout');
        default:
          unsupported.add('unsupported inline style');
      }
    }
    return _Style(
      bold: bold,
      italic: italic,
      underline: underline,
      strike: strike,
      smallCaps: smallCaps,
      verticalAlign: verticalAlign,
    );
  }

  static String _entity(Match match) {
    final name = match[1]!;
    final int? codePoint;
    if (name.startsWith('#')) {
      final hex = name.length > 2 && name[1].toLowerCase() == 'x';
      codePoint = int.tryParse(
        name.substring(hex ? 2 : 1),
        radix: hex ? 16 : 10,
      );
    } else {
      codePoint = _entities[name];
    }
    if (codePoint == null || !_xmlCharacter(codePoint)) {
      throw const FormatException(
        'The formatted reference contains an unsupported HTML entity.',
      );
    }
    return '&#$codePoint;';
  }

  static bool _xmlCharacter(int value) =>
      value == 9 ||
      value == 10 ||
      value == 13 ||
      (value >= 0x20 && value <= 0xd7ff) ||
      (value >= 0xe000 && value <= 0xfffd) ||
      (value >= 0x10000 && value <= 0x10ffff);

  static FormatException _malformed() => const FormatException(
    'Zotero returned malformed formatted text. The existing field was kept.',
  );

  static const _entities = <String, int>{
    'amp': 38,
    'lt': 60,
    'gt': 62,
    'quot': 34,
    'apos': 39,
    'nbsp': 160,
    'ensp': 8194,
    'emsp': 8195,
    'thinsp': 8201,
    'ndash': 8211,
    'mdash': 8212,
    'lsquo': 8216,
    'rsquo': 8217,
    'sbquo': 8218,
    'ldquo': 8220,
    'rdquo': 8221,
    'bdquo': 8222,
    'bull': 8226,
    'hellip': 8230,
    'laquo': 171,
    'raquo': 187,
    'copy': 169,
    'reg': 174,
    'trade': 8482,
    'deg': 176,
    'plusmn': 177,
    'times': 215,
    'divide': 247,
    'minus': 8722,
    'micro': 181,
    'middot': 183,
  };
}

enum _Role { inline, block, leftMargin }

final class _ElementState {
  const _ElementState({
    required this.style,
    required this.role,
    required this.hidden,
  });
  final _Style style;
  final _Role role;
  final bool hidden;
}

final class _Style {
  const _Style({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.smallCaps = false,
    this.verticalAlign = WmlVertAlign.baseline,
  });
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool smallCaps;
  final WmlVertAlign verticalAlign;

  bool sameAs(_Style other) =>
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      strike == other.strike &&
      smallCaps == other.smallCaps &&
      verticalAlign == other.verticalAlign;
  ZoteroTextSpan span(String text) => ZoteroTextSpan(
    text: text,
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    smallCaps: smallCaps,
    verticalAlign: verticalAlign,
  );
}

final class _TextBuilder {
  static const _maxSpans = 10000;
  final _spans = <ZoteroTextSpan>[];
  final _buffer = StringBuffer();
  _Style? _style;
  var _hasText = false;
  var _endsWithBreak = false;
  var _pendingSpace = false;
  var _pendingBreaks = 0;
  var _explicitBreak = false;
  var _pendingBlockBreak = false;
  var _length = 0;
  final paragraphBreakOffsets = <int>[];

  void space() {
    if (_hasText && _pendingBreaks == 0) _pendingSpace = true;
  }

  void blockBreak() {
    if (_hasText && _pendingBreaks == 0) _pendingBreaks = 1;
    if (_hasText) _pendingBlockBreak = true;
    _pendingSpace = false;
  }

  void lineBreak() {
    _pendingBreaks++;
    _pendingSpace = false;
    _explicitBreak = true;
  }

  void text(String text, _Style style) {
    for (final match in RegExp(
      r'[\t\n\r\f ]+|[^\t\n\r\f ]+',
    ).allMatches(text)) {
      final token = match[0]!;
      if (RegExp(r'^[\t\n\r\f ]').hasMatch(token)) {
        space();
        continue;
      }
      if (_pendingBreaks > 0) {
        if (_pendingBlockBreak) paragraphBreakOffsets.add(_length);
        _append('\n' * _pendingBreaks, style);
      } else if (_pendingSpace && !_endsWithBreak) {
        _append(' ', style);
      }
      _pendingBreaks = 0;
      _explicitBreak = false;
      _pendingBlockBreak = false;
      _pendingSpace = false;
      _append(token, style);
    }
  }

  void _append(String text, _Style style) {
    if (_style != null && !_style!.sameAs(style)) _flush();
    _style = style;
    _buffer.write(text);
    _length += text.length;
    _hasText = true;
    _endsWithBreak = text.endsWith('\n');
  }

  void _flush() {
    if (_buffer.isEmpty) return;
    if (_spans.length >= _maxSpans) {
      throw const FormatException(
        'The formatted reference has too many text spans.',
      );
    }
    _spans.add(_style!.span(_buffer.toString()));
    _buffer.clear();
  }

  List<ZoteroTextSpan> finish() {
    if (_explicitBreak) {
      _append('\n' * _pendingBreaks, _style ?? const _Style());
    }
    _flush();
    return _spans;
  }
}
