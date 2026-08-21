/// Path-based facade for common operations.
///
/// Provides convenience methods that accept human-readable paths
/// instead of raw UUIDs. Wraps resolvePath + operation into single calls.
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:filen_client/filen_client.dart';

extension FilenPaths on FilenClient {
  /// Upload a local file to a remote path.
  ///
  /// Example: `client.uploadToPath(File('report.pdf'), '/Documents/');`
  Future<Map<String, String>> uploadToPath(
    File localFile,
    String remotePath, {
    bool preserveTimestamps = false,
  }) async {
    // Determine if remotePath is a directory or a full file path
    String parentPath;
    if (remotePath.endsWith('/')) {
      parentPath = remotePath;
    } else {
      // Check if it resolves to a folder
      try {
        final resolved = await resolvePath(remotePath);
        if (resolved['type'] == 'folder') {
          parentPath = remotePath;
        } else {
          parentPath = p.dirname(remotePath);
        }
      } catch (_) {
        parentPath = p.dirname(remotePath);
      }
    }

    final parent = await drive.resolveOrCreateFolder(parentPath);

    String? cTime, mTime;
    if (preserveTimestamps) {
      final stat = await localFile.stat();
      mTime = stat.modified.millisecondsSinceEpoch.toString();
      cTime = stat.changed.millisecondsSinceEpoch.toString();
    }

    return uploader.uploadFileChunked(
      localFile,
      parent['uuid'],
      creationTime: cTime,
      modificationTime: mTime,
    );
  }

  /// Download a file by remote path to a local destination.
  ///
  /// Example: `client.downloadFromPath('/Documents/report.pdf', '/tmp/');`
  Future<Map<String, dynamic>> downloadFromPath(
    String remotePath, {
    String? localDestination,
  }) async {
    final resolved = await resolvePath(remotePath);

    if (resolved['type'] != 'file') {
      throw Exception("'$remotePath' is not a file");
    }

    final savePath = localDestination != null
        ? (FileSystemEntity.isDirectorySync(localDestination)
            ? p.join(localDestination, p.basename(remotePath))
            : localDestination)
        : p.basename(remotePath);

    return downloader.downloadFile(resolved['uuid'], savePath: savePath);
  }

  /// Delete a file or folder by path (move to trash).
  ///
  /// Example: `client.trashByPath('/Documents/old-report.pdf');`
  Future<void> trashByPath(String remotePath) async {
    final resolved = await resolvePath(remotePath);
    await trashItem(resolved['uuid'], resolved['type']);
  }

  /// Rename a file or folder by path.
  ///
  /// Example: `client.renameByPath('/Documents/old.pdf', 'new.pdf');`
  Future<void> renameByPath(String remotePath, String newName) async {
    final resolved = await resolvePath(remotePath);
    await renameItem(resolved['uuid'], newName, resolved['type']);
  }

  /// Move a file or folder by path.
  ///
  /// Example: `client.moveByPath('/Documents/report.pdf', '/Archive/');`
  Future<void> moveByPath(String sourcePath, String destPath) async {
    final src = await resolvePath(sourcePath);
    final dest = await drive.resolveOrCreateFolder(destPath);
    await moveItem(src['uuid'], dest['uuid'], src['type']);
  }

  /// List contents of a folder by path.
  ///
  /// Returns a map with 'folders' and 'files' keys.
  Future<Map<String, List<Map<String, dynamic>>>> listPath(
      String remotePath) async {
    final resolved = await resolvePath(remotePath);
    if (resolved['type'] != 'folder') {
      throw Exception("'$remotePath' is not a folder");
    }

    final folders = await listFoldersAsync(resolved['uuid'], detailed: true);
    final files = await listFolderFiles(resolved['uuid'], detailed: true);

    return {'folders': folders, 'files': files};
  }

  /// Upload raw bytes as a file to a remote path.
  ///
  /// Useful for programmatic uploads without a local file.
  Future<Map<String, String>> uploadFileBytes(
    Uint8List bytes,
    String remotePath, {
    String? mimeType,
  }) async {
    final parentPath = p.dirname(remotePath);
    final fileName = p.basename(remotePath);
    final parent = await drive.resolveOrCreateFolder(parentPath);

    // Write to temp file, upload, clean up
    final tempDir = Directory.systemTemp.createTempSync('filen_upload_');
    final tempFile = File(p.join(tempDir.path, fileName));

    try {
      await tempFile.writeAsBytes(bytes);
      return await uploader.uploadFileChunked(tempFile, parent['uuid']);
    } finally {
      if (tempFile.existsSync()) tempFile.deleteSync();
      if (tempDir.existsSync()) tempDir.deleteSync();
    }
  }
}
