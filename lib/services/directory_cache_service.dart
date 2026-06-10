// lib/services/directory_cache_service.dart
//
// In-memory cache for directory listings (local and remote).
// Shows cached content instantly on source/path switch, then the caller
// refreshes from the real source in the background.

import '../models/file_item.dart';

class DirectoryCacheService {
  // Key: "source_type:provider_or_local:path"
  final Map<String, _CachedListing> _cache = {};

  static const _maxEntries = 200;

  /// Build a cache key from source descriptor + path.
  static String key(String sourceKey, String path) => '$sourceKey:$path';

  /// Returns the cached listing for [cacheKey], or null if not cached.
  List<FileItem>? get(String cacheKey) {
    final entry = _cache[cacheKey];
    if (entry == null) return null;
    entry.lastAccessed = DateTime.now();
    return entry.files;
  }

  /// Store a listing in the cache.
  void put(String cacheKey, List<FileItem> files) {
    _cache[cacheKey] = _CachedListing(
      files: List.of(files),
      cachedAt: DateTime.now(),
      lastAccessed: DateTime.now(),
    );
    _evictIfNeeded();
  }

  /// Invalidate a specific path.
  void invalidate(String cacheKey) => _cache.remove(cacheKey);

  /// Clear all cached listings.
  void clear() => _cache.clear();

  void _evictIfNeeded() {
    if (_cache.length <= _maxEntries) return;
    // Evict least recently accessed entries.
    final sorted = _cache.entries.toList()
      ..sort((a, b) => a.value.lastAccessed.compareTo(b.value.lastAccessed));
    final toRemove = sorted.take(_cache.length - _maxEntries);
    for (final e in toRemove) {
      _cache.remove(e.key);
    }
  }
}

class _CachedListing {
  final List<FileItem> files;
  final DateTime cachedAt;
  DateTime lastAccessed;

  _CachedListing({
    required this.files,
    required this.cachedAt,
    required this.lastAccessed,
  });
}
