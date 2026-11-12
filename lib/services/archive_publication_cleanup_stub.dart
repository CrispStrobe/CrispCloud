import '../models/file_item.dart';
import 'file_operation_service.dart';
import 'storage_transfer_contract.dart';

Future<bool> deleteNativeArchiveRecoveryFile(
  FileOperationBackend backend,
  FileItem recovery,
  FileItem published, {
  required String recoverySha256,
  required String publishedSha256,
  required TransferCheckpoint checkpoint,
}) async => false;
