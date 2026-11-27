import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

/// Opens a PDF with the platform's native renderer (pdfx).
///
/// pdfx's `PdfDocument.openData`/`openFile` start `assertHasPdfSupport()`
/// without awaiting it, so on a platform without native PDF rendering (Linux)
/// its `PlatformNotSupportedException` escapes as an unhandled async error that
/// no caller can catch, while the open itself fails separately. Checking first
/// turns that into one ordinary, catchable exception, so the viewer's fallback
/// to another engine runs cleanly.
Future<PdfDocument> openNativePdfData(Uint8List data) async {
  await _requireNativePdf();
  return PdfDocument.openData(data);
}

/// File-path variant of [openNativePdfData].
Future<PdfDocument> openNativePdfFile(String path) async {
  await _requireNativePdf();
  return PdfDocument.openFile(path);
}

Future<void> _requireNativePdf() async {
  if (!await hasPdfSupport()) throw PlatformNotSupportedException();
}
