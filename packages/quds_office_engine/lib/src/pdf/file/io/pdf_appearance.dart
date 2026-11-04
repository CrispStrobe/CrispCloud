import 'dart:convert';
import 'dart:typed_data';

import '../../../bidi/arabic_shaping.dart';
import '../../../bidi/line_breaker.dart';
import '../../../bidi/uax9_bidi.dart';
import '../../../fonts/font_metrics.dart';
import '../../../fonts/font_subsetter.dart';
import '../../../fonts/gpos_mark_to_base.dart';
import '../../../fonts/sfnt_parser.dart';
import '../../pdf_canvas.dart';
import '../../pdf_font.dart';
import '../../pdf_stream.dart';
import '../cos/pdf_cos.dart';
import '../cos/pdf_cos_write.dart';

/// One COS object body (no `n 0 obj` wrapper) for an appearance bundle.
class PdfAppearanceObj {
  /// PdfAppearanceObj API.
  const PdfAppearanceObj(this.id, this.body);

  /// Object number.
  final int id;

  /// Dictionary or stream body.
  final Uint8List body;
}

/// Form XObject plus optional Identity-H font objects for `/AP`.
class PdfAppearanceBundle {
  /// PdfAppearanceBundle API.
  const PdfAppearanceBundle({
    required this.formId,
    required this.objects,
    required this.nextId,
    this.needAppearances = false,
  });

  /// Form XObject object number (`/AP /N`).
  final int formId;

  /// Extra objects (font + form).
  final List<PdfAppearanceObj> objects;

  /// Next free object number after this bundle.
  final int nextId;

  /// True when the viewer should regenerate (`/NeedAppearances`).
  final bool needAppearances;
}

/// Builds annotation / field appearances with the engine BiDi path.
abstract final class PdfAppearance {
  /// Colored rect, plus shaped text when [font] covers the script.
  static PdfAppearanceBundle text({
    required int startId,
    required double width,
    required double height,
    required String text,
    required int colorArgb,
    SfntFont? font,
    double fontSize = 11,
    bool rtl = false,
  }) {
    final double w = width < 1 ? 1 : width;
    final double h = height < 1 ? 1 : height;
    if (text.isEmpty) {
      return _formOnly(startId, w, h, '${_pdfRgb(colorArgb)} 0 0 ${_n(w)} ${_n(h)} re f\n');
    }
    if (font != null) {
      final _ShapedAp? shaped = _shape(
        font,
        text,
        w,
        h,
        fontSize,
        rtl,
        colorArgb,
      );
      if (shaped != null) {
        return _identityForm(
          startId: startId,
          width: w,
          height: h,
          glyphs: shaped,
          font: font,
        );
      }
    }
    if (_winAnsiOnly(text)) {
      return _helveticaForm(
        startId: startId,
        width: w,
        height: h,
        colorArgb: colorArgb,
        text: text,
        fontSize: fontSize.clamp(6, h < 8 ? h : h - 2),
      );
    }
    return PdfAppearanceBundle(
      formId: startId,
      objects: <PdfAppearanceObj>[
        PdfAppearanceObj(
          startId,
          _formStream(
            w,
            h,
            '${_pdfRgb(colorArgb)} 0 0 ${_n(w)} ${_n(h)} re f\n',
          ),
        ),
      ],
      nextId: startId + 1,
      needAppearances: true,
    );
  }

  /// Checkbox / radio button mark (no embedded face).
  static PdfAppearanceBundle button({
    required int startId,
    required double width,
    required double height,
    required bool on,
    bool radio = false,
  }) {
    final double w = width < 1 ? 1 : width;
    final double h = height < 1 ? 1 : height;
    final StringBuffer ops = StringBuffer(
      '0.94 0.94 0.94 rg 0 0 ${_n(w)} ${_n(h)} re f\n',
    );
    ops.write('0.22 0.28 0.31 RG 0.9 w ');
    if (radio) {
      final double cx = w / 2;
      final double cy = h / 2;
      final double r = (w < h ? w : h) / 2 - 0.8;
      ops.write('${_ellipse(cx, cy, r)} S\n');
      if (on) {
        ops.write('0.11 0.37 0.13 rg ${_ellipse(cx, cy, r * 0.45)} f\n');
      }
    } else {
      ops.write('0.8 0.8 ${_n(w - 1.6)} ${_n(h - 1.6)} re S\n');
      if (on) {
        ops.write(
          '0.11 0.37 0.13 RG 1.4 w '
          '${_n(2)} ${_n(h * 0.45)} m ${_n(w * 0.4)} ${_n(2)} l '
          '${_n(w - 2)} ${_n(h - 2.5)} l S\n',
        );
      }
    }
    return _formOnly(startId, w, h, ops.toString());
  }

  static PdfAppearanceBundle _formOnly(
    int startId,
    double w,
    double h,
    String ops,
  ) {
    return PdfAppearanceBundle(
      formId: startId,
      objects: <PdfAppearanceObj>[
        PdfAppearanceObj(startId, _formStream(w, h, ops)),
      ],
      nextId: startId + 1,
    );
  }

  static PdfAppearanceBundle _helveticaForm({
    required int startId,
    required double width,
    required double height,
    required int colorArgb,
    required String text,
    required double fontSize,
  }) {
    final int fontId = startId;
    final int formId = startId + 1;
    final String escaped = text
        .replaceAll('\\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
    final String ops =
        '${_pdfRgb(colorArgb)} 0 0 ${_n(width)} ${_n(height)} re f\n'
        'BT /F2 ${_n(fontSize)} Tf 0 0 0 rg 1 0 0 -1 2 ${_n(height - 3)} Tm '
        '($escaped) Tj ET\n';
    return PdfAppearanceBundle(
      formId: formId,
      objects: <PdfAppearanceObj>[
        PdfAppearanceObj(
          fontId,
          utf8.encode(
            '<</Type /Font/Subtype /Type1/BaseFont /Helvetica>>',
          ),
        ),
        PdfAppearanceObj(
          formId,
          _formStream(width, height, ops, fontId: fontId, fontName: 'F2'),
        ),
      ],
      nextId: startId + 2,
    );
  }

  static PdfAppearanceBundle _identityForm({
    required int startId,
    required double width,
    required double height,
    required _ShapedAp glyphs,
    required SfntFont font,
  }) {
    final FontSubset subset = FontSubsetter(font).subset(glyphs.codePoints);
    final PdfCidFont cid = PdfCidFont.build(subset, font);
    final int fontId = startId;
    final int cidId = startId + 1;
    final int descId = startId + 2;
    final int fileId = startId + 3;
    final int toUnicodeId = startId + 4;
    final int formId = startId + 5;
    final PdfCanvas canvas = PdfCanvas(width, height);
    canvas.fillRect(0, 0, width, height, glyphs.fillHex);
    for (final _ApGlyph g in glyphs.glyphs) {
      final int newGid =
          subset.oldToNewGlyph[g.oldGid] ??
          subset.unicodeToNewGlyph[g.codePoint] ??
          0;
      if (newGid == 0 && g.codePoint > 32) {
        continue;
      }
      canvas.showGlyph(
        x: g.x,
        y: g.y,
        fontSize: g.size,
        glyphId: newGid,
        color: glyphs.inkHex,
      );
    }
    canvas.endText();
    final Uint8List compressed = PdfFlate.compress(cid.fontFile);
    return PdfAppearanceBundle(
      formId: formId,
      objects: <PdfAppearanceObj>[
        PdfAppearanceObj(
          fontId,
          utf8.encode(cid.type0Dict(cidId, toUnicodeId)),
        ),
        PdfAppearanceObj(cidId, utf8.encode(cid.cidFontDict(descId))),
        PdfAppearanceObj(descId, utf8.encode(cid.descriptorDict(fileId))),
        PdfAppearanceObj(
          fileId,
          PdfCosWrite.encode(
            PdfCosStream(
              PdfCosDict(<String, PdfCos>{
                'Length': PdfCosInt(compressed.length),
                'Filter': const PdfCosName('FlateDecode'),
                'Length1': PdfCosInt(cid.fontFile.length),
              }),
              compressed,
            ),
          ),
        ),
        PdfAppearanceObj(
          toUnicodeId,
          PdfCosWrite.encode(
            PdfCosStream(
              PdfCosDict(<String, PdfCos>{
                'Length': PdfCosInt(cid.toUnicodeCmap.length),
              }),
              Uint8List.fromList(utf8.encode(cid.toUnicodeCmap)),
            ),
          ),
        ),
        PdfAppearanceObj(
          formId,
          _formStream(
            width,
            height,
            utf8.decode(canvas.toStream()),
            fontId: fontId,
          ),
        ),
      ],
      nextId: startId + 6,
    );
  }

  static _ShapedAp? _shape(
    SfntFont font,
    String text,
    double width,
    double height,
    double fontSize,
    bool rtl,
    int colorArgb,
  ) {
    final double size = fontSize.clamp(6, height < 8 ? height : height - 2);
    final FontMetrics metrics = FontMetrics(font: font, fontSizePoints: size);
    final List<BrokenLine> lines = LineBreaker.breakLines(
      text: text,
      maxWidth: width - 4,
      widthOf: (int cp) => metrics.characterWidth(cp),
      glyphIdOf: (int cp) {
        final int gid = font.glyphIdFor(cp);
        if (gid != 0) {
          return gid;
        }
        final int? nom = ArabicShaper.nominalOf(cp);
        return nom == null ? 0 : font.glyphIdFor(nom);
      },
      markAttachOf: GposMarkToBase.fnFor(font, size),
      baseLevel: rtl ? 1 : null,
      justify: false,
    );
    if (lines.isEmpty || lines.first.glyphs.isEmpty) {
      return null;
    }
    final Set<int> cps = <int>{};
    final List<_ApGlyph> glyphs = <_ApGlyph>[];
    var y = 2.0;
    for (final BrokenLine line in lines) {
      if (y + size > height) {
        break;
      }
      final bool lineRtl =
          rtl || line.glyphs.any((ShapedGlyph g) => g.level.isOdd);
      var x = lineRtl ? width - 2 - line.width : 2.0;
      final double baseline = y + size * 0.8;
      for (final ShapedGlyph g in line.glyphs) {
        if (g.codePoint < 32 || Uax9Bidi.isInvisibleFormat(g.codePoint)) {
          x += g.advance;
          continue;
        }
        cps.add(g.codePoint);
        final int? nom = ArabicShaper.nominalOf(g.codePoint);
        if (nom != null) {
          cps.add(nom);
        }
        glyphs.add(
          _ApGlyph(
            codePoint: g.codePoint,
            oldGid: g.glyphId == 0 ? font.glyphIdFor(g.codePoint) : g.glyphId,
            x: x + g.paintDx,
            y: baseline - g.paintDy,
            size: size,
          ),
        );
        x += g.advance;
      }
      y += size * 1.2;
    }
    if (glyphs.isEmpty) {
      return null;
    }
    return _ShapedAp(
      glyphs: glyphs,
      codePoints: cps,
      fillHex: (colorArgb & 0xFFFFFF).toRadixString(16).padLeft(6, '0'),
      inkHex: _inkFor(colorArgb),
    );
  }

  static Uint8List _formStream(
    double w,
    double h,
    String ops, {
    int? fontId,
    String fontName = 'F1',
  }) {
    final Uint8List raw = Uint8List.fromList(utf8.encode(ops));
    final Map<String, PdfCos> res = <String, PdfCos>{};
    if (fontId != null) {
      res['Font'] = PdfCosDict(<String, PdfCos>{fontName: PdfCosRef(fontId)});
    }
    return PdfCosWrite.encode(
      PdfCosStream(
        PdfCosDict(<String, PdfCos>{
          'Type': const PdfCosName('XObject'),
          'Subtype': const PdfCosName('Form'),
          'BBox': PdfCosArray(<PdfCos>[
            const PdfCosReal(0),
            const PdfCosReal(0),
            PdfCosReal(w),
            PdfCosReal(h),
          ]),
          'Resources': PdfCosDict(res),
          'Length': PdfCosInt(raw.length),
        }),
        raw,
      ),
    );
  }

  static String _ellipse(double cx, double cy, double r) {
    final double k = 0.5522847498 * r;
    return '${_n(cx + r)} ${_n(cy)} m '
        '${_n(cx + r)} ${_n(cy + k)} ${_n(cx + k)} ${_n(cy + r)} ${_n(cx)} ${_n(cy + r)} c '
        '${_n(cx - k)} ${_n(cy + r)} ${_n(cx - r)} ${_n(cy + k)} ${_n(cx - r)} ${_n(cy)} c '
        '${_n(cx - r)} ${_n(cy - k)} ${_n(cx - k)} ${_n(cy - r)} ${_n(cx)} ${_n(cy - r)} c '
        '${_n(cx + k)} ${_n(cy - r)} ${_n(cx + r)} ${_n(cy - k)} ${_n(cx + r)} ${_n(cy)} c';
  }

  static bool _winAnsiOnly(String text) {
    for (final int cp in text.runes) {
      if (cp > 255) {
        return false;
      }
    }
    return true;
  }

  static String _inkFor(int argb) {
    final int r = (argb >> 16) & 0xFF;
    final int g = (argb >> 8) & 0xFF;
    final int b = argb & 0xFF;
    return (0.299 * r + 0.587 * g + 0.114 * b) < 140 ? 'FFFFFF' : '1A1A1A';
  }

  static String _pdfRgb(int argb) {
    final double r = ((argb >> 16) & 0xFF) / 255.0;
    final double g = ((argb >> 8) & 0xFF) / 255.0;
    final double b = (argb & 0xFF) / 255.0;
    return '${_n(r)} ${_n(g)} ${_n(b)} rg';
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(3);
}

class _ShapedAp {
  _ShapedAp({
    required this.glyphs,
    required this.codePoints,
    required this.fillHex,
    required this.inkHex,
  });

  final List<_ApGlyph> glyphs;
  final Set<int> codePoints;
  final String fillHex;
  final String inkHex;
}

class _ApGlyph {
  const _ApGlyph({
    required this.codePoint,
    required this.oldGid,
    required this.x,
    required this.y,
    required this.size,
  });

  final int codePoint;
  final int oldGid;
  final double x;
  final double y;
  final double size;
}
