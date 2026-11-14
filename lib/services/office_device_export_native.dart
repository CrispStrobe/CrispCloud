import 'dart:typed_data';

import 'office_device_export_types.dart';
import 'pdf_device_export_native.dart';
import 'pdf_edit_session.dart';

Future<OfficeCopyOutcome?> exportOfficeCopy(
  Uint8List bytes,
  String name,
  String dialogTitle,
) async {
  final result = await NativePdfDeviceExport(
    dialogTitle: dialogTitle,
    allowedExtensions: [name.toLowerCase().split('.').last],
  ).exportCopy(bytes, name);
  return switch (result) {
    null => null,
    PdfSaveOutcome.downloadedCopy => OfficeCopyOutcome.downloadedCopy,
    _ => OfficeCopyOutcome.savedCopy,
  };
}
