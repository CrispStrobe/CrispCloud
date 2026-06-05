// lib/services/dir_size_service.dart
//
// Calculate and cache directory sizes for inline display.

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class DirSizeService {
  final Map<String, int> _cache = {};

  /// Calculate the total size of a directory recursively.
  /// Results are cached; use [invalidate] to clear a specific entry.
  Future<int> calculateSize(
    String path, {
    void Function(int bytesScanned)? onProgress,
  }) async {
    if (kIsWeb) throw UnsupportedError('Dir size not supported on Web');

    // Return cached value if available
    if (_cache.containsKey(path)) return _cache[path]!;

    int totalSize = 0;
    final dir = Directory(path);
    if (!await dir.exists()) return 0;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          totalSize += await entity.length();
          onProgress?.call(totalSize);
        } catch (_) {
          // Skip files we can't read
        }
      }
    }

    _cache[path] = totalSize;
    return totalSize;
  }

  /// Clear the cached size for a specific path.
  void invalidate(String path) {
    _cache.remove(path);
  }

  /// Clear all cached sizes.
  void invalidateAll() {
    _cache.clear();
  }

  /// Get a cached size without triggering calculation.
  int? getCachedSize(String path) => _cache[path];
}
