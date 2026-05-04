// SharedPreferences-backed implementation of internxt_client's
// ConfigStorage interface, for cloud-dart's Flutter Web build
// (where dart:io File is unavailable).
//
// Native builds (macOS/iOS/Android/Linux/Windows) keep using the
// default FileConfigStorage from the published package — this
// class only ships through the kIsWeb branch in the adapter.

import 'package:internxt_client/internxt_client.dart' show ConfigStorage;
import 'package:shared_preferences/shared_preferences.dart';

/// Maps internxt_client's string-keyed config storage onto
/// SharedPreferences. Keys are passed through verbatim — for the
/// CLI's FileConfigStorage they're absolute file paths, but
/// SharedPreferences treats them as opaque strings, so any path
/// shape works as long as it's stable across runs.
///
/// Each method is async to satisfy the interface; SharedPreferences
/// I/O is synchronous after the initial getInstance() but we await
/// it to keep the contract clean.
class SharedPreferencesStorage implements ConfigStorage {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  void init(String dataDir, List<String> subDirs) {
    // No filesystem to set up. SharedPreferences is global per app.
  }

  @override
  Future<bool> exists(String key) async {
    final prefs = await _prefs;
    return prefs.containsKey(key);
  }

  @override
  Future<String?> read(String key) async {
    final prefs = await _prefs;
    return prefs.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await _prefs;
    await prefs.setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await _prefs;
    await prefs.remove(key);
  }
}
