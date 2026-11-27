import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:quds_office_engine/quds_office_engine.dart';

const wordClipboardLimit = 2 * 1024 * 1024;

/// Projects clipboard HTML into editable Word blocks without loading resources.
List<WmlBlock> readWordClipboardHtml(String source) {
  if (source.isEmpty || source.length > wordClipboardLimit) return [];
  final document = html.parse(source);
  final body = document.body;
  if (body == null) return [];
  final start = source.indexOf('<!--StartFragment-->');
  final end = source.indexOf('<!--EndFragment-->');
  final reader = _HtmlClipboard(document, fragment: start >= 0 && end > start);
  reader.walk(body, (WmlRunProps(), WmlParagraphProps(), null, false), 0);
  reader.flush();
  return reader.blocks;
}

typedef _Style = (WmlRunProps, WmlParagraphProps, WmlHyperlink?, bool);

class _HtmlClipboard {
  _HtmlClipboard(dom.Document document, {required bool fragment})
    : _insideFragment = !fragment {
    // Word fragments sometimes place the actual styles in their HTML header.
    for (final style in document.querySelectorAll('style').take(8)) {
      final css = style.text.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
      for (final match in _rules.allMatches(css).take(128)) {
        final declarations = _declarations(match[2]!);
        for (final raw in match[1]!.split(',').take(12)) {
          final selector = raw.trim();
          if (styles.length == 128) return;
          if (_simpleSelector.hasMatch(selector)) {
            styles.add((selector, declarations));
          }
        }
      }
    }
  }

  static final _rules = RegExp(r'([^{}]+)\{([^{}]*)\}');
  static final _simpleSelector = RegExp(r'^(?:[\w-]+)?(?:\.[\w-]+)*$');
  static final _whitespace = RegExp(r'[\t\r\n\f ]+');
  static const _container = {
    'address',
    'article',
    'aside',
    'blockquote',
    'div',
    'dl',
    'dt',
    'dd',
    'main',
    'section',
    'header',
    'footer',
    'figure',
    'figcaption',
    'table',
    'thead',
    'tbody',
    'tfoot',
    'tr',
  };
  static const _paragraphTags = {
    'p',
    'pre',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  };
  static const _hidden = {
    'script',
    'style',
    'template',
    'noscript',
    'iframe',
    'object',
    'embed',
    'svg',
    'math',
    'select',
    'textarea',
    'button',
    'audio',
    'video',
  };

  final styles = <(String, Map<String, String>)>[];
  final blocks = <WmlBlock>[];
  WmlParagraph? _paragraph;
  var _pendingSpace = false;
  var _lineStart = true;
  bool _insideFragment;
  var _nodes = 0;

  void flush({bool empty = false}) {
    final paragraph = _paragraph;
    if (paragraph != null && (empty || paragraph.inlines.isNotEmpty)) {
      blocks.add(paragraph);
    }
    _paragraph = null;
    _pendingSpace = false;
    _lineStart = true;
  }

  void _append(String text, _Style style) {
    if (!style.$4) {
      // HTML collapses ASCII whitespace, including across inline elements.
      text = text.replaceAll(_whitespace, ' ');
      final startsWithSpace = text.startsWith(' ');
      final endsWithSpace = text.endsWith(' ');
      text = text.trimAscii();
      if (text.isEmpty) {
        _pendingSpace |= startsWithSpace;
        return;
      }
      if (!_lineStart && (_pendingSpace || startsWithSpace)) text = ' $text';
      _pendingSpace = endsWithSpace;
    }
    if (text.isEmpty) return;
    _lineStart = text.endsWith('\n');
    (_paragraph ??= WmlParagraph(properties: style.$2.copy())).inlines.add(
      WmlRun(text: text, properties: style.$1.copy(), hyperlink: style.$3),
    );
  }

  void walk(dom.Node node, _Style parent, int depth) {
    if (depth > 80 || ++_nodes > 20000) {
      throw const FormatException('Clipboard HTML exceeds structural limits');
    }
    if (node is dom.Comment) {
      if (node.data == 'StartFragment') _insideFragment = true;
      if (node.data == 'EndFragment') _insideFragment = false;
      return;
    }
    if (node is dom.Text) {
      if (_insideFragment) _append(node.data, parent);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName!;
    if (_hidden.contains(tag) || node.attributes.containsKey('hidden')) return;
    final css = <String, String>{
      for (final (selector, declarations) in styles)
        if (_matches(node, selector)) ...declarations,
      ..._declarations(node.attributes['style'] ?? ''),
    };
    if (css['display'] == 'none' ||
        css['visibility'] == 'hidden' ||
        css['mso-hide'] == 'all') {
      return;
    }
    final style = _derive(node, parent, css);
    if (tag == 'br') {
      if (!_insideFragment) return;
      final paragraph = _paragraph ??= WmlParagraph(
        properties: style.$2.copy(),
      );
      paragraph.inlines.add(WmlBreak(WmlBreakType.textWrapping));
      _pendingSpace = false;
      _lineStart = true;
      return;
    }
    if (tag == 'img') {
      final alt = node.attributes['alt'];
      if (_insideFragment && alt != null) _append(alt, style);
      return;
    }
    if (tag == 'ul' || tag == 'ol') {
      flush();
      var number = int.tryParse(node.attributes['start'] ?? '') ?? 1;
      for (final child in node.children.where(
        (child) => child.localName == 'li',
      )) {
        final label = tag == 'ol' ? '${number++}. ' : '• ';
        if (_insideFragment) {
          _append(label, style);
          _pendingSpace = true;
        }
        for (final part in child.nodes) {
          walk(part, style, depth + 1);
        }
        flush();
      }
      return;
    }
    final paragraph = _paragraphTags.contains(tag);
    final container = _container.contains(tag);
    if (paragraph || container) flush();
    final preserveEmpty = paragraph && _insideFragment;
    if (preserveEmpty) _paragraph = WmlParagraph(properties: style.$2.copy());
    if (_insideFragment && (tag == 'td' || tag == 'th') && _paragraph != null) {
      _append('\t', (style.$1, style.$2, null, true));
    }
    for (final child in node.nodes) {
      walk(child, style, depth + 1);
    }
    if (paragraph || container) flush(empty: preserveEmpty);
  }

  bool _matches(dom.Element node, String selector) {
    final parts = selector.split('.');
    return (parts.first.isEmpty || parts.first == node.localName) &&
        parts.skip(1).every(node.classes.contains);
  }

  _Style _derive(dom.Element node, _Style parent, Map<String, String> css) {
    final tag = node.localName;
    final run = parent.$1.copy();
    final paragraph = parent.$2.copy();
    final heading = _paragraphTags.contains(tag) && tag!.startsWith('h')
        ? int.parse(tag[1])
        : null;
    if (heading != null) {
      run.bold = true;
      run.fontSizeHalfPoints = [48, 36, 30, 26, 22, 20][heading - 1];
    }
    if (tag == 'b' || tag == 'strong' || tag == 'th') run.bold = true;
    if (tag == 'i' || tag == 'em') run.italic = true;
    if (tag == 'u' || tag == 'ins') run.underline = WmlUnderline.single;
    if (tag == 's' || tag == 'strike' || tag == 'del') run.strike = true;
    if (tag == 'sup') run.vertAlign = WmlVertAlign.superscript;
    if (tag == 'sub') run.vertAlign = WmlVertAlign.subscript;
    if (tag == 'mark') run.highlight = 'FFFF00';
    if (tag == 'pre' || tag == 'code' || tag == 'tt') {
      run.asciiFont = run.csFont = 'Courier New';
    }
    var link = parent.$3;
    if (tag == 'a') {
      final href = node.attributes['href']?.trim();
      final uri = href == null ? null : Uri.tryParse(href);
      if (uri != null &&
          ((const {'http', 'https'}.contains(uri.scheme) && uri.hasAuthority) ||
              (uri.scheme == 'mailto' && uri.path.isNotEmpty)) &&
          !href!.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        link = WmlHyperlink(url: href);
        run.underline = WmlUnderline.single;
        run.color = '0563C1';
      }
    }
    final weight = css['font-weight'];
    if (weight == 'bold' ||
        weight == 'bolder' ||
        (int.tryParse(weight ?? '') ?? 0) >= 600) {
      run.bold = true;
    } else if (weight == 'normal' ||
        weight == 'lighter' ||
        int.tryParse(weight ?? '') != null) {
      run.bold = false;
    }
    final italic = css['font-style'];
    if (italic == 'italic' || italic?.startsWith('oblique') == true) {
      run.italic = true;
    }
    if (italic == 'normal') run.italic = false;
    final decoration = css['text-decoration-line'] ?? css['text-decoration'];
    if (decoration != null) {
      run.underline = decoration.contains('underline')
          ? WmlUnderline.single
          : WmlUnderline.none;
      run.strike = decoration.contains('line-through');
    }
    final color = wordClipboardColor(css['color'] ?? node.attributes['color']);
    if (color != null) run.color = color;
    final highlight = wordClipboardColor(
      css['background-color'] ?? css['background'],
    );
    if (highlight != null) run.highlight = highlight;
    final font = (css['font-family'] ?? node.attributes['face'])
        ?.split(',')
        .first
        .replaceAll(RegExp("[\"']"), '')
        .trim();
    if (font != null && font.isNotEmpty && font.length <= 128) {
      run.asciiFont = run.csFont = font;
    }
    final size = RegExp(
      r'^(\d+(?:\.\d+)?)(pt|px|em|rem|%)$',
    ).firstMatch(css['font-size'] ?? '');
    if (size != null) {
      final value = double.parse(size[1]!);
      final halfPoints = switch (size[2]) {
        'px' => value * 1.5,
        'em' => value * parent.$1.fontSizeHalfPoints,
        'rem' => value * 24,
        '%' => value * parent.$1.fontSizeHalfPoints / 100,
        _ => value * 2,
      };
      run.fontSizeHalfPoints = halfPoints.clamp(2, 800).round();
    }
    switch (css['vertical-align']) {
      case 'super':
        run.vertAlign = WmlVertAlign.superscript;
      case 'sub':
        run.vertAlign = WmlVertAlign.subscript;
      case 'baseline':
        run.vertAlign = WmlVertAlign.baseline;
    }
    final direction = css['direction'] ?? node.attributes['dir']?.toLowerCase();
    if (direction == 'rtl' || direction == 'ltr') {
      paragraph.rightToLeft = direction == 'rtl';
    }
    final alignment = switch (css['text-align'] ??
        node.attributes['align']?.toLowerCase()) {
      'center' => WmlJustification.center,
      'justify' => WmlJustification.justify,
      'right' => WmlJustification.right,
      'left' => WmlJustification.left,
      'start' =>
        paragraph.rightToLeft == true
            ? WmlJustification.right
            : WmlJustification.left,
      'end' =>
        paragraph.rightToLeft == true
            ? WmlJustification.left
            : WmlJustification.right,
      _ => null,
    };
    if (alignment != null) {
      paragraph.justification = alignment;
      paragraph.explicitJustification = true;
    }
    final preserveWhitespace = switch (css['white-space']) {
      'pre' || 'pre-wrap' || 'break-spaces' => true,
      'normal' || 'nowrap' => false,
      _ => tag == 'pre' || parent.$4,
    };
    return (run, paragraph, link, preserveWhitespace);
  }
}

Map<String, String> _declarations(String css) => {
  for (final declaration in css.split(';'))
    if (declaration.indexOf(':') case final colon when colon > 0)
      declaration.substring(0, colon).trim().toLowerCase(): declaration
          .substring(colon + 1)
          .replaceFirst(RegExp(r'\s*!important\s*$', caseSensitive: false), '')
          .trim(),
};

String? wordClipboardColor(String? raw) {
  final value = raw?.toLowerCase().trim();
  if (value == null) return null;
  final hex = RegExp(r'^#?([\da-f]{3}|[\da-f]{6})$').firstMatch(value)?[1];
  if (hex != null) {
    return (hex.length == 3
            ? hex.split('').map((digit) => digit * 2).join()
            : hex)
        .toUpperCase();
  }
  final rgb = RegExp(
    r'^rgba?\(\s*(\d+(?:\.\d+)?%?)[,\s]+(\d+(?:\.\d+)?%?)[,\s]+(\d+(?:\.\d+)?%?)(?:\s*[,/]\s*([\d.]+%?))?\s*\)$',
  ).firstMatch(value);
  if (rgb != null) {
    if (rgb[4] != null && double.tryParse(rgb[4]!.replaceAll('%', '')) == 0) {
      return null;
    }
    String channel(String str) {
      final percent = str.endsWith('%');
      final n = double.parse(percent ? str.substring(0, str.length - 1) : str);
      return (percent ? n * 255 / 100 : n)
          .clamp(0, 255)
          .round()
          .toRadixString(16)
          .padLeft(2, '0');
    }

    return [
      channel(rgb[1]!),
      channel(rgb[2]!),
      channel(rgb[3]!),
    ].join().toUpperCase();
  }
  return _namedColors[value];
}

const _namedColors = {
  'black': '000000',
  'white': 'FFFFFF',
  'red': 'FF0000',
  'green': '008000',
  'blue': '0000FF',
  'yellow': 'FFFF00',
  'gray': '808080',
  'grey': '808080',
  'orange': 'FFA500',
  'purple': '800080',
  'navy': '000080',
  'teal': '008080',
  'cyan': '00FFFF',
  'magenta': 'FF00FF',
  'lime': '00FF00',
  'silver': 'C0C0C0',
  'maroon': '800000',
  'olive': '808000',
  'aqua': '00FFFF',
  'fuchsia': 'FF00FF',
};

extension on String {
  // String.trim also strips NBSP, which is meaningful in Word and HTML.
  String trimAscii() =>
      replaceFirst(RegExp(r'^ +'), '').replaceFirst(RegExp(r' +$'), '');
}
