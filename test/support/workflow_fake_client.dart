import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:crisp_cloud/services/cloud_storage_interface.dart';

class WorkflowFakeClient extends CloudStorageClient {
  final Map<String, Uint8List> files = {};
  final Map<String, DateTime> modified = {};
  final Set<String> directories = {'/'};
  final List<String> writes = [];
  final List<String> downloads = [];
  bool failUploads = false;
  bool current = true;

  void put(String path, List<int> bytes, {DateTime? date}) {
    files[path] = Uint8List.fromList(bytes);
    modified[path] = date ?? DateTime.utc(2025, 1, 1);
    var parent = p.posix.dirname(path);
    while (directories.add(parent) && parent != '/') {
      parent = p.posix.dirname(parent);
    }
  }

  @override
  String get providerName => 'Memory';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => current;
  @override
  String? get userId => 'account-a';
  @override
  String? get bucketId => null;
  @override
  bool get supportsStreaming => true;
  @override
  Future<void> login(
    String email,
    String password, {
    String? twoFactorCode,
  }) async {}
  @override
  Future<bool> is2faNeeded(String email) async => false;
  @override
  Future<void> logout() async {
    current = false;
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async =>
      files.containsKey(path) || directories.contains(path)
      ? {'path': path}
      : null;

  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'files': [
      for (final entry in files.entries)
        if (p.posix.dirname(entry.key) == path)
          {
            'name': p.posix.basename(entry.key),
            'path': entry.key,
            'size': entry.value.length,
            'lastModified': modified[entry.key]!.toIso8601String(),
            'content_hash': sha256.convert(entry.value).toString(),
          },
    ],
    'folders': [
      for (final directory in directories)
        if (directory != path && p.posix.dirname(directory) == path)
          {'name': p.posix.basename(directory), 'path': directory},
    ],
  };

  @override
  Future<Uint8List> downloadFileBytes(
    String path, {
    Function(int, int)? onProgress,
  }) async {
    downloads.add(path);
    return Uint8List.fromList(
      files[path] ?? (throw StateError('Missing $path')),
    );
  }

  @override
  Stream<List<int>> downloadStream(
    String path, {
    Function(int, int)? onProgress,
  }) async* {
    final bytes = await downloadFileBytes(path);
    for (var i = 0; i < bytes.length; i += 2) {
      yield bytes.sublist(i, i + 2 > bytes.length ? bytes.length : i + 2);
    }
  }

  @override
  Future<void> uploadFile(
    List<int> bytes,
    String name,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    if (failUploads) throw StateError('Upload failed');
    final path = p.posix.join(targetPath, name);
    writes.add(path);
    put(path, bytes, date: DateTime.now());
  }

  @override
  Future<void> createFolderPath(String path) async {
    directories.add(path);
  }

  @override
  Future<void> deletePath(String path) async {
    files.remove(path);
    directories.remove(path);
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    put(targetPath, files.remove(sourcePath)!);
  }

  @override
  Future<void> renamePath(String path, String name) =>
      movePath(path, p.posix.join(p.posix.dirname(path), name));
  @override
  Future<void> downloadFileByPath(
    String path,
    String localPath, {
    Function(int, int)? onProgress,
  }) async => throw UnimplementedError();
}
