import 'package:uuid/uuid.dart';

import '../models/file_item.dart';
import '../models/transfer_job.dart';
import 'file_operation_service.dart';
import 'transfer_journal.dart';
import 'transfer_recovery_service.dart';

/// A sync copy uses the same bounded, staged backend writes as F5/F6, while
/// retaining the contents reviewed by the sync plan until the commit boundary.
class SyncTransferService {
  const SyncTransferService({this.journal});
  final TransferJournal? journal;

  Future<FileItem> copy({
    required FileOperationBackend source,
    required FileItem file,
    required FileOperationBackend destination,
    required String destinationPath,
    required FileItem? expectedDestination,
    required FileOperationControl control,
    required void Function() check,
    String? expectedSourceHash,
    String? expectedDestinationHash,
  }) async {
    check();
    await _validateVersion(source, file.path!, file);
    await _validateVersion(destination, destinationPath, expectedDestination);
    final sourceHash = await transferDigest(source, file, control);
    if (expectedSourceHash != null && sourceHash != expectedSourceHash) {
      throw StateError(
        'The reviewed sync source contents changed. Compare again.',
      );
    }
    final destinationHash = expectedDestination == null
        ? null
        : expectedDestinationHash ??
              await transferDigest(destination, expectedDestination, control);
    Future<void> validateDestination() async {
      check();
      await _validateVersion(destination, destinationPath, expectedDestination);
      if (expectedDestination != null &&
          await transferDigest(destination, expectedDestination, control) !=
              destinationHash) {
        throw StateError(
          'The reviewed sync destination contents changed. Compare again.',
        );
      }
    }

    await validateDestination();
    final plan = await const FileOperationService().prepare(
      files: [file],
      source: source,
      destination: destination,
      targetDirectory: destination.paths.dirname(destinationPath),
      options: FileOperationOptions(
        destinationName: destination.paths.basename(destinationPath),
        recursive: false,
        fileConflict: expectedDestination == null
            ? FileConflictPolicy.ask
            : FileConflictPolicy.replace,
        verifyContents: true,
        preferNative: false,
        copyMethod: FileCopyMethod.stream,
      ),
      control: control,
    );
    if (!plan.canExecute || plan.entries.length != 1) {
      throw StateError(
        plan.errors.isEmpty
            ? 'The sync copy cannot be prepared.'
            : plan.errors.join('\n'),
      );
    }
    final entry = plan.entries.single;
    entry.recovery = {
      'sourceSha256': sourceHash,
      if (destinationHash != null) 'backupSha256': destinationHash,
    };
    final id = const Uuid().v4();
    if (journal != null) {
      await journal!.create(id, plan);
      await journal!.setStatus(id, TransferJobStatus.running);
    }
    var originalBackedUp = false;
    try {
      await const FileOperationService().execute(
        plan,
        control: control,
        checkpoint: (item, phase) async {
          item.recovery = {
            ...?item.recovery,
            'phase': phase,
            if (const ['writing', 'backingUp', 'committing'].contains(phase))
              'lastMutationPhase': phase,
          };
          // Record completion/recovery evidence even after cancellation. A
          // backend must remain free to restore its verified original backup.
          if (const [
            'committed',
            'restoringBackup',
            'restoreCopied',
          ].contains(phase)) {
            await journal?.checkpoint(id, 0, item, phase);
            return;
          }
          if (phase == 'backedUp') originalBackedUp = true;
          if (!const ['failed', 'cancelled', 'complete'].contains(phase)) {
            await control.checkpoint();
            check();
          }
          if (const [
            'writing',
            'staged',
            'backingUp',
            'committing',
          ].contains(phase)) {
            await _validateVersion(source, file.path!, file);
            final copiedHash = item.recovery?['contentSha256'];
            if (copiedHash != null && copiedHash != sourceHash) {
              throw StateError(
                'The sync source changed while copying. The destination was not replaced.',
              );
            }
            if (!originalBackedUp) await validateDestination();
          }
          if (phase == 'verified') {
            final written = await destination.stat(destinationPath);
            if (written == null) {
              throw StateError('The completed sync copy is missing.');
            }
            item.recovery = {
              ...?item.recovery,
              'destinationSnapshot': transferFileJson(written),
              'dataVerified': true,
            };
          }
          await journal?.checkpoint(id, 0, item, phase);
        },
      );
      if (journal != null) {
        await journal!.saveEntries(id, plan.entries);
        await journal!.setStatus(
          id,
          entry.completed
              ? TransferJobStatus.completed
              : control.isCancelled ||
                    entry.outcome == FileOperationOutcome.cancelled
              ? TransferJobStatus.cancelled
              : TransferJobStatus.failed,
          message: entry.message,
        );
      }
      if (!entry.completed) {
        if (control.isCancelled) throw const FileOperationCancelled();
        throw StateError(entry.message ?? 'The sync copy did not complete.');
      }
      final written = await destination.stat(destinationPath);
      if (written == null || written.isFolder) {
        throw StateError('The completed sync copy is unavailable.');
      }
      return written;
    } catch (error) {
      await journal?.setStatus(
        id,
        control.isCancelled
            ? TransferJobStatus.cancelled
            : TransferJobStatus.failed,
        message: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> _validateVersion(
    FileOperationBackend backend,
    String path,
    FileItem? expected,
  ) async {
    final actual = await backend.stat(path);
    if (!backend.isCurrent ||
        (expected == null
            ? actual != null
            : actual == null || !sameTransferVersion(expected, actual))) {
      throw StateError('A reviewed sync file changed: $path. Compare again.');
    }
  }
}
