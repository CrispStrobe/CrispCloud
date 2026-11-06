import 'web_file_failure.dart';
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
    if (kIsWeb)
      throw UnsupportedError('Extract to disk is unavailable on Web.');
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
    if (kIsWeb)
      throw UnsupportedError('Extract to disk is unavailable on Web.');
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
      final type = await FileSystemEntity.type(cursor, followLinks: false);
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

  /// Check if a file is a supported archive format.
  static bool isArchive(String filename) {
    final lower = filename.toLowerCase();
    for (final ext in _supportedExtensions) {
      if (lower.endsWith(ext)) return true;
    }
    return false;
  }

  static const _supportedExtensions = {
    '.zip',
    '.tar',
    '.tar.gz',
    '.tgz',
    '.tar.bz2',
    '.tbz2',
    '.7z',
    '.rar',
    '.tar.xz',
    '.txz',
    '.tar.zst',
    '.tzst',
  };

  /// List the contents of an archive at [innerPath] without extracting.
  /// Returns [FileItem] entries one level deep within [innerPath].
  static Future<List<FileItem>> listArchiveContents(
    String archivePath,
    String innerPath,
  ) async {
    if (kIsWeb)
      throw UnsupportedError('Use listArchiveContentsFromBytes on Web');

    final bytes = await File(archivePath).readAsBytes();
    return listArchiveContentsFromBytes(archivePath, bytes, innerPath);
  }

  /// List archive contents from bytes (works on web and native).
  static List<FileItem> listArchiveContentsFromBytes(
    String archiveName,
    Uint8List archiveBytes,
    String innerPath,
  ) {
    final archive = _decodeArchive(archiveName, archiveBytes);
    if (archive == null) return [];

    // Normalise innerPath to always end with '/' (or empty for root)
    final prefix = innerPath.isNotEmpty && !innerPath.endsWith('/')
        ? '$innerPath/'
        : innerPath;

    // Collect unique entries at exactly one level below prefix
    final folders = <String>{};
    final fileEntries = <String, ArchiveFile>{};

    for (final entry in archive) {
      var name = entry.name;
      // Strip leading './' if present
      if (name.startsWith('./')) name = name.substring(2);
      // Skip entries that don't start with our prefix
      if (!name.startsWith(prefix) && prefix.isNotEmpty) continue;
      // Skip the prefix directory itself
      if (name == prefix || name == innerPath) continue;

      final relative = name.substring(prefix.length);
      // Skip empty
      if (relative.isEmpty) continue;

      final slashIdx = relative.indexOf('/');
      if (slashIdx == -1) {
        // File at this level
        if (entry.isFile) {
          fileEntries[relative] = entry;
        }
      } else {
        // Subdirectory — extract just the folder name
        final folderName = relative.substring(0, slashIdx);
        folders.add(folderName);
      }
    }

    final items = <FileItem>[];

    // Add folders
    for (final folder in folders) {
      items.add(
        FileItem(name: folder, path: '$prefix$folder/', isFolder: true),
      );
    }

    // Add files
    for (final entry in fileEntries.entries) {
      items.add(
        FileItem(
          name: entry.key,
          path: '$prefix${entry.key}',
          isFolder: false,
          size: entry.value.size,
          updatedAt: entry.value.lastModTime > 0
              ? DateTime.fromMillisecondsSinceEpoch(
                  entry.value.lastModTime * 1000,
                )
              : null,
        ),
      );
    }

    return items;
  }

  /// Extract a single entry from an archive by its path within the archive.
  /// Returns the entry's bytes, or null if not found.
  static Future<Uint8List?> extractArchiveEntry(
    String archivePath,
    String entryPath,
  ) async {
    if (kIsWeb)
      throw UnsupportedError('Use extractArchiveEntryFromBytes on Web');

    final bytes = await File(archivePath).readAsBytes();
    return extractArchiveEntryFromBytes(archivePath, bytes, entryPath);
  }

  /// Extract a single entry from archive bytes (works on web and native).
  static Uint8List? extractArchiveEntryFromBytes(
    String archiveName,
    Uint8List archiveBytes,
    String entryPath,
  ) {
    final archive = _decodeArchive(archiveName, archiveBytes);
    if (archive == null) return null;

    for (final entry in archive) {
      var name = entry.name;
      if (name.startsWith('./')) name = name.substring(2);
      if (name == entryPath && entry.isFile) {
        return Uint8List.fromList(entry.content as List<int>);
      }
    }
    return null;
  }

  /// Decode an archive based on its file extension.
  static Archive? _decodeArchive(String path, Uint8List bytes) {
    final lower = path.toLowerCase();
    try {
      if (lower.endsWith('.zip')) {
        return ZipDecoder().decodeBytes(bytes);
      } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
        return TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      } else if (lower.endsWith('.tar.bz2') || lower.endsWith('.tbz2')) {
        return TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));
      } else if (lower.endsWith('.tar')) {
        return TarDecoder().decodeBytes(bytes);
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
