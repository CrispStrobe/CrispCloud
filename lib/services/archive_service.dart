// lib/services/archive_service.dart
//
// Archive operations: extract and create .zip files.
// Uses package:archive for codec support.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'archive_viewer_service.dart';
import 'archive_viewer_file.dart';
import 'archive_format_registry.dart';
import 'archive_member_index.dart';
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
    final file = File(archivePath);
    if (await file.length() > maxArchiveBytes) {
      throw const ArchiveViewException(
        'Archive exceeds the 256 MiB input limit.',
      );
    }
    return extractArchiveBytes(
      archivePath,
      await file.readAsBytes(),
      targetDir,
      overwrite: overwrite,
      password: password,
      selectedPaths: selectedPaths,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
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
      final selected = archive.members
          .where(
            (entry) =>
                selectedPaths == null ||
                selectedPaths.any(
                  (path) =>
                      entry.name == path ||
                      entry.name.startsWith(
                        '${path.replaceAll(RegExp(r'/+$'), '')}/',
                      ),
                ),
          )
          .toList();
      final paths = <int, String>{};
      final names = <String>{};
      var totalBytes = 0;
      for (final entry in selected) {
        if (entry.pathEscapedRoot || entry.isSpecial) {
          throw ArchiveViewException('Unsafe archive entry: ${entry.name}');
        }
        final relative = safeMemberPath(entry.name);
        final destination = p.joinAll([root, ...relative.split('/')]);
        final key = Platform.isWindows
            ? destination.toLowerCase()
            : destination;
        if (!names.add(key)) {
          throw ArchiveViewException(
            'Duplicate archive destination: ${entry.name}',
          );
        }
        await _checkDestination(
          root,
          destination,
          isFile: entry.isFile,
          overwrite: overwrite,
        );
        totalBytes += entry.isFile ? entry.size : 0;
        if (totalBytes > maxExtractedBytes) {
          throw const ArchiveViewException(
            'Extraction exceeds the 256 MiB total limit.',
          );
        }
        paths[entry.index] = destination;
      }
      final extracted = <String>[];
      var completed = 0;
      for (final entry in selected) {
        if (isCancelled?.call() ?? false) break;
        final destination = paths[entry.index]!;
        await _checkDestination(
          root,
          destination,
          isFile: entry.isFile,
          overwrite: overwrite,
        );
        if (entry.isFile) {
          final content = await archive.readMember(entry);
          if (isCancelled?.call() ?? false) break;
          final file = File(destination);
          await file.parent.create(recursive: true);
          // Create exclusively before writing: existing files require the
          // explicit overwrite choice, including changes after preflight.
          await file.create(exclusive: !overwrite);
          await file.writeAsBytes(content, flush: true);
          extracted.add(destination);
        } else {
          await Directory(destination).create(recursive: true);
        }
        onProgress?.call(++completed, selected.length);
      }
      return extracted;
    } finally {
      await archive.close();
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

  /// List contents through the same bounded readers as pane navigation/F3.
  static Future<List<FileItem>> listArchiveContents(
    String archivePath,
    String innerPath,
  ) async {
    if (kIsWeb) {
      throw UnsupportedError('Use listArchiveContentsFromBytes on Web');
    }
    final archive = await openViewerArchiveFile(archivePath, name: archivePath);
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
