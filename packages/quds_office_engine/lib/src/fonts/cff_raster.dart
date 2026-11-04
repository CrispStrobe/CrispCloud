/// Type 2 charstring rasterizer used for CFF outlines inside the engine.
library;

import 'dart:typed_data';

/// A grayscale bitmap, row-major, 0 transparent and 255 covered.
class CffBitmap {
  /// CffBitmap API.
  const CffBitmap({required this.width, required this.height, required this.pixels});

  /// width API.
  final int width;

  /// height API.
  final int height;

  /// pixels API.
  final Uint8List pixels;
}

/// Interprets a Type 2 charstring (`rmoveto`, `h/vmoveto`, `rlineto`,
/// `h/vlineto`, `rrcurveto`, `endchar`) and fills the outline.
abstract final class CffRaster {
  /// Rasterizes [program] into a square of [size] pixels.
  static CffBitmap charstring(Uint8List program, {int size = 64}) {
    final int side = size < 8 ? 8 : size;
    final List<({double x, double y})> points = <({double x, double y})>[];
    final List<int> contourEnds = <int>[];
    final List<double> stack = <double>[];
    var x = 0.0;
    var y = 0.0;
    var i = 0;
    void lineTo(double nx, double ny) {
      points.add((x: nx, y: ny));
      x = nx;
      y = ny;
    }

    void curve(double x1, double y1, double x2, double y2, double x3, double y3) {
      const int steps = 8;
      for (int s = 1; s <= steps; s++) {
        final double t = s / steps;
        final double u = 1 - t;
        lineTo(
          u * u * u * x +
              3 * u * u * t * x1 +
              3 * u * t * t * x2 +
              t * t * t * x3,
          u * u * u * y +
              3 * u * u * t * y1 +
              3 * u * t * t * y2 +
              t * t * t * y3,
        );
      }
    }

    while (i < program.length) {
      final int op = program[i++];
      if (op >= 32) {
        if (op <= 246) {
          stack.add((op - 139).toDouble());
        } else if (op <= 250 && i < program.length) {
          stack.add(((op - 247) * 256 + program[i++] + 108).toDouble());
        } else if (op <= 254 && i < program.length) {
          stack.add((-(op - 251) * 256 - program[i++] - 108).toDouble());
        } else if (i + 4 <= program.length) {
          final int v = (program[i] << 24) |
              (program[i + 1] << 16) |
              (program[i + 2] << 8) |
              program[i + 3];
          i += 4;
          stack.add((v > 0x7FFFFFFF ? v - 0x100000000 : v) / 65536);
        }
        continue;
      }
      switch (op) {
        case 21: // rmoveto
          if (stack.length >= 2) {
            if (points.isNotEmpty) {
              contourEnds.add(points.length);
            }
            x += stack[stack.length - 2];
            y += stack.last;
            points.add((x: x, y: y));
          }
        case 22: // hmoveto
          if (stack.isNotEmpty) {
            if (points.isNotEmpty) {
              contourEnds.add(points.length);
            }
            x += stack.last;
            points.add((x: x, y: y));
          }
        case 4: // vmoveto
          if (stack.isNotEmpty) {
            if (points.isNotEmpty) {
              contourEnds.add(points.length);
            }
            y += stack.last;
            points.add((x: x, y: y));
          }
        case 5: // rlineto
          for (int k = 0; k + 1 < stack.length; k += 2) {
            lineTo(x + stack[k], y + stack[k + 1]);
          }
        case 6: // hlineto
        case 7: // vlineto
          var horizontal = op == 6;
          for (final double d in stack) {
            if (horizontal) {
              lineTo(x + d, y);
            } else {
              lineTo(x, y + d);
            }
            horizontal = !horizontal;
          }
        case 8: // rrcurveto
          for (int k = 0; k + 5 < stack.length; k += 6) {
            curve(
              x + stack[k],
              y + stack[k + 1],
              x + stack[k] + stack[k + 2],
              y + stack[k + 1] + stack[k + 3],
              x + stack[k] + stack[k + 2] + stack[k + 4],
              y + stack[k + 1] + stack[k + 3] + stack[k + 5],
            );
          }
        case 14: // endchar
          if (points.isNotEmpty) {
            contourEnds.add(points.length);
          }
          i = program.length;
        default:
          break;
      }
      stack.clear();
    }
    if (points.isEmpty) {
      return CffBitmap(width: side, height: side, pixels: Uint8List(side * side));
    }
    var minX = points.first.x;
    var maxX = points.first.x;
    var minY = points.first.y;
    var maxY = points.first.y;
    for (final ({double x, double y}) p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    final double span = (maxX - minX) > (maxY - minY) ? maxX - minX : maxY - minY;
    final double scale = span <= 0 ? 1 : (side - 4) / span;
    final Uint8List pixels = Uint8List(side * side);
    var start = 0;
    for (final int end in contourEnds) {
      if (end - start >= 2) {
        _fill(
          pixels,
          side,
          <({double x, double y})>[
            for (int k = start; k < end; k++)
              (
                x: 2 + (points[k].x - minX) * scale,
                y: side - 2 - (points[k].y - minY) * scale,
              ),
          ],
        );
      }
      start = end;
    }
    return CffBitmap(width: side, height: side, pixels: pixels);
  }

  static void _fill(
    Uint8List pixels,
    int side,
    List<({double x, double y})> contour,
  ) {
    for (int y = 0; y < side; y++) {
      final List<double> hits = <double>[];
      for (int i = 0; i < contour.length; i++) {
        final ({double x, double y}) a = contour[i];
        final ({double x, double y}) b = contour[(i + 1) % contour.length];
        if ((a.y <= y && b.y > y) || (b.y <= y && a.y > y)) {
          final double t = (y - a.y) / (b.y - a.y);
          hits.add(a.x + (b.x - a.x) * t);
        }
      }
      hits.sort();
      for (int i = 0; i + 1 < hits.length; i += 2) {
        final int from = hits[i].ceil().clamp(0, side);
        final int to = hits[i + 1].floor().clamp(0, side);
        for (int x = from; x < to; x++) {
          pixels[y * side + x] = 255;
        }
      }
    }
  }
}
