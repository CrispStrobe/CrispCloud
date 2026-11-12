import 'dart:convert';
import 'dart:typed_data';

import 'rtf_codepages.dart';

enum RtfDocumentErrorCode {
  malformed,
  unsupportedCodePage,
  unsupportedFeature,
  resourceLimit,
}

class RtfDocumentException implements Exception {
  const RtfDocumentException(this.code);
  final RtfDocumentErrorCode code;
  @override
  String toString() => 'RtfDocumentException(${code.name})';
}

class RtfDocument {
  const RtfDocument({
    required this.plainText,
    required this.markdown,
    required this.html,
  });
  final String plainText;
  final String markdown;

  /// Generated from escaped text and fixed formatting tags only. No original
  /// HTML, URLs, images, fields, scripts or embedded objects enter this markup.
  final String html;
}

const kRtfInputLimit = 8 * 1024 * 1024;
const kRtfTextLimit = 4 * 1024 * 1024;

/// A bounded RTF 1 reader authored from Microsoft's RTF 1.9.1 specification.
/// Preserves basic runs, paragraph alignment, explicit list markers and flat
/// tables. It neither executes fields/objects nor resolves any external URL.
RtfDocument parseRtfDocument(Uint8List bytes) => _RtfParser(bytes).parse();

class _State {
  bool skip = false;
  bool starred = false;
  bool fontTable = false;
  bool listText = false;
  bool hidden = false;
  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool strike = false;
  bool inTable = false;
  int codePage = 1252;
  int unicodeFallback = 1;
  int font = 0;
  int list = 0;
  int level = 0;
  int uprChildren = -1;
  String alignment = 'left';

  _State copy() => _State()
    ..skip = skip
    ..fontTable = fontTable
    ..listText = listText
    ..hidden = hidden
    ..bold = bold
    ..italic = italic
    ..underline = underline
    ..strike = strike
    ..inTable = inTable
    ..codePage = codePage
    ..unicodeFallback = unicodeFallback
    ..font = font
    ..list = list
    ..level = level
    ..alignment = alignment;
  int get style =>
      (bold ? 1 : 0) |
      (italic ? 2 : 0) |
      (underline ? 4 : 0) |
      (strike ? 8 : 0);
}

class _Run {
  _Run(this.style);
  final int style;
  final text = StringBuffer();
}

sealed class _Block {}

class _Paragraph extends _Block {
  final runs = <_Run>[];
  String alignment = 'left';
  String marker = '';
  int level = 0;
  bool list = false;
  bool get isEmpty => runs.isEmpty && marker.isEmpty;
}

class _Table extends _Block {
  final rows = <List<List<_Paragraph>>>[];
}

class _RtfParser {
  _RtfParser(this.bytes);
  final Uint8List bytes;
  final states = <_State>[];
  final fontCodePages = <int, int>{};
  final blocks = <_Block>[];
  final pending = <int>[];
  final cell = <_Paragraph>[];
  final row = <List<_Paragraph>>[];
  _State state = _State();
  _Paragraph paragraph = _Paragraph();
  final marker = StringBuffer();
  int position = 0;
  int fallback = 0;
  int controls = 0;
  int textLength = 0;
  int defaultFont = 0;
  bool rootClosed = false;

  Never fail([RtfDocumentErrorCode code = RtfDocumentErrorCode.malformed]) =>
      throw RtfDocumentException(code);

  RtfDocument parse() {
    if (bytes.length > kRtfInputLimit) fail(RtfDocumentErrorCode.resourceLimit);
    if (bytes.length < 6 || latin1.decode(bytes.sublist(0, 6)) != r'{\rtf1') {
      fail();
    }
    while (position < bytes.length) {
      final byte = bytes[position++];
      if (rootClosed) {
        if (byte != 9 && byte != 10 && byte != 13 && byte != 32 && byte != 0) {
          fail();
        }
        continue;
      }
      if (byte == 0x7b) {
        flushBytes();
        fallback = 0;
        if (++controls > 250000 || states.length >= 128) {
          fail(RtfDocumentErrorCode.resourceLimit);
        }
        final parent = state;
        state = parent.copy();
        if (parent.uprChildren >= 0) {
          parent.uprChildren++;
          if (parent.uprChildren > 2) fail();
          if (parent.uprChildren == 1) state.skip = true;
        }
        states.add(parent);
      } else if (byte == 0x7d) {
        flushBytes();
        fallback = 0;
        if (states.isEmpty ||
            (state.uprChildren >= 0 && state.uprChildren != 2)) {
          fail();
        }
        final previous = state;
        state = states.removeLast();
        if (previous.listText && !state.listText) {
          paragraph.marker = marker.toString().trim();
          marker.clear();
        }
        if (states.isEmpty) rootClosed = true;
      } else if (byte == 0x5c) {
        readControl();
      } else if (byte != 10 && byte != 13) {
        if (states.isEmpty) fail();
        emitByte(byte);
      }
    }
    flushBytes();
    if (!rootClosed || states.isNotEmpty) fail();
    if (!paragraph.isEmpty) finishParagraph();
    if (cell.isNotEmpty || row.isNotEmpty) finishRow();
    final plain = StringBuffer();
    final markdown = StringBuffer();
    final html = StringBuffer();
    for (final block in blocks) {
      if (block is _Paragraph) {
        plain.writeln(_paragraphText(block));
        markdown.writeln('${_paragraphMarkdown(block)}\n');
        html.write(_paragraphHtml(block));
      } else if (block is _Table) {
        html.write('<table><tbody>');
        for (var index = 0; index < block.rows.length; index++) {
          final cells = block.rows[index];
          plain.writeln(
            cells
                .map((parts) => parts.map(_paragraphText).join('\n'))
                .join('\t'),
          );
          markdown.writeln(
            '| ${cells.map((parts) => parts.map(_paragraphMarkdown).join(' / ')).join(' | ')} |',
          );
          if (index == 0) {
            markdown.writeln(
              '| ${List.filled(cells.length, '---').join(' | ')} |',
            );
          }
          html.write('<tr>');
          for (final parts in cells) {
            html.write('<td>${parts.map(_paragraphHtml).join()}</td>');
          }
          html.write('</tr>');
        }
        markdown.writeln();
        html.write('</tbody></table>');
      }
      if (plain.length > kRtfTextLimit ||
          html.length > 24 * 1024 * 1024 ||
          markdown.length > 16 * 1024 * 1024) {
        fail(RtfDocumentErrorCode.resourceLimit);
      }
    }
    final plainText = _removeFinalNewline(plain.toString());
    _validateUnicode(plainText);
    return RtfDocument(
      plainText: plainText,
      markdown: markdown.toString().trimRight(),
      html: html.toString(),
    );
  }

  void readControl() {
    if (position >= bytes.length) fail();
    if (++controls > 250000) {
      fail(RtfDocumentErrorCode.resourceLimit);
    }
    final first = bytes[position++];
    if (first == 0x27) {
      if (position + 2 > bytes.length) fail();
      final hex = int.tryParse(
        String.fromCharCodes(bytes.sublist(position, position + 2)),
        radix: 16,
      );
      if (hex == null) fail();
      position += 2;
      emitByte(hex);
      return;
    }
    flushBytes();
    if (!_letter(first)) {
      if (fallback > 0) {
        fallback--;
        return;
      }
      if (first == 0x2a) {
        state.starred = true;
        return;
      }
      final character = switch (first) {
        0x5c => r'\',
        0x7b => '{',
        0x7d => '}',
        0x7e => '\u00a0',
        0x2d => '\u00ad',
        0x5f => '\u2011',
        10 || 13 => '\n',
        _ => '',
      };
      emit(character);
      return;
    }
    final start = position - 1;
    while (position < bytes.length && _letter(bytes[position])) {
      position++;
    }
    if (position - start > 64) fail(RtfDocumentErrorCode.resourceLimit);
    final word = ascii.decode(bytes.sublist(start, position));
    final numberStart = position;
    if (position < bytes.length && bytes[position] == 0x2d) position++;
    final digitsStart = position;
    while (position < bytes.length && _digit(bytes[position])) {
      position++;
    }
    if (position - digitsStart > 10) fail();
    final number = position > digitsStart
        ? int.tryParse(ascii.decode(bytes.sublist(numberStart, position)))
        : null;
    if (position > numberStart && number == null) fail();
    if (number != null && (number < -2147483648 || number > 2147483647)) fail();
    if (position < bytes.length && bytes[position] == 32) position++;
    if (word == 'bin') {
      if (number == null || number < 0 || number > bytes.length - position) {
        fail();
      }
      position += number;
      if (fallback > 0) fallback--;
      return;
    }
    if (fallback > 0) {
      fallback--;
      return;
    }
    if (state.starred) {
      state.starred = false;
      if (word != 'ud') state.skip = true;
    }
    if (word == 'fonttbl') state.fontTable = true;
    if (_destinations.contains(word)) state.skip = true;
    if (state.fontTable) {
      if (word == 'f' && number != null) state.font = number;
      if (word == 'fcharset' && number != null) {
        fontCodePages[state.font] = _fontCharset(number, state.codePage);
      }
      if (word == 'cpg' && number != null) fontCodePages[state.font] = number;
      return;
    }
    if (state.skip) return;
    final enabled = number != 0;
    switch (word) {
      case 'rtf':
        if (number != 1) fail();
      case 'ansi':
        state.codePage = 1252;
      case 'mac':
        state.codePage = 10000;
      case 'pc':
        state.codePage = 437;
      case 'pca':
        state.codePage = 850;
      case 'ansicpg':
        if (number == null || number < 0) fail();
        state.codePage = number;
      case 'deff':
        if (number != null) defaultFont = state.font = number;
      case 'f':
        if (number != null) state.font = number;
      case 'uc':
        if (number == null || number < 0 || number > 255) fail();
        state.unicodeFallback = number;
      case 'u':
        if (number == null || number < -32768 || number > 65535) fail();
        emit(String.fromCharCode(number & 0xffff));
        fallback = state.unicodeFallback;
      case 'upr':
        state.uprChildren = 0;
      case 'b':
        state.bold = enabled;
      case 'i':
        state.italic = enabled;
      case 'ul':
      case 'uldb':
      case 'ulw':
        state.underline = enabled;
      case 'ulnone':
        state.underline = false;
      case 'strike':
      case 'striked':
      case 'deleted':
        state.strike = enabled;
      case 'v':
        state.hidden = enabled;
      case 'plain':
        state.bold = state.italic = state.underline = state.strike =
            state.hidden = false;
        state.font = defaultFont;
      case 'pard':
        state.alignment = 'left';
        state.inTable = false;
        state.list = 0;
        state.level = 0;
      case 'ql':
        state.alignment = 'left';
      case 'qr':
        state.alignment = 'right';
      case 'qc':
        state.alignment = 'center';
      case 'qj':
        state.alignment = 'justify';
      case 'listtext':
      case 'pntext':
        state.listText = true;
        marker.clear();
      case 'ls':
        state.list = number ?? 0;
      case 'ilvl':
        state.level = (number ?? 0).clamp(0, 8);
      case 'intbl':
        state.inTable = enabled;
      case 'itap':
        if ((number ?? 0) > 1) fail(RtfDocumentErrorCode.unsupportedFeature);
      case 'par':
        finishParagraph(force: true);
      case 'line':
        emit('\n');
      case 'tab':
        emit('\t');
      case 'cell':
        finishCell();
      case 'row':
        finishRow();
      case 'nestcell':
      case 'nestrow':
        fail(RtfDocumentErrorCode.unsupportedFeature);
      case 'page':
      case 'sect':
        finishParagraph(force: true);
      case 'emdash':
        emit('\u2014');
      case 'endash':
        emit('\u2013');
      case 'emspace':
        emit('\u2003');
      case 'enspace':
        emit('\u2002');
      case 'bullet':
        emit('\u2022');
      case 'lquote':
        emit('\u2018');
      case 'rquote':
        emit('\u2019');
      case 'ldblquote':
        emit('\u201c');
      case 'rdblquote':
        emit('\u201d');
      default:
        break;
    }
  }

  void emitByte(int byte) {
    if (fallback > 0) {
      fallback--;
      return;
    }
    if (state.skip || state.hidden) return;
    if (pending.length + textLength >= kRtfTextLimit) {
      fail(RtfDocumentErrorCode.resourceLimit);
    }
    pending.add(byte);
  }

  void flushBytes() {
    if (pending.isEmpty) return;
    final page = fontCodePages[state.font] ?? state.codePage;
    String text;
    try {
      text = decodeRtfCodePage(pending, page);
    } on UnsupportedError {
      fail(RtfDocumentErrorCode.unsupportedCodePage);
    } on FormatException {
      fail();
    }
    pending.clear();
    emit(text);
  }

  void emit(String text) {
    if (text.isEmpty || state.skip || state.hidden) return;
    textLength += text.length;
    if (textLength > kRtfTextLimit) fail(RtfDocumentErrorCode.resourceLimit);
    if (text.codeUnits.any((unit) => unit < 32 && unit != 9 && unit != 10)) {
      fail();
    }
    if (state.listText) {
      marker.write(text);
      return;
    }
    paragraph.alignment = state.alignment;
    paragraph.list = state.list != 0;
    paragraph.level = state.level;
    if (paragraph.runs.isEmpty || paragraph.runs.last.style != state.style) {
      paragraph.runs.add(_Run(state.style));
    }
    paragraph.runs.last.text.write(text);
  }

  void finishParagraph({bool force = false}) {
    if (!force && paragraph.isEmpty) return;
    if (blocks.length + cell.length + row.length > 50000) {
      fail(RtfDocumentErrorCode.resourceLimit);
    }
    if (state.inTable || cell.isNotEmpty || row.isNotEmpty) {
      cell.add(paragraph);
    } else {
      blocks.add(paragraph);
    }
    paragraph = _Paragraph();
  }

  void finishCell() {
    if (!paragraph.isEmpty || cell.isEmpty) {
      cell.add(paragraph);
      paragraph = _Paragraph();
    }
    if (row.length >= 256) fail(RtfDocumentErrorCode.resourceLimit);
    row.add(List.of(cell));
    cell.clear();
  }

  void finishRow() {
    if (!paragraph.isEmpty || cell.isNotEmpty || row.isEmpty) finishCell();
    final table = blocks.lastOrNull is _Table
        ? blocks.last as _Table
        : _Table();
    if (blocks.lastOrNull != table) blocks.add(table);
    if (table.rows.length >= 10000) fail(RtfDocumentErrorCode.resourceLimit);
    table.rows.add(List.of(row));
    row.clear();
  }
}

bool _letter(int value) =>
    value >= 65 && value <= 90 || value >= 97 && value <= 122;
bool _digit(int value) => value >= 48 && value <= 57;
String _removeFinalNewline(String value) =>
    value.endsWith('\n') ? value.substring(0, value.length - 1) : value;
String _escape(String value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value);
String _markdown(String value) => value.replaceAllMapped(
  RegExp(r'[\\`*_{}\[\]<>#|]'),
  (match) => '\\${match[0]}',
);
String _prefix(_Paragraph paragraph) => paragraph.marker.isNotEmpty
    ? paragraph.marker
    : paragraph.list
    ? '•'
    : '';
String _paragraphText(_Paragraph paragraph) {
  final prefix = _prefix(paragraph);
  return '${prefix.isEmpty ? '' : '$prefix '}'
      '${paragraph.runs.map((run) => run.text.toString()).join()}';
}

String _paragraphMarkdown(_Paragraph paragraph) {
  final prefix = _prefix(paragraph);
  final text = paragraph.runs
      .map((run) {
        var text = _markdown(run.text.toString());
        if ((run.style & 1) != 0) text = '**$text**';
        if ((run.style & 2) != 0) text = '*$text*';
        if ((run.style & 8) != 0) text = '~~$text~~';
        return text;
      })
      .join()
      .replaceAll('\n', '  \n');
  return '${prefix.isEmpty ? '' : '${prefix == '•' || prefix == '·' ? '-' : _markdown(prefix)} '}'
      '$text';
}

String _paragraphHtml(_Paragraph paragraph) {
  var text = paragraph.runs.map((run) {
    var text = _escape(run.text.toString())
        .replaceAll('\n', '<br>')
        .replaceAll('\t', '&#9;');
    if ((run.style & 1) != 0) text = '<strong>$text</strong>';
    if ((run.style & 2) != 0) text = '<em>$text</em>';
    if ((run.style & 4) != 0) text = '<u>$text</u>';
    if ((run.style & 8) != 0) text = '<s>$text</s>';
    return text;
  }).join();
  if (text.isEmpty) text = '<br>';
  final prefix = _prefix(paragraph);
  final style = 'text-align:${paragraph.alignment};white-space:pre-wrap';
  if (prefix == '•' || prefix == '·') {
    return '<ul><li style="$style">$text</li></ul>';
  }
  final numeric = RegExp(r'^(\d{1,6})[.)]$').firstMatch(prefix);
  if (numeric != null) {
    return '<ol start="${numeric[1]}"><li style="$style">$text</li></ol>';
  }
  return '<p style="$style">${prefix.isEmpty ? '' : '${_escape(prefix)} '}$text</p>';
}

void _validateUnicode(String text) {
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= text.length ||
          text.codeUnitAt(index) < 0xdc00 ||
          text.codeUnitAt(index) > 0xdfff) {
        throw const RtfDocumentException(RtfDocumentErrorCode.malformed);
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const RtfDocumentException(RtfDocumentErrorCode.malformed);
    }
  }
}

int _fontCharset(int charset, int fallback) => switch (charset) {
  0 || 1 => fallback,
  2 => 42,
  77 => 10000,
  128 => 932,
  129 => 949,
  134 => 936,
  136 => 950,
  161 => 1253,
  162 => 1254,
  163 => 1258,
  177 => 1255,
  178 => 1256,
  186 => 1257,
  204 => 1251,
  222 => 874,
  238 => 1250,
  254 => 437,
  255 => 850,
  _ => -1,
};

const _destinations = {
  'fonttbl',
  'colortbl',
  'stylesheet',
  'info',
  'filetbl',
  'revtbl',
  'rsidtbl',
  'listtable',
  'listoverridetable',
  'listpicture',
  'latentstyles',
  'xmlnstbl',
  'generator',
  'datastore',
  'themedata',
  'colorschememapping',
  'fontemb',
  'fontfile',
  'pict',
  'object',
  'objdata',
  'objclass',
  'objname',
  'objalias',
  'shp',
  'shpinst',
  'shprslt',
  'nonshppict',
  'shppict',
  'do',
  'dptxbxtext',
  'fldinst',
  'datafield',
  'header',
  'headerl',
  'headerr',
  'headerf',
  'footer',
  'footerl',
  'footerr',
  'footerf',
  'footnote',
  'ftnsep',
  'ftnsepc',
  'aftnsep',
  'aftnsepc',
  'annotation',
  'atnauthor',
  'atnid',
  'atndate',
  'atnref',
  'bkmkstart',
  'bkmkend',
  'xe',
  'tc',
  'pn',
  'pntxtb',
  'pntxta',
  'docvar',
  'userprops',
  'propname',
  'staticval',
  'linkval',
  'formfield',
  'htmltag',
  'mhtmltag',
  'xmlopen',
  'xmlclose',
  'xmlattrname',
  'xmlattrvalue',
  'private',
  'password',
  'passwordhash',
  'keycode',
  'background',
  'mmathPr',
};
