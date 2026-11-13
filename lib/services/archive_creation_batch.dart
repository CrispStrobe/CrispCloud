import '../models/file_item.dart';
import 'archive_creation_service.dart';

/// One independently verified output in a reviewed creation batch. Credentials
/// remain in memory; the queue persists only whether a password is required.
class ArchiveCreationBatchItem {
  ArchiveCreationBatchItem({
    required List<FileItem> files,
    required this.destinationDirectory,
    required this.options,
  }) : files = List.unmodifiable(files);
  final List<FileItem> files;
  final String destinationDirectory;
  final ArchiveCreationOptions options;
}

/// Keep the complete original filename so report.txt and report.csv cannot
/// silently collapse into the same report.zip output in a separate-file batch.
String archiveCreationBatchName(FileItem file, ArchiveCreationFormat format) =>
    '${file.name}${format.extension}';

List<ArchiveCreationBatchItem> planArchiveCreationBatch({
  required List<FileItem> files,
  required String destinationDirectory,
  required ArchiveCreationOptions options,
}) {
  if (files.isEmpty) {
    throw const ArchiveCreationException(ArchiveCreationError.emptySelection);
  }
  final result = <ArchiveCreationBatchItem>[];
  for (final file in files) {
    if (file.path == null ||
        file.isSymlink == true ||
        file.isFolder && !options.format.supportsDirectories) {
      throw ArchiveCreationException(
        ArchiveCreationError.unsupportedEntry,
        file.name,
      );
    }
    final selected = ArchiveCreationOptions(
      name: archiveCreationBatchName(file, options.format),
      format: options.format,
      compression: options.compression,
      password: options.password,
      encryptNames: options.encryptNames,
    );
    selected.validate();
    result.add(
      ArchiveCreationBatchItem(
        files: [file],
        destinationDirectory: destinationDirectory,
        options: selected,
      ),
    );
  }
  return List.unmodifiable(result);
}
