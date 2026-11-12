import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../utils/path_access.dart';
import 'external_remote_editing_service.dart';
import 'file_operation_backend.dart';
import 'local_file_service.dart';

/// Export streams a verified retained file into the existing staged local-write
/// contract. Its success is always an independent copy, never a remote save.
Future<bool> exportExternalEditCopy(
  ExternalEditSession session,
  String dialogTitle,
) => ExternalEditCopyExporter().export(session, dialogTitle);

class ExternalEditCopyExporter {
  ExternalEditCopyExporter({FilePicker? picker, LocalFileService? files})
    : picker = picker ?? FilePicker.platform,
      files = files ?? LocalFileService();
  final FilePicker picker;
  final LocalFileService files;

  Future<bool> export(ExternalEditSession session, String dialogTitle) async {
    final record = session.record;
    if (record == null) {
      throw const ExternalEditException(
        ExternalEditFailure.retainedUnavailable,
      );
    }
    final source = await session.workingFile(forExport: true);
    final destination = await picker.saveFile(
      dialogTitle: dialogTitle,
      fileName: record.name,
      lockParentWindow: true,
    );
    if (destination == null) return false;
    if (destination.isEmpty ||
        !p.isAbsolute(destination) ||
        isSameOrUnderPath(destination, session.directoryPath)) {
      throw const ExternalEditException(ExternalEditFailure.exportFailed);
    }
    final backend = LocalOperationBackend(
      files,
      isCurrent: () => !session.isClosed,
    );
    Future<void> write() => backend.writePreparedFile(
      destination,
      session.stage.openRead(source),
      source.length,
      replace: true,
    );
    try {
      await write();
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (!Platform.isMacOS ||
          error is! PathAccessException && code != 1 && code != 13) {
        rethrow;
      }
      final grant = await files.requestDirectoryAccess(
        initialDirectory: p.dirname(destination),
      );
      if (grant == null) return false;
      if (!isSameOrUnderPath(destination, grant)) {
        throw const ExternalEditException(ExternalEditFailure.exportFailed);
      }
      await write();
    }
    return true;
  }
}
