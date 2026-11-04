import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:quds_office_engine/pdf_file.dart';

import 'pdf_font_faces.dart';

/// Paints a [PdfDisplayList] in top-left page space.
abstract final class PaintPdfDisplayList {
  /// paint API.
  static void paint(
    Canvas canvas,
    PdfDisplayList list, {
    ui.Image? Function(Uint8List bytes, bool jpeg)? decodeImage,
  }) {
    for (final PdfPaintOp op in list.ops) {
      switch (op) {
        case PdfSaveGState():
          canvas.save();
        case PdfRestoreGState():
          canvas.restore();
        case PdfClipPath(:final List<PdfPathVerb> points, :final bool evenOdd):
          final Path clip = _path(points)
            ..fillType = evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
          canvas.clipPath(clip);
        case PdfFillPath(
          :final List<PdfPathVerb> points,
          :final int color,
          :final bool evenOdd,
          :final PdfBlendMode blend,
        ):
          final Path path = _path(points)
            ..fillType = evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
          canvas.drawPath(
            path,
            Paint()
              ..color = Color(color)
              ..style = PaintingStyle.fill
              ..blendMode = _blend(blend)
              ..isAntiAlias = true,
          );
        case PdfStrokePath(
          :final List<PdfPathVerb> points,
          :final int color,
          :final double width,
          :final int cap,
          :final int join,
          :final double miter,
          :final List<double> dash,
          :final double dashPhase,
          :final PdfBlendMode blend,
        ):
          Path strokePath = _path(points);
          if (dash.isNotEmpty) {
            strokePath = _dash(strokePath, dash, dashPhase);
          }
          canvas.drawPath(
            strokePath,
            Paint()
              ..color = Color(color)
              ..style = PaintingStyle.stroke
              ..strokeWidth = width <= 0 ? 1 : width
              ..strokeCap = cap == 1
                  ? StrokeCap.round
                  : cap == 2
                  ? StrokeCap.square
                  : StrokeCap.butt
              ..strokeJoin = join == 1
                  ? StrokeJoin.round
                  : join == 2
                  ? StrokeJoin.bevel
                  : StrokeJoin.miter
              ..strokeMiterLimit = miter <= 0 ? 4 : miter
              ..blendMode = _blend(blend),
          );
        case PdfDrawText(
          :final double x,
          :final double y,
          :final double size,
          :final int color,
          :final String text,
          :final bool italic,
          :final bool bold,
          :final String fontFamily,
          :final Uint8List? fontBytes,
          :final double angle,
        ):
          final bool rotated = angle.abs() > 0.01;
          final String host = PdfFontFaces.hostFamily(fontFamily);
          final String family = rotated
              ? host
              : PdfFontFaces.familyFor(fontBytes, fontFamily);
          // Embedded subsets already encode bold/italic; synthesizing again
          // fattens strokes past the PDF design.
          final FontWeight weight = PdfFontFaces.isEmbedded(family)
              ? FontWeight.w400
              : (bold ? FontWeight.w700 : FontWeight.w400);
          final FontStyle style = PdfFontFaces.isEmbedded(family)
              ? FontStyle.normal
              : (italic ? FontStyle.italic : FontStyle.normal);
          final TextPainter painter = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                inherit: false,
                color: Color(color),
                fontSize: size,
                fontFamily: family,
                // Embedded faces must not fall back mid-run: Liberation metrics
                // at PDF glyph origins create rivers / broken columns.
                fontFamilyFallback: PdfFontFaces.isEmbedded(family)
                    ? const <String>[]
                    : <String>[
                        host,
                        'Liberation Sans',
                        'DejaVu Sans',
                        'Noto Naskh Arabic',
                      ],
                fontWeight: weight,
                fontStyle: style,
                height: 1,
                letterSpacing: 0,
              ),
            ),
            textDirection: rotated && _arabicScript(text)
                ? TextDirection.rtl
                : TextDirection.ltr,
            strutStyle: StrutStyle(
              fontSize: size,
              height: 1,
              forceStrutHeight: true,
              fontWeight: weight,
            ),
          )..layout();
          if (rotated) {
            canvas.save();
            canvas.translate(x, y);
            canvas.rotate(angle);
            painter.paint(canvas, Offset.zero);
            canvas.restore();
          } else {
            painter.paint(canvas, Offset(x, y));
          }
        case PdfDrawImage(
          :final double x,
          :final double y,
          :final double width,
          :final double height,
          :final Uint8List bytes,
          :final bool jpeg,
          :final bool placeholder,
          :final PdfBlendMode blend,
        ):
          final Rect rect = Rect.fromLTWH(x, y, width, height);
          final ui.Image? image = placeholder
              ? null
              : decodeImage?.call(bytes, jpeg);
          if (image != null) {
            canvas.drawImageRect(
              image,
              Rect.fromLTWH(
                0,
                0,
                image.width.toDouble(),
                image.height.toDouble(),
              ),
              rect,
              Paint()
                ..filterQuality = FilterQuality.high
                ..isAntiAlias = true
                ..blendMode = _blend(blend),
            );
          } else {
            canvas.drawRect(rect, Paint()..color = const Color(0xFFE0E4EA));
            canvas.drawRect(
              rect,
              Paint()
                ..color = const Color(0xFF7A8494)
                ..style = PaintingStyle.stroke,
            );
          }
      }
    }
  }

  static Path _path(List<PdfPathVerb> verbs) {
    final Path path = Path();
    for (final PdfPathVerb v in verbs) {
      switch (v.kind) {
        case PdfPathKind.move:
          path.moveTo(v.x, v.y);
        case PdfPathKind.line:
          path.lineTo(v.x, v.y);
        case PdfPathKind.cubic:
          path.cubicTo(v.x, v.y, v.x2, v.y2, v.x3, v.y3);
        case PdfPathKind.close:
          path.close();
        case PdfPathKind.rect:
          path.addRect(Rect.fromLTWH(v.x, v.y, v.x2, v.y2));
      }
    }
    return path;
  }

  static BlendMode _blend(PdfBlendMode mode) {
    return switch (mode) {
      PdfBlendMode.multiply => BlendMode.multiply,
      PdfBlendMode.screen => BlendMode.screen,
      PdfBlendMode.normal => BlendMode.srcOver,
    };
  }

  static Path _dash(Path source, List<double> dash, double phase) {
    // PDF [0 gap] + round cap = dots; keep a hairline on-run so round caps
    // still paint (a literal 0-length extract yields nothing).
    if (dash.isEmpty) {
      return source;
    }
    final Path dest = Path();
    for (final ui.PathMetric metric in source.computeMetrics()) {
      var distance = -phase;
      var draw = true;
      var index = 0;
      while (distance < metric.length) {
        final double raw = dash[index % dash.length];
        final double len = raw <= 0 ? 0.01 : raw;
        final double start = distance.clamp(0, metric.length);
        final double end = (distance + len).clamp(0, metric.length);
        if (draw && end >= start) {
          dest.addPath(metric.extractPath(start, end), Offset.zero);
        }
        distance += len;
        draw = !draw;
        index++;
      }
    }
    return dest;
  }
}

bool _arabicScript(String text) {
  for (final int unit in text.runes) {
    if ((unit >= 0x0600 && unit <= 0x06FF) ||
        (unit >= 0x0750 && unit <= 0x077F) ||
        (unit >= 0x08A0 && unit <= 0x08FF) ||
        (unit >= 0xFB50 && unit <= 0xFDFF) ||
        (unit >= 0xFE70 && unit <= 0xFEFF)) {
      return true;
    }
  }
  return false;
}
