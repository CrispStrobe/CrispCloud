import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/document_printing.dart';
import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:pdf_document/pdf_document.dart' as pdf;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('oversized image headers are refused before pixel allocation', () {
    final bytes = Uint8List.fromList(
      image.encodePng(image.Image(width: 1, height: 1)),
    );
    final header = ByteData.sublistView(bytes);
    header.setUint32(16, 0xffffffff, Endian.big);
    header.setUint32(20, 0xffffffff, Endian.big);
    header.setUint32(29, getCrc32(bytes.sublist(12, 29)), Endian.big);
    final info = image.PngDecoder().startDecode(bytes);
    expect(info, isNotNull);
    expect(info!.width, 0xffffffff);
    expect(() => imagePrintPdf(bytes, 'oversized.png'), throwsFormatException);
  });
  test(
    'text, CSV, markup and images produce independently readable print PDFs',
    () async {
      final text = await textPrintPdf(
        'First line\n  indented();\nمرحبا',
        'source.dart',
      );
      expect(pdf.PdfDocument.open(text).pageCount, greaterThan(0));
      final input = Uint8List.fromList(utf8.encode('name,value\n"A,B",=1+1'));
      final before = Uint8List.fromList(input);
      final table = await csvPrintPdf(input, 'table.csv');
      expect(pdf.PdfDocument.open(table).pageCount, greaterThan(0));
      expect(input, orderedEquals(before));
      final rich = await richTextPrintPdf(
        '# Heading\n\n**Bold** text ![diagram](https://example.invalid/image.png)',
        'README.md',
        markdown: true,
      );
      expect(pdf.PdfDocument.open(rich).pageCount, greaterThan(0));
      final canvas = image.Image(width: 200, height: 100);
      image.fill(canvas, color: image.ColorRgb8(255, 0, 0));
      final picture = imagePrintPdf(
        Uint8List.fromList(image.encodePng(canvas)),
        'photo.png',
      );
      expect(pdf.PdfDocument.open(picture).pageCount, 1);
      expect(
        () => imagePrintPdf(Uint8List.fromList([0, 1, 2]), 'bad'),
        throwsFormatException,
      );
    },
  );
}
