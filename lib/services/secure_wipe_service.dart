// lib/services/secure_wipe_service.dart
//
// Multi-pass overwrite before delete for local files.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

class SecureWipeService {
  static const _blockSize = 64 * 1024; // 64 KB blocks

  /// Securely wipe a file by overwriting its contents before deletion.
  ///
  /// Uses a 3-pass scheme by default: random, zeros, random (DoD 5220.22-M).
  /// Set [passes] to 1 for quick wipe or 7 for higher security.
  static Future<void> secureWipe(
    String path, {
    int passes = 3,
    void Function(int currentPass, int totalPasses)? onProgress,
  }) async {
    if (kIsWeb) throw UnsupportedError('Secure wipe not supported on Web');
    if (passes < 1) throw ArgumentError('passes must be >= 1');

    final file = File(path);
    if (!await file.exists()) return;

    final length = await file.length();
    if (length == 0) {
      await file.delete();
      return;
    }

    final random = Random.secure();
    final blocks = (length / _blockSize).ceil();

    for (var pass = 0; pass < passes; pass++) {
      onProgress?.call(pass + 1, passes);

      final raf = await file.open(mode: FileMode.writeOnly);
      try {
        for (var block = 0; block < blocks; block++) {
          final remaining = length - (block * _blockSize);
          final size = remaining < _blockSize ? remaining : _blockSize;

          Uint8List data;
          if (pass % 2 == 1) {
            // Even-numbered passes (0-indexed odd) use zeros
            data = Uint8List(size);
          } else {
            // Odd passes use random data
            data = Uint8List(size);
            for (var i = 0; i < size; i++) {
              data[i] = random.nextInt(256);
            }
          }

          await raf.writeFrom(data);
        }
        await raf.flush();
      } finally {
        await raf.close();
      }
    }

    // Final deletion
    await file.delete();
  }

  /// Securely wipe a directory by wiping all files recursively, then removing.
  static Future<void> secureWipeDirectory(
    String path, {
    int passes = 3,
    void Function(String currentFile, int filesProcessed, int totalFiles)? onProgress,
  }) async {
    if (kIsWeb) throw UnsupportedError('Secure wipe not supported on Web');

    final dir = Directory(path);
    if (!await dir.exists()) return;

    // Collect all files first
    final files = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) files.add(entity);
    }

    for (var i = 0; i < files.length; i++) {
      onProgress?.call(files[i].path, i + 1, files.length);
      await secureWipe(files[i].path, passes: passes);
    }

    // Remove empty directory tree
    await dir.delete(recursive: true);
  }
}
