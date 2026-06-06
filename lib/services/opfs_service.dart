// lib/services/opfs_service.dart
//
// Origin Private File System (OPFS) service.
//
// OPFS gives web apps a sandboxed, persistent file system backed by the
// browser storage quota.  CrispCloud uses it as an offline cache on web —
// an alternative to FileCacheService which uses native dart:io on other
// platforms.
//
// Access is via navigator.storage.getDirectory() → FileSystemDirectoryHandle.
// All JS interop is wrapped with the same dart:js_util pattern used elsewhere
// in the codebase.
//
// Non-web platforms receive a no-op stub.

import 'dart:typed_data';

import 'opfs_service_stub.dart'
    if (dart.library.html) 'opfs_service_web.dart' as impl;

/// Abstract interface for the OPFS-backed cache.
abstract class OpfsService {
  /// Whether OPFS is supported by the current browser.
  bool get isSupported;

  /// Initialise the service (obtains the root directory handle).
  /// Must be called before any read/write operations.
  Future<void> initialize();

  /// Write [data] to a file at [relativePath] inside the OPFS root.
  /// Intermediate directories are created automatically.
  Future<void> writeFile(String relativePath, Uint8List data);

  /// Read a file from the OPFS cache.  Returns null if not found.
  Future<Uint8List?> readFile(String relativePath);

  /// Delete a cached file.
  Future<void> deleteFile(String relativePath);

  /// Check whether a file exists in the cache.
  Future<bool> exists(String relativePath);

  /// Remove all cached files (full cache wipe).
  Future<void> clearAll();

  factory OpfsService() => impl.createOpfsService();
}
