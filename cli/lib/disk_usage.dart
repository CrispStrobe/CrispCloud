import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

enum UsageKind { file, directory, link, other }

class UsageMetadata {
  const UsageMetadata(this.kind, {this.bytes = 0});
  final UsageKind kind;
  final int bytes;
}

/// Only metadata is needed. Injectable so inaccessible/changing trees can be
/// tested without relying on platform-specific permission enforcement.
abstract interface class DiskUsageSource {
  p.Context get paths;
  Future<String> resolveRoot(String path);
  Future<UsageMetadata> inspect(String path);
  Stream<String> list(String path);
}

class LocalDiskUsageSource implements DiskUsageSource {
  @override
  p.Context get paths => p.context;

  @override
  Future<String> resolveRoot(String path) =>
      Directory(paths.absolute(path)).resolveSymbolicLinks();

  @override
  Future<UsageMetadata> inspect(String path) async {
    final before = await FileSystemEntity.type(path, followLinks: false);
    if (before == FileSystemEntityType.link) {
      return const UsageMetadata(UsageKind.link);
    }
    if (before == FileSystemEntityType.notFound) {
      throw FileSystemException('The entry no longer exists.', path);
    }
    if (before != FileSystemEntityType.file &&
        before != FileSystemEntityType.directory) {
      return const UsageMetadata(UsageKind.other);
    }
    final stat = await FileStat.stat(path);
    if (stat.type != before ||
        await FileSystemEntity.type(path, followLinks: false) != before) {
      throw FileSystemException('The entry changed during inspection.', path);
    }
    if (before == FileSystemEntityType.directory) {
      return const UsageMetadata(UsageKind.directory);
    }
    // Do not treat FIFOs, devices and sockets as regular files on POSIX.
    if (!Platform.isWindows && (stat.mode & 0xf000) != 0x8000) {
      return const UsageMetadata(UsageKind.other);
    }
    return UsageMetadata(UsageKind.file, bytes: stat.size);
  }

  @override
  Stream<String> list(String path) async* {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw FileSystemException('The directory changed before listing.', path);
    }
    await for (final entry in Directory(path).list(followLinks: false)) {
      yield entry.path;
    }
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw FileSystemException('The directory changed during listing.', path);
    }
  }
}

class UsageRow {
  UsageRow(this.path, this.kind);
  final String path;
  final UsageKind kind;
  int bytes = 0;
  int files = 0;
  int directories = 0;
  bool complete = true;

  Map<String, Object> toJson() => {
    'path': path,
    'type': kind.name,
    'bytes': bytes,
    'files': files,
    'directories': directories,
    'complete': complete,
  };
}

class UsageIssue {
  const UsageIssue(this.path, this.code);
  final String path;
  final String code;
  Map<String, String> toJson() => {'path': path, 'code': code};
}

class DiskUsageResult {
  DiskUsageResult({
    required this.root,
    required this.rows,
    required this.entriesVisited,
    required this.linksSkipped,
    required this.otherEntriesSkipped,
    required this.issues,
    required this.suppressedIssues,
    required this.cancelled,
    required this.limited,
    required this.elapsedMilliseconds,
  });
  final UsageRow root;
  final List<UsageRow> rows;
  final int entriesVisited;
  final int linksSkipped;
  final int otherEntriesSkipped;
  final List<UsageIssue> issues;
  final int suppressedIssues;
  final bool cancelled;
  final bool limited;
  final int elapsedMilliseconds;

  Map<String, Object> toJson() => {
    'measurement': 'logical_file_bytes',
    'root': root.toJson(),
    'entries': rows.map((row) => row.toJson()).toList(),
    'entriesVisited': entriesVisited,
    'linksSkipped': linksSkipped,
    'otherEntriesSkipped': otherEntriesSkipped,
    'complete': root.complete,
    'cancelled': cancelled,
    'limited': limited,
    'issues': issues.map((issue) => issue.toJson()).toList(),
    'suppressedIssues': suppressedIssues,
    'elapsedMilliseconds': elapsedMilliseconds,
  };
}

class DiskUsageScanner {
  DiskUsageScanner({DiskUsageSource? source})
    : source = source ?? LocalDiskUsageSource();
  final DiskUsageSource source;

  // Match the GUI's exact cross-platform reporting bound.
  static const maxBytes = 9007199254740991;

  Future<DiskUsageResult> scan(
    String path, {
    int top = 20,
    bool recursive = false,
    bool filesOnly = false,
    bool directoriesOnly = false,
    int maxEntries = 1000000,
    int maxDepth = 200,
    bool Function()? isCancelled,
  }) async {
    if (top < 1 ||
        top > 10000 ||
        maxEntries < 1 ||
        maxDepth < 0 ||
        maxDepth > 500 ||
        (filesOnly && directoriesOnly)) {
      throw ArgumentError('Invalid disk-usage scan options.');
    }
    final clock = Stopwatch()..start();
    final rootPath = source.paths.normalize(await source.resolveRoot(path));
    final rootMetadata = await source.inspect(rootPath);
    if (rootMetadata.kind != UsageKind.file &&
        rootMetadata.kind != UsageKind.directory) {
      throw FileSystemException(
        'Choose a regular file or directory.',
        rootPath,
      );
    }
    int compare(UsageRow a, UsageRow b) {
      final size = b.bytes.compareTo(a.bytes);
      return size == 0 ? a.path.compareTo(b.path) : size;
    }

    final largest = HeapPriorityQueue<UsageRow>((a, b) => compare(b, a));
    final issues = <UsageIssue>[];
    var suppressed = 0;
    var visited = 0;
    var links = 0;
    var other = 0;
    var cancelled = false;
    var limited = false;
    var stopped = false;
    void issue(String at, String code) {
      if (issues.length < 100) {
        issues.add(UsageIssue(at, code));
      } else {
        suppressed++;
      }
    }

    bool stop() {
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        stopped = true;
      }
      return stopped;
    }

    void offer(UsageRow row, int depth) {
      if (depth == 0 && row.kind == UsageKind.directory) return;
      if (filesOnly && row.kind != UsageKind.file) return;
      if (directoriesOnly && row.kind != UsageKind.directory) return;
      if (depth > 1 && !recursive && !filesOnly) return;
      if (largest.length < top) {
        largest.add(row);
      } else if (compare(row, largest.first) < 0) {
        largest.removeFirst();
        largest.add(row);
      }
    }

    int addBytes(int a, int b, UsageRow row) {
      if (b < 0 || b > maxBytes - a) {
        row.complete = false;
        issue(row.path, 'byte_limit');
        stopped = limited = true;
        return b < 0 ? a : maxBytes;
      }
      return a + b;
    }

    Future<UsageRow> walk(
      String current,
      UsageMetadata metadata,
      int depth,
    ) async {
      visited++;
      final row = UsageRow(current, metadata.kind);
      if (metadata.kind == UsageKind.file) {
        row.files = 1;
        row.bytes = addBytes(0, metadata.bytes, row);
      } else if (metadata.kind == UsageKind.directory) {
        if (stop()) {
          row.complete = false;
        } else if (depth >= maxDepth) {
          limited = true;
          row.complete = false;
          issue(current, 'depth_limit');
        } else {
          final names = <String>{};
          try {
            await for (final listed in source.list(current)) {
              if (stop() || visited >= maxEntries) {
                if (!stopped) {
                  stopped = limited = true;
                  issue(current, 'entry_limit');
                }
                row.complete = false;
                break;
              }
              final child = source.paths.normalize(listed);
              if (!source.paths.equals(source.paths.dirname(child), current) ||
                  !source.paths.isWithin(rootPath, child) ||
                  !names.add(child)) {
                visited++;
                row.complete = false;
                issue(child, 'invalid_or_duplicate_entry');
                continue;
              }
              try {
                final info = await source.inspect(child);
                if (info.kind == UsageKind.link ||
                    info.kind == UsageKind.other) {
                  visited++;
                  if (info.kind == UsageKind.link) {
                    links++;
                  } else {
                    other++;
                  }
                  continue;
                }
                final nested = await walk(child, info, depth + 1);
                row.bytes = addBytes(row.bytes, nested.bytes, row);
                row.files += nested.files;
                row.directories +=
                    nested.directories +
                    (nested.kind == UsageKind.directory ? 1 : 0);
                row.complete = row.complete && nested.complete;
              } on FileSystemException {
                visited++;
                row.complete = false;
                issue(child, 'unreadable_metadata');
              }
            }
          } on FileSystemException {
            row.complete = false;
            issue(current, 'unreadable_directory');
          }
        }
      }
      offer(row, depth);
      return row;
    }

    final root = await walk(rootPath, rootMetadata, 0);
    root.complete = root.complete && !stop();
    final rows = largest.toList()..sort(compare);
    return DiskUsageResult(
      root: root,
      rows: rows,
      entriesVisited: visited,
      linksSkipped: links,
      otherEntriesSkipped: other,
      issues: issues,
      suppressedIssues: suppressed,
      cancelled: cancelled,
      limited: limited,
      elapsedMilliseconds: clock.elapsedMilliseconds,
    );
  }
}
