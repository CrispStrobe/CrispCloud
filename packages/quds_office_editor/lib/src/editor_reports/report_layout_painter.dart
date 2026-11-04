import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Paints [ReportDocumentLayout] pages on a Flutter canvas.
///
/// Text uses the TrueType outlines of the same faces the PDF writer embeds,
/// positioned from the engine's shaped lines, so the preview shows the
/// exported line breaks, joining, and mark placement exactly. Characters
/// without a registered face fall back to Liberation Sans (Helvetica
/// metrics), like the PDF's standard-14 fallback.
class ReportLayoutPainter {
  /// ReportLayoutPainter API.
  ReportLayoutPainter({this.onImageReady});

  /// Called when an image finished decoding (repaint).
  void Function()? onImageReady;

  final Map<SfntFont, Map<int, ui.Path>> _glyphs =
      <SfntFont, Map<int, ui.Path>>{};
  final Map<SfntFont, GlyphOutlineDecoder> _decoders =
      <SfntFont, GlyphOutlineDecoder>{};
  final Map<Uint8List, ui.Image> _images = <Uint8List, ui.Image>{};
  final Set<Uint8List> _pending = <Uint8List>{};
  final Set<Uint8List> _failed = <Uint8List>{};
  final Map<String, TextPainter> _fallback = <String, TextPainter>{};

  /// Paints [page] in page points (the caller sets the transform).
  void paintPage(
    Canvas canvas,
    ReportDocumentLayout doc,
    ReportPageLayout page,
  ) => paintPrimitives(canvas, doc.fonts, page.primitives);

  /// Paints [primitives] in page points with [fonts] for text.
  void paintPrimitives(
    Canvas canvas,
    ReportFontRegistry fonts,
    Iterable<ReportPrimitive> primitives,
  ) {
    for (final ReportPrimitive p in primitives) {
      switch (p) {
        case ReportRectPrimitive():
          _rect(canvas, p);
        case ReportLinePrimitive():
          _line(canvas, p);
        case ReportImagePrimitive():
          _image(canvas, p);
        case ReportBarcodePrimitive():
          final Paint paint = Paint()..color = Color(p.color.argb);
          for (final ReportRect r in p.darkRects) {
            canvas.drawRect(_r(r), paint);
          }
        case ReportPathPrimitive():
          _polyline(canvas, p);
        case ReportTextPrimitive():
          _text(canvas, fonts, p);
      }
    }
  }

  /// Decoded image for [bytes], or null while decoding / on failure.
  ui.Image? imageFor(Uint8List bytes) {
    final ui.Image? ready = _images[bytes];
    if (ready != null) {
      return ready;
    }
    if (_failed.contains(bytes) || !_pending.add(bytes)) {
      return null;
    }
    ui
        .instantiateImageCodec(bytes)
        .then((ui.Codec codec) => codec.getNextFrame())
        .then((ui.FrameInfo frame) {
          _pending.remove(bytes);
          _images[bytes] = frame.image;
          onImageReady?.call();
        })
        .catchError((Object _) {
          _pending.remove(bytes);
          _failed.add(bytes);
        });
    return null;
  }

  /// Releases decoded images.
  void dispose() {
    for (final ui.Image image in _images.values) {
      image.dispose();
    }
    _images.clear();
    for (final TextPainter tp in _fallback.values) {
      tp.dispose();
    }
    _fallback.clear();
  }

  static Rect _r(ReportRect r) =>
      Rect.fromLTWH(r.left, r.top, r.width, r.height);

  void _rect(Canvas canvas, ReportRectPrimitive p) {
    final Rect r = _r(p.bounds);
    final Path path = Path();
    if (p.ellipse) {
      path.addOval(r);
    } else if (p.radius > 0) {
      path.addRRect(RRect.fromRectAndRadius(r, Radius.circular(p.radius)));
    } else {
      path.addRect(r);
    }
    final ReportColor? fill = p.fill;
    if (fill != null && fill.alpha > 0) {
      canvas.drawPath(path, Paint()..color = Color(fill.argb));
    }
    final ReportColor? stroke = p.stroke;
    if (stroke != null && stroke.alpha > 0 && p.strokeWidth > 0) {
      canvas.drawPath(
        dashPath(path, p.lineStyle, p.strokeWidth),
        strokePaint(stroke, p.strokeWidth, p.lineStyle),
      );
    }
  }

  void _line(Canvas canvas, ReportLinePrimitive p) {
    if (p.color.alpha == 0 || p.width <= 0) {
      return;
    }
    final Path path = Path()
      ..moveTo(p.x1, p.y1)
      ..lineTo(p.x2, p.y2);
    canvas.drawPath(
      dashPath(path, p.lineStyle, p.width),
      strokePaint(p.color, p.width, p.lineStyle),
    );
  }

  void _polyline(Canvas canvas, ReportPathPrimitive p) {
    final Float64List pts = p.points;
    if (pts.length < 4) {
      return;
    }
    final Path path = Path()..moveTo(pts[0], pts[1]);
    for (int i = 2; i + 1 < pts.length; i += 2) {
      path.lineTo(pts[i], pts[i + 1]);
    }
    if (p.closed) {
      path.close();
    }
    final ReportColor? fill = p.fill;
    if (p.closed && fill != null && fill.alpha > 0) {
      canvas.drawPath(path, Paint()..color = Color(fill.argb));
    }
    final ReportColor? stroke = p.stroke;
    if (stroke != null && stroke.alpha > 0 && p.strokeWidth > 0) {
      canvas.drawPath(
        dashPath(path, p.lineStyle, p.strokeWidth),
        strokePaint(stroke, p.strokeWidth, p.lineStyle)
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  /// Stroke paint for [style].
  static Paint strokePaint(
    ReportColor color,
    double width,
    ReportLineStyle style,
  ) => Paint()
    ..color = Color(color.argb)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = style == ReportLineStyle.dotted
        ? StrokeCap.round
        : StrokeCap.butt;

  /// [source] cut into dashes for [style] (solid returns it unchanged).
  static Path dashPath(Path source, ReportLineStyle style, double width) {
    if (style == ReportLineStyle.solid) {
      return source;
    }
    final double w = width < 0.5 ? 0.5 : width;
    final double on = style == ReportLineStyle.dashed ? 3 * w : 0.01;
    final double off = 2 * w;
    final Path out = Path();
    for (final ui.PathMetric metric in source.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final double end = d + on > metric.length ? metric.length : d + on;
        out.addPath(metric.extractPath(d, end), Offset.zero);
        d = end + off;
      }
    }
    return out;
  }

  void _image(Canvas canvas, ReportImagePrimitive p) {
    final ui.Image? image = imageFor(p.bytes);
    if (image == null) {
      return;
    }
    final Rect bounds = _r(p.bounds);
    final Rect dst = _r(p.imageRect);
    final bool clip =
        dst.left < bounds.left - 0.5 ||
        dst.top < bounds.top - 0.5 ||
        dst.right > bounds.right + 0.5 ||
        dst.bottom > bounds.bottom + 0.5;
    if (clip) {
      canvas.save();
      canvas.clipRect(bounds);
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    if (clip) {
      canvas.restore();
    }
  }

  void _text(Canvas canvas, ReportFontRegistry fonts, ReportTextPrimitive p) {
    if (p.color.alpha == 0) {
      return;
    }
    final ReportShapedText shaped = p.shaped;
    final ReportRect b = p.bounds;
    final bool clip =
        shaped.height > p.contentRect.height + 0.5 ||
        shaped.maxLineWidth > p.contentRect.width + 0.5;
    if (clip) {
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(b.left - 0.5, b.top - 0.5, b.width + 1, b.height + 1),
      );
    }
    final Paint fill = Paint()..color = Color(p.color.argb);
    final double size = p.font.size;
    final double top0 = p.firstLineTop;
    for (int i = 0; i < shaped.lines.length; i++) {
      final ReportTextLine line = shaped.lines[i];
      final double baseline = top0 + i * shaped.lineHeight + shaped.ascent;
      final double startX = p.lineLeft(i);
      var x = startX;
      final BrokenLine broken = line.broken;
      for (final ShapedGlyph glyph in broken.glyphs) {
        final int cp = glyph.codePoint;
        if ((cp == 0 && glyph.advance == 0) || Uax9Bidi.isInvisibleFormat(cp)) {
          continue;
        }
        final double extra = glyph.isSpace && broken.justificationRatio != 0
            ? broken.justificationRatio * 3
            : 0;
        if (!glyph.isSpace) {
          _glyph(
            canvas,
            fonts,
            p.font,
            cp,
            x + glyph.paintDx,
            baseline - glyph.paintDy,
            fill,
          );
        }
        x += glyph.advance + extra;
      }
      if (p.underline && line.width > 0) {
        final double y = baseline + size * 0.12;
        canvas.drawLine(
          Offset(startX, y),
          Offset(startX + line.width, y),
          Paint()
            ..color = fill.color
            ..strokeWidth = size * 0.06,
        );
      }
    }
    if (clip) {
      canvas.restore();
    }
  }

  void _glyph(
    Canvas canvas,
    ReportFontRegistry fonts,
    ReportFontSpec font,
    int cp,
    double x,
    double baseline,
    Paint fill,
  ) {
    final SfntFont? face = fonts.faceFor(font.family, cp, bold: font.bold);
    if (face == null) {
      _fallbackGlyph(canvas, font, cp, x, baseline, fill.color);
      return;
    }
    var gid = face.glyphIdFor(cp);
    if (gid == 0) {
      final int? nominal = ArabicShaper.nominalOf(cp);
      if (nominal != null) {
        gid = face.glyphIdFor(nominal);
      }
    }
    if (gid == 0) {
      return;
    }
    final ui.Path? path = _path(face, gid);
    if (path == null) {
      return;
    }
    final double s = font.size / face.unitsPerEm;
    canvas.save();
    canvas.translate(x, baseline);
    canvas.scale(s, -s);
    if (font.italic) {
      canvas.skew(0.2, 0);
    }
    canvas.drawPath(path, fill);
    if (font.bold && !_isRealBold(fonts, face)) {
      canvas.drawPath(
        path,
        Paint()
          ..color = fill.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = face.unitsPerEm * 0.03,
      );
    }
    canvas.restore();
  }

  static bool _isRealBold(ReportFontRegistry fonts, SfntFont face) {
    for (final ReportFontFamily f in fonts.families) {
      if (identical(f.bold, face)) {
        return true;
      }
    }
    return false;
  }

  ui.Path? _path(SfntFont face, int gid) {
    final Map<int, ui.Path> cache = _glyphs.putIfAbsent(
      face,
      () => <int, ui.Path>{},
    );
    final ui.Path? hit = cache[gid];
    if (hit != null) {
      return hit;
    }
    final GlyphOutline outline = _decoders
        .putIfAbsent(face, () => GlyphOutlineDecoder(face))
        .decode(gid);
    if (outline.isEmpty) {
      return null;
    }
    final ui.Path path = ui.Path()..fillType = PathFillType.nonZero;
    for (final GlyphPathCommand c in outline.commands) {
      switch (c.op) {
        case GlyphPathOp.move:
          path.moveTo(c.x, c.y);
        case GlyphPathOp.line:
          path.lineTo(c.x, c.y);
        case GlyphPathOp.quad:
          path.quadraticBezierTo(c.cx, c.cy, c.x, c.y);
        case GlyphPathOp.close:
          path.close();
      }
    }
    cache[gid] = path;
    return path;
  }

  void _fallbackGlyph(
    Canvas canvas,
    ReportFontSpec font,
    int cp,
    double x,
    double baseline,
    Color color,
  ) {
    if (cp < 0x20) {
      return;
    }
    final String key =
        '$cp|${font.size}|${font.bold}|${font.italic}|'
        '${color.toARGB32()}';
    TextPainter? tp = _fallback[key];
    if (tp == null) {
      if (_fallback.length > 2000) {
        for (final TextPainter old in _fallback.values) {
          old.dispose();
        }
        _fallback.clear();
      }
      tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(cp),
          style: TextStyle(
            fontFamily: 'Liberation Sans',
            fontSize: font.size,
            fontWeight: font.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: font.italic ? FontStyle.italic : FontStyle.normal,
            color: color,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _fallback[key] = tp;
    }
    final double ascent = tp.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    tp.paint(canvas, Offset(x, baseline - ascent));
  }
}
