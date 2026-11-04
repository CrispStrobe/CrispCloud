import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/fonts/cff_raster.dart';
import 'package:quds_office_engine/src/fonts/gsub_ligature.dart';
import 'package:quds_office_engine/src/pdf/widgets/pw_barcode.dart';
import 'package:test/test.dart';

void main() {
  test('EAN-13 rejects a bad check digit and encodes a valid one', () {
    const String twelve = '400638133393';
    final String full = '$twelve${Ean13Encoder.check(twelve)}';
    final List<bool> modules = const Ean13Encoder().encode(full);
    expect(modules.length, greaterThan(50));
    expect(modules.any((bool dark) => dark), isTrue);
    expect(
      () => const Ean13Encoder().encode('${twelve}0'),
      throwsArgumentError,
    );
  });

  test('a Type 2 rectangle charstring fills pixels', () {
    final Uint8List program = Uint8List.fromList(<int>[
      139, 139, 21, // 0 0 rmoveto
      219, 139, 139, 219, 59, 139, 139, 59, 5, // rlineto square
      14, // endchar
    ]);
    final CffBitmap bitmap = CffRaster.charstring(program, size: 32);
    expect(bitmap.pixels.any((int p) => p == 255), isTrue);
  });

  test('GSUB ligature lookup replaces a glyph pair', () {
    final GsubLigatures gsub = GsubLigatures.parseBytes(_gsub());
    expect(gsub.isEmpty, isFalse);
    expect(gsub.apply(<int>[3, 4, 1]), <int>[9, 1]);
  });

  test('redaction empties a Tj whose origin is inside the rect', () {
    final PdfDocument doc = PdfDocument(title: 'Redact');
    final PdfCanvas canvas = PdfCanvas(200, 200);
    canvas.showLatin(x: 20, y: 40, fontSize: 12, text: 'Secret', color: '000000');
    canvas.endText();
    doc.addPage(PdfPage(width: 200, height: 200, content: canvas.toStream()));
    final PdfFile file = PdfFile.open(doc.save());
    file.redactRect(
      0,
      const PdfRect(x: 10, y: 30, width: 80, height: 30),
      mode: PdfRedactMode.removeContent,
    );
    final String stream = utf8.decode(
      file.pageRec(0).pendingContent ?? Uint8List(0),
      allowMalformed: true,
    );
    expect(stream.contains('Secret'), isFalse);
    expect(stream, contains('()Tj'));
  });

  test('mail merge repeats the merge row and fills the letter once', () {
    final WmlDocument template = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Hello «Name»')]),
            WmlTable(
              rows: <WmlTableRow>[
                WmlTableRow(
                  cells: <WmlTableCell>[
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[WmlRun(text: '«City»')],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final WmlDocument merged = WordMailMerge.documentFor(template, <Map<String, String>>[
      <String, String>{'Name': 'Amal', 'City': 'Nablus'},
      <String, String>{'Name': 'Bassam', 'City': 'Gaza'},
    ]);
    final String text = merged.paragraphs.map((WmlParagraph p) => p.text).join('\n');
    expect(text, contains('Amal'));
    expect(text, contains('Nablus'));
    expect(text, contains('Gaza'));
  });

  test('an EAN barcode and a page header reach the workbook', () {
    final String code = '400638133393${Ean13Encoder.check('400638133393')}';
    final String xml = '''
<QudsReport>
  <Bands>
    <PageHeader height="8mm" printOnFirstPage="true">
      <Text x="0" y="0" width="40mm" height="6mm">Invoice</Text>
    </PageHeader>
    <Detail height="20mm">
      <Barcode x="0" y="0" width="40mm" height="16mm" symbology="ean13" value="$code"/>
    </Detail>
  </Bands>
</QudsReport>''';
    final QudsReportEngine engine = QudsReportEngine.fromXml(xml);
    final Uint8List xlsx = engine.exportToExcelSync(const <String, Object?>{});
    final ZipReader zip = ZipReader.fromBytes(xlsx);
    final String sheet = utf8.decode(zip.read('xl/worksheets/sheet1.xml'));
    expect(sheet, contains('oddHeader'));
    expect(sheet, contains('Invoice'));
    expect(zip.entries.any((ZipEntry e) => e.fileName.contains('drawing')), isTrue);
    final ReportDocumentLayout bad = QudsReportEngine.fromXml('''
<QudsReport>
  <Bands>
    <Detail height="12mm">
      <Barcode x="0" y="0" width="40mm" height="10mm" symbology="ean13" value="12"/>
    </Detail>
  </Bands>
</QudsReport>''').layout(const <String, Object?>{});
    expect(bad.warnings.join('\n'), contains('EAN-13'));
  });
}

Uint8List _gsub() {
  final BytesBuilder b = BytesBuilder()
    ..add(const <int>[0, 1, 0, 0])
    ..add(const <int>[0, 10, 0, 10, 0, 10])
    ..add(const <int>[0, 1, 0, 4])
    ..add(const <int>[0, 4, 0, 0, 0, 1, 0, 8])
    ..add(const <int>[0, 1, 0, 8, 0, 1, 0, 14])
    ..add(const <int>[0, 1, 0, 1, 0, 3])
    ..add(const <int>[0, 1, 0, 4])
    ..add(const <int>[0, 9, 0, 2, 0, 4]);
  return b.toBytes();
}
