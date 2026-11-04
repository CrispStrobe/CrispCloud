/// Images, charts, links, watermark, and table of contents.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../builders/office_markup.dart';
import '../../pdf/pdf_canvas.dart';
import '../../pdf/pdf_document.dart';
import '../../pdf/pdf_image.dart';
import 'pw_box.dart';
import 'pw_core.dart';
import 'pw_layout.dart';
import 'pw_paint.dart';
import 'pw_style.dart';
import 'pw_text.dart';
import 'pw_types.dart';

/// Image bytes provider.
class ImageProvider {
  /// ImageProvider API.
  const ImageProvider(this.bytes);

  /// bytes API.
  final Uint8List bytes;
}

/// In-memory PNG / JPEG.
class MemoryImage extends ImageProvider {
  /// MemoryImage API.
  const MemoryImage(super.bytes);
}

/// Inline picture.
class Image extends Widget {
  /// Image API.
  const Image(
    this.image, {
    this.width,
    this.height,
    this.dpi,
    this.fit = BoxFit.contain,
  });

  /// image API.
  final ImageProvider image;

  /// width API.
  final double? width;

  /// height API.
  final double? height;

  /// dpi API.
  final double? dpi;

  /// fit API.
  final BoxFit fit;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final PdfRaster? raster = PdfImageCodec.decode(image.bytes);
    final double iw = raster == null
        ? (width ?? 120)
        : (dpi != null
              ? raster.width * 72 / dpi!
              : width ?? raster.width.toDouble());
    final double ih = raster == null
        ? (height ?? 80)
        : (dpi != null
              ? raster.height * 72 / dpi!
              : height ??
                    (width != null && raster.width > 0
                        ? width! * raster.height / raster.width
                        : raster.height.toDouble()));
    final PwSize size = constraints.constrain(PwSize(iw, ih));
    return _ImageBox(size, image.bytes, raster);
  }
}

class _ImageBox extends PwBox {
  _ImageBox(super.size, this.bytes, this.raster);

  final Uint8List bytes;
  final PdfRaster? raster;

  @override
  void paint(Context context, PwOffset offset) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      return;
    }
    final PdfRaster? decoded = raster ?? PdfImageCodec.decode(bytes);
    if (decoded == null) {
      canvas.fillRect(offset.dx, offset.dy, size.width, size.height, 'ECEFF1');
      return;
    }
    final String name = context.nextImageName();
    context.images.add(
      PdfEmbeddedImage(
        name: name,
        width: decoded.width,
        height: decoded.height,
        bytes: decoded.jpegBytes ?? decoded.rgb,
        jpeg: decoded.isJpeg,
        maskBytes: decoded.alpha,
      ),
    );
    canvas.drawImage(name, offset.dx, offset.dy, size.width, size.height);
  }
}

/// Chart kind drawn with [PdfCanvas] paths.
enum ChartType { bar, line, pie }

/// Vector chart (no Flutter). Bars, line, and pie with axes, values, and legend.
class Chart extends Widget {
  /// Chart API.
  const Chart({
    this.type = ChartType.bar,
    this.points = const <ChartPoint>[],
    this.title = '',
    this.width = 360,
    this.height = 180,
    this.showValues = true,
    this.showLegend = true,
    this.showGrid = true,
  });

  /// type API.
  final ChartType type;

  /// points API.
  final List<ChartPoint> points;

  /// title API.
  final String title;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// Paint numeric labels on marks.
  final bool showValues;

  /// Color key beside pie charts, under bar/line charts when space allows.
  final bool showLegend;

  /// Horizontal guides on bar and line plots.
  final bool showGrid;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    context.useText(title);
    for (final ChartPoint p in points) {
      context.useText(p.label);
      if (showValues) {
        context.useText(_chartValue(p.value));
      }
    }
    return _ChartBox(
      constraints.constrain(PwSize(width, height)),
      type,
      points,
      title,
      showValues: showValues,
      showLegend: showLegend,
      showGrid: showGrid,
    );
  }
}

String _chartValue(double value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

/// Keep axis labels inside their slot so Latin names do not collide.
String _chartAxisLabel(String label, double slotWidth) {
  final String trimmed = label.trim();
  if (trimmed.isEmpty || slotWidth >= 90) {
    return trimmed;
  }
  // Cutting Arabic mid-word breaks joining; leave the full string.
  for (final int unit in trimmed.codeUnits) {
    if (unit >= 0x0600 && unit <= 0x06FF) {
      return trimmed;
    }
  }
  if (slotWidth >= 48) {
    return trimmed.length <= 14 ? trimmed : '${trimmed.substring(0, 13)}…';
  }
  if (slotWidth >= 32) {
    return trimmed.length <= 10 ? trimmed : '${trimmed.substring(0, 9)}…';
  }
  return trimmed.length <= 6 ? trimmed : '${trimmed.substring(0, 5)}…';
}

class _ChartBox extends PwBox {
  _ChartBox(
    super.size,
    this.type,
    this.points,
    this.title, {
    required this.showValues,
    required this.showLegend,
    required this.showGrid,
  });

  final ChartType type;
  final List<ChartPoint> points;
  final String title;
  final bool showValues;
  final bool showLegend;
  final bool showGrid;

  @override
  void paint(Context context, PwOffset offset) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      return;
    }
    canvas.endText();
    canvas.setFillColor('FAFBFC');
    canvas.roundedRect(offset.dx, offset.dy, size.width, size.height, 4);
    canvas.fill();
    if (title.isNotEmpty) {
      final bool rtl = context.textDirection == TextDirection.rtl;
      pwPaintParagraph(
        context,
        title,
        PwOffset(offset.dx + 10, offset.dy + 6),
        size.width - 20,
        const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: '37474F',
        ),
        rtl ? TextAlign.right : TextAlign.left,
      );
    }
    if (points.isEmpty) {
      pwPaintParagraph(
        context,
        'No data',
        PwOffset(offset.dx + 12, offset.dy + size.height / 2 - 6),
        size.width - 24,
        const TextStyle(fontSize: 9, color: '78909C'),
        TextAlign.center,
      );
      return;
    }
    final List<ChartPoint> pts = points;
    var maxV = 1.0;
    for (final ChartPoint p in pts) {
      if (p.value > maxV) {
        maxV = p.value;
      }
    }
    final double plotTop = offset.dy + (title.isEmpty ? 14 : 26);
    final double legendH = showLegend && type != ChartType.pie ? 16 : 0;
    final double plotLeft = offset.dx + (type == ChartType.pie ? 12 : 28);
    final double plotW = size.width - (type == ChartType.pie ? 24 : 40);
    final double plotH =
        size.height - (title.isEmpty ? 28 : 42) - legendH;
    switch (type) {
      case ChartType.bar:
        _bars(context, canvas, pts, maxV, plotLeft, plotTop, plotW, plotH);
      case ChartType.line:
        _line(context, canvas, pts, maxV, plotLeft, plotTop, plotW, plotH);
      case ChartType.pie:
        _pie(context, canvas, pts, plotLeft, plotTop, plotW, plotH);
    }
    if (showLegend && type != ChartType.pie) {
      _legendRow(context, canvas, pts, offset.dx + 12, offset.dy + size.height - 16, size.width - 24);
    }
  }

  void _grid(
    PdfCanvas canvas,
    double x,
    double y,
    double w,
    double h,
    double maxV,
  ) {
    canvas.setStrokeColor('ECEFF1');
    canvas.setLineWidth(0.4);
    for (int i = 0; i <= 3; i++) {
      final double gy = y + (h - 16) * i / 3;
      canvas.moveTo(x, gy);
      canvas.lineTo(x + w, gy);
      canvas.stroke();
    }
  }

  void _yLabels(
    Context context,
    double x,
    double y,
    double h,
    double maxV,
  ) {
    for (int i = 0; i <= 3; i++) {
      final double v = maxV * (1 - i / 3);
      final double gy = y + (h - 16) * i / 3;
      pwPaintParagraph(
        context,
        _chartValue(v),
        PwOffset(x - 26, gy - 4),
        24,
        const TextStyle(fontSize: 6, color: '90A4AE'),
        TextAlign.right,
      );
    }
  }

  void _bars(
    Context context,
    PdfCanvas canvas,
    List<ChartPoint> pts,
    double maxV,
    double x,
    double y,
    double w,
    double h,
  ) {
    if (showGrid) {
      _grid(canvas, x, y, w, h, maxV);
      _yLabels(context, x, y, h, maxV);
    }
    final double slot = w / pts.length;
    final double barW = slot * 0.55;
    for (int i = 0; i < pts.length; i++) {
      final double bh = (pts[i].value / maxV) * (h - 16);
      final double bx = x + i * slot + (slot - barW) / 2;
      final double by = y + h - 14 - bh;
      final double topRadius = (barW * 0.22).clamp(2.0, 6.0);
      canvas.endText();
      canvas.setFillColor(pts[i].color);
      canvas.roundedTopRect(bx, by, barW, bh, topRadius);
      canvas.fill();
      if (showValues) {
        pwPaintParagraph(
          context,
          _chartValue(pts[i].value),
          PwOffset(x + i * slot, by - 10),
          slot,
          const TextStyle(fontSize: 6, color: '37474F'),
          TextAlign.center,
        );
      }
      pwPaintParagraph(
        context,
        _chartAxisLabel(pts[i].label, slot),
        PwOffset(x + i * slot, y + h - 12),
        slot,
        const TextStyle(fontSize: 6.5, color: '546E7A'),
        TextAlign.center,
      );
    }
  }

  void _line(
    Context context,
    PdfCanvas canvas,
    List<ChartPoint> pts,
    double maxV,
    double x,
    double y,
    double w,
    double h,
  ) {
    if (showGrid) {
      _grid(canvas, x, y, w, h, maxV);
      _yLabels(context, x, y, h, maxV);
    }
    canvas.setStrokeColor('1A237E');
    canvas.setLineWidth(1.4);
    for (int i = 0; i < pts.length; i++) {
      final double px = x + (pts.length == 1 ? w / 2 : w * i / (pts.length - 1));
      final double py = y + (h - 14) * (1 - pts[i].value / maxV);
      if (i == 0) {
        canvas.moveTo(px, py);
      } else {
        canvas.lineTo(px, py);
      }
    }
    canvas.stroke();
    for (int i = 0; i < pts.length; i++) {
      final double px = x + (pts.length == 1 ? w / 2 : w * i / (pts.length - 1));
      final double py = y + (h - 14) * (1 - pts[i].value / maxV);
      canvas.setFillColor(pts[i].color);
      canvas.ellipse(px - 2.5, py - 2.5, 5, 5);
      canvas.fill();
      if (showValues) {
        pwPaintParagraph(
          context,
          _chartValue(pts[i].value),
          PwOffset(px - 16, py - 12),
          32,
          const TextStyle(fontSize: 6, color: '37474F'),
          TextAlign.center,
        );
      }
      final double labelW = pts.length <= 1 ? w : w / (pts.length - 1);
      pwPaintParagraph(
        context,
        _chartAxisLabel(pts[i].label, labelW),
        PwOffset(px - labelW / 2, y + h - 12),
        labelW,
        const TextStyle(fontSize: 6.5, color: '546E7A'),
        TextAlign.center,
      );
    }
  }

  void _pie(
    Context context,
    PdfCanvas canvas,
    List<ChartPoint> pts,
    double x,
    double y,
    double w,
    double h,
  ) {
    var sum = 0.0;
    for (final ChartPoint p in pts) {
      sum += p.value.abs();
    }
    if (sum <= 0) {
      sum = 1;
    }
    final double cx = x + w * (showLegend ? 0.36 : 0.5);
    final double cy = y + h / 2;
    final double r = math.min(w, h) * 0.32;
    var angle = -90.0;
    for (final ChartPoint p in pts) {
      final double sweep = 360 * p.value.abs() / sum;
      canvas.setFillColor(p.color);
      canvas.moveTo(cx, cy);
      final int steps = math.max(8, (sweep.abs() / 5).round());
      for (int i = 0; i <= steps; i++) {
        final double a = (angle + sweep * i / steps) * math.pi / 180;
        canvas.lineTo(cx + r * math.cos(a), cy + r * math.sin(a));
      }
      canvas.closePath();
      canvas.fill();
      if (showValues && sweep > 18) {
        final double mid = (angle + sweep / 2) * math.pi / 180;
        final double lx = cx + r * 0.62 * math.cos(mid);
        final double ly = cy + r * 0.62 * math.sin(mid);
        pwPaintParagraph(
          context,
          '${(100 * p.value.abs() / sum).round()}%',
          PwOffset(lx - 12, ly - 4),
          24,
          const TextStyle(fontSize: 6, color: 'FFFFFF'),
          TextAlign.center,
        );
      }
      angle += sweep;
    }
    if (!showLegend) {
      return;
    }
    var ly = y + 8;
    for (final ChartPoint p in pts) {
      canvas.fillRect(x + w * 0.72, ly, 8, 8, p.color);
      pwPaintParagraph(
        context,
        '${p.label}  ${_chartValue(p.value)}',
        PwOffset(x + w * 0.72 + 12, ly),
        w * 0.26,
        const TextStyle(fontSize: 8, color: '37474F'),
        TextAlign.left,
      );
      ly += 14;
    }
  }

  void _legendRow(
    Context context,
    PdfCanvas canvas,
    List<ChartPoint> pts,
    double x,
    double y,
    double w,
  ) {
    final double slot = w / pts.length;
    for (int i = 0; i < pts.length; i++) {
      canvas.fillRect(x + i * slot, y, 7, 7, pts[i].color);
      pwPaintParagraph(
        context,
        pts[i].label,
        PwOffset(x + i * slot + 10, y - 1),
        (slot - 12).clamp(8, slot),
        const TextStyle(fontSize: 7, color: '546E7A'),
        TextAlign.left,
      );
    }
  }
}

/// Tappable URI or internal destination over [child].
class Link extends Widget {
  /// Link API.
  const Link({
    required this.child,
    this.destination,
    this.destPage,
  });

  /// child API.
  final Widget child;

  /// Named anchor (see [Anchor]).
  final String? destination;

  /// 0-based page index.
  final int? destPage;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final PwBox box = child.layout(context, constraints);
    return _LinkBox(box.size, box, destPage: destPage, destination: destination);
  }
}

/// URI annotation over [child].
class UrlLink extends Widget {
  /// UrlLink API.
  const UrlLink({required this.child, required this.destination});

  /// child API.
  final Widget child;

  /// destination API.
  final String destination;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final PwBox box = child.layout(context, constraints);
    return _LinkBox(box.size, box, uri: destination);
  }
}

class _LinkBox extends PwBox {
  _LinkBox(
    super.size,
    this.child, {
    this.uri,
    this.destPage,
    this.destination,
  });

  final PwBox child;
  final String? uri;
  final int? destPage;
  final String? destination;

  @override
  void paint(Context context, PwOffset offset) {
    child.paint(context, offset);
    int? page = destPage;
    double? destY;
    final String? name = destination;
    if (page == null && name != null) {
      final PwHeading? hit =
          context.headingNamed(name) ?? context.anchors[name];
      if (hit != null) {
        page = hit.pageNumber - 1;
        destY = hit.destY;
      }
    }
    context.links.add(
      PdfLinkAnnot(
        x: offset.dx,
        y: offset.dy,
        width: size.width,
        height: size.height,
        uri: uri,
        destPage: page,
        destY: destY,
      ),
    );
  }

  @override
  void noteDestination(Context context, PwOffset offset) {
    child.noteDestination(context, offset);
  }
}

/// Diagonal document stamp, extracted by [MultiPage].
class Watermark extends Widget with PwPageOverlay {
  /// Watermark API.
  const Watermark({required this.child});

  /// text API.
  Watermark.text(String text, {TextStyle? style})
    : child = Text(
        text,
        style:
            style ??
            const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: 'E0E0E0',
            ),
      );

  /// child API.
  final Widget child;

  @override
  Widget get overlayChild => child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return child.layout(context, constraints);
  }
}

/// Two-pass TOC from [Header] entries.
class TableOfContent extends Widget {
  /// TableOfContent API.
  const TableOfContent({
    this.title = 'Table of Contents',
    this.minLevel = 1,
    this.maxLevel = 3,
    this.showPageNumbers = true,
  });

  /// title API.
  final String title;

  /// minLevel API.
  final int minLevel;

  /// maxLevel API.
  final int maxLevel;

  /// showPageNumbers API.
  final bool showPageNumbers;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final List<PwHeading> source = context.frozenHeadings.isNotEmpty
        ? context.frozenHeadings
        : context.headings;
    final List<Widget> rows = <Widget>[
      Header(level: 1, text: title, title: title),
      const SizedBox(height: 6),
    ];
    for (final PwHeading heading in source) {
      if (heading.level < minLevel || heading.level > maxLevel) {
        continue;
      }
      if (heading.title == title) {
        continue;
      }
      final double indent = (heading.level - minLevel) * 14.0;
      final bool rtl = context.textDirection == TextDirection.rtl;
      final TextStyle linkStyle = TextStyle(
        fontSize: heading.level == 1 ? 11 : 10,
        color: '1565C0',
        decoration: TextDecoration.underline,
      );
      rows.add(
        Padding(
          padding: EdgeInsets.only(
            left: rtl ? 0 : indent,
            right: rtl ? indent : 0,
            bottom: 4,
          ),
          child: Link(
            destination: heading.title,
            child: Row(
              children: <Widget>[
                Expanded(child: Text(heading.title, style: linkStyle)),
                if (showPageNumbers)
                  Text(
                    '${heading.pageNumber}',
                    style: const TextStyle(fontSize: 10, color: '546E7A'),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows).layout(context, constraints);
  }
}

/// Bullet / numbered list of widgets.
class Bullet extends Widget {
  /// Bullet API.
  const Bullet({
    required this.text,
    this.style,
    this.bullet = '•',
  });

  /// text API.
  final String text;

  /// style API.
  final TextStyle? style;

  /// bullet API.
  final String bullet;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 14,
            child: Text(bullet, style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text(text, style: style, textAlign: TextAlign.start),
          ),
        ],
      ),
    ).layout(context, constraints);
  }
}
