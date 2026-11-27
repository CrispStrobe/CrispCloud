import 'package:quds_office_engine/quds_office_engine.dart';

import 'word_html_clipboard.dart' show wordClipboardLimit;

/// Reads the character and paragraph formatting of a clipboard RTF fragment.
List<WmlBlock> readWordClipboardRtf(String source) {
  if (!source.startsWith(r'{\rtf') || source.length > wordClipboardLimit) {
    return [];
  }
  return _RtfClipboard(source).read();
}

class _RtfState {
  _RtfState({
    WmlRunProps? run,
    WmlParagraphProps? paragraph,
    this.skip = false,
    this.unicodeFallback = 1,
  }) : run = run ?? WmlRunProps(),
       paragraph = paragraph ?? WmlParagraphProps();

  WmlRunProps run;
  WmlParagraphProps paragraph;
  bool skip;
  int unicodeFallback;

  _RtfState copy() => _RtfState(
    run: run.copy(),
    paragraph: paragraph.copy(),
    skip: skip,
    unicodeFallback: unicodeFallback,
  );
}

class _RtfClipboard {
  _RtfClipboard(this.source) {
    final fonts = _destination('fonttbl');
    final colors = _destination('colortbl');
    for (final font in _fontEntry.allMatches(fonts ?? '')) {
      final name = font[2]!.trim();
      if (name.isNotEmpty && name.length <= 128) {
        _fonts[int.parse(font[1]!)] = name;
      }
    }
    if (colors != null) {
      for (final entry in colors.split(';')) {
        final components = <String, int>{
          for (final channel in _colorComponent.allMatches(entry))
            channel[1]!: int.parse(channel[2]!).clamp(0, 255),
        };
        _colors.add(
          components.isEmpty
              ? null
              : [
                  for (final name in ['red', 'green', 'blue'])
                    (components[name] ?? 0).toRadixString(16).padLeft(2, '0'),
                ].join().toUpperCase(),
        );
      }
    }
    final defaultFont = RegExp(r'\\deff(\d+)').firstMatch(source);
    if (defaultFont != null) {
      _defaultFont = _fonts[int.tryParse(defaultFont[1]!)];
      _resetRun();
    }
  }

  static final _control = RegExp(r'([A-Za-z]+)(-?\d+)? ?');
  static final _fontEntry = RegExp(r'\\f(\d+)[^;{}]*? ([^;{}\\]+);');
  static final _colorComponent = RegExp(r'\\(red|green|blue)(\d+)');
  static const _ignored = {
    'fonttbl',
    'colortbl',
    'stylesheet',
    'info',
    'pict',
    'object',
    'objdata',
    'listtable',
    'listoverridetable',
    'listtext',
    'pntext',
    'themedata',
    'datastore',
    'xmlnstbl',
    'fldinst',
    'header',
    'footer',
    'footnote',
    'shp',
    'nonshppict',
    'annotation',
  };
  static const _windows1252 = [
    0x20ac,
    0x81,
    0x201a,
    0x192,
    0x201e,
    0x2026,
    0x2020,
    0x2021,
    0x2c6,
    0x2030,
    0x160,
    0x2039,
    0x152,
    0x8d,
    0x17d,
    0x8f,
    0x90,
    0x2018,
    0x2019,
    0x201c,
    0x201d,
    0x2022,
    0x2013,
    0x2014,
    0x2dc,
    0x2122,
    0x161,
    0x203a,
    0x153,
    0x9d,
    0x17e,
    0x178,
  ];

  final String source;
  final _fonts = <int, String>{};
  final _colors = <String?>[];
  final _blocks = <WmlBlock>[];
  final _stack = <_RtfState>[];
  final _text = StringBuffer();
  var _state = _RtfState();
  var _paragraph = WmlParagraph();
  String? _defaultFont;
  var _fallback = 0;
  var _index = 0;
  var _groups = 0;
  var _runs = 0;

  String? _destination(String name) {
    final begin = source.indexOf('{\\$name');
    if (begin < 0) return null;
    var depth = 1;
    for (var i = begin + 1; i < source.length; i++) {
      switch (source.codeUnitAt(i)) {
        case 92: // A literal brace is escaped.
          if (i + 1 < source.length &&
              const [92, 123, 125].contains(source.codeUnitAt(i + 1))) {
            i++;
          }
        case 123:
          depth++;
        case 125:
          if (--depth == 0) return source.substring(begin, i);
      }
    }
    return null;
  }

  void _resetRun() {
    final font = _defaultFont;
    _state.run = WmlRunProps(
      asciiFont: font ?? 'Arial',
      csFont: font ?? 'Arial',
    );
  }

  void _flushText() {
    if (_text.isEmpty) return;
    if (++_runs > 20000) {
      throw const FormatException('Clipboard RTF exceeds structural limits');
    }
    _paragraph.inlines.add(
      WmlRun(text: _text.toString(), properties: _state.run.copy()),
    );
    _text.clear();
  }

  void _finishParagraph() {
    _flushText();
    _paragraph.properties = _state.paragraph.copy();
    _blocks.add(_paragraph);
    _paragraph = WmlParagraph();
  }

  void _character(int code, {bool unicode = false}) {
    if (_state.skip) return;
    if (!unicode && _fallback > 0) {
      _fallback--;
      return;
    }
    _text.writeCharCode(
      !unicode && code >= 0x80 && code <= 0x9f
          ? _windows1252[code - 0x80]
          : code,
    );
  }

  List<WmlBlock> read() {
    while (_index < source.length) {
      final code = source.codeUnitAt(_index++);
      switch (code) {
        case 123:
          if (_stack.length >= 128 || ++_groups > 20000) return [];
          _flushText();
          _stack.add(_state);
          _state = _state.copy();
        case 125:
          if (_stack.isEmpty) return [];
          _flushText();
          if (_stack.length == 1 && _paragraph.inlines.isNotEmpty) {
            _finishParagraph();
          }
          _state = _stack.removeLast();
        case 92:
          _readControl();
        case 0:
        case 10:
        case 13:
          break;
        default:
          _character(code);
      }
    }
    return _stack.isEmpty ? _blocks : [];
  }

  void _readControl() {
    if (_index >= source.length) return;
    final match = _control.matchAsPrefix(source, _index);
    if (match == null) {
      final code = source.codeUnitAt(_index++);
      switch (code) {
        case 39:
          if (_index + 2 > source.length) return;
          final hex = int.tryParse(
            source.substring(_index, _index + 2),
            radix: 16,
          );
          _index += 2;
          if (hex != null) _character(hex);
        case 42:
          _state.skip = true;
        case 92:
        case 123:
        case 125:
          _character(code);
        case 126:
          _character(0xa0);
        case 95:
          _character(0x2011);
      }
      return;
    }
    _index = match.end;
    final word = match[1]!;
    final value = int.tryParse(match[2] ?? '');
    if (word == 'bin') {
      _index = (_index + (value ?? 0).clamp(0, source.length)).clamp(
        0,
        source.length,
      );
      return;
    }
    if (_ignored.contains(word)) _state.skip = true;
    if (_state.skip) return;
    switch (word) {
      case 'u':
        if (value != null) _character(value & 0xffff, unicode: true);
        _fallback = _state.unicodeFallback;
        return;
      case 'uc':
        _state.unicodeFallback = (value ?? 1).clamp(0, 16);
        return;
      case 'tab':
        _character(9);
        return;
      case 'emdash':
        _character(0x2014);
        return;
      case 'endash':
        _character(0x2013);
        return;
      case 'bullet':
        _character(0x2022);
        return;
      case 'lquote':
        _character(0x2018);
        return;
      case 'rquote':
        _character(0x2019);
        return;
      case 'ldblquote':
        _character(0x201c);
        return;
      case 'rdblquote':
        _character(0x201d);
        return;
      case 'par':
        _finishParagraph();
        return;
      case 'line':
        _flushText();
        _paragraph.inlines.add(WmlBreak(WmlBreakType.textWrapping));
        return;
    }
    final run = _state.run;
    switch (word) {
      case 'plain':
        _flushText();
        _resetRun();
      case 'b':
        _flushText();
        run.bold = value != 0;
      case 'i':
        _flushText();
        run.italic = value != 0;
      case 'ul':
      case 'ulnone':
        _flushText();
        run.underline = word == 'ulnone' || value == 0
            ? WmlUnderline.none
            : WmlUnderline.single;
      case 'uldb':
        _flushText();
        run.underline = WmlUnderline.double;
      case 'strike':
        _flushText();
        run.strike = value != 0;
      case 'super':
        _flushText();
        run.vertAlign = WmlVertAlign.superscript;
      case 'sub':
        _flushText();
        run.vertAlign = WmlVertAlign.subscript;
      case 'nosupersub':
        _flushText();
        run.vertAlign = WmlVertAlign.baseline;
      case 'fs' when value != null:
        _flushText();
        run.fontSizeHalfPoints = value.clamp(2, 800);
      case 'f' when _fonts[value] != null:
        _flushText();
        run.asciiFont = run.csFont = _fonts[value]!;
      case 'cf':
        _flushText();
        run.color = _color(value) ?? '000000';
      case 'highlight':
      case 'chcbpat':
        _flushText();
        run.highlight = _color(value);
      case 'pard':
        _state.paragraph = WmlParagraphProps();
      case 'rtlpar':
        _state.paragraph.rightToLeft = true;
      case 'ltrpar':
        _state.paragraph.rightToLeft = false;
      case 'ql' || 'qr' || 'qc' || 'qj':
        _state.paragraph.justification = switch (word) {
          'qr' => WmlJustification.right,
          'qc' => WmlJustification.center,
          'qj' => WmlJustification.justify,
          _ => WmlJustification.left,
        };
        _state.paragraph.explicitJustification = true;
    }
  }

  String? _color(int? index) =>
      index == null || index < 0 || index >= _colors.length
      ? null
      : _colors[index];
}
