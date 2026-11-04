import 'dart:math' as math;
import 'dart:typed_data';

import '../../../fonts/sfnt_parser.dart';
import '../cos/pdf_cos.dart';
import '../cos/pdf_store.dart';
import '../decode/pdf_filters.dart';
import '../model/pdf_extra.dart';
import '../model/pdf_page_info.dart';
import '../text/pdf_cff_host.dart';
import '../text/pdf_std14.dart';
import '../text/pdf_tounicode.dart';
import 'pdf_display_list.dart';

/// Interprets a page content stream into a [PdfDisplayList].
class PdfInterpreter {
  /// PdfInterpreter API.
  PdfInterpreter(this.store, {this.maxFormDepth = 32, List<PdfLayer>? layers})
    : layers = layers ?? const <PdfLayer>[];

  /// store API.
  final PdfCosStore store;

  /// maxFormDepth API.
  final int maxFormDepth;

  /// Optional content groups from the catalog (visibility at interpret time).
  final List<PdfLayer> layers;

  /// interpret API.
  PdfDisplayList interpret({
    required PdfPageInfo page,
    required PdfCosDict pageDict,
    required List<PdfHotspot> hotspots,
  }) {
    final _Frame frame = _Frame(page, this);
    final PdfCosDict resources =
        store.asDict(pageDict['Resources']) ?? PdfCosDict();
    final Uint8List content = _pageContent(pageDict);
    _run(content, resources, frame, 0);
    _paintAnnotAppearances(pageDict, frame, 0);
    return PdfDisplayList(
      page: page,
      ops: frame.ops,
      runs: frame.runs,
      hotspots: hotspots,
    );
  }

  void _paintAnnotAppearances(
    PdfCosDict pageDict,
    _Frame frame,
    int depth,
  ) {
    final PdfCosArray? arr = store.asArray(pageDict['Annots']);
    if (arr == null) {
      return;
    }
    for (final PdfCos item in arr.items) {
      final PdfCosDict? dict = store.asDict(item);
      if (dict == null) {
        continue;
      }
      final PdfCosStream? form = _annotAppearance(dict);
      if (form == null) {
        continue;
      }
      final ({double llx, double lly, double urx, double ury})? rect =
          pdfCosRect(dict['Rect']);
      if (rect == null) {
        continue;
      }
      frame.save();
      frame.ops.add(const PdfSaveGState());
      frame.ctm.multiply(1, 0, 0, 1, rect.llx, rect.lly);
      final ({double llx, double lly, double urx, double ury})? box =
          pdfCosRect(form.dict['BBox']);
      if (box != null) {
        final double bw = (box.urx - box.llx).abs();
        final double bh = (box.ury - box.lly).abs();
        final double rw = (rect.urx - rect.llx).abs();
        final double rh = (rect.ury - rect.lly).abs();
        if (bw > 0.5 && bh > 0.5) {
          frame.ctm.multiply(rw / bw, 0, 0, rh / bh, 0, 0);
        }
        if (box.llx.abs() > 0.01 || box.lly.abs() > 0.01) {
          frame.ctm.multiply(1, 0, 0, 1, -box.llx, -box.lly);
        }
      }
      final PdfCosArray? matrix = store.asArray(form.dict['Matrix']);
      if (matrix != null && matrix.items.length >= 6) {
        frame.ctm.multiply(
          pdfCosNumber(matrix.items[0]) ?? 1,
          pdfCosNumber(matrix.items[1]) ?? 0,
          pdfCosNumber(matrix.items[2]) ?? 0,
          pdfCosNumber(matrix.items[3]) ?? 1,
          pdfCosNumber(matrix.items[4]) ?? 0,
          pdfCosNumber(matrix.items[5]) ?? 0,
        );
      }
      final PdfCosDict inner = store.asDict(form.dict['Resources']) ?? PdfCosDict();
      final Uint8List? bytes = store.streamBytes(form);
      if (bytes != null) {
        _run(bytes, inner, frame, depth + 1);
      }
      frame.ops.add(const PdfRestoreGState());
      frame.restore();
    }
  }

  PdfCosStream? _annotAppearance(PdfCosDict dict) {
    final PdfCosDict? ap = store.asDict(dict['AP']);
    if (ap == null) {
      return null;
    }
    final PdfCos? n = store.deref(ap['N']);
    if (n is PdfCosStream) {
      return n;
    }
    if (n is PdfCosDict) {
      final String state = pdfCosName(dict['AS']) ?? 'Off';
      final PdfCos? chosen = store.deref(n[state]) ??
          (n.values.isEmpty ? null : store.deref(n.values.values.first));
      if (chosen is PdfCosStream) {
        return chosen;
      }
    }
    return null;
  }

  Uint8List _pageContent(PdfCosDict pageDict) {
    final PdfCos? contents = pageDict['Contents'];
    if (contents is PdfCosArray) {
      final BytesBuilder out = BytesBuilder(copy: false);
      for (final PdfCos item in contents.items) {
        final Uint8List? part = store.streamBytes(item);
        if (part != null) {
          out.add(part);
          out.addByte(0x20);
        }
      }
      return out.takeBytes();
    }
    return store.streamBytes(contents) ?? Uint8List(0);
  }

  void _run(Uint8List data, PdfCosDict resources, _Frame frame, int depth) {
    if (depth > maxFormDepth) {
      return;
    }
    final List<Object> stack = <Object>[];
    final _Lexer lex = _Lexer(data);
    while (true) {
      final _Tok? tok = lex.next();
      if (tok == null) {
        break;
      }
      if (tok.op == 'BI') {
        _inlineImage(lex, resources, frame);
        stack.clear();
        continue;
      }
      if (tok.op != null) {
        _exec(tok.op!, stack, resources, frame, depth);
        stack.clear();
      } else if (tok.value != null) {
        stack.add(tok.value!);
      }
    }
  }

  void _exec(
    String op,
    List<Object> stack,
    PdfCosDict resources,
    _Frame frame,
    int depth,
  ) {
    switch (op) {
      case 'q':
        frame.save();
        frame.ops.add(const PdfSaveGState());
      case 'Q':
        frame.restore();
        frame.ops.add(const PdfRestoreGState());
      case 'cm':
        if (stack.length >= 6) {
          frame.ctm.multiply(
            _n(stack[stack.length - 6]),
            _n(stack[stack.length - 5]),
            _n(stack[stack.length - 4]),
            _n(stack[stack.length - 3]),
            _n(stack[stack.length - 2]),
            _n(stack[stack.length - 1]),
          );
        }
      case 'w':
        if (stack.isNotEmpty) {
          frame.lineWidth = _n(stack.last);
        }
      case 'J':
        if (stack.isNotEmpty) {
          frame.lineCap = _n(stack.last).round().clamp(0, 2);
        }
      case 'j':
        if (stack.isNotEmpty) {
          frame.lineJoin = _n(stack.last).round().clamp(0, 2);
        }
      case 'M':
        if (stack.isNotEmpty) {
          frame.miter = _n(stack.last);
        }
      case 'i':
        break;
      case 'd':
        if (stack.length >= 2 && stack[stack.length - 2] is List<Object>) {
          frame.dash = <double>[
            for (final Object item in stack[stack.length - 2] as List<Object>)
              _n(item),
          ];
          frame.dashPhase = _n(stack.last);
        }
      case 'ri':
      case 'cs':
      case 'CS':
        break;
      case 'sc':
      case 'SC':
      case 'scn':
      case 'SCN':
        final bool stroke = op == 'SC' || op == 'SCN';
        if (stack.length >= 4) {
          final int c = _cmyk(
            _n(stack[stack.length - 4]),
            _n(stack[stack.length - 3]),
            _n(stack[stack.length - 2]),
            _n(stack.last),
          );
          if (stroke) {
            frame.stroke = _keepAlpha(frame.stroke, c);
          } else {
            frame.fill = _keepAlpha(frame.fill, c);
          }
        } else if (stack.length >= 3) {
          final int c = _rgb(
            _n(stack[stack.length - 3]),
            _n(stack[stack.length - 2]),
            _n(stack.last),
          );
          if (stroke) {
            frame.stroke = _keepAlpha(frame.stroke, c);
          } else {
            frame.fill = _keepAlpha(frame.fill, c);
          }
        } else if (stack.isNotEmpty) {
          final double v = _n(stack.last);
          final int c = _rgb(v, v, v);
          if (stroke) {
            frame.stroke = _keepAlpha(frame.stroke, c);
          } else {
            frame.fill = _keepAlpha(frame.fill, c);
          }
        }
      case 'rg':
        if (stack.length >= 3) {
          frame.fill = _keepAlpha(
            frame.fill,
            _rgb(
              _n(stack[stack.length - 3]),
              _n(stack[stack.length - 2]),
              _n(stack[stack.length - 1]),
            ),
          );
        }
      case 'RG':
        if (stack.length >= 3) {
          frame.stroke = _keepAlpha(
            frame.stroke,
            _rgb(
              _n(stack[stack.length - 3]),
              _n(stack[stack.length - 2]),
              _n(stack[stack.length - 1]),
            ),
          );
        }
      case 'g':
        if (stack.isNotEmpty) {
          final double v = _n(stack.last);
          frame.fill = _keepAlpha(frame.fill, _rgb(v, v, v));
        }
      case 'G':
        if (stack.isNotEmpty) {
          final double v = _n(stack.last);
          frame.stroke = _keepAlpha(frame.stroke, _rgb(v, v, v));
        }
      case 'k':
        if (stack.length >= 4) {
          frame.fill = _keepAlpha(
            frame.fill,
            _cmyk(
              _n(stack[stack.length - 4]),
              _n(stack[stack.length - 3]),
              _n(stack[stack.length - 2]),
              _n(stack[stack.length - 1]),
            ),
          );
        }
      case 'K':
        if (stack.length >= 4) {
          frame.stroke = _keepAlpha(
            frame.stroke,
            _cmyk(
              _n(stack[stack.length - 4]),
              _n(stack[stack.length - 3]),
              _n(stack[stack.length - 2]),
              _n(stack[stack.length - 1]),
            ),
          );
        }
      case 'm':
        if (stack.length >= 2) {
          frame.path.add(
            PdfPathVerb(
              PdfPathKind.move,
              _n(stack[stack.length - 2]),
              _n(stack.last),
            ),
          );
        }
      case 'l':
        if (stack.length >= 2) {
          frame.path.add(
            PdfPathVerb(
              PdfPathKind.line,
              _n(stack[stack.length - 2]),
              _n(stack.last),
            ),
          );
        }
      case 'c':
        if (stack.length >= 6) {
          frame.path.add(
            PdfPathVerb(
              PdfPathKind.cubic,
              _n(stack[stack.length - 6]),
              _n(stack[stack.length - 5]),
              _n(stack[stack.length - 4]),
              _n(stack[stack.length - 3]),
              _n(stack[stack.length - 2]),
              _n(stack.last),
            ),
          );
        }
      case 'v':
        if (stack.length >= 4) {
          final (double cx, double cy) = frame.currentPoint;
          frame.path.add(
            PdfPathVerb(
              PdfPathKind.cubic,
              cx,
              cy,
              _n(stack[stack.length - 4]),
              _n(stack[stack.length - 3]),
              _n(stack[stack.length - 2]),
              _n(stack.last),
            ),
          );
        }
      case 'y':
        if (stack.length >= 4) {
          frame.path.add(
            PdfPathVerb(
              PdfPathKind.cubic,
              _n(stack[stack.length - 4]),
              _n(stack[stack.length - 3]),
              _n(stack[stack.length - 2]),
              _n(stack.last),
              _n(stack[stack.length - 2]),
              _n(stack.last),
            ),
          );
        }
      case 'gs':
        if (stack.isNotEmpty && stack.last is _Name) {
          frame.applyExtGState(store, resources, (stack.last as _Name).value);
        }
      case 'h':
        frame.path.add(const PdfPathVerb(PdfPathKind.close, 0, 0));
      case 're':
        if (stack.length >= 4) {
          frame.path.add(
            PdfPathVerb(
              PdfPathKind.rect,
              _n(stack[stack.length - 4]),
              _n(stack[stack.length - 3]),
              _n(stack[stack.length - 2]),
              _n(stack.last),
            ),
          );
        }
      case 'S':
        frame.emitStroke();
      case 's':
        frame.path.add(const PdfPathVerb(PdfPathKind.close, 0, 0));
        frame.emitStroke();
      case 'f':
      case 'F':
        frame.emitFill(false);
      case 'f*':
        frame.emitFill(true);
      case 'B':
        frame.emitFill(false, keepPath: true);
        frame.emitStroke();
      case 'B*':
        frame.emitFill(true, keepPath: true);
        frame.emitStroke();
      case 'b':
        frame.path.add(const PdfPathVerb(PdfPathKind.close, 0, 0));
        frame.emitFill(false, keepPath: true);
        frame.emitStroke();
      case 'b*':
        frame.path.add(const PdfPathVerb(PdfPathKind.close, 0, 0));
        frame.emitFill(true, keepPath: true);
        frame.emitStroke();
      case 'W':
        frame.clipPending = true;
        frame.clipEvenOdd = false;
      case 'W*':
        frame.clipPending = true;
        frame.clipEvenOdd = true;
      case 'n':
        frame.endPath();
      case 'BT':
        frame.textMatrix = _Matrix.identity();
        frame.textLine = _Matrix.identity();
      case 'ET':
        break;
      case 'Tm':
        if (stack.length >= 6) {
          frame.textMatrix = _Matrix(
            _n(stack[stack.length - 6]),
            _n(stack[stack.length - 5]),
            _n(stack[stack.length - 4]),
            _n(stack[stack.length - 3]),
            _n(stack[stack.length - 2]),
            _n(stack.last),
          );
          frame.textLine = frame.textMatrix.copy();
        }
      case 'Td':
        if (stack.length >= 2) {
          frame.td(_n(stack[stack.length - 2]), _n(stack.last));
        }
      case 'TD':
        if (stack.length >= 2) {
          frame.leading = -_n(stack.last);
          frame.td(_n(stack[stack.length - 2]), _n(stack.last));
        }
      case 'T*':
        frame.td(0, -frame.leading);
      case 'TL':
        if (stack.isNotEmpty) {
          frame.leading = _n(stack.last);
        }
      case 'Tc':
        if (stack.isNotEmpty) {
          frame.charSpace = _n(stack.last);
        }
      case 'Tw':
        if (stack.isNotEmpty) {
          frame.wordSpace = _n(stack.last);
        }
      case 'Tz':
        if (stack.isNotEmpty) {
          frame.horizScale = _n(stack.last) / 100.0;
        }
      case 'Ts':
        if (stack.isNotEmpty) {
          frame.rise = _n(stack.last);
        }
      case 'Tr':
        if (stack.isNotEmpty) {
          frame.textRender = _n(stack.last).round();
        }
      case 'Tf':
        if (stack.length >= 2) {
          frame.fontSize = _n(stack.last);
          final String name = stack[stack.length - 2] is _Name
              ? (stack[stack.length - 2] as _Name).value
              : '';
          frame.font = _loadFont(resources, name);
        }
      case 'Tj':
        if (stack.isNotEmpty) {
          frame.show(_text(stack.last));
        }
      case "'":
        frame.td(0, -frame.leading);
        if (stack.isNotEmpty) {
          frame.show(_text(stack.last));
        }
      case '"':
        if (stack.length >= 3) {
          frame.wordSpace = _n(stack[stack.length - 3]);
          frame.charSpace = _n(stack[stack.length - 2]);
          frame.td(0, -frame.leading);
          frame.show(_text(stack.last));
        }
      case 'TJ':
        if (stack.isNotEmpty && stack.last is List<Object>) {
          frame.showTj(stack.last as List<Object>);
        }
      case 'Do':
        if (stack.isNotEmpty && stack.last is _Name) {
          try {
            _doXObject((stack.last as _Name).value, resources, frame, depth);
          } catch (_) {
            break;
          }
        }
      case 'BMC':
      case 'BDC':
        frame.beginMarked(stack, resources);
      case 'EMC':
        frame.endMarked();
      case 'sh':
        if (stack.isNotEmpty && stack.last is _Name) {
          _doShading((stack.last as _Name).value, resources, frame);
        }
      default:
        break;
    }
  }

  void _doXObject(String name, PdfCosDict resources, _Frame frame, int depth) {
    final PdfCosDict? xos = store.asDict(resources['XObject']);
    final PdfCos? raw = xos == null ? null : store.deref(xos[name]);
    if (raw is! PdfCosStream) {
      return;
    }
    if (frame.hidden) {
      return;
    }
    final String subtype = pdfCosName(raw.dict['Subtype']) ?? '';
    if (subtype == 'Form') {
      final PdfCosDict inner = store.asDict(raw.dict['Resources']) ?? resources;
      final Uint8List? bytes = store.streamBytes(raw);
      if (bytes != null) {
        // Transparency-group forms are painted offscreen then composited with
        // the parent `/ca`. Capture that alpha before the form resets ExtGState.
        final bool isGroup = raw.dict['Group'] != null;
        final double groupOpacity = ((frame.fill >> 24) & 0xFF) / 255.0;
        final int opStart = frame.ops.length;
        frame.save();
        if (isGroup) {
          frame.fill = (frame.fill & 0x00FFFFFF) | 0xFF000000;
          frame.stroke = (frame.stroke & 0x00FFFFFF) | 0xFF000000;
        }
        frame.ops.add(const PdfSaveGState());
        final PdfCosArray? matrix = store.asArray(raw.dict['Matrix']);
        if (matrix != null && matrix.items.length >= 6) {
          frame.ctm.multiply(
            pdfCosNumber(matrix.items[0]) ?? 1,
            pdfCosNumber(matrix.items[1]) ?? 0,
            pdfCosNumber(matrix.items[2]) ?? 0,
            pdfCosNumber(matrix.items[3]) ?? 1,
            pdfCosNumber(matrix.items[4]) ?? 0,
            pdfCosNumber(matrix.items[5]) ?? 0,
          );
        }
        final ({double llx, double lly, double urx, double ury})? box =
            pdfCosRect(raw.dict['BBox']);
        if (box != null) {
          frame.path
            ..clear()
            ..add(
              PdfPathVerb(
                PdfPathKind.rect,
                box.llx,
                box.lly,
                box.urx - box.llx,
                box.ury - box.lly,
              ),
            );
          frame.clipEvenOdd = false;
          frame.emitClip();
          frame.path.clear();
        }
        _run(bytes, inner, frame, depth + 1);
        frame.ops.add(const PdfRestoreGState());
        frame.restore();
        if (isGroup && groupOpacity < 0.999) {
          _scaleOpsOpacity(frame.ops, opStart, groupOpacity);
        }
      }
      return;
    }
    if (subtype != 'Image') {
      return;
    }
    if (frame.hidden) {
      return;
    }
    final double w = pdfCosNumber(raw.dict['Width']) ?? 1;
    final double h = pdfCosNumber(raw.dict['Height']) ?? 1;
    final (double x, double y) = frame.map(0, 0);
    final (double x1, double y1) = frame.map(1, 1);
    final PdfFilterResult decoded = store.streamResult(raw);
    final bool jpeg = _isJpeg(raw.dict);
    var pixels = decoded.bytes ?? Uint8List(0);
    final int pw = w.round();
    final int ph = h.round();
    final bool imageMask =
        _flag(raw.dict['ImageMask']) || _flag(raw.dict['IM']);
    final int bpc =
        pdfCosInt(raw.dict['BitsPerComponent']) ?? (imageMask ? 1 : 8);
    final bool invert = _decodeInverts(raw.dict);
    var hasAlpha = false;
    if (imageMask && !jpeg) {
      pixels = _stencilRgba(pixels, pw, ph, bpc, frame.fill, invert);
      hasAlpha = true;
    } else if (!jpeg && pixels.isNotEmpty) {
      final Uint8List? palette = _indexedPalette(raw.dict);
      if (palette != null) {
        pixels = _expandIndexed(pixels, pw, ph, bpc, palette);
      } else {
        final int n = _colorComponents(raw.dict);
        final bool gray = n == 1 || _isCcitt(raw.dict);
        if (gray) {
          final int bits = pixels.length == pw * ph ? 8 : bpc;
          pixels = _expandGray(pixels, pw, ph, bits, invert: invert);
        } else if (n == 4 && pixels.length == pw * ph * 4) {
          pixels = _cmykToRgb(pixels, pw, ph);
        }
      }
    }
    if (!jpeg && !imageMask && pixels.length == pw * ph * 3) {
      final Uint8List? mask = _smaskGray(raw.dict, pw, ph);
      if (mask != null) {
        pixels = _composeSMask(pixels, mask, pw, ph);
        hasAlpha = true;
      }
    }
    final double ca = ((frame.fill >> 24) & 0xFF) / 255.0;
    if (!jpeg && ca < 0.999 && pixels.isNotEmpty) {
      final PdfDrawImage probe = PdfDrawImage(
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        bytes: pixels,
        jpeg: false,
        placeholder: false,
        pixelWidth: pw,
        pixelHeight: ph,
        hasAlpha: hasAlpha,
      );
      pixels = _mulImageOpacity(probe, ca);
      hasAlpha = true;
    }
    final Uint8List? softMaskJpeg = jpeg ? _smaskJpegBytes(raw.dict) : null;
    frame.ops.add(
      PdfDrawImage(
        x: math.min(x, x1),
        y: math.min(y, y1),
        width: (x1 - x).abs().clamp(1, 100000),
        height: (y1 - y).abs().clamp(1, 100000),
        bytes: pixels,
        jpeg: jpeg,
        placeholder: decoded.bytes == null || w < 1 || h < 1,
        pixelWidth: pw,
        pixelHeight: ph,
        hasAlpha: hasAlpha || softMaskJpeg != null,
        softMaskJpeg: softMaskJpeg,
        blend: frame.blend,
      ),
    );
  }

  bool _isJpeg(PdfCosDict dict) {
    final List<String> names = <String>[];
    final PdfCos? filter = dict['Filter'];
    if (filter is PdfCosName) {
      names.add(filter.value);
    } else if (filter is PdfCosArray) {
      for (final PdfCos item in filter.items) {
        if (item is PdfCosName) {
          names.add(item.value);
        }
      }
    }
    return names.contains('DCTDecode') || names.contains('DCT');
  }

  bool _isCcitt(PdfCosDict dict) {
    final PdfCos? filter = dict['Filter'];
    if (filter is PdfCosName) {
      return filter.value == 'CCITTFaxDecode' || filter.value == 'CCF';
    }
    if (filter is PdfCosArray) {
      for (final PdfCos item in filter.items) {
        if (item is PdfCosName &&
            (item.value == 'CCITTFaxDecode' || item.value == 'CCF')) {
          return true;
        }
      }
    }
    return false;
  }

  /// DeviceN / ICCBased `/N` without applying an ICC profile.
  int _colorComponents(PdfCosDict dict) {
    final PdfCos? cs = store.deref(dict['ColorSpace']);
    if (cs is PdfCosName) {
      switch (cs.value) {
        case 'DeviceGray' || 'G':
          return 1;
        case 'DeviceCMYK' || 'CMYK':
          return 4;
        default:
          return 3;
      }
    }
    if (cs is PdfCosArray && cs.items.isNotEmpty) {
      final String name = pdfCosName(cs.items.first) ?? '';
      if (name == 'ICCBased' && cs.items.length > 1) {
        final PdfCos? profile = store.deref(cs.items[1]);
        if (profile is PdfCosStream) {
          return pdfCosInt(profile.dict['N']) ?? 3;
        }
      }
      if (name == 'DeviceGray' ||
          name == 'G' ||
          name == 'Indexed' ||
          name == 'I') {
        return 1;
      }
      if (name == 'DeviceCMYK' || name == 'CMYK') {
        return 4;
      }
    }
    return 3;
  }

  static Uint8List _cmykToRgb(Uint8List cmyk, int w, int h) {
    final Uint8List out = Uint8List(w * h * 3);
    for (int i = 0; i < w * h; i++) {
      final double c = cmyk[i * 4] / 255.0;
      final double m = cmyk[i * 4 + 1] / 255.0;
      final double y = cmyk[i * 4 + 2] / 255.0;
      final double k = cmyk[i * 4 + 3] / 255.0;
      out[i * 3] = (((1 - c) * (1 - k)) * 255).round().clamp(0, 255);
      out[i * 3 + 1] = (((1 - m) * (1 - k)) * 255).round().clamp(0, 255);
      out[i * 3 + 2] = (((1 - y) * (1 - k)) * 255).round().clamp(0, 255);
    }
    return out;
  }

  Uint8List? _smaskJpegBytes(PdfCosDict image) {
    final PdfCos? raw = store.deref(image['SMask']);
    if (raw is! PdfCosStream || !_isJpeg(raw.dict)) {
      return null;
    }
    return store.streamResult(raw).bytes;
  }

  Uint8List? _smaskGray(PdfCosDict image, int w, int h) {
    final PdfCos? raw = store.deref(image['SMask']);
    if (raw is! PdfCosStream) {
      return null;
    }
    final PdfFilterResult decoded = store.streamResult(raw);
    final Uint8List? bytes = decoded.bytes;
    if (bytes == null) {
      return null;
    }
    final int mw = (pdfCosNumber(raw.dict['Width']) ?? w).round();
    final int mh = (pdfCosNumber(raw.dict['Height']) ?? h).round();
    if (mw != w || mh != h) {
      return null;
    }
    if (bytes.length == w * h) {
      return bytes;
    }
    final int bpc = pdfCosInt(raw.dict['BitsPerComponent']) ?? 1;
    final bool invert = _decodeInverts(raw.dict);
    final Uint8List rgb = _expandGray(bytes, w, h, bpc, invert: invert);
    if (rgb.length != w * h * 3) {
      return null;
    }
    final Uint8List gray = Uint8List(w * h);
    for (int i = 0; i < gray.length; i++) {
      gray[i] = rgb[i * 3];
    }
    return gray;
  }

  static Uint8List _composeSMask(Uint8List rgb, Uint8List mask, int w, int h) {
    final Uint8List out = Uint8List(w * h * 4);
    for (int i = 0; i < w * h; i++) {
      out[i * 4] = rgb[i * 3];
      out[i * 4 + 1] = rgb[i * 3 + 1];
      out[i * 4 + 2] = rgb[i * 3 + 2];
      out[i * 4 + 3] = mask[i];
    }
    return out;
  }

  void _doShading(String name, PdfCosDict resources, _Frame frame) {
    if (frame.hidden) {
      return;
    }
    final PdfCosDict? shs = store.asDict(resources['Shading']);
    final PdfCosDict? sh = shs == null ? null : store.asDict(shs[name]);
    if (sh == null) {
      return;
    }
    final int type = pdfCosInt(sh['ShadingType']) ?? 0;
    if (type == 3) {
      _radialShading(sh, frame);
      return;
    }
    if (type != 2) {
      return;
    }
    final PdfCosArray? coords = store.asArray(sh['Coords']);
    if (coords == null || coords.items.length < 4) {
      return;
    }
    final double x0 = pdfCosNumber(coords.items[0]) ?? 0;
    final double y0 = pdfCosNumber(coords.items[1]) ?? 0;
    final double x1 = pdfCosNumber(coords.items[2]) ?? 0;
    final double y1 = pdfCosNumber(coords.items[3]) ?? 0;
    final PdfCosDict? fn = store.asDict(sh['Function']);
    final List<double> c0 = _fnColor(fn?['C0'], 0);
    final List<double> c1 = _fnColor(fn?['C1'], 1);
    const int steps = 12;
    final bool alongX = (x1 - x0).abs() >= (y1 - y0).abs();
    for (int i = 0; i < steps; i++) {
      final double t = i / steps;
      final double t2 = (i + 1) / steps;
      final int color = _lerpRgb(c0, c1, t);
      if (alongX) {
        final double xa = x0 + (x1 - x0) * t;
        final double xb = x0 + (x1 - x0) * t2;
        final double top = math.min(y0, y1);
        frame.path.add(
          PdfPathVerb(
            PdfPathKind.rect,
            math.min(xa, xb),
            top,
            (xb - xa).abs().clamp(0.5, 1e6),
            (y1 - y0).abs().clamp(0.5, 1e6),
          ),
        );
      } else {
        final double ya = y0 + (y1 - y0) * t;
        final double yb = y0 + (y1 - y0) * t2;
        final double left = math.min(x0, x1);
        frame.path.add(
          PdfPathVerb(
            PdfPathKind.rect,
            left,
            math.min(ya, yb),
            (x1 - x0).abs().clamp(0.5, 1e6),
            (yb - ya).abs().clamp(0.5, 1e6),
          ),
        );
      }
      frame.fill = _keepAlpha(frame.fill, color);
      frame.emitFill(false);
    }
  }

  void _radialShading(PdfCosDict sh, _Frame frame) {
    final PdfCosArray? coords = store.asArray(sh['Coords']);
    if (coords == null || coords.items.length < 6) {
      return;
    }
    final double x0 = pdfCosNumber(coords.items[0]) ?? 0;
    final double y0 = pdfCosNumber(coords.items[1]) ?? 0;
    final double r0 = pdfCosNumber(coords.items[2]) ?? 0;
    final double x1 = pdfCosNumber(coords.items[3]) ?? 0;
    final double y1 = pdfCosNumber(coords.items[4]) ?? 0;
    final double r1 = pdfCosNumber(coords.items[5]) ?? 0;
    final PdfCosDict? fn = store.asDict(sh['Function']);
    final List<double> c0 = _fnColor(fn?['C0'], 0);
    final List<double> c1 = _fnColor(fn?['C1'], 1);
    const int steps = 12;
    for (int i = steps - 1; i >= 0; i--) {
      final double t = i / steps;
      final double cx = x0 + (x1 - x0) * t;
      final double cy = y0 + (y1 - y0) * t;
      final double r = (r0 + (r1 - r0) * t).abs().clamp(0.5, 1e6);
      frame.fill = _keepAlpha(frame.fill, _lerpRgb(c0, c1, t));
      _addCircle(frame, cx, cy, r);
      frame.emitFill(false);
    }
  }

  static void _addCircle(_Frame frame, double cx, double cy, double r) {
    const double k = 0.5522847498307936;
    frame.path
      ..add(PdfPathVerb(PdfPathKind.move, cx + r, cy))
      ..add(
        PdfPathVerb(
          PdfPathKind.cubic,
          cx + r,
          cy + k * r,
          cx + k * r,
          cy + r,
          cx,
          cy + r,
        ),
      )
      ..add(
        PdfPathVerb(
          PdfPathKind.cubic,
          cx - k * r,
          cy + r,
          cx - r,
          cy + k * r,
          cx - r,
          cy,
        ),
      )
      ..add(
        PdfPathVerb(
          PdfPathKind.cubic,
          cx - r,
          cy - k * r,
          cx - k * r,
          cy - r,
          cx,
          cy - r,
        ),
      )
      ..add(
        PdfPathVerb(
          PdfPathKind.cubic,
          cx + k * r,
          cy - r,
          cx + r,
          cy - k * r,
          cx + r,
          cy,
        ),
      )
      ..add(const PdfPathVerb(PdfPathKind.close, 0, 0));
  }

  static int _lerpRgb(List<double> c0, List<double> c1, double t) {
    return _rgb(
      c0[0] + (c1[0] - c0[0]) * t,
      c0[1] + (c1[1] - c0[1]) * t,
      c0[2] + (c1[2] - c0[2]) * t,
    );
  }

  static List<double> _fnColor(PdfCos? value, double fallback) {
    if (value is PdfCosArray && value.items.length >= 4) {
      final int argb = _cmyk(
        pdfCosNumber(value.items[0]) ?? fallback,
        pdfCosNumber(value.items[1]) ?? fallback,
        pdfCosNumber(value.items[2]) ?? fallback,
        pdfCosNumber(value.items[3]) ?? fallback,
      );
      return <double>[
        ((argb >> 16) & 0xFF) / 255.0,
        ((argb >> 8) & 0xFF) / 255.0,
        (argb & 0xFF) / 255.0,
      ];
    }
    if (value is PdfCosArray && value.items.isNotEmpty) {
      return <double>[
        pdfCosNumber(value.items[0]) ?? fallback,
        value.items.length > 1
            ? (pdfCosNumber(value.items[1]) ?? fallback)
            : fallback,
        value.items.length > 2
            ? (pdfCosNumber(value.items[2]) ?? fallback)
            : fallback,
      ];
    }
    return <double>[fallback, fallback, fallback];
  }

  _FontRes? _loadFont(PdfCosDict resources, String name) {
    final PdfCosDict? fonts = store.asDict(resources['Font']);
    if (fonts == null) {
      return null;
    }
    final PdfCosDict? font = store.asDict(fonts[name]);
    if (font == null) {
      return null;
    }
    PdfToUnicode? cmap;
    final Uint8List? tu = store.streamBytes(font['ToUnicode']);
    if (tu != null) {
      cmap = PdfToUnicode.parse(tu);
    } else {
      final PdfCos? desc = store.deref(font['DescendantFonts']);
      if (desc is PdfCosArray && desc.items.isNotEmpty) {
        final PdfCosDict? cid = store.asDict(desc.items.first);
        final Uint8List? inner = cid == null
            ? null
            : store.streamBytes(cid['ToUnicode']);
        if (inner != null) {
          cmap = PdfToUnicode.parse(inner);
        }
      }
    }
    String family = pdfCosName(font['BaseFont']) ?? '';
    if (family.contains('+')) {
      family = family.substring(family.lastIndexOf('+') + 1);
    }
    PdfCosDict? desc = store.asDict(font['FontDescriptor']);
    final PdfCos? kids = store.deref(font['DescendantFonts']);
    if (desc == null && kids is PdfCosArray && kids.items.isNotEmpty) {
      final PdfCosDict? cid = store.asDict(kids.items.first);
      desc = cid == null ? null : store.asDict(cid['FontDescriptor']);
    }
    final Uint8List? fileBytes = desc == null
        ? null
        : store.streamBytes(desc['FontFile2']) ??
              store.streamBytes(desc['FontFile3']) ??
              store.streamBytes(desc['FontFile']);
    SfntFont? sfnt;
    if (fileBytes != null && fileBytes.length > 16) {
      try {
        sfnt = SfntFont.parse(fileBytes);
        if (family.isEmpty && sfnt.familyName.isNotEmpty) {
          family = sfnt.familyName;
        }
      } catch (_) {
        sfnt = null;
      }
    }
    final int flags = pdfCosInt(desc?['Flags']) ?? 0;
    final bool italic =
        flags & 64 != 0 ||
        family.contains('Italic') ||
        family.contains('Oblique');
    final bool bold = flags & 262144 != 0 || family.contains('Bold');
    final String subtype = pdfCosName(font['Subtype']) ?? '';
    final bool cid = subtype == 'Type0' || kids is PdfCosArray;
    final Uint8List? hostBytes = fileBytes == null
        ? null
        : PdfCffHost.forFlutter(
            fileBytes,
            toUnicode: cmap,
            cid: cid,
            family: family.isEmpty ? 'CFF' : family,
          );
    PdfCosDict simpleOrCid = font;
    if (cid && kids is PdfCosArray && kids.items.isNotEmpty) {
      simpleOrCid = store.asDict(kids.items.first) ?? font;
    }
    final String encoding = _encodingName(font, simpleOrCid);
    final Map<int, int> widths = _readWidths(simpleOrCid, cid, family);
    final Map<int, String> type3 = subtype == 'Type3'
        ? _type3Names(font)
        : const <int, String>{};
    if (family.isEmpty) {
      family = 'Helvetica';
    }
    return _FontRes(
      cmap,
      family: family,
      bold: bold,
      italic: italic,
      bytes: hostBytes,
      sfnt: sfnt,
      encoding: encoding,
      widths: widths,
      dw: pdfCosInt(simpleOrCid['DW']) ?? 1000,
      cid: cid,
      type3: type3,
      type3Procs: subtype == 'Type3' ? font : null,
    );
  }

  String _encodingName(PdfCosDict font, PdfCosDict? desc) {
    final PdfCos? enc =
        store.deref(font['Encoding']) ??
        (desc == null ? null : store.deref(desc['Encoding']));
    if (enc is PdfCosName) {
      return enc.value;
    }
    if (enc is PdfCosDict) {
      return pdfCosName(enc['BaseEncoding']) ?? 'WinAnsiEncoding';
    }
    return 'WinAnsiEncoding';
  }

  Map<int, int> _readWidths(PdfCosDict font, bool cid, String family) {
    final Map<int, int> out = <int, int>{};
    if (cid) {
      final PdfCos? w = store.deref(font['W']);
      if (w is PdfCosArray) {
        var i = 0;
        while (i < w.items.length) {
          final int c0 = pdfCosInt(w.items[i]) ?? 0;
          i++;
          if (i >= w.items.length) {
            break;
          }
          final PdfCos next = w.items[i];
          if (next is PdfCosArray) {
            for (int k = 0; k < next.items.length; k++) {
              out[c0 + k] = pdfCosInt(next.items[k]) ?? 0;
            }
            i++;
          } else if (i + 1 < w.items.length) {
            final int c1 = pdfCosInt(next) ?? c0;
            final int ww = pdfCosInt(w.items[i + 1]) ?? 0;
            for (int c = c0; c <= c1; c++) {
              out[c] = ww;
            }
            i += 2;
          } else {
            break;
          }
        }
      }
      return out;
    }
    final int first = pdfCosInt(font['FirstChar']) ?? 0;
    final PdfCos? arr = store.deref(font['Widths']);
    if (arr is PdfCosArray) {
      for (int i = 0; i < arr.items.length; i++) {
        out[first + i] = pdfCosInt(arr.items[i]) ?? 0;
      }
    }
    if (out.isEmpty) {
      for (int c = 32; c < 127; c++) {
        out[c] = PdfStd14.width(family, c);
      }
    }
    return out;
  }

  Map<int, String> _type3Names(PdfCosDict font) {
    final PdfCos? enc = store.deref(font['Encoding']);
    final PdfCosDict? dict = enc is PdfCosDict ? enc : null;
    final PdfCosArray? diff = dict == null
        ? null
        : store.asArray(dict['Differences']);
    if (diff == null) {
      return const <int, String>{};
    }
    final Map<int, String> out = <int, String>{};
    var code = 0;
    for (final PdfCos item in diff.items) {
      if (item is PdfCosInt) {
        code = item.value;
      } else if (item is PdfCosName) {
        out[code++] = item.value;
      }
    }
    return out;
  }

  void _paintType3(_Frame frame, List<int> codes) {
    final _FontRes? font = frame.font;
    final PdfCosDict? dict = font?.type3Procs;
    if (font == null || dict == null) {
      return;
    }
    final PdfCosDict? procs = store.asDict(dict['CharProcs']);
    final PdfCosDict resources =
        store.asDict(dict['Resources']) ?? PdfCosDict();
    for (final int code in codes) {
      final String? name = font.type3[code];
      final Uint8List? bytes = name == null
          ? null
          : store.streamBytes(procs?[name]);
      final ({double x, double y, double size}) draw = frame._textDraw();
      if (bytes != null) {
        frame.save();
        frame.ctm.multiply(draw.size, 0, 0, draw.size, 0, 0);
        _run(bytes, resources, frame, 1);
        frame.restore();
      }
      frame.textMatrix.multiply(1, 0, 0, 1, frame._textWidth(<int>[code]), 0);
    }
  }

  void _inlineImage(_Lexer lex, PdfCosDict _, _Frame frame) {
    final PdfCosDict dict = PdfCosDict();
    while (true) {
      final _Tok? key = lex.next();
      if (key == null) {
        return;
      }
      if (key.op == 'ID' || key.op == 'EI') {
        break;
      }
      if (key.value is! _Name) {
        continue;
      }
      final _Tok? val = lex.next();
      if (val == null) {
        return;
      }
      final String name = (key.value! as _Name).value;
      final Object? v = val.value;
      if (v is _Name) {
        dict[name] = PdfCosName(v.value);
      } else if (v is num) {
        dict[name] = PdfCosInt(v.round());
      }
      if (val.op == 'ID') {
        break;
      }
    }
    lex.skipWs();
    final int width = pdfCosInt(dict['Width'] ?? dict['W']) ?? 0;
    final int height = pdfCosInt(dict['Height'] ?? dict['H']) ?? 0;
    final int bpc = pdfCosInt(dict['BitsPerComponent'] ?? dict['BPC']) ?? 8;
    final int row = width <= 0 ? 0 : ((width * bpc + 7) ~/ 8);
    final int need = row * height;
    final Uint8List raw = lex.take(need);
    lex.skipWs();
    final _Tok? ei = lex.next();
    if (ei?.op != 'EI' && ei?.op != null) {
      // Trailing token consumed.
    }
    if (width < 1 || height < 1 || frame.hidden) {
      return;
    }
    final (double x, double y) = frame.map(0, 0);
    final (double x1, double y1) = frame.map(1, 1);
    frame.ops.add(
      PdfDrawImage(
        x: math.min(x, x1),
        y: math.min(y, y1),
        width: (x1 - x).abs().clamp(1, 100000),
        height: (y1 - y).abs().clamp(1, 100000),
        bytes: _expandGray(raw, width, height, bpc),
        jpeg: false,
        placeholder: false,
        pixelWidth: width,
        pixelHeight: height,
      ),
    );
  }

  static bool _flag(PdfCos? value) => value is PdfCosBool && value.value;

  /// `/Decode [1 0]` (or max < min) inverts 1-bit samples.
  static bool _decodeInverts(PdfCosDict dict) {
    final PdfCos? raw = dict['Decode'] ?? dict['D'];
    if (raw is! PdfCosArray || raw.items.length < 2) {
      return false;
    }
    final double a = pdfCosNumber(raw.items[0]) ?? 0;
    final double b = pdfCosNumber(raw.items[1]) ?? 1;
    return a > b;
  }

  Uint8List? _indexedPalette(PdfCosDict image) {
    final PdfCos? cs = store.deref(image['ColorSpace']);
    if (cs is! PdfCosArray || cs.items.length < 4) {
      return null;
    }
    final String name = pdfCosName(cs.items.first) ?? '';
    if (name != 'Indexed' && name != 'I') {
      return null;
    }
    final PdfCos? table = store.deref(cs.items[3]);
    if (table is PdfCosStream) {
      return store.streamBytes(table);
    }
    if (table is PdfCosString) {
      return table.bytes;
    }
    return null;
  }

  static Uint8List _expandIndexed(
    Uint8List raw,
    int w,
    int h,
    int bpc,
    Uint8List palette,
  ) {
    final Uint8List rgb = Uint8List(w * h * 3);
    var o = 0;
    for (int i = 0; i < w * h; i++) {
      final int index = _sampleAt(raw, w, i, bpc);
      final int p = (index * 3).clamp(0, palette.length - 3);
      rgb[o++] = palette[p];
      rgb[o++] = p + 1 < palette.length ? palette[p + 1] : 0;
      rgb[o++] = p + 2 < palette.length ? palette[p + 2] : 0;
    }
    return rgb;
  }

  static Uint8List _stencilRgba(
    Uint8List raw,
    int w,
    int h,
    int bpc,
    int fill,
    bool invert,
  ) {
    final int r = (fill >> 16) & 0xFF;
    final int g = (fill >> 8) & 0xFF;
    final int b = fill & 0xFF;
    final Uint8List out = Uint8List(w * h * 4);
    var o = 0;
    for (int i = 0; i < w * h; i++) {
      final int bit = _sampleAt(
        raw,
        w,
        i,
        bpc == 8 && raw.length >= w * h ? 8 : 1,
      );
      final bool paint = invert ? bit == 0 : bit != 0;
      out[o++] = r;
      out[o++] = g;
      out[o++] = b;
      out[o++] = paint ? 255 : 0;
    }
    return out;
  }

  static int _sampleAt(Uint8List raw, int width, int index, int bpc) {
    if (width < 1 || raw.isEmpty) {
      return 0;
    }
    final int x = index % width;
    final int y = index ~/ width;
    if (bpc >= 8) {
      final int i = y * width + x;
      return i < raw.length ? raw[i] : 0;
    }
    final int stride = (width + 7) >> 3;
    final int row = y * stride + (x >> 3);
    if (row < 0 || row >= raw.length) {
      return 0;
    }
    return (raw[row] >> (7 - (x & 7))) & 1;
  }

  static Uint8List _expandGray(
    Uint8List raw,
    int w,
    int h,
    int bpc, {
    bool invert = false,
  }) {
    if (bpc == 8 && raw.length >= w * h) {
      final Uint8List rgb = Uint8List(w * h * 3);
      for (int i = 0; i < w * h; i++) {
        var g = raw[i];
        if (invert) {
          g = 255 - g;
        }
        rgb[i * 3] = g;
        rgb[i * 3 + 1] = g;
        rgb[i * 3 + 2] = g;
      }
      return rgb;
    }
    if (bpc == 1) {
      final int stride = (w + 7) >> 3;
      if (raw.length < stride * h || w < 1 || h < 1) {
        return raw;
      }
      final Uint8List rgb = Uint8List(w * h * 3);
      var o = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final int byte = raw[y * stride + (x >> 3)];
          final int bit = (byte >> (7 - (x & 7))) & 1;
          final int g = (invert ? bit == 0 : bit != 0) ? 255 : 0;
          rgb[o++] = g;
          rgb[o++] = g;
          rgb[o++] = g;
        }
      }
      return rgb;
    }
    return raw;
  }

  static double _n(Object value) {
    if (value is num) {
      return value.toDouble();
    }
    return 0;
  }

  static Object _text(Object value) => value;

  static int _rgb(double r, double g, double b) {
    final int R = (r.clamp(0, 1) * 255).round();
    final int G = (g.clamp(0, 1) * 255).round();
    final int B = (b.clamp(0, 1) * 255).round();
    return 0xFF000000 | (R << 16) | (G << 8) | B;
  }

  /// Keep `/ca`/`/CA` alpha when operators replace the RGB channels.
  static int _keepAlpha(int previous, int rgb) {
    return (previous & 0xFF000000) | (rgb & 0x00FFFFFF);
  }

  static int _mulColorAlpha(int color, double opacity) {
    final int a = (((color >> 24) & 0xFF) * opacity).round().clamp(0, 255);
    return (a << 24) | (color & 0x00FFFFFF);
  }

  static void _scaleOpsOpacity(
    List<PdfPaintOp> ops,
    int start,
    double opacity,
  ) {
    if (opacity >= 0.999 || start >= ops.length) {
      return;
    }
    for (int i = start; i < ops.length; i++) {
      final PdfPaintOp op = ops[i];
      if (op is PdfFillPath) {
        ops[i] = PdfFillPath(
          points: op.points,
          color: _mulColorAlpha(op.color, opacity),
          evenOdd: op.evenOdd,
          blend: op.blend,
        );
      } else if (op is PdfStrokePath) {
        ops[i] = PdfStrokePath(
          points: op.points,
          color: _mulColorAlpha(op.color, opacity),
          width: op.width,
          cap: op.cap,
          join: op.join,
          miter: op.miter,
          dash: op.dash,
          dashPhase: op.dashPhase,
          blend: op.blend,
        );
      } else if (op is PdfDrawText) {
        ops[i] = PdfDrawText(
          x: op.x,
          y: op.y,
          size: op.size,
          color: _mulColorAlpha(op.color, opacity),
          text: op.text,
          italic: op.italic,
          bold: op.bold,
          fontFamily: op.fontFamily,
          fontBytes: op.fontBytes,
        );
      } else if (op is PdfDrawImage) {
        ops[i] = PdfDrawImage(
          x: op.x,
          y: op.y,
          width: op.width,
          height: op.height,
          bytes: _mulImageOpacity(op, opacity),
          jpeg: op.jpeg,
          placeholder: op.placeholder,
          pixelWidth: op.pixelWidth,
          pixelHeight: op.pixelHeight,
          hasAlpha: true,
          softMaskJpeg: op.softMaskJpeg,
          blend: op.blend,
        );
      }
    }
  }

  static Uint8List _mulImageOpacity(PdfDrawImage image, double opacity) {
    final int pw = image.pixelWidth;
    final int ph = image.pixelHeight;
    if (pw < 1 || ph < 1 || image.placeholder) {
      return image.bytes;
    }
    if (image.hasAlpha && image.bytes.length >= pw * ph * 4) {
      final Uint8List out = Uint8List.fromList(
        image.bytes.sublist(0, pw * ph * 4),
      );
      for (int i = 3; i < out.length; i += 4) {
        out[i] = (out[i] * opacity).round().clamp(0, 255);
      }
      return out;
    }
    if (image.jpeg) {
      // Painter cannot re-encode JPEG with alpha; leave opaque (rare for groups).
      return image.bytes;
    }
    if (image.bytes.length < pw * ph * 3) {
      return image.bytes;
    }
    final Uint8List out = Uint8List(pw * ph * 4);
    final int a = (opacity * 255).round().clamp(0, 255);
    var o = 0;
    for (int i = 0; i < pw * ph; i++) {
      out[o++] = image.bytes[i * 3];
      out[o++] = image.bytes[i * 3 + 1];
      out[o++] = image.bytes[i * 3 + 2];
      out[o++] = a;
    }
    return out;
  }

  static int _cmyk(double c, double m, double y, double k) {
    final double r = (1 - c) * (1 - k);
    final double g = (1 - m) * (1 - k);
    final double b = (1 - y) * (1 - k);
    return _rgb(r, g, b);
  }

  static PdfBlendMode _blendOf(String name) {
    switch (name) {
      case 'Multiply':
        return PdfBlendMode.multiply;
      case 'Screen':
        return PdfBlendMode.screen;
      default:
        return PdfBlendMode.normal;
    }
  }
}

class _FontRes {
  _FontRes(
    this.cmap, {
    this.family = 'Helvetica',
    this.bold = false,
    this.italic = false,
    this.bytes,
    this.sfnt,
    this.encoding = 'WinAnsiEncoding',
    this.widths = const <int, int>{},
    this.dw = 1000,
    this.cid = false,
    this.type3 = const <int, String>{},
    this.type3Procs,
  });
  final PdfToUnicode? cmap;
  final String family;
  final bool bold;
  final bool italic;
  final Uint8List? bytes;
  final SfntFont? sfnt;
  final String encoding;
  final Map<int, int> widths;
  final int dw;
  final bool cid;
  final Map<int, String> type3;
  final PdfCosDict? type3Procs;

  double widthOfCodes(List<int> codes, double size) {
    if (codes.isEmpty) {
      return 0;
    }
    var w = 0.0;
    for (final int code in codes) {
      final int tw = widths[code] ?? (cid ? dw : PdfStd14.width(family, code));
      if (sfnt != null && !cid) {
        final int cp = PdfStd14.unicode(code, encoding);
        final int gid = sfnt!.glyphIdFor(cp);
        if (gid != 0) {
          w += sfnt!.advanceWidth(gid) / sfnt!.unitsPerEm * size;
          continue;
        }
      }
      w += tw / 1000.0 * size;
    }
    return w;
  }
}

class _Matrix {
  _Matrix(this.a, this.b, this.c, this.d, this.e, this.f);

  factory _Matrix.identity() => _Matrix(1, 0, 0, 1, 0, 0);

  double a, b, c, d, e, f;

  _Matrix copy() => _Matrix(a, b, c, d, e, f);

  void multiply(
    double na,
    double nb,
    double nc,
    double nd,
    double ne,
    double nf,
  ) {
    final double oa = a, ob = b, oc = c, od = d, oe = e, of = f;
    a = oa * na + oc * nb;
    b = ob * na + od * nb;
    c = oa * nc + oc * nd;
    d = ob * nc + od * nd;
    e = oa * ne + oc * nf + oe;
    f = ob * ne + od * nf + of;
  }

  (double, double) map(double x, double y) =>
      (a * x + c * y + e, b * x + d * y + f);
}

class _Frame {
  _Frame(this.page, this.interp);

  final PdfPageInfo page;
  final PdfInterpreter interp;

  (double, double) get currentPoint {
    if (path.isEmpty) {
      return (0, 0);
    }
    final PdfPathVerb last = path.last;
    return last.kind == PdfPathKind.cubic
        ? (last.x3, last.y3)
        : (last.x, last.y);
  }

  void applyExtGState(PdfCosStore store, PdfCosDict resources, String name) {
    final PdfCosDict? ext = store.asDict(resources['ExtGState']);
    final PdfCosDict? gs = ext == null ? null : store.asDict(ext[name]);
    if (gs == null) {
      return;
    }
    final double? lw = pdfCosNumber(gs['LW']);
    if (lw != null) {
      lineWidth = lw;
    }
    final double? ca = pdfCosNumber(gs['ca']);
    if (ca != null) {
      final int a = (ca.clamp(0, 1) * 255).round();
      fill = (fill & 0x00FFFFFF) | (a << 24);
    }
    final double? strokeAlpha = pdfCosNumber(gs['CA']);
    if (strokeAlpha != null) {
      final int a = (strokeAlpha.clamp(0, 1) * 255).round();
      stroke = (stroke & 0x00FFFFFF) | (a << 24);
    }
    final int? lc = pdfCosInt(gs['LC']);
    if (lc != null) {
      lineCap = lc.clamp(0, 2);
    }
    final int? lj = pdfCosInt(gs['LJ']);
    if (lj != null) {
      lineJoin = lj.clamp(0, 2);
    }
    final double? ml = pdfCosNumber(gs['ML']);
    if (ml != null) {
      miter = ml;
    }
    final PdfCos? d = store.deref(gs['D']);
    if (d is PdfCosArray && d.items.isNotEmpty) {
      final PdfCos arr = d.items.first;
      if (arr is PdfCosArray) {
        dash = <double>[
          for (final PdfCos item in arr.items) pdfCosNumber(item) ?? 0,
        ];
      }
      if (d.items.length > 1) {
        dashPhase = pdfCosNumber(d.items[1]) ?? 0;
      }
    }
    final String? bm = pdfCosName(gs['BM']);
    if (bm != null) {
      blend = PdfInterpreter._blendOf(bm);
    }
  }

  _Matrix ctm = _Matrix.identity();
  _Matrix textMatrix = _Matrix.identity();
  _Matrix textLine = _Matrix.identity();
  final List<_Snap> _stack = <_Snap>[];
  final List<PdfPathVerb> path = <PdfPathVerb>[];
  final List<PdfPaintOp> ops = <PdfPaintOp>[];
  final List<PdfTextRun> runs = <PdfTextRun>[];
  int fill = 0xFF000000;
  int stroke = 0xFF000000;
  double lineWidth = 1;
  int lineCap = 0;
  int lineJoin = 0;
  double miter = 10;
  List<double> dash = const <double>[];
  double dashPhase = 0;
  PdfBlendMode blend = PdfBlendMode.normal;
  int textRender = 0;
  String? actualText;
  var actualTextEmitted = false;
  final List<String?> _actualStack = <String?>[];
  double fontSize = 12;
  double charSpace = 0;
  double wordSpace = 0;
  double horizScale = 1;
  double leading = 0;
  double rise = 0;
  _FontRes? font;
  var clipPending = false;
  var clipEvenOdd = false;
  var _hidden = 0;
  final List<bool> _marks = <bool>[];

  bool get hidden => _hidden > 0;

  void beginMarked(List<Object> stack, PdfCosDict resources) {
    var hide = false;
    String? marked;
    if (stack.isNotEmpty && stack.last is _Name) {
      final String last = (stack.last as _Name).value;
      final PdfCosDict? props = interp.store.asDict(resources['Properties']);
      final PdfCos? raw = props?[last];
      final int? id = raw is PdfCosRef ? raw.id : null;
      if (id != null) {
        for (final PdfLayer layer in interp.layers) {
          if (layer.objectId == id && !layer.visible) {
            hide = true;
          }
        }
      }
      if (raw is PdfCosDict) {
        marked = pdfCosText(raw['ActualText']);
      }
    } else if (stack.isNotEmpty && stack.last is _Dict) {
      marked = _asMarkedText(stack.last as _Dict);
    }
    _actualStack.add(actualText);
    if (marked != null) {
      actualText = marked;
      actualTextEmitted = false;
    }
    _marks.add(hide);
    if (hide) {
      _hidden++;
    }
  }

  void endMarked() {
    if (_actualStack.isNotEmpty) {
      actualText = _actualStack.removeLast();
      actualTextEmitted = false;
    }
    if (_marks.isEmpty) {
      return;
    }
    if (_marks.removeLast()) {
      _hidden--;
    }
  }

  static String? _asMarkedText(_Dict dict) {
    final Object? value = dict['ActualText'];
    if (value is _Lit) {
      return String.fromCharCodes(value.bytes);
    }
    if (value is String) {
      return value;
    }
    if (value is _Hex) {
      return _utf16FromBytes(value.bytes);
    }
    return null;
  }

  static String _utf16FromBytes(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final StringBuffer buf = StringBuffer();
      for (int i = 2; i + 1 < bytes.length; i += 2) {
        buf.writeCharCode((bytes[i] << 8) | bytes[i + 1]);
      }
      return buf.toString();
    }
    return String.fromCharCodes(bytes);
  }

  void save() {
    _stack.add(
      _Snap(
        ctm: ctm.copy(),
        fill: fill,
        stroke: stroke,
        lineWidth: lineWidth,
        fontSize: fontSize,
        font: font,
        lineCap: lineCap,
        lineJoin: lineJoin,
        miter: miter,
        dash: dash,
        dashPhase: dashPhase,
        blend: blend,
        textRender: textRender,
      ),
    );
  }

  void restore() {
    if (_stack.isEmpty) {
      return;
    }
    final _Snap s = _stack.removeLast();
    ctm = s.ctm;
    fill = s.fill;
    stroke = s.stroke;
    lineWidth = s.lineWidth;
    fontSize = s.fontSize;
    font = s.font;
    lineCap = s.lineCap;
    lineJoin = s.lineJoin;
    miter = s.miter;
    dash = s.dash;
    dashPhase = s.dashPhase;
    blend = s.blend;
    textRender = s.textRender;
  }

  (double, double) map(double x, double y) {
    final (double px, double py) = ctm.map(x, y);
    return (px - page.cropBox.llx, page.cropBox.ury - py);
  }

  List<PdfPathVerb> _mappedPath() {
    final List<PdfPathVerb> out = <PdfPathVerb>[];
    for (final PdfPathVerb v in path) {
      if (v.kind == PdfPathKind.rect) {
        final (double x0, double y0) = map(v.x, v.y);
        final (double x1, double y1) = map(v.x + v.x2, v.y);
        final (double x2, double y2) = map(v.x + v.x2, v.y + v.y2);
        final (double x3, double y3) = map(v.x, v.y + v.y2);
        out
          ..add(PdfPathVerb(PdfPathKind.move, x0, y0))
          ..add(PdfPathVerb(PdfPathKind.line, x1, y1))
          ..add(PdfPathVerb(PdfPathKind.line, x2, y2))
          ..add(PdfPathVerb(PdfPathKind.line, x3, y3))
          ..add(const PdfPathVerb(PdfPathKind.close, 0, 0));
        continue;
      }
      if (v.kind == PdfPathKind.cubic) {
        out.add(
          PdfPathVerb(
            v.kind,
            map(v.x, v.y).$1,
            map(v.x, v.y).$2,
            map(v.x2, v.y2).$1,
            map(v.x2, v.y2).$2,
            map(v.x3, v.y3).$1,
            map(v.x3, v.y3).$2,
          ),
        );
        continue;
      }
      out.add(PdfPathVerb(v.kind, map(v.x, v.y).$1, map(v.x, v.y).$2));
    }
    return out;
  }

  void emitClip() {
    if (path.isEmpty) {
      clipPending = false;
      return;
    }
    ops.add(PdfClipPath(points: _mappedPath(), evenOdd: clipEvenOdd));
    clipPending = false;
  }

  void endPath() {
    if (clipPending) {
      emitClip();
    }
    path.clear();
    clipPending = false;
  }

  void emitFill(bool evenOdd, {bool keepPath = false}) {
    if (clipPending) {
      emitClip();
    }
    if (path.isEmpty || hidden) {
      if (!keepPath) {
        path.clear();
      }
      return;
    }
    ops.add(
      PdfFillPath(
        points: _mappedPath(),
        color: fill,
        evenOdd: evenOdd,
        blend: blend,
      ),
    );
    if (!keepPath) {
      path.clear();
    }
  }

  void emitStroke() {
    if (clipPending) {
      emitClip();
    }
    if (path.isEmpty || hidden) {
      path.clear();
      return;
    }
    final double scale = math.sqrt(ctm.a * ctm.a + ctm.b * ctm.b);
    final double s = scale == 0 ? 1 : scale;
    ops.add(
      PdfStrokePath(
        points: _mappedPath(),
        color: stroke,
        width: lineWidth * s,
        cap: lineCap,
        join: lineJoin,
        miter: miter,
        dash: <double>[for (final double v in dash) v * s],
        dashPhase: dashPhase * s,
        blend: blend,
      ),
    );
    path.clear();
  }

  void td(double tx, double ty) {
    textLine.multiply(1, 0, 0, 1, tx, ty);
    textMatrix = textLine.copy();
  }

  /// ActualText with nothing decodable in the showing operator.
  void _emitActualTextOnly() {
    final String? marked = actualText;
    if (marked == null || marked.isEmpty || actualTextEmitted || hidden) {
      return;
    }
    final ({double x, double y, double size}) start = _textDraw();
    runs.add(
      PdfTextRun(
        text: marked,
        x: start.x,
        y: start.y,
        width: 0,
        height: start.size <= 0 ? 12 : start.size,
      ),
    );
    actualTextEmitted = true;
  }

  void show(Object value) {
    final ({String text, List<int> codes, List<String> glyphs}) run = _decode(
      value,
    );
    if (run.text.isEmpty && run.codes.isEmpty) {
      // A marked span can carry ActualText while the WinAnsi showing is
      // empty (Arabic on Helvetica). The marked string is the line.
      _emitActualTextOnly();
      return;
    }
    if (hidden) {
      textMatrix.multiply(1, 0, 0, 1, _textWidth(run.codes), 0);
      return;
    }
    if (font?.type3Procs != null) {
      interp._paintType3(this, run.codes);
      return;
    }
    _emitText(run.text, run.codes, run.glyphs);
  }

  void showTj(List<Object> items) {
    for (final Object item in items) {
      if (item is num) {
        textMatrix.multiply(
          1,
          0,
          0,
          1,
          -item.toDouble() / 1000.0 * fontSize,
          0,
        );
        continue;
      }
      final ({String text, List<int> codes, List<String> glyphs}) run = _decode(
        item,
      );
      if (run.text.isEmpty && run.codes.isEmpty) {
        _emitActualTextOnly();
        continue;
      }
      if (hidden) {
        textMatrix.multiply(1, 0, 0, 1, _textWidth(run.codes), 0);
        continue;
      }
      if (font?.type3Procs != null) {
        interp._paintType3(this, run.codes);
        continue;
      }
      _emitText(run.text, run.codes, run.glyphs);
    }
  }

  /// Paint one PDF code at a time. Ligatures map to multi-char strings but
  /// still use one PDF advance; joining them lets Flutter `hmtx` fight TJ/Tw.
  ///
  /// A rotated baseline is different: the showing is one word. Splitting it
  /// draws upright letters along a diagonal and breaks Arabic joining.
  void _emitText(String text, List<int> codes, List<String> glyphs) {
    final ({double x, double y, double size}) start = _textDraw();
    final double totalW = _textWidth(codes);
    final double renderedW = fontSize.abs() < 1e-9
        ? totalW
        : totalW * (start.size / fontSize.abs());
    final double angle = _screenAngle();
    if (angle.abs() > 0.02) {
      final String paint = actualText != null && actualText!.isNotEmpty
          ? actualText!
          : text;
      if (actualText != null) {
        actualTextEmitted = true;
      }
      if (paint.isNotEmpty && textRender != 3) {
        ops.add(
          PdfDrawText(
            x: start.x,
            y: start.y,
            size: start.size,
            color: textRender == 1 ? stroke : fill,
            text: paint,
            italic: font?.italic ?? false,
            bold: font?.bold ?? false,
            fontFamily: font?.family ?? 'Helvetica',
            fontBytes: font?.bytes,
            angle: angle,
          ),
        );
      }
      textMatrix.multiply(1, 0, 0, 1, totalW, 0);
      if (paint.isNotEmpty) {
        runs.add(
          PdfTextRun(
            text: paint,
            x: start.x,
            y: start.y,
            width: renderedW,
            height: start.size,
          ),
        );
      }
      return;
    }
    if (textRender != 3) {
      final List<String> paintGlyphs = glyphs.length == codes.length
          ? glyphs
          : <String>[for (final int u in text.runes) String.fromCharCode(u)];
      final List<int> paintCodes = glyphs.length == codes.length
          ? codes
          : <int>[for (final int u in text.runes) u];
      if (paintCodes.isNotEmpty && paintGlyphs.length == paintCodes.length) {
        for (int i = 0; i < paintCodes.length; i++) {
          final String g = paintGlyphs[i];
          final ({double x, double y, double size}) draw = _textDraw();
          if (g.isNotEmpty) {
            ops.add(
              PdfDrawText(
                x: draw.x,
                y: draw.y,
                size: draw.size,
                color: textRender == 1 ? stroke : fill,
                text: g,
                italic: font?.italic ?? false,
                bold: font?.bold ?? false,
                fontFamily: font?.family ?? 'Helvetica',
                fontBytes: font?.bytes,
              ),
            );
          }
          final int unit = g.isEmpty ? 0 : g.runes.first;
          textMatrix.multiply(1, 0, 0, 1, _advanceCode(paintCodes[i], unit), 0);
        }
      } else {
        ops.add(
          PdfDrawText(
            x: start.x,
            y: start.y,
            size: start.size,
            color: textRender == 1 ? stroke : fill,
            text: text,
            italic: font?.italic ?? false,
            bold: font?.bold ?? false,
            fontFamily: font?.family ?? 'Helvetica',
            fontBytes: font?.bytes,
          ),
        );
        textMatrix.multiply(1, 0, 0, 1, totalW, 0);
      }
    } else {
      textMatrix.multiply(1, 0, 0, 1, totalW, 0);
    }
    final String extract = actualText != null && !actualTextEmitted
        ? actualText!
        : (actualText != null ? '' : text);
    if (actualText != null) {
      actualTextEmitted = true;
    }
    if (extract.isNotEmpty) {
      runs.add(
        PdfTextRun(
          text: extract,
          x: start.x,
          y: start.y,
          width: renderedW,
          height: start.size,
        ),
      );
    }
  }

  /// Screen-space angle of the text baseline (y down, clockwise positive).
  double _screenAngle() {
    final _Matrix trm = ctm.copy();
    trm.multiply(
      textMatrix.a,
      textMatrix.b,
      textMatrix.c,
      textMatrix.d,
      textMatrix.e,
      textMatrix.f,
    );
    final (double x0, double y0) = trm.map(0, 0);
    final (double x1, double y1) = trm.map(1, 0);
    return math.atan2(-(y1 - y0), x1 - x0);
  }

  /// ISO 32000-1 §9.4.4: ((w0/1000)×Tfs + Tc + Tw)×Th; Tw only for space.
  double _advanceCode(int code, int unit) {
    var w = font?.widthOfCodes(<int>[code], fontSize) ?? fontSize.abs() * 0.5;
    w += charSpace;
    if (code == 32 || unit == 0x20) {
      w += wordSpace;
    }
    return w * horizScale;
  }

  double _textWidth(List<int> codes) {
    var w =
        font?.widthOfCodes(codes, fontSize) ??
        codes.length * fontSize.abs() * 0.5;
    w += charSpace * codes.length;
    for (final int code in codes) {
      if (code == 32) {
        w += wordSpace;
      }
    }
    return w * horizScale;
  }

  /// ISO 32000-1 §9.4.4: Trm = Tfs × Tm × CTM. Size comes from Trm, not Tf alone.
  ({double x, double y, double size}) _textDraw() {
    final _Matrix trm = ctm.copy();
    trm.multiply(
      textMatrix.a,
      textMatrix.b,
      textMatrix.c,
      textMatrix.d,
      textMatrix.e,
      textMatrix.f,
    );
    final double fs = fontSize == 0 ? 1 : fontSize;
    trm.multiply(fs * horizScale, 0, 0, fs, 0, rise);
    final double size = math.sqrt(trm.a * trm.a + trm.b * trm.b);
    final double x = trm.e - page.cropBox.llx;
    final double y = page.cropBox.ury - trm.f - size;
    return (x: x, y: y, size: size < 0.2 ? fs.abs() : size);
  }

  ({String text, List<int> codes, List<String> glyphs}) _decode(Object value) {
    if (value is _Hex) {
      final PdfToUnicode? cmap = font?.cmap;
      final StringBuffer buf = StringBuffer();
      final List<int> codes = <int>[];
      final List<String> glyphs = <String>[];
      final bool wide =
          font?.cid == true ||
          (value.bytes.length >= 2 && value.bytes.length.isEven);
      if (wide && value.bytes.length >= 2) {
        for (int i = 0; i + 1 < value.bytes.length; i += 2) {
          final int cid = (value.bytes[i] << 8) | value.bytes[i + 1];
          codes.add(cid);
          final String g = _mapCid(cmap, cid);
          glyphs.add(g);
          buf.write(g);
        }
        if (value.bytes.length.isOdd) {
          final int cid = value.bytes.last;
          codes.add(cid);
          final String g = _mapCid(cmap, cid);
          glyphs.add(g);
          buf.write(g);
        }
      } else {
        for (final int b in value.bytes) {
          codes.add(b);
          final String g = _mapCid(cmap, b, encoding: font?.encoding);
          glyphs.add(g);
          buf.write(g);
        }
      }
      return (text: buf.toString(), codes: codes, glyphs: glyphs);
    }
    if (value is _Lit) {
      final PdfToUnicode? cmap = font?.cmap;
      final StringBuffer buf = StringBuffer();
      final List<int> codes = <int>[];
      final List<String> glyphs = <String>[];
      final List<int> units = value.bytes;
      if (font?.cid == true) {
        for (int i = 0; i + 1 < units.length; i += 2) {
          final int cid = (units[i] << 8) | units[i + 1];
          codes.add(cid);
          final String g = _mapCid(cmap, cid);
          glyphs.add(g);
          buf.write(g);
        }
        if (units.length.isOdd) {
          final int cid = units.last;
          codes.add(cid);
          final String g = _mapCid(cmap, cid);
          glyphs.add(g);
          buf.write(g);
        }
      } else {
        for (final int b in units) {
          codes.add(b);
          final String g = _mapCid(cmap, b, encoding: font?.encoding);
          glyphs.add(g);
          buf.write(g);
        }
      }
      return (text: buf.toString(), codes: codes, glyphs: glyphs);
    }
    if (value is String) {
      return (
        text: value,
        codes: value.codeUnits,
        glyphs: <String>[
          for (final int u in value.runes) String.fromCharCode(u),
        ],
      );
    }
    return (text: '', codes: const <int>[], glyphs: const <String>[]);
  }

  String _mapCid(PdfToUnicode? cmap, int cid, {String? encoding}) {
    final String mapped = cmap?.mapCid(cid) ?? '';
    if (mapped.isNotEmpty) {
      return mapped.replaceAll(String.fromCharCode(0), '');
    }
    if (cid <= 0) {
      return '';
    }
    if (cid <= 0xFFFF) {
      final int uni = encoding == null ? cid : PdfStd14.unicode(cid, encoding);
      return uni <= 0 ? '' : String.fromCharCode(uni);
    }
    return '';
  }
}

class _Snap {
  _Snap({
    required this.ctm,
    required this.fill,
    required this.stroke,
    required this.lineWidth,
    required this.fontSize,
    required this.font,
    required this.lineCap,
    required this.lineJoin,
    required this.miter,
    required this.dash,
    required this.dashPhase,
    required this.blend,
    required this.textRender,
  });
  final _Matrix ctm;
  final int fill;
  final int stroke;
  final double lineWidth;
  final double fontSize;
  final _FontRes? font;
  final int lineCap;
  final int lineJoin;
  final double miter;
  final List<double> dash;
  final double dashPhase;
  final PdfBlendMode blend;
  final int textRender;
}

class _Dict {
  _Dict(this.values);
  final Map<String, Object> values;
  Object? operator [](String key) => values[key];
}

class _Name {
  _Name(this.value);
  final String value;
}

class _Hex {
  _Hex(this.bytes);
  final Uint8List bytes;
}

class _Lit {
  _Lit(this.bytes);
  final Uint8List bytes;
}

class _Tok {
  _Tok.op(this.op) : value = null;
  _Tok.val(this.value) : op = null;
  final String? op;
  final Object? value;
}

class _Lexer {
  _Lexer(this.bytes);
  final Uint8List bytes;
  var _i = 0;

  void skipWs() => _skip();

  Uint8List take(int n) {
    final int end = (_i + n).clamp(0, bytes.length);
    final Uint8List out = Uint8List.sublistView(bytes, _i, end);
    _i = end;
    return out;
  }

  _Tok? next() {
    _skip();
    if (_i >= bytes.length) {
      return null;
    }
    final int b = bytes[_i];
    if (b == 0x5B) {
      _i++;
      final List<Object> items = <Object>[];
      while (true) {
        _skip();
        if (_i >= bytes.length) {
          break;
        }
        if (bytes[_i] == 0x5D) {
          _i++;
          return _Tok.val(items);
        }
        final _Tok? t = next();
        if (t == null) {
          break;
        }
        if (t.value != null) {
          items.add(t.value!);
        }
      }
      return _Tok.val(items);
    }
    if (b == 0x2F) {
      _i++;
      final int start = _i;
      while (_i < bytes.length && !_delim(bytes[_i])) {
        _i++;
      }
      return _Tok.val(_Name(String.fromCharCodes(bytes.sublist(start, _i))));
    }
    if (b == 0x3C) {
      if (_i + 1 < bytes.length && bytes[_i + 1] == 0x3C) {
        _i += 2;
        return _Tok.val(_parseDict());
      }
      _i++;
      final int start = _i;
      while (_i < bytes.length && bytes[_i] != 0x3E) {
        _i++;
      }
      final String hex = String.fromCharCodes(bytes.sublist(start, _i));
      if (_i < bytes.length) {
        _i++;
      }
      return _Tok.val(_Hex(_fromHex(hex)));
    }
    if (b == 0x28) {
      return _Tok.val(_Lit(_literal()));
    }
    if (_isOpStart(b) && !_isNum(b)) {
      final int start = _i;
      while (_i < bytes.length && !_delim(bytes[_i]) && !_isNum(bytes[_i]) ||
          (_i > start && bytes[_i] == 0x2A)) {
        if (_delim(bytes[_i]) && bytes[_i] != 0x2A) {
          break;
        }
        _i++;
        if (_i - start > 4) {
          break;
        }
      }
      return _Tok.op(String.fromCharCodes(bytes.sublist(start, _i)));
    }
    if (_isNum(b) || b == 0x2B || b == 0x2D || b == 0x2E) {
      final int start = _i;
      if (b == 0x2B || b == 0x2D) {
        _i++;
      }
      var dot = false;
      while (_i < bytes.length) {
        final int c = bytes[_i];
        if (c >= 0x30 && c <= 0x39) {
          _i++;
          continue;
        }
        if (c == 0x2E && !dot) {
          dot = true;
          _i++;
          continue;
        }
        break;
      }
      return _Tok.val(
        double.tryParse(String.fromCharCodes(bytes.sublist(start, _i))) ?? 0,
      );
    }
    _i++;
    return next();
  }

  _Dict _parseDict() {
    final Map<String, Object> values = <String, Object>{};
    while (true) {
      _skip();
      if (_i + 1 < bytes.length && bytes[_i] == 0x3E && bytes[_i + 1] == 0x3E) {
        _i += 2;
        return _Dict(values);
      }
      if (_i >= bytes.length) {
        return _Dict(values);
      }
      final _Tok? key = next();
      if (key == null) {
        return _Dict(values);
      }
      if (key.value is! _Name) {
        continue;
      }
      _skip();
      if (_i + 1 < bytes.length && bytes[_i] == 0x3E && bytes[_i + 1] == 0x3E) {
        _i += 2;
        return _Dict(values);
      }
      final _Tok? value = next();
      if (value?.value != null) {
        values[(key.value as _Name).value] = value!.value!;
      }
    }
  }

  void _skip() {
    while (_i < bytes.length) {
      final int b = bytes[_i];
      if (b == 0x00 ||
          b == 0x09 ||
          b == 0x0A ||
          b == 0x0C ||
          b == 0x0D ||
          b == 0x20) {
        _i++;
        continue;
      }
      if (b == 0x25) {
        while (_i < bytes.length && bytes[_i] != 0x0A && bytes[_i] != 0x0D) {
          _i++;
        }
        continue;
      }
      return;
    }
  }

  Uint8List _literal() {
    _i++;
    var depth = 1;
    final BytesBuilder buf = BytesBuilder(copy: false);
    while (_i < bytes.length && depth > 0) {
      final int b = bytes[_i++];
      if (b == 0x5C && _i < bytes.length) {
        final int n = bytes[_i];
        if (n >= 0x30 && n <= 0x37) {
          var v = 0;
          for (int k = 0; k < 3 && _i < bytes.length; k++) {
            final int d = bytes[_i];
            if (d < 0x30 || d > 0x37) {
              break;
            }
            v = (v << 3) | (d - 0x30);
            _i++;
          }
          buf.addByte(v & 0xFF);
          continue;
        }
        _i++;
        buf.addByte(switch (n) {
          0x6E => 0x0A,
          0x72 => 0x0D,
          0x74 => 0x09,
          0x62 => 0x08,
          0x66 => 0x0C,
          _ => n,
        });
        continue;
      }
      if (b == 0x28) {
        depth++;
        buf.addByte(b);
        continue;
      }
      if (b == 0x29) {
        depth--;
        if (depth > 0) {
          buf.addByte(b);
        }
        continue;
      }
      buf.addByte(b);
    }
    return buf.takeBytes();
  }

  static Uint8List _fromHex(String hex) {
    final String clean = hex.replaceAll(RegExp(r'\s'), '');
    final Uint8List out = Uint8List((clean.length + 1) ~/ 2);
    for (int i = 0; i < out.length; i++) {
      final int hi = i * 2 < clean.length
          ? int.tryParse(clean[i * 2], radix: 16) ?? 0
          : 0;
      final int lo = i * 2 + 1 < clean.length
          ? int.tryParse(clean[i * 2 + 1], radix: 16) ?? 0
          : 0;
      out[i] = (hi << 4) | lo;
    }
    return out;
  }

  static bool _delim(int b) =>
      b == 0x00 ||
      b == 0x09 ||
      b == 0x0A ||
      b == 0x0C ||
      b == 0x0D ||
      b == 0x20 ||
      b == 0x28 ||
      b == 0x29 ||
      b == 0x3C ||
      b == 0x3E ||
      b == 0x5B ||
      b == 0x5D ||
      b == 0x7B ||
      b == 0x7D ||
      b == 0x2F ||
      b == 0x25;

  static bool _isNum(int b) => b >= 0x30 && b <= 0x39;

  static bool _isOpStart(int b) =>
      (b >= 0x41 && b <= 0x5A) ||
      (b >= 0x61 && b <= 0x7A) ||
      b == 0x27 ||
      b == 0x22;
}
