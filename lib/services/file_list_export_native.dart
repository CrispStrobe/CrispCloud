import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../utils/path_access.dart';
import 'local_file_service.dart';

Future<String?> exportFileListText(String text) async {
  final bytes = Uint8List.fromList(utf8.encode(text));
  final mobile = Platform.isAndroid || Platform.isIOS;
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export file list',
    fileName: 'file-list.txt',
    type: FileType.custom,
    allowedExtensions: const ['txt', 'lst'],
    bytes: mobile ? bytes : null,
    lockParentWindow: true,
  );
  if (path == null) return null;
  if (path.isEmpty) {
    throw StateError('The save dialog returned no destination.');
  }
  if (mobile) return 'File list saved.';
  final files = LocalFileService();
  Future<void> write() async {
    await files.saveFileReportingResult(path, bytes);
  }

  try {
    await write();
  } on FileSystemException catch (error) {
    final code = error.osError?.errorCode;
    if (!Platform.isMacOS ||
        (error is! PathAccessException && code != 1 && code != 13)) {
      rethrow;
    }
    final grant = await files.requestDirectoryAccess(
      initialDirectory: File(path).parent.path,
    );
    if (grant == null) return null;
    if (!isSameOrUnderPath(path, grant)) {
      throw FileSystemException(
        'Grant access to the folder containing the chosen list file.',
        path,
      );
    }
    await write();
  }
  return 'File list saved.';
}
