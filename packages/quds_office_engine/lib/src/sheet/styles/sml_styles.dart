import '../../xml/xml_reader.dart';

/// Horizontal cell alignment (`alignment/@horizontal`).
enum SmlHAlign { general, left, center, right }

/// Parsed `styles.xml` subset: numFmts, fills, fonts, and cellXfs.
class SmlStyleSheet {
  /// SmlStyleSheet API.
  SmlStyleSheet({
    Map<int, String>? numFmts,
    List<int>? cellXfsNumFmt,
    List<SmlHAlign>? cellXfsAlign,
    List<String>? fillRgbs,
    List<String>? fontRgbs,
    List<bool>? fontBolds,
    List<double>? fontSizes,
    List<int>? cellXfsFillId,
    List<int>? cellXfsFontId,
    List<String>? themeColors,
  }) : numFmts = numFmts ?? Map<int, String>.from(_builtIn),
       cellXfsNumFmt = cellXfsNumFmt ?? <int>[0],
       cellXfsAlign = cellXfsAlign ?? <SmlHAlign>[SmlHAlign.general],
       fillRgbs = fillRgbs ?? <String>['', ''],
       fontRgbs = fontRgbs ?? <String>[''],
       fontBolds = fontBolds ?? <bool>[false],
       fontSizes = fontSizes ?? <double>[11],
       cellXfsFillId = cellXfsFillId ?? <int>[0],
       cellXfsFontId = cellXfsFontId ?? <int>[0],
       themeColors = themeColors ?? List<String>.from(_officeTheme);

  /// numFmts API.
  final Map<int, String> numFmts;

  /// cellXfsNumFmt API.
  final List<int> cellXfsNumFmt;

  /// cellXfsAlign API.
  final List<SmlHAlign> cellXfsAlign;

  /// Solid fill RGB (`RRGGBB`) per fills.xml entry; empty means no fill.
  final List<String> fillRgbs;

  /// Font RGB (`RRGGBB`) per fonts.xml entry; empty means default text.
  final List<String> fontRgbs;

  /// Bold flag per fonts.xml entry.
  final List<bool> fontBolds;

  /// Point size per fonts.xml entry.
  final List<double> fontSizes;

  /// cellXfsFillId API.
  final List<int> cellXfsFillId;

  /// cellXfsFontId API.
  final List<int> cellXfsFontId;

  /// Theme scheme colors (dk1 … folHlink).
  final List<String> themeColors;

  /// parse API.
  factory SmlStyleSheet.parse(String xml, {List<String>? themeColors}) {
    final SmlStyleSheet sheet = SmlStyleSheet(
      cellXfsNumFmt: <int>[],
      cellXfsAlign: <SmlHAlign>[],
      fillRgbs: <String>[],
      fontRgbs: <String>[],
      fontBolds: <bool>[],
      fontSizes: <double>[],
      cellXfsFillId: <int>[],
      cellXfsFontId: <int>[],
      themeColors: themeColors,
    );
    final XmlPullReader reader = XmlPullReader(xml);
    var inCellXfs = false;
    var inCellStyleXfs = false;
    var inFills = false;
    var inFonts = false;
    var currentFill = '';
    var currentFont = '';
    var currentBold = false;
    var currentSize = 11.0;
    while (reader.next()) {
      if (reader.eventType == XmlEventType.endElement) {
        if (reader.localName == 'cellXfs') {
          inCellXfs = false;
        } else if (reader.localName == 'cellStyleXfs') {
          inCellStyleXfs = false;
        } else if (reader.localName == 'fills') {
          inFills = false;
        } else if (reader.localName == 'fonts') {
          inFonts = false;
        } else if (reader.localName == 'fill' && inFills) {
          sheet.fillRgbs.add(currentFill);
          currentFill = '';
        } else if (reader.localName == 'font' && inFonts) {
          sheet.fontRgbs.add(currentFont);
          sheet.fontBolds.add(currentBold);
          sheet.fontSizes.add(currentSize);
          currentFont = '';
          currentBold = false;
          currentSize = 11;
        }
        continue;
      }
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'cellStyleXfs') {
        inCellStyleXfs = true;
      } else if (reader.localName == 'cellXfs') {
        inCellXfs = !inCellStyleXfs;
      } else if (reader.localName == 'fills') {
        inFills = true;
      } else if (reader.localName == 'fonts') {
        inFonts = true;
      } else if (reader.localName == 'numFmt') {
        final int id = int.parse(reader.getAttribute('numFmtId') ?? '0');
        sheet.numFmts[id] = reader.getAttribute('formatCode') ?? 'General';
      } else if (inFills && reader.localName == 'fill') {
        currentFill = '';
      } else if (inFills &&
          (reader.localName == 'fgColor' || reader.localName == 'bgColor')) {
        final String resolved = resolveColor(
          rgb: reader.getAttribute('rgb'),
          theme: reader.getAttribute('theme'),
          indexed: reader.getAttribute('indexed'),
          tint: reader.getAttribute('tint'),
          themeColors: sheet.themeColors,
        );
        if (resolved.isNotEmpty &&
            (reader.localName == 'fgColor' || currentFill.isEmpty)) {
          currentFill = resolved;
        }
      } else if (inFonts && reader.localName == 'font') {
        currentFont = '';
        currentBold = false;
        currentSize = 11;
      } else if (inFonts && reader.localName == 'b') {
        final String? val = reader.getAttribute('val');
        currentBold = val == null || val == '1' || val.toLowerCase() == 'true';
      } else if (inFonts && reader.localName == 'sz') {
        currentSize = double.tryParse(reader.getAttribute('val') ?? '') ?? 11;
      } else if (inFonts && reader.localName == 'color') {
        currentFont = resolveColor(
          rgb: reader.getAttribute('rgb'),
          theme: reader.getAttribute('theme'),
          indexed: reader.getAttribute('indexed'),
          tint: reader.getAttribute('tint'),
          themeColors: sheet.themeColors,
        );
      } else if (inCellXfs && reader.localName == 'xf') {
        sheet.cellXfsNumFmt.add(
          int.parse(reader.getAttribute('numFmtId') ?? '0'),
        );
        sheet.cellXfsAlign.add(SmlHAlign.general);
        sheet.cellXfsFillId.add(
          int.tryParse(reader.getAttribute('fillId') ?? '0') ?? 0,
        );
        sheet.cellXfsFontId.add(
          int.tryParse(reader.getAttribute('fontId') ?? '0') ?? 0,
        );
      } else if (inCellXfs &&
          reader.localName == 'alignment' &&
          sheet.cellXfsAlign.isNotEmpty) {
        sheet.cellXfsAlign[sheet.cellXfsAlign.length - 1] = parseHAlign(
          reader.getAttribute('horizontal'),
        );
      }
    }
    return sheet;
  }

  /// parseTheme API.
  static List<String> parseTheme(String xml) {
    final List<String> colors = List<String>.from(_officeTheme);
    final XmlPullReader reader = XmlPullReader(xml);
    var inScheme = false;
    var index = 0;
    while (reader.next()) {
      if (reader.eventType == XmlEventType.endElement &&
          reader.localName == 'clrScheme') {
        break;
      }
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'clrScheme') {
        inScheme = true;
        continue;
      }
      if (!inScheme) {
        continue;
      }
      if (reader.localName == 'srgbClr') {
        final String val = normalizeRgb(reader.getAttribute('val') ?? '');
        if (val.isNotEmpty && index < colors.length) {
          colors[index] = val;
        }
        index++;
      } else if (reader.localName == 'sysClr') {
        final String val = normalizeRgb(reader.getAttribute('lastClr') ?? '');
        if (val.isNotEmpty && index < colors.length) {
          colors[index] = val;
        }
        index++;
      }
    }
    return colors;
  }

  /// format API.
  String format(Object? value, int styleIndex) {
    final int numFmtId = styleIndex >= 0 && styleIndex < cellXfsNumFmt.length
        ? cellXfsNumFmt[styleIndex]
        : 0;
    final String code = numFmts[numFmtId] ?? 'General';
    return applyNumberFormat(value, code);
  }

  /// alignAt API.
  SmlHAlign alignAt(int styleIndex) {
    if (styleIndex >= 0 && styleIndex < cellXfsAlign.length) {
      return cellXfsAlign[styleIndex];
    }
    return SmlHAlign.general;
  }

  /// fillAt API.
  String fillAt(int styleIndex) {
    if (styleIndex < 0 || styleIndex >= cellXfsFillId.length) {
      return '';
    }
    final int id = cellXfsFillId[styleIndex];
    if (id < 0 || id >= fillRgbs.length) {
      return '';
    }
    return fillRgbs[id];
  }

  /// fontAt API.
  String fontAt(int styleIndex) {
    if (styleIndex < 0 || styleIndex >= cellXfsFontId.length) {
      return '';
    }
    final int id = cellXfsFontId[styleIndex];
    if (id < 0 || id >= fontRgbs.length) {
      return '';
    }
    return fontRgbs[id];
  }

  /// boldAt API.
  bool boldAt(int styleIndex) {
    if (styleIndex < 0 || styleIndex >= cellXfsFontId.length) {
      return false;
    }
    final int id = cellXfsFontId[styleIndex];
    if (id < 0 || id >= fontBolds.length) {
      return false;
    }
    return fontBolds[id];
  }

  /// sizeAt API.
  double sizeAt(int styleIndex) {
    if (styleIndex < 0 || styleIndex >= cellXfsFontId.length) {
      return 11;
    }
    final int id = cellXfsFontId[styleIndex];
    if (id < 0 || id >= fontSizes.length) {
      return 11;
    }
    return fontSizes[id];
  }

  /// xfForAlign API.
  int xfForAlign(SmlHAlign align) => xfFor(align: align);

  /// xfFor API.
  int xfFor({
    SmlHAlign align = SmlHAlign.general,
    String fillRgb = '',
    String fontRgb = '',
    bool bold = false,
    double size = 11,
  }) {
    if (cellXfsAlign.isEmpty) {
      cellXfsNumFmt.add(0);
      cellXfsAlign.add(SmlHAlign.general);
      cellXfsFillId.add(0);
      cellXfsFontId.add(0);
    }
    if (fillRgbs.isEmpty) {
      fillRgbs.addAll(<String>['', '']);
    }
    if (fontRgbs.isEmpty) {
      fontRgbs.add('');
      fontBolds.add(false);
      fontSizes.add(11);
    }
    final String fill = normalizeRgb(fillRgb);
    final String font = normalizeRgb(fontRgb);
    final int fillId = _idFor(fillRgbs, fill, reserveNone: true);
    final int fontId = _fontId(rgb: font, bold: bold, size: size);
    for (int i = 0; i < cellXfsAlign.length; i++) {
      final int xfFill = i < cellXfsFillId.length ? cellXfsFillId[i] : 0;
      final int xfFont = i < cellXfsFontId.length ? cellXfsFontId[i] : 0;
      if (cellXfsAlign[i] == align && xfFill == fillId && xfFont == fontId) {
        return i;
      }
    }
    cellXfsNumFmt.add(0);
    cellXfsAlign.add(align);
    cellXfsFillId.add(fillId);
    cellXfsFontId.add(fontId);
    return cellXfsAlign.length - 1;
  }

  int _fontId({
    required String rgb,
    required bool bold,
    required double size,
  }) {
    final int n = fontRgbs.length;
    while (fontBolds.length < n) {
      fontBolds.add(false);
    }
    while (fontSizes.length < n) {
      fontSizes.add(11);
    }
    for (int i = 0; i < n; i++) {
      if (fontRgbs[i] == rgb &&
          fontBolds[i] == bold &&
          fontSizes[i] == size) {
        return i;
      }
    }
    fontRgbs.add(rgb);
    fontBolds.add(bold);
    fontSizes.add(size);
    return fontRgbs.length - 1;
  }

  int _idFor(List<String> values, String rgb, {required bool reserveNone}) {
    if (rgb.isEmpty) {
      return 0;
    }
    final int start = reserveNone && values.length > 1 ? 2 : 0;
    for (int i = start; i < values.length; i++) {
      if (values[i] == rgb) {
        return i;
      }
    }
    values.add(rgb);
    return values.length - 1;
  }

  /// parseHAlign API.
  static SmlHAlign parseHAlign(String? raw) {
    return switch (raw) {
      'center' => SmlHAlign.center,
      'left' => SmlHAlign.left,
      'right' => SmlHAlign.right,
      _ => SmlHAlign.general,
    };
  }

  /// hAlignName API.
  static String hAlignName(SmlHAlign align) {
    return switch (align) {
      SmlHAlign.center => 'center',
      SmlHAlign.left => 'left',
      SmlHAlign.right => 'right',
      SmlHAlign.general => 'general',
    };
  }

  /// Minimal `styles.xml` that preserves number formats, fill, and alignment.
  String toXml() {
    if (fillRgbs.isEmpty) {
      fillRgbs.addAll(<String>['', '']);
    }
    if (fontRgbs.isEmpty) {
      fontRgbs.add('');
      fontBolds.add(false);
      fontSizes.add(11);
    }
    while (fontBolds.length < fontRgbs.length) {
      fontBolds.add(false);
    }
    while (fontSizes.length < fontRgbs.length) {
      fontSizes.add(11);
    }
    final StringBuffer buf = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    );
    buf.write('<fonts count="${fontRgbs.length}">');
    for (int i = 0; i < fontRgbs.length; i++) {
      final String font = fontRgbs[i];
      final bool bold = fontBolds[i];
      final String size = fontSizes[i].toString();
      buf.write('<font>');
      if (bold) {
        buf.write('<b/>');
      }
      buf.write('<sz val="$size"/><name val="Calibri"/>');
      if (font.isNotEmpty) {
        buf.write('<color rgb="FF$font"/>');
      }
      buf.write('</font>');
    }
    buf.write('</fonts><fills count="${fillRgbs.length}">');
    for (int i = 0; i < fillRgbs.length; i++) {
      final String rgb = fillRgbs[i];
      if (i == 1 && rgb.isEmpty) {
        buf.write('<fill><patternFill patternType="gray125"/></fill>');
      } else if (rgb.isEmpty) {
        buf.write('<fill><patternFill patternType="none"/></fill>');
      } else {
        buf.write(
          '<fill><patternFill patternType="solid">'
          '<fgColor rgb="FF$rgb"/></patternFill></fill>',
        );
      }
    }
    buf.write(
      '</fills><borders count="1">'
      '<border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>'
      '</cellStyleXfs>'
      '<cellXfs count="${cellXfsAlign.length}">',
    );
    for (int i = 0; i < cellXfsAlign.length; i++) {
      final int numFmtId = i < cellXfsNumFmt.length ? cellXfsNumFmt[i] : 0;
      final int fillId = i < cellXfsFillId.length ? cellXfsFillId[i] : 0;
      final int fontId = i < cellXfsFontId.length ? cellXfsFontId[i] : 0;
      final SmlHAlign align = cellXfsAlign[i];
      buf.write(
        '<xf numFmtId="$numFmtId" fontId="$fontId" fillId="$fillId" '
        'borderId="0" xfId="0"',
      );
      if (fillId > 0) {
        buf.write(' applyFill="1"');
      }
      if (fontId > 0) {
        buf.write(' applyFont="1"');
      }
      if (align != SmlHAlign.general) {
        buf.write(
          ' applyAlignment="1">'
          '<alignment horizontal="${hAlignName(align)}" vertical="center"/>'
          '</xf>',
        );
      } else {
        buf.write('/>');
      }
    }
    buf.write('</cellXfs></styleSheet>');
    return buf.toString();
  }

  /// resolveColor API.
  static String resolveColor({
    String? rgb,
    String? theme,
    String? indexed,
    String? tint,
    List<String> themeColors = const <String>[],
  }) {
    var hex = normalizeRgb(rgb ?? '');
    if (hex.isEmpty && theme != null) {
      final int raw = int.tryParse(theme) ?? -1;
      final int i = themeSchemeIndex(raw);
      if (i >= 0 && i < themeColors.length) {
        hex = themeColors[i];
      } else if (i >= 0 && i < _officeTheme.length) {
        hex = _officeTheme[i];
      }
    }
    if (hex.isEmpty && indexed != null) {
      final int i = int.tryParse(indexed) ?? -1;
      if (i >= 0 && i < _indexed.length) {
        hex = _indexed[i];
      }
    }
    if (hex.isEmpty) {
      return '';
    }
    final double? t = double.tryParse(tint ?? '');
    if (t == null || t == 0) {
      return hex;
    }
    return applyTint(hex, t);
  }

  /// SpreadsheetML `theme=` indices swap lt/dk pairs in `clrScheme`.
  static int themeSchemeIndex(int theme) {
    return switch (theme) {
      0 => 1,
      1 => 0,
      2 => 3,
      3 => 2,
      _ => theme,
    };
  }

  /// normalizeRgb API.
  static String normalizeRgb(String raw) {
    var hex = raw.trim().toUpperCase();
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }
    if (hex.length == 8) {
      hex = hex.substring(2);
    }
    if (hex.length != 6 || int.tryParse(hex, radix: 16) == null) {
      return '';
    }
    return hex;
  }

  /// applyTint API.
  static String applyTint(String rgb, double tint) {
    int channel(int value) {
      final double n = value / 255;
      final double out = tint < 0 ? n * (1 + tint) : n * (1 - tint) + tint;
      return (out.clamp(0, 1) * 255).round();
    }

    final int v = int.parse(rgb, radix: 16);
    final String r = channel(
      (v >> 16) & 0xFF,
    ).toRadixString(16).padLeft(2, '0');
    final String g = channel((v >> 8) & 0xFF).toRadixString(16).padLeft(2, '0');
    final String b = channel(v & 0xFF).toRadixString(16).padLeft(2, '0');
    return '$r$g$b'.toUpperCase();
  }
}

/// ECMA-376 §18.8.30 number formats (common subset).
String applyNumberFormat(Object? value, String code) {
  if (value == null) {
    return '';
  }
  if (code == 'General' || code == '@') {
    if (value is num && value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toString();
  }

  /// n API.
  final double? n = value is num
      ? value.toDouble()
      : double.tryParse(value.toString());
  if (n == null) {
    return value.toString();
  }

  final List<String> sections = code.split(';');
  // Sections: positive; negative; zero. A negative section prints its own
  // sign (e.g. parentheses), so the value is formatted without one.
  var section = sections.first;
  var shown = n;
  if (n < 0 && sections.length > 1 && sections[1].isNotEmpty) {
    section = sections[1];
    shown = -n;
  } else if (n == 0 && sections.length > 2 && sections[2].isNotEmpty) {
    section = sections[2];
  }
  final bool negativeRed = section.contains('[Red]');
  final String clean = section.replaceAll('[Red]', '');

  String out;
  if (_isDateFormat(clean) && !RegExp(r'[0#?]').hasMatch(_literalFree(clean))) {
    out = formatExcelDate(excelSerialToDate(shown), clean);
  } else {
    out = _formatNumberSection(shown, clean);
  }
  if (negativeRed && n < 0) {
    return 'RED:$out';
  }
  return out;
}

/// [code] without quoted literals, escapes, and `[…]` blocks.
String _literalFree(String code) => code
    .replaceAll(RegExp(r'"[^"]*"'), '')
    .replaceAll(RegExp(r'\\.'), '')
    .replaceAll(RegExp(r'\[[^\]]*\]'), '');

/// Formats one numeric section: `0` / `#` / `?` digits, `,` grouping and
/// thousands scaling, `.` decimals, `%`, and literal prefix / suffix text.
String _formatNumberSection(double n, String code) {
  final StringBuffer literal = StringBuffer();
  final StringBuffer pattern = StringBuffer();
  var prefix = '';
  var inPattern = false;
  var patternDone = false;
  var percent = false;
  var i = 0;
  void emit(String text) {
    if (patternDone || inPattern) {
      literal.write(text);
      patternDone = true;
      inPattern = false;
    } else {
      prefix += text;
    }
  }

  while (i < code.length) {
    final String ch = code[i];
    if (ch == '"') {
      final int end = code.indexOf('"', i + 1);
      emit(code.substring(i + 1, end < 0 ? code.length : end));
      i = end < 0 ? code.length : end + 1;
    } else if (ch == r'\' && i + 1 < code.length) {
      emit(code[i + 1]);
      i += 2;
    } else if (ch == '[') {
      final int end = code.indexOf(']', i + 1);
      final String inner = code.substring(i + 1, end < 0 ? code.length : end);
      if (inner.startsWith(r'$')) {
        final int dash = inner.indexOf('-');
        emit(inner.substring(1, dash < 0 ? inner.length : dash));
      }
      i = end < 0 ? code.length : end + 1;
    } else if (ch == '_' && i + 1 < code.length) {
      emit(' ');
      i += 2;
    } else if (ch == '*' && i + 1 < code.length) {
      i += 2;
    } else if (!patternDone && '0#?,.'.contains(ch)) {
      inPattern = true;
      pattern.write(ch);
      i++;
    } else {
      if (ch == '%') {
        percent = true;
      }
      emit(ch);
      i++;
    }
  }
  final String suffix = literal.toString();
  final String digits = pattern.toString();
  if (digits.isEmpty) {
    final String text = '$prefix$suffix';
    return text.trim().isEmpty ? _plainNumber(n) : text;
  }
  final int dot = digits.indexOf('.');
  var integerPart = dot < 0 ? digits : digits.substring(0, dot);
  final String fraction = dot < 0 ? '' : digits.substring(dot + 1);
  var scale = 1.0;
  while (integerPart.endsWith(',')) {
    scale *= 1000;
    integerPart = integerPart.substring(0, integerPart.length - 1);
  }
  final bool group = integerPart.contains(',');
  final int minInteger = '0'.allMatches(integerPart).length;
  final int fixed = '0'.allMatches(fraction).length;
  final int optional = fraction.length - fixed;
  var value = (percent ? n * 100 : n) / scale;
  final bool negative = value < 0;
  value = value.abs();
  var text = value.toStringAsFixed(fixed + optional);
  if (optional > 0 && text.contains('.')) {
    var end = text.length;
    final int minEnd = text.indexOf('.') + 1 + fixed;
    while (end > minEnd && text[end - 1] == '0') {
      end--;
    }
    text = text.substring(0, end);
    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }
  }
  final int point = text.indexOf('.');
  var whole = point < 0 ? text : text.substring(0, point);
  final String decimals = point < 0 ? '' : text.substring(point);
  if (whole == '0' && minInteger == 0) {
    whole = '';
  }
  whole = whole.padLeft(minInteger, '0');
  if (group && whole.length > 3) {
    final StringBuffer grouped = StringBuffer();
    final int head = whole.length % 3;
    grouped.write(whole.substring(0, head));
    for (var g = head; g < whole.length; g += 3) {
      if (grouped.isNotEmpty) {
        grouped.write(',');
      }
      grouped.write(whole.substring(g, g + 3));
    }
    whole = grouped.toString();
  }
  final bool isZero = RegExp(r'^[0.,]*$').hasMatch('$whole$decimals');
  final String sign = negative && !isZero ? '-' : '';
  return '$sign$prefix$whole$decimals$suffix';
}

String _plainNumber(double n) =>
    n == n.roundToDouble() ? '${n.round()}' : n.toString();

bool _isDateFormat(String code) {
  final String c = code.toLowerCase();
  return c.contains('yy') ||
      c.contains('mmm') ||
      c.contains('dd') ||
      c.contains('d-m') ||
      c.contains('mm-');
}

/// Excel 1900-date-system serial → UTC date (leap-year bug included).
DateTime excelSerialToDate(double serial) {
  final int days = serial.floor();
  final int ms = ((serial - days) * 86400000).round();
  return DateTime.utc(1899, 12, 30).add(Duration(days: days, milliseconds: ms));
}

/// formatExcelDate API.
String formatExcelDate(DateTime dt, String code) {
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String pad(int value, int width) => value.toString().padLeft(width, '0');
  final String month = months[dt.month - 1];
  var out = code;
  out = out.replaceAll('yyyy', '${dt.year}');
  out = out.replaceAll('yy', pad(dt.year % 100, 2));
  out = out.replaceAll('mmm', month);
  out = out.replaceAll('mm', pad(dt.month, 2));
  out = out.replaceAll('dd', pad(dt.day, 2));
  out = out.replaceAll('d', '${dt.day}');
  return out;
}

const Map<int, String> _builtIn = <int, String>{
  0: 'General',
  1: '0',
  2: '0.00',
  3: '#,##0',
  4: '#,##0.00',
  9: '0%',
  10: '0.00%',
  14: 'mm-dd-yy',
  15: 'd-mmm-yy',
  16: 'd-mmm',
  17: 'mmm-yy',
  164: '"\$"#,##0.00',
};

const List<String> _officeTheme = <String>[
  '000000',
  'FFFFFF',
  '1F497D',
  'EEECE1',
  '4F81BD',
  'C0504D',
  '9BBB59',
  '8064A2',
  '4BACC6',
  'F79646',
  '0000FF',
  '800080',
];

const List<String> _indexed = <String>[
  '000000',
  'FFFFFF',
  'FF0000',
  '00FF00',
  '0000FF',
  'FFFF00',
  'FF00FF',
  '00FFFF',
  '000000',
  'FFFFFF',
  'FF0000',
  '00FF00',
  '0000FF',
  'FFFF00',
  'FF00FF',
  '00FFFF',
  '800000',
  '008000',
  '000080',
  '808000',
  '800080',
  '008080',
  'C0C0C0',
  '808080',
  '9999FF',
  '993366',
  'FFFFCC',
  'CCFFFF',
  '660066',
  'FF8080',
  '0066CC',
  'CCCCFF',
  '000080',
  'FF00FF',
  'FFFF00',
  '00FFFF',
  '800080',
  '800000',
  '008080',
  '0000FF',
  '00CCFF',
  'CCFFFF',
  'CCFFCC',
  'FFFF99',
  '99CCFF',
  'FF99CC',
  'CC99FF',
  'FFCC99',
  '3366FF',
  '33CCCC',
  '99CC00',
  'FFCC00',
  'FF9900',
  'FF6600',
  '666699',
  '969696',
  '003366',
  '339966',
  '003300',
  '333300',
  '993300',
  '993366',
  '333399',
  '333333',
];
