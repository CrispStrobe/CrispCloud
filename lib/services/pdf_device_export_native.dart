import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../utils/path_access.dart';
import 'local_file_service.dart';
import 'pdf_edit_session.dart';

Future<PdfSaveOutcome?> exportPdfCopy(Uint8List bytes, String suggestedName) =>
    NativePdfDeviceExport().exportCopy(bytes, suggestedName);

/// Desktop save dialogs choose a path; mobile document providers do the write.
///
/// FilePicker 10.3.x requires bytes on Android/iOS. Their returned URI/path is
/// not a dart:io destination and must not be written a second time. Desktop
/// pickers receive no bytes, leaving the write to our staged local service.
class NativePdfDeviceExport {
  NativePdfDeviceExport({
    FilePicker? picker,
    LocalFileService? files,
    bool? useNativeDocumentExport,
    bool? requestMacOSFolderAccess,
  })  : _picker = picker ?? FilePicker.platform,
        _files = files ?? LocalFileService(),
        _useNativeDocumentExport =
            useNativeDocumentExport ?? (Platform.isAndroid || Platform.isIOS),
        _requestMacOSFolderAccess = requestMacOSFolderAccess ?? Platform.isMacOS;

  final FilePicker _picker;
  final LocalFileService _files;
  final bool _useNativeDocumentExport;
  final bool _requestMacOSFolderAccess;

  Future<PdfSaveOutcome?> exportCopy(
    Uint8List bytes,
    String suggestedName,
  ) async {
    final path = await _picker.saveFile(
      dialogTitle: 'Export a PDF copy',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: _useNativeDocumentExport ? bytes : null,
      lockParentWindow: true,
    );
    if (path == null) return null;
    if (path.isEmpty) throw StateError('The save dialog returned no destination.');
    if (_useNativeDocumentExport) return PdfSaveOutcome.savedCopy;

    // Use exactly the path confirmed by the native save dialog, which owns
    // overwrite confirmation. Appending/changing its extension here could
    // overwrite a different path that the user did not approve.
    Future<LocalFileSaveResult> write() =>
        _files.saveFileReportingResult(path, bytes);
    LocalFileSaveResult result;
    try {
      result = await write();
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (!_requestMacOSFolderAccess ||
          (error is! PathAccessException && code != 1 && code != 13)) {
        rethrow;
      }
      // A macOS save panel may grant only the chosen file. Staging a sibling
      // needs its containing folder's scope. Ask through the existing bookmark
      // service only when the filesystem actually denied that operation.
      final grant = await _files.requestDirectoryAccess(
        initialDirectory: File(path).parent.path,
      );
      if (grant == null) return null;
      if (!isSameOrUnderPath(path, grant)) {
        throw FileSystemException(
          'Grant access to the folder containing the selected destination.',
          path,
        );
      }
      result = await write();
    }
    return result == LocalFileSaveResult.written
        ? PdfSaveOutcome.savedCopy
        : PdfSaveOutcome.downloadedCopy;
  }
}
