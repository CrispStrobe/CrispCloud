// lib/services/file_split_service.dart
//
// Split large files into parts and combine them back.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

class FileSplitService {
  /// Split a file into chunks of [chunkSizeBytes].
  /// Returns the list of created part file paths.
  static Future<List<String>> splitFile(
    String sourcePath,
    String targetDir, {
    required int chunkSizeBytes,
    void Function(int bytesWritten, int totalBytes)? onProgress,
  }) async {
    if (kIsWeb) throw UnsupportedError('File split not supported on Web');
    if (chunkSizeBytes <= 0) throw ArgumentError('chunkSizeBytes must be positive');

    final sourceFile = File(sourcePath);
    final totalBytes = await sourceFile.length();
    final baseName = p.basename(sourcePath);
    final parts = <String>[];
    int partIndex = 1;
    int bytesWritten = 0;

    final input = sourceFile.openRead();
    List<int> buffer = [];

    await for (final chunk in input) {
      buffer.addAll(chunk);

      while (buffer.length >= chunkSizeBytes) {
        final partName = '$baseName.part${partIndex.toString().padLeft(3, '0')}';
        final partPath = p.join(targetDir, partName);
        await File(partPath).writeAsBytes(
          Uint8List.fromList(buffer.sublist(0, chunkSizeBytes)),
        );
        parts.add(partPath);
        buffer = buffer.sublist(chunkSizeBytes);
        bytesWritten += chunkSizeBytes;
        onProgress?.call(bytesWritten, totalBytes);
        partIndex++;
      }
    }

    // Write remaining bytes
    if (buffer.isNotEmpty) {
      final partName = '$baseName.part${partIndex.toString().padLeft(3, '0')}';
      final partPath = p.join(targetDir, partName);
      await File(partPath).writeAsBytes(Uint8List.fromList(buffer));
      parts.add(partPath);
      bytesWritten += buffer.length;
      onProgress?.call(bytesWritten, totalBytes);
    }

    return parts;
  }

  /// Combine part files back into a single file.
  static Future<String> combineFiles(
    List<String> partPaths,
    String outputPath, {
    void Function(int partsDone, int totalParts)? onProgress,
  }) async {
    if (kIsWeb) throw UnsupportedError('File combine not supported on Web');

    final output = File(outputPath).openWrite();
    try {
      for (var i = 0; i < partPaths.length; i++) {
        final bytes = await File(partPaths[i]).readAsBytes();
        output.add(bytes);
        onProgress?.call(i + 1, partPaths.length);
      }
    } finally {
      await output.flush();
      await output.close();
    }

    return outputPath;
  }

  /// Detect split-file parts in a directory matching the pattern `baseName.partNNN`.
  static List<String> detectParts(String dirPath, String baseName) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];

    final pattern = RegExp(
      '^${RegExp.escape(baseName)}\\.part(\\d{3})\$',
      caseSensitive: false,
    );

    final parts = <MapEntry<int, String>>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final match = pattern.firstMatch(name);
      if (match != null) {
        parts.add(MapEntry(int.parse(match.group(1)!), entity.path));
      }
    }

    parts.sort((a, b) => a.key.compareTo(b.key));
    return parts.map((e) => e.value).toList();
  }
}
