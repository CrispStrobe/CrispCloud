// lib/services/archive_service.dart
//
// Archive operations: extract and create .zip files.
// Uses package:archive for codec support.

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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
    final ext = filename.split('.').last.toLowerCase();
    return ext == 'zip';
  }
}
