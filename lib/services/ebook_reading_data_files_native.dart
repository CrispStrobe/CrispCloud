import 'dart:typed_data';

import 'ebook_edit_session.dart';
import 'ebook_file_store.dart';
import 'pdf_device_export_native.dart';

Future<EbookSaveOutcome?> exportReadingData(
  Uint8List bytes,
  String name,
) async {
  final result = await NativePdfDeviceExport(
    dialogTitle: 'Export reading data',
    allowedExtensions: const ['json'],
  ).exportCopy(bytes, name);
  return result == null ? null : ebookSaveOutcome(result);
}
