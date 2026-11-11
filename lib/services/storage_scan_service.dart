import 'dart:collection';

import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/storage_analysis.dart';
import 'storage_scan_source.dart';

export '../models/storage_analysis.dart';
export 'storage_scan_source.dart';

/// Reads directory metadata only. Scans never download, hash, or mutate files.
/// Results remain useful after cancellation and inaccessible subdirectories,
/// with incomplete totals explicitly marked throughout the ancestor chain.
class StorageScanService {
  const StorageScanService();

  // Exact on Dart VM and JavaScript. Larger totals cannot be faithfully
  // represented by the shared int model across all supported platforms.
  static const maxReportedBytes = 9007199254740991;

  Future<StorageScanResult> scan(
    StorageScanSource source,
    String rootPath, {
    bool Function()? isCancelled,
    void Function(StorageScanProgress)? onProgress,
    int maxEntries = 200000,
    int maxDepth = 200,
    int maxIssues = 1000,
    Duration progressInterval = const Duration(milliseconds: 100),
  }) async {
    final outcome = await _scan(
      source,
      rootPath,
      retainTree: true,
      isCancelled: isCancelled,
      onProgress: onProgress,
      maxEntries: maxEntries,
      maxDepth: maxDepth,
      maxIssues: maxIssues,
      progressInterval: progressInterval,
    );
    final summary = outcome.summary;
    return StorageScanResult(
      root: outcome.root!,
      issues: summary.issues,
      cancelled: summary.cancelled,
      limited: summary.limited,
      sourceChanged: summary.sourceChanged,
      startedAt: summary.startedAt,
      completedAt: summary.completedAt,
      suppressedIssueCount: summary.suppressedIssueCount,
    );
  }

  /// Reads the same metadata as [scan], retaining aggregate totals, bounded
  /// diagnostics, pending directories and the path keys needed to reject
  /// duplicates. File display nodes and sorted child lists are unnecessary
  /// for an inline size calculation.
  Future<StorageScanSummary> scanSummary(
    StorageScanSource source,
    String rootPath, {
    bool Function()? isCancelled,
    void Function(StorageScanProgress)? onProgress,
    int maxEntries = 200000,
    int maxDepth = 200,
    int maxIssues = 1000,
    Duration progressInterval = const Duration(milliseconds: 100),
  }) async => (await _scan(
    source,
    rootPath,
    retainTree: false,
    isCancelled: isCancelled,
    onProgress: onProgress,
    maxEntries: maxEntries,
    maxDepth: maxDepth,
    maxIssues: maxIssues,
    progressInterval: progressInterval,
  )).summary;

  Future<({StorageNode? root, StorageScanSummary summary})> _scan(
    StorageScanSource source,
    String rootPath, {
    required bool retainTree,
    bool Function()? isCancelled,
    void Function(StorageScanProgress)? onProgress,
    required int maxEntries,
    required int maxDepth,
    required int maxIssues,
    required Duration progressInterval,
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
    final builders = retainTree ? <_NodeBuilder>[rootBuilder] : null;
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
    var unknownSizes = 0;
    var skippedLinks = 0;
    var directoriesComplete = false;
    var examined = 0;
    var currentPath = root;
    _NodeBuilder? activeDirectory;
    StorageScanSession? session;
    var directoriesSinceYield = 0;
    var lastYieldMilliseconds = 0;

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
      if (source is StorageScanSessionFactory) {
        try {
          session = await (source as StorageScanSessionFactory)
              .openStorageScanSession();
        } catch (_) {
          check();
          rethrow;
        }
        check();
      }
      final reader = session ?? source;
      final verifiesDirectoryType =
          reader is StorageScanDirectoryReader &&
          reader is StorageScanDirectoryGuard &&
          (reader as StorageScanDirectoryGuard)
              .verifiesStorageScanDirectoryType;
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
      if (builders != null) builders[0] = rootBuilder;
      directoriesComplete = true;
      pending.add((rootBuilder, 0));

      while (pending.isNotEmpty) {
        check();
        // Native/provider I/O already lets the event loop run. A bounded yield
        // budget also handles cached or empty-directory trees whose futures
        // finish in microtasks, including repeated unreadable directories.
        if (directoriesSinceYield >= 32 ||
            clock.elapsedMilliseconds - lastYieldMilliseconds >= 8) {
          await Future<void>.delayed(Duration.zero);
          directoriesSinceYield = 0;
          lastYieldMilliseconds = clock.elapsedMilliseconds;
          check();
        }
        directoriesSinceYield++;
        final (directory, depth) = pending.removeLast();
        activeDirectory = directory;
        currentPath = directory.item.path!;
        final canonicalChild = _CanonicalChildPath(source.paths, currentPath);
        progress();
        StorageScanDirectory listing;
        try {
          // A listed folder may have become a link before descent.
          // Recheck without following links wherever the backend supports it.
          if (depth > 0 &&
              source.supportsSymbolicLinks &&
              !verifiesDirectoryType) {
            final fresh = await source.stat(currentPath);
            check();
            if (fresh == null || !fresh.isFolder || fresh.isSymlink == true) {
              throw StateError('The directory changed before it was scanned.');
            }
          }
          check();
          listing = reader is StorageScanDirectoryReader
              ? await reader.listForStorageScan(currentPath)
              : StorageScanDirectory(entries: await source.list(currentPath));
          check();
        } on _ScanCancelled {
          rethrow;
        } on _ScanSourceChanged {
          rethrow;
        } catch (error) {
          check();
          directoriesComplete = false;
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
        directoriesComplete = directoriesComplete && directory.complete;
        for (final problem in listing.issues) {
          issue(problem);
        }
        for (final item in listing.entries) {
          check();
          if (examined >= maxEntries) {
            limited = true;
            directory.complete = false;
            directoriesComplete = false;
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
            directoriesSinceYield = 0;
            lastYieldMilliseconds = clock.elapsedMilliseconds;
            check();
          }
          final itemPath = item.path;
          if (itemPath == null ||
              item.name.isEmpty ||
              item.name == '.' ||
              item.name == '..' ||
              item.name.contains('\u0000') ||
              itemPath.contains('\u0000') ||
              (!canonicalChild.matches(item.name, itemPath) &&
                  (!source.paths.isAbsolute(itemPath) ||
                      source.paths.normalize(itemPath) != itemPath ||
                      !source.isWithin(root, itemPath) ||
                      !source.samePath(
                        source.paths.dirname(itemPath),
                        currentPath,
                      ) ||
                      source.paths.basename(itemPath) != item.name))) {
            directory.complete = false;
            directoriesComplete = false;
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
            directoriesComplete = false;
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
          // A summary only needs directory metadata until descent. It never
          // allocates or retains one builder/display node for every file.
          final child = retainTree || (item.isFolder && item.isSymlink != true)
              ? _NodeBuilder(item)
              : null;
          if (retainTree) {
            directory.addChild(child!);
            builders!.add(child);
          }
          if (item.isSymlink == true) {
            skippedLinks++;
            child?.complete = true;
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
              pending.add((child!, depth + 1));
            }
          } else {
            files++;
            final size = item.size;
            if (size != null && size >= 0 && size <= maxReportedBytes) {
              if (size > maxReportedBytes - bytes) {
                child?.complete = false;
                child?.sizeKnown = false;
                unknownSizes++;
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
              child?.sizeKnown = true;
              child?.complete = true;
              bytes += size;
            } else {
              unknownSizes++;
            }
          }
          progress();
        }
        activeDirectory = null;
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
      directoriesComplete = false;
      issue(
        StorageScanIssue(
          path: root,
          code: StorageScanIssueCode.rootUnavailable,
          message: error is _RootUnavailable ? error.message : error.toString(),
        ),
      );
    } finally {
      try {
        if (session != null) await session.close();
      } catch (error) {
        rootBuilder.complete = false;
        directoriesComplete = false;
        issue(
          StorageScanIssue(
            path: root,
            code: StorageScanIssueCode.incompleteListing,
            message: 'Could not close the directory scan session: $error',
          ),
        );
      }
    }

    // Closing a worker can itself await a message. Account/cancellation changes
    // during that wait must invalidate even a tiny tree with no aggregate yield.
    if (!cancelled && !sourceChanged) {
      try {
        check();
      } on _ScanCancelled {
        cancelled = true;
        rootBuilder.complete = false;
      } on _ScanSourceChanged {
        sourceChanged = true;
        rootBuilder.complete = false;
        issue(
          StorageScanIssue(
            path: root,
            code: StorageScanIssueCode.sourceChanged,
            message: 'The original storage connection changed during the scan.',
          ),
        );
      } catch (error) {
        rootBuilder.complete = false;
        directoriesComplete = false;
        issue(
          StorageScanIssue(
            path: root,
            code: StorageScanIssueCode.rootUnavailable,
            message: error.toString(),
          ),
        );
      }
    }

    // Iterative postorder avoids recursion limits and preserves all completed
    // descendants even when a later directory fails or the scan is stopped.
    var aggregated = 0;
    for (final builder in builders?.reversed ?? const <_NodeBuilder>[]) {
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
    return (
      root: rootBuilder.frozen,
      summary: StorageScanSummary(
        rootPath: root,
        bytes: bytes,
        fileCount: files,
        folderCount: folders,
        unknownSizeCount: unknownSizes,
        skippedLinkCount: skippedLinks,
        isComplete: directoriesComplete && unknownSizes == 0,
        issues: issues,
        cancelled: cancelled,
        limited: limited,
        sourceChanged: sourceChanged,
        startedAt: startedAt,
        completedAt: DateTime.now(),
        suppressedIssueCount: suppressedIssues,
      ),
    );
  }
}

class _NodeBuilder {
  _NodeBuilder(this.item);
  final FileItem item;
  // Most entries are leaves. Allocate a mutable list only when a directory
  // actually has children, and share the immutable empty list for all leaves.
  List<_NodeBuilder>? _children;
  List<_NodeBuilder> get children => _children ?? const <_NodeBuilder>[];
  void addChild(_NodeBuilder child) => (_children ??= []).add(child);
  bool complete = false;
  bool sizeKnown = false;
  StorageNode? frozen;

  void freeze() {
    final link = item.isSymlink == true;
    final file = !item.isFolder && !link;
    if (children.isEmpty) {
      frozen = StorageNode(
        item: item,
        bytes: file && sizeKnown ? item.size! : 0,
        fileCount: file ? 1 : 0,
        folderCount: 0,
        unknownSizeCount: file && !sizeKnown ? 1 : 0,
        skippedLinkCount: link ? 1 : 0,
        isComplete: complete,
      );
      return;
    }
    final nodes = <StorageNode>[];
    var bytes = 0;
    var files = 0;
    var folders = 0;
    var unknown = 0;
    var links = 0;
    var allComplete = true;
    for (final child in children) {
      final node = child.frozen!;
      nodes.add(node);
      bytes += node.bytes;
      files += node.fileCount;
      folders +=
          node.folderCount +
          (node.isFolder && node.item.isSymlink != true ? 1 : 0);
      unknown += node.unknownSizeCount;
      links += node.skippedLinkCount;
      allComplete = allComplete && node.isComplete;
    }
    nodes.sort((a, b) {
      final bySize = b.bytes.compareTo(a.bytes);
      return bySize != 0 ? bySize : a.path.compareTo(b.path);
    });
    frozen = StorageNode(
      item: item,
      children: nodes,
      bytes: file && sizeKnown ? item.size! : bytes,
      fileCount: file ? 1 : files,
      folderCount: folders,
      unknownSizeCount: file && !sizeKnown ? 1 : unknown,
      skippedLinkCount: link ? 1 : links,
      isComplete: complete && allComplete,
    );
  }
}

/// The parent is already normalized and accepted inside the scan root. For
/// ordinary POSIX/Windows names, exact parent + separator + one component
/// proves absolute, normalized, direct-child membership without reparsing the
/// same long path six times. Aliases and other path styles use the original
/// backend predicates, preserving their comparison rules.
class _CanonicalChildPath {
  _CanonicalChildPath(p.Context paths, String parent)
    : _windows = paths.style == p.Style.windows,
      _prefix = paths.style == p.Style.posix
          ? (parent.endsWith('/') ? parent : '$parent/')
          : paths.style == p.Style.windows
          ? (parent.endsWith(r'\') ? parent : '$parent\\')
          : null;

  final bool _windows;
  final String? _prefix;

  bool matches(String name, String path) {
    final prefix = _prefix;
    if (prefix == null ||
        name.contains('/') ||
        (_windows && (name.contains(r'\') || name.contains(':')))) {
      return false;
    }
    return path.length == prefix.length + name.length &&
        path.startsWith(prefix) &&
        path.endsWith(name);
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
