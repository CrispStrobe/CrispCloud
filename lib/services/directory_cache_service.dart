// lib/services/directory_cache_service.dart
//
// In-memory cache for directory listings (local and remote).
// Shows cached content instantly on source/path switch, then the caller
// refreshes from the real source in the background.
//
// The bound is the total number of cached file rows, not the number of
// folders. A single listing larger than the whole budget is not cached, so a
// directory with millions of entries cannot silently consume unbounded memory.

import '../models/file_item.dart';

class DirectoryCacheService {
  DirectoryCacheService({this.maxItems = 20000});

  // Key: "source_type:provider_or_local:path"
  final Map<String, _CachedListing> _cache = {};

  /// Maximum number of file rows retained across all listings. Zero disables
  /// the cache entirely.
  int maxItems;
  int _itemCount = 0;

  /// Build a cache key from source descriptor + path.
  static String key(String sourceKey, String path) => '$sourceKey:$path';

  /// Total rows currently retained. Exposed for tests and diagnostics.
  int get cachedItems => _itemCount;

  /// Returns the cached listing for [cacheKey], or null if not cached.
  List<FileItem>? get(String cacheKey) {
    final entry = _cache[cacheKey];
    if (entry == null) return null;
    entry.lastAccessed = DateTime.now();
    return entry.files;
  }

  /// Store a listing in the cache.
  void put(String cacheKey, List<FileItem> files) {
    if (maxItems <= 0) return;
    final previous = _cache.remove(cacheKey);
    if (previous != null) _itemCount -= previous.files.length;
    if (files.length > maxItems) {
      // Never cache a listing that alone exceeds the configured budget.
      _evictIfNeeded();
      return;
    }
    _cache[cacheKey] = _CachedListing(
      files: List.of(files),
      cachedAt: DateTime.now(),
      lastAccessed: DateTime.now(),
    );
    _itemCount += files.length;
    _evictIfNeeded();
  }

  /// Invalidate a specific path.
  void invalidate(String cacheKey) {
    final removed = _cache.remove(cacheKey);
    if (removed != null) _itemCount -= removed.files.length;
  }

  /// Clear all cached listings.
  void clear() {
    _cache.clear();
    _itemCount = 0;
  }

  void _evictIfNeeded() {
    if (maxItems <= 0) {
      clear();
      return;
    }
    while (_itemCount > maxItems && _cache.isNotEmpty) {
      String? oldestKey;
      DateTime? oldestAccess;
      for (final entry in _cache.entries) {
        if (oldestAccess == null ||
            entry.value.lastAccessed.isBefore(oldestAccess)) {
          oldestAccess = entry.value.lastAccessed;
          oldestKey = entry.key;
        }
      }
      if (oldestKey == null) break;
      invalidate(oldestKey);
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
