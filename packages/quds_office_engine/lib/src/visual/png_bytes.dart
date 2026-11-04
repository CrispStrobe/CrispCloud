import 'dart:math' as math;
import 'dart:typed_data';

import '../builders/office_markup.dart';
import '../opc/zip/crc32.dart';
import 'office_visual.dart';

/// Minimal RGB PNG writer used for demo pictures (no `dart:ui`).
abstract final class PngBytes {
  /// rgb API.
  static Uint8List rgb({
    required int width,
    required int height,
    required void Function(int x, int y, List<int> rgb) plot,
  }) {
    final Uint8List raw = Uint8List((width * 3 + 1) * height);
    final List<int> pixel = <int>[0, 0, 0];
    var i = 0;
    for (int y = 0; y < height; y++) {
      raw[i++] = 0;
      for (int x = 0; x < width; x++) {
        pixel[0] = 0;
        pixel[1] = 0;
        pixel[2] = 0;
        plot(x, y, pixel);
        raw[i++] = pixel[0] & 0xFF;
        raw[i++] = pixel[1] & 0xFF;
        raw[i++] = pixel[2] & 0xFF;
      }
    }
    final BytesBuilder out = BytesBuilder(copy: false);
    out.add(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
    _chunk(out, 'IHDR', _ihdr(width, height));
    _chunk(out, 'IDAT', _zlib(raw));
    _chunk(out, 'IEND', Uint8List(0));
    return out.toBytes();
  }

  /// RGBA PNG so floating logos keep a true alpha channel.
  static Uint8List rgba({
    required int width,
    required int height,
    required void Function(int x, int y, List<int> rgba) plot,
  }) {
    final Uint8List raw = Uint8List((width * 4 + 1) * height);
    final List<int> pixel = <int>[0, 0, 0, 255];
    var i = 0;
    for (int y = 0; y < height; y++) {
      raw[i++] = 0;
      for (int x = 0; x < width; x++) {
        pixel[0] = 0;
        pixel[1] = 0;
        pixel[2] = 0;
        pixel[3] = 255;
        plot(x, y, pixel);
        raw[i++] = pixel[0] & 0xFF;
        raw[i++] = pixel[1] & 0xFF;
        raw[i++] = pixel[2] & 0xFF;
        raw[i++] = pixel[3] & 0xFF;
      }
    }
    final BytesBuilder out = BytesBuilder(copy: false);
    out.add(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
    _chunk(out, 'IHDR', _ihdr(width, height, colorType: 6));
    _chunk(out, 'IDAT', _zlib(raw));
    _chunk(out, 'IEND', Uint8List(0));
    return out.toBytes();
  }

  /// PNG from packed RGB pixels, three bytes per pixel, top row first.
  static Uint8List fromRgb({
    required int width,
    required int height,
    required Uint8List pixels,
  }) {
    return _fromPacked(
      width: width,
      height: height,
      pixels: pixels,
      channels: 3,
    );
  }

  /// PNG from packed RGBA pixels, four bytes per pixel, top row first.
  static Uint8List fromRgba({
    required int width,
    required int height,
    required Uint8List pixels,
  }) {
    return _fromPacked(
      width: width,
      height: height,
      pixels: pixels,
      channels: 4,
    );
  }

  static Uint8List _fromPacked({
    required int width,
    required int height,
    required Uint8List pixels,
    required int channels,
  }) {
    final int row = width * channels;
    final Uint8List raw = Uint8List((row + 1) * height);
    var src = 0;
    var dst = 0;
    for (var y = 0; y < height; y++) {
      raw[dst++] = 0;
      final int take = src + row <= pixels.length ? row : pixels.length - src;
      if (take > 0) {
        raw.setRange(dst, dst + take, pixels, src);
      }
      src += row;
      dst += row;
    }
    final BytesBuilder out = BytesBuilder(copy: false);
    out.add(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
    _chunk(out, 'IHDR', _ihdr(width, height, colorType: channels == 4 ? 6 : 2));
    _chunk(out, 'IDAT', _zlib(raw));
    _chunk(out, 'IEND', Uint8List(0));
    return out.toBytes();
  }

  /// Raster of a chart or diagram so Word/LibreOffice can show the visual.
  static Uint8List fromVisual(OfficeVisual visual, {int? width, int? height}) {
    final int w = (width ?? visual.width.round()).clamp(80, 1200);
    final int h = (height ?? visual.height.round()).clamp(60, 800);
    if (visual.isPicture &&
        visual.imageBytes != null &&
        visual.imageBytes!.isNotEmpty) {
      return visual.imageBytes!;
    }
    if (visual.isChart) {
      return chart(
        visual.points,
        title: visual.title,
        width: w,
        height: h,
        kind: visual.kind,
      );
    }
    return diagram(title: visual.title, width: w, height: h, kind: visual.kind);
  }

  /// chart API.
  static Uint8List chart(
    List<ChartPoint> points, {
    String title = '',
    int width = 420,
    int height = 170,
    OfficeVisualKind kind = OfficeVisualKind.chartColumn,
  }) {
    final List<ChartPoint> pts = points.isEmpty
        ? OfficeVisual.sampleSeries()
        : points;
    var maxV = 1.0;
    for (final ChartPoint p in pts) {
      if (p.value > maxV) {
        maxV = p.value;
      }
    }
    return rgb(
      width: width,
      height: height,
      plot: (int x, int y, List<int> rgb) {
        rgb[0] = 0xFF;
        rgb[1] = 0xFF;
        rgb[2] = 0xFF;
        if (y < 22) {
          rgb[0] = 0x2B;
          rgb[1] = 0x57;
          rgb[2] = 0x9A;
          return;
        }
        if (kind == OfficeVisualKind.chartBar) {
          _plotBars(x, y, width, height, pts, maxV, rgb, vertical: false);
          return;
        }
        if (kind == OfficeVisualKind.chartPie) {
          _plotPie(x, y, width, height, pts, maxV, rgb);
          return;
        }
        if (kind == OfficeVisualKind.chartLine) {
          _plotLine(x, y, width, height, pts, maxV, rgb);
          return;
        }
        _plotBars(x, y, width, height, pts, maxV, rgb, vertical: true);
      },
    );
  }

  /// diagram API.
  static Uint8List diagram({
    String title = '',
    int width = 360,
    int height = 140,
    OfficeVisualKind kind = OfficeVisualKind.diagramProcess,
  }) {
    return rgb(
      width: width,
      height: height,
      plot: (int x, int y, List<int> rgb) {
        rgb[0] = 0xF7;
        rgb[1] = 0xF7;
        rgb[2] = 0xF7;
        if (y < 20) {
          rgb[0] = 0x2B;
          rgb[1] = 0x57;
          rgb[2] = 0x9A;
          return;
        }
        const List<List<int>> colors = <List<int>>[
          <int>[0x2B, 0x57, 0x9A],
          <int>[0x21, 0x73, 0x46],
          <int>[0xB7, 0x47, 0x2A],
        ];
        if (kind == OfficeVisualKind.diagramCycle) {
          final int cx = width ~/ 2;
          final int cy = 20 + (height - 20) ~/ 2;
          final int r = math.min(width, height - 20) ~/ 3;
          final int d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy);
          if (d2 < r * r && d2 > (r - 14) * (r - 14)) {
            final List<int> c = colors[(x + y) % colors.length];
            rgb[0] = c[0];
            rgb[1] = c[1];
            rgb[2] = c[2];
          }
          return;
        }
        final int boxW = ((width - 48) / 3).floor();
        final int top = kind == OfficeVisualKind.diagramHierarchy ? 36 : 48;
        final int boxH = 44;
        for (int i = 0; i < 3; i++) {
          final int left = 16 + i * (boxW + 8);
          final int boxTop = kind == OfficeVisualKind.diagramHierarchy && i == 1
              ? top + 36
              : top;
          if (x >= left &&
              x < left + boxW &&
              y >= boxTop &&
              y < boxTop + boxH) {
            rgb[0] = colors[i][0];
            rgb[1] = colors[i][1];
            rgb[2] = colors[i][2];
          }
        }
      },
    );
  }

  static void _plotBars(
    int x,
    int y,
    int width,
    int height,
    List<ChartPoint> pts,
    double maxV,
    List<int> rgb, {
    required bool vertical,
  }) {
    final int plotTop = 32;
    final int plotBottom = height - 16;
    final int plotLeft = 16;
    final int plotRight = width - 16;
    if (y < plotTop || y >= plotBottom || x < plotLeft || x >= plotRight) {
      return;
    }
    final int n = pts.isEmpty ? 1 : pts.length;
    if (vertical) {
      final double slot = (plotRight - plotLeft) / n;
      final int i = ((x - plotLeft) / slot).floor().clamp(0, n - 1);
      final int gap = 6;
      final int barLeft = plotLeft + (i * slot).round() + gap;
      final int barRight = plotLeft + ((i + 1) * slot).round() - gap;
      final int barH = ((plotBottom - plotTop) * (pts[i].value / maxV))
          .round()
          .clamp(2, plotBottom - plotTop);
      if (x >= barLeft && x < barRight && y > plotBottom - barH) {
        _fillColor(pts[i].color, rgb);
      }
      return;
    }
    final double slot = (plotBottom - plotTop) / n;
    final int i = ((y - plotTop) / slot).floor().clamp(0, n - 1);
    final int gap = 4;
    final int barTop = plotTop + (i * slot).round() + gap;
    final int barBottom = plotTop + ((i + 1) * slot).round() - gap;
    final int barW = ((plotRight - plotLeft) * (pts[i].value / maxV))
        .round()
        .clamp(2, plotRight - plotLeft);
    if (y >= barTop && y < barBottom && x < plotLeft + barW) {
      _fillColor(pts[i].color, rgb);
    }
  }

  static void _plotPie(
    int x,
    int y,
    int width,
    int height,
    List<ChartPoint> pts,
    double maxV,
    List<int> rgb,
  ) {
    final int cx = width ~/ 2;
    final int cy = 22 + (height - 22) ~/ 2;
    final int r = math.min(width, height - 22) ~/ 3;
    final int dx = x - cx;
    final int dy = y - cy;
    if (dx * dx + dy * dy > r * r) {
      return;
    }
    var sum = 0.0;
    for (final ChartPoint p in pts) {
      sum += p.value > 0 ? p.value : 0;
    }
    if (sum <= 0) {
      sum = 1;
    }
    var angle = math.atan2(dy.toDouble(), dx.toDouble());
    if (angle < 0) {
      angle += math.pi * 2;
    }
    var walked = 0.0;
    final double t = angle / (math.pi * 2);
    for (int i = 0; i < pts.length; i++) {
      walked += (pts[i].value > 0 ? pts[i].value : 0) / sum;
      if (t <= walked || i == pts.length - 1) {
        _fillColor(pts[i].color, rgb);
        return;
      }
    }
  }

  static void _plotLine(
    int x,
    int y,
    int width,
    int height,
    List<ChartPoint> pts,
    double maxV,
    List<int> rgb,
  ) {
    final int plotTop = 32;
    final int plotBottom = height - 16;
    final int plotLeft = 16;
    final int plotRight = width - 16;
    if (pts.length < 2 || x < plotLeft || x >= plotRight) {
      return;
    }
    final double t = (x - plotLeft) / (plotRight - plotLeft);
    final double idx = t * (pts.length - 1);
    final int i0 = idx.floor().clamp(0, pts.length - 2);
    final double f = idx - i0;
    final double v = pts[i0].value * (1 - f) + pts[i0 + 1].value * f;
    final int py = plotBottom - ((plotBottom - plotTop) * (v / maxV)).round();
    if ((y - py).abs() <= 2) {
      _fillColor(pts[i0].color, rgb);
    }
  }

  static void _fillColor(String hex, List<int> rgb) {
    final String h = hex.replaceAll('#', '');
    if (h.length >= 6) {
      rgb[0] =
          int.tryParse(h.substring(h.length - 6, h.length - 4), radix: 16) ??
          0x2B;
      rgb[1] =
          int.tryParse(h.substring(h.length - 4, h.length - 2), radix: 16) ??
          0x57;
      rgb[2] = int.tryParse(h.substring(h.length - 2), radix: 16) ?? 0x9A;
      return;
    }
    rgb[0] = 0x2B;
    rgb[1] = 0x57;
    rgb[2] = 0x9A;
  }

  /// Office-blue sample card with three accent bars.
  static Uint8List studioCard({int width = 240, int height = 140}) {
    return rgb(
      width: width,
      height: height,
      plot: (int x, int y, List<int> rgb) {
        if (y < 28) {
          rgb[0] = 0x2B;
          rgb[1] = 0x57;
          rgb[2] = 0x9A;
          return;
        }
        rgb[0] = 0xF3;
        rgb[1] = 0xF6;
        rgb[2] = 0xFB;
        final int barTop = 48;
        final int barBottom = height - 24;
        if (y >= barTop && y < barBottom) {
          final int slot = ((x - 24) / ((width - 48) / 3)).floor();
          if (x > 24 && x < width - 24 && slot >= 0 && slot < 3) {
            final List<int> heights = <int>[
              ((barBottom - barTop) * 0.55).round(),
              ((barBottom - barTop) * 0.8).round(),
              ((barBottom - barTop) * 0.4).round(),
            ];
            if (y > barBottom - heights[slot]) {
              switch (slot) {
                case 0:
                  rgb[0] = 0x2B;
                  rgb[1] = 0x57;
                  rgb[2] = 0x9A;
                case 1:
                  rgb[0] = 0x21;
                  rgb[1] = 0x73;
                  rgb[2] = 0x46;
                default:
                  rgb[0] = 0xB7;
                  rgb[1] = 0x47;
                  rgb[2] = 0x2A;
              }
            }
          }
        }
      },
    );
  }

  static Uint8List _ihdr(int width, int height, {int colorType = 2}) {
    final ByteData data = ByteData(13);
    data.setUint32(0, width);
    data.setUint32(4, height);
    data.setUint8(8, 8);
    data.setUint8(9, colorType);
    return data.buffer.asUint8List();
  }

  static void _chunk(BytesBuilder out, String type, Uint8List payload) {
    final ByteData len = ByteData(4)..setUint32(0, payload.length);
    out.add(len.buffer.asUint8List());
    final Uint8List typeBytes = Uint8List.fromList(type.codeUnits);
    out.add(typeBytes);
    out.add(payload);
    final Uint8List crcSrc = Uint8List(typeBytes.length + payload.length);
    crcSrc.setAll(0, typeBytes);
    crcSrc.setAll(typeBytes.length, payload);
    final ByteData crc = ByteData(4)..setUint32(0, Crc32.compute(crcSrc));
    out.add(crc.buffer.asUint8List());
  }

  static Uint8List _zlib(Uint8List raw) {
    final Uint8List deflated = _storedDeflate(raw);
    final int adler = _adler32(raw);
    final Uint8List out = Uint8List(2 + deflated.length + 4);
    out[0] = 0x78;
    out[1] = 0x01;
    out.setAll(2, deflated);
    final ByteData tail = ByteData(4)..setUint32(0, adler);
    out.setAll(2 + deflated.length, tail.buffer.asUint8List());
    return out;
  }

  static Uint8List _storedDeflate(Uint8List raw) {
    final BytesBuilder out = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < raw.length) {
      final int n = math.min(65535, raw.length - offset);
      final bool last = offset + n >= raw.length;
      out.addByte(last ? 1 : 0);
      out.addByte(n & 0xFF);
      out.addByte((n >> 8) & 0xFF);
      out.addByte((~n) & 0xFF);
      out.addByte(((~n) >> 8) & 0xFF);
      out.add(raw.sublist(offset, offset + n));
      offset += n;
    }
    return out.toBytes();
  }

  static int _adler32(Uint8List data) {
    var a = 1;
    var b = 0;
    for (int i = 0; i < data.length; i++) {
      a = (a + data[i]) % 65521;
      b = (b + a) % 65521;
    }
    return ((b << 16) | a) & 0xFFFFFFFF;
  }
}
