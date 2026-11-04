// lib/providers/ui_chrome_provider.dart
//
// Persisted UI chrome preferences.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the application's top toolbar/AppBar is visible.
///
/// Collapsing it puts a "..." action in the active panel's command row. The
/// choice is stored in SharedPreferences so it survives restarts and app
/// upgrades within the same app container.
class TopToolbarVisibilityNotifier extends StateNotifier<bool> {
  TopToolbarVisibilityNotifier() : super(true) {
    _load();
  }

  static const _key = 'top_toolbar_visible_v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_key) ?? true;
    } catch (_) {
      // Keep the default.
    }
  }

  Future<void> setVisible(bool visible) async {
    state = visible;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, visible);
    } catch (_) {
      // Persistence is best effort.
    }
  }

  Future<void> toggle() => setVisible(!state);
}

final topToolbarVisibleProvider =
    StateNotifierProvider<TopToolbarVisibilityNotifier, bool>(
  (ref) => TopToolbarVisibilityNotifier(),
);
