import 'dart:typed_data';

import 'image_device_export_native.dart'
    if (dart.library.html) 'image_device_export_web.dart'
    as platform;
import 'image_edit_session.dart';
import 'image_export_options.dart';
import 'image_edit_project.dart';

typedef ImageProjectExporter = Future<ImageSaveOutcome?> Function(
  Uint8List bytes,
  String suggestedName,
  String dialogTitle,
);

typedef ImageDeviceExporter = Future<ImageSaveOutcome?> Function(
  Uint8List bytes,
  String suggestedName,
  String dialogTitle,
  ImageExportFormat format,
);

/// Writes an independent copy; a browser download never marks the source saved.
Future<ImageSaveOutcome?> exportImageCopy(
  Uint8List bytes,
  String suggestedName,
  String dialogTitle,
  ImageExportFormat format,
) => ImageDeviceExport().exportCopy(bytes, suggestedName, dialogTitle, format);

class ImageDeviceExport {
  ImageDeviceExport({ImageDeviceExporter? exporter})
    : _exporter = exporter ?? platform.exportImageCopy;

  final ImageDeviceExporter _exporter;

  Future<ImageSaveOutcome?> exportCopy(
    Uint8List bytes,
    String suggestedName,
    String dialogTitle,
    ImageExportFormat format,
  ) async {
    validateImageExport(bytes, format);
    return _exporter(
      Uint8List.fromList(bytes).asUnmodifiableView(),
      suggestedName,
      dialogTitle,
      format,
    );
  }
}

/// Saves a validated self-contained project without changing the source image.
Future<ImageSaveOutcome?> exportImageProjectCopy(
  Uint8List bytes,
  String suggestedName,
  String dialogTitle,
) async {
  ImageEditProject.decode(bytes);
  return platform.exportProjectCopy(
    Uint8List.fromList(bytes).asUnmodifiableView(),
    suggestedName,
    dialogTitle,
  );
}
