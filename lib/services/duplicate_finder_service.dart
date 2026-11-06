import 'package:crypto/crypto.dart';

import '../models/file_item.dart';
import 'file_operation_service.dart';

class DuplicateScanResult {
  const DuplicateScanResult({
    required this.groups,
    required this.errors,
    required this.cancelled,
    required this.checkedFiles,
  });
  final List<List<FileItem>> groups;
  final List<String> errors;
  final bool cancelled;
  final int checkedFiles;
}

/// Same-size items are candidates only. Every reported group has matching
/// SHA-256 hashes calculated from full content, from the captured source.
class DuplicateFinderService {
  Future<DuplicateScanResult> scan(
    FileOperationBackend source,
    Iterable<FileItem> files, {
    bool Function()? isCancelled,
    void Function(int checked, int total)? onProgress,
  }) async {
    final sizes = <int, List<FileItem>>{};
    final seen = <String>{};
    final errors = <String>[];
    for (final file in files) {
      if (file.isFolder || file.isSymlink == true || file.path == null)
        continue;
      if (!seen.add(source.pathKey(file.path!))) continue;
      final size = file.size;
      if (size == null || size < 0) {
        errors.add(
          '${file.path}: size is unknown; not classified as a duplicate.',
        );
      } else {
        sizes.putIfAbsent(size, () => []).add(file);
      }
    }
    final candidates = sizes.values.where((group) => group.length > 1);
    final total = candidates.fold<int>(0, (sum, group) => sum + group.length);
    var checked = 0;
    var cancelled = false;
    final groups = <List<FileItem>>[];
    for (final candidatesBySize in candidates) {
      final hashes = <String, List<FileItem>>{};
      for (final file in candidatesBySize) {
        if (isCancelled?.call() ?? false) {
          cancelled = true;
          break;
        }
        try {
          if (!source.isCurrent)
            throw StateError('The source connection changed.');
          final before = await source.stat(file.path!);
          if (before == null || before.isFolder || before.size != file.size) {
            throw StateError('File changed before verification.');
          }
          var bytesRead = 0;
          final digest = await sha256
              .bind(
                source.readFile(before).map((chunk) {
                  if (isCancelled?.call() ?? false)
                    throw const _ScanCancelled();
                  if (!source.isCurrent)
                    throw StateError('The source connection changed.');
                  bytesRead += chunk.length;
                  return chunk;
                }),
              )
              .first;
          final after = await source.stat(file.path!);
          if (!source.isCurrent ||
              after == null ||
              bytesRead != file.size ||
              after.size != before.size ||
              after.updatedAt != before.updatedAt) {
            throw StateError('File changed during verification.');
          }
          hashes.putIfAbsent(digest.toString(), () => []).add(file);
        } on _ScanCancelled {
          cancelled = true;
          break;
        } catch (error) {
          errors.add('${file.path}: $error');
        }
        checked++;
        onProgress?.call(checked, total);
      }
      groups.addAll(hashes.values.where((group) => group.length > 1));
      if (cancelled) break;
    }
    return DuplicateScanResult(
      groups: groups,
      errors: errors,
      cancelled: cancelled,
      checkedFiles: checked,
    );
  }
}

class _ScanCancelled implements Exception {
  const _ScanCancelled();
}
