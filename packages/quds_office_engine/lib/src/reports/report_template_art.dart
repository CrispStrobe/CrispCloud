/// Pictures drawn in code for the bundled report templates: a company logo,
/// an ink stamp, a handwritten signature, a certificate seal, and product
/// photos. Pure Dart (no `dart:ui`), anti-aliased, compressed PNG output.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../opc/zip/crc32.dart';
import '../opc/zip/deflate_codec.dart';

/// Products drawn by [ReportTemplateArt.product].
enum ReportProductArt {
  laptop,
  monitor,
  keyboard,
  mouse,
  printer,
  headset,
  router,
  tablet,
}

/// Sample pictures embedded in the ready-made templates (`ReportTemplates`).
///
/// Every method returns new PNG bytes; the drawing is deterministic, so the
/// same call always yields the same image.
abstract final class ReportTemplateArt {
  static const int _navy = 0x12355B;
  static const int _teal = 0x0E7490;
  static const int _gold = 0xF2B544;
  static const int _goldDeep = 0xD4911C;

  /// Company mark (transparent PNG): a rounded tile with a domed building.
  static Uint8List logo({int size = 256}) {
    final _Raster r = _Raster(size, size);
    final double s = size / 256;
    r.fill(
      _RRect(16 * s, 16 * s, 240 * s, 240 * s, 54 * s),
      _Linear(16 * s, 16 * s, 240 * s, 240 * s, _navy, _teal),
    );
    r.fill(
      _RRect(28 * s, 28 * s, 228 * s, 128 * s, 44 * s),
      const _Solid(0xFFFFFF),
      opacity: 0.06,
    );
    final _Shape dome = _Intersect(
      _Ellipse(128 * s, 136 * s, 50 * s, 58 * s),
      _RRect(0, 0, 256 * s, 136 * s, 0),
    );
    r.fill(dome, _Linear(90 * s, 80 * s, 166 * s, 136 * s, _gold, _goldDeep));
    r.fill(
      _RRect(125 * s, 62 * s, 131 * s, 82 * s, 2 * s),
      const _Solid(_gold),
    );
    r.fill(
      _Subtract(
        _Circle(128 * s, 56 * s, 8 * s),
        _Circle(131.5 * s, 53.5 * s, 7 * s),
      ),
      const _Solid(_gold),
    );
    r.fill(
      _RRect(72 * s, 134 * s, 184 * s, 152 * s, 4 * s),
      const _Solid(0xFFFFFF),
    );
    r.fill(
      _RRect(56 * s, 150 * s, 200 * s, 192 * s, 6 * s),
      const _Solid(0xFFFFFF),
    );
    for (int i = 0; i < 5; i++) {
      final double x = (78 + i * 22) * s;
      r.fill(
        _RRect(x, 160 * s, x + 12 * s, 182 * s, 6 * s),
        _Linear(0, 160 * s, 0, 182 * s, _navy, _teal),
      );
    }
    r.fill(
      _RRect(46 * s, 202 * s, 210 * s, 208 * s, 3 * s),
      const _Solid(_gold),
    );
    return r.encode(alpha: true);
  }

  /// Round ink stamp (transparent PNG) with a ring of glyph-like marks, a
  /// star, and a date band, slightly rotated and grainy like a real print.
  static Uint8List stamp({int size = 320, int ink = 0x1D4ED8}) {
    final _Raster r = _Raster(size, size);
    final double s = size / 320;
    final double c = 160 * s;
    const double tilt = -0.21;
    final _Ink grain = _Grain(ink, 0.82, seed: 7);
    void put(_Shape shape) => r.fill(_Rotate(shape, c, c, tilt), grain);
    put(_Ring(c, c, 148 * s, 9 * s));
    put(_Ring(c, c, 129 * s, 3 * s));
    put(_Ring(c, c, 86 * s, 3 * s));
    final math.Random rnd = math.Random(11);
    for (int i = 0; i < 30; i++) {
      final double a = math.pi / 2 + 0.75 + i * ((2 * math.pi - 1.5) / 29);
      final double h = (9 + rnd.nextInt(6)) * s;
      final double w = (4 + rnd.nextInt(4)) * s;
      final double gx = c + math.cos(a) * 108 * s;
      final double gy = c + math.sin(a) * 108 * s;
      put(
        _Rotate(
          _RRect(gx - w / 2, gy - h / 2, gx + w / 2, gy + h / 2, 1.2 * s),
          gx,
          gy,
          a + math.pi / 2,
        ),
      );
    }
    for (final double a in <double>[
      math.pi * 0.5 - 0.42,
      math.pi * 0.5 + 0.42,
    ]) {
      put(
        _Star(
          c + math.cos(a) * 108 * s,
          c + math.sin(a) * 108 * s,
          7 * s,
          3 * s,
          5,
        ),
      );
    }
    put(_Star(c, c - 18 * s, 34 * s, 14 * s, 5));
    put(
      _Subtract(
        _RRect(c - 70 * s, c + 26 * s, c + 70 * s, c + 52 * s, 4 * s),
        _RRect(c - 66 * s, c + 29 * s, c + 66 * s, c + 49 * s, 2 * s),
      ),
    );
    double x = c - 58 * s;
    while (x < c + 54 * s) {
      final double w = (5 + rnd.nextInt(9)) * s;
      put(
        _RRect(x, c + 35 * s, math.min(x + w, c + 58 * s), c + 43 * s, 1.5 * s),
      );
      x += w + 4 * s;
    }
    return r.encode(alpha: true);
  }

  /// Handwritten signature in navy ink (transparent PNG).
  static Uint8List signature({int width = 420, int height = 150}) {
    final _Raster r = _Raster(width, height);
    final double sx = width / 420;
    final double sy = height / 150;
    const int ink = 0x1E2A5A;
    List<(double, double)> scaled(List<(double, double)> p) =>
        <(double, double)>[
          for (final (double, double) q in p) (q.$1 * sx, q.$2 * sy),
        ];
    r.fill(
      _Stroke(
        _spline(
          scaled(const <(double, double)>[
            (28, 104),
            (40, 44),
            (56, 108),
            (74, 36),
            (90, 104),
            (100, 72),
            (118, 62),
            (128, 86),
            (112, 98),
            (102, 80),
            (130, 70),
            (148, 96),
            (164, 58),
            (176, 96),
            (196, 68),
            (212, 92),
            (232, 54),
            (242, 100),
            (222, 110),
            (252, 80),
            (276, 88),
            (300, 70),
            (320, 94),
          ]),
        ),
        1.6 * sx,
        4.2 * sx,
      ),
      const _Solid(ink),
    );
    r.fill(
      _Stroke(
        _spline(
          scaled(const <(double, double)>[
            (52, 124),
            (130, 114),
            (230, 116),
            (320, 104),
            (392, 84),
          ]),
        ),
        1.2 * sx,
        3.4 * sx,
      ),
      const _Solid(ink),
    );
    r.fill(_Circle(184 * sx, 38 * sy, 3.2 * sx), const _Solid(ink));
    return r.encode(alpha: true);
  }

  /// Gold rosette seal with ribbon tails (transparent PNG) for certificates.
  static Uint8List seal({int size = 260}) {
    final _Raster r = _Raster(size, size);
    final double s = size / 260;
    final double cx = 130 * s;
    final double cy = 116 * s;
    for (final double dir in <double>[-1, 1]) {
      final double top = cx + dir * 22 * s;
      final double tip = cx + dir * 50 * s;
      r.fill(
        _Polygon(<double>[
          top - 20 * s,
          160 * s,
          top + 20 * s,
          160 * s,
          tip + 20 * s,
          252 * s,
          tip,
          236 * s,
          tip - 20 * s,
          252 * s,
        ]),
        _Linear(0, 160 * s, 0, 252 * s, 0xB91C1C, 0x7F1D1D),
      );
    }
    final List<double> burst = <double>[
      for (int i = 0; i < 48; i++) ...<double>[
        cx + math.cos(i * math.pi / 24) * (i.isEven ? 112 : 100) * s,
        cy + math.sin(i * math.pi / 24) * (i.isEven ? 112 : 100) * s,
      ],
    ];
    r.fill(
      _Polygon(burst),
      _Linear(
        cx - 100 * s,
        cy - 100 * s,
        cx + 100 * s,
        cy + 100 * s,
        0xF8D477,
        0xC98A12,
      ),
    );
    r.fill(
      _Circle(cx, cy, 84 * s),
      _Linear(cx, cy - 84 * s, cx, cy + 84 * s, 0xE9B23A, 0xB97A0E),
    );
    r.fill(
      _Ring(cx, cy, 74 * s, 2.4 * s),
      const _Solid(0xFFF3C4),
      opacity: 0.9,
    );
    r.fill(
      _Ring(cx, cy, 64 * s, 1.2 * s),
      const _Solid(0xFFF3C4),
      opacity: 0.7,
    );
    r.fill(_Star(cx, cy, 40 * s, 16 * s, 5), const _Solid(0xFFF8DC));
    return r.encode(alpha: true);
  }

  /// Studio-style product photo (opaque PNG) for catalogs and price lists.
  static Uint8List product(
    ReportProductArt kind, {
    int width = 240,
    int height = 180,
  }) {
    final _Raster r = _Raster(width, height);
    final double s = math.min(width / 320, height / 240);
    final double ox = (width - 320 * s) / 2;
    final double oy = (height - 240 * s) / 2;
    r.fill(
      _RRect(0, 0, width.toDouble(), height.toDouble(), 0),
      _Linear(0, 0, 0, height.toDouble(), 0xF6F8FB, 0xDDE4EE),
    );
    r.fill(
      _Ellipse(ox + 160 * s, oy + 212 * s, 120 * s, 12 * s),
      const _Solid(0x0F172A),
      opacity: 0.16,
      soft: 10 * s,
    );
    final _Pen p = _Pen(r, ox, oy, s);
    switch (kind) {
      case ReportProductArt.laptop:
        p.rrect(78, 36, 242, 152, 9, 0x2B2F36);
        p.rrect(86, 44, 234, 144, 3, 0x3B82F6, to: 0x8B5CF6);
        p.rrect(104, 60, 186, 112, 4, 0xFFFFFF, opacity: 0.88);
        p.rrect(112, 70, 170, 76, 2, 0x93C5FD);
        p.rrect(112, 82, 178, 86, 2, 0xCBD5E1);
        p.rrect(112, 92, 160, 96, 2, 0xCBD5E1);
        p.rrect(196, 60, 224, 88, 4, 0xFFFFFF, opacity: 0.55);
        p.poly(
          <double>[58, 152, 262, 152, 280, 172, 40, 172],
          0xDDE1E7,
          to: 0xA9B0BB,
        );
        p.rrect(78, 149, 242, 155, 2, 0x9AA1AC);
        p.rrect(138, 160, 182, 166, 3, 0xC3C9D2);
      case ReportProductArt.monitor:
        p.rrect(56, 26, 264, 162, 7, 0x1F2329);
        p.rrect(63, 33, 257, 148, 2, 0x38BDF8, to: 0xBAE6FD);
        const _RRect screen = _RRect(63, 33, 257, 148, 2);
        p.shape(_Intersect(_Ellipse(110, 150, 90, 40), screen), 0x16A34A);
        p.shape(_Intersect(_Ellipse(220, 156, 100, 46), screen), 0x22C55E);
        p.circle(214, 62, 14, 0xFDE68A);
        p.rrect(56, 148, 264, 162, 0, 0x1F2329);
        p.circle(160, 155, 2.5, 0x6B7280);
        p.poly(
          <double>[148, 162, 172, 162, 180, 196, 140, 196],
          0xC2C8D1,
          to: 0x9CA3AF,
        );
        p.rrect(108, 194, 212, 204, 5, 0xA3AAB5);
      case ReportProductArt.keyboard:
        p.rrect(28, 88, 292, 174, 12, 0x3A4049, to: 0x22262C);
        for (int row = 0; row < 4; row++) {
          for (int col = 0; col < 13; col++) {
            final double x = 40 + col * 19.3;
            final double y = 98 + row * 17.5;
            p.rrect(x, y, x + 16, y + 14, 3, 0x59616C, to: 0x4A515B);
          }
        }
        p.rrect(98, 151, 222, 165, 3, 0x59616C, to: 0x4A515B);
        p.rrect(40, 151, 94, 165, 3, 0x59616C, to: 0x4A515B);
        p.rrect(226, 151, 280, 165, 3, 0x59616C, to: 0x4A515B);
      case ReportProductArt.mouse:
        p.ellipse(160, 122, 54, 82, 0x4B5563, to: 0x1F2329);
        p.rrect(158, 40, 162, 112, 2, 0x15181C);
        p.rrect(153, 66, 167, 96, 7, 0xA3AAB5);
        p.ellipse(140, 92, 18, 36, 0xFFFFFF, opacity: 0.10);
      case ReportProductArt.printer:
        p.rrect(98, 34, 222, 104, 3, 0xFFFFFF);
        for (int i = 0; i < 4; i++) {
          p.rrect(
            112,
            48 + i * 10.0,
            196 - i * 12.0,
            52 + i * 10.0,
            2,
            0xCBD5E1,
          );
        }
        p.rrect(66, 92, 254, 178, 14, 0xF1F3F6, to: 0xC9CDD3);
        p.rrect(66, 150, 254, 178, 12, 0xB8BEC7);
        p.rrect(196, 106, 238, 124, 4, 0x374151);
        p.circle(230, 115, 3, 0x22C55E);
        p.rrect(100, 158, 220, 204, 2, 0xFFFFFF);
        p.rrect(114, 172, 206, 176, 2, 0x93C5FD);
        p.rrect(114, 182, 180, 186, 2, 0xCBD5E1);
      case ReportProductArt.headset:
        p.shape(
          _Intersect(_Ring(160, 132, 80, 14), _RRect(0, 0, 320, 132, 0)),
          0x3A4049,
        );
        p.rrect(62, 116, 106, 194, 20, 0x3A4049, to: 0x1F2329);
        p.rrect(214, 116, 258, 194, 20, 0x3A4049, to: 0x1F2329);
        p.rrect(96, 124, 108, 186, 6, 0x6B7280);
        p.rrect(212, 124, 224, 186, 6, 0x6B7280);
        p.stroke(
          <(double, double)>[(88, 186), (104, 204), (134, 210)],
          3.5,
          0x2F343B,
        );
        p.circle(138, 210, 6, 0x111827);
      case ReportProductArt.router:
        for (final double x in <double>[90, 155, 220]) {
          p.rrect(
            x,
            x == 155 ? 30 : 42,
            x + 10,
            124,
            5,
            0x4B5563,
            to: 0x1F2329,
          );
        }
        p.rrect(56, 118, 264, 172, 14, 0x374151, to: 0x111827);
        p.rrect(56, 118, 264, 128, 10, 0xFFFFFF, opacity: 0.08);
        for (int i = 0; i < 5; i++) {
          p.circle(
            108 + i * 20.0,
            148,
            3.5,
            i == 4 ? 0xF59E0B : (i.isEven ? 0x22C55E : 0x38BDF8),
          );
        }
      case ReportProductArt.tablet:
        p.rrect(94, 26, 226, 206, 16, 0x1F2329);
        p.rrect(102, 38, 218, 194, 6, 0xF97316, to: 0xDB2777);
        for (int row = 0; row < 4; row++) {
          for (int col = 0; col < 3; col++) {
            final double x = 114 + col * 34.0;
            final double y = 52 + row * 34.0;
            p.rrect(x, y, x + 24, y + 24, 6, 0xFFFFFF, opacity: 0.82);
          }
        }
        p.circle(160, 200, 2.5, 0x6B7280);
    }
    return r.encode(alpha: false);
  }

  /// Catmull-Rom curve through [p], sampled densely.
  static List<(double, double)> _spline(List<(double, double)> p) {
    final List<(double, double)> out = <(double, double)>[];
    for (int i = 0; i < p.length - 1; i++) {
      final (double, double) p0 = p[math.max(i - 1, 0)];
      final (double, double) p1 = p[i];
      final (double, double) p2 = p[i + 1];
      final (double, double) p3 = p[math.min(i + 2, p.length - 1)];
      for (int k = 0; k < 12; k++) {
        final double t = k / 12;
        final double t2 = t * t;
        final double t3 = t2 * t;
        double at(double a, double b, double c, double d) =>
            0.5 *
            (2 * b +
                (-a + c) * t +
                (2 * a - 5 * b + 4 * c - d) * t2 +
                (-a + 3 * b - 3 * c + d) * t3);
        out.add((
          at(p0.$1, p1.$1, p2.$1, p3.$1),
          at(p0.$2, p1.$2, p2.$2, p3.$2),
        ));
      }
    }
    out.add(p.last);
    return out;
  }
}

// ------------------------------------------------------------------ raster

/// Premultiplied RGBA float canvas.
final class _Raster {
  _Raster(this.width, this.height) : _px = Float32List(width * height * 4);

  final int width;
  final int height;
  final Float32List _px;

  /// Paints [shape] with [ink]. Coverage comes from the signed distance
  /// (negative inside), so edges are anti-aliased; [soft] widens the edge.
  void fill(_Shape shape, _Ink ink, {double opacity = 1, double soft = 1}) {
    final (double, double, double, double) b = shape.bounds;
    final int x0 = math.max(0, (b.$1 - soft - 1).floor());
    final int y0 = math.max(0, (b.$2 - soft - 1).floor());
    final int x1 = math.min(width, (b.$3 + soft + 1).ceil());
    final int y1 = math.min(height, (b.$4 + soft + 1).ceil());
    for (int y = y0; y < y1; y++) {
      final double py = y + 0.5;
      for (int x = x0; x < x1; x++) {
        final double px = x + 0.5;
        final double d = shape.distance(px, py);
        double a = 0.5 - d / soft;
        if (a <= 0) {
          continue;
        }
        if (a > 1) {
          a = 1;
        }
        final (int rgb, double alpha) = ink.at(px, py);
        a *= alpha * opacity;
        if (a <= 0) {
          continue;
        }
        final int i = (y * width + x) * 4;
        final double keep = 1 - a;
        _px[i] = ((rgb >> 16) & 0xFF) / 255 * a + _px[i] * keep;
        _px[i + 1] = ((rgb >> 8) & 0xFF) / 255 * a + _px[i + 1] * keep;
        _px[i + 2] = (rgb & 0xFF) / 255 * a + _px[i + 2] * keep;
        _px[i + 3] = a + _px[i + 3] * keep;
      }
    }
  }

  /// PNG bytes (RGBA when [alpha], else RGB), deflate-compressed.
  Uint8List encode({required bool alpha}) {
    final int channels = alpha ? 4 : 3;
    final Uint8List raw = Uint8List((width * channels + 1) * height);
    var o = 0;
    for (int y = 0; y < height; y++) {
      raw[o++] = 0;
      for (int x = 0; x < width; x++) {
        final int i = (y * width + x) * 4;
        final double a = _px[i + 3];
        for (int c = 0; c < 3; c++) {
          final double v = alpha
              ? (a > 0 ? _px[i + c] / a : 0)
              : _px[i + c] + (1 - a);
          raw[o++] = (v.clamp(0, 1) * 255).round();
        }
        if (alpha) {
          raw[o++] = (a.clamp(0, 1) * 255).round();
        }
      }
    }
    final BytesBuilder out = BytesBuilder(copy: false)
      ..add(const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    final ByteData ihdr = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, 8)
      ..setUint8(9, alpha ? 6 : 2);
    _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
    final Uint8List deflated = RawDeflate.deflate(raw, level: 9);
    final ByteData adler = ByteData(4)..setUint32(0, _adler32(raw));
    _chunk(
      out,
      'IDAT',
      Uint8List.fromList(<int>[
        0x78,
        0xDA,
        ...deflated,
        ...adler.buffer.asUint8List(),
      ]),
    );
    _chunk(out, 'IEND', Uint8List(0));
    return out.toBytes();
  }

  static void _chunk(BytesBuilder out, String type, Uint8List payload) {
    final Uint8List body = Uint8List(4 + payload.length)
      ..setAll(0, type.codeUnits)
      ..setAll(4, payload);
    out
      ..add((ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List())
      ..add(body)
      ..add(
        (ByteData(4)..setUint32(0, Crc32.compute(body))).buffer.asUint8List(),
      );
  }

  static int _adler32(Uint8List data) {
    var a = 1;
    var b = 0;
    for (int i = 0; i < data.length; i++) {
      a = (a + data[i]) % 65521;
      b = (b + a) % 65521;
    }
    return (b << 16) | a;
  }
}

/// Shorthand drawing in the 320×240 product design space.
final class _Pen {
  _Pen(this._r, this._ox, this._oy, this._s);

  final _Raster _r;
  final double _ox;
  final double _oy;
  final double _s;

  double _x(double v) => _ox + v * _s;
  double _y(double v) => _oy + v * _s;

  _Ink _ink(double top, double bottom, int color, int? to) => to == null
      ? _Solid(color)
      : _Linear(0, _y(top), 0, _y(bottom), color, to);

  void rrect(
    double l,
    double t,
    double r,
    double b,
    double radius,
    int color, {
    int? to,
    double opacity = 1,
  }) => _r.fill(
    _RRect(_x(l), _y(t), _x(r), _y(b), radius * _s),
    _ink(t, b, color, to),
    opacity: opacity,
  );

  void circle(double cx, double cy, double radius, int color) =>
      _r.fill(_Circle(_x(cx), _y(cy), radius * _s), _Solid(color));

  void ellipse(
    double cx,
    double cy,
    double rx,
    double ry,
    int color, {
    int? to,
    double opacity = 1,
  }) => _r.fill(
    _Ellipse(_x(cx), _y(cy), rx * _s, ry * _s),
    _ink(cy - ry, cy + ry, color, to),
    opacity: opacity,
  );

  void poly(List<double> points, int color, {int? to}) {
    final List<double> p = <double>[
      for (int i = 0; i < points.length; i++)
        i.isEven ? _x(points[i]) : _y(points[i]),
    ];
    double top = double.infinity;
    double bottom = -double.infinity;
    for (int i = 1; i < points.length; i += 2) {
      top = math.min(top, points[i]);
      bottom = math.max(bottom, points[i]);
    }
    _r.fill(_Polygon(p), _ink(top, bottom, color, to));
  }

  void stroke(List<(double, double)> points, double width, int color) =>
      _r.fill(
        _Stroke(
          <(double, double)>[
            for (final (double, double) q in points) (_x(q.$1), _y(q.$2)),
          ],
          width * _s,
          width * _s,
        ),
        _Solid(color),
      );

  /// [shape] given in design units.
  void shape(_Shape shape, int color) =>
      _r.fill(_Scale(shape, _ox, _oy, _s), _Solid(color));
}

// ------------------------------------------------------------------- inks

abstract class _Ink {
  const _Ink();

  (int, double) at(double x, double y);
}

final class _Solid extends _Ink {
  const _Solid(this.rgb);

  final int rgb;

  @override
  (int, double) at(double x, double y) => (rgb, 1);
}

final class _Linear extends _Ink {
  _Linear(this.x0, this.y0, double x1, double y1, this.from, this.to)
    : _dx = x1 - x0,
      _dy = y1 - y0,
      _len2 = math.max((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0), 1e-9);

  final double x0;
  final double y0;
  final int from;
  final int to;
  final double _dx;
  final double _dy;
  final double _len2;

  @override
  (int, double) at(double x, double y) {
    final double t = (((x - x0) * _dx + (y - y0) * _dy) / _len2).clamp(0, 1);
    int mix(int shift) {
      final int a = (from >> shift) & 0xFF;
      final int b = (to >> shift) & 0xFF;
      return (a + (b - a) * t).round();
    }

    return ((mix(16) << 16) | (mix(8) << 8) | mix(0), 1);
  }
}

/// Ink with print grain: alpha varies with hashed noise, with a few voids.
final class _Grain extends _Ink {
  const _Grain(this.rgb, this.alpha, {required this.seed});

  final int rgb;
  final double alpha;
  final int seed;

  double _noise(int x, int y) {
    var h = (x * 7919 + y * 104729 + seed * 1299709) & 0xFFFFFF;
    h = ((h ^ (h >> 7)) * 2654435) & 0xFFFFFF;
    h = ((h ^ (h >> 11)) * 40503) & 0xFFFFFF;
    return (h & 0xFFFF) / 0xFFFF;
  }

  @override
  (int, double) at(double x, double y) {
    final double fine = _noise(x.floor(), y.floor());
    final double coarse = _noise((x / 9).floor(), (y / 9).floor());
    final double a = alpha * (0.72 + 0.28 * fine) * (coarse < 0.1 ? 0.45 : 1);
    return (rgb, a);
  }
}

// ----------------------------------------------------------------- shapes

abstract class _Shape {
  const _Shape();

  /// Signed distance in pixels (negative inside).
  double distance(double x, double y);

  /// Left, top, right, bottom.
  (double, double, double, double) get bounds;
}

final class _Circle extends _Shape {
  const _Circle(this.cx, this.cy, this.r);

  final double cx;
  final double cy;
  final double r;

  @override
  double distance(double x, double y) =>
      math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) - r;

  @override
  (double, double, double, double) get bounds =>
      (cx - r, cy - r, cx + r, cy + r);
}

final class _Ring extends _Shape {
  const _Ring(this.cx, this.cy, this.r, this.w);

  final double cx;
  final double cy;
  final double r;
  final double w;

  @override
  double distance(double x, double y) =>
      (math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) - r).abs() - w / 2;

  @override
  (double, double, double, double) get bounds =>
      (cx - r - w, cy - r - w, cx + r + w, cy + r + w);
}

final class _Ellipse extends _Shape {
  const _Ellipse(this.cx, this.cy, this.rx, this.ry);

  final double cx;
  final double cy;
  final double rx;
  final double ry;

  @override
  double distance(double x, double y) {
    final double nx = (x - cx) / rx;
    final double ny = (y - cy) / ry;
    final double k = math.sqrt(nx * nx + ny * ny);
    if (k == 0) {
      return -math.min(rx, ry);
    }
    final double gx = nx / rx;
    final double gy = ny / ry;
    return (k - 1) * k / math.max(math.sqrt(gx * gx + gy * gy), 1e-9);
  }

  @override
  (double, double, double, double) get bounds =>
      (cx - rx, cy - ry, cx + rx, cy + ry);
}

final class _RRect extends _Shape {
  const _RRect(this.l, this.t, this.r, this.b, this.radius);

  final double l;
  final double t;
  final double r;
  final double b;
  final double radius;

  @override
  double distance(double x, double y) {
    final double hw = (r - l) / 2;
    final double hh = (b - t) / 2;
    final double rad = math.min(radius, math.min(hw, hh));
    final double qx = (x - (l + r) / 2).abs() - hw + rad;
    final double qy = (y - (t + b) / 2).abs() - hh + rad;
    final double ox = math.max(qx, 0);
    final double oy = math.max(qy, 0);
    return math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0) - rad;
  }

  @override
  (double, double, double, double) get bounds => (l, t, r, b);
}

final class _Polygon extends _Shape {
  _Polygon(this.p);

  /// x0, y0, x1, y1, …
  final List<double> p;

  @override
  double distance(double x, double y) {
    final int n = p.length ~/ 2;
    double best = double.infinity;
    bool inside = false;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final double xi = p[i * 2];
      final double yi = p[i * 2 + 1];
      final double xj = p[j * 2];
      final double yj = p[j * 2 + 1];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
      best = math.min(best, _segment(x, y, xi, yi, xj, yj));
    }
    return inside ? -best : best;
  }

  @override
  (double, double, double, double) get bounds {
    double l = double.infinity;
    double t = double.infinity;
    double r = -double.infinity;
    double b = -double.infinity;
    for (int i = 0; i < p.length; i += 2) {
      l = math.min(l, p[i]);
      r = math.max(r, p[i]);
      t = math.min(t, p[i + 1]);
      b = math.max(b, p[i + 1]);
    }
    return (l, t, r, b);
  }
}

/// Regular star with [points] tips.
final class _Star extends _Polygon {
  _Star(double cx, double cy, double outer, double inner, int points)
    : super(<double>[
        for (int i = 0; i < points * 2; i++) ...<double>[
          cx +
              math.cos(-math.pi / 2 + i * math.pi / points) *
                  (i.isEven ? outer : inner),
          cy +
              math.sin(-math.pi / 2 + i * math.pi / points) *
                  (i.isEven ? outer : inner),
        ],
      ]);
}

/// Polyline stroke whose width swells from [thin] to [thick] and back.
final class _Stroke extends _Shape {
  _Stroke(this.points, this.thin, this.thick)
    : _half = Float64List.fromList(<double>[
        for (int i = 0; i < points.length - 1; i++)
          (thin +
                  (thick - thin) *
                      math.sin(i / math.max(points.length - 2, 1) * math.pi)) /
              2,
      ]);

  final List<(double, double)> points;
  final double thin;
  final double thick;
  final Float64List _half;

  @override
  double distance(double x, double y) {
    double best = thick + 2;
    for (int i = 0; i < _half.length; i++) {
      final (double ax, double ay) = points[i];
      final (double bx, double by) = points[i + 1];
      final double reach = best + _half[i];
      if (x < math.min(ax, bx) - reach ||
          x > math.max(ax, bx) + reach ||
          y < math.min(ay, by) - reach ||
          y > math.max(ay, by) + reach) {
        continue;
      }
      best = math.min(best, _segment(x, y, ax, ay, bx, by) - _half[i]);
    }
    return best;
  }

  @override
  (double, double, double, double) get bounds {
    double l = double.infinity;
    double t = double.infinity;
    double r = -double.infinity;
    double b = -double.infinity;
    for (final (double x, double y) in points) {
      l = math.min(l, x);
      r = math.max(r, x);
      t = math.min(t, y);
      b = math.max(b, y);
    }
    return (l - thick, t - thick, r + thick, b + thick);
  }
}

final class _Intersect extends _Shape {
  const _Intersect(this.a, this.b);

  final _Shape a;
  final _Shape b;

  @override
  double distance(double x, double y) =>
      math.max(a.distance(x, y), b.distance(x, y));

  @override
  (double, double, double, double) get bounds {
    final (double, double, double, double) p = a.bounds;
    final (double, double, double, double) q = b.bounds;
    return (
      math.max(p.$1, q.$1),
      math.max(p.$2, q.$2),
      math.min(p.$3, q.$3),
      math.min(p.$4, q.$4),
    );
  }
}

final class _Subtract extends _Shape {
  const _Subtract(this.a, this.b);

  final _Shape a;
  final _Shape b;

  @override
  double distance(double x, double y) =>
      math.max(a.distance(x, y), -b.distance(x, y));

  @override
  (double, double, double, double) get bounds => a.bounds;
}

/// [shape] rotated by [angle] radians around (cx, cy).
final class _Rotate extends _Shape {
  _Rotate(this.shape, this.cx, this.cy, double angle)
    : _cos = math.cos(angle),
      _sin = math.sin(angle);

  final _Shape shape;
  final double cx;
  final double cy;
  final double _cos;
  final double _sin;

  @override
  double distance(double x, double y) {
    final double dx = x - cx;
    final double dy = y - cy;
    return shape.distance(
      cx + dx * _cos + dy * _sin,
      cy - dx * _sin + dy * _cos,
    );
  }

  @override
  (double, double, double, double) get bounds {
    final (double l, double t, double r, double b) = shape.bounds;
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;
    for (final (double x, double y) in <(double, double)>[
      (l, t),
      (r, t),
      (l, b),
      (r, b),
    ]) {
      final double dx = x - cx;
      final double dy = y - cy;
      final double rx = cx + dx * _cos - dy * _sin;
      final double ry = cy + dx * _sin + dy * _cos;
      minX = math.min(minX, rx);
      maxX = math.max(maxX, rx);
      minY = math.min(minY, ry);
      maxY = math.max(maxY, ry);
    }
    return (minX, minY, maxX, maxY);
  }
}

/// [shape] given in design units, placed at (ox, oy) and scaled by [s].
final class _Scale extends _Shape {
  const _Scale(this.shape, this.ox, this.oy, this.s);

  final _Shape shape;
  final double ox;
  final double oy;
  final double s;

  @override
  double distance(double x, double y) =>
      shape.distance((x - ox) / s, (y - oy) / s) * s;

  @override
  (double, double, double, double) get bounds {
    final (double l, double t, double r, double b) = shape.bounds;
    return (ox + l * s, oy + t * s, ox + r * s, oy + b * s);
  }
}

double _segment(
  double x,
  double y,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final double dx = bx - ax;
  final double dy = by - ay;
  final double len2 = dx * dx + dy * dy;
  final double t = len2 == 0
      ? 0
      : (((x - ax) * dx + (y - ay) * dy) / len2).clamp(0, 1);
  final double px = ax + dx * t - x;
  final double py = ay + dy * t - y;
  return math.sqrt(px * px + py * py);
}
