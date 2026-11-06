import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'file_operation_service.dart';
import 'storage_transfer_contract.dart';

/// A captured snapshot may be used as a copy source while its owner remains
/// available. It never grants write, move, or persistent recovery authority.
class ReadOnlyOperationBackend extends FileOperationBackend {
  ReadOnlyOperationBackend(this.source, {required this.isAvailable});
  final FileOperationBackend source;
  final bool Function() isAvailable;
  @override
  Object get identity => source.identity;
  @override
  String get label => source.label;
  @override
  p.Context get paths => source.paths;
  @override
  String pathKey(String path) => source.pathKey(path);
  @override
  bool get isCurrent => isAvailable() && source.isCurrent;
  @override
  StorageTransferCapabilities get capabilities => source.capabilities;

  void _check() {
    if (!isCurrent) {
      throw StateError('The captured copy source is no longer available.');
    }
  }

  @override
  Future<FileItem?> stat(String path) async {
    _check();
    final item = await source.stat(path);
    _check();
    return item;
  }

  @override
  Future<List<FileItem>> list(String path) async {
    _check();
    final items = await source.list(path);
    _check();
    return items;
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    _check();
    await for (final chunk in source.readFile(file)) {
      _check();
      yield chunk;
    }
    _check();
  }

  @override
  Future<TransferMetadata> readMetadata(String path) async {
    _check();
    final metadata = await source.readMetadata(path);
    _check();
    return metadata;
  }

  @override
  Future<void> createDirectory(String path) async =>
      throw UnsupportedError('This snapshot is a read-only copy source.');
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async =>
      throw UnsupportedError('This snapshot is a read-only copy source.');
  @override
  Future<void> deleteFile(FileItem file) async =>
      throw UnsupportedError('This snapshot is a read-only copy source.');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('This snapshot is a read-only copy source.');
}
