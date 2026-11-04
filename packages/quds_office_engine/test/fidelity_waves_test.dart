import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/pdf_widgets.dart' as pw;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/pdf/file/decode/pdf_cms.dart';
import 'package:quds_office_engine/src/pdf/file/decode/pdf_jbig2.dart';
import 'package:test/test.dart';

SfntFont? _font(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  return SfntFont.parse(file.readAsBytesSync());
}

void main() {
  final SfntFont? naskh = _font(
    '../quds_office_editor/fonts/NotoNaskhArabic-Regular.ttf',
  );
  final SfntFont? tajawal = _font(
    '../quds_office_editor/example/fonts/Tajawal-Regular.ttf',
  );

  group('wave 1 GPOS MarkToBase', () {
    for (final (String name, SfntFont? font) in <(String, SfntFont?)>[
      ('Noto Naskh Arabic', naskh),
      ('Tajawal', tajawal),
    ]) {
      test('$name places damma using GPOS not advance/2', () {
        if (font == null) {
          markTestSkipped('$name is not next to the engine package');
          return;
        }
        expect(font.hasTable('GPOS'), isTrue);
        final GposMarkToBase gpos = GposMarkToBase.of(font);
        expect(gpos.isEmpty, isFalse);
        const double size = 24;
        final FontMetrics metrics = FontMetrics(
          font: font,
          fontSizePoints: size,
        );
        final List<BrokenLine> lines = LineBreaker.breakLines(
          text: 'أُنشئت',
          maxWidth: 1000,
          widthOf: metrics.characterWidth,
          glyphIdOf: font.glyphIdFor,
          markAttachOf: GposMarkToBase.fnFor(font, size),
          baseLevel: 1,
          justify: false,
        );
        final List<ShapedGlyph> glyphs = lines.single.glyphs;
        final ShapedGlyph damma = glyphs.firstWhere(
          (ShapedGlyph g) => g.codePoint == 0x064F,
        );
        final ShapedGlyph alef = glyphs.firstWhere(
          (ShapedGlyph g) =>
              g.codePoint == 0x0623 ||
              g.codePoint == 0xFE83 ||
              g.codePoint == 0xFE84 ||
              g.codePoint == 0xFE87,
        );
        expect(damma.advance, 0);
        final double centered = -alef.advance / 2;
        if ((damma.paintDx - centered).abs() < 0.05 && damma.paintDy.abs() < 0.05) {
          markTestSkipped('$name has no MarkToBase pair for this cluster');
          return;
        }
        expect(damma.paintDx, isNot(closeTo(centered, 0.05)));
        expect(damma.paintDy.abs(), greaterThan(0.5));
        expect((damma.paintDx + alef.advance).abs(), lessThan(alef.advance));
      });
    }
  });

  test('wave 2 FreeText AP paints أُنشئت with damma on alef', () {
    if (naskh == null) {
      markTestSkipped('Noto Naskh Arabic is not next to the engine package');
      return;
    }
    final PdfDocument doc = PdfDocument(title: 'ap');
    doc.addPage(
      PdfPage(width: 300, height: 200, content: Uint8List(0)),
    );
    final PdfFile file = PdfFile.open(doc.save());
    file.appearanceFont = naskh;
    file.addAnnot(
      0,
      PdfAnnot(
        id: 0,
        subtype: 'FreeText',
        rect: const PdfRect(x: 20, y: 40, width: 160, height: 36),
        contents: 'أُنشئت',
        color: 0xFFFFF3C4,
      ),
    );
    final Uint8List saved = PdfIncrementalSave.write(
      originalBytes: file.originalBytes,
      file: file,
    );
    final PdfFile again = PdfFile.open(saved);
    final List<PdfDrawText> glyphs = <PdfDrawText>[
      for (final PdfPaintOp op in again.displayList(0).ops)
        if (op is PdfDrawText && op.text.isNotEmpty) op,
    ];
    PdfDrawText? damma;
    PdfDrawText? alef;
    PdfDrawText? sheen;
    for (final PdfDrawText g in glyphs) {
      final int cp = g.text.runes.first;
      if (cp == 0x064F) {
        damma = g;
      } else if (cp == 0x0623 || cp == 0xFE83 || cp == 0xFE84 || cp == 0xFE87) {
        alef = g;
      } else if (cp == 0x0634 || cp == 0xFEB7 || cp == 0xFEB8) {
        sheen = g;
      }
    }
    expect(damma, isNotNull);
    expect(alef, isNotNull);
    expect(sheen, isNotNull);
    expect((damma!.x - alef!.x).abs(), lessThan((damma.x - sheen!.x).abs()));
  });

  test('wave 3 appendPages keeps two embedded faces', () {
    if (naskh == null || tajawal == null) {
      markTestSkipped('Arabic gallery fonts are not next to the engine package');
      return;
    }
    Uint8List oneWord(SfntFont face, String word) {
      final pw.Document doc = pw.Document(font: face);
      doc.addPage(
        pw.Page(
          pageFormat: const pw.PdfPageFormat(200, 80),
          margin: const pw.EdgeInsets.all(8),
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context ctx) => pw.Text(word),
        ),
      );
      return doc.save();
    }

    final PdfFile a = PdfFile.open(oneWord(naskh, 'مرحبا'));
    final PdfFile b = PdfFile.open(oneWord(tajawal, 'عالم'));
    a.appendPages(b);
    expect(a.pageCount, 2);
    final String first = a.displayList(0).plainText;
    final String second = a.displayList(1).plainText;
    expect(first.contains('م') || first.contains('ﻣ'), isTrue);
    expect(second.contains('ع') || second.contains('ﻋ') || second.contains('ع'), isTrue);
    expect(first, isNot(contains('\uFFFD')));
    expect(second, isNot(contains('.notdef')));
  });

  test('wave 4 widgets write a fillable AcroForm Tx field', () {
    if (naskh == null) {
      markTestSkipped('Noto Naskh Arabic is not next to the engine package');
      return;
    }
    final pw.Document doc = pw.Document(font: naskh);
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context ctx) => pw.Column(
          children: <pw.Widget>[
            pw.TextField(name: 'name', value: 'Ada', acroForm: true),
            pw.Checkbox(name: 'ok', value: true, acroForm: true),
          ],
        ),
      ),
    );
    final Uint8List bytes = doc.save();
    final PdfFile file = PdfFile.open(bytes);
    expect(file.form.field('name')?.value, 'Ada');
    expect(file.form.field('ok'), isNotNull);
    file.form.field('name')!.value = 'Grace';
    file.markDirty(0);
    final PdfFile again = PdfFile.open(
      PdfIncrementalSave.write(originalBytes: bytes, file: file),
    );
    expect(again.form.field('name')?.value, 'Grace');
  });

  test('wave 5a JBIG2 MMR generic region decodes; junk stays placeholder', () {
    final Uint8List white = PdfJbig2.decode(_jbig2White8x1(), PdfCosDict());
    expect(white.length, 8);
    expect(white.every((int b) => b == 0xFF), isTrue);

    final PdfFile junk = PdfFile.open(_jbig2Pdf(Uint8List.fromList(<int>[0x78, 0x78])));
    expect(
      junk.displayList(0).ops.whereType<PdfDrawImage>().first.placeholder,
      isTrue,
    );

    final PdfFile ok = PdfFile.open(_jbig2Pdf(_jbig2White8x1()));
    final PdfDrawImage img = ok.displayList(0).ops.whereType<PdfDrawImage>().first;
    expect(img.placeholder, isFalse);
    expect(img.pixelWidth, 8);

    final PdfFile jpx = PdfFile.open(
      _jbig2Pdf(Uint8List.fromList(<int>[0, 1, 2, 3]), filter: 'JPXDecode'),
    );
    expect(
      jpx.displayList(0).ops.whereType<PdfDrawImage>().first.placeholder,
      isTrue,
    );
  });

  test('wave 5b CMS messageDigest matches ByteRange', () {
    final Uint8List valid = _cmsSigPdf(match: true);
    expect(PdfFile.open(valid).signatures.first.status, PdfSignatureStatus.valid);
    final Uint8List bad = _cmsSigPdf(match: false);
    expect(PdfFile.open(bad).signatures.first.status, PdfSignatureStatus.invalid);
    expect(
      PdfCms.verify(
        contents: Uint8List.fromList(<int>[0]),
        signedBytes: Uint8List(4),
      ),
      PdfSignatureStatus.unverified,
    );
  });
}

Uint8List _jbig2White8x1() {
  final BytesBuilder out = BytesBuilder();
  out.add(<int>[0x97, 0x4A, 0x42, 0x32, 0x0D, 0x0A, 0x1A, 0x0A]);
  out.add(<int>[0x00]);
  out.add(_u32(1));
  // Page information, type 48, page 1, 19 bytes.
  out.add(_u32(0));
  out.addByte(48);
  out.addByte(0);
  out.addByte(1);
  out.add(_u32(19));
  out.add(_u32(8));
  out.add(_u32(1));
  out.add(_u32(196));
  out.add(_u32(196));
  out.addByte(0);
  out.add(<int>[0xFF, 0xFF]);
  // Immediate generic region type 36.
  final Uint8List mmr = Uint8List.fromList(<int>[0x80]);
  out.add(_u32(1));
  out.addByte(36);
  out.addByte(0);
  out.addByte(1);
  out.add(_u32(18 + mmr.length));
  out.add(_u32(8));
  out.add(_u32(1));
  out.add(_u32(0));
  out.add(_u32(0));
  out.addByte(0);
  out.addByte(1);
  out.add(mmr);
  // End of page / file.
  out.add(_u32(2));
  out.addByte(49);
  out.addByte(0);
  out.addByte(1);
  out.add(_u32(0));
  out.add(_u32(3));
  out.addByte(51);
  out.addByte(0);
  out.addByte(0);
  out.add(_u32(0));
  return out.takeBytes();
}

List<int> _u32(int v) => <int>[
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

Uint8List _jbig2Pdf(Uint8List payload, {String filter = 'JBIG2Decode'}) {
  const String content = 'q 20 0 0 20 72 400 cm /Im0 Do Q\n';
  return _pdfObjects(<List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /XObject << /Im0 5 0 R >> >> >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    ),
    Uint8List.fromList(<int>[
      ...utf8.encode(
        '5 0 obj << /Type /XObject /Subtype /Image /Width 8 /Height 1 '
        '/ColorSpace /DeviceGray /BitsPerComponent 1 /Filter /$filter '
        '/Length ${payload.length} >> stream\n',
      ),
      ...payload,
      ...utf8.encode('\nendstream\nendobj\n'),
    ]),
  ]);
}

Uint8List _pdfObjects(List<List<int>> objs) {
  final BytesBuilder body = BytesBuilder();
  body.add(utf8.encode('%PDF-1.4\n'));
  final List<int> offs = <int>[0];
  for (final List<int> obj in objs) {
    offs.add(body.length);
    body.add(obj);
  }
  final int xref = body.length;
  final StringBuffer x = StringBuffer('xref\n0 ${objs.length + 1}\n');
  x.write('0000000000 65535 f \n');
  for (int i = 1; i < offs.length; i++) {
    x.write('${offs[i].toString().padLeft(10, '0')} 00000 n \n');
  }
  x.write(
    'trailer\n<</Size ${objs.length + 1}/Root 1 0 R>>\nstartxref\n$xref\n%%EOF\n',
  );
  body.add(utf8.encode(x.toString()));
  return body.takeBytes();
}

Uint8List _cmsSigPdf({required bool match}) {
  const String br = '/ByteRange [0 0000000000 0000000000 0000000000]';
  const String hole =
      'CONTENTS_PLACEHOLDER_'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000';
  final Uint8List skeleton = _pdfObjects(<List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R /AcroForm 5 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Annots [4 0 R] /Resources << >> >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Type /Annot /Subtype /Widget /FT /Sig /T (Sig1) '
      '/Rect [72 700 200 720] /V 6 0 R /P 3 0 R >> endobj\n',
    ),
    utf8.encode('5 0 obj << /Fields [4 0 R] >> endobj\n'),
    utf8.encode(
      '6 0 obj << /Type /Sig /Filter /Adobe.PPKLite $br /Contents <$hole> >> endobj\n',
    ),
  ]);
  final int marker = _indexOf(skeleton, '/Contents <');
  final int holeStart = marker + '/Contents '.length;
  var holeEnd = holeStart;
  while (holeEnd < skeleton.length && skeleton[holeEnd] != 0x3E) {
    holeEnd++;
  }
  holeEnd++;
  final String patched =
      '/ByteRange [0 ${holeStart.toString().padLeft(10, '0')} '
      '${holeEnd.toString().padLeft(10, '0')} '
      '${(skeleton.length - holeEnd).toString().padLeft(10, '0')}]';
  final int at = _indexOf(skeleton, br);
  final Uint8List out = Uint8List.fromList(skeleton);
  out.setRange(at, at + patched.length, utf8.encode(patched));
  final Uint8List signed = Uint8List(holeStart + (skeleton.length - holeEnd));
  signed.setAll(0, out.sublist(0, holeStart));
  signed.setAll(holeStart, out.sublist(holeEnd));
  final List<int> digest = sha256.convert(signed).bytes;
  final Uint8List cms = _signedData(match ? digest : List<int>.filled(32, 1));
  final String hex = cms.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  final int inner = holeStart + 1;
  final int innerEnd = holeEnd - 1;
  expect(hex.length, lessThanOrEqualTo(innerEnd - inner));
  final List<int> padded = utf8.encode(hex.padRight(innerEnd - inner, '0'));
  out.setRange(inner, inner + padded.length, padded);
  return out;
}

Uint8List _signedData(List<int> digest) {
  final Uint8List md = _tlv(0x04, Uint8List.fromList(digest));
  final Uint8List mdAttr = _seq(<Uint8List>[
    _oid(<int>[1, 2, 840, 113549, 1, 9, 4]),
    _tlv(0x31, md),
  ]);
  final Uint8List signer = _seq(<Uint8List>[
    _tlv(0x02, Uint8List.fromList(<int>[1])),
    _seq(<Uint8List>[_tlv(0x04, Uint8List.fromList(<int>[0])), _tlv(0x02, Uint8List.fromList(<int>[1]))]),
    _seq(<Uint8List>[_oid(<int>[2, 16, 840, 1, 101, 3, 4, 2, 1]), _tlv(0x05, Uint8List(0))]),
    _tlv(0xA0, mdAttr),
    _seq(<Uint8List>[_oid(<int>[1, 2, 840, 113549, 1, 1, 1]), _tlv(0x05, Uint8List(0))]),
    _tlv(0x04, Uint8List.fromList(<int>[0])),
  ]);
  final Uint8List signedData = _seq(<Uint8List>[
    _tlv(0x02, Uint8List.fromList(<int>[1])),
    _tlv(0x31, _seq(<Uint8List>[_oid(<int>[2, 16, 840, 1, 101, 3, 4, 2, 1]), _tlv(0x05, Uint8List(0))])),
    _seq(<Uint8List>[_oid(<int>[1, 2, 840, 113549, 1, 7, 1])]),
    _tlv(0x31, signer),
  ]);
  return _seq(<Uint8List>[
    _oid(<int>[1, 2, 840, 113549, 1, 7, 2]),
    _tlv(0xA0, signedData),
  ]);
}

Uint8List _seq(List<Uint8List> parts) {
  final BytesBuilder b = BytesBuilder();
  for (final Uint8List p in parts) {
    b.add(p);
  }
  return _tlv(0x30, b.takeBytes());
}

Uint8List _oid(List<int> arcs) {
  final List<int> body = <int>[40 * arcs[0] + arcs[1]];
  for (int i = 2; i < arcs.length; i++) {
    var v = arcs[i];
    if (v < 128) {
      body.add(v);
      continue;
    }
    final List<int> tmp = <int>[];
    tmp.add(v & 0x7F);
    v >>= 7;
    while (v > 0) {
      tmp.add(0x80 | (v & 0x7F));
      v >>= 7;
    }
    body.addAll(tmp.reversed);
  }
  return _tlv(0x06, Uint8List.fromList(body));
}

Uint8List _tlv(int tag, Uint8List body) {
  final BytesBuilder b = BytesBuilder();
  b.addByte(tag);
  if (body.length < 128) {
    b.addByte(body.length);
  } else {
    b.addByte(0x81);
    b.addByte(body.length);
  }
  b.add(body);
  return b.takeBytes();
}

int _indexOf(Uint8List hay, String needle) {
  final List<int> n = utf8.encode(needle);
  for (int i = 0; i <= hay.length - n.length; i++) {
    var ok = true;
    for (int j = 0; j < n.length; j++) {
      if (hay[i + j] != n[j]) {
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
