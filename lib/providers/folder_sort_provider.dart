import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FolderSortNotifier extends StateNotifier<bool> {
  FolderSortNotifier() : super(true) {
    _load();
  }

  static const preferenceKey = 'panel.sortFoldersLikeFiles.v1';
  bool _changedBeforeLoad = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted && !_changedBeforeLoad) {
      state = prefs.getBool(preferenceKey) ?? true;
    }
  }

  Future<void> set(bool value) async {
    _changedBeforeLoad = true;
    state = value;
    await (await SharedPreferences.getInstance()).setBool(preferenceKey, value);
  }
}

final sortFoldersLikeFilesProvider =
    StateNotifierProvider<FolderSortNotifier, bool>(
      (ref) => FolderSortNotifier(),
    );
