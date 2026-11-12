import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/archive_endpoint.dart';
import '../models/file_item.dart';
import '../utils/system_links.dart';
import 'archive_service.dart';
import 'archive_viewer_service.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';

/// A complete bounded native namespace, including empty directories and the
/// content of every regular file. Missing names are evidence only after a full
/// successful scan. No unsupported entry is silently excluded.
class ArchiveDirectorySnapshot {
  ArchiveDirectorySnapshot._(
    this.dependency,
    Map<String, ArchiveDirectorySnapshotEntry> entries,
  ) : entries = Map.unmodifiable(entries);

  final ArchivePublicationDirectoryDependency dependency;
  final Map<String, ArchiveDirectorySnapshotEntry> entries;
}

class ArchiveDirectorySnapshotEntry {
  const ArchiveDirectorySnapshotEntry._(
    this.relativePath,
    this.file,
    this.sha256,
    this.mode,
    this._nativeWitness,
  );
  final String relativePath;
  final FileItem file;
  final String? sha256;
  final int? mode;
  final _NativeDirectoryWitness _nativeWitness;
}

const _inactivity = Duration(seconds: 30);
const _deadline = Duration(minutes: 10);
const _maximumEntries = 200000;
const _maximumDepth = 200;
const _maximumNameBytes = 8 * 1024 * 1024;

/// Captures directory contents without following user-controlled links. The
/// digest includes canonical relative paths, types, sizes, UTC time instants,
/// native modes/change times and complete SHA-256 content hashes. Access times
/// are deliberately excluded because reading files can change them.
Future<ArchiveDirectorySnapshot> captureArchiveDirectorySnapshot(
  FileOperationBackend backend,
  String directory, {
  bool Function()? isCancelled,
  void Function(int entries, String path)? onProgress,
  FileItem? forbiddenContainer,
}) async {
  final local = _requireNative(backend);
  final paths = backend.paths;
  if (!paths.isAbsolute(directory) ||
      paths.normalize(directory) != directory ||
      backend.isRootPath(directory) ||
      directory.contains('\u0000') ||
      utf8.encode(directory).length > 16 * 1024) {
    throw StateError('Choose a canonical native source directory.');
  }
  if (forbiddenContainer?.path case final target?) {
    if (backend.samePath(directory, target) ||
        backend.isWithin(directory, target)) {
      throw StateError(
        'The source directory contains the destination archive.',
      );
    }
  }
  final elapsed = Stopwatch()..start();
  void check() {
    if (!backend.isCurrent) throw StateError('The source directory changed.');
    if (isCancelled?.call() ?? false) throw const FileOperationCancelled();
    if (elapsed.elapsed > _deadline) {
      throw TimeoutException('Directory verification exceeded ten minutes.');
    }
  }

  check();
  final root = await backend.stat(directory).timeout(_inactivity);
  check();
  if (root == null || !root.isFolder || root.isSymlink == true) {
    throw StateError('The source is not an available regular directory.');
  }
  final rootWitness = await _nativeWitness(local, root, check);
  final entries = <String, ArchiveDirectorySnapshotEntry>{};
  final physicalPaths = <String>{backend.pathKey(directory)};
  final listings = <String, List<String>>{};
  var totalBytes = 0;
  var nameBytes = 0;

  Future<List<FileItem>> list(String path) async {
    check();
    final children = await backend.list(path).timeout(_inactivity);
    check();
    if (children.length > _maximumEntries) {
      throw StateError('The source directory exceeds 200,000 entries.');
    }
    final keys = <String>{};
    for (final child in children) {
      final name = child.path;
      if (name == null ||
          !paths.isAbsolute(name) ||
          paths.normalize(name) != name ||
          paths.dirname(name) != path ||
          !backend.isWithin(directory, name) ||
          child.name != paths.basename(name) ||
          !keys.add(backend.pathKey(name))) {
        throw StateError('An ambiguous or unsafe source entry was returned.');
      }
      if (child.isSymlink == true ||
          !child.isFolder && (child.size == null || child.size! < 0)) {
        throw UnsupportedError(
          'Directory synchronization requires regular files and directories: $name',
        );
      }
    }
    children.sort((a, b) => a.path!.compareTo(b.path!));
    return children;
  }

  List<String> names(List<FileItem> children) => [
    for (final child in children)
      jsonEncode([child.name, child.isFolder, child.isSymlink == true]),
  ];

  Future<void> walk(String path, int depth) async {
    if (depth > _maximumDepth) {
      throw StateError('The source directory exceeds 200 levels.');
    }
    final children = await list(path);
    listings[path] = names(children);
    for (final child in children) {
      check();
      if (entries.length >= _maximumEntries ||
          !physicalPaths.add(backend.pathKey(child.path!))) {
        throw StateError('The source directory exceeds its namespace bounds.');
      }
      final relative = paths
          .relative(child.path!, from: directory)
          .replaceAll(paths.separator, '/');
      final safe = ArchiveService.safeMemberPath(relative);
      final length = utf8.encode(relative).length;
      nameBytes += length;
      if (safe != relative ||
          entries.containsKey(relative) ||
          length > 4096 ||
          relative.split('/').length > _maximumDepth ||
          nameBytes > _maximumNameBytes) {
        throw StateError(
          'A source name cannot be represented safely in an archive.',
        );
      }
      final captured = _captureFile(child);
      final witness = await _nativeWitness(local, captured, check);
      if (!child.isFolder && forbiddenContainer?.path != null) {
        final identical = await local.service
            .withFileOperationAccess(forbiddenContainer!.path!, () async {
              check();
              return FileSystemEntity.identical(
                child.path!,
                forbiddenContainer.path!,
              ).timeout(_inactivity);
            })
            .timeout(_inactivity);
        check();
        if (identical) {
          throw StateError(
            'The source includes a physical alias of the destination archive.',
          );
        }
      }
      String? hash;
      if (!child.isFolder) {
        totalBytes += child.size!;
        if (child.size! > kArchiveReadLimit ||
            totalBytes > ArchiveService.maxExtractedBytes) {
          throw StateError(
            'Directory synchronization is limited to 64 MiB per file and 256 MiB in total.',
          );
        }
        hash = await _hashFile(local, captured, witness, check);
      }
      entries[relative] = ArchiveDirectorySnapshotEntry._(
        relative,
        captured,
        hash,
        backend.capabilities.permissions ? witness.mode & 0xfff : null,
        witness,
      );
      onProgress?.call(entries.length, relative);
      if (child.isFolder) await walk(child.path!, depth + 1);
    }
  }

  await walk(directory, 0);
  // Re-list every visited directory. Checking only file contents or directory
  // timestamps would miss additions, removals and replaced empty directories.
  for (final listing in listings.entries) {
    final current = names(await list(listing.key));
    if (jsonEncode(current) != jsonEncode(listing.value)) {
      throw StateError(
        'The source directory membership changed while comparing.',
      );
    }
  }
  for (final entry in entries.values) {
    if (await _nativeWitness(local, entry.file, check) !=
        entry._nativeWitness) {
      throw StateError(
        'A source entry changed while comparing: ${entry.relativePath}',
      );
    }
  }
  if (await _nativeWitness(local, root, check) != rootWitness) {
    throw StateError('The source directory changed while comparing.');
  }
  check();
  final ordered = entries.keys.toList()..sort();
  final hashSink = _DirectoryDigestSink();
  final digest = crypto.sha256.startChunkedConversion(hashSink);
  void add(Object value) => digest.add(utf8.encode('${jsonEncode(value)}\n'));
  add(['crisp-directory-snapshot-v1', rootWitness.toJson()]);
  for (final path in ordered) {
    final entry = entries[path]!;
    add([path, entry._nativeWitness.toJson(), entry.sha256]);
  }
  digest.close();
  return ArchiveDirectorySnapshot._(
    ArchivePublicationDirectoryDependency(
      storage: backend.storageReference!,
      directory: _captureFile(root),
      sha256: hashSink.value!.toString(),
      entryCount: entries.length,
      totalBytes: totalBytes,
    ),
    {for (final path in ordered) path: entries[path]!},
  );
}

/// Recovery uses the same native storage authority and fixed bounds as the
/// foreground comparison. A complete tree digest avoids persisting filenames
/// or file contents in the journal while still detecting changed absence.
Future<void> verifyArchiveDirectoryDependency(
  FileOperationBackend backend,
  ArchivePublicationDirectoryDependency dependency, {
  bool Function()? isCancelled,
}) async {
  _requireNative(backend);
  if (backend.storageReference != dependency.storage) {
    throw StateError('Reconnect the exact synchronization source storage.');
  }
  final current = await captureArchiveDirectorySnapshot(
    backend,
    dependency.directory.path!,
    isCancelled: isCancelled,
  );
  if (!_sameFile(dependency.directory, current.dependency.directory) ||
      current.dependency.sha256 != dependency.sha256 ||
      current.dependency.entryCount != dependency.entryCount ||
      current.dependency.totalBytes != dependency.totalBytes) {
    throw StateError(
      'The synchronization source directory changed. Recompare before publishing; recovery files are retained.',
    );
  }
}

/// Reads one selected file under the complete comparison's native and content
/// witnesses. No source path can be substituted by a later plan decision.
Future<Uint8List> readArchiveDirectorySnapshotFile(
  FileOperationBackend backend,
  ArchiveDirectorySnapshotEntry entry, {
  bool Function()? isCancelled,
}) async {
  final local = _requireNative(backend);
  if (entry.file.isFolder || entry.sha256 == null) {
    throw StateError('A selected synchronization source is not a file.');
  }
  void check() {
    if (!backend.isCurrent) {
      throw StateError('The synchronization source changed.');
    }
    if (isCancelled?.call() ?? false) throw const FileOperationCancelled();
  }

  final bytes = BytesBuilder(copy: false);
  final hash = await _hashFile(
    local,
    entry.file,
    entry._nativeWitness,
    check,
    bytes: bytes,
  );
  if (hash != entry.sha256) {
    throw StateError('Selected source content changed: ${entry.relativePath}');
  }
  return bytes.takeBytes();
}

LocalOperationBackend _requireNative(FileOperationBackend backend) {
  if (kIsWeb ||
      backend is! LocalOperationBackend ||
      !backend.storageReference.persistent ||
      !backend.canRecover) {
    throw UnsupportedError(
      'Directory synchronization requires native local storage.',
    );
  }
  return backend;
}

Future<_NativeDirectoryWitness> _nativeWitness(
  LocalOperationBackend backend,
  FileItem expected,
  void Function() check,
) => backend.service
    .withFileOperationAccess(expected.path!, () async {
      check();
      var parent = backend.paths.dirname(expected.path!);
      while (true) {
        if (entityTypeTrustingSystemLinksSync(parent) !=
            FileSystemEntityType.directory) {
          throw StateError('The synchronization source parent changed.');
        }
        final next = backend.paths.dirname(parent);
        if (next == parent) break;
        parent = next;
      }
      final type = entityTypeTrustingSystemLinksSync(expected.path!);
      if (type !=
          (expected.isFolder
              ? FileSystemEntityType.directory
              : FileSystemEntityType.file)) {
        throw StateError(
          'A synchronization source is no longer a regular entry.',
        );
      }
      final stat = FileStat.statSync(expected.path!);
      if (stat.type != type ||
          !expected.isFolder && stat.size != expected.size ||
          expected.updatedAt != null &&
              !stat.modified.isAtSameMomentAs(expected.updatedAt!)) {
        throw StateError('A synchronization source snapshot changed.');
      }
      check();
      return _NativeDirectoryWitness(
        expected.isFolder,
        expected.isFolder ? 0 : stat.size,
        stat.modified.toUtc().microsecondsSinceEpoch,
        stat.changed.toUtc().microsecondsSinceEpoch,
        stat.mode,
      );
    })
    .timeout(_inactivity);

Future<String> _hashFile(
  LocalOperationBackend backend,
  FileItem file,
  _NativeDirectoryWitness witness,
  void Function() check, {
  BytesBuilder? bytes,
}) async {
  check();
  if (file.size == null || file.size! < 0 || file.size! > kArchiveReadLimit) {
    throw StateError('A synchronization source exceeds the member limit.');
  }
  if (await _nativeWitness(backend, file, check) != witness) {
    throw StateError('A synchronization source identity changed.');
  }
  var count = 0;
  final elapsed = Stopwatch()..start();
  final hash = await crypto.sha256
      .bind(
        backend.readFile(file).timeout(_inactivity).map((chunk) {
          check();
          count += chunk.length;
          if (count > file.size! ||
              count > kArchiveReadLimit ||
              elapsed.elapsed > _deadline) {
            throw StateError(
              'A synchronization source changed or exceeded its limits.',
            );
          }
          if (bytes != null) bytes.add(Uint8List.fromList(chunk));
          return chunk;
        }),
      )
      .first;
  check();
  if (count != file.size ||
      await _nativeWitness(backend, file, check) != witness) {
    throw StateError('A synchronization source changed while reading.');
  }
  return hash.toString();
}

class _NativeDirectoryWitness {
  const _NativeDirectoryWitness(
    this.directory,
    this.size,
    this.modified,
    this.changed,
    this.mode,
  );
  final bool directory;
  final int size;
  final int modified;
  final int changed;
  final int mode;
  List<Object> toJson() => [directory, size, modified, changed, mode];
  @override
  bool operator ==(Object other) =>
      other is _NativeDirectoryWitness &&
      directory == other.directory &&
      size == other.size &&
      modified == other.modified &&
      changed == other.changed &&
      mode == other.mode;
  @override
  int get hashCode => Object.hash(directory, size, modified, changed, mode);
}

FileItem _captureFile(FileItem file) => file.copyWith(
  metadata: file.metadata == null
      ? null
      : Map.unmodifiable(Map<String, dynamic>.of(file.metadata!)),
);

bool _sameFile(FileItem a, FileItem b) =>
    a.path == b.path &&
    a.isFolder == b.isFolder &&
    a.isSymlink != true &&
    b.isSymlink != true &&
    a.uuid == b.uuid &&
    a.size == b.size &&
    (a.updatedAt == null
        ? b.updatedAt == null
        : b.updatedAt != null && a.updatedAt!.isAtSameMomentAs(b.updatedAt!));

class _DirectoryDigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) => value = data;
  @override
  void close() {}
}
