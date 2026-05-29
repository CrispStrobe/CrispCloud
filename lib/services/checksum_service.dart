// lib/services/checksum_service.dart
//
// Utility service for computing MD5 and SHA-256 checksums of files and
// byte buffers.  Uses the `crypto` package which is already a project
// dependency.

import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

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
}
