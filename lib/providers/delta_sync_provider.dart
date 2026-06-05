// lib/providers/delta_sync_provider.dart
//
// Riverpod providers for the delta sync service.
//
// Providers:
//   deltaSyncServiceProvider  — singleton DeltaSyncService
//   deltaBlockSizeProvider    — configurable block size (persisted via
//                               SharedPreferences, default 4 MB)
//   deltaSyncEnabledProvider  — toggle: whether to use delta sync at all
//                               (default: true — applied automatically to
//                               files larger than the 10 MB threshold)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/delta_sync_service.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const int _kDefaultBlockSize  = 4 * 1024 * 1024; // 4 MB
const int _kMinBlockSize      = 64 * 1024;         // 64 KB
const int _kMaxBlockSize      = 64 * 1024 * 1024; // 64 MB

const String _kBlockSizeKey   = 'delta_sync_block_size';
const String _kEnabledKey     = 'delta_sync_enabled';

// ---------------------------------------------------------------------------
// Singleton service
// ---------------------------------------------------------------------------

/// Singleton [DeltaSyncService].  All callers share the same instance so
/// in-flight operations are visible across the widget tree.
final deltaSyncServiceProvider = Provider<DeltaSyncService>((ref) {
  return DeltaSyncService();
});

// ---------------------------------------------------------------------------
// Block size notifier
// ---------------------------------------------------------------------------

class _BlockSizeNotifier extends StateNotifier<int> {
  _BlockSizeNotifier() : super(_kDefaultBlockSize) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_kBlockSizeKey);
    if (stored != null &&
        stored >= _kMinBlockSize &&
        stored <= _kMaxBlockSize) {
      state = stored;
    }
  }

  /// Update the block size used when computing block maps.
  ///
  /// [size] is clamped to [_kMinBlockSize]..[_kMaxBlockSize].
  Future<void> setBlockSize(int size) async {
    final clamped = size.clamp(_kMinBlockSize, _kMaxBlockSize);
    state = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBlockSizeKey, clamped);
  }

  /// Reset to the default 4 MB block size.
  Future<void> reset() => setBlockSize(_kDefaultBlockSize);
}

/// Configurable block size for delta sync (in bytes).
///
/// Default: 4 MB.  Persisted via SharedPreferences across app restarts.
/// Valid range: 64 KB – 64 MB.
final deltaBlockSizeProvider =
    StateNotifierProvider<_BlockSizeNotifier, int>(
  (_) => _BlockSizeNotifier(),
);

// ---------------------------------------------------------------------------
// Enabled toggle notifier
// ---------------------------------------------------------------------------

class _DeltaSyncEnabledNotifier extends StateNotifier<bool> {
  _DeltaSyncEnabledNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kEnabledKey) ?? true;
  }

  /// Enable or disable delta sync globally.
  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, value);
  }

  Future<void> toggle() => setEnabled(!state);
}

/// Whether delta sync is globally enabled.
///
/// When true, files larger than 10 MB are synced using block-level deltas
/// instead of full re-uploads.  Persisted via SharedPreferences.
final deltaSyncEnabledProvider =
    StateNotifierProvider<_DeltaSyncEnabledNotifier, bool>(
  (_) => _DeltaSyncEnabledNotifier(),
);
