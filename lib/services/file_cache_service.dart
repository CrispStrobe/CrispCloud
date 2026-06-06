// lib/services/file_cache_service.dart
//
// Local file cache for recently accessed remote files.
// Enables offline access to previously viewed files with LRU eviction.
//
// Cache structure:
//   <cacheDir>/
//     index.json       — metadata: remote path, provider, size, access time
//     files/            — cached file data, keyed by SHA-1 of remote path
//
// Features:
//   - Configurable max cache size (default 500 MB)
//   - LRU eviction: least recently accessed files evicted first
//   - Per-provider cache isolation
//   - Cache hit/miss tracking for UI display

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';

/// Metadata for a cached file.
class CacheEntry {
  final String remotePath;
  final String provider;
  final int sizeBytes;
  final DateTime cachedAt;
  DateTime lastAccessed;
  final String localFileName;

  CacheEntry({
    required this.remotePath,
    required this.provider,
    required this.sizeBytes,
    required this.cachedAt,
    required this.lastAccessed,
    required this.localFileName,
  });

  Map<String, dynamic> toJson() => {
        'remotePath': remotePath,
        'provider': provider,
        'sizeBytes': sizeBytes,
        'cachedAt': cachedAt.toIso8601String(),
        'lastAccessed': lastAccessed.toIso8601String(),
        'localFileName': localFileName,
      };

  factory CacheEntry.fromJson(Map<String, dynamic> json) => CacheEntry(
        remotePath: json['remotePath'] as String,
        provider: json['provider'] as String,
        sizeBytes: json['sizeBytes'] as int,
        cachedAt: DateTime.parse(json['cachedAt'] as String),
        lastAccessed: DateTime.parse(json['lastAccessed'] as String),
        localFileName: json['localFileName'] as String,
      );
}

class FileCacheService {
  static const _log = Log('FileCache');
  static const _maxSizeKey = 'file_cache_max_size';
  static const _defaultMaxSize = 500 * 1024 * 1024; // 500 MB

  String? _cacheDir;
  final Map<String, CacheEntry> _index = {}; // key = "provider:remotePath"
  int _maxSizeBytes = _defaultMaxSize;
  int _totalSize = 0;

  int get totalSize => _totalSize;
  int get maxSize => _maxSizeBytes;
  int get entryCount => _index.length;
  double get usagePercent => _maxSizeBytes > 0 ? _totalSize / _maxSizeBytes : 0;

  /// Initialize the cache: create directories, load index.
  Future<void> init() async {
    if (kIsWeb) return; // File cache uses dart:io — not available on web
    final appDir = await getApplicationSupportDirectory();
    _cacheDir = p.join(appDir.path, 'file_cache');

    final dir = Directory(_cacheDir!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final filesDir = Directory(p.join(_cacheDir!, 'files'));
    if (!await filesDir.exists()) {
      await filesDir.create();
    }

    // Load max size setting
    final prefs = await SharedPreferences.getInstance();
    _maxSizeBytes = prefs.getInt(_maxSizeKey) ?? _defaultMaxSize;

    // Load index
    await _loadIndex();
    _log.info('File cache initialized: ${_index.length} entries, '
        '${(_totalSize / 1024 / 1024).toStringAsFixed(1)} MB / '
        '${(_maxSizeBytes / 1024 / 1024).toStringAsFixed(0)} MB');
  }

  /// Set the maximum cache size in bytes.
  Future<void> setMaxSize(int bytes) async {
    _maxSizeBytes = bytes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxSizeKey, bytes);
    await _evictIfNeeded();
  }

  /// Check if a file is cached.
  bool isCached(String remotePath, String provider) {
    return _index.containsKey(_key(remotePath, provider));
  }

  /// Get cached file bytes, updating access time. Returns null on miss.
  Future<List<int>?> get(String remotePath, String provider) async {
    final key = _key(remotePath, provider);
    final entry = _index[key];
    if (entry == null) return null;

    final file = File(p.join(_cacheDir!, 'files', entry.localFileName));
    if (!await file.exists()) {
      // File missing — remove stale index entry
      _index.remove(key);
      _totalSize -= entry.sizeBytes;
      await _saveIndex();
      return null;
    }

    // Update last accessed time
    entry.lastAccessed = DateTime.now();
    await _saveIndex();

    return await file.readAsBytes();
  }

  /// Store file bytes in cache, evicting old entries if needed.
  Future<void> put(String remotePath, String provider, List<int> data) async {
    if (_cacheDir == null) return;

    final key = _key(remotePath, provider);
    final localName = _hashPath(key);

    // Remove old entry if exists
    final existing = _index[key];
    if (existing != null) {
      _totalSize -= existing.sizeBytes;
      final oldFile = File(p.join(_cacheDir!, 'files', existing.localFileName));
      if (await oldFile.exists()) await oldFile.delete();
    }

    // Write file
    final file = File(p.join(_cacheDir!, 'files', localName));
    await file.writeAsBytes(data);

    // Create entry
    final now = DateTime.now();
    _index[key] = CacheEntry(
      remotePath: remotePath,
      provider: provider,
      sizeBytes: data.length,
      cachedAt: now,
      lastAccessed: now,
      localFileName: localName,
    );
    _totalSize += data.length;

    // Evict if over limit
    await _evictIfNeeded();
    await _saveIndex();
  }

  /// Remove a specific file from cache.
  Future<void> remove(String remotePath, String provider) async {
    final key = _key(remotePath, provider);
    final entry = _index.remove(key);
    if (entry != null) {
      _totalSize -= entry.sizeBytes;
      final file = File(p.join(_cacheDir!, 'files', entry.localFileName));
      if (await file.exists()) await file.delete();
      await _saveIndex();
    }
  }

  /// Clear entire cache.
  Future<void> clear() async {
    for (final entry in _index.values) {
      final file = File(p.join(_cacheDir!, 'files', entry.localFileName));
      if (await file.exists()) await file.delete();
    }
    _index.clear();
    _totalSize = 0;
    await _saveIndex();
    _log.info('File cache cleared');
  }

  /// Get all cached entries sorted by last accessed (most recent first).
  List<CacheEntry> getEntries() {
    final entries = _index.values.toList()
      ..sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));
    return entries;
  }

  // --- LRU Eviction ---

  Future<void> _evictIfNeeded() async {
    if (_maxSizeBytes == 0) return; // 0 = unlimited
    if (_totalSize <= _maxSizeBytes) return;

    // Sort by last accessed (oldest first)
    final entries = _index.entries.toList()
      ..sort((a, b) => a.value.lastAccessed.compareTo(b.value.lastAccessed));

    int evicted = 0;
    for (final entry in entries) {
      if (_totalSize <= _maxSizeBytes * 0.8) break; // Evict down to 80%

      final file = File(p.join(_cacheDir!, 'files', entry.value.localFileName));
      if (await file.exists()) await file.delete();
      _totalSize -= entry.value.sizeBytes;
      _index.remove(entry.key);
      evicted++;
    }

    if (evicted > 0) {
      _log.info('Evicted $evicted entries, cache now ${(_totalSize / 1024 / 1024).toStringAsFixed(1)} MB');
    }
  }

  // --- Persistence ---

  Future<void> _loadIndex() async {
    final file = File(p.join(_cacheDir!, 'index.json'));
    if (!await file.exists()) return;

    try {
      final raw = await file.readAsString();
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _totalSize = 0;
      for (final json in list) {
        final entry = CacheEntry.fromJson(json);
        final key = _key(entry.remotePath, entry.provider);
        _index[key] = entry;
        _totalSize += entry.sizeBytes;
      }
    } catch (e) {
      _log.warn('Failed to load cache index', e);
      _index.clear();
      _totalSize = 0;
    }
  }

  Future<void> _saveIndex() async {
    if (_cacheDir == null) return;
    final file = File(p.join(_cacheDir!, 'index.json'));
    final list = _index.values.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }

  // --- Helpers ---

  static String _key(String remotePath, String provider) => '$provider:$remotePath';

  static String _hashPath(String key) {
    return sha1.convert(utf8.encode(key)).toString();
  }
}
