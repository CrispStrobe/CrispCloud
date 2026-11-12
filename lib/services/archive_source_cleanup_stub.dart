import '../models/file_item.dart';
import 'file_operation_service.dart';
import 'storage_transfer_contract.dart';

Future<bool> sameNativeArchiveContainer(
  FileOperationBackend first,
  FileItem firstFile,
  FileOperationBackend second,
  FileItem secondFile,
) async => false;

Future<bool> deleteNativeArchiveImportSource(
  FileOperationBackend backend,
  FileItem source, {
  required String sha256,
  required TransferCheckpoint checkpoint,
  required TransferCheckpoint verifyPublication,
  required Object? capturedIdentity,
}) async => false;

Future<Object?> captureNativeArchiveImportSource(
  FileOperationBackend backend,
  FileItem source,
) async => null;
Future<void> verifyNativeArchiveImportSource(
  FileOperationBackend backend,
  FileItem source,
  Object? captured,
) async {}
