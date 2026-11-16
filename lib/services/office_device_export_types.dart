import 'dart:typed_data';

/// A copy never establishes that the captured original was saved.
enum OfficeCopyOutcome { savedCopy, downloadedCopy }

typedef OfficeDeviceExporter = Future<OfficeCopyOutcome?> Function(
  Uint8List bytes,
  String suggestedName,
  String dialogTitle, {
  String? initialDirectory,
});

/// Returns a writable device path after a completed Save As, or null on cancel.
/// A download is not a writable target and must never be adopted by the editor.
typedef OfficeSaveAsExporter = Future<String?> Function(
  Uint8List bytes,
  String suggestedName,
  String dialogTitle, {
  String? initialDirectory,
});
