import '../models/file_item.dart';
import 'archive_creation_service.dart';
import 'archive_creation_worker.dart';
import 'local_file_service.dart';

Future<ArchiveCreationWorker> startArchiveCreationWorker({
  required LocalFileService local,
  required List<FileItem> files,
  required String destinationDirectory,
  required ArchiveCreationOptions options,
  required void Function(ArchiveCreationProgress) onProgress,
  required Future<void> Function(ArchiveCreationPrepared) onPrepared,
}) async => throw UnsupportedError(
  'Background archive creation is available on desktop only.',
);
