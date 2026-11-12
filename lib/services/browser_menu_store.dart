import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/browser_menu_layout.dart';
import '../utils/async_lock.dart';

abstract interface class BrowserMenuStorage {
  Future<String?> read(String key);
  Future<bool> write(String key, String value);
}

class PreferencesBrowserMenuStorage implements BrowserMenuStorage {
  const PreferencesBrowserMenuStorage();
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<bool> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

/// Writes are serialized and validated before replacing the live layout. A
/// corrupt current record can fall back to the previous verified configuration
/// without erasing either stored record just by opening the application.
class BrowserMenuStore extends ChangeNotifier {
  BrowserMenuStore({BrowserMenuStorage? storage})
    : _storage = storage ?? const PreferencesBrowserMenuStorage() {
    ready = _load();
  }
  static const currentKey = 'browser_menu_layout_v1';
  static const backupKey = 'browser_menu_layout_last_good_v1';
  final BrowserMenuStorage _storage;
  final _lock = AsyncLock();
  late final Future<void> ready;
  BrowserMenuLayout _layout = BrowserMenuLayout.defaults();
  BrowserMenuLayout get layout => _layout;
  bool recovered = false;
  bool loaded = false;
  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.read(currentKey);
      if (raw != null) _layout = BrowserMenuLayout.decode(raw);
    } catch (_) {
      recovered = true;
      try {
        final backup = await _storage.read(backupKey);
        if (backup != null) _layout = BrowserMenuLayout.decode(backup);
      } catch (_) {
        /* Usable defaults remain available. */
      }
    } finally {
      loaded = true;
      _changed();
    }
  }

  Future<void> save(BrowserMenuLayout layout) {
    // Snapshot caller-owned data and reject it before entering a write queue.
    final serialized = layout.encode();
    final captured = BrowserMenuLayout.decode(serialized);
    return _lock.synchronized(() async {
      await ready;
      if (_disposed) throw StateError('Menu settings are no longer available.');
      if (!await _storage.write(backupKey, _layout.encode()) ||
          !await _storage.write(currentKey, serialized)) {
        throw StateError('Menu settings could not be saved.');
      }
      _layout = captured;
      recovered = false;
      _changed();
    });
  }

  Future<void> reset() => save(BrowserMenuLayout.defaults());

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
