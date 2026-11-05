import 'dart:typed_data';

import 'gallery_device_export_native.dart'
    if (dart.library.html) 'gallery_device_export_web.dart'
    as platform;
import 'gallery_device_export_types.dart';

export 'gallery_device_export_types.dart';

const kGalleryExportLimitBytes = 128 * 1024 * 1024;

final _galleryDeviceExport = GalleryDeviceExport();

/// Save an independent image, contact sheet or catalog export to the device.
///
/// The original file is never used as a destination. A native picker owns the
/// destination and overwrite confirmation; null means the picker was cancelled.
Future<GalleryExportResult?> exportGalleryFile(
  Uint8List bytes,
  String suggestedName, {
  String? mimeType,
  String? dialogTitle,
}) => _galleryDeviceExport.exportCopy(
  bytes,
  suggestedName,
  mimeType: mimeType,
  dialogTitle: dialogTitle,
);

class GalleryDeviceExport {
  GalleryDeviceExport({GalleryDeviceExporter? exporter})
      : _exporter = exporter ?? platform.exportGalleryFile;

  final GalleryDeviceExporter _exporter;

  Future<GalleryExportResult?> exportCopy(
    Uint8List bytes,
    String suggestedName, {
    String? mimeType,
    String? dialogTitle,
  }) async {
    if (bytes.length > kGalleryExportLimitBytes) {
      throw StateError('The export exceeds the 128 MB device export limit.');
    }
    // Hold the exact exported revision while the save dialog is open.
    final snapshot = Uint8List.fromList(bytes).asUnmodifiableView();
    var name = suggestedName.replaceAll('\\', '/').split('/').last.trim();
    name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_');
    if (name.isEmpty || name == '.' || name == '..') name = 'image.bin';
    return _exporter(
      snapshot,
      name,
      mimeType: mimeType,
      dialogTitle: dialogTitle,
    );
  }
}
