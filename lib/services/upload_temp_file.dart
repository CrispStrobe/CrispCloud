import 'dart:io';

import 'package:path/path.dart' as p;

import 'log_service.dart';

const _log = Log('UploadTempFile');

/// Give one native upload its own file, including when another upload uses the
/// same basename. Neither a failed write nor an upload failure leaks the folder.
Future<T> withTemporaryUploadFile<T>(
  String fileName,
  List<int> bytes,
  Future<T> Function(File file) upload, {
  String? temporaryDirectory,
}) async {
  if (fileName.isEmpty || fileName == '.' || fileName == '..' ||
      fileName.contains('/') || fileName.contains(r'\') || fileName.contains('\u0000')) {
    throw ArgumentError.value(fileName, 'fileName', 'Expected one file name.');
  }
  final root = temporaryDirectory == null ? Directory.systemTemp : Directory(temporaryDirectory);
  await root.create(recursive: true);
  final directory = await root.createTemp('crisp-upload-');
  try {
    final file = File(p.join(directory.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return await upload(file);
  } finally {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error, stack) {
      // A completed remote write must not become a failed save just because
      // removing its local temporary file failed.
      _log.warn('Could not remove temporary upload files', error, stack);
    }
  }
}
