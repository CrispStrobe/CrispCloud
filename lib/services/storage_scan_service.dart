import 'dart:collection';

import '../models/file_item.dart';
import '../models/storage_analysis.dart';
import 'file_operation_service.dart';

export '../models/storage_analysis.dart';

/// Reads directory metadata only. Scans never download, hash, or mutate files.
/// Results remain useful after cancellation and inaccessible subdirectories,
/// with incomplete totals explicitly marked throughout the ancestor chain.
class StorageScanService {
  const StorageScanService();

  // Exact on Dart VM and JavaScript. Larger totals cannot be faithfully
  // represented by the shared int model across all supported platforms.
  static const maxReportedBytes = 9007199254740991;

  Future<StorageScanResult> scan(
    FileOperationBackend source,
    String rootPath, {
    bool Function()? isCancelled,
    void Function(StorageScanProgress)? onProgress,
    int maxEntries = 200000,
    int maxDepth = 200,
    int maxIssues = 1000,
    Duration progressInterval = const Duration(milliseconds: 100),
  }) async {
    if (maxEntries < 1 || maxDepth < 0 || maxIssues < 1) {
      throw ArgumentError('Scan limits must be positive (depth may be zero).');
    }
    if (progressInterval.isNegative) {
      throw ArgumentError.value(progressInterval, 'progressInterval');
    }
    final startedAt = DateTime.now();
    final clock = Stopwatch()..start();
    var lastProgress = -progressInterval.inMilliseconds;
    final identity = source.identity;
    final root = source.paths.normalize(rootPath);
    final fallbackRoot = FileItem(
      name: source.paths.basename(root),
      path: root,
      isFolder: true,
    );
    var rootBuilder = _NodeBuilder(fallbackRoot);
    final builders = <_NodeBuilder>[rootBuilder];
    final pending = ListQueue<(_NodeBuilder, int)>();
    final seen = <String>{source.pathKey(root)};
    final issues = <StorageScanIssue>[];
    var suppressedIssues = 0;
    var cancelled = false;
    var limited = false;
    var sourceChanged = false;
    var files = 0;
    var folders = 0;
    var bytes = 0;
    var examined = 0;
    var currentPath = root;
    _NodeBuilder? activeDirectory;

    void issue(StorageScanIssue value) {
      if (issues.length < maxIssues) {
        issues.add(value);
      } else {
        suppressedIssues++;
      }
    }

    void check() {
      if (isCancelled?.call() ?? false) throw const _ScanCancelled();
      if (!source.isCurrent || source.identity != identity) {
        throw const _ScanSourceChanged();
      }
    }

    void progress({bool force = false}) {
      if (onProgress == null) return;
      final elapsed = clock.elapsedMilliseconds;
      if (!force && elapsed - lastProgress < progressInterval.inMilliseconds) {
        return;
      }
      lastProgress = elapsed;
      onProgress(
        StorageScanProgress(
          files: files,
          folders: folders,
          bytes: bytes,
          currentPath: currentPath,
        ),
      );
    }

    try {
      check();
      progress(force: true);
      if (rootPath.isEmpty ||
          rootPath.contains('\u0000') ||
          !source.paths.isAbsolute(root)) {
        throw const _RootUnavailable('Use an absolute directory path.');
      }
      FileItem? rootItem;
      try {
        rootItem = await source.stat(root);
      } catch (_) {
        check();
        rethrow;
      }
      check();
      if (rootItem == null ||
          !rootItem.isFolder ||
          rootItem.isSymlink == true) {
        throw const _RootUnavailable(
          'The scan root is missing, is not a directory, or is a symbolic link.',
        );
      }
      rootBuilder = _NodeBuilder(rootItem.copyWith(path: root));
      builders[0] = rootBuilder;
      pending.add((rootBuilder, 0));

      while (pending.isNotEmpty) {
        check();
        final (directory, depth) = pending.removeLast();
        activeDirectory = directory;
        currentPath = directory.item.path!;
        progress();
        StorageScanDirectory listing;
        try {
          // A listed folder may have become a link before descent.
          // Recheck without following links wherever the backend supports it.
          if (depth > 0 && source.supportsSymbolicLinks) {
            final fresh = await source.stat(currentPath);
            check();
            if (fresh == null || !fresh.isFolder || fresh.isSymlink == true) {
              throw StateError('The directory changed before it was scanned.');
            }
          }
          check();
          listing = source is StorageScanDirectoryReader
              ? await (source as StorageScanDirectoryReader).listForStorageScan(
                  currentPath,
                )
              : StorageScanDirectory(entries: await source.list(currentPath));
          check();
        } on _ScanCancelled {
          rethrow;
        } on _ScanSourceChanged {
          rethrow;
        } catch (error) {
          check();
          issue(
            StorageScanIssue(
              path: currentPath,
              code: StorageScanIssueCode.unreadableDirectory,
              message: error.toString(),
            ),
          );
          continue;
        }

        directory.complete = listing.isComplete && listing.issues.isEmpty;
        for (final problem in listing.issues) {
          issue(problem);
        }
        for (final item in listing.entries) {
          check();
          if (examined >= maxEntries) {
            limited = true;
            directory.complete = false;
            issue(
              StorageScanIssue(
                path: currentPath,
                code: StorageScanIssueCode.entryLimit,
                message: 'The scan reached its $maxEntries entry limit.',
              ),
            );
            throw const _ScanLimitReached();
          }
          examined++;
          // Yield to repaint/cancel even when one directory has many entries.
          if (examined % 256 == 0) {
            progress();
            await Future<void>.delayed(Duration.zero);
            check();
          }
          final itemPath = item.path;
          if (itemPath == null ||
              item.name.isEmpty ||
              item.name == '.' ||
              item.name == '..' ||
              item.name.contains('\u0000') ||
              itemPath.contains('\u0000') ||
              !source.paths.isAbsolute(itemPath) ||
              source.paths.normalize(itemPath) != itemPath ||
              !source.isWithin(root, itemPath) ||
              !source.samePath(source.paths.dirname(itemPath), currentPath) ||
              source.paths.basename(itemPath) != item.name) {
            directory.complete = false;
            issue(
              StorageScanIssue(
                path: itemPath ?? currentPath,
                code: StorageScanIssueCode.invalidEntry,
                message: 'An entry did not identify a direct child of its directory.',
              ),
            );
            continue;
          }
          if (!seen.add(source.pathKey(itemPath))) {
            directory.complete = false;
            issue(
              StorageScanIssue(
                path: itemPath,
                code: StorageScanIssueCode.duplicateEntry,
                message:
                    'A repeated or ambiguous path was excluded from the scan.',
              ),
            );
            continue;
          }
          final child = _NodeBuilder(item);
          directory.children.add(child);
          builders.add(child);
          if (item.isSymlink == true) {
            child.complete = true;
            continue;
          }
          if (item.isFolder) {
            folders++;
            if (depth >= maxDepth) {
              limited = true;
              issue(
                StorageScanIssue(
                  path: itemPath,
                  code: StorageScanIssueCode.depthLimit,
                  message:
                      'The scan reached its $maxDepth directory depth limit.',
                ),
              );
            } else {
              pending.add((child, depth + 1));
            }
          } else {
            files++;
            final size = item.size;
            if (size != null && size >= 0 && size <= maxReportedBytes) {
              if (size > maxReportedBytes - bytes) {
                child.complete = false;
                child.sizeKnown = false;
                limited = true;
                issue(
                  StorageScanIssue(
                    path: itemPath,
                    code: StorageScanIssueCode.byteLimit,
                    message: 'The total exceeds the exact cross-platform byte limit.',
                  ),
                );
                throw const _ScanLimitReached();
              }
              child.sizeKnown = true;
              child.complete = true;
              bytes += size;
            }
          }
          progress();
        }
        activeDirectory = null;
        // Cheap directory-only trees must also remain cancellable.
        await Future<void>.delayed(Duration.zero);
        check();
      }
      check();
    } on _ScanCancelled {
      cancelled = true;
      rootBuilder.complete = false;
      activeDirectory?.complete = false;
    } on _ScanSourceChanged {
      sourceChanged = true;
      rootBuilder.complete = false;
      activeDirectory?.complete = false;
      issue(
        StorageScanIssue(
          path: currentPath,
          code: StorageScanIssueCode.sourceChanged,
          message: 'The original storage connection changed during the scan.',
        ),
      );
    } on _ScanLimitReached {
      rootBuilder.complete = false;
      activeDirectory?.complete = false;
    } catch (error) {
      rootBuilder.complete = false;
      issue(
        StorageScanIssue(
          path: root,
          code: StorageScanIssueCode.rootUnavailable,
          message: error is _RootUnavailable ? error.message : error.toString(),
        ),
      );
    }

    // Iterative postorder avoids recursion limits and preserves all completed
    // descendants even when a later directory fails or the scan is stopped.
    var aggregated = 0;
    for (final builder in builders.reversed) {
      // Keep repaint/cancellation responsive while finalizing a large tree.
      // The root is frozen last, after any late cancellation/source change,
      // so each node still needs only one immutable snapshot.
      if (++aggregated % 512 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (!cancelled && !sourceChanged) {
          if (isCancelled?.call() ?? false) {
            cancelled = true;
            rootBuilder.complete = false;
          } else if (!source.isCurrent || source.identity != identity) {
            sourceChanged = true;
            rootBuilder.complete = false;
            issue(
              StorageScanIssue(
                path: root,
                code: StorageScanIssueCode.sourceChanged,
                message:
                    'The original storage connection changed during the scan.',
              ),
            );
          }
        }
      }
      builder.freeze();
    }
    progress(force: true);
    return StorageScanResult(
      root: rootBuilder.frozen!,
      issues: issues,
      cancelled: cancelled,
      limited: limited,
      sourceChanged: sourceChanged,
      startedAt: startedAt,
      completedAt: DateTime.now(),
      suppressedIssueCount: suppressedIssues,
    );
  }
}

class _NodeBuilder {
  _NodeBuilder(this.item);
  final FileItem item;
  final children = <_NodeBuilder>[];
  bool complete = false;
  bool sizeKnown = false;
  StorageNode? frozen;

  void freeze() {
    final nodes = children.map((child) => child.frozen!).toList();
    nodes.sort((a, b) {
      final bySize = b.bytes.compareTo(a.bytes);
      return bySize != 0 ? bySize : a.path.compareTo(b.path);
    });
    final link = item.isSymlink == true;
    final file = !item.isFolder && !link;
    frozen = StorageNode(
      item: item,
      children: nodes,
      bytes: file && sizeKnown
          ? item.size!
          : nodes.fold(0, (sum, child) => sum + child.bytes),
      fileCount: file
          ? 1
          : nodes.fold(0, (sum, child) => sum + child.fileCount),
      folderCount: nodes.fold(
        0,
        (sum, child) =>
            sum +
            child.folderCount +
            (child.isFolder && child.item.isSymlink != true ? 1 : 0),
      ),
      unknownSizeCount: file && !sizeKnown
          ? 1
          : nodes.fold(0, (sum, child) => sum + child.unknownSizeCount),
      skippedLinkCount: link
          ? 1
          : nodes.fold(0, (sum, child) => sum + child.skippedLinkCount),
      isComplete: complete && nodes.every((child) => child.isComplete),
    );
  }
}

class _ScanCancelled implements Exception {
  const _ScanCancelled();
}

class _ScanSourceChanged implements Exception {
  const _ScanSourceChanged();
}

class _ScanLimitReached implements Exception {
  const _ScanLimitReached();
}

class _RootUnavailable implements Exception {
  const _RootUnavailable(this.message);
  final String message;
}
