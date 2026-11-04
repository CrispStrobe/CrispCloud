// lib/services/office_pdf_service.dart
//
// Renders Office documents (DOCX / XLSX / PPTX) to a paginated PDF using the
// pure-Dart `quds_office_engine` (MIT, no native code, all platforms).
//
// The resulting PDF is displayed with the existing pdfx page viewer, so slides
// keep their real layout and the PDF text layer remains extractable.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:quds_office_engine/quds_office_engine.dart';

const int kOfficePdfInputCap = 64 * 1024 * 1024;

class OfficePdfException implements Exception {
  final String message;
  const OfficePdfException(this.message);

  @override
  String toString() => message;
}

/// Convert [bytes] (DOCX/XLSX/PPTX) to PDF bytes.
///
/// Runs on a background isolate on native platforms. Throws
/// [OfficePdfException] for unsupported/corrupt input or when conversion
/// exceeds the input cap.
Future<Uint8List> convertOfficeToPdf(
  Uint8List bytes, {
  String? password,
}) async {
  if (bytes.length > kOfficePdfInputCap) {
    throw OfficePdfException(
      'This document is too large to lay out safely '
      '(${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB).',
    );
  }

  final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
  final fontBytes = fontData.buffer.asUint8List(
    fontData.offsetInBytes,
    fontData.lengthInBytes,
  );

  Uint8List render() {
    final font = SfntFont.parse(fontBytes);
    return OfficePdfExport.fromBytes(
      bytes,
      font: font,
      password: password,
    );
  }

  try {
    if (kIsWeb) {
      // Isolates are unavailable on the web; run inline.
      return render();
    }
    return await Isolate.run(render);
  } catch (e) {
    throw OfficePdfException('Could not lay out this document: $e');
  }
}
