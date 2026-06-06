// lib/services/checksum_service.dart
//
// Utility service for computing MD5 and SHA-256 checksums of files and
// byte buffers.  Uses the `crypto` package which is already a project
// dependency.

import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

/// Result of a checksum verification for a single file.
class ChecksumVerifyResult {
  final String filename;
  final String expected;
  final String actual;
  bool get ok => expected.toLowerCase() == actual.toLowerCase();

  const ChecksumVerifyResult({
    required this.filename,
    required this.expected,
    required this.actual,
  });
}

class ChecksumService {
  /// Compute the MD5 hex digest of [data].
  static String md5Hash(Uint8List data) =>
      crypto.md5.convert(data).toString();

  /// Compute the SHA-256 hex digest of [data].
  static String sha256Hash(Uint8List data) =>
      crypto.sha256.convert(data).toString();

  /// Compute the MD5 hex digest of the file at [path].
  static Future<String> md5File(String path) async {
    final bytes = await File(path).readAsBytes();
    return md5Hash(bytes);
  }

  /// Compute the SHA-256 hex digest of the file at [path].
  static Future<String> sha256File(String path) async {
    final bytes = await File(path).readAsBytes();
    return sha256Hash(bytes);
  }

  // --- MD5 sidecar file generation/verification (md5sum format) ---

  /// Generate a `.md5` sidecar file in [dirPath] for all [filePaths].
  /// Format: `MD5_HASH  filename.ext\n` (standard md5sum output).
  static Future<String> generateMd5File(
    List<String> filePaths,
    String dirPath, {
    String? outputName,
  }) async {
    final buf = StringBuffer();
    for (final path in filePaths) {
      final hash = await md5File(path);
      final name = p.basename(path);
      buf.writeln('$hash  $name');
    }
    final outPath = p.join(dirPath, outputName ?? 'checksums.md5');
    await File(outPath).writeAsString(buf.toString());
    return outPath;
  }

  /// Generate a `.sha256` sidecar file in [dirPath] for all [filePaths].
  static Future<String> generateSha256File(
    List<String> filePaths,
    String dirPath, {
    String? outputName,
  }) async {
    final buf = StringBuffer();
    for (final path in filePaths) {
      final hash = await sha256File(path);
      final name = p.basename(path);
      buf.writeln('$hash  $name');
    }
    final outPath = p.join(dirPath, outputName ?? 'checksums.sha256');
    await File(outPath).writeAsString(buf.toString());
    return outPath;
  }

  /// Verify a `.md5` or `.sha256` sidecar file against the actual files.
  /// [checksumFilePath] is the path to the .md5/.sha256 file.
  /// Returns a list of [ChecksumVerifyResult] for each listed file.
  static Future<List<ChecksumVerifyResult>> verifyChecksumFile(
    String checksumFilePath,
  ) async {
    final dir = p.dirname(checksumFilePath);
    final ext = p.extension(checksumFilePath).toLowerCase();
    final lines = await File(checksumFilePath).readAsLines();
    final results = <ChecksumVerifyResult>[];

    for (final line in lines) {
      if (line.trim().isEmpty || line.startsWith(';') || line.startsWith('#')) {
        continue;
      }
      // md5sum format: "HASH  filename" (two spaces) or "HASH filename"
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final expected = parts[0];
      final filename = parts.sublist(1).join(' ');
      final filePath = p.join(dir, filename.startsWith('*') ? filename.substring(1) : filename);

      String actual;
      try {
        actual = ext == '.sha256' || ext == '.sha1'
            ? await sha256File(filePath)
            : await md5File(filePath);
      } catch (_) {
        actual = '(file not found)';
      }

      results.add(ChecksumVerifyResult(
        filename: filename,
        expected: expected,
        actual: actual,
      ));
    }
    return results;
  }
}
