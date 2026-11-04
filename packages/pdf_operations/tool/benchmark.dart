import 'dart:convert';
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_operations/pdf_operations.dart';

/// A bounded VM workflow measurement, intended to be retained as a CI artifact.
/// It reports the environment and raw observations, not an invented baseline.
void main() {
  const service = PdfOperationsService();
  final source = PdfDocument.open(PdfBlankDocument.create(pageCount: 100));
  final seed = PdfEditor(source);
  for (var page = 0; page < 100; page += 10) {
    final field = seed.addTextField(
        page, 'benchmark.${page + 1}', const PdfRect(72, 620, 380, 650));
    seed.setTextValue(field, 'Page ${page + 1}');
  }
  final input = PdfInput(seed.save());
  final ocrInput = PdfInput(PdfBlankDocument.create(pageCount: 10));
  final font = PdfEmbeddedFont.parse(
      File('test/fonts/CrispPdfTestSans.ttf').readAsBytesSync());
  final recognition = [
    for (var page = 0; page < 10; page++)
      PdfOcrPage(pageIndex: page, spans: [
        for (var row = 0; row < 10; row++)
          PdfOcrSpan(
              text: 'Жук Αθήνα ${row + 1}',
              bounds: PdfRect(72, 700.0 - row * 32, 280, 724.0 - row * 32)),
      ]),
  ];
  PdfOperationResult ocr() =>
      service.applyOcr(ocrInput, pages: recognition, font: font);
  // Warm parser/writer code once before recording the same small workloads.
  service.rotate(input, pages: '1-100');
  service.watermark(input,
      watermark: const PdfWatermarkOptions(text: 'DRAFT', angleDegrees: -35));
  service.extract(input, pages: '100-51');
  ocr();
  final observations = <Map<String, Object?>>[];
  for (var i = 0; i < 3; i++) {
    void measure(String operation, PdfOperationResult Function() run) {
      final timer = Stopwatch()..start();
      final result = run();
      timer.stop();
      observations.add({
        'operation': operation,
        'iteration': i,
        'microseconds': timer.elapsedMicroseconds,
        'outputPages': result.pageCount,
        'outputBytes': result.bytes.length
      });
    }

    measure('rotate100', () => service.rotate(input, pages: '1-100'));
    measure(
        'watermark100',
        () => service.watermark(input,
            watermark:
                const PdfWatermarkOptions(text: 'DRAFT', angleDegrees: -35)));
    measure('extract50DescendingWithForms',
        () => service.extract(input, pages: '100-51'));
    measure('unicodeOcr100Spans10Pages', ocr);
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'dart': Platform.version,
    'os': Platform.operatingSystem,
    'inputBytes': input.bytes.length,
    'inputPages': 100,
    'inputFormFields': 10,
    'ocrInputBytes': ocrInput.bytes.length,
    'ocrInputPages': 10,
    'ocrSpanCount': 100,
    'ocrFontBytes': font.fontBytes.length,
    'observations': observations,
  }));
}
