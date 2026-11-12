import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/command_entry_service.dart';
import 'package:crisp_cloud/services/conditional_file_publication.dart';
import 'package:crisp_cloud/services/external_editor_service.dart';
import 'package:crisp_cloud/services/external_remote_editing_service.dart';
import 'package:crisp_cloud/services/private_tool_staging.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:flutter_test/flutter_test.dart';

String editHash(List<int> bytes) => sha256.convert(bytes).toString();

class FakeEditBundle {
  final files = <String, List<int>>{};
  Map<String, dynamic>? manifest;
  bool leased = true;
  final changes = StreamController<void>.broadcast(sync: true);
}

class FakeEditStagingStore implements PrivateToolStagingStore {
  final bundles = <String, FakeEditBundle>{};
  int _next = 0;
  Future<void> Function(Map<String, dynamic>)? beforeManifest;
  final failDeletionOnce = <String>{};
  final failCloseOnce = <String>{};
  Future<void> Function(String id)? beforeClose;
  @override
  Future<PrivateToolStage> create({required String kind, String? id}) async {
    id ??= '00000000-0000-4000-8000-${(++_next).toString().padLeft(12, '0')}';
    final bundle = FakeEditBundle();
    bundles[id] = bundle;
    return FakeEditStage(this, id, kind, bundle);
  }

  @override
  Future<List<String>> list(String kind) async => bundles.keys.toList();
  @override
  Future<PrivateToolStage> open({
    required String kind,
    required String id,
  }) async {
    final bundle = bundles[id];
    if (bundle == null || bundle.leased) {
      throw const PrivateStageException(PrivateStageFailure.busy);
    }
    bundle.leased = true;
    return FakeEditStage(this, id, kind, bundle);
  }

  void edit(
    ExternalEditSession session,
    List<int> bytes, {
    bool notify = true,
  }) {
    final bundle = bundles[session.id]!;
    bundle.files[session.record!.workingName] = List.of(bytes);
    if (notify) bundle.changes.add(null);
  }
}

class FakeEditStage implements PrivateToolStage {
  FakeEditStage(this.store, this.id, this.kind, this.bundle);
  final FakeEditStagingStore store;
  final FakeEditBundle bundle;
  @override
  final String id, kind;
  bool closed = false;
  @override
  String get directoryPath => '/stages/$kind/$id';
  void check() {
    if (closed) {
      throw const PrivateStageException(PrivateStageFailure.unavailable);
    }
  }

  PrivateStagedFile identity(String name, int maxBytes) {
    check();
    final data = bundle.files[name];
    if (data == null) {
      throw const PrivateStageException(PrivateStageFailure.unavailable);
    }
    if (data.length > maxBytes) {
      throw const PrivateStageException(PrivateStageFailure.tooLarge);
    }
    return PrivateStagedFile(
      name: name,
      path: '$directoryPath/$name',
      length: data.length,
      sha256: editHash(data),
    );
  }

  @override
  Future<PrivateStagedFile> write(
    String name,
    Stream<List<int>> source, {
    required int maxBytes,
    int? expectedLength,
    PrivateStageCheckpoint? checkpoint,
  }) async {
    check();
    if (bundle.files.containsKey(name)) {
      throw const PrivateStageException(PrivateStageFailure.changed);
    }
    final bytes = <int>[];
    await for (final chunk in source) {
      await checkpoint?.call();
      if (bytes.length + chunk.length > maxBytes) {
        throw const PrivateStageException(PrivateStageFailure.tooLarge);
      }
      bytes.addAll(chunk);
    }
    await checkpoint?.call();
    if (expectedLength != null && expectedLength != bytes.length) {
      throw const PrivateStageException(PrivateStageFailure.changed);
    }
    bundle.files[name] = bytes;
    return identity(name, maxBytes);
  }

  @override
  Future<PrivateStagedFile> inspect(
    String name, {
    required int maxBytes,
    PrivateStageCheckpoint? checkpoint,
  }) async {
    await checkpoint?.call();
    return identity(name, maxBytes);
  }

  @override
  Stream<List<int>> openRead(
    PrivateStagedFile expected, {
    PrivateStageCheckpoint? checkpoint,
  }) async* {
    final before = identity(expected.name, expected.length);
    if (before.sha256 != expected.sha256 || before.path != expected.path) {
      throw const PrivateStageException(PrivateStageFailure.changed);
    }
    await checkpoint?.call();
    yield List.of(bundle.files[expected.name]!);
    await checkpoint?.call();
    if (identity(expected.name, expected.length).sha256 != expected.sha256) {
      throw const PrivateStageException(PrivateStageFailure.changed);
    }
  }

  @override
  Future<PrivateStagedFile> snapshot(
    String name,
    String snapshotName, {
    required int maxBytes,
    PrivateStageCheckpoint? checkpoint,
  }) async {
    final source = await inspect(
      name,
      maxBytes: maxBytes,
      checkpoint: checkpoint,
    );
    return write(
      snapshotName,
      openRead(source),
      maxBytes: maxBytes,
      expectedLength: source.length,
      checkpoint: checkpoint,
    );
  }

  @override
  Stream<void> watch(String name) => bundle.changes.stream;
  @override
  Future<void> deleteFile(String name) async {
    check();
    bundle.files.remove(name);
  }

  @override
  Future<Map<String, dynamic>?> readManifest() async {
    check();
    return bundle.manifest == null
        ? null
        : jsonDecode(jsonEncode(bundle.manifest)) as Map<String, dynamic>;
  }

  @override
  Future<void> writeManifest(Map<String, dynamic> manifest) async {
    check();
    await store.beforeManifest?.call(manifest);
    bundle.manifest = jsonDecode(jsonEncode(manifest)) as Map<String, dynamic>;
  }

  @override
  Future<void> close() async {
    await store.beforeClose?.call(id);
    closed = true;
    bundle.leased = false;
    if (store.failCloseOnce.remove(id)) throw StateError('close failed');
  }

  @override
  Future<void> delete() async {
    check();
    closed = true;
    bundle.leased = false;
    if (store.failDeletionOnce.remove(id)) throw StateError('delete failed');
    store.bundles.remove(id);
    await bundle.changes.close();
  }
}

class FakeEditClient extends Fake
    implements
        CloudStorageClient,
        ConditionalFilePublication,
        CloudTransferOperations {
  List<int> bytes = [1, 2];
  String path = '/work/document.txt',
      objectId = 'id:document',
      account = 'original';
  int revision = 1, writes = 0, activeWrites = 0, maximumActiveWrites = 0;
  bool authenticated = true,
      current = true,
      reviewCurrent = true,
      loseAcknowledgement = false;
  Future<void> Function()? beforeCommit, afterCommit, afterRead;
  final uploaded = <List<int>>[];
  @override
  String get providerName => 'Fixture';
  @override
  String? get userId => 'fixture@example.test';
  @override
  String? get bucketId => null;
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => authenticated;
  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(boundedDownload: true);

  FilePublicationVersion get version => FilePublicationVersion(
    accountIdentity: editHash(utf8.encode(account)),
    path: path,
    objectId: objectId,
    revision: revision.toString(),
    length: bytes.length,
    contentHash: editHash(bytes),
  );

  ExternalEditSource source() => ExternalEditSource(
    reference: FileReference(
      storage: storageReferenceForClient(this),
      path: path,
      objectId: objectId,
    ),
    file: FileItem(
      name: path.split('/').last,
      path: path,
      uuid: objectId,
      isFolder: false,
      size: bytes.length,
    ),
    client: this,
    isCurrent: () => current,
    isReviewCurrent: () => reviewCurrent,
  );

  void remoteEdit(List<int> contents) {
    bytes = List.of(contents);
    revision++;
  }

  @override
  Future<FilePublicationVersion> inspectForPublication(
    String requested, {
    required void Function() checkCurrent,
  }) async {
    checkCurrent();
    if (requested.toLowerCase() != path) {
      throw const FilePublicationException(FilePublicationFailure.changed);
    }
    return version;
  }

  @override
  Stream<List<int>> readForPublication(
    FilePublicationVersion expected, {
    required void Function() checkCurrent,
  }) async* {
    checkCurrent();
    if (version != expected) {
      throw const FilePublicationException(FilePublicationFailure.changed);
    }
    yield List.of(bytes);
    await afterRead?.call();
    checkCurrent();
    if (version != expected) {
      throw const FilePublicationException(FilePublicationFailure.changed);
    }
  }

  @override
  Future<FilePublicationVersion> publishFileVersion(
    FilePublicationVersion expected,
    Stream<List<int>> contents, {
    required int length,
    required void Function() checkCurrent,
    required Future<void> Function(String contentHash) prepareCommit,
  }) async {
    activeWrites++;
    if (activeWrites > maximumActiveWrites) maximumActiveWrites = activeWrites;
    try {
      checkCurrent();
      if (version != expected) {
        throw const FilePublicationException(FilePublicationFailure.conflict);
      }
      final data = await contents.fold<List<int>>(
        [],
        (all, part) => all..addAll(part),
      );
      if (data.length != length) {
        throw const FilePublicationException(FilePublicationFailure.invalid);
      }
      await beforeCommit?.call();
      await prepareCommit(editHash(data));
      checkCurrent();
      if (version != expected) {
        throw const FilePublicationException(FilePublicationFailure.conflict);
      }
      bytes = data;
      revision++;
      writes++;
      uploaded.add(List.of(data));
      final result = version;
      await afterCommit?.call();
      if (loseAcknowledgement) {
        throw const FilePublicationException(FilePublicationFailure.uncertain);
      }
      return result;
    } finally {
      activeWrites--;
    }
  }
}

class FakeReadOnlyEditClient extends Fake
    implements CloudStorageClient, CloudTransferOperations {
  List<int> bytes = [1, 2];
  @override
  String get providerName => 'ReadOnlyFixture';
  @override
  String? get userId => 'fixture@example.test';
  @override
  String? get bucketId => null;
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => true;
  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(boundedDownload: true);
  @override
  Future<Map<String, dynamic>> listPath(String path) async => path == '/'
      ? {
          'folders': [
            {'name': 'work', 'uuid': 'folder'},
          ],
          'files': [],
        }
      : {
          'folders': [],
          'files': [
            {'name': 'document.txt', 'uuid': 'file', 'size': bytes.length},
          ],
        };
  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) => Stream.value(bytes);
  ExternalEditSource source() => ExternalEditSource(
    reference: FileReference(
      storage: storageReferenceForClient(this),
      path: '/work/document.txt',
      objectId: 'file',
    ),
    file: FileItem(
      name: 'document.txt',
      path: '/work/document.txt',
      uuid: 'file',
      isFolder: false,
      size: bytes.length,
    ),
    client: this,
    isCurrent: () => true,
  );
}

class FakeEditorHost implements ExternalEditorHost {
  @override
  String? platform = 'linux';
  bool access = true;
  int executableVersion = 0;
  final launches =
      <({String executable, List<String> arguments, String directory})>[];
  Future<void> Function()? onLaunch;
  @override
  Future<bool> hasExistingAccess(String path) async => access;
  @override
  Future<CommandEntryFileIdentity?> inspectPath(String path) async =>
      CommandEntryFileIdentity(
        resolvedPath: path,
        isDirectory: path.startsWith('/stages/'),
        size: 1,
        mode: 0x1c0,
        modified: DateTime.fromMillisecondsSinceEpoch(executableVersion),
        changed: DateTime.fromMillisecondsSinceEpoch(executableVersion),
      );
  @override
  Future<void> launch(
    String executable,
    List<String> arguments,
    String directory,
  ) async {
    launches.add((
      executable: executable,
      arguments: List.of(arguments),
      directory: directory,
    ));
    await onLaunch?.call();
  }
}
