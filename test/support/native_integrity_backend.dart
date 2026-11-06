import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';

/// Real staged filesystem writes with a fixed test installation identity in
/// both the worker process and its restarted foreground reader.
class NativeIntegrityBackend extends LocalOperationBackend {
  NativeIntegrityBackend({this.afterWrite})
    : super(LocalFileService(), isCurrent: () => true);
  final void Function(String path)? afterWrite;
  @override
  StorageReference get storageReference => const StorageReference(
    kind: 'local',
    provider: 'local',
    accountKey: 'integrity-process-fixture',
  );
  @override
  Object get identity => storageReference.id;
  @override
  bool get canRecover => true;
  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    await super.writePreparedFile(
      path,
      data,
      length,
      replace: replace,
      verifyStaged: verifyStaged,
      checkpoint: checkpoint,
    );
    afterWrite?.call(path);
  }
}
