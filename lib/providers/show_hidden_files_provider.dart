// App-wide "show hidden files" setting (names starting with "."), like
// Finder's Cmd+Shift+. — one choice for both panes and every tab, kept
// across restarts. Panels follow it (PanelNotifier listens).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShowHiddenFilesNotifier extends StateNotifier<bool> {
  ShowHiddenFilesNotifier() : super(false) {
    _load();
  }

  static const preferenceKey = 'panel.showHiddenFiles.v1';
  bool _changedBeforeLoad = false;

  Future<void> _load() async {
    final saved = (await SharedPreferences.getInstance()).getBool(
      preferenceKey,
    );
    if (saved != null && !_changedBeforeLoad && mounted) state = saved;
  }

  Future<void> set(bool value) async {
    _changedBeforeLoad = true;
    state = value;
    await (await SharedPreferences.getInstance()).setBool(preferenceKey, value);
  }

  Future<void> toggle() => set(!state);
}

final showHiddenFilesProvider =
    StateNotifierProvider<ShowHiddenFilesNotifier, bool>(
      (ref) => ShowHiddenFilesNotifier(),
    );
