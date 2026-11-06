import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../utils/path_access.dart';
import 'gallery_device_export_types.dart';
import 'local_file_service.dart';

Future<GalleryExportResult?> exportGalleryFile(
  Uint8List bytes,
  String suggestedName, {
  String? mimeType,
  String? dialogTitle,
}) => NativeGalleryDeviceExport().exportCopy(
  bytes,
  suggestedName,
  mimeType: mimeType,
  dialogTitle: dialogTitle,
);

/// Mobile document providers write the supplied bytes; desktop pickers choose
/// a destination which is then written using CrispCloud's staged file service.
class NativeGalleryDeviceExport {
  NativeGalleryDeviceExport({
    FilePicker? picker,
    LocalFileService? files,
    bool? useNativeDocumentExport,
    bool? requestMacOSFolderAccess,
  }) : _picker = picker ?? FilePicker.platform,
       _files = files ?? LocalFileService(),
       _useNativeDocumentExport =
           useNativeDocumentExport ?? (Platform.isAndroid || Platform.isIOS),
       _requestMacOSFolderAccess = requestMacOSFolderAccess ?? Platform.isMacOS;

  final FilePicker _picker;
  final LocalFileService _files;
  final bool _useNativeDocumentExport;
  final bool _requestMacOSFolderAccess;

  Future<GalleryExportResult?> exportCopy(
    Uint8List bytes,
    String suggestedName, {
    String? mimeType,
    String? dialogTitle,
  }) async {
    final destination = await _picker.saveFile(
      dialogTitle: dialogTitle ?? 'Save a copy',
      fileName: suggestedName,
      type: FileType.any,
      bytes: _useNativeDocumentExport ? bytes : null,
      lockParentWindow: true,
    );
    if (destination == null) return null;
    if (destination.isEmpty) {
      throw StateError('The save dialog returned no destination.');
    }
    if (_useNativeDocumentExport) return GalleryExportResult.savedCopy;

    // The exact chosen path owns overwrite approval. Appending an extension
    // after the picker would target a different, unapproved file.
    Future<LocalFileSaveResult> write() =>
        _files.saveFileReportingResult(destination, bytes);
    LocalFileSaveResult result;
    try {
      result = await write();
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (!_requestMacOSFolderAccess ||
          (error is! PathAccessException && code != 1 && code != 13)) {
        rethrow;
      }
      final grant = await _files.requestDirectoryAccess(
        initialDirectory: File(destination).parent.path,
      );
      if (grant == null) return null;
      if (!isSameOrUnderPath(destination, grant)) {
        throw FileSystemException(
          'Grant access to the folder containing the selected destination.',
          destination,
        );
      }
      result = await write();
    }
    return result == LocalFileSaveResult.written
        ? GalleryExportResult.savedCopy
        : GalleryExportResult.downloadedCopy;
  }
}
