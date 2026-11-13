import 'dart:async';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';

import 'archive_creation_backend.dart';

class QueueArchiveBackend extends ArchiveCreationBackend {
  QueueArchiveBackend(this.account);
  final String account;
  void Function()? afterInstall;
  @override
  StorageReference get storageReference =>
      StorageReference(kind: 'local', provider: 'fixture', accountKey: account);
  @override
  String get persistentStorageId => storageReference.id;
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
    Future<void> Function(FileItem)? verifyStaged,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) async {
    await checkpoint?.call({'phase': 'committing'});
    await super.writePreparedFile(
      path,
      data,
      length,
      replace: replace,
      verifyStaged: verifyStaged,
    );
    afterInstall?.call();
    await checkpoint?.call({'phase': 'committed'});
  }
}

/// Holds the actual creation service before compression so scheduler ordering,
/// disposal and controls can be observed without timing a particular codec.
class GatedArchiveCreation extends ArchiveCreationService {
  final entered = Completer<void>();
  final release = Completer<void>();
  int calls = 0;
  @override
  Future<ArchiveCreationResult> create({
    required FileOperationBackend source,
    required FileOperationBackend destination,
    required List<FileItem> files,
    required String destinationDirectory,
    required ArchiveCreationOptions options,
    bool Function()? isCancelled,
    FileOperationControl? control,
    bool background = false,
    String? expectedSourceManifestSha256,
    Future<void> Function(Map<String, dynamic>)? onPublicationCheckpoint,
    void Function(ArchiveCreationProgress)? onProgress,
    ArchiveCreationWriter? writer,
  }) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    await Future.any<void>([
      release.future,
      if (control != null) control.cancellationFuture,
    ]);
    await control?.checkpoint();
    return super.create(
      source: source,
      destination: destination,
      files: files,
      destinationDirectory: destinationDirectory,
      options: options,
      isCancelled: isCancelled,
      control: control,
      background: background,
      expectedSourceManifestSha256: expectedSourceManifestSha256,
      onPublicationCheckpoint: onPublicationCheckpoint,
      onProgress: onProgress,
    );
  }
}
