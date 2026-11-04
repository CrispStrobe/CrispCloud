import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/pdf/file/crypto/pdf_rc4.dart';
import 'package:quds_office_engine/src/pdf/file/decode/pdf_ccitt.dart';
import 'package:quds_office_engine/src/pdf/file/text/pdf_cff_host.dart';
import 'package:quds_office_engine/src/pdf/file/text/pdf_std14.dart';
import 'package:quds_office_engine/src/pdf/file/text/pdf_tounicode.dart';
import 'package:test/test.dart';

void main() {
  Uint8List writerPdf() {
    final PdfDocument doc = PdfDocument(title: 'PDF file test', author: 'Quds');
    final PdfCanvas canvas = PdfCanvas(595.28, 841.89)
      ..setFillColor('2B579A')
      ..rect(72, 72, 200, 40)
      ..fill();
    canvas.showLatin(
      x: 72,
      y: 140,
      fontSize: 14,
      text: 'Hello PDF',
      color: '000000',
    );
    canvas.endText();
    doc.addPage(
      PdfPage(width: 595.28, height: 841.89, content: canvas.toStream()),
    );
    return doc.save();
  }

  test('opens writer output and reads catalog pages', () {
    final Uint8List bytes = writerPdf();
    final PdfFile file = PdfFile.open(bytes);
    expect(file.version, '1.7');
    expect(file.pageCount, 1);
    expect(file.pageAt(0).width, closeTo(595.28, 0.5));
    expect(file.info.title, 'PDF file test');
    expect(file.encrypted, isFalse);
  });

  test('display list paints paths from writer streams', () {
    final PdfFile file = PdfFile.open(writerPdf());
    final PdfDisplayList list = file.displayList(0);
    expect(list.ops.whereType<PdfFillPath>(), isNotEmpty);
    final String painted = list.ops
        .whereType<PdfDrawText>()
        .map((PdfDrawText t) => t.text)
        .join();
    expect(painted, contains('Hello'));
    expect(
      list.ops.whereType<PdfDrawText>().first.size,
      closeTo(14, 0.6),
    );
  });

  test('text size follows Tm when Tf is 1', () {
    final PdfFile file = PdfFile.open(_tmScalePdf());
    final List<PdfDrawText> texts =
        file.displayList(0).ops.whereType<PdfDrawText>().toList();
    expect(texts, isNotEmpty);
    expect(texts.map((PdfDrawText t) => t.text).join(), contains('Hello'));
    expect(texts.first.size, closeTo(18, 0.3));
  });

  test('extract and find see ToUnicode or fallback text', () {
    final PdfFile file = PdfFile.open(writerPdf());
    final List<OfficeFindHit> hits = OfficeFind.inPdf(
      file,
      const OfficeFindOptions(query: 'Hello'),
    );
    expect(hits, isNotEmpty);
    expect(file.pageCount, 1);
    expect(OfficeTextStats.ofPdf(file).pages, 1);
    expect(hits, isA<List<OfficeFindHit>>());
  });

  test('incremental highlight save reopens', () {
    final Uint8List bytes = writerPdf();
    final PdfFile file = PdfFile.open(bytes);
    file.addAnnot(
      0,
      PdfAnnot(
        id: 0,
        subtype: 'Highlight',
        rect: const PdfRect(x: 72, y: 72, width: 80, height: 16),
        contents: 'note',
      ),
    );
    final Uint8List saved = PdfIncrementalSave.write(
      originalBytes: bytes,
      file: file,
    );
    expect(saved.length, greaterThan(bytes.length));
    final PdfFile again = PdfFile.open(saved);
    expect(again.pageCount, 1);
    expect(again.annotsOn(0), isNotEmpty);
    expect(utf8.decode(saved, allowMalformed: true), contains('/AP'));
  });

  test('AcroForm fill persists after incremental save', () {
    final Uint8List bytes = acroFormPdf();
    final PdfFile file = PdfFile.open(bytes);
    expect(file.form.field('Name')?.value, 'Ada');
    file.form.field('Name')!.value = 'Grace';
    file.markDirty(0);
    final PdfFile again = PdfFile.open(
      PdfIncrementalSave.write(originalBytes: bytes, file: file),
    );
    expect(again.form.field('Name')?.value, 'Grace');
  });

  test('merge extract rotate persist', () {
    final PdfFile a = PdfFile.open(writerPdf());
    final PdfFile b = PdfFile.open(writerPdf());
    a.appendPages(b);
    expect(a.pageCount, 2);
    a.rotatePage(1, 90);
    final Uint8List extracted = a.extractPages(<int>[1]);
    final PdfFile one = PdfFile.open(extracted);
    expect(one.pageCount, 1);
    expect(one.pageAt(0).rotate, 90);
    final Uint8List saved = PdfIncrementalSave.write(
      originalBytes: a.originalBytes,
      file: a,
    );
    final PdfFile merged = PdfFile.open(saved);
    expect(merged.pageCount, 2);
  });

  test('XFDF export import and redact stay typed', () {
    final PdfFile file = PdfFile.open(writerPdf());
    file.addAnnot(
      0,
      PdfAnnot(
        id: 0,
        subtype: 'Highlight',
        rect: const PdfRect(x: 10, y: 10, width: 20, height: 8),
        contents: 'hi',
      ),
    );
    final String xfdf = PdfXfdf.exportXml(file);
    expect(xfdf, contains('highlight'));
    final PdfFile other = PdfFile.open(writerPdf());
    PdfXfdf.importXml(other, xfdf);
    expect(other.annotsOn(0), isNotEmpty);
    file.redactRect(
      0,
      const PdfRect(x: 72, y: 140, width: 80, height: 16),
      mode: PdfRedactMode.removeContent,
    );
    expect(file.redactions, isNotEmpty);
    expect(file.pdfAProfile, isNull);
    expect(file.signatures, isEmpty);
    expect(file.incrementalSaveWarnsPdfA, isFalse);
  });

  test('OfficeTextExtractor detects PDF', () {
    final OfficeTextExtract extracted = OfficeTextExtractor.extract(
      writerPdf(),
      name: 'a.pdf',
    );
    expect(extracted.kind, OfficeExtractKind.pdf);
  });

  test('bad header is typed', () {
    expect(
      () => PdfFile.open(Uint8List.fromList(<int>[0, 1, 2, 3])),
      throwsA(
        isA<PdfOpenException>().having(
          (PdfOpenException e) => e.error,
          'error',
          PdfOpenError.badHeader,
        ),
      ),
    );
  });

  test('page insert delete rotate stay typed', () {
    final PdfFile file = PdfFile.open(writerPdf());
    file.insertBlankPage(1, width: 842, height: 595);
    expect(file.pageCount, 2);
    file.rotatePage(1, 90);
    expect(file.pageAt(1).rotate, 90);
    file.deletePage(1);
    expect(file.pageCount, 1);
  });

  test('isolate open returns payload', () async {
    final PdfOpenPayload payload = await OfficeIsolateOpen.pdf(writerPdf());
    expect(payload.file.pageCount, 1);
    expect(payload.lists, isNotEmpty);
  });

  test('encrypted Rev2 opens with password and fails without', () {
    final Uint8List bytes = encryptedRev2Pdf('secret');
    expect(
      () => PdfFile.open(bytes),
      throwsA(
        isA<PdfOpenException>().having(
          (PdfOpenException e) => e.error,
          'error',
          PdfOpenError.encrypted,
        ),
      ),
    );
    expect(
      () => PdfFile.open(bytes, password: 'nope'),
      throwsA(
        isA<PdfOpenException>().having(
          (PdfOpenException e) => e.error,
          'error',
          PdfOpenError.wrongPassword,
        ),
      ),
    );
    final PdfFile file = PdfFile.open(bytes, password: 'secret');
    expect(file.encrypted, isTrue);
    expect(file.pageCount, 1);
    expect(file.info.title, 'Secret');
  });

  test('truncated xref repairs from obj markers', () {
    final Uint8List bytes = writerPdf();
    final int xrefAt = _indexOf(bytes, 'xref');
    expect(xrefAt, greaterThan(0));
    final PdfFile file = PdfFile.open(bytes.sublist(0, xrefAt));
    expect(file.pageCount, 1);
  });

  test('OfficePdfExport.word opens as PdfFile', () {
    final SfntFont? font = _tryFont();
    if (font == null) {
      return;
    }
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(
              inlines: <WmlInline>[WmlRun(text: 'Phase one')],
            ),
          ],
        ),
      ],
    );
    final Uint8List pdf = OfficePdfExport.word(
      doc,
      font: font,
      title: 'Round trip',
    );
    final PdfFile file = PdfFile.open(pdf);
    expect(file.pageCount, greaterThan(0));
    expect(file.info.title, 'Round trip');
    expect(PdfExtract.documentText(file), contains('Phase'));
  });

  test('FlateDecode does not strip DEFLATE payload as Adler-32', () {
    final Uint8List raw = Uint8List.fromList(
      _hexToBytes(
        '4889ecc13101000000c2a0f54fed610da0000000000000000000000000000000'
        '0000000000000000000000000000000000000000000000000000000000000000'
        '0000000000000000000000000000000000000000000000000000000000000000'
        '0000000000000000000000000000000000000000000000000000000000000000'
        '000000000000000000000000000000006e000000ffff000000ffffecc1310100'
        '0000c2a0f54f6d0b2fa000000000000000000000000000000000000000000000'
        '0000000000000000b818000000ffff000000ffff03007a77',
      ),
    );
    expect(PdfFlate.decompress(raw).length, 162393);
    expect(
      utf8.decode(PdfFlate.decompress(PdfFlate.compress(utf8.encode('Quds Flate')))),
      'Quds Flate',
    );
  });

  test('Standard 14 widths and WinAnsi map bytes', () {
    expect(PdfStd14.width('Helvetica', 65), 667);
    expect(PdfStd14.width('Courier', 65), 600);
    expect(PdfStd14.unicode(0x80, 'WinAnsiEncoding'), 0x20AC);
    expect(PdfStd14.unicode(0x80, 'MacRomanEncoding'), 0x00C4);
    final PdfFile file = PdfFile.open(_winAnsiPdf());
    final List<PdfDrawText> texts =
        file.displayList(0).ops.whereType<PdfDrawText>().toList();
    expect(texts.map((PdfDrawText t) => t.text).join(), contains('A'));
    expect(texts.map((PdfDrawText t) => t.text).join(), contains('\u20AC'));
    expect(texts.first.size, closeTo(10, 0.3));
    final PdfTextRun run = file.displayList(0).runs.first;
    expect(run.width, closeTo(6.67, 0.2));
  });

  test('CCITT G3 decodes a white row; JBIG2 stays placeholder', () {
    final Uint8List gray = PdfCcitt.decode(
      Uint8List.fromList(<int>[0x98]),
      PdfCosDict(<String, PdfCos>{
        'Columns': const PdfCosInt(8),
        'Rows': const PdfCosInt(1),
        'K': const PdfCosInt(0),
      }),
    );
    expect(gray.length, 8);
    expect(gray.every((int b) => b == 0xFF), isTrue);
    final Uint8List g4 = PdfCcitt.decode(
      Uint8List.fromList(<int>[0x80]),
      PdfCosDict(<String, PdfCos>{
        'Columns': const PdfCosInt(8),
        'Rows': const PdfCosInt(1),
        'K': const PdfCosInt(-1),
      }),
    );
    expect(g4.length, 8);
    expect(g4.every((int b) => b == 0xFF), isTrue);
    final PdfFile file = PdfFile.open(_jbig2Pdf());
    final Iterable<PdfDrawImage> images =
        file.displayList(0).ops.whereType<PdfDrawImage>();
    expect(images, isNotEmpty);
    expect(images.first.placeholder, isTrue);
  });

  test('hidden OCG BDC is skipped; axial sh paints strips', () {
    final PdfFile ocg = PdfFile.open(_ocgPdf());
    expect(ocg.layers, isNotEmpty);
    expect(ocg.layers.first.visible, isFalse);
    final String text = ocg.displayList(0).plainText;
    expect(text, contains('Shown'));
    expect(text, isNot(contains('Hidden')));
    final PdfFile shade = PdfFile.open(_axialPdf());
    expect(shade.displayList(0).ops.whereType<PdfFillPath>().length, greaterThan(4));
  });

  test('struct tree and signature ByteRange statuses', () {
    final PdfFile tagged = PdfFile.open(_structPdf());
    expect(tagged.structTree?.role, 'StructTreeRoot');
    expect(tagged.structTree?.kids, isNotEmpty);
    expect(tagged.structTree!.kids.first.role, 'P');
    expect(tagged.structTree!.kids.first.alt, 'Para');

    final PdfFile broken = PdfFile.open(_sigPdf(validRange: false));
    expect(broken.signatures, isNotEmpty);
    expect(broken.signatures.first.status, PdfSignatureStatus.broken);

    final PdfFile ok = PdfFile.open(_sigPdf(validRange: true));
    expect(ok.signatures.first.status, PdfSignatureStatus.unverified);
    expect(ok.signatures.first.byteRangeLength, greaterThan(0));

    final PdfFile other = PdfFile.open(
      _sigPdf(validRange: true, filter: 'Unknown.Handler'),
    );
    expect(other.signatures.first.status, PdfSignatureStatus.unsupported);
  });

  test('re size follows CTM and W* emits a clip', () {
    final PdfFile file = PdfFile.open(_clipScalePdf());
    final PdfDisplayList list = file.displayList(0);
    expect(list.ops.whereType<PdfClipPath>(), isNotEmpty);
    expect(list.ops.whereType<PdfSaveGState>(), isNotEmpty);
    final PdfFillPath fill = list.ops.whereType<PdfFillPath>().first;
    var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (final PdfPathVerb v in fill.points) {
      if (v.kind == PdfPathKind.close) {
        continue;
      }
      minX = minX < v.x ? minX : v.x;
      minY = minY < v.y ? minY : v.y;
      maxX = maxX > v.x ? maxX : v.x;
      maxY = maxY > v.y ? maxY : v.y;
    }
    expect(maxX - minX, closeTo(100, 0.8));
    expect(maxY - minY, closeTo(100, 0.8));
  });

  test('CFF FontFile3 wraps as OTTO for the host', () {
    final Uint8List ottoIn = Uint8List.fromList(<int>[0x4F, 0x54, 0x54, 0x4F, 0, 0, 0, 0]);
    expect(PdfCffHost.isSfnt(ottoIn), isTrue);
    expect(identical(PdfCffHost.forFlutter(ottoIn), ottoIn), isTrue);

    final Uint8List cff = _minimalCff();
    expect(PdfCffHost.isRawCff(cff), isTrue);
    final Uint8List otto = PdfCffHost.forFlutter(cff);
    expect(otto.sublist(0, 4), <int>[0x4F, 0x54, 0x54, 0x4F]);
    expect(_sfntHas(otto, 'CFF '), isTrue);
    expect(_sfntHas(otto, 'cmap'), isTrue);
    // Host FontLoader rejects truncated `hhea`; keep the table parseable.
    expect(() => SfntFont.parse(otto), returnsNormally);

    final PdfFile file = PdfFile.open(_cffFontPdf(cff));
    final List<PdfDrawText> texts =
        file.displayList(0).ops.whereType<PdfDrawText>().toList();
    expect(texts, isNotEmpty);
    expect(texts.first.fontBytes, isNotNull);
    expect(texts.first.fontBytes!.sublist(0, 4), <int>[0x4F, 0x54, 0x54, 0x4F]);
  });

  test('TrueType subsets without cmap get ToUnicode cmap for the host', () {
    final File pdf = File('/home/mohammed/Desktop/al_tahreer_profile.pdf');
    if (!pdf.existsSync()) {
      return;
    }
    final PdfDisplayList toc =
        PdfFile.open(pdf.readAsBytesSync()).displayLists()[2];
    final List<PdfDrawText> mediums = toc.ops
        .whereType<PdfDrawText>()
        .where(
          (PdfDrawText t) =>
              t.fontFamily.startsWith('Roboto-Medium') && t.fontBytes != null,
        )
        .toList();
    expect(mediums, isNotEmpty);
    for (final PdfDrawText t in mediums) {
      expect(
        _sfntHas(t.fontBytes!, 'cmap'),
        isTrue,
        reason: 'len=${t.fontBytes!.length}',
      );
    }
  });

  test('b/b* keep the path; Tr 3 is extract-only', () {
    final PdfFile file = PdfFile.open(_fillStrokeTrPdf());
    final PdfDisplayList list = file.displayList(0);
    expect(list.ops.whereType<PdfFillPath>(), isNotEmpty);
    expect(list.ops.whereType<PdfStrokePath>(), isNotEmpty);
    final String painted = list.ops
        .whereType<PdfDrawText>()
        .map((PdfDrawText t) => t.text)
        .join();
    expect(painted, contains('Show'));
    expect(painted, isNot(contains('Hide')));
    expect(list.plainText, contains('Hide'));
    expect(list.plainText, contains('Show'));
  });

  test('stroke style, Multiply gs, CMYK and ICCBased images', () {
    final PdfFile stroke = PdfFile.open(_strokeStylePdf());
    final PdfStrokePath s =
        stroke.displayList(0).ops.whereType<PdfStrokePath>().first;
    expect(s.width, closeTo(2, 0.05));
    expect(s.cap, 1);
    expect(s.join, 1);
    expect(s.dash, <double>[3, 1]);

    final PdfFile mul = PdfFile.open(_multiplyPdf());
    final PdfFillPath fill =
        mul.displayList(0).ops.whereType<PdfFillPath>().first;
    expect(fill.blend, PdfBlendMode.multiply);
    expect((fill.color >> 24) & 0xFF, closeTo(128, 2));

    final PdfFile cmyk = PdfFile.open(_cmykImagePdf());
    final PdfDrawImage img =
        cmyk.displayList(0).ops.whereType<PdfDrawImage>().first;
    expect(img.placeholder, isFalse);
    expect(img.bytes.length, 3);
    expect(img.bytes, <int>[255, 255, 255]);

    final PdfFile icc = PdfFile.open(_iccBasedPdf());
    final PdfDrawImage gray =
        icc.displayList(0).ops.whereType<PdfDrawImage>().first;
    expect(gray.bytes.length, 3);
    expect(gray.bytes[0], 0);
  });

  test('ImageMask is a stencil; Indexed uses the palette; 1-bit gray is not inverted', () {
    final PdfFile mask = PdfFile.open(_imageMaskPdf());
    final PdfDrawImage stencil =
        mask.displayList(0).ops.whereType<PdfDrawImage>().first;
    expect(stencil.hasAlpha, isTrue);
    expect(stencil.bytes.length, 8 * 4);
    expect(stencil.bytes.sublist(0, 4), <int>[255, 255, 255, 255]);
    expect(stencil.bytes[7], 0);

    final PdfFile indexed = PdfFile.open(_indexedPdf());
    final PdfDrawImage pal =
        indexed.displayList(0).ops.whereType<PdfDrawImage>().first;
    expect(pal.hasAlpha, isFalse);
    expect(pal.bytes, <int>[0, 255, 0, 255, 0, 0]);

    final PdfFile gray1 = PdfFile.open(_oneBitGrayPdf());
    final PdfDrawImage row =
        gray1.displayList(0).ops.whereType<PdfDrawImage>().first;
    expect(row.bytes.sublist(0, 3), <int>[255, 255, 255]);
    expect(row.bytes.sublist(3, 6), <int>[0, 0, 0]);
  });

  test('JPEG with DCT SMask attaches softMaskJpeg for the host', () {
    final File pdf = File('/home/mohammed/Desktop/al_tahreer_profile.pdf');
    if (!pdf.existsSync()) {
      return;
    }
    final PdfDrawImage logo = PdfFile.open(pdf.readAsBytesSync())
        .displayList(1)
        .ops
        .whereType<PdfDrawImage>()
        .first;
    expect(logo.jpeg, isTrue);
    expect(logo.softMaskJpeg, isNotNull);
    expect(logo.softMaskJpeg!.length, greaterThan(1000));
    expect(logo.softMaskJpeg!.sublist(0, 2), <int>[0xFF, 0xD8]);
    expect(logo.hasAlpha, isTrue);
  });

  test('Identity-H CID literals decode two bytes; ToUnicode skips UTF-32 pad', () {
    final PdfToUnicode padded = PdfToUnicode.parse(
      Uint8List.fromList(utf8.encode(
        '1 beginbfchar\n<0041> <00000041>\nendbfchar\n',
      )),
    );
    expect(padded.mapCid(0x41), 'A');

    final PdfFile file = PdfFile.open(_identityHLiteralPdf());
    final List<PdfDrawText> texts =
        file.displayList(0).ops.whereType<PdfDrawText>().toList();
    expect(texts, isNotEmpty);
    expect(texts.map((PdfDrawText t) => t.text).join(), 'AL');
    expect(texts.map((PdfDrawText t) => t.text).join().codeUnits, <int>[0x41, 0x4C]);
  });

  test('transparency group Form composites with parent ca', () {
    final PdfFile file = PdfFile.open(_groupFormCaPdf());
    final PdfDrawImage img =
        file.displayList(0).ops.whereType<PdfDrawImage>().first;
    expect(img.hasAlpha, isTrue);
    expect(img.bytes.length, 4);
    // Parent /ca 0.35 over fully opaque white stencil → alpha ≈ 89.
    expect(img.bytes[3], closeTo(89, 2));
  });

  test('ActualText, XFA flag, viewer prefs, layer toggle, reading order, radial', () {
    final PdfFile marked = PdfFile.open(_actualTextPdf());
    expect(marked.displayList(0).plainText, contains('CopyMe'));
    expect(marked.displayList(0).plainText, isNot(contains('xx')));
    expect(
      marked.displayList(0).ops
          .whereType<PdfDrawText>()
          .map((PdfDrawText t) => t.text)
          .join(),
      contains('xx'),
    );

    final PdfFile xfa = PdfFile.open(_xfaPdf());
    expect(xfa.form.hasXfa, isTrue);

    final PdfFile prefs = PdfFile.open(_viewerPrefsPdf());
    expect(prefs.viewerPrefs.direction, 'R2L');
    expect(prefs.viewerPrefs.fitWindow, isTrue);
    expect(prefs.viewerPrefs.hideToolbar, isTrue);

    final PdfFile ocg = PdfFile.open(_ocgPdf());
    expect(ocg.displayList(0).plainText, isNot(contains('Hidden')));
    ocg.setLayerVisibleAt(0, true);
    expect(ocg.displayList(0).plainText, contains('Hidden'));

    final PdfFile tagged = PdfFile.open(_structPdf());
    expect(PdfExtract.readingOrder(tagged), contains('Para'));

    final PdfFile radial = PdfFile.open(_radialPdf());
    expect(
      radial.displayList(0).ops.whereType<PdfFillPath>().length,
      greaterThan(4),
    );
  });

  test('outline GoTo named destinations resolve via Names/Dests', () {
    final PdfFile file = PdfFile.open(_namedOutlinePdf());
    expect(file.outline, isNotNull);
    expect(file.outline!.children, isNotEmpty);
    expect(file.outline!.children.first.title, 'Chapter');
    expect(file.outline!.children.first.pageIndex, 1);
  });
}

Uint8List _tmScalePdf() {
  final String content = 'BT /F1 1 Tf 18 0 0 18 72 400 Tm (Hello) Tj ET\n';
  final List<Uint8List> objs = <Uint8List>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    ),
    utf8.encode(
      '5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n',
    ),
  ];
  final BytesBuilder out = BytesBuilder()..add(utf8.encode('%PDF-1.7\n%\n'));
  final List<int> offsets = <int>[];
  for (final Uint8List obj in objs) {
    offsets.add(out.length);
    out.add(obj);
  }
  final int xrefAt = out.length;
  final StringBuffer xref = StringBuffer('xref\n0 6\n0000000000 65535 f \n');
  for (final int off in offsets) {
    xref.write('${off.toString().padLeft(10, '0')} 00000 n \n');
  }
  xref.write('trailer\n<</Size 6/Root 1 0 R>>\nstartxref\n$xrefAt\n%%EOF\n');
  out.add(utf8.encode(xref.toString()));
  return out.takeBytes();
}

Uint8List _pdfObjects(List<String> objs) {
  final BytesBuilder out = BytesBuilder()..add(utf8.encode('%PDF-1.7\n%\n'));
  final List<int> offsets = <int>[];
  for (final String obj in objs) {
    offsets.add(out.length);
    out.add(utf8.encode(obj));
  }
  final int xrefAt = out.length;
  final StringBuffer xref = StringBuffer(
    'xref\n0 ${objs.length + 1}\n0000000000 65535 f \n',
  );
  for (final int off in offsets) {
    xref.write('${off.toString().padLeft(10, '0')} 00000 n \n');
  }
  xref.write(
    'trailer\n<</Size ${objs.length + 1}/Root 1 0 R>>\nstartxref\n$xrefAt\n%%EOF\n',
  );
  out.add(utf8.encode(xref.toString()));
  return out.takeBytes();
}

Uint8List _namedOutlinePdf() {
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R /Outlines 6 0 R '
        '/Names << /Dests 8 0 R >> >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 5 0 R >> endobj\n',
    '4 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 5 0 R >> endobj\n',
    '5 0 obj << /Length 0 >> stream\n\nendstream\nendobj\n',
    '6 0 obj << /Type /Outlines /First 7 0 R /Last 7 0 R /Count 1 >> endobj\n',
    '7 0 obj << /Title (Chapter) /Parent 6 0 R '
        '/A << /S /GoTo /D (chap1) >> >> endobj\n',
    '8 0 obj << /Names [(chap1) [4 0 R /Fit]] >> endobj\n',
  ]);
}

Uint8List _clipScalePdf() {
  const String content = 'q 0.5 0 0 0.5 0 0 cm 0 0 100 100 re W* n 0 0 200 200 re f Q\n';
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << >> >> endobj\n',
    '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
  ]);
}

Uint8List _winAnsiPdf() {
  const String content = 'BT /F1 10 Tf 72 400 Td <41> Tj 0 -12 Td <80> Tj ET\n';
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n',
    '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    '5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding /WinAnsiEncoding >> endobj\n',
  ]);
}

Uint8List _jbig2Pdf() {
  const String content = 'q 20 0 0 20 72 400 cm /Im0 Do Q\n';
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /XObject << /Im0 5 0 R >> >> >> endobj\n',
    '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    '5 0 obj << /Type /XObject /Subtype /Image /Width 8 /Height 8 '
        '/ColorSpace /DeviceGray /BitsPerComponent 1 /Filter /JBIG2Decode '
        '/Length 2 >> stream\nxx\nendstream\nendobj\n',
  ]);
}

Uint8List _ocgPdf() {
  const String content =
      '/OC /L1 BDC BT /F1 12 Tf 72 400 Td (Hidden) Tj ET EMC '
      'BT /F1 12 Tf 72 300 Td (Shown) Tj ET\n';
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R '
        '/OCProperties << /OCGs [6 0 R] /D << /OFF [6 0 R] >> >> >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> '
        '/Properties << /L1 6 0 R >> >> >> endobj\n',
    '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    '5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n',
    '6 0 obj << /Type /OCG /Name (Notes) >> endobj\n',
  ]);
}

Uint8List _axialPdf() {
  const String content = '/Sh1 sh\n';
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Shading << /Sh1 5 0 R >> >> >> endobj\n',
    '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    '5 0 obj << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [72 400 200 400] '
        '/Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> '
        '>> endobj\n',
  ]);
}

Uint8List _structPdf() {
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R /StructTreeRoot 5 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << >> >> endobj\n',
    '4 0 obj << /Type /StructElem /S /P /Alt (Para) >> endobj\n',
    '5 0 obj << /Type /StructTreeRoot /K [4 0 R] >> endobj\n',
  ]);
}

Uint8List _sigPdf({required bool validRange, String filter = 'Adobe.PPKLite'}) {
  const String br = '/ByteRange [0 0000000000 0000000000 0000000000]';
  final Uint8List bytes = _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R /AcroForm 5 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Annots [4 0 R] /Resources << >> >> endobj\n',
    '4 0 obj << /Type /Annot /Subtype /Widget /FT /Sig /T (Sig1) '
        '/Rect [72 700 200 720] /V 6 0 R /P 3 0 R >> endobj\n',
    '5 0 obj << /Fields [4 0 R] >> endobj\n',
    '6 0 obj << /Type /Sig /Filter /$filter $br /Contents <00> >> endobj\n',
  ]);
  if (!validRange) {
    return bytes;
  }
  final int marker = _indexOf(bytes, '/Contents <');
  expect(marker, greaterThan(0));
  final int holeStart = marker + '/Contents '.length;
  var holeEnd = holeStart;
  while (holeEnd < bytes.length && bytes[holeEnd] != 0x3E) {
    holeEnd++;
  }
  holeEnd++;
  final String patched =
      '/ByteRange [0 ${holeStart.toString().padLeft(10, '0')} '
      '${holeEnd.toString().padLeft(10, '0')} '
      '${(bytes.length - holeEnd).toString().padLeft(10, '0')}]';
  expect(patched.length, br.length);
  final int at = _indexOf(bytes, br);
  final Uint8List out = Uint8List.fromList(bytes);
  out.setRange(at, at + patched.length, utf8.encode(patched));
  return out;
}

Uint8List acroFormPdf() {
  final List<Uint8List> objs = <Uint8List>[
    utf8.encode(
      '1 0 obj << /Type /Catalog /Pages 2 0 R /AcroForm 5 0 R >> endobj\n',
    ),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [4 0 R] /Resources << >> >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Type /Annot /Subtype /Widget /FT /Tx /T (Name) /V (Ada) /Rect [72 700 300 720] /P 3 0 R >> endobj\n',
    ),
    utf8.encode('5 0 obj << /Fields [4 0 R] /NeedAppearances true >> endobj\n'),
  ];
  final Uint8List header = utf8.encode('%PDF-1.7\n%\n');
  final BytesBuilder out = BytesBuilder();
  out.add(header);
  final List<int> offsets = <int>[];
  for (final Uint8List obj in objs) {
    offsets.add(out.length);
    out.add(obj);
  }
  final int xrefAt = out.length;
  final StringBuffer xref = StringBuffer('xref\n0 6\n0000000000 65535 f \n');
  for (final int off in offsets) {
    xref.write('${off.toString().padLeft(10, '0')} 00000 n \n');
  }
  xref.write('trailer\n<</Size 6/Root 1 0 R>>\nstartxref\n$xrefAt\n%%EOF\n');
  out.add(utf8.encode(xref.toString()));
  return out.takeBytes();
}

const List<int> _pdfPad = <int>[
  0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
  0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
  0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
  0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
];

Uint8List encryptedRev2Pdf(String password) {
  final Uint8List id = Uint8List.fromList(<int>[
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
  ]);
  const int pPerm = -4;
  final Uint8List userPad = _padPassword(password);
  final Uint8List oKey = Uint8List.fromList(
    md5.convert(userPad).bytes.sublist(0, 5),
  );
  final Uint8List o = PdfRc4.crypt(oKey, userPad);
  final BytesBuilder keySrc = BytesBuilder()
    ..add(userPad)
    ..add(o)
    ..addByte(pPerm & 0xFF)
    ..addByte((pPerm >> 8) & 0xFF)
    ..addByte((pPerm >> 16) & 0xFF)
    ..addByte((pPerm >> 24) & 0xFF)
    ..add(id);
  final Uint8List fileKey = Uint8List.fromList(
    md5.convert(keySrc.takeBytes()).bytes.sublist(0, 5),
  );
  final Uint8List u = PdfRc4.crypt(fileKey, Uint8List.fromList(_pdfPad));

  Uint8List enc(int objId, Uint8List data) {
    final Uint8List buf = Uint8List(fileKey.length + 5);
    buf.setAll(0, fileKey);
    buf[fileKey.length] = objId & 0xFF;
    buf[fileKey.length + 1] = (objId >> 8) & 0xFF;
    buf[fileKey.length + 2] = (objId >> 16) & 0xFF;
    return PdfRc4.crypt(
      Uint8List.fromList(md5.convert(buf).bytes.sublist(0, 10)),
      data,
    );
  }

  final Uint8List content = enc(
    4,
    utf8.encode('BT /F1 12 Tf 72 700 Td (Hi) Tj ET'),
  );
  final Uint8List title = enc(7, utf8.encode('Secret'));
  final String idHex = _hex(id);
  final List<List<int>> parts = <List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n',
    ),
    <int>[
      ...utf8.encode('4 0 obj << /Length ${content.length} >> stream\n'),
      ...content,
      ...utf8.encode('\nendstream\nendobj\n'),
    ],
    utf8.encode(
      '5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n',
    ),
    utf8.encode(
      '6 0 obj << /Filter /Standard /V 1 /R 2 /Length 40 '
      '/O <${_hex(o)}> /U <${_hex(u)}> /P $pPerm >> endobj\n',
    ),
    utf8.encode('7 0 obj << /Title <${_hex(title)}> >> endobj\n'),
  ];
  final BytesBuilder out = BytesBuilder()..add(utf8.encode('%PDF-1.7\n%\n'));
  final List<int> offsets = <int>[];
  for (final List<int> part in parts) {
    offsets.add(out.length);
    out.add(part);
  }
  final int xrefAt = out.length;
  final StringBuffer xref = StringBuffer('xref\n0 8\n0000000000 65535 f \n');
  for (final int off in offsets) {
    xref.write('${off.toString().padLeft(10, '0')} 00000 n \n');
  }
  xref.write(
    'trailer\n<</Size 8/Root 1 0 R/Info 7 0 R/Encrypt 6 0 R'
    '/ID[<$idHex><$idHex>]>>\nstartxref\n$xrefAt\n%%EOF\n',
  );
  out.add(utf8.encode(xref.toString()));
  return out.takeBytes();
}

Uint8List _padPassword(String password) {
  final Uint8List raw = Uint8List.fromList(latin1.encode(password));
  final Uint8List out = Uint8List(32);
  final int n = raw.length < 32 ? raw.length : 32;
  out.setRange(0, n, raw);
  if (n < 32) {
    out.setRange(n, 32, _pdfPad);
  }
  return out;
}

List<int> _hexToBytes(String hex) {
  final String clean = hex.replaceAll(RegExp(r'\s'), '');
  return <int>[
    for (int i = 0; i + 1 < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ];
}

String _hex(Uint8List bytes) {
  final StringBuffer buf = StringBuffer();
  for (final int b in bytes) {
    buf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

int _indexOf(Uint8List data, String token) {
  final List<int> needle = token.codeUnits;
  for (int i = 0; i <= data.length - needle.length; i++) {
    var ok = true;
    for (int k = 0; k < needle.length; k++) {
      if (data[i + k] != needle[k]) {
        ok = false;
        break;
      }
    }
    if (ok) {
      return i;
    }
  }
  return -1;
}

Uint8List _minimalCff() {
  // CFF1: name TestCFF, 2 charstrings (.notdef + space), charset GID1=SID1.
  return Uint8List.fromList(<int>[
    0x01, 0x00, 0x04, 0x01,
    0x00, 0x01, 0x01, 0x01, 0x08,
    0x54, 0x65, 0x73, 0x74, 0x43, 0x46, 0x46,
    0x00, 0x01, 0x01, 0x01, 0x09,
    0x1C, 0x00, 0x29, 0x0F,
    0x1C, 0x00, 0x21, 0x11,
    0x00, 0x00,
    0x00, 0x00,
    0x00, 0x02, 0x01, 0x01, 0x02, 0x03, 0x0E, 0x0E,
    0x00, 0x00, 0x01,
  ]);
}

bool _sfntHas(Uint8List font, String tag) {
  if (font.length < 12) {
    return false;
  }
  final int n = (font[4] << 8) | font[5];
  for (int i = 0; i < n; i++) {
    final int at = 12 + i * 16;
    if (at + 4 > font.length) {
      return false;
    }
    final String name = String.fromCharCodes(font.sublist(at, at + 4));
    if (name == tag) {
      return true;
    }
  }
  return false;
}

Uint8List _pdfParts(List<List<int>> parts) {
  final BytesBuilder out = BytesBuilder()..add(utf8.encode('%PDF-1.7\n%\n'));
  final List<int> offsets = <int>[];
  for (final List<int> part in parts) {
    offsets.add(out.length);
    out.add(part);
  }
  final int xrefAt = out.length;
  final StringBuffer xref = StringBuffer(
    'xref\n0 ${parts.length + 1}\n0000000000 65535 f \n',
  );
  for (final int off in offsets) {
    xref.write('${off.toString().padLeft(10, '0')} 00000 n \n');
  }
  xref.write(
    'trailer\n<</Size ${parts.length + 1}/Root 1 0 R>>\nstartxref\n$xrefAt\n%%EOF\n',
  );
  out.add(utf8.encode(xref.toString()));
  return out.takeBytes();
}

Uint8List _cffFontPdf(Uint8List cff) {
  const String content = 'BT /F1 12 Tf 72 400 Td ( ) Tj ET\n';
  return _pdfParts(<List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    ),
    utf8.encode(
      '5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /TestCFF '
      '/FirstChar 32 /LastChar 32 /Widths [250] /FontDescriptor 6 0 R >> endobj\n',
    ),
    utf8.encode(
      '6 0 obj << /Type /FontDescriptor /FontName /TestCFF /Flags 32 '
      '/FontBBox [0 0 500 700] /ItalicAngle 0 /Ascent 700 /Descent -200 '
      '/CapHeight 700 /StemV 80 /FontFile3 7 0 R >> endobj\n',
    ),
    <int>[
      ...utf8.encode(
        '7 0 obj << /Length ${cff.length} /Subtype /Type1C >> stream\n',
      ),
      ...cff,
      ...utf8.encode('\nendstream\nendobj\n'),
    ],
  ]);
}

Uint8List _fillStrokeTrPdf() {
  const String content =
      '0 0 20 20 re b BT /F1 12 Tf 3 Tr 72 400 Td (Hide) Tj '
      '0 Tr 0 -14 Td (Show) Tj ET\n';
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n',
    '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    '5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n',
  ]);
}

Uint8List _strokeStylePdf() {
  const String content = '2 w 1 J 1 j [3 1] 0 d 72 400 40 10 re S\n';
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << >> >> endobj\n',
    '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
  ]);
}

Uint8List _multiplyPdf() {
  const String content = '/GS1 gs 72 400 40 20 re f\n';
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /ExtGState << /GS1 5 0 R >> >> >> endobj\n',
    '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    '5 0 obj << /Type /ExtGState /BM /Multiply /ca 0.5 >> endobj\n',
  ]);
}

Uint8List _cmykImagePdf() {
  const String content = 'q 10 0 0 10 72 400 cm /Im0 Do Q\n';
  return _pdfParts(<List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /XObject << /Im0 5 0 R >> >> >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    ),
    <int>[
      ...utf8.encode(
        '5 0 obj << /Type /XObject /Subtype /Image /Width 1 /Height 1 '
        '/ColorSpace /DeviceCMYK /BitsPerComponent 8 /Length 4 >> stream\n',
      ),
      0, 0, 0, 0,
      ...utf8.encode('\nendstream\nendobj\n'),
    ],
  ]);
}

Uint8List _imageMaskPdf() {
  const String content = '1 1 1 rg q 8 0 0 1 72 400 cm /Im0 Do Q\n';
  return _pdfParts(<List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /XObject << /Im0 5 0 R >> >> >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    ),
    <int>[
      ...utf8.encode(
        '5 0 obj << /Type /XObject /Subtype /Image /Width 8 /Height 1 '
        '/ImageMask true /BitsPerComponent 1 /Length 1 >> stream\n',
      ),
      0x80,
      ...utf8.encode('\nendstream\nendobj\n'),
    ],
  ]);
}

Uint8List _indexedPdf() {
  const String content = 'q 2 0 0 1 72 400 cm /Im0 Do Q\n';
  return _pdfParts(<List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /XObject << /Im0 5 0 R >> >> >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    ),
    <int>[
      ...utf8.encode(
        '5 0 obj << /Type /XObject /Subtype /Image /Width 2 /Height 1 '
        '/ColorSpace [/Indexed /DeviceRGB 1 <FF000000FF00>] '
        '/BitsPerComponent 1 /Length 1 >> stream\n',
      ),
      0x80,
      ...utf8.encode('\nendstream\nendobj\n'),
    ],
  ]);
}

Uint8List _oneBitGrayPdf() {
  const String content = 'q 8 0 0 1 72 400 cm /Im0 Do Q\n';
  return _pdfParts(<List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /XObject << /Im0 5 0 R >> >> >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    ),
    <int>[
      ...utf8.encode(
        '5 0 obj << /Type /XObject /Subtype /Image /Width 8 /Height 1 '
        '/ColorSpace /DeviceGray /BitsPerComponent 1 /Length 1 >> stream\n',
      ),
      0x80,
      ...utf8.encode('\nendstream\nendobj\n'),
    ],
  ]);
}

Uint8List _identityHLiteralPdf() {
  final Uint8List content = Uint8List.fromList(<int>[
    ...utf8.encode('BT /F1 24 Tf 72 720 Td ('),
    0x00,
    0x41,
    0x00,
    0x4C,
    ...utf8.encode(') Tj ET\n'),
  ]);
  const String toUnicode =
      '/CIDInit /ProcSet findresource begin\n'
      '12 dict begin\nbegincmap\n'
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n'
      '/CMapName /Adobe-Identity-UCS def\n'
      '/CMapType 2 def\n'
      '1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n'
      '2 beginbfchar\n<0041> <0041>\n<004C> <004C>\nendbfchar\n'
      'endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n';
  return _pdfParts(<List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n',
    ),
    <int>[
      ...utf8.encode('4 0 obj << /Length ${content.length} >> stream\n'),
      ...content,
      ...utf8.encode('\nendstream\nendobj\n'),
    ],
    utf8.encode(
      '5 0 obj << /Type /Font /Subtype /Type0 /BaseFont /Dummy '
      '/Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 7 0 R >> endobj\n',
    ),
    utf8.encode(
      '6 0 obj << /Type /Font /Subtype /CIDFontType2 /BaseFont /Dummy '
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> '
      '/DW 500 >> endobj\n',
    ),
    utf8.encode(
      '7 0 obj << /Length ${toUnicode.length} >> stream\n$toUnicode\nendstream\nendobj\n',
    ),
  ]);
}

Uint8List _groupFormCaPdf() {
  const String pageContent = 'q /GS0 gs /Fm0 Do Q\n';
  const String formContent = 'q 1 0 0 1 0 0 cm /Im0 Do Q\n';
  return _pdfParts(<List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /ExtGState << /GS0 5 0 R >> '
      '/XObject << /Fm0 6 0 R >> >> >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Length ${pageContent.length} >> stream\n'
      '$pageContent\nendstream\nendobj\n',
    ),
    utf8.encode('5 0 obj << /Type /ExtGState /ca 0.35 /BM /Normal >> endobj\n'),
    utf8.encode(
      '6 0 obj << /Type /XObject /Subtype /Form /FormType 1 '
      '/BBox [0 0 1 1] /Group << /Type /Group /S /Transparency >> '
      '/Resources << /XObject << /Im0 7 0 R >> >> '
      '/Length ${formContent.length} >> stream\n'
      '$formContent\nendstream\nendobj\n',
    ),
    <int>[
      ...utf8.encode(
        '7 0 obj << /Type /XObject /Subtype /Image /Width 1 /Height 1 '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Length 3 >> stream\n',
      ),
      255,
      255,
      255,
      ...utf8.encode('\nendstream\nendobj\n'),
    ],
  ]);
}

Uint8List _iccBasedPdf() {
  const String content = 'q 10 0 0 10 72 400 cm /Im0 Do Q\n';
  return _pdfParts(<List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /XObject << /Im0 5 0 R >> >> >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    ),
    utf8.encode(
      '5 0 obj << /Type /XObject /Subtype /Image /Width 1 /Height 1 '
      '/ColorSpace [/ICCBased 6 0 R] /BitsPerComponent 8 /Length 1 >> stream\n'
      '\x00\nendstream\nendobj\n',
    ),
    utf8.encode(
      '6 0 obj << /N 1 /Length 1 >> stream\nx\nendstream\nendobj\n',
    ),
  ]);
}

Uint8List _actualTextPdf() {
  const String content =
      '/Span << /ActualText (CopyMe) >> BDC BT /F1 12 Tf 72 400 Td (xx) Tj ET EMC\n';
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n',
    '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    '5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n',
  ]);
}

Uint8List _xfaPdf() {
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R /AcroForm 5 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << >> >> endobj\n',
    '4 0 obj << /Length 0 >> stream\n\nendstream\nendobj\n',
    '5 0 obj << /Fields [] /XFA [(xdp:xdp) 6 0 R] >> endobj\n',
    '6 0 obj << /Length 3 >> stream\nxdp\nendstream\nendobj\n',
  ]);
}

Uint8List _viewerPrefsPdf() {
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R /ViewerPreferences '
        '<< /Direction /R2L /FitWindow true /HideToolbar true >> >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << >> >> endobj\n',
  ]);
}

Uint8List _radialPdf() {
  const String content = '/Sh1 sh\n';
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Shading << /Sh1 5 0 R >> >> >> endobj\n',
    '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    '5 0 obj << /ShadingType 3 /ColorSpace /DeviceRGB '
        '/Coords [100 400 0 100 400 40] '
        '/Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> '
        '>> endobj\n',
  ]);
}

SfntFont? _tryFont() {
  for (final String path in <String>[
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
  ]) {
    final File file = File(path);
    if (file.existsSync()) {
      return SfntFont.parse(file.readAsBytesSync());
    }
  }
  return null;
}
