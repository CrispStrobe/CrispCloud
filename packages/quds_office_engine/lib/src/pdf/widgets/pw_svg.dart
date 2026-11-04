/// SVG path subset → PDF widget (path / rect / circle / line / polyline).
library;

import '../../pdf/pdf_canvas.dart';
import 'pw_core.dart';
import 'pw_flutter.dart';
import 'pw_types.dart';

/// Parsed SVG viewBox.
class SvgViewBox {
  /// SvgViewBox API.
  const SvgViewBox(this.minX, this.minY, this.width, this.height);

  /// minX API.
  final double minX;

  /// minY API.
  final double minY;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// Parses `minX minY width height`.
  static SvgViewBox? tryParse(String raw) {
    final List<String> parts = raw
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((String s) => s.isNotEmpty)
        .toList();
    if (parts.length < 4) {
      return null;
    }
    final double? a = double.tryParse(parts[0]);
    final double? b = double.tryParse(parts[1]);
    final double? c = double.tryParse(parts[2]);
    final double? d = double.tryParse(parts[3]);
    if (a == null || b == null || c == null || d == null || c <= 0 || d <= 0) {
      return null;
    }
    return SvgViewBox(a, b, c, d);
  }
}

/// Draws a constrained SVG subset with [CustomPaint].
class SvgImage extends Widget {
  /// SvgImage API.
  const SvgImage(
    this.svg, {
    this.width = 120,
    this.height = 80,
    this.color = '1A237E',
    this.strokeWidth = 1.2,
  });

  /// Raw SVG markup (subset).
  final String svg;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// Fallback stroke/fill when the element omits color.
  final String color;

  /// strokeWidth API.
  final double strokeWidth;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final _SvgDoc doc = _SvgParser().parse(svg);
    final PwSize box = constraints.constrain(PwSize(width, height));
    return CustomPaint(
      size: box,
      painter: (PdfCanvas canvas, PwSize painted) {
        canvas.endText();
        final SvgViewBox vb = doc.viewBox ??
            SvgViewBox(0, 0, painted.width, painted.height);
        final double sx = painted.width / vb.width;
        final double sy = painted.height / vb.height;
        for (final _SvgShape shape in doc.shapes) {
          shape.paint(
            canvas,
            sx: sx,
            sy: sy,
            ox: -vb.minX * sx,
            oy: -vb.minY * sy,
            fallbackColor: color,
            fallbackStroke: strokeWidth,
          );
        }
      },
    ).layout(context, constraints);
  }
}

class _SvgDoc {
  _SvgDoc({this.viewBox, required this.shapes});

  final SvgViewBox? viewBox;
  final List<_SvgShape> shapes;
}

abstract class _SvgShape {
  void paint(
    PdfCanvas canvas, {
    required double sx,
    required double sy,
    required double ox,
    required double oy,
    required String fallbackColor,
    required double fallbackStroke,
  });
}

class _SvgRect extends _SvgShape {
  _SvgRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.fill,
    this.stroke,
    this.strokeWidth,
  });

  final double x, y, w, h;
  final String? fill;
  final String? stroke;
  final double? strokeWidth;

  @override
  void paint(
    PdfCanvas canvas, {
    required double sx,
    required double sy,
    required double ox,
    required double oy,
    required String fallbackColor,
    required double fallbackStroke,
  }) {
    final double px = ox + x * sx;
    final double py = oy + y * sy;
    final double pw = w * sx;
    final double ph = h * sy;
    final String? f = _colorOrNull(fill);
    final String? s = _colorOrNull(stroke);
    if (f != null) {
      canvas.fillRect(px, py, pw, ph, f);
    }
    if (s != null) {
      canvas.setStrokeColor(s);
      canvas.setLineWidth(strokeWidth ?? fallbackStroke);
      canvas.strokeRect(px, py, pw, ph, s);
    }
    if (f == null && s == null) {
      canvas.setStrokeColor(fallbackColor);
      canvas.setLineWidth(fallbackStroke);
      canvas.strokeRect(px, py, pw, ph, fallbackColor);
    }
  }
}

class _SvgCircle extends _SvgShape {
  _SvgCircle({
    required this.cx,
    required this.cy,
    required this.r,
    this.fill,
    this.stroke,
    this.strokeWidth,
  });

  final double cx, cy, r;
  final String? fill;
  final String? stroke;
  final double? strokeWidth;

  @override
  void paint(
    PdfCanvas canvas, {
    required double sx,
    required double sy,
    required double ox,
    required double oy,
    required String fallbackColor,
    required double fallbackStroke,
  }) {
    final double px = ox + (cx - r) * sx;
    final double py = oy + (cy - r) * sy;
    final double d = r * 2 * ((sx + sy) / 2);
    final String? f = _colorOrNull(fill);
    final String? s = _colorOrNull(stroke);
    if (f != null) {
      canvas.setFillColor(f);
      canvas.ellipse(px, py, d, d);
      canvas.fill();
    }
    if (s != null || (f == null && s == null)) {
      canvas.setStrokeColor(s ?? fallbackColor);
      canvas.setLineWidth(strokeWidth ?? fallbackStroke);
      canvas.ellipse(px, py, d, d);
      canvas.stroke();
    }
  }
}

class _SvgLine extends _SvgShape {
  _SvgLine({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.stroke,
    this.strokeWidth,
  });

  final double x1, y1, x2, y2;
  final String? stroke;
  final double? strokeWidth;

  @override
  void paint(
    PdfCanvas canvas, {
    required double sx,
    required double sy,
    required double ox,
    required double oy,
    required String fallbackColor,
    required double fallbackStroke,
  }) {
    canvas.setStrokeColor(_colorOrNull(stroke) ?? fallbackColor);
    canvas.setLineWidth(strokeWidth ?? fallbackStroke);
    canvas.moveTo(ox + x1 * sx, oy + y1 * sy);
    canvas.lineTo(ox + x2 * sx, oy + y2 * sy);
    canvas.stroke();
  }
}

class _SvgPolyline extends _SvgShape {
  _SvgPolyline({
    required this.points,
    this.stroke,
    this.fill,
    this.strokeWidth,
    this.close = false,
  });

  final List<(double, double)> points;
  final String? stroke;
  final String? fill;
  final double? strokeWidth;
  final bool close;

  @override
  void paint(
    PdfCanvas canvas, {
    required double sx,
    required double sy,
    required double ox,
    required double oy,
    required String fallbackColor,
    required double fallbackStroke,
  }) {
    if (points.isEmpty) {
      return;
    }
    canvas.moveTo(ox + points.first.$1 * sx, oy + points.first.$2 * sy);
    for (int i = 1; i < points.length; i++) {
      canvas.lineTo(ox + points[i].$1 * sx, oy + points[i].$2 * sy);
    }
    if (close) {
      canvas.closePath();
    }
    final String? f = _colorOrNull(fill);
    final String? s = _colorOrNull(stroke);
    if (f != null && s != null) {
      canvas.setFillColor(f);
      canvas.setStrokeColor(s);
      canvas.setLineWidth(strokeWidth ?? fallbackStroke);
      canvas.fillAndStroke();
    } else if (f != null) {
      canvas.setFillColor(f);
      canvas.fill();
    } else {
      canvas.setStrokeColor(s ?? fallbackColor);
      canvas.setLineWidth(strokeWidth ?? fallbackStroke);
      canvas.stroke();
    }
  }
}

class _SvgPath extends _SvgShape {
  _SvgPath({
    required this.ops,
    this.stroke,
    this.fill,
    this.strokeWidth,
  });

  final List<_PathOp> ops;
  final String? stroke;
  final String? fill;
  final double? strokeWidth;

  @override
  void paint(
    PdfCanvas canvas, {
    required double sx,
    required double sy,
    required double ox,
    required double oy,
    required String fallbackColor,
    required double fallbackStroke,
  }) {
    for (final _PathOp op in ops) {
      op.apply(canvas, sx: sx, sy: sy, ox: ox, oy: oy);
    }
    final String? f = _colorOrNull(fill);
    final String? s = _colorOrNull(stroke);
    if (f != null && s != null) {
      canvas.setFillColor(f);
      canvas.setStrokeColor(s);
      canvas.setLineWidth(strokeWidth ?? fallbackStroke);
      canvas.fillAndStroke();
    } else if (f != null) {
      canvas.setFillColor(f);
      canvas.fill();
    } else {
      canvas.setStrokeColor(s ?? fallbackColor);
      canvas.setLineWidth(strokeWidth ?? fallbackStroke);
      canvas.stroke();
    }
  }
}

abstract class _PathOp {
  void apply(
    PdfCanvas canvas, {
    required double sx,
    required double sy,
    required double ox,
    required double oy,
  });
}

class _MoveOp extends _PathOp {
  _MoveOp(this.x, this.y);
  final double x, y;
  @override
  void apply(
    PdfCanvas canvas, {
    required double sx,
    required double sy,
    required double ox,
    required double oy,
  }) => canvas.moveTo(ox + x * sx, oy + y * sy);
}

class _LineOp extends _PathOp {
  _LineOp(this.x, this.y);
  final double x, y;
  @override
  void apply(
    PdfCanvas canvas, {
    required double sx,
    required double sy,
    required double ox,
    required double oy,
  }) => canvas.lineTo(ox + x * sx, oy + y * sy);
}

class _CloseOp extends _PathOp {
  @override
  void apply(
    PdfCanvas canvas, {
    required double sx,
    required double sy,
    required double ox,
    required double oy,
  }) => canvas.closePath();
}

String? _colorOrNull(String? raw) {
  if (raw == null) {
    return null;
  }
  final String t = raw.trim().toLowerCase();
  if (t.isEmpty || t == 'none') {
    return null;
  }
  if (t.startsWith('#')) {
    final String hex = t.substring(1);
    if (hex.length == 3) {
      return '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}'
          .toUpperCase();
    }
    if (hex.length >= 6) {
      return hex.substring(0, 6).toUpperCase();
    }
  }
  switch (t) {
    case 'black':
      return '000000';
    case 'white':
      return 'FFFFFF';
    case 'red':
      return 'E53935';
    case 'blue':
      return '1A237E';
    case 'green':
      return '2E7D32';
    default:
      return null;
  }
}

class _SvgParser {
  _SvgDoc parse(String raw) {
    final SvgViewBox? viewBox = _attr(raw, 'viewBox') == null
        ? null
        : SvgViewBox.tryParse(_attr(raw, 'viewBox')!);
    final List<_SvgShape> shapes = <_SvgShape>[];
    final RegExp tag = RegExp(
      r'<(rect|circle|line|polyline|polygon|path)\b([^>]*)/?>',
      caseSensitive: false,
    );
    for (final Match m in tag.allMatches(raw)) {
      final String name = m.group(1)!.toLowerCase();
      final String attrs = m.group(2) ?? '';
      switch (name) {
        case 'rect':
          shapes.add(
            _SvgRect(
              x: _num(attrs, 'x'),
              y: _num(attrs, 'y'),
              w: _num(attrs, 'width'),
              h: _num(attrs, 'height'),
              fill: _attr(attrs, 'fill'),
              stroke: _attr(attrs, 'stroke'),
              strokeWidth: _optNum(attrs, 'stroke-width'),
            ),
          );
        case 'circle':
          shapes.add(
            _SvgCircle(
              cx: _num(attrs, 'cx'),
              cy: _num(attrs, 'cy'),
              r: _num(attrs, 'r'),
              fill: _attr(attrs, 'fill'),
              stroke: _attr(attrs, 'stroke'),
              strokeWidth: _optNum(attrs, 'stroke-width'),
            ),
          );
        case 'line':
          shapes.add(
            _SvgLine(
              x1: _num(attrs, 'x1'),
              y1: _num(attrs, 'y1'),
              x2: _num(attrs, 'x2'),
              y2: _num(attrs, 'y2'),
              stroke: _attr(attrs, 'stroke'),
              strokeWidth: _optNum(attrs, 'stroke-width'),
            ),
          );
        case 'polyline':
        case 'polygon':
          shapes.add(
            _SvgPolyline(
              points: _points(_attr(attrs, 'points') ?? ''),
              stroke: _attr(attrs, 'stroke'),
              fill: _attr(attrs, 'fill'),
              strokeWidth: _optNum(attrs, 'stroke-width'),
              close: name == 'polygon',
            ),
          );
        case 'path':
          shapes.add(
            _SvgPath(
              ops: _parsePath(_attr(attrs, 'd') ?? ''),
              stroke: _attr(attrs, 'stroke'),
              fill: _attr(attrs, 'fill'),
              strokeWidth: _optNum(attrs, 'stroke-width'),
            ),
          );
      }
    }
    return _SvgDoc(viewBox: viewBox, shapes: shapes);
  }

  static String? _attr(String src, String name) {
    final Match? m = RegExp(
      '$name\\s*=\\s*"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(src);
    if (m != null) {
      return m.group(1);
    }
    final Match? m2 = RegExp(
      "$name\\s*=\\s*'([^']*)'",
      caseSensitive: false,
    ).firstMatch(src);
    return m2?.group(1);
  }

  static double _num(String attrs, String name) =>
      double.tryParse(_attr(attrs, name) ?? '') ?? 0;

  static double? _optNum(String attrs, String name) {
    final String? raw = _attr(attrs, name);
    if (raw == null) {
      return null;
    }
    return double.tryParse(raw);
  }

  static List<(double, double)> _points(String raw) {
    final List<double> nums = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)')
        .allMatches(raw)
        .map((Match m) => double.parse(m.group(0)!))
        .toList();
    final List<(double, double)> out = <(double, double)>[];
    for (int i = 0; i + 1 < nums.length; i += 2) {
      out.add((nums[i], nums[i + 1]));
    }
    return out;
  }

  static List<_PathOp> _parsePath(String d) {
    final List<_PathOp> ops = <_PathOp>[];
    final RegExp token = RegExp(
      r'([MmLlHhVvZz])|([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)',
    );
    String cmd = 'M';
    final List<double> args = <double>[];
    var cx = 0.0;
    var cy = 0.0;
    var startX = 0.0;
    var startY = 0.0;

    void flush() {
      if (cmd == 'Z' || cmd == 'z') {
        ops.add(_CloseOp());
        cx = startX;
        cy = startY;
        args.clear();
        return;
      }
      final bool rel = cmd == cmd.toLowerCase();
      final String u = cmd.toUpperCase();
      switch (u) {
        case 'M':
          for (int i = 0; i + 1 < args.length; i += 2) {
            final double x = rel ? cx + args[i] : args[i];
            final double y = rel ? cy + args[i + 1] : args[i + 1];
            if (i == 0) {
              ops.add(_MoveOp(x, y));
              startX = x;
              startY = y;
            } else {
              ops.add(_LineOp(x, y));
            }
            cx = x;
            cy = y;
          }
        case 'L':
          for (int i = 0; i + 1 < args.length; i += 2) {
            final double x = rel ? cx + args[i] : args[i];
            final double y = rel ? cy + args[i + 1] : args[i + 1];
            ops.add(_LineOp(x, y));
            cx = x;
            cy = y;
          }
        case 'H':
          for (final double a in args) {
            final double x = rel ? cx + a : a;
            ops.add(_LineOp(x, cy));
            cx = x;
          }
        case 'V':
          for (final double a in args) {
            final double y = rel ? cy + a : a;
            ops.add(_LineOp(cx, y));
            cy = y;
          }
      }
      args.clear();
    }

    for (final Match m in token.allMatches(d)) {
      final String? letter = m.group(1);
      final String? number = m.group(2);
      if (letter != null) {
        if (args.isNotEmpty || letter.toUpperCase() == 'Z') {
          flush();
        }
        cmd = letter;
        if (letter.toUpperCase() == 'Z') {
          flush();
        }
      } else if (number != null) {
        args.add(double.parse(number));
      }
    }
    if (args.isNotEmpty) {
      flush();
    }
    return ops;
  }
}
