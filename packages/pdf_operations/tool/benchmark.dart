import 'dart:convert';
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_operations/pdf_operations.dart';

/// A bounded VM workflow measurement, intended to be retained as a CI artifact.
/// It reports the environment and raw observations, not an invented baseline.
void main() {
  const service = PdfOperationsService();
  final input = PdfInput(PdfBlankDocument.create(pageCount: 100));
  // Warm parser/writer code once before recording the same small workloads.
  service.rotate(input, pages: '1-100');
  final observations = <Map<String, Object?>>[];
  for (var i = 0; i < 3; i++) {
    final timer = Stopwatch()..start();
    final rotated = service.rotate(input, pages: '1-100');
    timer.stop();
    observations.add({'operation': 'rotate100', 'iteration': i,
      'microseconds': timer.elapsedMicroseconds, 'outputBytes': rotated.bytes.length});
    timer.reset();
    timer.start();
    final marked = service.watermark(input,
        watermark: const PdfWatermarkOptions(text: 'DRAFT', angleDegrees: -35));
    timer.stop();
    observations.add({'operation': 'watermark100', 'iteration': i,
      'microseconds': timer.elapsedMicroseconds, 'outputBytes': marked.bytes.length});
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'dart': Platform.version, 'os': Platform.operatingSystem,
    'inputBytes': input.bytes.length, 'inputPages': 100,
    'observations': observations,
  }));
}
