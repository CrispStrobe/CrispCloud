// lib/services/archive_service.dart
//
// Archive operations: streamed, verified native extraction and bounded
// compatibility helpers for archive bytes and previews.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'archive_viewer_service.dart';
import 'archive_viewer_file.dart';
import 'archive_format_registry.dart';
import 'archive_member_index.dart';
import 'file_operation_backend.dart';
import 'local_file_service.dart';
import '../utils/system_links.dart';

class ArchiveService {
  static const maxArchiveBytes = 256 * 1024 * 1024;
  static const maxExtractedBytes = 256 * 1024 * 1024;

  /// Compatibility entry point; dispatches by actual archive format.
  static Future<List<String>> extractZip(
    String archivePath,
    String targetDir,
  ) => extractArchive(archivePath, targetDir);

  static Future<List<String>> extractZipBytes(
    Uint8List bytes,
    String targetDir,
  ) => extractArchiveBytes('archive.zip', bytes, targetDir);

  static Future<List<String>> extractArchive(
    String archivePath,
    String targetDir, {
    bool overwrite = false,
    String? password,
    Set<String>? selectedPaths,
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Extract to disk is unavailable on Web.');
    }
    if (isCancelled?.call() ?? false) return [];
    final sourcePath = p.normalize(p.absolute(archivePath));
    final root = p.normalize(p.absolute(targetDir));
    final local = LocalFileService();
    return local.withFileOperationAccess(sourcePath, () async {
      final file = File(sourcePath);
      final source = await file.stat();
      if (await FileSystemEntity.type(sourcePath, followLinks: false) !=
              FileSystemEntityType.file ||
          source.type != FileSystemEntityType.file) {
        throw const ArchiveViewException(
          'Extraction requires a regular archive file.',
        );
      }
      if (source.size > kArchiveStreamingLimit) {
        throw const ArchiveViewException(
          'Archive exceeds the 8 GiB native input limit.',
        );
      }
      late final ViewerArchive archive;
      try {
        archive = await openViewerArchiveFile(
          sourcePath,
          name: archivePath,
          password: password,
          streaming: true,
          isCancelled: isCancelled,
        );
      } catch (_) {
        if (isCancelled?.call() ?? false) return <String>[];
        rethrow;
      }
      try {
        final streaming = archive.maxStreamingMemberBytes > kArchiveReadLimit;
        if (!streaming && source.size > maxArchiveBytes) {
          throw const ArchiveViewException(
            'This archive profile exceeds the 256 MiB input limit.',
          );
        }
        Future<void> checkSource() async {
          final latest = await file.stat();
          if (await FileSystemEntity.type(sourcePath, followLinks: false) !=
                  FileSystemEntityType.file ||
              latest.type != source.type ||
              latest.size != source.size ||
              latest.modified != source.modified ||
              latest.changed != source.changed) {
            throw const ArchiveViewException(
              'The source archive changed during extraction.',
            );
          }
        }

        return await local.withFileOperationAccess(
          root,
          () => _extractOpened(
            archive,
            root,
            local: local,
            maxTotalBytes: streaming
                ? archive.maxStreamingMemberBytes
                : maxExtractedBytes,
            overwrite: overwrite,
            selectedPaths: selectedPaths,
            isCancelled: isCancelled,
            onProgress: onProgress,
            sourcePath: sourcePath,
            checkSource: checkSource,
          ),
        );
      } finally {
        await archive.close();
      }
    });
  }

  /// Validate every selected path before writing anything. Never follow links
  /// in the archive or destination, and never overwrite without an opt-in.
  static Future<List<String>> extractArchiveBytes(
    String archiveName,
    Uint8List bytes,
    String targetDir, {
    bool overwrite = false,
    String? password,
    Set<String>? selectedPaths,
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Extract to disk is unavailable on Web.');
    }
    if (bytes.length > maxArchiveBytes) {
      throw const ArchiveViewException(
        'Archive exceeds the 256 MiB input limit.',
      );
    }
    final archive = await openViewerArchive(
      bytes,
      name: archiveName,
      password: password,
    );
    try {
      final root = p.normalize(p.absolute(targetDir));
      final local = LocalFileService();
      return await local.withFileOperationAccess(
        root,
        () => _extractOpened(
          archive,
          root,
          local: local,
          maxTotalBytes: maxExtractedBytes,
          overwrite: overwrite,
          selectedPaths: selectedPaths,
          isCancelled: isCancelled,
          onProgress: onProgress,
        ),
      );
    } finally {
      await archive.close();
    }
  }

  /// All selected destinations are checked before any directory is created.
  /// Each file is decoded into a private sibling, checked again from disk, and
  /// only then published. A cancelled operation returns completed files; its
  /// active stage is discarded by the backend without replacing a destination.
  static Future<List<String>> _extractOpened(
    ViewerArchive archive,
    String root, {
    required LocalFileService local,
    required int maxTotalBytes,
    required bool overwrite,
    Set<String>? selectedPaths,
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
    String? sourcePath,
    Future<void> Function()? checkSource,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() ?? false) {
        throw const _ArchiveExtractionCancelled();
      }
    }

    final backend = LocalOperationBackend(
      local,
      isCurrent: () => !(isCancelled?.call() ?? false),
    );
    final extracted = <String>[];
    try {
      checkCancelled();
      final selection = selectedPaths?.map(safeMemberPath).toSet();
      final selected = <({ViewerArchiveMember member, String destination})>[];
      final names = <String, bool>{};
      var totalBytes = 0;
      for (final entry in archive.members) {
        checkCancelled();
        final candidate = entry.name
            .replaceAll('\\', '/')
            .split('/')
            .where((part) => part.isNotEmpty && part != '.')
            .join('/');
        if (selection != null &&
            !selection.any(
              (path) => candidate == path || candidate.startsWith('$path/'),
            )) {
          continue;
        }
        if (entry.pathEscapedRoot || entry.isSpecial) {
          throw ArchiveViewException('Unsafe archive entry: ${entry.name}');
        }
        final relative = safeMemberPath(entry.name);
        final destination = p.joinAll([root, ...relative.split('/')]);
        final key = backend.pathKey(destination);
        if (sourcePath != null && key == backend.pathKey(sourcePath)) {
          throw const ArchiveViewException(
            'Extraction cannot replace its source archive.',
          );
        }
        if (names.containsKey(key)) {
          throw ArchiveViewException(
            'Duplicate archive destination: ${entry.name}',
          );
        }
        names[key] = entry.isFile;
        if (entry.size < 0 ||
            !entry.isFile && entry.size != 0 ||
            entry.isFile && entry.size > archive.maxStreamingMemberBytes) {
          throw ArchiveViewException(
            'Archive entry exceeds the supported extraction limit: ${entry.name}',
          );
        }
        totalBytes += entry.isFile ? entry.size : 0;
        if (totalBytes > maxTotalBytes) {
          throw ArchiveViewException(
            'Extraction exceeds the ${maxTotalBytes ~/ (1024 * 1024)} MiB total limit.',
          );
        }
        selected.add((member: entry, destination: destination));
      }
      for (final target in selected) {
        checkCancelled();
        var ancestor = p.dirname(target.destination);
        while (p.isWithin(root, ancestor)) {
          if (names[backend.pathKey(ancestor)] == true) {
            throw ArchiveViewException(
              'A file occupies an archive directory: ${target.member.name}',
            );
          }
          ancestor = p.dirname(ancestor);
        }
        await _checkDestination(
          root,
          target.destination,
          isFile: target.member.isFile,
          overwrite: overwrite,
        );
      }
      await checkSource?.call();
      var completed = 0;
      for (final target in selected) {
        checkCancelled();
        await checkSource?.call();
        final entry = target.member;
        final destination = target.destination;
        await _checkDestination(
          root,
          destination,
          isFile: entry.isFile,
          overwrite: overwrite,
        );
        await _ensureExtractionDirectory(
          entry.isFile ? p.dirname(destination) : destination,
          backend,
          checkCancelled,
        );
        if (entry.isFile) {
          await _writeExtractedMember(
            archive,
            entry,
            root,
            destination,
            backend,
            overwrite: overwrite,
            checkCancelled: checkCancelled,
            checkSource: checkSource,
          );
          extracted.add(destination);
        }
        onProgress?.call(++completed, selected.length);
      }
      return extracted;
    } on _ArchiveExtractionCancelled {
      return extracted;
    } catch (_) {
      // Backend streams independently observe the same cancellation callback.
      if (isCancelled?.call() ?? false) return extracted;
      rethrow;
    }
  }

  static Future<void> _writeExtractedMember(
    ViewerArchive archive,
    ViewerArchiveMember entry,
    String root,
    String destination,
    LocalOperationBackend backend, {
    required bool overwrite,
    required void Function() checkCancelled,
    Future<void> Function()? checkSource,
  }) async {
    Digest? sourceDigest;
    var sourceVerified = false;
    Stream<List<int>> decoded() async* {
      final digest = _ArchiveExtractionDigest();
      final hash = sha256.startChunkedConversion(digest);
      var closed = false;
      try {
        await for (final chunk in archive.openMember(
          entry,
          maxBytes: archive.maxStreamingMemberBytes,
          chunkSize: 256 * 1024,
        )) {
          checkCancelled();
          hash.add(chunk);
          yield chunk;
        }
        // Reaching a decoder's natural EOF is required: its CRC/length check
        // may reject a stream after its last data chunk has been emitted.
        checkCancelled();
        hash.close();
        closed = true;
        sourceDigest = digest.value;
        sourceVerified = sourceDigest != null;
      } finally {
        if (!closed) hash.close();
      }
    }

    await backend.writePreparedFile(
      destination,
      decoded(),
      entry.size,
      replace: overwrite,
      verifyStaged: (staged) async {
        checkCancelled();
        if (!sourceVerified || staged.size != entry.size) {
          throw const ArchiveViewException(
            'The extracted member did not finish verification.',
          );
        }
        var received = 0;
        final actual = await sha256
            .bind(
              backend.readFile(staged).map((chunk) {
                checkCancelled();
                received += chunk.length;
                if (received > entry.size) {
                  throw const ArchiveViewException(
                    'The staged extracted file changed size.',
                  );
                }
                return chunk;
              }),
            )
            .single;
        checkCancelled();
        if (received != entry.size || actual != sourceDigest) {
          throw const ArchiveViewException(
            'The staged extracted file does not match its decoded source.',
          );
        }
      },
      checkpoint: (state) async {
        // A completed rename is already a published file. Cancellation takes
        // effect before the next member, not after this file is committed.
        if (state['phase'] == 'committed') return;
        checkCancelled();
        if (state['phase'] == 'committing') {
          await _checkDestination(
            root,
            destination,
            isFile: true,
            overwrite: overwrite,
          );
          await checkSource?.call();
          checkCancelled();
        }
      },
    );
  }

  static Future<void> _ensureExtractionDirectory(
    String directory,
    LocalOperationBackend backend,
    void Function() checkCancelled,
  ) async {
    final missing = <String>[];
    var cursor = directory;
    while (true) {
      checkCancelled();
      final type = await entityTypeTrustingSystemLinks(cursor);
      if (type == FileSystemEntityType.notFound) {
        missing.add(cursor);
      } else if (type != FileSystemEntityType.directory) {
        throw ArchiveViewException(
          'Extraction parent is not a regular directory: $cursor',
        );
      }
      final parent = p.dirname(cursor);
      if (parent == cursor) break;
      cursor = parent;
    }
    for (final path in missing.reversed) {
      checkCancelled();
      // Recheck the complete ancestor chain before each directory creation.
      var ancestor = p.dirname(path);
      while (true) {
        if (await entityTypeTrustingSystemLinks(ancestor) !=
            FileSystemEntityType.directory) {
          throw ArchiveViewException('Extraction parent changed: $ancestor');
        }
        final parent = p.dirname(ancestor);
        if (parent == ancestor) break;
        ancestor = parent;
      }
      if (await entityTypeTrustingSystemLinks(path) ==
          FileSystemEntityType.link) {
        throw ArchiveViewException('Extraction will not follow a link: $path');
      }
      checkCancelled();
      await backend.createDirectory(path);
    }
  }

  static String safeMemberPath(String name) {
    final path = name.replaceAll('\\', '/');
    final parts = path
        .split('/')
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    if (path.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(path) ||
        path.contains('\u0000') ||
        parts.isEmpty ||
        parts.contains('..') ||
        parts.any((part) => part.contains(':'))) {
      throw ArchiveViewException('Unsafe archive path: $name');
    }
    return parts.join('/');
  }

  static Future<void> _checkDestination(
    String root,
    String destination, {
    required bool isFile,
    required bool overwrite,
  }) async {
    if (!p.isWithin(root, destination)) {
      throw ArchiveViewException(
        'Extraction path leaves its destination: $destination',
      );
    }
    var cursor = destination;
    while (true) {
      final type = await entityTypeTrustingSystemLinks(cursor);
      if (type == FileSystemEntityType.link) {
        throw ArchiveViewException(
          'Extraction will not follow a symbolic link: $cursor',
        );
      }
      if (cursor == destination) {
        if (isFile &&
            type != FileSystemEntityType.notFound &&
            (!overwrite || type != FileSystemEntityType.file)) {
          throw ArchiveViewException('Destination exists: $destination');
        }
        if (!isFile &&
            type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory) {
          throw ArchiveViewException(
            'Directory conflicts with a file: $destination',
          );
        }
      } else if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw ArchiveViewException(
          'Destination parent is not a directory: $cursor',
        );
      }
      final parent = p.dirname(cursor);
      if (parent == cursor) break;
      cursor = parent;
    }
  }

  /// Pack files and directories, preserving empty directories and never
  /// following symbolic links. Duplicate/nested selections are included once.
  static Future<Uint8List> createZip(
    List<String> filePaths, {
    String? basePath,
  }) async {
    if (kIsWeb) throw UnsupportedError('Archive creation not supported on Web');
    final archive = Archive();
    final seen = <String>{};
    var totalBytes = 0;
    Future<void> add(String source, String name) async {
      name = safeMemberPath(name);
      if (!seen.add(name)) return;
      final type = await FileSystemEntity.type(source, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw ArchiveViewException(
          'Packing symbolic links is not supported: $source',
        );
      }
      if (type == FileSystemEntityType.directory) {
        archive.addFile(ArchiveFile.directory('$name/'));
        final children = await Directory(source)
            .list(followLinks: false)
            .toList();
        children.sort((a, b) => a.path.compareTo(b.path));
        for (final child in children) {
          await add(child.path, '$name/${p.basename(child.path)}');
        }
      } else if (type == FileSystemEntityType.file) {
        final file = File(source);
        final stat = await file.stat();
        totalBytes += stat.size;
        if (stat.size > kArchiveReadLimit || totalBytes > maxExtractedBytes) {
          throw const ArchiveViewException(
            'Packing exceeds the supported size limit.',
          );
        }
        final bytes = await file.readAsBytes();
        archive.addFile(
          ArchiveFile(name, bytes.length, bytes)
            ..lastModTime = stat.modified.millisecondsSinceEpoch ~/ 1000,
        );
      } else {
        throw ArchiveViewException('Not a regular file or directory: $source');
      }
    }

    for (final source in filePaths) {
      await add(
        source,
        basePath == null
            ? p.basename(source)
            : p.relative(source, from: basePath).replaceAll(p.separator, '/'),
      );
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static Future<Uint8List> createZipFromDirectory(String dirPath) async {
    final children = await Directory(dirPath).list(followLinks: false).toList();
    return createZip(
      children.map((child) => child.path).toList(),
      basePath: dirPath,
    );
  }

  /// Whether a file can be offered to an archive reader; bytes are validated
  /// when it is opened, independently from this filename hint.
  static bool isArchive(String filename) => isArchiveFilename(filename);

  /// Native common formats use the streamed readers; previews remain bounded.
  static Future<List<FileItem>> listArchiveContents(
    String archivePath,
    String innerPath,
  ) async {
    if (kIsWeb) {
      throw UnsupportedError('Use listArchiveContentsFromBytes on Web');
    }
    final archive = await openViewerArchiveFile(
      archivePath,
      name: archivePath,
      streaming: true,
    );
    try {
      return ArchiveMemberIndex(archive).list(innerPath);
    } finally {
      await archive.close();
    }
  }

  static Future<List<FileItem>> listArchiveContentsFromBytes(
    String archiveName,
    Uint8List archiveBytes,
    String innerPath,
  ) async {
    final archive = await openViewerArchive(archiveBytes, name: archiveName);
    try {
      return ArchiveMemberIndex(archive).list(innerPath);
    } finally {
      await archive.close();
    }
  }

  /// Read one regular member without extracting an entire disk image.
  static Future<Uint8List?> extractArchiveEntry(
    String archivePath,
    String entryPath,
  ) async {
    if (kIsWeb) {
      throw UnsupportedError('Use extractArchiveEntryFromBytes on Web');
    }
    final archive = await openViewerArchiveFile(archivePath, name: archivePath);
    try {
      return await _readEntry(archive, entryPath);
    } finally {
      await archive.close();
    }
  }

  static Future<Uint8List?> extractArchiveEntryFromBytes(
    String archiveName,
    Uint8List archiveBytes,
    String entryPath,
  ) async {
    final archive = await openViewerArchive(archiveBytes, name: archiveName);
    try {
      return await _readEntry(archive, entryPath);
    } finally {
      await archive.close();
    }
  }

  static Future<Uint8List?> _readEntry(
    ViewerArchive archive,
    String path,
  ) async {
    final index = ArchiveMemberIndex(archive);
    final member = index.members[safeMemberPath(path)];
    return member == null || !member.isFile ? null : archive.readMember(member);
  }
}

class _ArchiveExtractionCancelled implements Exception {
  const _ArchiveExtractionCancelled();
}

class _ArchiveExtractionDigest implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
