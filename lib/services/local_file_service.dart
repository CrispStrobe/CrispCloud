// services/local_file_service.dart
//
// Abstract interface for local file system access.
// Platform implementations split into:
//   - local_file_service_native.dart (macOS, Windows, Linux, Android, iOS)
//   - local_file_service_web.dart (Web/PWA)

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/file_item.dart';

import 'local_file_service_native.dart' if (dart.library.html) 'local_file_service_web.dart' as platform;

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
  }) =>
      walkLocalFiles(
        path,
        includeHidden: includeHidden,
        maxItems: maxItems,
      );

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
          result.add(FileItem(
            name: name,
            path: entity.path,
            isFolder: false,
            size: stat.size,
            updatedAt: stat.modified,
          ));
        } catch (_) {
          // Skip entries that disappear mid-walk.
        }
      }
    }
  }

  await walk(path);
  return result;
}
