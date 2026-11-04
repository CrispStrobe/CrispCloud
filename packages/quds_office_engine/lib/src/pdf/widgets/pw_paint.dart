/// Measure, wrap, and paint helpers for PDF widgets.
library;

import '../../bidi/arabic_shaping.dart';
import '../../bidi/line_breaker.dart';
import '../../bidi/uax9_bidi.dart';
import '../../fonts/font_metrics.dart';
import '../../fonts/font_subsetter.dart';
import '../../fonts/gpos_mark_to_base.dart';
import '../../fonts/sfnt_parser.dart';
import '../../pdf/file/text/pdf_std14.dart';
import '../../pdf/pdf_canvas.dart';
import 'pw_core.dart';
import 'pw_style.dart';
import 'pw_types.dart';

/// Resolved size / color / weight for a run.
class PwResolvedStyle {
  /// PwResolvedStyle API.
  PwResolvedStyle(Context context, TextStyle? style)
    : merged = context.theme.defaultTextStyle.merge(style);

  /// merged API.
  final TextStyle merged;

  /// fontSize API.
  double get fontSize => merged.fontSize ?? 11;

  /// color API.
  String get color => merged.color ?? '212121';

  /// bold API.
  bool get bold => merged.fontWeight == FontWeight.bold;

  /// italic API.
  bool get italic => merged.fontStyle == FontStyle.italic;

  /// lineHeight API.
  double lineHeight(Context context) {
    final double factor = merged.lineHeightFactor;
    final face = context.faceFor(bold: bold);
    if (face != null) {
      return FontMetrics(font: face, fontSizePoints: fontSize).lineHeight *
          factor;
    }
    return fontSize * 1.2 * factor;
  }

  /// baseline API.
  double baseline(Context context) {
    final face = context.faceFor(bold: bold);
    if (face != null) {
      return FontMetrics(font: face, fontSizePoints: fontSize).ascender;
    }
    // Std14 fallback: keep the full em above the baseline.
    return fontSize;
  }
}

/// Width of [text] in points.
double pwMeasureText(Context context, String text, TextStyle? style) {
  final PwResolvedStyle resolved = PwResolvedStyle(context, style);
  context.useText(text);
  _recordShaped(context, text, resolved.bold);
  if (context.faceFor(bold: resolved.bold) != null) {
    final face = context.faceFor(bold: resolved.bold)!;
    double width = FontMetrics(
      font: face,
      fontSizePoints: resolved.fontSize,
    ).measureText(text);
    final double tracking = resolved.merged.letterSpacing ?? 0;
    if (tracking != 0 && text.isNotEmpty) {
      final int gaps = text.runes.where((int cp) => !_cursiveArabic(cp)).length;
      if (gaps > 1) {
        width += tracking * (gaps - 1);
      }
    }
    return width;
  }
  double width = 0;
  var i = 0;
  for (final int cp in text.runes) {
    if (i > 0) {
      width += resolved.merged.letterSpacing ?? 0;
    }
    width += _stdAdvance(cp, resolved.fontSize);
    i++;
  }
  return width;
}

/// UAX wrap of [text] to [maxWidth].
List<BrokenLine> pwWrapText(
  Context context,
  String text,
  double maxWidth,
  TextStyle? style, {
  TextAlign align = TextAlign.start,
}) {
  final PwResolvedStyle resolved = PwResolvedStyle(context, style);
  context.useText(text);
  _recordShaped(context, text, resolved.bold);
  final double tracking = resolved.merged.letterSpacing ?? 0;
  final face = context.faceFor(bold: resolved.bold);
  final int units = text.runes.where((int cp) => !_cursiveArabic(cp)).length;
  final double perGlyphTrack = units > 1 ? tracking * (units - 1) / units : 0;
  return LineBreaker.breakLines(
    text: text,
    maxWidth: maxWidth < 1 ? 1 : maxWidth,
    widthOf: (int cp) {
      final double track = _cursiveArabic(cp) ? 0 : perGlyphTrack;
      if (face != null) {
        return FontMetrics(
              font: face,
              fontSizePoints: resolved.fontSize,
            ).characterWidth(cp) +
            track;
      }
      return _stdAdvance(cp, resolved.fontSize) + track;
    },
    glyphIdOf: (int cp) => face?.glyphIdFor(cp) ?? cp,
    markAttachOf: face == null
        ? null
        : GposMarkToBase.fnFor(face, resolved.fontSize),
    baseLevel: context.textDirection == TextDirection.rtl ? 1 : 0,
    justify: align == TextAlign.justify,
  );
}

/// Paints one wrapped line. [origin] is the top-left of the line box.
void pwPaintLine(
  Context context,
  BrokenLine line,
  PwOffset origin,
  double maxWidth,
  TextStyle? style,
  TextAlign align,
) {
  final PdfCanvas? canvas = context.canvas;
  if (canvas == null) {
    return;
  }
  final PwResolvedStyle resolved = PwResolvedStyle(context, style);
  final double boxTop = origin.dy;
  final double baseline = boxTop + resolved.baseline(context);
  var startX = origin.dx;
  final double slack = (maxWidth - line.width).clamp(0, double.infinity);
  final bool rtl = context.textDirection == TextDirection.rtl;
  final TextAlign resolvedAlign = _resolvedAlign(align, rtl);
  if (resolvedAlign == TextAlign.right) {
    startX += slack;
  } else if (resolvedAlign == TextAlign.center) {
    startX += slack / 2;
  }
  var x = startX;
  for (final ShapedGlyph glyph in line.glyphs) {
    if (glyph.codePoint == 0 && glyph.advance == 0) {
      continue;
    }
    if (Uax9Bidi.isInvisibleFormat(glyph.codePoint)) {
      continue;
    }
    final double extra = glyph.isSpace && line.justificationRatio != 0
        ? line.justificationRatio * 3
        : 0;
    _paintGlyph(
      context,
      canvas,
      glyph.codePoint,
      x + glyph.paintDx,
      baseline - glyph.paintDy,
      resolved,
    );
    x += glyph.advance + extra;
  }
  final TextDecoration? deco = resolved.merged.decoration;
  if (deco != null && deco != TextDecoration.none && line.width > 0) {
    canvas.endText();
    canvas.setStrokeColor(resolved.color);
    canvas.setLineWidth(0.6);
    final double x0 = startX;
    final double x1 =
        startX + (maxWidth < line.width ? line.width : line.width);
    if (deco.contains(TextDecoration.underline)) {
      canvas.moveTo(x0, baseline + 1.4);
      canvas.lineTo(x1, baseline + 1.4);
      canvas.stroke();
    }
    if (deco.contains(TextDecoration.lineThrough)) {
      canvas.moveTo(x0, boxTop + resolved.lineHeight(context) * 0.55);
      canvas.lineTo(x1, boxTop + resolved.lineHeight(context) * 0.55);
      canvas.stroke();
    }
  }
}

/// One watermark line: a single text showing so the word rotates together.
void pwEmitStampLine(
  Context context,
  String text,
  TextStyle? style,
  double pageW,
  double pageH,
) {
  final PdfCanvas? canvas = context.canvas;
  if (canvas == null || text.isEmpty) {
    return;
  }
  final PwResolvedStyle resolved = PwResolvedStyle(context, style);
  context.useText(text);
  _recordShaped(context, text, resolved.bold);
  final List<BrokenLine> lines = pwWrapText(context, text, pageW * 0.9, style);
  if (lines.isEmpty || lines.first.glyphs.isEmpty) {
    return;
  }
  final BrokenLine line = lines.first;
  final double width = line.width < 1
      ? text.length * resolved.fontSize * 0.5
      : line.width;
  final double x = (pageW - width) / 2;
  final double y = pageH / 2;
  final SfntFont? face = context.faceFor(bold: resolved.bold);
  final ({FontSubset? subset, String fontName}) embed = context.embedFor(
    bold: resolved.bold,
  );
  final List<int> glyphIds = <int>[];
  if (face != null && embed.subset != null) {
    for (final ShapedGlyph glyph in line.glyphs) {
      final int paintCp = _drawableCodePoint(face, glyph.codePoint);
      glyphIds.add(
        embed.subset!.unicodeToNewGlyph[paintCp] ??
            embed.subset!.unicodeToNewGlyph[glyph.codePoint] ??
            0,
      );
    }
  }
  canvas.showMarkedLine(
    x: x,
    y: y,
    fontSize: resolved.fontSize,
    logical: text,
    color: resolved.color,
    fontName: face == null ? 'F2' : embed.fontName,
    glyphIds: glyphIds,
  );
}

/// Paints wrapped paragraphs; returns the height used.
double pwPaintParagraph(
  Context context,
  String text,
  PwOffset origin,
  double maxWidth,
  TextStyle? style,
  TextAlign align,
) {
  final PwResolvedStyle resolved = PwResolvedStyle(context, style);
  final double lh = resolved.lineHeight(context);
  final List<BrokenLine> lines = pwWrapText(
    context,
    text,
    maxWidth,
    style,
    align: align,
  );
  var y = origin.dy;
  for (final BrokenLine line in lines) {
    pwPaintLine(context, line, PwOffset(origin.dx, y), maxWidth, style, align);
    y += lh;
  }
  return y - origin.dy;
}

/// Drops lines past [maxLines] and, for [TextOverflow.ellipsis], marks the cut.
List<BrokenLine> pwApplyOverflow(
  Context context,
  List<BrokenLine> lines,
  double maxWidth,
  TextStyle? style, {
  required int? maxLines,
  required TextOverflow overflow,
  required bool softWrap,
}) {
  if (lines.isEmpty || overflow == TextOverflow.visible) {
    return lines;
  }
  final bool oneLineOverflow =
      overflow == TextOverflow.ellipsis &&
      !softWrap &&
      maxLines == null &&
      lines.first.width > maxWidth + 0.5;
  final int keep = oneLineOverflow
      ? 1
      : (maxLines == null ? lines.length : lines.length.clamp(0, maxLines));
  if (keep <= 0) {
    return const <BrokenLine>[];
  }
  final bool cut =
      overflow == TextOverflow.ellipsis &&
      (lines.length > keep || oneLineOverflow || lines[keep - 1].width > maxWidth + 0.5);
  final List<BrokenLine> kept = lines.length <= keep
      ? List<BrokenLine>.of(lines)
      : lines.sublist(0, keep);
  if (cut) {
    kept[keep - 1] = _ellipsizeLine(context, kept[keep - 1], maxWidth, style);
  }
  return kept;
}

BrokenLine _ellipsizeLine(
  Context context,
  BrokenLine line,
  double maxWidth,
  TextStyle? style,
) {
  final PwResolvedStyle resolved = PwResolvedStyle(context, style);
  final SfntFont? face = context.faceFor(bold: resolved.bold);
  final bool hasEllipsis = face != null && face.glyphIdFor(0x2026) != 0;
  final String mark = hasEllipsis ? '\u2026' : '...';
  context.useText(mark);
  final double markW = pwMeasureText(context, mark, style);
  final double budget = (maxWidth - markW).clamp(0, double.infinity);
  final bool rtl = context.textDirection == TextDirection.rtl;
  final List<ShapedGlyph> kept = List<ShapedGlyph>.of(line.glyphs);
  double width = 0;
  for (final ShapedGlyph glyph in kept) {
    width += glyph.advance;
  }
  while (kept.isNotEmpty && width > budget) {
    final ShapedGlyph gone = rtl ? kept.removeAt(0) : kept.removeLast();
    width -= gone.advance;
  }
  final int level = rtl ? 1 : 0;
  final List<ShapedGlyph> marks = <ShapedGlyph>[];
  if (hasEllipsis) {
    marks.add(
      ShapedGlyph(
        codePoint: 0x2026,
        glyphId: face.glyphIdFor(0x2026),
        advance: markW,
        logicalIndex: 0,
        level: level,
      ),
    );
  } else {
    final double dot = markW / 3;
    for (int i = 0; i < 3; i++) {
      marks.add(
        ShapedGlyph(
          codePoint: 0x2E,
          glyphId: face?.glyphIdFor(0x2E) ?? 0x2E,
          advance: dot,
          logicalIndex: i,
          level: level,
        ),
      );
    }
  }
  return BrokenLine(
    glyphs: rtl
        ? <ShapedGlyph>[...marks, ...kept]
        : <ShapedGlyph>[...kept, ...marks],
    width: width + markW,
    logicalStart: line.logicalStart,
    logicalEnd: line.logicalEnd,
    justificationRatio: 0,
  );
}

void _paintGlyph(
  Context context,
  PdfCanvas canvas,
  int codePoint,
  double x,
  double baseline,
  PwResolvedStyle style,
) {
  if (Uax9Bidi.isInvisibleFormat(codePoint)) {
    return;
  }
  final face = context.faceFor(bold: style.bold);
  if (face != null) {
    final ({FontSubset? subset, String fontName}) embed = context.embedFor(
      bold: style.bold,
    );
    final int paintCp = _drawableCodePoint(face, codePoint);
    final int gid = embed.subset != null
        ? (embed.subset!.unicodeToNewGlyph[paintCp] ??
              embed.subset!.unicodeToNewGlyph[codePoint] ??
              0)
        : face.glyphIdFor(paintCp);
    // Real bold face: never fake-stroke. Faux bold only without fontBold.
    final bool fauxBold = style.bold && context.document.fontBold == null;
    canvas.showGlyph(
      x: x,
      y: baseline,
      fontSize: style.fontSize,
      glyphId: gid,
      color: style.color,
      italic: style.italic,
      bold: fauxBold,
      fontName: embed.fontName,
    );
    return;
  }
  if (codePoint >= 32 && codePoint <= 126) {
    canvas.showLatin(
      x: x,
      y: baseline,
      fontSize: style.fontSize,
      text: String.fromCharCode(codePoint),
      color: style.color,
    );
  }
}

/// [TextAlign.start] / [TextAlign.end] resolved for [rtl].
TextAlign pwResolvedTextAlign(TextAlign align, bool rtl) =>
    _resolvedAlign(align, rtl);

TextAlign _resolvedAlign(TextAlign align, bool rtl) {
  return switch (align) {
    TextAlign.start => rtl ? TextAlign.right : TextAlign.left,
    TextAlign.end => rtl ? TextAlign.left : TextAlign.right,
    // Justify still packs the line; the origin edge must follow direction.
    TextAlign.justify => rtl ? TextAlign.right : TextAlign.left,
    _ => align,
  };
}

/// Record joining forms so the subset ToUnicode can paint them.
///
/// Measure only sees source letters. Without the presentation forms in the
/// subset, the viewer drops those glyphs and the letters that remain sit in
/// the holes.
void _recordShaped(Context context, String text, bool bold) {
  final SfntFont? face = context.faceFor(bold: bold);
  if (face == null || text.isEmpty) {
    return;
  }
  for (final ShapedChar shaped in ArabicShaper.shape(text)) {
    final int cp = _drawableCodePoint(face, shaped.codePoint);
    if (face.glyphIdFor(cp) != 0) {
      context.useText(String.fromCharCode(cp));
    }
  }
}

/// Presentation forms and Arabic letters must not take Latin tracking:
/// a gap between them breaks the join, so «ملاحظة» looks shattered.
bool _cursiveArabic(int cp) {
  return (cp >= 0x0600 && cp <= 0x06FF) ||
      (cp >= 0x0750 && cp <= 0x077F) ||
      (cp >= 0x08A0 && cp <= 0x08FF) ||
      (cp >= 0xFB50 && cp <= 0xFDFF) ||
      (cp >= 0xFE70 && cp <= 0xFEFF);
}

int _drawableCodePoint(SfntFont face, int codePoint) {
  if (face.glyphIdFor(codePoint) != 0) {
    return codePoint;
  }
  final int? nominal = ArabicShaper.nominalOf(codePoint);
  if (nominal != null && face.glyphIdFor(nominal) != 0) {
    return nominal;
  }
  return codePoint;
}

double _stdAdvance(int codePoint, double fontSize) {
  if (codePoint < 32 || Uax9Bidi.isInvisibleFormat(codePoint)) {
    return 0;
  }
  final int code = codePoint <= 255 ? codePoint : 32;
  return PdfStd14.width('Helvetica', code) / 1000.0 * fontSize;
}

/// Paints a [BoxDecoration] behind a child.
void pwPaintDecoration(
  Context context,
  PwOffset offset,
  PwSize size,
  BoxDecoration decoration,
) {
  final PdfCanvas? canvas = context.canvas;
  if (canvas == null) {
    return;
  }
  canvas.endText();
  if (decoration.shape == BoxShape.circle) {
    if (decoration.color != null) {
      canvas.setFillColor(decoration.color!);
      canvas.ellipse(offset.dx, offset.dy, size.width, size.height);
      canvas.fill();
    }
    final Border? border = decoration.border;
    if (border != null && border.top.width > 0) {
      canvas.setStrokeColor(border.top.color);
      canvas.setLineWidth(border.top.width);
      canvas.ellipse(offset.dx, offset.dy, size.width, size.height);
      canvas.stroke();
    }
    return;
  }
  if (decoration.color != null) {
    canvas.setFillColor(decoration.color!);
    if (decoration.borderRadius > 0.2) {
      canvas.roundedRect(
        offset.dx,
        offset.dy,
        size.width,
        size.height,
        decoration.borderRadius,
      );
      canvas.fill();
    } else {
      canvas.fillRect(
        offset.dx,
        offset.dy,
        size.width,
        size.height,
        decoration.color!,
      );
    }
  }
  final Border? border = decoration.border;
  if (border == null) {
    return;
  }
  final double strokeW = border.top.width;
  if (strokeW <= 0) {
    return;
  }
  canvas.setStrokeColor(border.top.color);
  canvas.setLineWidth(strokeW);
  // Follow the fill radius so KPI / card frames are not sharp rectangles
  // around a rounded background.
  if (decoration.borderRadius > 0.2) {
    canvas.roundedRect(
      offset.dx,
      offset.dy,
      size.width,
      size.height,
      decoration.borderRadius,
    );
    canvas.stroke();
    return;
  }
  void side(BorderSide s, double x1, double y1, double x2, double y2) {
    if (s.width <= 0) {
      return;
    }
    canvas.setStrokeColor(s.color);
    canvas.setLineWidth(s.width);
    canvas.moveTo(x1, y1);
    canvas.lineTo(x2, y2);
    canvas.stroke();
  }

  final double r = offset.dx + size.width;
  final double b = offset.dy + size.height;
  side(border.top, offset.dx, offset.dy, r, offset.dy);
  side(border.right, r, offset.dy, r, b);
  side(border.bottom, offset.dx, b, r, b);
  side(border.left, offset.dx, offset.dy, offset.dx, b);
}
