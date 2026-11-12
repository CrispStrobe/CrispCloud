import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../utils/async_lock.dart';
import 'native_file_primitives.dart';
import 'native_journal_lease.dart';
import 'native_system.dart';
import 'private_tool_staging.dart';

PrivateToolStagingStore createPrivateToolStagingStore({
  Future<String> Function()? rootDirectory,
}) => NativePrivateToolStagingStore(rootDirectory: rootDirectory);

const _manifestLimit = 64 * 1024;
const _maximumSessions = 256;
final _identifier = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _fileName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$');

Never _failure(PrivateStageFailure reason) =>
    throw PrivateStageException(reason);

void _checkKind(String kind) {
  if (!const {'external-edit', 'external-compare'}.contains(kind)) {
    _failure(PrivateStageFailure.invalid);
  }
}

void _checkName(String name) {
  if (!_fileName.hasMatch(name) ||
      const {'manifest.json', 'manifest.previous', 'lease'}.contains(name)) {
    _failure(PrivateStageFailure.invalid);
  }
}

Future<void> _privateMode(String path, int mode) async {
  if (Platform.isWindows) return; // Inherits the user's application-data ACL.
  if (!setFileMode(path, mode)) _failure(PrivateStageFailure.unavailable);
}

Future<void> _directory(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.directory ||
      p.normalize(await Directory(path).resolveSymbolicLinks()) != path) {
    _failure(PrivateStageFailure.invalid);
  }
  if (!Platform.isWindows) {
    final mode = (await Directory(path).stat()).mode;
    if (mode & 0x3f != 0 ||
        currentUserId() == null ||
        fileOwnerUserId(path) != currentUserId()) {
      _failure(PrivateStageFailure.unavailable);
    }
  }
}

/// Retained staging lives in user application data, not an expiring temp cache.
/// An OS lease prevents two app instances from operating on the same session.
class NativePrivateToolStagingStore implements PrivateToolStagingStore {
  NativePrivateToolStagingStore({
    Future<String> Function()? rootDirectory,
    this.beforeDelete,
  }) : _rootDirectory = rootDirectory ?? _defaultRoot;
  final Future<String> Function() _rootDirectory;

  /// Test seam at the Windows-compatible release/delete boundary. The parent
  /// mutation lease is still held while this callback runs.
  final Future<void> Function()? beforeDelete;
  Future<String>? _resolvedRoot;

  static Future<String> _defaultRoot() async => p.join(
    (await getApplicationSupportDirectory()).path,
    'external_tools_v1',
  );

  Future<String> _root() async {
    if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
      _failure(PrivateStageFailure.unsupported);
    }
    final future = _resolvedRoot ??= _createRoot();
    try {
      final root = await future;
      await _directory(root);
      return root;
    } catch (_) {
      if (identical(_resolvedRoot, future)) _resolvedRoot = null;
      rethrow;
    }
  }

  Future<String> _createRoot() async {
    final requested = p.normalize(await _rootDirectory());
    if (!p.isAbsolute(requested) || requested.contains('\u0000')) {
      _failure(PrivateStageFailure.invalid);
    }
    final parent = Directory(p.dirname(requested));
    await parent.create(recursive: true);
    final root = p.join(
      await parent.resolveSymbolicLinks(),
      p.basename(requested),
    );
    final kind = await FileSystemEntity.type(root, followLinks: false);
    if (kind == FileSystemEntityType.notFound) {
      await Directory(root).create();
      await _privateMode(root, 0x1c0);
    } else if (kind != FileSystemEntityType.directory) {
      _failure(PrivateStageFailure.invalid);
    }
    await _directory(root);
    return root;
  }

  Future<String> _kindDirectory(String kind) async {
    _checkKind(kind);
    final path = p.join(await _root(), kind);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await Directory(path).create();
      await _privateMode(path, 0x1c0);
    } else if (type != FileSystemEntityType.directory) {
      _failure(PrivateStageFailure.invalid);
    }
    await _directory(path);
    return path;
  }

  @override
  Future<List<String>> list(String kind) async {
    final parent = await _kindDirectory(kind);
    final result = <String>[];
    var count = 0;
    await for (final entry in Directory(parent).list(followLinks: false)) {
      if (p.basename(entry.path) == '_mutation') continue;
      if (++count > _maximumSessions) _failure(PrivateStageFailure.tooLarge);
      final id = p.basename(entry.path);
      if (entry is Directory && _identifier.hasMatch(id)) result.add(id);
    }
    result.sort();
    return List.unmodifiable(result);
  }

  @override
  Future<PrivateToolStage> create({required String kind, String? id}) async {
    final identifier = id ?? const Uuid().v4();
    if (!_identifier.hasMatch(identifier)) {
      _failure(PrivateStageFailure.invalid);
    }
    final parent = await _kindDirectory(kind);
    return _mutate(parent, () async {
      if ((await list(kind)).length >= _maximumSessions) {
        _failure(PrivateStageFailure.tooLarge);
      }
      final path = p.join(parent, identifier);
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        _failure(PrivateStageFailure.busy);
      }
      await Directory(path).create();
      await _privateMode(path, 0x1c0);
      return _open(parent, kind, identifier);
    });
  }

  @override
  Future<PrivateToolStage> open({
    required String kind,
    required String id,
  }) async {
    if (!_identifier.hasMatch(id)) _failure(PrivateStageFailure.invalid);
    final parent = await _kindDirectory(kind);
    return _mutate(parent, () => _open(parent, kind, id));
  }

  Future<T> _mutate<T>(String parent, Future<T> Function() action) async {
    await _directory(parent);
    final lease = await tryAcquireNativeJournalLease(
      p.join(parent, '_mutation'),
    );
    if (lease == null) _failure(PrivateStageFailure.busy);
    try {
      await _directory(parent);
      return await action();
    } finally {
      lease.close();
    }
  }

  Future<PrivateToolStage> _open(String parent, String kind, String id) async {
    final path = p.join(parent, id);
    await _directory(path);
    final lease = await tryAcquireNativeJournalLease(p.join(path, 'lease'));
    if (lease == null) _failure(PrivateStageFailure.busy);
    try {
      await _directory(path);
      return _NativePrivateToolStage(
        lease,
        id: id,
        kind: kind,
        directoryPath: path,
        protectDeletion: (action) => _mutate(parent, action),
        beforeDelete: beforeDelete,
        checkParents: () async {
          if (await _kindDirectory(kind) != parent) {
            _failure(PrivateStageFailure.changed);
          }
        },
      );
    } catch (_) {
      lease.close();
      rethrow;
    }
  }
}

class _NativePrivateToolStage implements PrivateToolStage {
  _NativePrivateToolStage(
    this._lease, {
    required this.id,
    required this.kind,
    required this.directoryPath,
    required this.checkParents,
    required this.protectDeletion,
    required this.beforeDelete,
  });

  @override
  final String id, kind, directoryPath;
  final NativeJournalLease _lease;
  final Future<void> Function() checkParents;
  final Future<void> Function(Future<void> Function()) protectDeletion;
  final Future<void> Function()? beforeDelete;
  final AsyncLock _lock = AsyncLock();
  int _active = 0;
  bool _closing = false, _closed = false;
  bool _deleteRequested = false;
  Completer<void>? _drained;
  Future<void>? _closingFuture;

  void _admit() {
    if (_closing || _closed) _failure(PrivateStageFailure.unavailable);
    _active++;
  }

  void _finish() {
    if (--_active == 0) {
      _drained?.complete();
      _drained = null;
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) {
    _admit();
    return _lock.synchronized(action).whenComplete(_finish);
  }

  Future<void> _check() async {
    if (_closed) _failure(PrivateStageFailure.unavailable);
    await checkParents();
    await _directory(directoryPath);
  }

  String _path(String name) {
    _checkName(name);
    return p.join(directoryPath, name);
  }

  Future<FileStat> _regular(String path) async {
    await _check();
    if (p.dirname(path) != directoryPath ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        p.normalize(await File(path).resolveSymbolicLinks()) != path) {
      _failure(PrivateStageFailure.invalid);
    }
    return File(path).stat();
  }

  static bool _same(FileStat before, FileStat after) =>
      after.type == FileSystemEntityType.file &&
      before.size == after.size &&
      before.modified == after.modified &&
      before.changed == after.changed;

  static void _limit(int length, int maxBytes) {
    if (maxBytes < 0 || length < 0) _failure(PrivateStageFailure.invalid);
    if (length > maxBytes) _failure(PrivateStageFailure.tooLarge);
  }

  @override
  Future<PrivateStagedFile> write(
    String name,
    Stream<List<int>> source, {
    required int maxBytes,
    int? expectedLength,
    PrivateStageCheckpoint? checkpoint,
  }) => _guard(
    () => _write(
      name,
      source,
      maxBytes: maxBytes,
      expectedLength: expectedLength,
      checkpoint: checkpoint,
    ),
  );

  Future<PrivateStagedFile> _write(
    String name,
    Stream<List<int>> source, {
    required int maxBytes,
    int? expectedLength,
    PrivateStageCheckpoint? checkpoint,
  }) async {
    final destination = _path(name);
    _limit(expectedLength ?? 0, maxBytes);
    await _check();
    await checkpoint?.call();
    if (await FileSystemEntity.type(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      _failure(PrivateStageFailure.changed);
    }
    final pending = File(
      p.join(directoryPath, '_pending-${const Uuid().v4()}'),
    );
    final result = _DigestSink();
    final hash = sha256.startChunkedConversion(result);
    var hashClosed = false;
    RandomAccessFile? writer;
    var length = 0;
    try {
      await pending.create(exclusive: true);
      await _privateMode(pending.path, 0x180);
      writer = await pending.open(mode: FileMode.writeOnly);
      await for (final chunk in source) {
        for (var offset = 0; offset < chunk.length;) {
          await _check();
          await checkpoint?.call();
          final end = math.min(offset + 64 * 1024, chunk.length);
          length += end - offset;
          _limit(length, maxBytes);
          if (expectedLength != null && length > expectedLength) {
            _failure(PrivateStageFailure.changed);
          }
          await writer.writeFrom(chunk, offset, end);
          hash.add(chunk.sublist(offset, end));
          await checkpoint?.call();
          offset = end;
        }
      }
      if (expectedLength != null && length != expectedLength) {
        _failure(PrivateStageFailure.changed);
      }
      await writer.flush();
      await writer.close();
      writer = null;
      hash.close();
      hashClosed = true;
      await _check();
      await checkpoint?.call();
      if (!await moveNativeNoReplace(pending.path, destination)) {
        _failure(PrivateStageFailure.unsupported);
      }
      return PrivateStagedFile(
        name: name,
        path: destination,
        length: length,
        sha256: result.value!,
      );
    } finally {
      await writer?.close();
      if (!hashClosed) hash.close();
      if (await FileSystemEntity.type(pending.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await pending.delete();
      }
    }
  }

  @override
  Future<PrivateStagedFile> inspect(
    String name, {
    required int maxBytes,
    PrivateStageCheckpoint? checkpoint,
  }) =>
      _guard(() => _inspect(name, maxBytes: maxBytes, checkpoint: checkpoint));

  Future<PrivateStagedFile> _inspect(
    String name, {
    required int maxBytes,
    PrivateStageCheckpoint? checkpoint,
  }) async {
    final path = _path(name);
    final before = await _regular(path);
    _limit(before.size, maxBytes);
    final result = _DigestSink();
    final hash = sha256.startChunkedConversion(result);
    var length = 0;
    try {
      await for (final chunk in File(path).openRead(0, maxBytes + 1)) {
        await checkpoint?.call();
        await _check();
        length += chunk.length;
        _limit(length, maxBytes);
        hash.add(chunk);
      }
    } finally {
      hash.close();
    }
    await checkpoint?.call();
    final after = await _regular(path);
    if (length != before.size || !_same(before, after)) {
      _failure(PrivateStageFailure.changed);
    }
    return PrivateStagedFile(
      name: name,
      path: path,
      length: length,
      sha256: result.value!,
    );
  }

  @override
  Stream<List<int>> openRead(
    PrivateStagedFile expected, {
    PrivateStageCheckpoint? checkpoint,
  }) async* {
    _admit();
    try {
      yield* _openRead(expected, checkpoint: checkpoint);
    } finally {
      _finish();
    }
  }

  Stream<List<int>> _openRead(
    PrivateStagedFile expected, {
    PrivateStageCheckpoint? checkpoint,
  }) async* {
    final path = _path(expected.name);
    if (path != expected.path ||
        expected.length < 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expected.sha256)) {
      _failure(PrivateStageFailure.invalid);
    }
    final before = await _regular(path);
    if (before.size != expected.length) _failure(PrivateStageFailure.changed);
    final result = _DigestSink();
    final hash = sha256.startChunkedConversion(result);
    var length = 0;
    try {
      await for (final chunk in File(path).openRead(0, expected.length + 1)) {
        await _check();
        await checkpoint?.call();
        length += chunk.length;
        if (length > expected.length) _failure(PrivateStageFailure.changed);
        hash.add(chunk);
        yield chunk;
      }
    } finally {
      hash.close();
    }
    final after = await _regular(path);
    await checkpoint?.call();
    if (length != expected.length ||
        result.value != expected.sha256 ||
        !_same(before, after)) {
      _failure(PrivateStageFailure.changed);
    }
  }

  @override
  Future<PrivateStagedFile> snapshot(
    String name,
    String snapshotName, {
    required int maxBytes,
    PrivateStageCheckpoint? checkpoint,
  }) => _guard(() async {
    final original = await _inspect(
      name,
      maxBytes: maxBytes,
      checkpoint: checkpoint,
    );
    return _write(
      snapshotName,
      _openRead(original, checkpoint: checkpoint),
      maxBytes: maxBytes,
      expectedLength: original.length,
      checkpoint: checkpoint,
    );
  });

  @override
  Stream<void> watch(String name) async* {
    final path = _path(name);
    await _check();
    await for (final event in Directory(directoryPath).watch()) {
      if (_closing || _closed) return;
      if (event.path == path ||
          event is FileSystemMoveEvent && event.destination == path) {
        yield null;
      }
    }
  }

  @override
  Future<void> deleteFile(String name) => _guard(() async {
    final path = _path(name);
    await _check();
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    await _regular(path);
    await File(path).delete();
  });

  Future<String?> _readMetadataFile(String name) async {
    final path = p.join(directoryPath, name);
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    final stat = await _regular(path);
    _limit(stat.size, _manifestLimit * 2 + 1024);
    final builder = BytesBuilder(copy: false);
    await for (final bytes in File(
      path,
    ).openRead(0, _manifestLimit * 2 + 1025)) {
      builder.add(bytes);
      _limit(builder.length, _manifestLimit * 2 + 1024);
    }
    return utf8.decode(builder.takeBytes());
  }

  @override
  Future<Map<String, dynamic>?> readManifest() => _guard(() async {
    await _check();
    final raw =
        await _readMetadataFile('manifest.json') ??
        await _readMetadataFile('manifest.previous');
    if (raw == null) return null;
    try {
      final envelope = jsonDecode(raw);
      if (envelope is! Map ||
          envelope['version'] != 1 ||
          envelope['id'] != id ||
          envelope['kind'] != kind ||
          envelope['payload'] is! String ||
          envelope['sha256'] is! String) {
        _failure(PrivateStageFailure.invalid);
      }
      final payload = envelope['payload'] as String;
      final bytes = utf8.encode(payload);
      _limit(bytes.length, _manifestLimit);
      if (sha256.convert(bytes).toString() != envelope['sha256']) {
        _failure(PrivateStageFailure.invalid);
      }
      final record = jsonDecode(payload);
      if (record is! Map<String, dynamic>) {
        _failure(PrivateStageFailure.invalid);
      }
      return record;
    } on FormatException {
      _failure(PrivateStageFailure.invalid);
    }
  });

  @override
  Future<void> writeManifest(Map<String, dynamic> manifest) => _guard(() async {
    final payload = jsonEncode(manifest);
    final payloadBytes = utf8.encode(payload);
    _limit(payloadBytes.length, _manifestLimit);
    final bytes = utf8.encode(
      jsonEncode({
        'version': 1,
        'id': id,
        'kind': kind,
        'payload': payload,
        'sha256': sha256.convert(payloadBytes).toString(),
      }),
    );
    await _check();
    final target = File(p.join(directoryPath, 'manifest.json'));
    final previous = File(p.join(directoryPath, 'manifest.previous'));
    final pending = File(
      p.join(directoryPath, '_manifest-${const Uuid().v4()}'),
    );
    for (final file in [target, previous]) {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        _failure(PrivateStageFailure.invalid);
      }
    }
    try {
      await pending.create(exclusive: true);
      await _privateMode(pending.path, 0x180);
      await pending.writeAsBytes(bytes, flush: true);
      await _check();
      if (await target.exists()) {
        await _regular(target.path);
        await target.copy(previous.path);
        await _privateMode(previous.path, 0x180);
      }
      await pending.rename(target.path);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  });

  @override
  Future<void> close() => _closingFuture ??= _close(deleteFiles: false);
  @override
  Future<void> delete() {
    if (_closingFuture != null && !_deleteRequested) {
      return Future.error(
        const PrivateStageException(PrivateStageFailure.unavailable),
      );
    }
    _deleteRequested = true;
    return _closingFuture ??= _close(deleteFiles: true);
  }

  Future<void> _close({required bool deleteFiles}) async {
    _closing = true;
    if (_active > 0) await (_drained ??= Completer<void>()).future;
    try {
      if (deleteFiles) {
        await protectDeletion(() async {
          await _check();
          // The parent mutation lease excludes new opens while Windows needs
          // the child handle closed before removing its containing directory.
          _closed = true;
          _lease.close();
          await beforeDelete?.call();
          await Directory(directoryPath).delete(recursive: true);
        });
      }
    } finally {
      _closed = true;
      _lease.close();
    }
  }
}

class _DigestSink implements Sink<Digest> {
  String? value;
  @override
  void add(Digest data) => value = data.toString();
  @override
  void close() {}
}
