import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:path/path.dart' as p;

/// A read-only fixture. Every attempted mutation is counted and rejected.
class ConflictPreviewBackend extends FileOperationBackend {
  ConflictPreviewBackend({
    required this.file,
    required this.bytes,
    this.storageLabel = 'Review storage',
  });

  FileItem file;
  Uint8List bytes;
  final String storageLabel;
  Object session = Object();
  bool current = true;
  bool bounded = true;
  int stats = 0;
  int reads = 0;
  int writes = 0;
  Future<FileItem?> Function(String path)? statOverride;
  Stream<List<int>> Function(FileItem file)? readOverride;

  @override
  Object get identity => session;
  @override
  String get label => storageLabel;
  @override
  bool get isCurrent => current;
  @override
  StorageTransferCapabilities get capabilities =>
      StorageTransferCapabilities(boundedDownload: bounded);
  @override
  p.Context get paths => p.posix;
  @override
  Future<FileItem?> stat(String path) async {
    stats++;
    if (statOverride != null) return statOverride!(path);
    return path == file.path ? file : null;
  }

  @override
  Stream<List<int>> readFile(FileItem file) {
    reads++;
    return readOverride?.call(file) ?? Stream.value(Uint8List.fromList(bytes));
  }

  @override
  Future<List<FileItem>> list(String path) async =>
      throw StateError('Preview must not enumerate directories.');
  Never _write() {
    writes++;
    throw StateError('Preview must not mutate files.');
  }

  @override
  Future<void> createDirectory(String path) async => _write();
  @override
  Future<void> deleteEmptyDirectory(String path) async => _write();
  @override
  Future<void> deleteFile(FileItem file) async => _write();
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async => _write();
}
