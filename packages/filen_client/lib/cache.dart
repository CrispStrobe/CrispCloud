/// Caching layer for folder and file listings.
///
/// Provides TTL-based caching with explicit invalidation on mutations.
import 'dart:convert';

import 'package:filen_client/api.dart';
import 'package:filen_client/crypto.dart';

class CacheEntry {
  final dynamic items;
  final DateTime timestamp;
  CacheEntry({required this.items, required this.timestamp});
}

class FilenCache {
  static const Duration cacheDuration = Duration(minutes: 10);

  final DateTime Function() _now;
  final Map<String, CacheEntry> folderCache = {};
  final Map<String, CacheEntry> fileCache = {};
  final Map<String, Map<String, dynamic>> pathCache = {};

  FilenCache({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  bool _isValid(CacheEntry entry) {
    return _now().difference(entry.timestamp) < cacheDuration;
  }

  void invalidate(String folderUuid) {
    folderCache.remove(folderUuid);
    fileCache.remove(folderUuid);
  }

  void clearPathCache() {
    pathCache.clear();
  }

  Future<void> clearParentCache(String itemUuid, String itemType, FilenApi api,
      FilenCrypto crypto, List<String> masterKeys) async {
    try {
      String? parentUuid;

      if (itemType == 'file') {
        final info = await api.post('/v3/file', {'uuid': itemUuid});
        parentUuid = info['data']?['parent'];
      } else if (itemType == 'folder') {
        final info = await api.post('/v3/dir', {'uuid': itemUuid});
        parentUuid = info['data']?['parent'];
      }

      if (parentUuid != null) {
        invalidate(parentUuid);
        api.log('Cleared parent cache for $parentUuid');
      }
    } catch (e) {
      api.log('Could not clear parent cache for $itemUuid: $e');
    }
  }

  /// List subfolders of [uuid], using cache when available.
  Future<List<Map<String, dynamic>>> listFoldersAsync(
    String uuid, {
    bool detailed = false,
    required FilenApi api,
    required FilenCrypto crypto,
    required List<String> masterKeys,
  }) async {
    final cached = folderCache[uuid];
    if (cached != null && _isValid(cached)) {
      api.log('Using cached folder list for $uuid');
      return List<Map<String, dynamic>>.from(cached.items);
    }

    final response = await api.post('/v3/dir/content', {'uuid': uuid});
    final d = response['data']['folders'] ?? [];

    List<Map<String, dynamic>> res = [];

    for (var f in d) {
      try {
        var dec = await crypto.tryDecrypt(f['name'], masterKeys);
        var name = dec.startsWith('{') ? json.decode(dec)['name'] : dec;
        res.add({
          'type': 'folder',
          'name': name,
          'uuid': f['uuid'],
          'size': 0,
          'parent': f['parent'],
          'timestamp': f['timestamp'],
          'lastModified': f['lastModified'],
        });
      } catch (_) {
        res.add({
          'type': 'folder',
          'name': '[Encrypted]',
          'uuid': f['uuid'],
          'size': 0,
        });
      }
    }

    folderCache[uuid] = CacheEntry(items: res, timestamp: _now());

    if (!detailed) {
      return res
          .map((item) => {
                'type': item['type'],
                'name': item['name'],
                'uuid': item['uuid'],
                'size': item['size'],
              })
          .toList();
    }
    return res;
  }

  /// List files in folder [uuid], using cache when available.
  Future<List<Map<String, dynamic>>> listFolderFiles(
    String uuid, {
    bool detailed = false,
    required FilenApi api,
    required FilenCrypto crypto,
    required List<String> masterKeys,
  }) async {
    final cached = fileCache[uuid];
    if (cached != null && _isValid(cached)) {
      api.log('Using cached file list for $uuid');
      return List<Map<String, dynamic>>.from(cached.items);
    }

    final response = await api.post('/v3/dir/content', {'uuid': uuid});
    final d = response['data']['uploads'] ?? [];

    final res = await Future.wait((d as List).map((f) async {
      try {
        final m =
            json.decode(await crypto.tryDecrypt(f['metadata'], masterKeys));
        return {
          'type': 'file',
          'name': m['name'],
          'uuid': f['uuid'],
          'size': m['size'],
          'parent': f['parent'],
          'timestamp': f['timestamp'],
          'lastModified': m['lastModified'],
        };
      } catch (_) {
        return {
          'type': 'file',
          'name': '[Encrypted]',
          'uuid': f['uuid'],
          'size': 0,
        };
      }
    }).toList());

    final typedRes = res.cast<Map<String, dynamic>>();
    fileCache[uuid] = CacheEntry(items: typedRes, timestamp: _now());

    if (!detailed) {
      return typedRes
          .map((item) => {
                'type': item['type'],
                'name': item['name'],
                'uuid': item['uuid'],
                'size': item['size'],
              })
          .toList();
    }
    return typedRes;
  }
}
