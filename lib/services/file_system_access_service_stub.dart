// lib/services/file_system_access_service_stub.dart
//
// No-op stub for non-web platforms.

import 'dart:typed_data';
import 'file_system_access_service.dart';

FileSystemAccessService createFileSystemAccessService() =>
    _StubFileSystemAccessService();

class _StubFileSystemAccessService implements FileSystemAccessService {
  @override
  bool get isSupported => false;

  @override
  Future<FsaFileResult?> openFilePicker({List<String>? acceptedTypes}) async =>
      null;

  @override
  Future<String?> saveFilePicker({
    required Uint8List data,
    required String suggestedName,
    List<String>? acceptedTypes,
  }) async => null;

  @override
  Future<Object?> openDirectoryPicker() async => null;

  @override
  Future<void> persistHandle(String key, Object handle) async {}

  @override
  Future<Object?> getPersistedHandle(String key) async => null;

  @override
  Future<void> removePersistedHandle(String key) async {}
}
