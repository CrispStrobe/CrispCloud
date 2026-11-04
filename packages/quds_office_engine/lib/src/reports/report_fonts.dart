/// Font registry and text shaping for report layout and PDF output.
library;

import 'dart:typed_data';

import '../bidi/arabic_shaping.dart';
import '../bidi/line_breaker.dart';
import '../bidi/uax9_bidi.dart';
import '../fonts/font_metrics.dart';
import '../fonts/gpos_mark_to_base.dart';
import '../fonts/gsub_ligature.dart';
import '../fonts/sfnt_parser.dart';
import '../pdf/file/text/pdf_std14.dart';

/// Thrown when a font cannot be used for embedding.
class ReportFontException implements Exception {
  /// ReportFontException API.
  const ReportFontException(this.message);

  /// message API.
  final String message;

  @override
  String toString() => 'ReportFontException: $message';
}

/// Regular, bold, italic, and bold-italic faces of one family.
class ReportFontFamily {
  /// ReportFontFamily API.
  const ReportFontFamily({
    required this.name,
    required this.regular,
    this.bold,
    this.italic,
    this.boldItalic,
  });

  /// Family name as referenced by templates (`Cairo`).
  final String name;

  /// regular API.
  final SfntFont regular;

  /// Real bold face; when null bold text is synthesized.
  final SfntFont? bold;

  /// Real italic face; when null italic text is sheared.
  final SfntFont? italic;

  /// Real bold-italic face.
  final SfntFont? boldItalic;

  /// Face for [bold] and [italic] (falls back toward [regular]).
  SfntFont face({required bool bold, bool italic = false}) {
    if (bold && italic) {
      return boldItalic ?? this.italic ?? this.bold ?? regular;
    }
    if (italic) {
      return this.italic ?? regular;
    }
    return bold ? (this.bold ?? regular) : regular;
  }
}

/// Families available to the report engine.
///
/// Only TrueType (`glyf`) faces are accepted, because they are subset and
/// embedded into the PDF. When a glyph is missing from the requested family,
/// the other registered families are tried in registration order; when no
/// family covers it, Latin falls back to PDF Helvetica.
class ReportFontRegistry {
  /// ReportFontRegistry API.
  ReportFontRegistry();

  final List<ReportFontFamily> _families = <ReportFontFamily>[];

  /// Family used when a template names an unknown font.
  String? defaultFamily;

  /// Registered families in fallback order.
  List<ReportFontFamily> get families =>
      List<ReportFontFamily>.unmodifiable(_families);

  /// True when nothing is registered (Helvetica-only output).
  bool get isEmpty => _families.isEmpty;

  /// Registers parsed faces. Replaces an existing family of the same name.
  void register(
    String family, {
    required SfntFont regular,
    SfntFont? bold,
    SfntFont? italic,
    SfntFont? boldItalic,
  }) {
    void requireGlyf(SfntFont face, String slot) {
      if (!face.hasTable('glyf')) {
        throw ReportFontException(
          '$slot face of "$family" has no glyf table '
          '(CFF/OTF outlines cannot be embedded)',
        );
      }
    }

    requireGlyf(regular, 'Regular');
    if (bold != null) {
      requireGlyf(bold, 'Bold');
    }
    if (italic != null) {
      requireGlyf(italic, 'Italic');
    }
    if (boldItalic != null) {
      requireGlyf(boldItalic, 'Bold italic');
    }
    _families.removeWhere(
      (ReportFontFamily f) => f.name.toLowerCase() == family.toLowerCase(),
    );
    _families.add(
      ReportFontFamily(
        name: family,
        regular: regular,
        bold: bold,
        italic: italic,
        boldItalic: boldItalic,
      ),
    );
    defaultFamily ??= family;
  }

  /// Parses and registers TTF bytes.
  void registerBytes(
    String family,
    Uint8List regular, {
    Uint8List? bold,
    Uint8List? italic,
    Uint8List? boldItalic,
  }) {
    register(
      family,
      regular: SfntFont.parse(regular),
      bold: bold == null ? null : SfntFont.parse(bold),
      italic: italic == null ? null : SfntFont.parse(italic),
      boldItalic: boldItalic == null ? null : SfntFont.parse(boldItalic),
    );
  }

  /// Family by name (case-insensitive), else the default, else the first.
  ReportFontFamily? family(String? name) {
    if (_families.isEmpty) {
      return null;
    }
    if (name != null && name.isNotEmpty) {
      final String n = name.toLowerCase();
      for (final ReportFontFamily f in _families) {
        if (f.name.toLowerCase() == n) {
          return f;
        }
      }
    }
    final String? d = defaultFamily;
    if (d != null) {
      final String n = d.toLowerCase();
      for (final ReportFontFamily f in _families) {
        if (f.name.toLowerCase() == n) {
          return f;
        }
      }
    }
    return _families.first;
  }

  /// True when [name] is registered exactly.
  bool has(String name) => _families.any(
    (ReportFontFamily f) => f.name.toLowerCase() == name.toLowerCase(),
  );

  /// Face that draws [codePoint] for [family], or null for Helvetica.
  SfntFont? faceFor(
    String? family,
    int codePoint, {
    required bool bold,
    bool italic = false,
  }) {
    final ReportFontFamily? primary = this.family(family);
    if (primary == null) {
      return null;
    }
    final SfntFont first = primary.face(bold: bold, italic: italic);
    if (_covers(first, codePoint)) {
      return first;
    }
    for (final ReportFontFamily f in _families) {
      if (identical(f, primary)) {
        continue;
      }
      final SfntFont face = f.face(bold: bold, italic: italic);
      if (_covers(face, codePoint)) {
        return face;
      }
    }
    if (codePoint >= 0x20 && codePoint <= 0x7E) {
      return null;
    }
    return first;
  }

  static bool _covers(SfntFont face, int codePoint) {
    if (face.glyphIdFor(codePoint) != 0) {
      return true;
    }
    final int? nominal = ArabicShaper.nominalOf(codePoint);
    return nominal != null && face.glyphIdFor(nominal) != 0;
  }

  /// Every distinct face (for subsetting).
  Iterable<SfntFont> get allFaces sync* {
    for (final ReportFontFamily f in _families) {
      yield f.regular;
      if (f.bold != null) {
        yield f.bold!;
      }
      if (f.italic != null) {
        yield f.italic!;
      }
      if (f.boldItalic != null) {
        yield f.boldItalic!;
      }
    }
  }
}

/// Logical slice of the source text placed on one line.
class ReportTextLine {
  /// ReportTextLine API.
  const ReportTextLine({
    required this.text,
    required this.width,
    required this.broken,
  });

  /// Logical-order text of the line (feed to a BiDi-aware painter).
  final String text;

  /// Advance width, points.
  final double width;

  /// Visual-order shaped glyphs (used by the PDF writer).
  final BrokenLine broken;
}

/// Wrapped, shaped paragraph.
class ReportShapedText {
  /// ReportShapedText API.
  const ReportShapedText({
    required this.lines,
    required this.lineHeight,
    required this.ascent,
  });

  /// lines API.
  final List<ReportTextLine> lines;

  /// Distance between baselines, points.
  final double lineHeight;

  /// Top of line box to baseline, points.
  final double ascent;

  /// Total height.
  double get height => lines.length * lineHeight;

  /// Widest line.
  double get maxLineWidth {
    var w = 0.0;
    for (final ReportTextLine l in lines) {
      if (l.width > w) {
        w = l.width;
      }
    }
    return w;
  }
}

/// Text style resolved for shaping.
class ReportFontSpec {
  /// ReportFontSpec API.
  const ReportFontSpec({
    required this.family,
    required this.size,
    this.bold = false,
    this.italic = false,
  });

  /// Requested family (may be empty → registry default).
  final String family;

  /// Points.
  final double size;

  /// bold API.
  final bool bold;

  /// italic API.
  final bool italic;
}

/// Shapes and wraps text with the same metrics the PDF writer paints.
class ReportTextShaper {
  /// ReportTextShaper API.
  ReportTextShaper(this.fonts);

  /// fonts API.
  final ReportFontRegistry fonts;

  final Map<String, ReportShapedText> _cache = <String, ReportShapedText>{};

  /// Advance of [codePoint] in points.
  double advance(int codePoint, ReportFontSpec spec) {
    if (codePoint < 0x20 || Uax9Bidi.isInvisibleFormat(codePoint)) {
      return 0;
    }
    final SfntFont? face = fonts.faceFor(
      spec.family,
      codePoint,
      bold: spec.bold,
      italic: spec.italic,
    );
    if (face != null) {
      return FontMetrics(font: face, fontSizePoints: spec.size).characterWidth(
        face.glyphIdFor(codePoint) != 0
            ? codePoint
            : (ArabicShaper.nominalOf(codePoint) ?? codePoint),
      );
    }
    final int? byte = PdfStd14.winAnsiByte(codePoint);
    final int code = byte ?? 0x20;
    return PdfStd14.width('Helvetica', code) / 1000.0 * spec.size;
  }

  /// Line height for [spec] times [lineSpacing].
  double lineHeight(ReportFontSpec spec, {double lineSpacing = 1}) {
    final ReportFontFamily? fam = fonts.family(spec.family);
    if (fam != null) {
      return FontMetrics(
            font: fam.face(bold: spec.bold, italic: spec.italic),
            fontSizePoints: spec.size,
          ).lineHeight *
          lineSpacing;
    }
    return spec.size * 1.2 * lineSpacing;
  }

  /// Baseline offset from the top of a line box.
  double ascent(ReportFontSpec spec, {double lineSpacing = 1}) {
    final ReportFontFamily? fam = fonts.family(spec.family);
    final double base;
    if (fam != null) {
      base = FontMetrics(
        font: fam.face(bold: spec.bold, italic: spec.italic),
        fontSizePoints: spec.size,
      ).ascender;
    } else {
      base = spec.size * 0.95;
    }
    return base +
        (lineHeight(spec, lineSpacing: lineSpacing) - lineHeight(spec)) / 2;
  }

  /// Width of one unwrapped line.
  double measure(String text, ReportFontSpec spec) {
    var w = 0.0;
    for (final ReportShapedChar c in _shapedChars(text)) {
      w += advance(c.codePoint, spec) * c.advanceFactor;
    }
    return w;
  }

  /// Wraps [text] to [maxWidth] (no wrap when [wrap] is false).
  ReportShapedText shape(
    String text,
    ReportFontSpec spec, {
    required double maxWidth,
    required bool rtl,
    bool wrap = true,
    bool justify = false,
    double lineSpacing = 1,
  }) {
    final String key =
        '${spec.family}|${spec.size}|${spec.bold}|${spec.italic}|'
        '$rtl|$wrap|$justify|$lineSpacing|'
        '${maxWidth.toStringAsFixed(2)}|$text';
    final ReportShapedText? hit = _cache[key];
    if (hit != null) {
      return hit;
    }
    final double width = wrap ? (maxWidth < 1 ? 1 : maxWidth) : 1e9;
    final SfntFont? primary = fonts
        .family(spec.family)
        ?.face(bold: spec.bold, italic: spec.italic);
    final List<BrokenLine> broken = LineBreaker.breakLines(
      text: text,
      maxWidth: width,
      widthOf: (int cp) => advance(cp, spec),
      glyphIdOf: (int cp) =>
          fonts
              .faceFor(spec.family, cp, bold: spec.bold, italic: spec.italic)
              ?.glyphIdFor(cp) ??
          cp,
      markAttachOf: primary == null
          ? null
          : GposMarkToBase.fnFor(
              primary,
              spec.size,
              faceFor: (int cp) =>
                  fonts.faceFor(
                    spec.family,
                    cp,
                    bold: spec.bold,
                    italic: spec.italic,
                  ),
            ),
      baseLevel: rtl ? 1 : 0,
      justify: justify,
      ligate: primary == null
          ? null
          : (List<ShapedGlyph> glyphs) {
              final GsubLigatures gsub = GsubLigatures.of(primary);
              return gsub.isEmpty ? glyphs : gsub.rewrite(glyphs);
            },
    );
    final List<ReportTextLine> lines = <ReportTextLine>[
      for (final BrokenLine b in broken)
        ReportTextLine(
          text: _slice(text, b.logicalStart, b.logicalEnd),
          width: b.width,
          broken: b,
        ),
    ];
    final ReportShapedText shaped = ReportShapedText(
      lines: lines.isEmpty
          ? <ReportTextLine>[
              ReportTextLine(
                text: '',
                width: 0,
                broken: BrokenLine(
                  glyphs: const <ShapedGlyph>[],
                  width: 0,
                  logicalStart: 0,
                  logicalEnd: 0,
                  justificationRatio: 0,
                ),
              ),
            ]
          : lines,
      lineHeight: lineHeight(spec, lineSpacing: lineSpacing),
      ascent: ascent(spec, lineSpacing: lineSpacing),
    );
    if (_cache.length > 4000) {
      _cache.clear();
    }
    _cache[key] = shaped;
    return shaped;
  }

  static String _slice(String text, int start, int end) {
    final int s = start.clamp(0, text.length);
    final int e = end.clamp(s, text.length);
    return text.substring(s, e).replaceAll('\n', '').replaceAll('\r', '');
  }

  static Iterable<ReportShapedChar> _shapedChars(String text) sync* {
    for (final ShapedChar c in ArabicShaper.shape(text)) {
      yield ReportShapedChar(c.codePoint, c.advanceFactor);
    }
  }
}

/// Shaped code point with its advance multiplier (lam-alef ligatures).
class ReportShapedChar {
  /// ReportShapedChar API.
  const ReportShapedChar(this.codePoint, this.advanceFactor);

  /// codePoint API.
  final int codePoint;

  /// advanceFactor API.
  final double advanceFactor;
}
