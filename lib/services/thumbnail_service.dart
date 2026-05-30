// lib/services/thumbnail_service.dart
//
// Thumbnail generation and caching for image files.
// Generates thumbnails in the background, caches on disk.
//
// Supports: JPEG, PNG, WebP, GIF, BMP
// Thumbnails are resized to 120x120 max (preserving aspect ratio).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'log_service.dart';

class ThumbnailService {
  static final _log = Log('Thumbnails');

  String? _cacheDir;
  final Map<String, Uint8List> _memoryCache = {};
  static const _maxMemoryCacheEntries = 200;
  static const _thumbnailSize = 120;

  static const _supportedExts = {
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'ico',
  };

  /// Check if a file extension supports thumbnail generation.
  static bool isSupported(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return _supportedExts.contains(ext);
  }

  /// Initialize the thumbnail cache directory.
  Future<void> init() async {
    if (kIsWeb) return;
    final appDir = await getApplicationSupportDirectory();
    _cacheDir = p.join(appDir.path, 'thumbnails');
    final dir = Directory(_cacheDir!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _log.info('Thumbnail cache: $_cacheDir');
  }

  /// Get a thumbnail for a file. Returns cached version or null.
  /// Use [generate] to create one if missing.
  Uint8List? getCached(String key) {
    return _memoryCache[key];
  }

  /// Generate a thumbnail from image bytes.
  /// Returns the resized image bytes (PNG format), or null if generation fails.
  /// Caches in memory and on disk.
  Future<Uint8List?> generate(String key, Uint8List imageBytes) async {
    // Check memory cache first
    if (_memoryCache.containsKey(key)) return _memoryCache[key];

    // Check disk cache
    if (_cacheDir != null) {
      final diskPath = _diskPath(key);
      final diskFile = File(diskPath);
      if (await diskFile.exists()) {
        final bytes = await diskFile.readAsBytes();
        _addToMemoryCache(key, bytes);
        return bytes;
      }
    }

    // Generate thumbnail in compute isolate
    try {
      final thumbnail = await compute(_generateThumbnail, imageBytes);
      if (thumbnail != null) {
        _addToMemoryCache(key, thumbnail);
        // Save to disk cache (fire-and-forget)
        if (_cacheDir != null) {
          File(_diskPath(key)).writeAsBytes(thumbnail);
        }
      }
      return thumbnail;
    } catch (e) {
      _log.debug('Thumbnail generation failed for $key: $e');
      return null;
    }
  }

  /// Generate thumbnail from provider-supplied thumbnail URL.
  /// Used for GDrive, OneDrive, Dropbox which provide server-side thumbnails.
  Future<void> cacheProviderThumbnail(String key, Uint8List bytes) async {
    _addToMemoryCache(key, bytes);
    if (_cacheDir != null) {
      await File(_diskPath(key)).writeAsBytes(bytes);
    }
  }

  /// Clear all cached thumbnails.
  Future<void> clear() async {
    _memoryCache.clear();
    if (_cacheDir != null) {
      final dir = Directory(_cacheDir!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create();
      }
    }
    _log.info('Thumbnail cache cleared');
  }

  void _addToMemoryCache(String key, Uint8List bytes) {
    // LRU-like: if at capacity, remove oldest entries
    while (_memoryCache.length >= _maxMemoryCacheEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = bytes;
  }

  String _diskPath(String key) {
    final hash = sha1.convert(utf8.encode(key)).toString();
    return p.join(_cacheDir!, '$hash.thumb');
  }

  /// Top-level function for compute isolate — resizes image to thumbnail.
  static Future<Uint8List?> _generateThumbnail(Uint8List imageBytes) async {
    try {
      // Decode the image
      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: _thumbnailSize,
        targetHeight: _thumbnailSize,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // Encode as PNG
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      return byteData.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  /// Create a thumbnail key for a remote file.
  static String remoteKey(String provider, String path) => '$provider:$path';

  /// Create a thumbnail key for a local file.
  static String localKey(String path) => 'local:$path';
}
