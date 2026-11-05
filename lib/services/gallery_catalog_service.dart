import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gallery.dart';

/// Device-local, source-scoped catalog. File bytes and embedded metadata stay
/// untouched. Writes are serialized and only published after persistence.
class GalleryCatalogService extends ChangeNotifier {
  static const preferencesKey = 'gallery_catalog_v1';
  Map<String, GalleryRecord> _records = {};
  Future<void>? _initializing;
  Future<void> _tail = Future.value();
  bool _disposed = false;

  GalleryRecord get(String assetId) => _records[assetId] ?? const GalleryRecord();

  Future<void> load() => _initializing ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preferencesKey);
    if (raw != null) {
      // Corruption must not silently overwrite the user's existing catalog.
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid gallery catalog');
      }
      _records = {
        for (final entry in value.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: GalleryRecord.fromJson(entry.value as Map<String, dynamic>),
      };
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> update(
    Iterable<String> assetIds, {
    int? rating,
    GalleryColor? color,
    bool? favorite,
    List<String>? tags,
    bool replaceTags = false,
  }) {
    final ids = assetIds.where((id) => id.isNotEmpty).toSet();
    final next = _tail.then((_) async {
      await load();
      if (ids.isEmpty) return;
      final updated = Map<String, GalleryRecord>.of(_records);
      for (final id in ids) {
        final old = get(id);
        final record = old.copyWith(
          rating: rating, color: color, favorite: favorite,
          tags: tags == null ? null : replaceTags ? tags : [...old.tags, ...tags],
        );
        if (record.isEmpty) {
          updated.remove(id);
        } else {
          updated[id] = record;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final written = await prefs.setString(preferencesKey, jsonEncode({
        for (final entry in updated.entries) entry.key: entry.value.toJson(),
      }));
      if (!written) throw StateError('Gallery catalog could not be saved');
      _records = updated;
      if (!_disposed) notifyListeners();
    });
    // A failed write is returned to the caller; subsequent writes can retry.
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  String exportJson(Map<String, String> namesByAssetId) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'crispcloud-gallery-catalog',
        'version': 1,
        'items': [
          for (final entry in namesByAssetId.entries)
            {'assetId': entry.key, 'name': entry.value, ...get(entry.key).toJson()},
        ],
      });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
