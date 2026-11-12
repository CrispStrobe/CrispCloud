import 'package:crisp_cloud/services/archive_publication_access_policy.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';

import 'workflow_fake_client.dart';

/// Explicitly private, exact and version-guarded fixture; the production remote
/// adapters deliberately do not claim this access-policy contract.
class ArchiveWorkflowClient extends WorkflowFakeClient
    with CloudTransferOperations {
  final versions = <String, int>{};
  int _version = 0;
  @override
  void put(String path, List<int> bytes, {DateTime? date}) {
    super.put(path, bytes, date: date);
    versions[path] = ++_version;
  }

  @override
  String get transferIdentity => 'archive-workspace-fixture';
  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(
        caseSensitivity: StorageCaseSensitivity.sensitive,
        nativeMove: true,
        atomicMove: true,
        noReplaceMove: true,
        conditionalMove: true,
        conditionalDelete: true,
        deleteEmptyDirectory: true,
      );
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    final listing = await super.listPath(path);
    for (final item in listing['files'] as List) {
      item['etag'] = '${versions[item['path']]}';
    }
    return listing;
  }

  @override
  Future<CloudTransferResult> moveToExact(
    String sourcePath,
    String destinationPath, {
    bool replace = false,
    String? expectedSourceVersion,
    String? expectedDestinationVersion,
    TransferCheckpoint? checkpoint,
  }) async {
    await checkpoint?.call();
    if (replace ||
        files.containsKey(destinationPath) ||
        directories.contains(destinationPath) ||
        !files.containsKey(sourcePath)) {
      throw StateError('Exclusive move collision.');
    }
    if (expectedSourceVersion != null &&
        expectedSourceVersion != '${versions[sourcePath]}') {
      throw StateError('Move source changed.');
    }
    await movePath(sourcePath, destinationPath);
    versions.remove(sourcePath);
    return CloudTransferResult(
      path: destinationPath,
      version: '${versions[destinationPath]}',
      size: files[destinationPath]!.length,
    );
  }

  @override
  Future<void> deleteTransferFile(
    String path, {
    String? expectedVersion,
  }) async {
    if (expectedVersion == null || expectedVersion != '${versions[path]}') {
      throw StateError('Delete source changed.');
    }
    await deletePath(path);
    versions.remove(path);
  }

  @override
  Future<void> deleteDirectoryIfEmpty(String path) async {
    if (files.keys.any((key) => key.startsWith('$path/')) ||
        directories.any((key) => key.startsWith('$path/'))) {
      throw StateError('Directory is not empty.');
    }
    await deletePath(path);
  }
}

class ArchiveWorkflowBackend extends CloudOperationBackend
    implements ArchivePublicationAccessPolicy {
  ArchiveWorkflowBackend(super.client, {required super.isCurrent});
  @override
  bool get preservesArchiveAccessPolicy => true;
}
