import 'package:crypto/crypto.dart';

import '../models/file_item.dart';
import 'file_operation_service.dart';

enum DirectoryComparisonStatus {
  equal,
  onlyLeft,
  onlyRight,
  different,
  unknown,
  typeConflict,
}

enum DirectoryComparisonAction { skip, copyToRight, copyToLeft }

class DirectoryComparisonRow {
  DirectoryComparisonRow(
    this.relativePath,
    this.left,
    this.right,
    this.status, {
    this.leftHash,
    this.rightHash,
  });
  final String relativePath;
  final FileItem? left;
  final FileItem? right;
  final DirectoryComparisonStatus status;
  final String? leftHash;
  final String? rightHash;
  List<DirectoryComparisonAction> get choices => [
    DirectoryComparisonAction.skip,
    if (left != null && status != DirectoryComparisonStatus.typeConflict)
      DirectoryComparisonAction.copyToRight,
    if (right != null && status != DirectoryComparisonStatus.typeConflict)
      DirectoryComparisonAction.copyToLeft,
  ];
}

class DirectoryComparisonPlan {
  const DirectoryComparisonPlan(
    this.left,
    this.right,
    this.leftRoot,
    this.rightRoot,
    this.rows,
    this.errors,
    this.cancelled,
  );
  final FileOperationBackend left;
  final FileOperationBackend right;
  final String leftRoot;
  final String rightRoot;
  final List<DirectoryComparisonRow> rows;
  final List<String> errors;
  final bool cancelled;
}

/// Arbitrary local/cloud directory pairs. Metadata alone never proves content
/// equality when size or modification time is missing.
class DirectoryComparisonService {
  Future<DirectoryComparisonPlan> compare({
    required FileOperationBackend left,
    required FileOperationBackend right,
    required String leftRoot,
    required String rightRoot,
    bool recursive = true,
    bool verifyContents = true,
    bool Function()? isCancelled,
    void Function(int compared, String path)? onProgress,
  }) async {
    final errors = <String>[];
    var cancelled = false;
    void check() {
      if (isCancelled?.call() ?? false) throw const _ComparisonCancelled();
      if (!left.isCurrent || !right.isCurrent) {
        throw StateError('A comparison source changed.');
      }
    }

    Future<Map<String, FileItem>> scan(
      FileOperationBackend source,
      String root,
    ) async {
      final rootItem = await source.stat(root);
      check();
      if (rootItem == null ||
          !rootItem.isFolder ||
          rootItem.isSymlink == true) {
        throw StateError(
          'Comparison directory is missing or unavailable: $root',
        );
      }
      final found = <String, FileItem>{};
      final foundPaths = <String>{};
      final seen = <String>{};
      Future<void> walk(String path, int depth) async {
        check();
        if (!seen.add(source.pathKey(path))) return;
        if (depth > 200 || found.length > 200000) {
          throw StateError('Comparison traversal limit exceeded.');
        }
        final children = await source.list(path);
        check();
        for (final item in children) {
          if (item.path == null || item.name == '.' || item.name == '..') {
            continue;
          }
          if (!source.isWithin(root, item.path!) ||
              source.paths.dirname(item.path!) != path) {
            throw StateError('Source returned an invalid path: ${item.path}');
          }
          if (item.isSymlink == true) {
            errors.add(
              '${item.path}: symbolic links are excluded from comparison.',
            );
            continue;
          }
          final relative = source.paths
              .relative(item.path!, from: root)
              .replaceAll(source.paths.separator, '/');
          if (!foundPaths.add(source.pathKey(item.path!))) {
            throw StateError('Ambiguous comparison entry: ${item.path}');
          }
          found[relative] = item;
          if (recursive && item.isFolder) await walk(item.path!, depth + 1);
        }
      }

      await walk(root, 0);
      return found;
    }

    final rows = <DirectoryComparisonRow>[];
    try {
      final a = await scan(left, leftRoot), b = await scan(right, rightRoot);
      final paths = {...a.keys, ...b.keys}.toList()..sort();
      var compared = 0;
      for (final path in paths) {
        check();
        final first = a[path], second = b[path];
        String? hashA, hashB;
        DirectoryComparisonStatus status;
        if (first == null) {
          status = DirectoryComparisonStatus.onlyRight;
        } else if (second == null) {
          status = DirectoryComparisonStatus.onlyLeft;
        } else if (first.isFolder != second.isFolder) {
          status = DirectoryComparisonStatus.typeConflict;
        } else if (first.isFolder) {
          status = DirectoryComparisonStatus.equal;
        } else if (verifyContents) {
          hashA = await _hash(left, first, check);
          hashB = await _hash(right, second, check);
          status = hashA == hashB
              ? DirectoryComparisonStatus.equal
              : DirectoryComparisonStatus.different;
        } else if (first.size == null ||
            second.size == null ||
            first.updatedAt == null ||
            second.updatedAt == null) {
          status = DirectoryComparisonStatus.unknown;
        } else {
          status =
              first.size == second.size &&
                  first.updatedAt!.difference(second.updatedAt!).abs() <=
                      const Duration(seconds: 2)
              ? DirectoryComparisonStatus.equal
              : DirectoryComparisonStatus.different;
        }
        if (verifyContents) {
          if (first != null && !first.isFolder) {
            hashA ??= await _hash(left, first, check);
          }
          if (second != null && !second.isFolder) {
            hashB ??= await _hash(right, second, check);
          }
        }
        rows.add(
          DirectoryComparisonRow(
            path,
            first,
            second,
            status,
            leftHash: hashA,
            rightHash: hashB,
          ),
        );
        compared++;
        onProgress?.call(compared, path);
      }
    } on _ComparisonCancelled {
      cancelled = true;
    } catch (error) {
      errors.add(error.toString());
    }
    return DirectoryComparisonPlan(
      left,
      right,
      leftRoot,
      rightRoot,
      List.unmodifiable(rows),
      errors,
      cancelled,
    );
  }

  Future<String> _hash(
    FileOperationBackend source,
    FileItem file,
    void Function() check,
  ) async {
    check();
    final before = await source.stat(file.path!);
    if (!_sameVersion(file, before)) {
      throw StateError('${file.path} changed during comparison.');
    }
    var bytes = 0;
    final digest = await sha256
        .bind(
          source.readFile(file).map((chunk) {
            check();
            bytes += chunk.length;
            return chunk;
          }),
        )
        .first;
    final after = await source.stat(file.path!);
    if (!_sameVersion(before, after) ||
        (file.size != null && bytes != file.size)) {
      throw StateError('${file.path} changed during comparison.');
    }
    return digest.toString();
  }

  bool _sameVersion(FileItem? a, FileItem? b) => a == null
      ? b == null
      : b != null &&
            a.isFolder == b.isFolder &&
            a.isSymlink == b.isSymlink &&
            a.uuid == b.uuid &&
            _revision(a) == _revision(b) &&
            a.size == b.size &&
            a.updatedAt == b.updatedAt;

  String? _revision(FileItem item) =>
      (item.metadata?['etag'] ??
              item.metadata?['eTag'] ??
              item.metadata?['versionId'] ??
              item.metadata?['revision'])
          ?.toString();

  /// Apply exactly the chosen rows. Directory rows create only that directory;
  /// they never implicitly copy unchecked descendants. Existing files use the
  /// same staged/verified operation engine as the advanced transfer dialog.
  Future<List<String>> apply(
    DirectoryComparisonPlan plan,
    Map<String, DirectoryComparisonAction> decisions, {
    required FileOperationControl control,
    void Function(String path)? onProgress,
  }) async {
    if (plan.cancelled || plan.errors.isNotEmpty) {
      throw StateError('Run a complete comparison before applying changes.');
    }
    void check() {
      if (!plan.left.isCurrent || !plan.right.isCurrent) {
        throw StateError('A comparison source changed. Compare again.');
      }
      if (control.isCancelled) throw const _ComparisonCancelled();
    }

    final selected = plan.rows
        .where(
          (row) =>
              (decisions[row.relativePath] ?? DirectoryComparisonAction.skip) !=
              DirectoryComparisonAction.skip,
        )
        .toList();
    Future<void> validate(DirectoryComparisonRow row) async {
      check();
      final leftPath = plan.left.paths.joinAll([
        plan.leftRoot,
        ...row.relativePath.split('/'),
      ]);
      final rightPath = plan.right.paths.joinAll([
        plan.rightRoot,
        ...row.relativePath.split('/'),
      ]);
      if (!_sameVersion(row.left, await plan.left.stat(leftPath)) ||
          !_sameVersion(row.right, await plan.right.stat(rightPath))) {
        throw StateError(
          '${row.relativePath} changed after comparison. Compare again.',
        );
      }
      if (row.leftHash != null &&
              await _hash(plan.left, row.left!, check) != row.leftHash ||
          row.rightHash != null &&
              await _hash(plan.right, row.right!, check) != row.rightHash) {
        throw StateError(
          '${row.relativePath} contents changed after comparison.',
        );
      }
      if (!row.choices.contains(decisions[row.relativePath])) {
        throw StateError('Unsupported comparison decision.');
      }
    }

    // Revalidate the entire selection before the first mutation, then each
    // row again when it is reached. A long first transfer must not authorize
    // replacing a later file that changed while that transfer was running.
    for (final row in selected) {
      await validate(row);
    }
    final errors = <String>[];
    for (final direction in [
      DirectoryComparisonAction.copyToRight,
      DirectoryComparisonAction.copyToLeft,
    ]) {
      final source = direction == DirectoryComparisonAction.copyToRight
          ? plan.left
          : plan.right;
      final target = direction == DirectoryComparisonAction.copyToRight
          ? plan.right
          : plan.left;
      final sourceRoot = direction == DirectoryComparisonAction.copyToRight
          ? plan.leftRoot
          : plan.rightRoot;
      final targetRoot = direction == DirectoryComparisonAction.copyToRight
          ? plan.rightRoot
          : plan.leftRoot;
      final rows =
          selected
              .where((row) => decisions[row.relativePath] == direction)
              .toList()
            ..sort(
              (a, b) => a.relativePath
                  .split('/')
                  .length
                  .compareTo(b.relativePath.split('/').length),
            );
      for (final row in rows) {
        check();
        await validate(row);
        final item = direction == DirectoryComparisonAction.copyToRight
            ? row.left!
            : row.right!;
        final path = target.paths.joinAll([
          targetRoot,
          ...row.relativePath.split('/'),
        ]);
        if (item.isFolder) {
          // Parent directories are created by the transfer engine for files;
          // explicit empty-directory rows are handled here.
          final segments = row.relativePath.split('/');
          var parent = targetRoot;
          for (final segment in segments) {
            parent = target.paths.join(parent, segment);
            final existing = await target.stat(parent);
            if (existing == null) {
              await target.createDirectory(parent);
            } else if (!existing.isFolder) {
              throw StateError('Destination parent is a file: $parent');
            }
          }
          onProgress?.call(path);
          continue;
        }
        final operation = await const FileOperationService().prepare(
          files: [item],
          source: source,
          destination: target,
          targetDirectory: targetRoot,
          options: FileOperationOptions(
            fileConflict: FileConflictPolicy.replace,
            recursive: false,
            preserveRelativePaths: true,
            relativeBase: sourceRoot,
            verifyContents: true,
          ),
        );
        if (!operation.canExecute) {
          errors.addAll(operation.errors);
          break;
        }
        await validate(row);
        await const FileOperationService().execute(
          operation,
          control: control,
          onEntryComplete: (entry) => onProgress?.call(entry.destination),
        );
        errors.addAll(
          operation.entries
              .where((entry) => entry.failed)
              .map((entry) => entry.message ?? 'Copy failed.'),
        );
        if (errors.isNotEmpty || control.isCancelled) break;
      }
      if (errors.isNotEmpty || control.isCancelled) break;
    }
    return errors;
  }
}

class _ComparisonCancelled implements Exception {
  const _ComparisonCancelled();
  @override
  String toString() => 'Comparison cancelled.';
}
