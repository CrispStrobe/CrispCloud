import 'dart:typed_data';

/// A browser download is an initiated download, not proof of a persisted file.
enum GalleryExportResult { savedCopy, downloadedCopy }

typedef GalleryDeviceExporter = Future<GalleryExportResult?> Function(
  Uint8List bytes,
  String suggestedName, {
  String? mimeType,
  String? dialogTitle,
});
