import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/archive_publication_access_policy.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:path/path.dart' as p;

/// Independent exact-move filesystem. Hooks model replies lost after physical
/// mutations, concurrent writers, source failures, and captured-account loss.
class ArchiveEndpointTestBackend extends FileOperationBackend
    implements ArchivePublicationAccessPolicy {
  @override
  bool get preservesArchiveAccessPolicy => accessPolicySupported;
  bool accessPolicySupported = true;
  final files = <String, Uint8List>{};
  final directories = <String>{'/', '/input', '/out'};
  final links = <String>{};
  final versions = <String, int>{};
  final ids = <String, String>{};
  final modes = <String, int>{};
  final mutations = <String>[];
  int _revision = 0;
  bool current = true;
  bool publicationSupported = true;
  bool conditionalCleanup = true;
  String account = 'archive-fixture';
  FutureOr<void> Function(String action, String path, String? destination)?
  before;
  FutureOr<void> Function(String action, String path, String? destination)?
  after;
  @override
  Object get identity => this;
  @override
  String get label => 'Archive fixture';
  @override
  p.Context get paths => p.posix;
  @override
  bool get isCurrent => current;
  @override
  bool get canRecover => true;
  @override
  StorageReference get storageReference => StorageReference(
    kind: 'remote',
    provider: 'archive-fixture',
    accountKey: account,
  );
  @override
  bool get supportsStagedVerification => true;
  @override
  StorageTransferCapabilities get capabilities => StorageTransferCapabilities(
    caseSensitivity: StorageCaseSensitivity.sensitive,
    nativeMove: publicationSupported,
    atomicMove: publicationSupported,
    noReplaceMove: publicationSupported,
    conditionalDelete: conditionalCleanup,
    deleteEmptyDirectory: true,
    permissions: true,
  );

  void put(String path, List<int> bytes, {bool preserveVersion = false}) {
    files[path] = Uint8List.fromList(bytes);
    if (!preserveVersion) versions[path] = ++_revision;
    ids.putIfAbsent(path, () => 'fixture-${++_revision}');
    modes.putIfAbsent(path, () => 0x180);
    var parent = paths.dirname(path);
    while (directories.add(parent) && parent != '/') {
      parent = paths.dirname(parent);
    }
  }

  void _check() {
    if (!current) throw StateError('Fixture account replaced.');
  }

  @override
  Future<FileItem?> stat(String path) async {
    _check();
    if (directories.contains(path)) {
      return FileItem(
        name: paths.basename(path),
        path: path,
        isFolder: true,
        isSymlink: links.contains(path),
      );
    }
    if (!files.containsKey(path) && !links.contains(path)) return null;
    return FileItem(
      name: paths.basename(path),
      path: path,
      isFolder: false,
      size: files[path]?.length ?? 0,
      isSymlink: links.contains(path),
      uuid: ids[path],
      updatedAt: DateTime.utc(2026).add(Duration(seconds: versions[path] ?? 0)),
      metadata: {'version': '${versions[path]}'},
    );
  }

  @override
  Future<List<FileItem>> list(String path) async => [
    for (final key in {...files.keys, ...directories, ...links})
      if (key != path && paths.dirname(key) == path) (await stat(key))!,
  ];
  @override
  Stream<List<int>> readFile(FileItem file) async* {
    _check();
    await before?.call('read', file.path!, null);
    final bytes = files[file.path!];
    if (bytes == null) throw StateError('Fixture source missing.');
    for (var offset = 0; offset < bytes.length; offset += 8192) {
      _check();
      yield bytes.sublist(offset, (offset + 8192).clamp(0, bytes.length));
    }
    await after?.call('read', file.path!, null);
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
    _check();
    if (replace || await stat(path) != null) {
      throw StateError('Fixture exclusive destination occupied.');
    }
    final temporary = '$path.upload';
    final contents = BytesBuilder(copy: false);
    try {
      await checkpoint?.call({
        'phase': 'staging',
        'stagedPath': temporary,
        'destination': path,
      });
      await for (final chunk in data) {
        _check();
        contents.add(chunk);
      }
      if (length != null && contents.length != length) {
        throw StateError('Fixture source length changed.');
      }
      put(temporary, contents.takeBytes());
      await before?.call('write', path, null);
      await verifyStaged?.call((await stat(temporary))!);
      await checkpoint?.call({
        'phase': 'committing',
        'stagedPath': temporary,
        'destination': path,
      });
      _check();
      if (await stat(path) != null) {
        throw StateError('Fixture destination appeared.');
      }
      put(path, files[temporary]!);
      modes[path] = modes[temporary]!;
      mutations.add('write:$path');
      await after?.call('write', path, null);
      await checkpoint?.call({'phase': 'committed', 'destination': path});
    } finally {
      files.remove(temporary);
      versions.remove(temporary);
      ids.remove(temporary);
      modes.remove(temporary);
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
  Future<bool> moveNoReplace(FileItem file, String destination) async {
    _check();
    if (!publicationSupported) return false;
    await before?.call('move', file.path!, destination);
    _check();
    if (await stat(destination) != null || !files.containsKey(file.path!)) {
      throw StateError('Fixture move collision or missing source.');
    }
    if (file.metadata?['version'] != '${versions[file.path!]}') {
      throw StateError('Fixture move source changed.');
    }
    files[destination] = files.remove(file.path!)!;
    ids[destination] = ids.remove(file.path!)!;
    modes[destination] = modes.remove(file.path!)!;
    versions.remove(file.path!);
    versions[destination] = ++_revision;
    mutations.add('move:${file.path}:$destination');
    await after?.call('move', file.path!, destination);
    return true;
  }

  @override
  Future<void> deleteFile(FileItem file) async {
    _check();
    await before?.call('delete', file.path!, null);
    _check();
    if (file.metadata?['version'] != '${versions[file.path!]}') {
      throw StateError('Fixture cleanup source changed.');
    }
    files.remove(file.path!);
    ids.remove(file.path!);
    versions.remove(file.path!);
    modes.remove(file.path!);
    mutations.add('delete:${file.path}');
    await after?.call('delete', file.path!, null);
  }

  @override
  Future<void> createDirectory(String path) async => directories.add(path);
  @override
  Future<void> deleteEmptyDirectory(String path) async {
    if ((await list(path)).isNotEmpty) {
      throw StateError('Fixture directory not empty.');
    }
    directories.remove(path);
  }

  @override
  Future<TransferMetadata> readMetadata(String path) async =>
      TransferMetadata(mode: modes[path]);
  @override
  Future<void> writeMetadata(String path, TransferMetadata metadata) async {
    if (metadata.mode != null) modes[path] = metadata.mode!;
  }
}
