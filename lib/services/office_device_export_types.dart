import 'dart:typed_data';

/// A copy never establishes that the captured original was saved.
enum OfficeCopyOutcome { savedCopy, downloadedCopy }

typedef OfficeDeviceExporter = Future<OfficeCopyOutcome?> Function(
  Uint8List bytes,
  String suggestedName,
  String dialogTitle,
);
