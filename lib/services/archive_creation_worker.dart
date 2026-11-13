import '../models/file_item.dart';
import 'archive_creation_service.dart';
import 'local_file_service.dart';
import 'archive_creation_worker_stub.dart'
    if (dart.library.io) 'archive_creation_worker_io.dart'
    as platform;

/// One native archive attempt. Its result includes orderly worker exit and
/// release of the access scopes acquired on the originating isolate.
abstract interface class ArchiveCreationWorker {
  Future<ArchiveCreationResult> get result;

  /// Requests cooperative cancellation, resuming a paused worker first.
  /// A completed exclusive publication remains a successful result.
  void cancel();

  void pause();
  void resume();

  /// Cancels unfinished work and waits for its actual exit. Never kills an
  /// isolate that might be publishing a verified destination.
  Future<void> close();
}

/// Runs codec work on a separate desktop isolate. Access grants and callbacks
/// remain on the originating isolate. Passwords cross only the ephemeral
/// worker message; this API never journals or logs its request.
Future<ArchiveCreationWorker> startArchiveCreationWorker({
  required LocalFileService local,
  required List<FileItem> files,
  required String destinationDirectory,
  required ArchiveCreationOptions options,
  required void Function(ArchiveCreationProgress) onProgress,
  required Future<void> Function(ArchiveCreationPrepared) onPrepared,
}) => platform.startArchiveCreationWorker(
  local: local,
  files: files,
  destinationDirectory: destinationDirectory,
  options: options,
  onProgress: onProgress,
  onPrepared: onPrepared,
);
