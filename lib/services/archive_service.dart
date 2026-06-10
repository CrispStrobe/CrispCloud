// lib/services/archive_service.dart
//
// Archive operations: extract and create .zip files.
// Uses package:archive for codec support.

import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';

class ArchiveService {
  /// Extract a .zip file to a target directory.
  /// Returns the list of extracted file paths.
  static Future<List<String>> extractZip(String zipPath, String targetDir) async {
    if (kIsWeb) throw UnsupportedError('Archive extraction not supported on Web');

    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final extracted = <String>[];

    for (final file in archive) {
      final outPath = p.join(targetDir, file.name);

      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
        extracted.add(outPath);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    return extracted;
  }

  /// Extract a .zip from bytes (for remote files downloaded to memory).
  static Future<List<String>> extractZipBytes(
      Uint8List zipBytes, String targetDir) async {
    if (kIsWeb) throw UnsupportedError('Archive extraction not supported on Web');

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final extracted = <String>[];

    for (final file in archive) {
      final outPath = p.join(targetDir, file.name);

      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
        extracted.add(outPath);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    return extracted;
  }

  /// Create a .zip file from a list of file paths.
  /// Returns the zip file bytes.
  static Future<Uint8List> createZip(List<String> filePaths,
      {String? basePath}) async {
    if (kIsWeb) throw UnsupportedError('Archive creation not supported on Web');

    final archive = Archive();

    for (final filePath in filePaths) {
      final file = File(filePath);
      if (!await file.exists()) continue;

      final stat = await file.stat();
      final bytes = await file.readAsBytes();

      // Use relative path if basePath is provided
      String archiveName;
      if (basePath != null) {
        archiveName = p.relative(filePath, from: basePath);
      } else {
        archiveName = p.basename(filePath);
      }

      archive.addFile(ArchiveFile(
        archiveName,
        bytes.length,
        bytes,
      )..lastModTime = stat.modified.millisecondsSinceEpoch ~/ 1000);
    }

    final zipBytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipBytes!);
  }

  /// Create a .zip from a directory (recursive).
  static Future<Uint8List> createZipFromDirectory(String dirPath) async {
    if (kIsWeb) throw UnsupportedError('Archive creation not supported on Web');

    final dir = Directory(dirPath);
    final files = await dir
        .list(recursive: true)
        .where((e) => e is File)
        .map((e) => e.path)
        .toList();

    return createZip(files, basePath: dirPath);
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
    '.zip', '.tar', '.tar.gz', '.tgz', '.tar.bz2', '.tbz2',
  };

  /// List the contents of an archive at [innerPath] without extracting.
  /// Returns [FileItem] entries one level deep within [innerPath].
  static Future<List<FileItem>> listArchiveContents(
    String archivePath,
    String innerPath,
  ) async {
    if (kIsWeb) throw UnsupportedError('Use listArchiveContentsFromBytes on Web');

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
      items.add(FileItem(
        name: folder,
        path: '$prefix$folder/',
        isFolder: true,
      ));
    }

    // Add files
    for (final entry in fileEntries.entries) {
      items.add(FileItem(
        name: entry.key,
        path: '$prefix${entry.key}',
        isFolder: false,
        size: entry.value.size,
        updatedAt: entry.value.lastModTime > 0
            ? DateTime.fromMillisecondsSinceEpoch(entry.value.lastModTime * 1000)
            : null,
      ));
    }

    return items;
  }

  /// Extract a single entry from an archive by its path within the archive.
  /// Returns the entry's bytes, or null if not found.
  static Future<Uint8List?> extractArchiveEntry(
    String archivePath,
    String entryPath,
  ) async {
    if (kIsWeb) throw UnsupportedError('Use extractArchiveEntryFromBytes on Web');

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
