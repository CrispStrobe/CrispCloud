import 'dart:convert';
import 'dart:typed_data';

import '../../../fonts/sfnt_parser.dart';
import '../cos/pdf_cos.dart';
import '../cos/pdf_cos_write.dart';
import '../cos/pdf_store.dart';
import '../model/pdf_file.dart';
import '../model/pdf_page_info.dart';
import 'pdf_page_view.dart';

/// One page to emit, from an open file or a blank sheet.
class PdfGraftSlot {
  /// PdfGraftSlot API.
  const PdfGraftSlot.page(
    this.file,
    this.index, {
    this.extraRotate = 0,
    this.overlay,
    this.overlayOpacity = 1,
    this.cropLeft = 0,
    this.cropBottom = 0,
    this.cropRight = 0,
    this.cropTop = 0,
    this.embeddedFont,
  }) : width = 0,
       height = 0,
       blank = false;

  /// Blank sheet. Does not change orientation of neighbouring pages.
  const PdfGraftSlot.blank({this.width = 595.28, this.height = 841.89})
    : file = null,
      index = 0,
      extraRotate = 0,
      overlay = null,
      overlayOpacity = 1,
      cropLeft = 0,
      cropBottom = 0,
      cropRight = 0,
      cropTop = 0,
      embeddedFont = null,
      blank = true;

  /// file API.
  final PdfFile? file;

  /// Zero-based page index in [file].
  final int index;

  /// Added to the page's `/Rotate`, in 90° steps. Does not edit MediaBox.
  final int extraRotate;

  /// Extra content stream painted after the page (stamp, numbers).
  /// Helvetica unless [embeddedFont] is set.
  final String? overlay;

  /// Subset TrueType used as `/QzF` when the overlay shows glyph ids.
  final Uint8List? embeddedFont;

  /// `/ca` and `/CA` for [overlay]. Viewers that honor ExtGState use this.
  final double overlayOpacity;

  /// Insets applied to CropBox, in unrotated PDF points. MediaBox stays.
  final double cropLeft;

  /// cropBottom API.
  final double cropBottom;

  /// cropRight API.
  final double cropRight;

  /// cropTop API.
  final double cropTop;

  /// blank API.
  final bool blank;

  /// width API.
  final double width;

  /// height API.
  final double height;
}

/// Writes a new PDF whose pages carry their fonts, images, and other resources.
abstract final class PdfPageGraft {
  /// Assembles [slots] into a standalone PDF 1.7 file.
  static Uint8List write(List<PdfGraftSlot> slots) {
    if (slots.isEmpty) {
      throw ArgumentError('at least one page is required');
    }
    final _Assembler asm = _Assembler();
    final List<int> kids = <int>[];
    for (final PdfGraftSlot slot in slots) {
      kids.add(
        slot.blank ? asm.blank(slot.width, slot.height) : asm.page(slot),
      );
    }
    return asm.finish(kids);
  }
}

class _Assembler {
  static const int _catalogId = 1;
  static const int _pagesId = 2;

  int _next = 3;
  final Map<String, int> _ids = <String, int>{};
  final Map<int, PdfCos> _bodies = <int, PdfCos>{};

  int page(PdfGraftSlot slot) {
    final PdfFile file = slot.file!;
    final PdfPageRec rec = file.pageRec(slot.index);
    final PdfCosDict cloned = _rewriteDict(
      file.store,
      rec.dict,
      skip: const <String>{'Parent'},
    );
    cloned['Type'] = const PdfCosName('Page');
    cloned['Parent'] = const PdfCosRef(_pagesId);
    cloned['MediaBox'] = _box(rec.info.mediaBox);
    cloned['CropBox'] = _box(rec.info.cropBox);
    final int turn = PdfPageView.normalizeQuarter(
      rec.info.rotate + slot.extraRotate,
    );
    if (turn == 0) {
      cloned.values.remove('Rotate');
    } else {
      cloned['Rotate'] = PdfCosInt(turn);
    }
    if (cloned['Resources'] == null) {
      final PdfCos? inherited = _inheritedResources(file.store, rec.dict);
      if (inherited != null) {
        cloned['Resources'] = _rewrite(file.store, inherited);
      }
    }
    _applyCrop(cloned, rec.info, slot);
    if (rec.pendingContent != null) {
      final int contentId = _next++;
      _bodies[contentId] = PdfCosStream(
        PdfCosDict(<String, PdfCos>{}),
        rec.pendingContent!,
      );
      cloned['Contents'] = PdfCosRef(contentId);
    }
    final String? overlay = slot.overlay;
    if (overlay != null && overlay.isNotEmpty) {
      _appendOverlay(cloned, overlay, slot.overlayOpacity, slot);
    }
    final int id = _next++;
    _bodies[id] = cloned;
    return id;
  }

  int blank(double width, double height) {
    final int contentId = _next++;
    _bodies[contentId] = PdfCosStream(
      PdfCosDict(<String, PdfCos>{}),
      Uint8List(0),
    );
    final int id = _next++;
    _bodies[id] = PdfCosDict(<String, PdfCos>{
      'Type': const PdfCosName('Page'),
      'Parent': const PdfCosRef(_pagesId),
      'MediaBox': PdfCosArray(<PdfCos>[
        const PdfCosReal(0),
        const PdfCosReal(0),
        PdfCosReal(width),
        PdfCosReal(height),
      ]),
      'Resources': PdfCosDict(),
      'Contents': PdfCosRef(contentId),
    });
    return id;
  }

  Uint8List finish(List<int> kids) {
    final BytesBuilder out = BytesBuilder();
    out.add(utf8.encode('%PDF-1.7\n%\xE2\xE3\xCF\xD3\n'));
    final Map<int, int> xref = <int, int>{};
    void obj(int id, PdfCos body) {
      xref[id] = out.length;
      out.add(utf8.encode('$id 0 obj\n'));
      out.add(PdfCosWrite.encode(body));
      out.add(utf8.encode('\nendobj\n'));
    }

    obj(
      _pagesId,
      PdfCosDict(<String, PdfCos>{
        'Type': const PdfCosName('Pages'),
        'Kids': PdfCosArray(<PdfCos>[for (final int id in kids) PdfCosRef(id)]),
        'Count': PdfCosInt(kids.length),
      }),
    );
    obj(
      _catalogId,
      PdfCosDict(<String, PdfCos>{
        'Type': const PdfCosName('Catalog'),
        'Pages': const PdfCosRef(_pagesId),
      }),
    );
    final List<int> ids = _bodies.keys.toList()..sort();
    for (final int id in ids) {
      obj(id, _bodies[id]!);
    }
    final int xrefAt = out.length;
    final int size = _next;
    final StringBuffer table = StringBuffer('xref\n0 $size\n');
    table.write('0000000000 65535 f \n');
    for (int id = 1; id < size; id++) {
      final int at = xref[id] ?? 0;
      table.write('${at.toString().padLeft(10, '0')} 00000 n \n');
    }
    table.write(
      'trailer\n<</Size $size/Root 1 0 R>>\nstartxref\n$xrefAt\n%%EOF\n',
    );
    out.add(utf8.encode(table.toString()));
    return out.takeBytes();
  }

  PdfCos _rewrite(PdfCosStore store, PdfCos value) {
    if (value is PdfCosRef) {
      return PdfCosRef(_take(store, value.id));
    }
    if (value is PdfCosDict) {
      return _rewriteDict(store, value);
    }
    if (value is PdfCosArray) {
      return PdfCosArray(<PdfCos>[
        for (final PdfCos item in value.items) _rewrite(store, item),
      ]);
    }
    if (value is PdfCosStream) {
      return PdfCosStream(_rewriteDict(store, value.dict), value.raw);
    }
    return value;
  }

  PdfCosDict _rewriteDict(
    PdfCosStore store,
    PdfCosDict dict, {
    Set<String> skip = const <String>{'Parent', 'P'},
  }) {
    final PdfCosDict out = PdfCosDict();
    dict.values.forEach((String key, PdfCos item) {
      if (skip.contains(key)) {
        return;
      }
      out[key] = _rewrite(store, item);
    });
    return out;
  }

  int _take(PdfCosStore store, int id) {
    if (_ids.length > 8000) {
      throw StateError('page graft exceeded 8000 objects');
    }
    final String key = '${identityHashCode(store)}:$id';
    final int? hit = _ids[key];
    if (hit != null) {
      return hit;
    }
    final int neu = _next++;
    _ids[key] = neu;
    final PdfCos? obj = store.get(PdfCosRef(id));
    _bodies[neu] = obj == null ? const PdfCosNull() : _rewrite(store, obj);
    return neu;
  }

  PdfCos? _inheritedResources(PdfCosStore store, PdfCosDict page) {
    PdfCos? node = page['Parent'];
    var guard = 0;
    while (node != null && guard++ < 32) {
      final PdfCosDict? dict = store.asDict(node);
      if (dict == null) {
        return null;
      }
      final PdfCos? resources = dict['Resources'];
      if (resources != null) {
        return resources;
      }
      node = dict['Parent'];
    }
    return null;
  }

  int? _stampFontId;
  int? _embeddedFontId;

  int _embedFace(Uint8List bytes) {
    final SfntFont face = SfntFont.parse(bytes);
    final int fileId = _put(
      PdfCosStream(
        PdfCosDict(<String, PdfCos>{'Length1': PdfCosInt(bytes.length)}),
        bytes,
      ),
    );
    final int units = face.unitsPerEm <= 0 ? 1000 : face.unitsPerEm;
    int pdf(int value) => (value * 1000 / units).round();
    final List<PdfCos> widths = <PdfCos>[];
    for (int gid = 1; gid < face.numGlyphs && gid < 4096; gid++) {
      widths
        ..add(PdfCosInt(gid))
        ..add(PdfCosArray(<PdfCos>[PdfCosInt(pdf(face.advanceWidth(gid)))]));
    }
    final int descriptorId = _put(
      PdfCosDict(<String, PdfCos>{
        'Type': const PdfCosName('FontDescriptor'),
        'FontName': const PdfCosName('QudsStamp'),
        'Flags': const PdfCosInt(4),
        'FontBBox': PdfCosArray(<PdfCos>[
          PdfCosInt(pdf(face.xMin)),
          PdfCosInt(pdf(face.yMin)),
          PdfCosInt(pdf(face.xMax)),
          PdfCosInt(pdf(face.yMax)),
        ]),
        'ItalicAngle': const PdfCosInt(0),
        'Ascent': PdfCosInt(pdf(face.ascender)),
        'Descent': PdfCosInt(pdf(face.descender)),
        'CapHeight': PdfCosInt(pdf(face.capHeight)),
        'StemV': const PdfCosInt(80),
        'FontFile2': PdfCosRef(fileId),
      }),
    );
    final int cidId = _put(
      PdfCosDict(<String, PdfCos>{
        'Type': const PdfCosName('Font'),
        'Subtype': const PdfCosName('CIDFontType2'),
        'BaseFont': const PdfCosName('QudsStamp'),
        'CIDSystemInfo': PdfCosDict(<String, PdfCos>{
          'Registry': PdfCosString(Uint8List.fromList(utf8.encode('Adobe'))),
          'Ordering': PdfCosString(Uint8List.fromList(utf8.encode('Identity'))),
          'Supplement': const PdfCosInt(0),
        }),
        'FontDescriptor': PdfCosRef(descriptorId),
        'DW': const PdfCosInt(500),
        'W': PdfCosArray(widths),
        'CIDToGIDMap': const PdfCosName('Identity'),
      }),
    );
    return _put(
      PdfCosDict(<String, PdfCos>{
        'Type': const PdfCosName('Font'),
        'Subtype': const PdfCosName('Type0'),
        'BaseFont': const PdfCosName('QudsStamp'),
        'Encoding': const PdfCosName('Identity-H'),
        'DescendantFonts': PdfCosArray(<PdfCos>[PdfCosRef(cidId)]),
      }),
    );
  }

  void _applyCrop(PdfCosDict page, PdfPageInfo info, PdfGraftSlot slot) {
    if (slot.cropLeft == 0 &&
        slot.cropBottom == 0 &&
        slot.cropRight == 0 &&
        slot.cropTop == 0) {
      return;
    }
    final PdfBox box = info.cropBox;
    final double llx = box.llx + slot.cropLeft;
    final double lly = box.lly + slot.cropBottom;
    final double urx = box.urx - slot.cropRight;
    final double ury = box.ury - slot.cropTop;
    if (urx - llx < 1 || ury - lly < 1) {
      throw ArgumentError('crop leaves no visible page');
    }
    page['CropBox'] = PdfCosArray(<PdfCos>[
      PdfCosReal(llx),
      PdfCosReal(lly),
      PdfCosReal(urx),
      PdfCosReal(ury),
    ]);
  }

  void _appendOverlay(
    PdfCosDict page,
    String overlay,
    double opacity,
    PdfGraftSlot slot,
  ) {
    final PdfCosDict resources = _privateDict(page, 'Resources');
    final PdfCosDict fonts = _privateDict(resources, 'Font');
    final Uint8List? embedded = slot.embeddedFont;
    if (embedded != null) {
      _embeddedFontId ??= _embedFace(embedded);
      fonts['QzF'] = PdfCosRef(_embeddedFontId!);
    } else {
      _stampFontId ??= _put(
        PdfCosDict(<String, PdfCos>{
          'Type': const PdfCosName('Font'),
          'Subtype': const PdfCosName('Type1'),
          'BaseFont': const PdfCosName('Helvetica'),
        }),
      );
      fonts['QzF'] = PdfCosRef(_stampFontId!);
    }
    final double alpha = opacity.clamp(0.0, 1.0);
    final int gs = _put(
      PdfCosDict(<String, PdfCos>{
        'Type': const PdfCosName('ExtGState'),
        'ca': PdfCosReal(alpha),
        'CA': PdfCosReal(alpha),
      }),
    );
    final PdfCosDict states = _privateDict(resources, 'ExtGState');
    states['QzG'] = PdfCosRef(gs);
    final int contentId = _put(
      PdfCosStream(PdfCosDict(), Uint8List.fromList(utf8.encode(overlay))),
    );
    final PdfCos? existing = page['Contents'];
    if (existing == null) {
      page['Contents'] = PdfCosRef(contentId);
      return;
    }
    if (existing is PdfCosArray) {
      page['Contents'] = PdfCosArray(<PdfCos>[
        ...existing.items,
        PdfCosRef(contentId),
      ]);
      return;
    }
    page['Contents'] = PdfCosArray(<PdfCos>[existing, PdfCosRef(contentId)]);
  }

  PdfCosDict _privateDict(PdfCosDict parent, String key) {
    final PdfCosDict source = _asDict(parent[key]) ?? PdfCosDict();
    final PdfCosDict copy = PdfCosDict(Map<String, PdfCos>.of(source.values));
    parent[key] = copy;
    return copy;
  }

  PdfCosDict? _asDict(PdfCos? value) {
    if (value is PdfCosDict) {
      return value;
    }
    if (value is PdfCosRef) {
      final PdfCos? body = _bodies[value.id];
      if (body is PdfCosDict) {
        return body;
      }
    }
    return null;
  }

  int _put(PdfCos body) {
    final int id = _next++;
    _bodies[id] = body;
    return id;
  }

  PdfCosArray _box(PdfBox box) {
    return PdfCosArray(<PdfCos>[
      PdfCosReal(box.llx),
      PdfCosReal(box.lly),
      PdfCosReal(box.urx),
      PdfCosReal(box.ury),
    ]);
  }
}
