import 'dart:typed_data';

import 'pdf_device_export_native.dart'
    if (dart.library.html) 'pdf_device_export_web.dart'
    as platform;
import 'pdf_edit_session.dart';
import 'pdf_file_store.dart'
    show PdfFileTooLargeException, kPdfEditorOutputLimitBytes;

typedef PdfDeviceExporter = Future<PdfSaveOutcome?> Function(
  Uint8List bytes,
  String suggestedName,
);

final _deviceExport = PdfDeviceExport();

/// Export an independent recovery copy, even after a remote account disconnects.
///
/// Null means the native picker was cancelled. A browser download returns
/// [PdfSaveOutcome.downloadedCopy] when initiated, without claiming that the
/// browser/user persisted it. Neither success updates the original's baseline.
Future<PdfSaveOutcome?> exportPdfCopy(Uint8List bytes, String suggestedName) =>
    _deviceExport.exportCopy(bytes, suggestedName);

/// Owns the revision before opening a picker. The injected exporter is also a
/// narrow seam for testing cancellation, errors and in-flight edits.
class PdfDeviceExport {
  PdfDeviceExport({PdfDeviceExporter? exporter})
    : _exporter = exporter ?? platform.exportPdfCopy;

  final PdfDeviceExporter _exporter;

  Future<PdfSaveOutcome?> exportCopy(
    Uint8List bytes,
    String suggestedName,
  ) async {
    if (bytes.length > kPdfEditorOutputLimitBytes) {
      throw const PdfFileTooLargeException(kPdfEditorOutputLimitBytes);
    }
    final snapshot = Uint8List.fromList(bytes).asUnmodifiableView();
    var name = suggestedName.replaceAll('\\', '/').split('/').last.trim();
    name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    if (name.isEmpty || name == '.' || name == '..') name = 'document.pdf';
    if (!name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
    return _exporter(snapshot, name);
  }
}
