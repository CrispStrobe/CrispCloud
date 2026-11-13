import '../models/archive_job.dart';
import '../models/transfer_job.dart';
import 'archive_creation_service.dart';
import 'file_operation_service.dart';
import 'transfer_recovery_service.dart';

class ArchiveCreationRecoveryReview {
  const ArchiveCreationRecoveryReview._({
    required this.jobId,
    required this.definition,
    required this.source,
    required this.destination,
    this.result,
  });
  final String jobId;
  final ArchiveCreationJobDefinition definition;
  final FileOperationBackend source;
  final FileOperationBackend destination;
  final ArchiveCreationResult? result;
  bool get alreadyPublished => result != null;
}

/// Review is read-only. An interrupted compressor starts a fresh private
/// candidate, never appends at a guessed byte offset or overwrites an output.
class ArchiveJobRecoveryService {
  const ArchiveJobRecoveryService();

  Future<ArchiveCreationRecoveryReview> prepareCreation(
    TransferJobRecord job, {
    required FileOperationBackend source,
    required FileOperationBackend destination,
    FileOperationControl? control,
  }) async {
    final definition = ArchiveCreationJobDefinition.fromJob(job);
    final gate = control ?? FileOperationControl();
    void check() {
      if (!job.canRecover ||
          job.source != source.storageReference ||
          job.destination != destination.storageReference ||
          !source.isCurrent ||
          !destination.isCurrent) {
        throw StateError(
          'Reconnect the exact original source and destination to review this archive.',
        );
      }
      if (gate.isCancelled) throw const FileOperationCancelled();
    }

    await gate.checkpoint();
    check();
    if (!destination.samePath(
      definition.outputPath,
      destination.paths.join(definition.destinationDirectory, definition.name),
    )) {
      throw const FormatException(
        'The saved archive destination does not match its recipe.',
      );
    }
    final eventPath = definition.publication['destination'];
    if (eventPath != null &&
        (eventPath is! String ||
            !destination.samePath(eventPath, definition.outputPath))) {
      throw const FormatException(
        'The archive receipt belongs to another destination.',
      );
    }
    final output = await destination.stat(definition.outputPath);
    await gate.checkpoint();
    check();
    if (output != null) {
      final expectedBytes = definition.publication['packedBytes'];
      final expectedHash = definition.publication['packedSha256'];
      final entryCount = definition.publication['entryCount'];
      if (output.isFolder ||
          output.isSymlink == true ||
          expectedBytes is! int ||
          expectedHash is! String ||
          entryCount is! int ||
          output.size != expectedBytes) {
        throw StateError(
          'The output already exists and cannot be confirmed as this job’s archive. It will not be replaced.',
        );
      }
      final actual = await transferDigest(destination, output, gate);
      check();
      if (actual != expectedHash) {
        throw StateError(
          'The output differs from the saved archive receipt. It will not be replaced.',
        );
      }
      return ArchiveCreationRecoveryReview._(
        jobId: job.id,
        definition: definition,
        source: source,
        destination: destination,
        result: ArchiveCreationResult(
          definition.outputPath,
          entryCount,
          expectedBytes,
        ),
      );
    }
    final directory = await destination.stat(definition.destinationDirectory);
    await gate.checkpoint();
    check();
    if (directory == null ||
        !directory.isFolder ||
        directory.isSymlink == true) {
      throw StateError('The original destination directory is unavailable.');
    }
    for (final file in definition.files) {
      await gate.checkpoint();
      check();
      final current = await source.stat(file.path!);
      if (current == null || !sameTransferVersion(file, current)) {
        throw StateError(
          'An archive source changed after it was queued: ${file.path}',
        );
      }
    }
    check();
    return ArchiveCreationRecoveryReview._(
      jobId: job.id,
      definition: definition,
      source: source,
      destination: destination,
    );
  }
}
