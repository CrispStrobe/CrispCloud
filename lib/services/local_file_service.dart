// services/local_file_service.dart
//
// Abstract interface for local file system access.
// Platform implementations split into:
//   - local_file_service_native.dart (macOS, Windows, Linux, Android, iOS)
//   - local_file_service_web.dart (Web/PWA)

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/file_item.dart';

import 'local_file_service_native.dart'
    if (dart.library.html) 'local_file_service_web.dart'
    as platform;

/// Whether a local save wrote its destination or handed a copy to the browser.
enum LocalFileSaveResult { written, downloadedCopy }

/// Optional, explicit save semantics for document editors. Kept separate from
/// [LocalFileService] so existing integrations implementing that interface do
/// not silently acquire a stronger write contract.
abstract interface class LocalFileSaveReporter {
  Future<LocalFileSaveResult> saveFileWithResult(
    String path,
    Uint8List data, {
    bool overwrite = true,
  });
}

/// Reads current file contents instead of a browser's cached File snapshot.
abstract interface class FreshLocalFileReader {
  Future<Uint8List> readFileFresh(
    String path, {
    FileItem? fileItem,
    int? maxBytes,
  });
}

extension LocalFileEditorOperations on LocalFileService {
  Future<Uint8List> readFileForEdit(
    String path, {
    FileItem? fileItem,
    int? maxBytes,
  }) async {
    final service = this;
    if (service is FreshLocalFileReader) {
      return (service as FreshLocalFileReader).readFileFresh(
        path,
        fileItem: fileItem,
        maxBytes: maxBytes,
      );
    }
    if (maxBytes != null) {
      final length = await fileLength(path);
      if (length != null && length > maxBytes) {
        throw FileSystemException('File is too large to edit.', path);
      }
    }
    final bytes = await readFile(path, fileItem: fileItem);
    if (maxBytes != null && bytes.length > maxBytes) {
      throw FileSystemException('File is too large to edit.', path);
    }
    return bytes;
  }

  Future<LocalFileSaveResult> saveFileReportingResult(
    String path,
    Uint8List bytes, {
    bool overwrite = true,
  }) async {
    final service = this;
    if (service is LocalFileSaveReporter) {
      return (service as LocalFileSaveReporter).saveFileWithResult(
        path,
        bytes,
        overwrite: overwrite,
      );
    }
    if (!overwrite) {
      throw UnsupportedError('This filesystem cannot create a protected copy.');
    }
    await saveFile(path, bytes);
    // A legacy browser implementation cannot prove that it overwrote a file.
    return kIsWeb
        ? LocalFileSaveResult.downloadedCopy
        : LocalFileSaveResult.written;
  }
}

/// Optional bounded transfer operations. Folder cleanup must be nonrecursive.
abstract interface class LocalTransferFileOperations {
  Stream<List<int>> readTransferStream(String path);
  Future<void> writeTransferStream(String path, Stream<List<int>> data, int? length,
      {required bool replace});
  Future<void> deleteDirectoryIfEmpty(String path);
}

/// Optional per-invocation scope used by concurrent file operations.
abstract interface class ScopedLocalFileOperations {
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  );
}

extension LocalFileOperationScopes on LocalFileService {
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    final service = this;
    if (service is ScopedLocalFileOperations) {
      return (service as ScopedLocalFileOperations).withFileOperationAccess(
        path,
        action,
      );
    }
    if (!await ensureAccess(path)) {
      throw FileSystemException('Access to this path was not granted.', path);
    }
    return action();
  }
}

/// Abstract interface for handling local file system access.
abstract class LocalFileService {
  late String currentPath;
  String? get grantedBasePath;
  Future<String> getInitialPath();
  Future<String?> requestDirectoryAccess({String? initialDirectory});
  Future<List<FileSystemEntity>?> listDirectory(String path);
  Future<bool> hasAccessToPath(String path);
  Future<String> getSafeFallbackDirectory();

  /// Read file bytes, maintaining security scope on macOS
  Future<Uint8List> readFile(String path, {FileItem? fileItem});

  /// Ensure read access to [path]. On macOS, when the sandbox denies access,
  /// asks the user to grant the containing folder (security-scoped bookmark)
  /// and returns whether access was granted.
  Future<bool> ensureAccess(String path) async => true;

  /// Hold read access while streaming [path] (macOS security scope).
  /// Returns false when the user refuses or the path stays inaccessible.
  Future<bool> beginStreamAccess(String path) => ensureAccess(path);

  /// Release access acquired by [beginStreamAccess].
  Future<void> endStreamAccess() async {}

  /// File size, using the granted security scope where needed. Null when the
  /// file is missing or access was denied.
  Future<int?> fileLength(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

  /// Recursively collect files under [path] for the flat view.
  Future<List<FileItem>> walkFiles(
    String path, {
    bool includeHidden = false,
    int maxItems = 10000,
  }) => walkLocalFiles(path, includeHidden: includeHidden, maxItems: maxItems);

  /// Save data to a file, handling platform-specific permissions
  Future<void> saveFile(String path, Uint8List data);

  /// Get web metadata without stat()
  Map<String, dynamic> getWebMetadata(String path) => {};

  /// Return the raw platform file reference for [path] (web only).
  /// On web returns the underlying [html.File] object that was stored when
  /// the user granted directory access; on all other platforms returns null.
  /// The return type is [Object?] to avoid importing universal_html in the
  /// abstract interface.
  Object? getWebFileRef(String path) => null;

  /// Create a directory at [path] (web: uses FSA getDirectoryHandle with create).
  Future<void> createDirectory(String path) async {
    throw UnsupportedError('createDirectory not implemented on this platform');
  }

  /// Delete a file or directory entry (web: uses FSA removeEntry).
  Future<void> deleteEntry(String path, bool isFolder) async {
    throw UnsupportedError('deleteEntry not implemented on this platform');
  }

  /// Force a refresh of the file listing
  Future<void> refresh() async {}

  factory LocalFileService() {
    return platform.createPlatformFileService();
  }
}

/// Recursive local file walk used by the flat view. Callers on macOS wrap it in
/// a security scope (see MacosFileService.walkFiles).
Future<List<FileItem>> walkLocalFiles(
  String path, {
  bool includeHidden = false,
  int maxItems = 10000,
}) async {
  final result = <FileItem>[];
  final separator = Platform.pathSeparator;

  Future<void> walk(String dir) async {
    if (result.length >= maxItems) return;
    List<FileSystemEntity> entries;
    try {
      entries = await Directory(dir).list().toList();
    } catch (_) {
      return;
    }
    for (final entity in entries) {
      if (result.length >= maxItems) return;
      final name = entity.path.split(separator).last;
      if (!includeHidden && name.startsWith('.')) continue;
      FileSystemEntityType type;
      try {
        type = await FileSystemEntity.type(entity.path, followLinks: false);
      } catch (_) {
        continue;
      }
      if (type == FileSystemEntityType.link) continue;
      if (type == FileSystemEntityType.directory) {
        await walk(entity.path);
      } else if (type == FileSystemEntityType.file) {
        try {
          final stat = await entity.stat();
          result.add(
            FileItem(
              name: name,
              path: entity.path,
              isFolder: false,
              size: stat.size,
              updatedAt: stat.modified,
            ),
          );
        } catch (_) {
          // Skip entries that disappear mid-walk.
        }
      }
    }
  }

  await walk(path);
  return result;
}
