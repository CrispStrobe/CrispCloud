// lib/services/file_system_access_service.dart
//
// File System Access API service (web only).
//
// Provides access to showOpenFilePicker(), showSaveFilePicker(), and
// showDirectoryPicker() via JS interop. File handles can be persisted to
// IndexedDB so the user doesn't have to re-grant access after a page reload.
//
// On non-web platforms the stub implementation is compiled in, providing
// the same interface as no-ops.

import 'dart:typed_data';

import 'file_system_access_service_stub.dart'
    if (dart.library.html) 'file_system_access_service_web.dart' as impl;

/// Represents a resolved file handle (name + bytes).
class FsaFileResult {
  final String name;
  final Uint8List bytes;
  const FsaFileResult({required this.name, required this.bytes});
}

/// Abstract interface for the File System Access API.
abstract class FileSystemAccessService {
  /// Whether the browser supports the File System Access API.
  bool get isSupported;

  /// Open a file picker and return the selected file contents.
  /// Returns null if the user cancelled.
  Future<FsaFileResult?> openFilePicker({List<String>? acceptedTypes});

  /// Open a save picker and write [data] to the chosen file.
  /// Returns the chosen file name, or null on cancel.
  Future<String?> saveFilePicker({
    required Uint8List data,
    required String suggestedName,
    List<String>? acceptedTypes,
  });

  /// Open a directory picker and return its JS handle (opaque on non-web).
  /// Returns null if the user cancelled or the API is not supported.
  Future<Object?> openDirectoryPicker();

  /// Persist a file/directory handle to IndexedDB under [key].
  Future<void> persistHandle(String key, Object handle);

  /// Retrieve a previously-persisted handle from IndexedDB.
  /// Returns null if no handle is stored for [key].
  Future<Object?> getPersistedHandle(String key);

  /// Remove a persisted handle from IndexedDB.
  Future<void> removePersistedHandle(String key);

  factory FileSystemAccessService() => impl.createFileSystemAccessService();
}
