import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'archive_member_index.dart';
import 'archive_service.dart';
import 'archive_viewer_file.dart';
import 'archive_viewer_service.dart';
import 'file_operation_service.dart';
import 'viewer_spool.dart';

/// Native archive input is copied to an owned, bounded temporary file, then
/// opened through random access. Browsers retain a bounded in-memory snapshot.
const kArchiveBrowseInputLimit = 2 * 1024 * 1024 * 1024;
const kArchiveNestingLimit = 8;

class ArchiveBrowserSession {
  ArchiveBrowserSession._(
    this.source,
    this.file,
    this.archive,
    this.index,
    this._spool,
    this.fingerprint,
  );

  final FileOperationBackend source;
  final FileItem file;
  final ViewerArchive archive;
  final ArchiveMemberIndex index;
  final ViewerSpool? _spool;
  final String fingerprint;
  bool _closed = false;

  bool get isCurrent => !_closed && source.isCurrent;

  /// The owned disk snapshot, useful for diagnostics and cleanup verification.
  String? get temporaryPath => _spool?.path;

  static Future<ArchiveBrowserSession> open(
    FileOperationBackend source,
    FileItem file, {
    int maxInputBytes = kArchiveBrowseInputLimit,
    bool spoolToDisk = !kIsWeb,
    bool Function()? isCancelled,
  }) async {
    if (maxInputBytes <= 0) {
      throw ArgumentError.value(maxInputBytes, 'maxInputBytes');
    }
    void check() {
      if (!source.isCurrent) throw StateError('The archive source changed.');
      if (isCancelled?.call() ?? false) {
        throw StateError('Archive opening cancelled.');
      }
    }

    check();
    if (file.path == null || file.isFolder || file.isSymlink == true) {
      throw const ArchiveViewException('Choose a regular archive file.');
    }
    final captured = await source.stat(file.path!);
    check();
    if (captured == null ||
        captured.isFolder ||
        captured.isSymlink == true ||
        (file.uuid != null && file.uuid != captured.uuid)) {
      throw const ArchiveViewException(
        'The selected archive was replaced or removed.',
      );
    }
    final limit = spoolToDisk
        ? maxInputBytes
        : (maxInputBytes < ArchiveService.maxArchiveBytes
              ? maxInputBytes
              : ArchiveService.maxArchiveBytes);
    if ((captured.size ?? 0) > limit) {
      throw ArchiveViewException(
        'Archive input exceeds the ${limit ~/ (1024 * 1024)} MiB limit.',
      );
    }
    ViewerSpool? spool;
    ViewerArchive? archive;
    final input = _HashingArchiveBackend(source);
    try {
      if (spoolToDisk) {
        spool = await createViewerSpool(
          input,
          captured,
          maxBytes: limit,
          isCancelled: isCancelled,
        );
        check();
        archive = await openViewerArchiveFile(spool.path, name: captured.name);
      } else {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in input.readFile(captured)) {
          check();
          if (builder.length + chunk.length > limit) {
            throw ArchiveViewException(
              'Archive input exceeds the ${limit ~/ (1024 * 1024)} MiB limit.',
            );
          }
          builder.add(chunk);
        }
        check();
        if (captured.size != null && builder.length != captured.size) {
          throw const ArchiveViewException(
            'The archive stream ended at an unexpected size.',
          );
        }
        archive = await openViewerArchive(
          builder.takeBytes(),
          name: captured.name,
        );
      }
      check();
      final after = await source.stat(file.path!);
      check();
      if (!_sameSnapshot(captured, after)) {
        throw const ArchiveViewException(
          'The archive changed while it was opening. Reload it.',
        );
      }
      final index = ArchiveMemberIndex(archive);
      return ArchiveBrowserSession._(
        source,
        captured,
        archive,
        index,
        spool,
        input.fingerprint!,
      );
    } catch (_) {
      await archive?.close();
      await spool?.close();
      rethrow;
    }
  }

  static bool _sameSnapshot(FileItem before, FileItem? after) =>
      after != null &&
      !after.isFolder &&
      after.isSymlink != true &&
      before.uuid == after.uuid &&
      before.size == after.size &&
      before.updatedAt == after.updatedAt &&
      const [
        'etag',
        'versionId',
        'revision',
      ].every((key) => before.metadata?[key] == after.metadata?[key]);

  void _check() {
    if (!isCurrent) {
      throw const ArchiveViewException('This archive is no longer open.');
    }
  }

  List<FileItem> list(String path) {
    _check();
    return index.list(path);
  }

  Future<Uint8List> read(
    String path, {
    int maxBytes = kArchiveReadLimit,
  }) async {
    _check();
    final data = await archive.readMember(index.file(path), maxBytes: maxBytes);
    _check();
    return data;
  }

  FileOperationBackend get backend => _ArchiveBrowserBackend(this);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await archive.close();
    } finally {
      await _spool?.close();
    }
  }
}

/// Virtual member paths are resolved exclusively against this archive handle.
/// They never reach the physical backend captured by the enclosing session.
class _ArchiveBrowserBackend extends FileOperationBackend {
  _ArchiveBrowserBackend(this.session);
  final ArchiveBrowserSession session;
  @override
  Object get identity => session;
  @override
  String get label => session.file.name;
  @override
  p.Context get paths => p.posix;
  @override
  bool get isCurrent => session.isCurrent;
  String _relative(String path) => path.replaceFirst(RegExp(r'^/'), '');
  @override
  Future<List<FileItem>> list(String path) async => session
      .list(_relative(path))
      .map(
        (file) => file.copyWith(
          path: '/${file.path!.replaceAll(RegExp(r'/+$'), '')}',
        ),
      )
      .toList();
  @override
  Future<FileItem?> stat(String path) async {
    session._check();
    if (path == '/') return FileItem(name: '/', path: '/', isFolder: true);
    final relative = ArchiveService.safeMemberPath(_relative(path));
    final member = session.index.members[relative];
    if (member == null) return null;
    return FileItem(
      name: p.posix.basename(relative),
      path: '/$relative',
      isFolder: !member.isFile,
      size: member.size,
      updatedAt: member.modified,
    );
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    yield await session.read(_relative(file.path!));
  }

  @override
  Future<void> createDirectory(String path) async =>
      throw UnsupportedError('Use the archive workspace to change members.');
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async =>
      throw UnsupportedError('Use the archive workspace to change members.');
  @override
  Future<void> deleteFile(FileItem file) async =>
      throw UnsupportedError('Use the archive workspace to change members.');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('Use the archive workspace to change members.');
}

/// A captured route from a physical archive into nested members. Only [file]
/// belongs to physical storage; [nestedMembers] are validated archive paths.
class ArchiveWorkspaceLocation {
  const ArchiveWorkspaceLocation({
    required this.file,
    required this.nestedMembers,
    required this.isCurrent,
    required this.fingerprint,
  });
  final FileItem file;
  final List<String> nestedMembers;
  final bool Function() isCurrent;
  final String fingerprint;
}

/// Hashes the same stream that creates the immutable browsing snapshot, so a
/// later workspace can refuse a changed outer container before acting on an
/// automatically selected nested member.
class _HashingArchiveBackend extends FileOperationBackend {
  _HashingArchiveBackend(this.source);
  final FileOperationBackend source;
  String? fingerprint;
  @override
  Object get identity => source.identity;
  @override
  String get label => source.label;
  @override
  p.Context get paths => source.paths;
  @override
  bool get isCurrent => source.isCurrent;
  @override
  Future<FileItem?> stat(String path) => source.stat(path);
  @override
  Future<List<FileItem>> list(String path) => source.list(path);
  @override
  Stream<List<int>> readFile(FileItem file) async* {
    final digest = _ArchiveDigestSink();
    final hash = sha256.startChunkedConversion(digest);
    var finished = false;
    try {
      await for (final chunk in source.readFile(file)) {
        hash.add(chunk);
        yield chunk;
      }
      finished = true;
    } finally {
      hash.close();
      if (finished) fingerprint = digest.value!.toString();
    }
  }

  @override
  Future<void> createDirectory(String path) async =>
      throw UnsupportedError('Archive snapshot is read-only.');
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async => throw UnsupportedError('Archive snapshot is read-only.');
  @override
  Future<void> deleteFile(FileItem file) async =>
      throw UnsupportedError('Archive snapshot is read-only.');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('Archive snapshot is read-only.');
}

class _ArchiveDigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
