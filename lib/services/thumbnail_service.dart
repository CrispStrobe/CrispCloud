// Image thumbnail generation with bounded memory/disk caches. Platform codecs
// run on the root isolate; only the pure Dart fallback runs in compute.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'gallery_image_decoder.dart';
import 'log_service.dart';

class ThumbnailService {
  ThumbnailService({
    this.maxMemoryCacheEntries = 200,
    this.maxMemoryCacheBytes = 32 * 1024 * 1024,
    this.maxDiskCacheBytes = 256 * 1024 * 1024,
    this.maxDiskCacheEntries = 2000,
  }) : assert(maxMemoryCacheEntries > 0),
       assert(maxMemoryCacheBytes > 0),
       assert(maxDiskCacheBytes > 0),
       assert(maxDiskCacheEntries > 0);

  static const _log = Log('Thumbnails');
  static const defaultSize = 120;
  final int maxMemoryCacheEntries;
  final int maxMemoryCacheBytes;
  final int maxDiskCacheBytes;
  final int maxDiskCacheEntries;
  String? _cacheDir;
  final Map<String, Uint8List> _memoryCache = {};
  final Map<String, Future<Uint8List?>> _inFlight = {};
  Future<void> _diskWrites = Future<void>.value();
  int _memoryBytes = 0;
  int _cacheEpoch = 0;
  int _writesSincePrune = 0;
  int _diskBytes = 0;
  int _diskCount = 0;

  static const _supportedExts = {
    'jpg', 'jpeg', 'jpe', 'png', 'gif', 'bmp', 'webp', 'ico',
    'tif', 'tiff', 'tga', 'psd', 'pnm', 'ppm', 'pgm', 'pbm', 'pvr', 'exr',
    // These are attempted through the platform codec. Unsupported platforms
    // return a placeholder instead of repeatedly downloading the original.
    'heic', 'heif', 'avif',
  };

  static bool isSupported(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot >= 0 && _supportedExts.contains(fileName.substring(dot + 1).toLowerCase());
  }

  Future<void> init({String? cacheDirectory}) async {
    if (kIsWeb) return;
    try {
      _cacheDir = cacheDirectory ??
          p.join((await getApplicationSupportDirectory()).path, 'thumbnails');
      await Directory(_cacheDir!).create(recursive: true);
      await _pruneDisk();
    } catch (error) {
      _cacheDir = null;
      _log.debug('Disk thumbnail cache unavailable: $error');
    }
  }

  static String _sizeKey(String key, int size) =>
      size == defaultSize ? key : '$key:thumbnail-size=$size';

  /// Memory hit also refreshes its LRU position. Callers include account,
  /// path and revision in [key]; size variants cannot alias one another.
  Uint8List? getCached(String key, {int size = defaultSize}) {
    final cacheKey = _sizeKey(key, size);
    final bytes = _memoryCache.remove(cacheKey);
    if (bytes != null) _memoryCache[cacheKey] = bytes;
    return bytes;
  }

  /// Read a cached thumbnail before downloading or opening its source file.
  Future<Uint8List?> readCached(String key, {int size = defaultSize}) async {
    final cached = getCached(key, size: size);
    if (cached != null) return cached;
    if (_cacheDir == null) return null;
    final epoch = _cacheEpoch;
    final cacheKey = _sizeKey(key, size);
    try {
      final file = File(_diskPath(cacheKey));
      if (!await file.exists()) return null;
      // Cache corruption must not turn a thumbnail lookup into a large read.
      if (await file.length() > 16 * 1024 * 1024) {
        await file.delete();
        return null;
      }
      final bytes = await file.readAsBytes();
      if (epoch != _cacheEpoch) return null;
      _addToMemoryCache(cacheKey, bytes);
      return getCached(key, size: size) ?? bytes;
    } catch (_) {
      return null;
    }
  }

  /// Generate the first frame as PNG, preserving aspect ratio and never
  /// enlarging a small source. Concurrent requests for the same key coalesce.
  Future<Uint8List?> generate(
    String key,
    Uint8List imageBytes, {
    int size = defaultSize,
    String fileName = '',
  }) {
    if (size < 1 || size > 2048) throw RangeError.range(size, 1, 2048, 'size');
    final cacheKey = _sizeKey(key, size);
    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;
    final epoch = _cacheEpoch;
    late final Future<Uint8List?> future;
    future = () async {
      try {
        final cached = await readCached(key, size: size);
        if (cached != null) return cached;
        if (imageBytes.length > kGalleryInputLimitBytes) return null;
        var thumbnail = await _generateWithPlatformCodec(imageBytes, size);
        thumbnail ??= (await compute(
          decodeGalleryRaster,
          GalleryDecodeRequest(imageBytes, fileName: fileName, maxSize: size),
        ))?.bytes;
        if (thumbnail != null && epoch == _cacheEpoch) {
          _addToMemoryCache(cacheKey, thumbnail);
          await _queueDiskWrite(cacheKey, thumbnail, epoch);
        }
        return thumbnail;
      } catch (error) {
        _log.debug('Thumbnail decode failed: $error');
        return null;
      } finally {
        if (identical(_inFlight[cacheKey], future)) _inFlight.remove(cacheKey);
      }
    }();
    _inFlight[cacheKey] = future;
    return future;
  }

  Future<void> cacheProviderThumbnail(String key, Uint8List bytes,
      {int size = defaultSize}) async {
    final cacheKey = _sizeKey(key, size);
    _addToMemoryCache(cacheKey, bytes);
    await _queueDiskWrite(cacheKey, bytes, _cacheEpoch);
  }

  List<String> get cachedKeys => _memoryCache.keys.toList(growable: false);
  int get memoryCacheSize => _memoryBytes;

  Future<int> getDiskCacheSize() async {
    if (_cacheDir == null) return 0;
    try {
      var total = 0;
      await for (final entity in Directory(_cacheDir!).list()) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<int> getDiskCacheCount() async {
    if (_cacheDir == null) return 0;
    try {
      return await Directory(_cacheDir!).list().where((e) => e is File).length;
    } catch (_) {
      return 0;
    }
  }

  /// Invalidates in-flight cache writes too. A completed old decode cannot
  /// silently repopulate the cache after the user has cleared it.
  Future<void> clear() async {
    _cacheEpoch++;
    _inFlight.clear();
    _memoryCache.clear();
    _memoryBytes = 0;
    await _diskWrites;
    if (_cacheDir != null) {
      try {
        final dir = Directory(_cacheDir!);
        if (await dir.exists()) await dir.delete(recursive: true);
        await dir.create(recursive: true);
        _diskBytes = 0;
        _diskCount = 0;
      } catch (error) {
        _log.debug('Thumbnail cache clear failed: $error');
      }
    }
  }

  Future<void> invalidate(String key, {int size = defaultSize}) async {
    final cacheKey = _sizeKey(key, size);
    final bytes = _memoryCache.remove(cacheKey);
    if (bytes != null) _memoryBytes -= bytes.length;
    await _diskWrites;
    if (_cacheDir == null) return;
    try {
      final file = File(_diskPath(cacheKey));
      if (await file.exists()) {
        final length = await file.length();
        await file.delete();
        _diskBytes = math.max(0, _diskBytes - length);
        _diskCount = math.max(0, _diskCount - 1);
      }
    } catch (_) {
      // A missing/unwritable disk cache must not prevent an explicit retry.
    }
  }

  void _addToMemoryCache(String key, Uint8List bytes) {
    final previous = _memoryCache.remove(key);
    if (previous != null) _memoryBytes -= previous.length;
    if (bytes.length > maxMemoryCacheBytes) return;
    while (_memoryCache.isNotEmpty &&
        (_memoryCache.length >= maxMemoryCacheEntries ||
            _memoryBytes + bytes.length > maxMemoryCacheBytes)) {
      _memoryBytes -= _memoryCache.remove(_memoryCache.keys.first)!.length;
    }
    final snapshot = Uint8List.fromList(bytes).asUnmodifiableView();
    _memoryCache[key] = snapshot;
    _memoryBytes += snapshot.length;
  }

  String _diskPath(String key) => p.join(_cacheDir!,
      '${sha256.convert(utf8.encode('gallery-v2:$key'))}.thumb');

  Future<void> _queueDiskWrite(String key, Uint8List bytes, int epoch) {
    if (_cacheDir == null || bytes.length > maxDiskCacheBytes) {
      return Future<void>.value();
    }
    _diskWrites = _diskWrites.then((_) async {
      if (epoch != _cacheEpoch || _cacheDir == null) return;
      try {
        final file = File(_diskPath(key));
        final previous = await file.stat();
        await file.writeAsBytes(bytes, flush: true);
        _diskBytes += bytes.length -
            (previous.type == FileSystemEntityType.file ? previous.size : 0);
        if (previous.type != FileSystemEntityType.file) _diskCount++;
        // Keep ordinary cache hits cheap; rescan on budget overflow and
        // occasionally to reconcile external cache cleanup.
        if (_diskBytes > maxDiskCacheBytes || _diskCount > maxDiskCacheEntries ||
            ++_writesSincePrune >= 128) {
          _writesSincePrune = 0;
          await _pruneDisk();
        }
      } catch (error) {
        _log.debug('Thumbnail cache write failed: $error');
      }
    });
    return _diskWrites;
  }

  Future<void> _pruneDisk() async {
    final entries = <(File, FileStat)>[];
    var total = 0;
    await for (final entity in Directory(_cacheDir!).list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      entries.add((entity, stat));
      total += stat.size;
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var count = entries.length;
    for (final (file, stat) in entries) {
      if (count <= maxDiskCacheEntries && total <= maxDiskCacheBytes) break;
      await file.delete();
      total -= stat.size;
      count--;
    }
    _diskBytes = total;
    _diskCount = count;
  }

  static Future<Uint8List?> _generateWithPlatformCodec(
      Uint8List bytes, int size) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width < 1 || height < 1 || width * height > kGalleryMaxPixels) return null;
      final scale = math.min(1.0, size / math.max(width, height));
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (width * scale).round()),
        targetHeight: math.max(1, (height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  // Retained for older preview callers. Gallery requests use account- and
  // revision-aware identities instead of these legacy provider-only keys.
  static String remoteKey(String provider, String path) => '$provider:$path';
  static String localKey(String path) => 'local:$path';
}
