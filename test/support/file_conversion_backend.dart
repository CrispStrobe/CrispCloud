import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:path/path.dart' as p;

class ConversionMemoryBackend extends FileOperationBackend {
  ConversionMemoryBackend() {
    nodes['/files'] = FileItem(
      name: 'files',
      path: '/files',
      uuid: 'root',
      isFolder: true,
    );
  }
  final nodes = <String, FileItem>{};
  final contents = <String, Uint8List>{};
  final readCounts = <String, int>{};
  Object session = Object();
  bool current = true, bounded = true, exclusive = true, staged = true;
  int writes = 0, commits = 0, stats = 0;
  Future<void> Function(String path)? beforeVerify;
  Future<void> Function(String path)? beforeCommit;
  Stream<List<int>>? Function(FileItem file, int count)? readOverride;
  Future<FileItem?> Function(String path)? statOverride;

  FileItem put(String name, List<int> bytes, {String? path}) {
    path ??= '/files/$name';
    final file = FileItem(
      name: name,
      path: path,
      uuid: path,
      size: bytes.length,
      updatedAt: DateTime.utc(2026),
      isFolder: false,
      metadata: {'revision': 'v1'},
    );
    nodes[path] = file;
    contents[path] = Uint8List.fromList(bytes);
    return file;
  }

  @override
  Object get identity => session;
  @override
  String get label => 'Conversion storage';
  @override
  bool get isCurrent => current;
  @override
  bool get supportsStagedVerification => staged;
  @override
  StorageTransferCapabilities get capabilities => StorageTransferCapabilities(
    boundedDownload: bounded,
    boundedUpload: bounded,
    nativeMove: exclusive,
    atomicMove: exclusive,
    noReplaceMove: exclusive,
  );
  @override
  p.Context get paths => p.posix;
  @override
  Future<FileItem?> stat(String path) async {
    stats++;
    return statOverride == null ? nodes[path] : await statOverride!(path);
  }

  @override
  Stream<List<int>> readFile(FileItem file) {
    final count = readCounts.update(
      file.path!,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
    final overridden = readOverride?.call(file, count);
    if (overridden != null) return overridden;
    final bytes = Uint8List.fromList(contents[file.path!]!);
    return Stream.fromIterable([
      for (var offset = 0; offset < bytes.length; offset += 701)
        Uint8List.sublistView(
          bytes,
          offset,
          (offset + 701).clamp(0, bytes.length),
        ),
    ]);
  }

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem)? verifyStaged,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) async {
    writes++;
    if (replace) throw StateError('Conversion must never replace output.');
    final temporary = '$path.staged';
    await checkpoint?.call({'phase': 'staging'});
    try {
      final bytes = BytesBuilder();
      await for (final chunk in data) {
        bytes.add(chunk);
      }
      if (length != bytes.length) {
        throw StateError('Incorrect prepared length.');
      }
      put(paths.basename(temporary), bytes.takeBytes(), path: temporary);
      await beforeVerify?.call(temporary);
      await verifyStaged?.call(nodes[temporary]!);
      await beforeCommit?.call(path);
      await checkpoint?.call({'phase': 'committing'});
      if (nodes.containsKey(path)) {
        throw StateError('Exclusive publication failed.');
      }
      put(paths.basename(path), contents[temporary]!, path: path);
      commits++;
      await checkpoint?.call({'phase': 'committed'});
    } finally {
      nodes.remove(temporary);
      contents.remove(temporary);
    }
  }

  @override
  Future<List<FileItem>> list(String path) async =>
      throw StateError('Unexpected directory scan.');
  @override
  Future<void> createDirectory(String path) async =>
      throw StateError('Unexpected mutation.');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw StateError('Unexpected mutation.');
  @override
  Future<void> deleteFile(FileItem file) async =>
      throw StateError('Original files must not be deleted.');
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async => throw StateError('Unverified writes are forbidden.');
}
