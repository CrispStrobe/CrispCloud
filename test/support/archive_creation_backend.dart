import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:path/path.dart' as p;

/// An isolated filesystem with a real verify-before-publication boundary.
class ArchiveCreationBackend extends FileOperationBackend {
  final contents = <String, Uint8List>{};
  final directories = <String>{'/', '/input', '/output'};
  final links = <String>{};
  final advertisedSizes = <String, int>{};
  final writes = <String>[];
  bool current = true;
  void Function()? beforeStageVerification;
  @override
  Object get identity => this;
  @override
  String get label => 'Test files';
  @override
  p.Context get paths => p.posix;
  @override
  bool get isCurrent => current;
  @override
  bool get supportsStagedVerification => true;

  void put(String path, List<int> bytes) {
    contents[path] = Uint8List.fromList(bytes);
    var parent = paths.dirname(path);
    while (directories.add(parent) && parent != '/') {
      parent = paths.dirname(parent);
    }
  }

  @override
  Future<FileItem?> stat(String path) async {
    if (directories.contains(path)) {
      return FileItem(name: paths.basename(path), path: path, isFolder: true);
    }
    final bytes = contents[path];
    if (bytes == null && !links.contains(path)) return null;
    return FileItem(
      name: paths.basename(path),
      path: path,
      isFolder: false,
      isSymlink: links.contains(path),
      size: advertisedSizes[path] ?? bytes?.length,
      updatedAt: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<List<FileItem>> list(String path) async => [
    for (final name in {...contents.keys, ...directories, ...links})
      if (name != path && paths.dirname(name) == path) (await stat(name))!,
  ];

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    final bytes = contents[file.path]!;
    for (var offset = 0; offset < bytes.length; offset += 32768) {
      yield Uint8List.sublistView(
        bytes,
        offset,
        offset + 32768 > bytes.length ? bytes.length : offset + 32768,
      );
    }
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
    if (replace || await stat(path) != null) {
      throw StateError('Destination exists.');
    }
    final stage = '${paths.dirname(path)}/.stage';
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in data) {
      bytes.add(chunk);
    }
    put(stage, bytes.takeBytes());
    try {
      beforeStageVerification?.call();
      await verifyStaged?.call((await stat(stage))!);
      if (await stat(path) != null) throw StateError('Destination exists.');
      contents[path] = contents[stage]!;
      writes.add(path);
    } finally {
      contents.remove(stage);
    }
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) => writePreparedFile(path, data, length, replace: replace);
  @override
  Future<void> createDirectory(String path) async {
    directories.add(path);
  }

  @override
  Future<void> deleteFile(FileItem file) async {
    contents.remove(file.path);
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {
    directories.remove(path);
  }
}
