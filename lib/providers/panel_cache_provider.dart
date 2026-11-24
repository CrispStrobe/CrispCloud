import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory folder-listing cache budget. The cache is intentionally bounded
/// by the total number of cached file rows, not by folder count: one folder
/// can contain millions of entries. It never becomes a disk store.
class PanelCacheSettings {
  const PanelCacheSettings({this.maxItems = kIsWeb ? 5000 : 20000});

  static int get defaultMaxItems => kIsWeb ? 5000 : 20000;

  /// Zero disables the cache; otherwise the least-recently-used listings are
  /// discarded until the total cached row count fits this budget.
  final int maxItems;

  PanelCacheSettings copyWith({int? maxItems}) =>
      PanelCacheSettings(maxItems: maxItems ?? this.maxItems);
}

class PanelCacheSettingsNotifier extends StateNotifier<PanelCacheSettings> {
  PanelCacheSettingsNotifier() : super(const PanelCacheSettings()) {
    _load();
  }

  static const _key = 'panel.cache.maxItems.v1';
  static const _legacyFolderKey = 'panel.cache.maxFolders.v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedItems = prefs.getInt(_key);
      if (storedItems != null) {
        state = state.copyWith(maxItems: _clamp(storedItems));
        return;
      }
      final legacyFolders = prefs.getInt(_legacyFolderKey);
      if (legacyFolders != null) {
        final migrated = _clamp(_itemsForLegacyFolderCount(legacyFolders));
        state = state.copyWith(maxItems: migrated);
        await prefs.setInt(_key, migrated);
      }
    } catch (_) {
      // Defaults remain usable when preferences are unavailable.
    }
  }

  Future<void> setMaxItems(int value) async {
    final next = _clamp(value);
    state = state.copyWith(maxItems: next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, next);
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  /// Preserve the intent of the old folder-count setting while moving to a
  /// row budget. The old default of 200 folders becomes 20,000 rows.
  static int _itemsForLegacyFolderCount(int folders) {
    if (folders <= 0) return 0;
    if (folders <= 50) return 5000;
    if (folders <= 100) return 10000;
    if (folders <= 200) return 20000;
    if (folders <= 500) return 50000;
    return 100000;
  }

  static int _clamp(int value) => value.clamp(0, 100000);
}

final panelCacheSettingsProvider =
    StateNotifierProvider<PanelCacheSettingsNotifier, PanelCacheSettings>(
      (ref) => PanelCacheSettingsNotifier(),
    );
