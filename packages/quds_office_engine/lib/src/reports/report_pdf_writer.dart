/// Paints a [ReportDocumentLayout] into a PDF 1.7 file.
library;

import 'dart:collection';
import 'dart:typed_data';

import '../bidi/arabic_shaping.dart';
import '../bidi/line_breaker.dart';
import '../bidi/uax9_bidi.dart';
import '../fonts/font_subsetter.dart';
import '../fonts/sfnt_parser.dart';
import '../pdf/file/text/pdf_std14.dart';
import '../pdf/pdf_canvas.dart';
import '../pdf/pdf_document.dart';
import '../pdf/pdf_image.dart';
import '../pdf/pdf_save_options.dart';
import 'report_fonts.dart';
import 'report_layout.dart';
import 'report_template.dart';
import 'report_units.dart';

/// Writes report layouts with the writer-side [PdfDocument].
///
/// Every registered face that draws at least one glyph is subset and embedded
/// as a CID font (`F1`, `F3`, `F4`, …; `F2` stays Helvetica for the Latin
/// fallback). Families without a real bold face get synthesized bold.
class ReportPdfWriter {
  /// ReportPdfWriter API.
  const ReportPdfWriter({
    this.author = '',
    this.options = const PdfSaveOptions(),
  });

  /// `/Author`.
  final String author;

  /// PDF/A, tagging, and encryption options.
  final PdfSaveOptions options;

  /// Serializes [layout].
  Uint8List write(ReportDocumentLayout layout) {
    final ReportFontRegistry fonts = layout.fonts;
    final Map<SfntFont, Set<int>> used =
        LinkedHashMap<SfntFont, Set<int>>.identity();
    final Map<SfntFont, Set<int>> extraGlyphs =
        LinkedHashMap<SfntFont, Set<int>>.identity();
    for (final ReportPageLayout page in layout.pages) {
      for (final ReportPrimitive p in page.primitives) {
        if (p is! ReportTextPrimitive) {
          continue;
        }
        for (final ReportTextLine line in p.shaped.lines) {
          for (final ShapedGlyph glyph in line.broken.glyphs) {
            final int cp = glyph.codePoint;
            if (cp == 0 || Uax9Bidi.isInvisibleFormat(cp)) {
              continue;
            }
            final SfntFont? face = fonts.faceFor(
              p.font.family,
              cp,
              bold: p.font.bold,
              italic: p.font.italic,
            );
            if (face == null) {
              continue;
            }
            used.putIfAbsent(face, () => <int>{})
              ..add(cp)
              ..add(_drawable(face, cp));
            if (glyph.glyphId > 0) {
              extraGlyphs.putIfAbsent(face, () => <int>{}).add(glyph.glyphId);
            }
          }
        }
      }
    }
    final Map<SfntFont, PdfEmbeddedFace> embedded =
        LinkedHashMap<SfntFont, PdfEmbeddedFace>.identity();
    var nameIndex = 1;
    for (final MapEntry<SfntFont, Set<int>> e in used.entries) {
      final String name = 'F$nameIndex';
      nameIndex = nameIndex == 1 ? 3 : nameIndex + 1;
      embedded[e.key] = PdfEmbeddedFace(
        subset: FontSubsetter(e.key).subset(
          e.value,
          extraGlyphIds: extraGlyphs[e.key] ?? const <int>{},
        ),
        source: e.key,
        resourceName: name,
      );
    }
    final Set<SfntFont> realBold = Set<SfntFont>.identity();
    for (final ReportFontFamily f in fonts.families) {
      final SfntFont? b = f.bold;
      if (b != null) {
        realBold.add(b);
      }
    }

    final PdfDocument doc = PdfDocument(
      title: layout.template.name,
      author: author,
    );
    final Map<Uint8List, PdfRaster?> rasters =
        LinkedHashMap<Uint8List, PdfRaster?>.identity();
    for (final ReportPageLayout page in layout.pages) {
      final PdfCanvas canvas = PdfCanvas(layout.pageWidth, layout.pageHeight);
      final List<PdfEmbeddedImage> images = <PdfEmbeddedImage>[];
      final _PagePainter painter = _PagePainter(
        canvas: canvas,
        fonts: fonts,
        embedded: embedded,
        realBold: realBold,
        images: images,
        rasters: rasters,
      );
      final List<PdfLinkAnnot> links = <PdfLinkAnnot>[];
      for (final ReportPrimitive p in page.primitives) {
        painter.paint(p);
        if (p is ReportTextPrimitive) {
          final String? uri = p.link;
          if (uri != null && uri.isNotEmpty) {
            links.add(
              PdfLinkAnnot(
                x: p.bounds.left,
                y: p.bounds.top,
                width: p.bounds.width,
                height: p.bounds.height,
                uri: uri,
              ),
            );
          }
        }
      }
      canvas.endText();
      doc.addPage(
        PdfPage(
          width: layout.pageWidth,
          height: layout.pageHeight,
          content: canvas.toStream(),
          images: images,
          links: links,
        ),
      );
    }
    return doc.save(
      faces: embedded.values.toList(growable: false),
      options: options,
    );
  }

  static int _drawable(SfntFont face, int codePoint) {
    if (face.glyphIdFor(codePoint) != 0) {
      return codePoint;
    }
    final int? nominal = ArabicShaper.nominalOf(codePoint);
    if (nominal != null && face.glyphIdFor(nominal) != 0) {
      return nominal;
    }
    return codePoint;
  }
}

class _PagePainter {
  _PagePainter({
    required this.canvas,
    required this.fonts,
    required this.embedded,
    required this.realBold,
    required this.images,
    required this.rasters,
  });

  final PdfCanvas canvas;
  final ReportFontRegistry fonts;
  final Map<SfntFont, PdfEmbeddedFace> embedded;
  final Set<SfntFont> realBold;
  final List<PdfEmbeddedImage> images;
  final Map<Uint8List, PdfRaster?> rasters;

  void paint(ReportPrimitive p) {
    switch (p) {
      case ReportTextPrimitive():
        _text(p);
      case ReportRectPrimitive():
        _rect(p);
      case ReportLinePrimitive():
        _line(p);
      case ReportPathPrimitive():
        _polyline(p);
      case ReportImagePrimitive():
        _image(p);
      case ReportBarcodePrimitive():
        canvas.endText();
        final String hex = p.color.hex;
        for (final ReportRect r in p.darkRects) {
          canvas.fillRect(r.left, r.top, r.width, r.height, hex);
        }
    }
  }

  static bool _visible(ReportColor? c) => c != null && c.alpha > 0;

  void _dash(ReportLineStyle style, double width) {
    final double w = width < 0.5 ? 0.5 : width;
    switch (style) {
      case ReportLineStyle.solid:
        break;
      case ReportLineStyle.dashed:
        canvas.setDash(<double>[4 * w, 3 * w]);
      case ReportLineStyle.dotted:
        canvas.setDash(<double>[w, 2 * w]);
    }
  }

  void _path(ReportRectPrimitive p) {
    final ReportRect b = p.bounds;
    if (p.ellipse) {
      canvas.ellipse(b.left, b.top, b.width, b.height);
    } else if (p.radius > 0) {
      canvas.roundedRect(b.left, b.top, b.width, b.height, p.radius);
    } else {
      canvas.rect(b.left, b.top, b.width, b.height);
    }
  }

  void _rect(ReportRectPrimitive p) {
    final bool fill = _visible(p.fill);
    final bool stroke = _visible(p.stroke) && p.strokeWidth > 0;
    if (!fill && !stroke) {
      return;
    }
    canvas.endText();
    if (fill) {
      canvas.setFillColor(p.fill!.hex);
    }
    if (stroke) {
      canvas.setStrokeColor(p.stroke!.hex);
      canvas.setLineWidth(p.strokeWidth);
      _dash(p.lineStyle, p.strokeWidth);
    }
    _path(p);
    if (fill && stroke) {
      canvas.fillAndStroke();
    } else if (fill) {
      canvas.fill();
    } else {
      canvas.stroke();
    }
    if (stroke && p.lineStyle != ReportLineStyle.solid) {
      canvas.resetDash();
    }
  }

  void _line(ReportLinePrimitive p) {
    if (!_visible(p.color) || p.width <= 0) {
      return;
    }
    canvas.endText();
    canvas.setStrokeColor(p.color.hex);
    canvas.setLineWidth(p.width);
    _dash(p.lineStyle, p.width);
    canvas.moveTo(p.x1, p.y1);
    canvas.lineTo(p.x2, p.y2);
    canvas.stroke();
    if (p.lineStyle != ReportLineStyle.solid) {
      canvas.resetDash();
    }
  }

  void _polyline(ReportPathPrimitive p) {
    final bool fill = p.closed && _visible(p.fill);
    final bool stroke = _visible(p.stroke) && p.strokeWidth > 0;
    if ((!fill && !stroke) || p.length < 2) {
      return;
    }
    canvas.endText();
    if (fill) {
      canvas.setFillColor(p.fill!.hex);
    }
    if (stroke) {
      canvas.setStrokeColor(p.stroke!.hex);
      canvas.setLineWidth(p.strokeWidth);
      canvas.setLineJoin(1);
      _dash(p.lineStyle, p.strokeWidth);
    }
    final Float64List pts = p.points;
    canvas.moveTo(pts[0], pts[1]);
    for (int i = 2; i + 1 < pts.length; i += 2) {
      canvas.lineTo(pts[i], pts[i + 1]);
    }
    if (p.closed) {
      canvas.closePath();
    }
    if (fill && stroke) {
      canvas.fillAndStroke();
    } else if (fill) {
      canvas.fill();
    } else {
      canvas.stroke();
    }
    if (stroke) {
      canvas.setLineJoin(0);
      if (p.lineStyle != ReportLineStyle.solid) {
        canvas.resetDash();
      }
    }
  }

  void _image(ReportImagePrimitive p) {
    final PdfRaster? raster = rasters.putIfAbsent(
      p.bytes,
      () => PdfImageCodec.decode(p.bytes),
    );
    if (raster == null) {
      return;
    }
    final String name = 'Im${images.length + 1}';
    images.add(
      PdfEmbeddedImage(
        name: name,
        width: raster.width,
        height: raster.height,
        bytes: raster.jpegBytes ?? raster.rgb,
        jpeg: raster.isJpeg,
        maskBytes: raster.alpha,
      ),
    );
    final ReportRect r = p.imageRect;
    final ReportRect b = p.bounds;
    final bool sliced = p.cropTop > 0.001 || p.cropHeight < 0.999;
    final bool overflow =
        !sliced &&
        (r.left < b.left - 0.01 ||
            r.top < b.top - 0.01 ||
            r.right > b.right + 0.01 ||
            r.bottom > b.bottom + 0.01);
    if (sliced || overflow) {
      canvas.save();
      canvas.clipRect(b.left, b.top, b.width, b.height);
    }
    if (sliced && p.cropHeight > 0) {
      final double fullH = b.height / p.cropHeight;
      canvas.drawImage(name, b.left, b.top - fullH * p.cropTop, b.width, fullH);
    } else {
      canvas.drawImage(name, r.left, r.top, r.width, r.height);
    }
    if (sliced || overflow) {
      canvas.restore();
    }
  }

  void _text(ReportTextPrimitive p) {
    if (!_visible(p.color)) {
      return;
    }
    final ReportShapedText shaped = p.shaped;
    final ReportRect b = p.bounds;
    final double needed = shaped.height;
    final bool clip =
        needed > p.contentRect.height + 0.5 ||
        shaped.maxLineWidth > p.contentRect.width + 0.5;
    if (clip) {
      canvas.save();
      canvas.clipRect(b.left - 0.5, b.top - 0.5, b.width + 1, b.height + 1);
    }
    final String hex = p.color.hex;
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
        _glyph(
          p,
          cp,
          x + glyph.paintDx,
          baseline - glyph.paintDy,
          hex,
          glyphId: glyph.glyphId,
        );
        x += glyph.advance + extra;
      }
      if (p.underline && line.width > 0) {
        canvas.endText();
        canvas.setStrokeColor(hex);
        canvas.setLineWidth(size * 0.06);
        canvas.moveTo(startX, baseline + size * 0.12);
        canvas.lineTo(startX + line.width, baseline + size * 0.12);
        canvas.stroke();
      }
    }
    if (clip) {
      canvas.restore();
    }
  }

  void _glyph(
    ReportTextPrimitive p,
    int cp,
    double x,
    double baseline,
    String hex, {
    int glyphId = 0,
  }) {
    final SfntFont? face = fonts.faceFor(
      p.font.family,
      cp,
      bold: p.font.bold,
      italic: p.font.italic,
    );
    if (face != null) {
      final PdfEmbeddedFace? embed = embedded[face];
      if (embed == null) {
        return;
      }
      final int paintCp = ReportPdfWriter._drawable(face, cp);
      final int? fromGlyph = glyphId > 0
          ? embed.subset.oldToNewGlyph[glyphId]
          : null;
      final int gid =
          fromGlyph ??
          embed.subset.unicodeToNewGlyph[paintCp] ??
          embed.subset.unicodeToNewGlyph[cp] ??
          0;
      final ReportFontFamily? family = fonts.family(p.font.family);
      final SfntFont? realItalic = p.font.bold
          ? family?.boldItalic
          : family?.italic;
      canvas.showGlyph(
        x: x,
        y: baseline,
        fontSize: p.font.size,
        glyphId: gid,
        color: hex,
        italic: p.font.italic && !identical(face, realItalic),
        bold: p.font.bold && !realBold.contains(face),
        fontName: embed.resourceName,
      );
      return;
    }
    if (cp >= 0x20 && PdfStd14.winAnsiByte(cp) != null) {
      canvas.showLatin(
        x: x,
        y: baseline,
        fontSize: p.font.size,
        text: String.fromCharCode(cp),
        color: hex,
      );
    }
  }
}
