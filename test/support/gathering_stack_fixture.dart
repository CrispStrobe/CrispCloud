import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/gathering_stack_service.dart';
import 'package:path/path.dart' as p;

class GatheringMemoryBackend extends FileOperationBackend {
  GatheringMemoryBackend(this.reference) {
    directory('/');
  }
  final StorageReference reference;
  final items = <String, FileItem>{};
  final contents = <String, List<int>>{};
  final writes = <String>[];
  final listings = <String>[];
  final failWrites = <String>{};
  Future<void> Function(String)? beforeList;
  bool current = true;

  @override
  StorageReference get storageReference => reference;
  @override
  String get persistentStorageId => reference.id;
  @override
  Object get identity => '${reference.id}\u0000${reference.root}';
  @override
  String get label => 'Same account label';
  @override
  bool get isCurrent => current;
  @override
  p.Context get paths => p.posix;

  void directory(String path) {
    if (items.containsKey(path)) return;
    final parent = paths.dirname(path);
    if (parent != path) directory(parent);
    items[path] = FileItem(
      name: paths.basename(path),
      path: path,
      uuid: 'folder:$path',
      isFolder: true,
      updatedAt: DateTime.utc(2026, 1, 1),
    );
  }

  FileItem file(
    String path,
    String content, {
    String? objectId,
    String? version,
  }) {
    directory(paths.dirname(path));
    final bytes = utf8.encode(content);
    contents[path] = bytes;
    return items[path] = FileItem(
      name: paths.basename(path),
      path: path,
      uuid: objectId,
      isFolder: false,
      size: bytes.length,
      updatedAt: DateTime.utc(2026, 1, 1),
      metadata: version == null ? null : {'etag': version},
    );
  }

  @override
  Future<FileItem?> stat(String path) async {
    if (!current) throw StateError('Offline');
    return items[path];
  }

  @override
  Future<List<FileItem>> list(String path) async {
    listings.add(path);
    await beforeList?.call(path);
    if (!current) throw StateError('Offline');
    if (items[path]?.isFolder != true) throw StateError('Missing directory');
    return items.values
        .where((item) => item.path != path && paths.dirname(item.path!) == path)
        .toList();
  }

  @override
  Future<void> createDirectory(String path) async => directory(path);

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    if (!current) throw StateError('Offline');
    yield List.of(contents[file.path]!);
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async {
    if (failWrites.contains(path)) throw StateError('Configured write failure');
    if (!replace && items.containsKey(path)) throw StateError('Occupied');
    final bytes = <int>[];
    await for (final chunk in data) {
      bytes.addAll(chunk);
    }
    file(path, utf8.decode(bytes));
    writes.add(path);
  }

  @override
  Future<void> deleteFile(FileItem file) async {
    items.remove(file.path);
    contents.remove(file.path);
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {
    if ((await list(path)).isNotEmpty) throw StateError('Not empty');
    items.remove(path);
  }

  GatheringSourceBinding binding() =>
      GatheringSourceBinding(storage: reference, backend: this);

  GatheringDestinationCapture destination(
    String path, {
    bool Function()? isCurrent,
    bool Function()? isReviewCurrent,
  }) => GatheringDestinationCapture(
    backend: this,
    path: path,
    isCurrent: isCurrent ?? () => current,
    isReviewCurrent: isReviewCurrent,
  );
}

const gatheringAccountA = StorageReference(
  kind: 'remote',
  provider: 'Memory',
  accountKey: 'account-a',
);
const gatheringAccountB = StorageReference(
  kind: 'remote',
  provider: 'Memory',
  accountKey: 'account-b',
);
const gatheringTarget = StorageReference(
  kind: 'remote',
  provider: 'Memory',
  accountKey: 'target-account',
);
