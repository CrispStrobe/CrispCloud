import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:crisp_cloud/services/storage_scan_service.dart';

/// Reads truth produced independently by Python's no-follow filesystem walk.
/// Verification is intentionally outside benchmark stopwatches.
class StorageScanBenchmarkOracle {
  StorageScanBenchmarkOracle(this.data)
    : files = {
        for (final row in data['records'] as List)
          (row as List)[0] as String: row,
      },
      directories = {
        for (final row in data['directories'] as List)
          (row as List)[0] as String: row[1] as int,
      };

  factory StorageScanBenchmarkOracle.read(String path) =>
      StorageScanBenchmarkOracle(
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
      );

  final Map<String, dynamic> data;
  final Map<String, List<dynamic>> files;
  final Map<String, int> directories;

  String get root => data['root'] as String;
  int get fileCount => data['files'] as int;
  int get folderCount => data['foldersExcludingRoot'] as int;
  int get bytes => data['logicalBytes'] as int;

  void verifyTotals({
    required int bytes,
    required int files,
    required int folders,
    required int unknownSizes,
    required int skippedLinks,
    required bool isComplete,
    required bool cancelled,
    required bool limited,
    required bool sourceChanged,
    required int issueCount,
  }) {
    if (bytes != this.bytes ||
        files != fileCount ||
        folders != folderCount ||
        unknownSizes != 0 ||
        skippedLinks != 0 ||
        !isComplete ||
        cancelled ||
        limited ||
        sourceChanged ||
        issueCount != 0) {
      throw StateError('Result does not match the independent fixture totals.');
    }
  }

  String verify(StorageScanResult result) {
    verifyTotals(
      bytes: result.root.bytes,
      files: result.root.fileCount,
      folders: result.root.folderCount,
      unknownSizes: result.root.unknownSizeCount,
      skippedLinks: result.root.skippedLinkCount,
      isComplete: result.isComplete,
      cancelled: result.cancelled,
      limited: result.limited,
      sourceChanged: result.sourceChanged,
      issueCount: result.issues.length + result.suppressedIssueCount,
    );
    if (result.root.path != root) {
      throw StateError('Benchmark root differs from the oracle root.');
    }
    final seenFiles = <String>{};
    final seenDirectories = <String>{};
    final records = <List<Object>>[];
    final pending = <StorageNode>[result.root];
    final totals = data['directoryTotals'] as Map<String, dynamic>;
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (!node.isComplete ||
          node.unknownSizeCount != 0 ||
          node.skippedLinkCount != 0 ||
          node.item.isSymlink == true) {
        throw StateError('Unexpected partial or link node: ${node.path}');
      }
      final relative = _relative(root, node.path);
      if (node.name != p.basename(node.path)) {
        throw StateError('Incorrect entry name: ${node.path}');
      }
      if (node.isFolder) {
        final wanted = totals[relative] as List?;
        if (!seenDirectories.add(relative) ||
            directories[relative] !=
                node.item.updatedAt?.microsecondsSinceEpoch ||
            wanted == null ||
            wanted[0] != node.bytes ||
            wanted[1] != node.fileCount ||
            wanted[2] != node.folderCount) {
          throw StateError('Directory metadata mismatch: $relative');
        }
        pending.addAll(node.children);
        for (var index = 1; index < node.children.length; index++) {
          final before = node.children[index - 1];
          final after = node.children[index];
          if (before.bytes < after.bytes ||
              (before.bytes == after.bytes &&
                  before.path.compareTo(after.path) > 0)) {
            throw StateError('Incorrect child order: $relative');
          }
        }
      } else {
        final wanted = files[relative];
        final modified = node.item.updatedAt?.microsecondsSinceEpoch;
        if (!seenFiles.add(relative) ||
            wanted == null ||
            wanted[1] != node.bytes ||
            node.item.size != node.bytes ||
            wanted[2] != modified ||
            node.fileCount != 1 ||
            node.folderCount != 0 ||
            node.children.isNotEmpty) {
          throw StateError('File metadata mismatch: $relative');
        }
        records.add([relative, node.bytes, modified!]);
      }
    }
    if (seenFiles.length != files.length ||
        seenDirectories.length != directories.length) {
      throw StateError('Missing file or directory metadata.');
    }
    records.sort((a, b) => (a[0] as String).compareTo(b[0] as String));
    final digest = sha256.convert(utf8.encode(jsonEncode(records))).toString();
    if (digest != data['filesSizeMtimeDigest']) {
      throw StateError('File path/size/mtime digest mismatch.');
    }
    return digest;
  }
}

/// Includes directory metadata and subtree totals, without per-run timestamps.
String storageScanMetadataFingerprint(StorageScanResult result) {
  final pending = <StorageNode>[result.root];
  final rows = <List<Object?>>[];
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    pending.addAll(node.children);
    rows.add([
      _relative(result.root.path, node.path),
      node.name,
      node.isFolder,
      node.item.size,
      node.item.updatedAt?.microsecondsSinceEpoch,
      node.item.isSymlink,
      node.bytes,
      node.fileCount,
      node.folderCount,
      node.unknownSizeCount,
      node.skippedLinkCount,
      node.isComplete,
    ]);
  }
  rows.sort((a, b) => (a[0] as String).compareTo(b[0] as String));
  return sha256.convert(utf8.encode(jsonEncode(rows))).toString();
}

String _relative(String root, String path) {
  if (path == root) return '';
  if (p.normalize(path) != path || !p.isWithin(root, path)) {
    throw StateError('Out-of-root or noncanonical benchmark entry: $path');
  }
  return p.relative(path, from: root).split(p.separator).join('/');
}
