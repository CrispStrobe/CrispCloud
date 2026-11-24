import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory folder-listing cache size. The cache is intentionally bounded:
/// it makes revisiting folders instantaneous but never becomes a disk store.
class PanelCacheSettings {
  const PanelCacheSettings({this.maxFolders = kIsWeb ? 50 : 200});

  static int get defaultMaxFolders => kIsWeb ? 50 : 200;

  /// Zero disables the cache; otherwise the least-recently-used folder is
  /// evicted after this many listings.
  final int maxFolders;

  PanelCacheSettings copyWith({int? maxFolders}) =>
      PanelCacheSettings(maxFolders: maxFolders ?? this.maxFolders);
}

class PanelCacheSettingsNotifier extends StateNotifier<PanelCacheSettings> {
  PanelCacheSettingsNotifier() : super(const PanelCacheSettings()) {
    _load();
  }

  static const _key = 'panel.cache.maxFolders.v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt(_key);
      if (value != null) {
        state = state.copyWith(maxFolders: _clamp(value));
      }
    } catch (_) {
      // Defaults remain usable when preferences are unavailable.
    }
  }

  Future<void> setMaxFolders(int value) async {
    final next = _clamp(value);
    state = state.copyWith(maxFolders: next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, next);
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  static int _clamp(int value) => value.clamp(0, 2000);
}

final panelCacheSettingsProvider =
    StateNotifierProvider<PanelCacheSettingsNotifier, PanelCacheSettings>(
      (ref) => PanelCacheSettingsNotifier(),
    );
