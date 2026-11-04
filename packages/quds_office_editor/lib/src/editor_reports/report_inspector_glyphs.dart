import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Vector glyphs of the report inspector (alignment, orientation, line
/// styles, font style, chevrons, status marks), drawn into a 16×16 box.
abstract final class ReportInspectorGlyphs {
  static const Set<String> _names = <String>{
    'left',
    'center',
    'right',
    'justify',
    'start',
    'end',
    'top',
    'middle',
    'bottom',
    'portrait',
    'landscape',
    'solid',
    'dashed',
    'dotted',
    'bold',
    'italic',
    'underline',
  };

  /// Whether [name] has a glyph (choice options with glyphs render as an
  /// icon segmented control).
  static bool has(String name) => _names.contains(name);

  /// Paints [name] centered in [box] (nominally 16×16).
  static void paint(Canvas canvas, String name, Rect box, Color color) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint fill = Paint()..color = color;
    final double l = box.left + (box.width - 16) / 2;
    final double t = box.top + (box.height - 16) / 2;
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(l + x1, t + y1), Offset(l + x2, t + y2), stroke);
    void lines(List<(double, double)> spans) {
      for (int i = 0; i < spans.length; i++) {
        final (double a, double b) = spans[i];
        line(a, 3.5 + i * 3, b, 3.5 + i * 3);
      }
    }

    switch (name) {
      case 'left':
        lines(const <(double, double)>[(2, 14), (2, 10), (2, 14), (2, 8)]);
      case 'center':
        lines(const <(double, double)>[(2, 14), (4, 12), (2, 14), (5, 11)]);
      case 'right':
        lines(const <(double, double)>[(2, 14), (6, 14), (2, 14), (8, 14)]);
      case 'justify':
        lines(const <(double, double)>[(2, 14), (2, 14), (2, 14), (2, 14)]);
      case 'start':
        line(1.5, 2, 1.5, 14);
        lines(const <(double, double)>[(4, 14), (4, 11), (4, 14), (4, 9)]);
      case 'end':
        line(14.5, 2, 14.5, 14);
        lines(const <(double, double)>[(2, 12), (5, 12), (2, 12), (7, 12)]);
      case 'top':
        line(2, 2, 14, 2);
        canvas.drawRRect(
          RRect.fromLTRBR(
            l + 5,
            t + 4.5,
            l + 11,
            t + 10,
            const Radius.circular(1),
          ),
          fill,
        );
      case 'middle':
        line(2, 8, 4, 8);
        line(12, 8, 14, 8);
        canvas.drawRRect(
          RRect.fromLTRBR(
            l + 5,
            t + 5,
            l + 11,
            t + 11,
            const Radius.circular(1),
          ),
          fill,
        );
      case 'bottom':
        line(2, 14, 14, 14);
        canvas.drawRRect(
          RRect.fromLTRBR(
            l + 5,
            t + 6,
            l + 11,
            t + 11.5,
            const Radius.circular(1),
          ),
          fill,
        );
      case 'portrait':
        canvas.drawRRect(
          RRect.fromLTRBR(
            l + 4,
            t + 1.5,
            l + 12,
            t + 14.5,
            const Radius.circular(1.5),
          ),
          stroke,
        );
      case 'landscape':
        canvas.drawRRect(
          RRect.fromLTRBR(
            l + 1.5,
            t + 4,
            l + 14.5,
            t + 12,
            const Radius.circular(1.5),
          ),
          stroke,
        );
      case 'solid':
        line(1, 8, 15, 8);
      case 'dashed':
        line(1, 8, 4.5, 8);
        line(6.5, 8, 10, 8);
        line(12, 8, 15, 8);
      case 'dotted':
        for (double x = 1.5; x < 15.5; x += 3.2) {
          canvas.drawCircle(Offset(l + x, t + 8), 0.95, fill);
        }
      case 'bold' || 'italic' || 'underline':
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: switch (name) {
              'bold' => 'B',
              'italic' => 'I',
              _ => 'U',
            },
            style: TextStyle(
              fontFamily: name == 'italic'
                  ? 'Liberation Serif'
                  : 'Liberation Sans',
              fontSize: 13,
              color: color,
              fontWeight: name == 'bold' ? FontWeight.w700 : FontWeight.w500,
              fontStyle: name == 'italic' ? FontStyle.italic : FontStyle.normal,
              decoration: name == 'underline'
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationColor: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(l + 8 - tp.width / 2, t + 8 - tp.height / 2));
        tp.dispose();
    }
  }

  /// Small chevron centered at [c]; [open] points down, else right.
  static void chevron(
    Canvas canvas,
    Offset c,
    Color color, {
    bool open = true,
  }) {
    final Paint p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path path = open
        ? (Path()
            ..moveTo(c.dx - 3.5, c.dy - 1.5)
            ..lineTo(c.dx, c.dy + 2)
            ..lineTo(c.dx + 3.5, c.dy - 1.5))
        : (Path()
            ..moveTo(c.dx - 1.5, c.dy - 3.5)
            ..lineTo(c.dx + 2, c.dy)
            ..lineTo(c.dx - 1.5, c.dy + 3.5));
    canvas.drawPath(path, p);
  }

  /// Up or down triangle of a stepper centered at [c].
  static void stepArrow(
    Canvas canvas,
    Offset c,
    Color color, {
    required bool up,
  }) {
    final double d = up ? -1 : 1;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 3, c.dy - d * 1.5)
        ..lineTo(c.dx + 3, c.dy - d * 1.5)
        ..lineTo(c.dx, c.dy + d * 1.8)
        ..close(),
      Paint()..color = color,
    );
  }

  /// Plus sign centered at [c].
  static void plus(Canvas canvas, Offset c, Color color) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(c.translate(-4, 0), c.translate(4, 0), p)
      ..drawLine(c.translate(0, -4), c.translate(0, 4), p);
  }

  /// Severity mark: red disc with `!`, amber triangle, or green check.
  static void status(Canvas canvas, Offset c, int severity) {
    final Paint white = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    switch (severity) {
      case 2:
        canvas.drawCircle(c, 6, Paint()..color = const Color(0xFFD32F2F));
        canvas.drawLine(c.translate(0, -3), c.translate(0, 0.8), white);
        canvas.drawCircle(
          c.translate(0, 3),
          0.9,
          white..style = PaintingStyle.fill,
        );
      case 1:
        final Path tri = Path()
          ..moveTo(c.dx, c.dy - 6)
          ..lineTo(c.dx + 6.5, c.dy + 5)
          ..lineTo(c.dx - 6.5, c.dy + 5)
          ..close();
        canvas.drawPath(tri, Paint()..color = const Color(0xFFF59E0B));
        canvas.drawLine(c.translate(0, -2.5), c.translate(0, 1), white);
        canvas.drawCircle(
          c.translate(0, 3),
          0.9,
          white..style = PaintingStyle.fill,
        );
      default:
        canvas.drawCircle(c, 6, Paint()..color = const Color(0xFF2E7D32));
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - 3, c.dy)
            ..lineTo(c.dx - 0.8, c.dy + 2.4)
            ..lineTo(c.dx + 3.2, c.dy - 2.4),
          white,
        );
    }
  }

  /// "No color" swatch: white square with a red diagonal.
  static void noColor(Canvas canvas, Rect r) {
    canvas.drawRect(r, Paint()..color = const Color(0xFFFFFFFF));
    canvas.save();
    canvas.clipRect(r);
    canvas.drawLine(
      r.bottomLeft,
      r.topRight,
      Paint()
        ..color = const Color(0xFFD32F2F)
        ..strokeWidth = math.max(1.2, r.width / 12),
    );
    canvas.restore();
  }
}
