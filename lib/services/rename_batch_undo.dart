import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'multi_rename_service.dart';

/// Retains an entire completed batch as one undo operation. A partially
/// successful undo keeps only its remaining rows, so retrying cannot rename an
/// already restored file a second time or exhaust the 50-record history.
class RenameBatchUndo {
  RenameBatchUndo(
    MultiRenameResult result, {
    required this.pathContext,
    required this.caseSensitivePaths,
    required Map<String, FileItem?> capturedTargets,
  }) : _remaining = {
         for (final outcome in result.outcomes)
           if (outcome.status == MultiRenameStatus.renamed)
             outcome.entry.targetPath: outcome.entry,
       },
       _capturedTargets = Map.unmodifiable(capturedTargets);

  final p.Context pathContext;
  final bool caseSensitivePaths;
  final Map<String, MultiRenameEntry> _remaining;
  final Map<String, FileItem?> _capturedTargets;
  bool _running = false;

  int get remaining => _remaining.length;

  MultiRenamePlan get preview => const MultiRenameService().preview(
    _remaining.values.map((entry) => entry.renamedFile).toList(),
    const MultiRenameOptions(),
    directory: pathContext.current,
    pathContext: pathContext,
    caseSensitivePaths: caseSensitivePaths,
    targetNames: {
      for (final entry in _remaining.values)
        entry.targetPath: entry.file.name,
    },
  );

  Future<MultiRenameResult> execute({
    required Future<FileItem?> Function(String path) stat,
    required Future<void> Function(FileItem file, String newName) rename,
  }) async {
    if (_running) throw StateError('This batch is already being undone.');
    _running = true;
    try {
      final result = await const MultiRenameService().execute(
        preview,
        exists: (path) async {
          final current = await stat(path);
          if (_remaining.containsKey(path) && current != null) {
            final captured = _capturedTargets[path];
            if (captured == null || !matchesSnapshot(captured, current)) {
              throw StateError(
                'The renamed item changed or cannot be verified: $path. '
                'Undo will not rename a replacement item.',
              );
            }
          }
          return current != null;
        },
        rename: rename,
      );
      for (final outcome in result.outcomes) {
        if (outcome.status == MultiRenameStatus.renamed) {
          _remaining.remove(outcome.entry.sourcePath);
        }
      }
      return result;
    } finally {
      _running = false;
    }
  }

  /// Compare the identity/version evidence supplied by a storage backend.
  /// Missing evidence is not invented; exact provider-side conditional writes
  /// remain a backend capability, rather than a guarantee of this comparison.
  static bool matchesSnapshot(FileItem captured, FileItem current) {
    if (captured.isFolder != current.isFolder ||
        (captured.isSymlink == true) != (current.isSymlink == true) ||
        (captured.uuid != null && captured.uuid != current.uuid) ||
        (captured.size != null && captured.size != current.size) ||
        (captured.updatedAt != null &&
            (current.updatedAt == null ||
                !captured.updatedAt!.isAtSameMomentAs(current.updatedAt!)))) {
      return false;
    }
    for (final key in const [
      'id', 'fileId', 'inode', 'version', 'etag', 'eTag', 'ETag',
      'generation', 'cTag', 'rev',
    ]) {
      final expected = captured.metadata?[key];
      if (expected != null && expected != current.metadata?[key]) return false;
    }
    return true;
  }
}
