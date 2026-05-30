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

  /// Save data to a file, handling platform-specific permissions
  Future<void> saveFile(String path, Uint8List data);

  /// Get web metadata without stat()
  Map<String, dynamic> getWebMetadata(String path) => {};

  /// Force a refresh of the file listing
  Future<void> refresh() async {}

  factory LocalFileService() {
    if (kIsWeb) {
      return platform.WebFileService.instance;
    }
    return platform.createPlatformFileService();
  }
}
