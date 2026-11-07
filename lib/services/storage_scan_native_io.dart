import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/storage_analysis.dart';

/// A directory-sized unit of work keeps synchronous metadata calls away from
/// the UI isolate. The caller holds its security scope until this completes.
/// Using a worker avoids a round trip through Dart's async I/O scheduler for
/// every type/stat check. No file contents or provider credentials are passed.
Future<StorageScanDirectory> readNativeStorageScanDirectory(String path) =>
    Isolate.run(() => _readDirectory(path));

StorageScanDirectory _readDirectory(String path) {
  final entries = <FileItem>[];
  final issues = <StorageScanIssue>[];
  var complete = true;
  // Keep per-directory errors bounded even before the global diagnostic limit
  // is applied. The summary preserves the fact that more entries failed.
  var suppressed = 0;
  void failed(String entryPath, Object error) {
    complete = false;
    if (issues.length < 20) {
      issues.add(
        StorageScanIssue(
          path: entryPath,
          code: StorageScanIssueCode.invalidEntry,
          message: 'Could not inspect an entry: $error',
        ),
      );
    } else {
      suppressed++;
    }
  }

  // Do not follow a root that was replaced by a link after the caller's stat.
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw FileSystemException('The directory is no longer available.', path);
  }
  for (final entity in Directory(path).listSync(followLinks: false)) {
    final entryPath = p.normalize(entity.path);
    final name = p.basename(entryPath);
    if (entity is Link) {
      // A disk-usage scan needs to identify links, not resolve their targets.
      entries.add(
        FileItem(name: name, path: entryPath, isFolder: false, isSymlink: true),
      );
      continue;
    }
    final listedType = entity is Directory
        ? FileSystemEntityType.directory
        : FileSystemEntityType.file;
    try {
      final info = FileStat.statSync(entryPath);
      // Directory enumeration already supplied the initial no-follow type.
      // Check again after stat so a new link cannot contribute target bytes.
      if (info.type != listedType ||
          FileSystemEntity.typeSync(entryPath, followLinks: false) !=
              listedType) {
        throw FileSystemException(
          'The entry changed while its metadata was read.',
          entryPath,
        );
      }
      entries.add(
        FileItem(
          name: name,
          path: entryPath,
          isFolder: listedType == FileSystemEntityType.directory,
          isSymlink: false,
          size: listedType == FileSystemEntityType.file ? info.size : null,
          updatedAt: info.modified,
        ),
      );
    } catch (error) {
      failed(entryPath, error);
      // Keep known names visible, but never invent a size for failed metadata.
      // Unknown folders are rechecked by StorageScanService before descent.
      entries.add(
        FileItem(
          name: name,
          path: entryPath,
          isFolder: listedType == FileSystemEntityType.directory,
        ),
      );
    }
  }
  if (suppressed > 0) {
    issues.add(
      StorageScanIssue(
        path: path,
        code: StorageScanIssueCode.incompleteListing,
        message: '$suppressed additional entries could not be inspected.',
      ),
    );
  }
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    // A changed root invalidates the entire listing: its apparent children
    // could have come from a replacement link target under the same names.
    throw FileSystemException('The directory changed during enumeration.', path);
  }
  return StorageScanDirectory(
    entries: entries,
    issues: issues,
    isComplete: complete,
  );
}
