import 'dart:convert';
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_operations/pdf_operations.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import '../test/support/fixtures.dart';

/// Emit actual engine outputs for independent parsing and raster inspection.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/emit_validation.dart OUTPUT_DIRECTORY');
    exitCode = 64;
    return;
  }
  final destination = Directory(arguments.single)..createSync(recursive: true);
  const service = PdfOperationsService();
  final font = PdfEmbeddedFont.parse(File('test/fonts/CrispPdfTestSans.ttf').readAsBytesSync());
  final source = PdfInput(workflowPdf());
  final encrypted = PdfInput(buildEncryptedPdf(userPassword: 'test-password', revision: 6), password: 'test-password');
  final outputs = <String, PdfOperationResult>{
    'merge.pdf': service.merge([
      PdfMergeInput(source, pages: '3,1,2'),
      PdfMergeInput(PdfInput(workflowPdf(label: 'Appendix')), pages: '2,1'),
    ]),
    'extract.pdf': service.extract(source, pages: '2'),
    'rotate.pdf': service.rotate(source, pages: '1,3'),
    'reorder.pdf': service.reorder(source, pages: '3-1'),
    'delete.pdf': service.deletePages(source, pages: '2'),
    'filled.pdf': service.fillForm(source, values: {
      'customer.name': 'Жук Αθήνα', 'agree': true, 'color': 'Blue',
      'delivery': 'express', 'interests': ['books', 'music'],
    }, appearanceFont: font),
    'watermark.pdf': service.watermark(source,
        watermark: const PdfWatermarkOptions(text: 'DRAFT', opacity: .25)),
    'watermark-unicode.pdf': service.watermark(PdfInput(geometryPdf()),
        watermark: PdfWatermarkOptions(text: 'Жук Αθήνα', font: font, opacity: .3)),
    'watermark-logo.pdf': service.watermark(PdfInput(geometryPdf()),
        watermark: PdfWatermarkOptions(imageBytes: redLogoPng(), opacity: .35,
            widthFraction: .4, angleDegrees: 20)),
    'image.pdf': service.insertImage(PdfInput(geometryPdf()), imageBytes: redLogoPng(),
        placement: const PdfImagePlacement(x: .1, y: .2, width: .5)),
    'ocr.pdf': service.applyOcr(PdfInput(PdfBlankDocument.create()), font: font,
        pages: [PdfOcrPage(pageIndex: 0, spans: [
          const PdfOcrSpan(text: 'Жук Αθήνα', bounds: PdfRect(72, 680, 230, 705)),
        ])]),
    'encrypted-rotate.pdf': service.rotate(encrypted),
    'encrypted-merge.pdf': service.merge([PdfMergeInput(encrypted), PdfMergeInput(source)]),
    'decrypted-extract.pdf': service.extract(encrypted, pages: '1', allowDecryption: true),
  };
  final manifest = <String, Object?>{};
  for (final entry in outputs.entries) {
    final password = entry.key.startsWith('encrypted-') ? 'test-password' : '';
    File('${destination.path}/${entry.key}').writeAsBytesSync(entry.value.bytes);
    manifest[entry.key] = {
      ...entry.value.toJson(),
      'inspection': service.inspect(PdfInput(entry.value.bytes, password: password)).toJson(),
      'text': service.text(PdfInput(entry.value.bytes, password: password)).map((page) => page.toJson()).toList(),
    };
  }
  File('${destination.path}/source.pdf').writeAsBytesSync(source.bytes);
  File('${destination.path}/geometry-source.pdf').writeAsBytesSync(geometryPdf());
  File('${destination.path}/manifest.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  stdout.writeln('Wrote ${outputs.length} PDF outputs and manifest.json.');
}
