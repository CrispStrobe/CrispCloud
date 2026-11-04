import 'dart:convert';
import 'dart:typed_data';

import '../cos/pdf_cos.dart';
import '../cos/pdf_cos_write.dart';
import '../model/pdf_annot.dart';
import '../model/pdf_file.dart';
import '../model/pdf_form.dart';
import '../model/pdf_page_info.dart';
import 'pdf_appearance.dart';

/// Appends annotation / form / page-tree updates (ISO 32000-1 §7.5.6).
abstract final class PdfIncrementalSave {
  /// write API.
  static Uint8List write({
    required Uint8List originalBytes,
    required PdfFile file,
  }) {
    if (file.permissions != null &&
        !file.permissions!.canAnnotate &&
        !file.permissions!.canModify) {
      throw StateError('PDF permissions forbid modify/annotate');
    }
    int next = file.nextObjectId;
    final BytesBuilder body = BytesBuilder();
    final List<(int, int)> newObjs = <(int, int)>[];

    void writeBytes(int id, List<int> dictOrStream) {
      final int offset = originalBytes.length + body.length;
      newObjs.add((id, offset));
      body.add(utf8.encode('$id 0 obj\n'));
      body.add(dictOrStream);
      body.add(utf8.encode('\nendobj\n'));
    }

    void writeObj(int id, String dict) => writeBytes(id, utf8.encode(dict));

    final List<int> kidIds = <int>[];
    for (final PdfPageRec rec in file.pageRecs) {
      final List<int> annotIds = <int>[];
      for (final PdfAnnot annot in rec.annots) {
        if (annot.objectId != null && !rec.dirty) {
          annotIds.add(annot.objectId!);
          continue;
        }
        if (annot.objectId != null) {
          annotIds.add(annot.objectId!);
          continue;
        }
        final int apStart = next;
        final PdfAppearanceBundle ap = annot.subtype == 'FreeText'
            ? PdfAppearance.text(
                startId: apStart,
                width: annot.rect.width,
                height: annot.rect.height,
                text: annot.contents,
                colorArgb: annot.color,
                font: file.appearanceFont,
                rtl: _looksRtl(annot.contents),
              )
            : PdfAppearance.text(
                startId: apStart,
                width: annot.rect.width,
                height: annot.rect.height,
                text: '',
                colorArgb: annot.color,
              );
        next = ap.nextId;
        for (final PdfAppearanceObj obj in ap.objects) {
          writeBytes(obj.id, obj.body);
        }
        final int id = next++;
        annot.objectId = id;
        annotIds.add(id);
        writeObj(id, _annotDict(annot, ap.formId, rec.info.cropBox));
      }

      final bool newPage = rec.objectId == null;
      if (newPage) {
        final int contentId = next++;
        final Uint8List content = rec.pendingContent ?? Uint8List(0);
        writeBytes(
          contentId,
          PdfCosWrite.encode(
            PdfCosStream(
              PdfCosDict(<String, PdfCos>{'Length': PdfCosInt(content.length)}),
              content,
            ),
          ),
        );
        final int pageId = next++;
        rec.objectId = pageId;
        rec.dict['Type'] = const PdfCosName('Page');
        rec.dict['Parent'] = PdfCosRef(file.pagesObjectId);
        rec.dict['MediaBox'] = PdfCosArray(<PdfCos>[
          const PdfCosReal(0),
          const PdfCosReal(0),
          PdfCosReal(rec.info.mediaBox.width),
          PdfCosReal(rec.info.mediaBox.height),
        ]);
        rec.dict['Rotate'] = PdfCosInt(rec.info.rotate);
        rec.dict['Resources'] = rec.dict['Resources'] ?? PdfCosDict();
        rec.dict['Contents'] = PdfCosRef(contentId);
      }

      if (rec.dirty || file.treeDirty || newPage) {
        rec.dict['Rotate'] = PdfCosInt(rec.info.rotate);
        if (annotIds.isNotEmpty) {
          rec.dict['Annots'] = PdfCosArray(<PdfCos>[
            for (final int id in annotIds) PdfCosRef(id),
          ]);
        }
        if (file.pagesObjectId > 0) {
          rec.dict['Parent'] = PdfCosRef(file.pagesObjectId);
        }
        if (rec.objectId != null) {
          writeObj(rec.objectId!, PdfCosWrite.encodeDict(rec.dict));
        }
      }
      if (rec.objectId != null) {
        kidIds.add(rec.objectId!);
      }
    }

    for (final PdfFormField field in file.form.fields) {
      if (field.objectId == null || field.readOnly) {
        continue;
      }
      final PdfCosDict? existing = file.store.asDict(
        PdfCosRef(field.objectId!),
      );
      int? apId;
      if (field.type == 'Tx' &&
          file.appearanceFont != null &&
          existing != null) {
        final ({double llx, double lly, double urx, double ury})? r =
            pdfCosRect(existing['Rect']);
        final double w = r == null ? 160 : (r.urx - r.llx).abs();
        final double h = r == null ? 18 : (r.ury - r.lly).abs();
        final PdfAppearanceBundle ap = PdfAppearance.text(
          startId: next,
          width: w,
          height: h,
          text: field.value,
          colorArgb: 0xFFFFFFFF,
          font: file.appearanceFont,
          rtl: _looksRtl(field.value),
        );
        next = ap.nextId;
        for (final PdfAppearanceObj obj in ap.objects) {
          writeBytes(obj.id, obj.body);
        }
        apId = ap.formId;
      }
      if (existing != null) {
        final StringBuffer dict = StringBuffer('<<');
        existing.values.forEach((String key, PdfCos value) {
          if (key == 'T' || key == 'V' || key == 'FT' || key == 'AP') {
            return;
          }
          dict.write('/$key ${utf8.decode(PdfCosWrite.encode(value))}');
        });
        dict.write(
          '/T ${_pdfText(field.name)}/V ${_pdfText(field.value)}'
          '/FT /${field.type}',
        );
        if (apId != null) {
          dict.write('/AP <</N $apId 0 R>>');
        }
        dict.write('>>');
        writeObj(field.objectId!, dict.toString());
      } else {
        writeObj(
          field.objectId!,
          '<</T ${_pdfText(field.name)}/V ${_pdfText(field.value)}'
          '/FT /${field.type}>>',
        );
      }
    }

    if (file.treeDirty && file.pagesObjectId > 0) {
      writeObj(
        file.pagesObjectId,
        PdfCosWrite.encodeDict(
          PdfCosDict(<String, PdfCos>{
            'Type': const PdfCosName('Pages'),
            'Kids': PdfCosArray(<PdfCos>[
              for (final int id in kidIds) PdfCosRef(id),
            ]),
            'Count': PdfCosInt(kidIds.length),
          }),
        ),
      );
    }

    if (file.infoDirty) {
      final int infoId = file.infoObjectId ?? next++;
      file.infoObjectId = infoId;
      writeObj(
        infoId,
        PdfCosWrite.encodeDict(
          PdfCosDict(<String, PdfCos>{
            if (file.info.title.isNotEmpty)
              'Title': PdfCosString(Uint8List.fromList(utf8.encode(file.info.title))),
            if (file.info.author.isNotEmpty)
              'Author': PdfCosString(Uint8List.fromList(utf8.encode(file.info.author))),
            if (file.info.subject.isNotEmpty)
              'Subject': PdfCosString(Uint8List.fromList(utf8.encode(file.info.subject))),
          }),
        ),
      );
    }

    final int rootId = file.catalogObjectId;
    final int prev = _lastStartXref(originalBytes);
    final int size = next;
    final int xrefAt = originalBytes.length + body.length;
    final StringBuffer xref = StringBuffer('xref\n0 1\n0000000000 65535 f \n');
    if (newObjs.isNotEmpty) {
      newObjs.sort((a, b) => a.$1 - b.$1);
      var runStart = 0;
      while (runStart < newObjs.length) {
        var runEnd = runStart;
        while (runEnd + 1 < newObjs.length &&
            newObjs[runEnd + 1].$1 == newObjs[runEnd].$1 + 1) {
          runEnd++;
        }
        xref.write('${newObjs[runStart].$1} ${runEnd - runStart + 1}\n');
        for (int i = runStart; i <= runEnd; i++) {
          xref.write('${newObjs[i].$2.toString().padLeft(10, '0')} 00000 n \n');
        }
        runStart = runEnd + 1;
      }
    }
    final String infoRef = file.infoObjectId == null
        ? ''
        : '/Info ${file.infoObjectId} 0 R';
    xref.write(
      'trailer\n<</Size $size/Root $rootId 0 R/Prev $prev$infoRef>>\n'
      'startxref\n$xrefAt\n%%EOF\n',
    );
    body.add(utf8.encode(xref.toString()));

    final Uint8List extra = body.takeBytes();
    final Uint8List out = Uint8List(originalBytes.length + extra.length);
    out.setAll(0, originalBytes);
    out.setAll(originalBytes.length, extra);
    return out;
  }

  static String _annotDict(PdfAnnot annot, int apId, PdfBox crop) {
    final double llx = annot.rect.x + crop.llx;
    final double ury = crop.ury - annot.rect.y;
    final double urx = llx + annot.rect.width;
    final double lly = ury - annot.rect.height;
    final StringBuffer buf = StringBuffer(
      '<</Type /Annot/Subtype /${annot.subtype}'
      '/Rect [$llx $lly $urx $ury]'
      '/C [${_rgb(annot.color)}]',
    );
    if (annot.contents.isNotEmpty) {
      buf.write('/Contents ${_pdfText(annot.contents)}');
    }
    if (annot.uri != null) {
      buf.write('/A <</S /URI/URI ${_lit(annot.uri!)}>>');
    }
    if (annot.quads.isNotEmpty) {
      buf.write('/QuadPoints [');
      for (final PdfQuad q in annot.quads) {
        buf.write(
          '${q.x1 + crop.llx} ${crop.ury - q.y1} '
          '${q.x2 + crop.llx} ${crop.ury - q.y2} '
          '${q.x3 + crop.llx} ${crop.ury - q.y3} '
          '${q.x4 + crop.llx} ${crop.ury - q.y4} ',
        );
      }
      buf.write(']');
    }
    if (annot.ink.isNotEmpty) {
      buf.write('/InkList [');
      for (final List<PdfPoint> stroke in annot.ink) {
        buf.write('[');
        for (final PdfPoint p in stroke) {
          buf.write('${p.x} ${p.y} ');
        }
        buf.write(']');
      }
      buf.write(']');
    }
    buf.write('/AP <</N $apId 0 R>>>>');
    return buf.toString();
  }

  static bool _looksRtl(String text) {
    for (final int cp in text.runes) {
      if ((cp >= 0x0590 && cp <= 0x08FF) ||
          (cp >= 0xFB1D && cp <= 0xFDFF) ||
          (cp >= 0xFE70 && cp <= 0xFEFF)) {
        return true;
      }
    }
    return false;
  }

  static Uint8List _unicodeBytes(String text) {
    final BytesBuilder out = BytesBuilder();
    out.addByte(0xFE);
    out.addByte(0xFF);
    for (final int unit in text.codeUnits) {
      out.addByte((unit >> 8) & 0xFF);
      out.addByte(unit & 0xFF);
    }
    return out.takeBytes();
  }

  static String _pdfText(String text) {
    var ascii = true;
    for (final int unit in text.codeUnits) {
      if (unit > 127) {
        ascii = false;
        break;
      }
    }
    if (ascii) {
      return _lit(text);
    }
    final StringBuffer hex = StringBuffer('<');
    for (final int b in _unicodeBytes(text)) {
      hex.write(b.toRadixString(16).padLeft(2, '0'));
    }
    hex.write('>');
    return hex.toString();
  }

  static String _rgb(int argb) {
    final double r = ((argb >> 16) & 0xFF) / 255.0;
    final double g = ((argb >> 8) & 0xFF) / 255.0;
    final double b = (argb & 0xFF) / 255.0;
    return '$r $g $b';
  }

  static String _lit(String text) {
    final String escaped = text
        .replaceAll('\\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
    return '($escaped)';
  }

  static int _lastStartXref(Uint8List bytes) {
    final Uint8List needle = Uint8List.fromList('startxref'.codeUnits);
    for (int i = bytes.length - needle.length; i >= 0; i--) {
      var ok = true;
      for (int j = 0; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        var k = i + needle.length;
        while (k < bytes.length && bytes[k] <= 0x20) {
          k++;
        }
        final int start = k;
        while (k < bytes.length && bytes[k] >= 0x30 && bytes[k] <= 0x39) {
          k++;
        }
        return int.tryParse(String.fromCharCodes(bytes.sublist(start, k))) ?? 0;
      }
    }
    return 0;
  }
}
