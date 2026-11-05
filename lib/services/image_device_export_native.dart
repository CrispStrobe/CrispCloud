import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../utils/path_access.dart';
import 'image_edit_session.dart';
import 'local_file_service.dart';

Future<ImageSaveOutcome?> exportImageCopy(
  Uint8List bytes,
  String suggestedName,
  String dialogTitle,
  ImageFileFormat format,
) async {
  final mobile = Platform.isAndroid || Platform.isIOS;
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: suggestedName,
    type: FileType.custom,
    allowedExtensions: format == ImageFileFormat.png
        ? ['png']
        : ['jpg', 'jpeg'],
    bytes: mobile ? bytes : null,
    lockParentWindow: true,
  );
  if (path == null) return null;
  if (path.isEmpty) throw StateError('Empty export destination');
  if (mobile) return ImageSaveOutcome.savedCopy;
  // Do not alter the approved path or silently write mismatched image bytes.
  if (imageFileFormatForName(path) != format) {
    throw const ImageEditException(ImageEditFailure.formatMismatch);
  }
  final files = LocalFileService();
  Future<LocalFileSaveResult> write() =>
      files.saveFileReportingResult(path, bytes);
  LocalFileSaveResult result;
  try {
    result = await write();
  } on FileSystemException catch (error) {
    final code = error.osError?.errorCode;
    if (!Platform.isMacOS ||
        (error is! PathAccessException && code != 1 && code != 13))
      rethrow;
    final grant = await files.requestDirectoryAccess(
      initialDirectory: File(path).parent.path,
    );
    if (grant == null) return null;
    if (!isSameOrUnderPath(path, grant)) rethrow;
    result = await write();
  }
  return result == LocalFileSaveResult.written
      ? ImageSaveOutcome.savedCopy
      : ImageSaveOutcome.downloadedCopy;
}
