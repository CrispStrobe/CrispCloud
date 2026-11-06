import 'dart:async';

import 'package:drift/drift.dart';

import '../models/file_item.dart';
import 'cloud_storage_interface.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';
import 'sync_database.dart';
import 'sync_engine.dart';
import 'sync_source_binding.dart';
import 'sync_transfer_service.dart';
import 'transfer_journal.dart';
import 'transfer_recovery_service.dart';

/// Offline work retains the exact account/device binding chosen at enqueue.
/// Replay uses captured backends and the same verified stages as reviewed sync.
class SyncOfflineService {
  SyncOfflineService(this.db, {TransferJournal? journal})
    : _transfers = SyncTransferService(journal: journal);
  final SyncDatabase db;
  final SyncTransferService _transfers;

  Future<void> enqueue({
    required int pairId,
    required String operation,
    required String path,
    String? targetPath,
  }) async {
    final pair = await db.getPair(pairId);
    SyncSourceBinding.requireLocal(pair);
    _validate(operation, path, targetPath);
    await db.enqueueOffline(
      OfflineQueueCompanion.insert(
        pairId: pairId,
        operation: operation,
        path: path,
        targetPath: Value(targetPath),
        sourceBinding: Value(pair.sourceBinding),
      ),
    );
  }

  Future<SyncResult> execute(
    OfflineQueueEntry op,
    SyncPair pair,
    CloudStorageClient client, {
    bool Function()? isCurrent,
  }) async {
    final binding = SyncSourceBinding.require(pair, client);
    if (op.pairId != pair.id || op.sourceBinding != pair.sourceBinding) {
      throw StateError(
        'This queued operation belongs to an earlier or unverified account binding. Review and enqueue it again.',
      );
    }
    _validate(op.operation, op.path, op.targetPath);
    final saved = await db.getPair(pair.id);
    if (saved.sourceBinding != op.sourceBinding) {
      throw StateError('The sync pair changed before offline replay.');
    }
    bool current() =>
        (isCurrent?.call() ?? true) && binding.matches(pair, client);
    void check() {
      if (!current()) {
        throw StateError('The offline operation account changed.');
      }
    }

    final local = LocalOperationBackend(LocalFileService(), isCurrent: current);
    final remote = CloudOperationBackend(client, isCurrent: current);
    final control = _OfflineControl(check);
    final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!current()) control.cancel();
    });
    try {
      final localPath = local.paths.joinAll([
        pair.localPath,
        ...op.path.split('/'),
      ]);
      final remotePath = remote.paths.join(pair.remotePath, op.path);
      final isUpload = op.operation == 'upload';
      if (isUpload || op.operation == 'download') {
        final source = isUpload ? local : remote;
        final destination = isUpload ? remote : local;
        final sourcePath = isUpload ? localPath : remotePath;
        final destinationPath = isUpload ? remotePath : localPath;
        final file = await source.stat(sourcePath);
        if (file == null || file.isFolder || file.isSymlink == true) {
          throw StateError(
            'The queued source file is missing or unsupported: ${op.path}',
          );
        }
        final existing = await destination.stat(destinationPath);
        _unchangedSinceQueued(existing, op);
        await _transfers.copy(
          source: source,
          file: file,
          destination: destination,
          destinationPath: destinationPath,
          expectedDestination: existing,
          control: control,
          check: check,
        );
        return isUpload
            ? const SyncResult(uploaded: 1, replayed: 1)
            : const SyncResult(downloaded: 1, replayed: 1);
      }
      final file = await remote.stat(remotePath);
      if (file == null) {
        if (op.operation == 'delete') return const SyncResult(replayed: 1);
        throw StateError('The queued source no longer exists: ${op.path}');
      }
      _unchangedSinceQueued(file, op);
      final beforeHash = file.isFolder
          ? null
          : await transferDigest(remote, file, control);
      final latest = await remote.stat(remotePath);
      if (latest == null ||
          !sameTransferVersion(file, latest) ||
          (beforeHash != null &&
              await transferDigest(remote, latest, control) != beforeHash)) {
        throw StateError('The queued file changed during replay: ${op.path}');
      }
      check();
      if (op.operation == 'delete') {
        if (file.isFolder) {
          await remote.deleteEmptyDirectory(remotePath);
        } else {
          await remote.deleteFile(latest);
        }
        return const SyncResult(deletedRemote: 1, replayed: 1);
      }
      final target = op.operation == 'rename'
          ? remote.paths.join(remote.paths.dirname(remotePath), op.targetPath!)
          : remote.paths.join(pair.remotePath, op.targetPath!);
      if (!remote.isWithin(pair.remotePath, target) ||
          remote.samePath(remotePath, target)) {
        throw StateError('The queued destination is invalid.');
      }
      if (await remote.stat(target) != null) {
        throw StateError(
          'The queued destination already exists: ${op.targetPath}',
        );
      }
      check();
      if (!await remote.moveNoReplace(latest, target)) {
        throw UnsupportedError(
          'This provider cannot guarantee a no-replace move. Review the operation in the file manager.',
        );
      }
      return const SyncResult(replayed: 1);
    } finally {
      timer.cancel();
    }
  }

  void _unchangedSinceQueued(FileItem? file, OfflineQueueEntry op) {
    if (file == null) return;
    if (file.isSymlink == true ||
        file.updatedAt == null ||
        file.updatedAt!.isAfter(op.createdAt)) {
      throw StateError(
        'Conflict: ${op.path} changed after this operation was queued, or its version cannot be verified. Compare the pair before retrying.',
      );
    }
  }

  void _validate(String operation, String path, String? targetPath) {
    if (!const [
      'upload',
      'download',
      'delete',
      'rename',
      'move',
    ].contains(operation)) {
      throw UnsupportedError('Unknown offline operation: $operation');
    }
    validateSyncRelativePath(path);
    if (operation == 'rename' || operation == 'move') {
      if (targetPath == null) {
        throw const FormatException('A destination is required.');
      }
      validateSyncRelativePath(targetPath);
      if (operation == 'rename' && targetPath.contains('/')) {
        throw const FormatException('A rename needs a filename, not a path.');
      }
    }
  }
}

class _OfflineControl extends FileOperationControl {
  _OfflineControl(this.check);
  final void Function() check;
  @override
  Future<void> checkpoint() async {
    try {
      check();
      await super.checkpoint();
      check();
    } catch (_) {
      cancel();
      rethrow;
    }
  }
}
