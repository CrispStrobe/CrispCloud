import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart:typed_data';

import 'office_device_export_types.dart';
import 'pdf_device_export_native.dart';
import 'pdf_edit_session.dart';

Future<OfficeCopyOutcome?> exportOfficeCopy(
  Uint8List bytes,
  String name,
  String dialogTitle, {
  String? initialDirectory,
}) async {
  final result = await NativePdfDeviceExport(
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
    allowedExtensions: [name.toLowerCase().split('.').last],
  ).exportCopy(bytes, name);
  return switch (result) {
    null => null,
    PdfSaveOutcome.downloadedCopy => OfficeCopyOutcome.downloadedCopy,
    _ => OfficeCopyOutcome.savedCopy,
  };
}

Future<String?> saveOfficeAs(
  Uint8List bytes,
  String name,
  String dialogTitle, {
  String? initialDirectory,
}) async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    throw UnsupportedError(
      'Save As requires a writable file destination. Use Save a copy for document exports.',
    );
  }
  final extension = p.extension(name).toLowerCase();
  final result = await NativePdfDeviceExport(
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
    allowedExtensions: [extension.substring(1)],
    validateDestination: (path) {
      if (p.extension(path).toLowerCase() != extension) {
        throw FormatException(
          'Keep the $extension extension for this document format.',
        );
      }
    },
  ).exportWithDestination(bytes, name);
  if (result == null) return null;
  if (result.outcome != PdfSaveOutcome.savedCopy) {
    throw StateError(
      'The document was downloaded without a writable save destination.',
    );
  }
  return result.path;
}
