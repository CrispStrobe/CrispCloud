import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'file/text/pdf_std14.dart';

/// Vector emitter: cm, BT/ET, Tf, Td, TJ, m/l/c/re/f/S.
class PdfCanvas {
  /// PdfCanvas API.
  PdfCanvas(this.pageWidth, this.pageHeight) {
    // Map top-left document space to PDF bottom-left via 1 0 0 -1 0 H cm.
    _buf.writeln('1 0 0 -1 0 ${_n(pageHeight)} cm');
  }

  /// pageWidth API.
  final double pageWidth;

  /// pageHeight API.
  final double pageHeight;

  /// StringBuffer API.
  final StringBuffer _buf = StringBuffer();
  var _inText = false;
  String _color = '';
  double _fontSize = 0;
  String _fontName = '';

  /// beginText API.
  void beginText() {
    if (_inText) {
      return;
    }
    _buf.writeln('BT');
    _inText = true;
  }

  /// endText API.
  void endText() {
    if (!_inText) {
      return;
    }
    _buf.writeln('ET');
    _inText = false;
  }

  /// setFillColor API.
  void setFillColor(String hex) {
    if (hex == _color) {
      return;
    }
    _color = hex;
    final int rgb = _parseRgb(hex);
    final double r = ((rgb >> 16) & 0xFF) / 255.0;
    final double g = ((rgb >> 8) & 0xFF) / 255.0;
    final double b = (rgb & 0xFF) / 255.0;
    _buf.writeln('${_n(r)} ${_n(g)} ${_n(b)} rg');
  }

  /// Strips `#` and alpha; keeps the last 6 hex digits as RRGGBB.
  static int _parseRgb(String hex) {
    final String clean = hex.replaceAll('#', '').trim();
    if (clean.length >= 8) {
      return int.tryParse(clean.substring(clean.length - 6), radix: 16) ?? 0;
    }
    if (clean.length == 6) {
      return int.tryParse(clean, radix: 16) ?? 0;
    }
    if (clean.length == 3) {
      final int n = int.tryParse(clean, radix: 16) ?? 0;
      final int r = (n >> 8) & 0xF;
      final int g = (n >> 4) & 0xF;
      final int b = n & 0xF;
      return (r << 20) | (r << 16) | (g << 12) | (g << 8) | (b << 4) | b;
    }
    return int.tryParse(clean, radix: 16) ?? 0;
  }

  /// showGlyph API.
  void showGlyph({
    required double x,
    required double y,
    required double fontSize,
    required int glyphId,
    required String color,
    bool italic = false,
    bool bold = false,
    String fontName = 'F1',
  }) {
    beginText();
    setFillColor(color);
    _setFont(fontName, fontSize);
    final String hex = glyphId.toRadixString(16).padLeft(4, '0');
    final double shear = italic ? 0.25 : 0;
    // Page CTM is Y-flipped (top-left). Negate d so glyphs grow up the page.
    _buf.writeln('1 0 ${_n(shear)} -1 ${_n(x)} ${_n(y)} Tm');
    _buf.writeln('[<$hex>] TJ');
    if (bold) {
      // A second pass 5% of the em over thickens stems by about the gap
      // between a regular and a bold cut.
      final double dx = math.max(0.35, fontSize * 0.05);
      _buf.writeln('1 0 ${_n(shear)} -1 ${_n(x + dx)} ${_n(y)} Tm');
      _buf.writeln('[<$hex>] TJ');
    }
  }

  /// moveTo API.
  void moveTo(double x, double y) => _buf.writeln('${_n(x)} ${_n(y)} m');

  /// lineTo API.
  void lineTo(double x, double y) => _buf.writeln('${_n(x)} ${_n(y)} l');

  /// curveTo API.
  void curveTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,

    /// writeln API.
  ) => _buf.writeln(
    '${_n(x1)} ${_n(y1)} ${_n(x2)} ${_n(y2)} ${_n(x3)} ${_n(y3)} c',
  );

  /// rect API.
  void rect(double x, double y, double w, double h) =>
      _buf.writeln('${_n(x)} ${_n(y)} ${_n(w)} ${_n(h)} re');

  /// fill API.
  void fill() => _buf.writeln('f');

  /// stroke API.
  void stroke() => _buf.writeln('S');

  /// setStrokeColor API.
  void setStrokeColor(String hex) {
    final int rgb = _parseRgb(hex);
    final double r = ((rgb >> 16) & 0xFF) / 255.0;
    final double g = ((rgb >> 8) & 0xFF) / 255.0;
    final double b = (rgb & 0xFF) / 255.0;
    _buf.writeln('${_n(r)} ${_n(g)} ${_n(b)} RG');
  }

  /// setLineWidth API.
  void setLineWidth(double w) => _buf.writeln('${_n(w)} w');

  /// Line join style: 0 miter, 1 round, 2 bevel.
  void setLineJoin(int style) => _buf.writeln('$style j');

  /// setDash API.
  void setDash(List<double> pattern, [double phase = 0]) {
    _buf.writeln('[${pattern.map(_n).join(' ')}] ${_n(phase)} d');
  }

  /// resetDash API.
  void resetDash() => _buf.writeln('[] 0 d');

  /// save API.
  void save() {
    endText();
    _buf.writeln('q');
  }

  /// restore API.
  void restore() {
    endText();
    _buf.writeln('Q');
    _color = '';
    _fontSize = 0;
    _fontName = '';
  }

  /// closePath API.
  void closePath() => _buf.writeln('h');

  /// clip API.
  void clip() {
    endText();
    _buf.writeln('W n');
  }

  /// clipRect API.
  void clipRect(double x, double y, double w, double h) {
    endText();
    rect(x, y, w, h);
    clip();
  }

  /// translateScale API.
  void translateScale(double x, double y, double scale) {
    endText();
    _buf.writeln('${_n(scale)} 0 0 ${_n(scale)} ${_n(x)} ${_n(y)} cm');
  }

  /// Shift subsequent drawing by ([dx], [dy]) in the current user space.
  void translate(double dx, double dy) {
    endText();
    _buf.writeln('1 0 0 1 ${_n(dx)} ${_n(dy)} cm');
  }

  /// Scale around ([cx], [cy]). [sy] is independent so a bar can stretch.
  void scaleAround(double cx, double cy, double sx, double sy) {
    endText();
    _buf.writeln('1 0 0 1 ${_n(cx)} ${_n(cy)} cm');
    _buf.writeln('${_n(sx)} 0 0 ${_n(sy)} 0 0 cm');
    _buf.writeln('1 0 0 1 ${_n(-cx)} ${_n(-cy)} cm');
  }

  /// rotateAround API.
  void rotateAround(double cx, double cy, double degrees) {
    endText();
    final double rad = degrees * math.pi / 180;
    final double c = math.cos(rad);
    final double s = math.sin(rad);
    _buf.writeln('1 0 0 1 ${_n(cx)} ${_n(cy)} cm');
    _buf.writeln('${_n(c)} ${_n(s)} ${_n(-s)} ${_n(c)} 0 0 cm');
    _buf.writeln('1 0 0 1 ${_n(-cx)} ${_n(-cy)} cm');
  }

  /// roundedRect API.
  void roundedRect(double x, double y, double w, double h, double radius) {
    final double r = radius.clamp(0, w < h ? w / 2 : h / 2);
    if (r <= 0.2) {
      rect(x, y, w, h);
      return;
    }
    final double k = 0.5522847498 * r;
    moveTo(x + r, y);
    lineTo(x + w - r, y);
    curveTo(x + w - r + k, y, x + w, y + r - k, x + w, y + r);
    lineTo(x + w, y + h - r);
    curveTo(x + w, y + h - r + k, x + w - r + k, y + h, x + w - r, y + h);
    lineTo(x + r, y + h);
    curveTo(x + r - k, y + h, x, y + h - r + k, x, y + h - r);
    lineTo(x, y + r);
    curveTo(x, y + r - k, x + r - k, y, x + r, y);
    closePath();
  }

  /// Bar / column with rounded top corners only (square baseline).
  void roundedTopRect(double x, double y, double w, double h, double radius) {
    final double r = radius.clamp(0, w < h ? w / 2 : h / 2);
    if (r <= 0.2 || h <= r * 2) {
      rect(x, y, w, h);
      return;
    }
    final double k = 0.5522847498 * r;
    moveTo(x, y + h);
    lineTo(x, y + r);
    curveTo(x, y + r - k, x + r - k, y, x + r, y);
    lineTo(x + w - r, y);
    curveTo(x + w - r + k, y, x + w, y + r - k, x + w, y + r);
    lineTo(x + w, y + h);
    closePath();
  }

  /// ellipse API.
  void ellipse(double x, double y, double w, double h) {
    final double cx = x + w / 2;
    final double cy = y + h / 2;
    final double rx = w / 2;
    final double ry = h / 2;
    final double kx = 0.5522847498 * rx;
    final double ky = 0.5522847498 * ry;
    moveTo(cx + rx, cy);
    curveTo(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry);
    curveTo(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy);
    curveTo(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry);
    curveTo(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy);
    closePath();
  }

  /// fillAndStroke API.
  void fillAndStroke() => _buf.writeln('B');

  /// fillRect API.
  void fillRect(double x, double y, double w, double h, String hex) {
    endText();
    setFillColor(hex);
    rect(x, y, w, h);
    fill();
  }

  /// strokeRect API.
  void strokeRect(double x, double y, double w, double h, String hex) {
    endText();
    setStrokeColor(hex);
    rect(x, y, w, h);
    stroke();
  }

  /// Draws XObject [name] at top-left ([x], [y]) in the flipped page space.
  void drawImage(String name, double x, double y, double w, double h) {
    endText();
    _buf.writeln('q');
    _buf.writeln('${_n(w)} 0 0 ${_n(-h)} ${_n(x)} ${_n(y + h)} cm');
    _buf.writeln('/$name Do');
    _buf.writeln('Q');
  }

  /// showLatin API.
  void showLatin({
    required double x,
    required double y,
    required double fontSize,
    required String text,
    required String color,
  }) {
    beginText();
    setFillColor(color);
    _setFont('F2', fontSize);
    _buf.writeln('1 0 0 -1 ${_n(x)} ${_n(y)} Tm');
    _buf.writeln('(${_pdfEscape(text)}) Tj');
  }

  /// One text showing under the current CTM, not one operator per letter.
  ///
  /// [logical] is stored as ActualText (UTF-16BE) so a viewer can rotate the
  /// whole word. [glyphIds] is the visual-order subset TJ for other readers.
  void showMarkedLine({
    required double x,
    required double y,
    required double fontSize,
    required String logical,
    required String color,
    required String fontName,
    List<int> glyphIds = const <int>[],
  }) {
    endText();
    _buf.writeln('/Span << /ActualText ${_utf16Hex(logical)} >> BDC');
    beginText();
    setFillColor(color);
    _setFont(fontName, fontSize);
    _buf.writeln('1 0 0 -1 ${_n(x)} ${_n(y)} Tm');
    if (glyphIds.isEmpty) {
      _buf.writeln('(${_pdfEscape(logical)}) Tj');
    } else {
      final String hex = glyphIds
          .map((int id) => id.toRadixString(16).padLeft(4, '0'))
          .join();
      _buf.writeln('[<$hex>] TJ');
    }
    endText();
    _buf.writeln('EMC');
  }

  static String _utf16Hex(String text) {
    final StringBuffer hex = StringBuffer('FEFF');
    for (final int unit in text.codeUnits) {
      hex.write(unit.toRadixString(16).padLeft(4, '0'));
    }
    return '<$hex>';
  }

  /// PDF literal-string body for Helvetica WinAnsi.
  ///
  /// The content stream is UTF-8-encoded as ASCII. Bytes above 0x7E must be
  /// octal escapes — stuffing the Dart character (or its UTF-8) into `(…)` is
  /// how `·` becomes `Â·` and Arabic becomes `Ø…`.
  static String _pdfEscape(String value) {
    final StringBuffer out = StringBuffer();
    for (final int cp in value.runes) {
      final int? byte = PdfStd14.winAnsiByte(cp);
      if (byte == null) {
        continue;
      }
      if (byte == 0x5C) {
        out.write(r'\\');
      } else if (byte == 0x28) {
        out.write(r'\(');
      } else if (byte == 0x29) {
        out.write(r'\)');
      } else if (byte < 0x20 || byte > 0x7E) {
        out.write('\\${byte.toRadixString(8).padLeft(3, '0')}');
      } else {
        out.writeCharCode(byte);
      }
    }
    return out.toString();
  }

  /// toStream API.
  Uint8List toStream() => Uint8List.fromList(utf8.encode(_buf.toString()));

  void _setFont(String name, double size) {
    if (_fontName == name && _fontSize == size) {
      return;
    }
    _buf.writeln('/$name ${_n(size)} Tf');
    _fontName = name;
    _fontSize = size;
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(3);
}
