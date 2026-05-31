// lib/providers/update_provider.dart
//
// Riverpod providers for the auto-update subsystem.
//
//  updateChannelProvider     — StateNotifier<UpdateChannel> with SharedPrefs persistence
//  autoUpdateEnabledProvider — StateNotifier<bool> with SharedPrefs persistence
//  updateCheckProvider       — FutureProvider<UpdateInfo?> that calls checkForUpdate

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auto_update_service.dart';

// ---------------------------------------------------------------------------
// AutoUpdateService singleton provider
// ---------------------------------------------------------------------------

/// Provides a configured [AutoUpdateService].  Override in tests.
final autoUpdateServiceProvider = Provider<AutoUpdateService>((ref) {
  return AutoUpdateService(
    owner: 'crispasr',      // replace with your actual GitHub org/user
    repo: 'CrispCloud',
  );
});

// ---------------------------------------------------------------------------
// Update channel
// ---------------------------------------------------------------------------

class _UpdateChannelNotifier extends StateNotifier<UpdateChannel> {
  final AutoUpdateService _svc;

  _UpdateChannelNotifier(this._svc) : super(UpdateChannel.stable) {
    _load();
  }

  Future<void> _load() async {
    final channel = await _svc.loadChannel();
    if (mounted) state = channel;
  }

  Future<void> setChannel(UpdateChannel channel) async {
    state = channel;
    await _svc.saveChannel(channel);
  }
}

/// Persisted update channel preference (stable / beta / nightly).
final updateChannelProvider =
    StateNotifierProvider<_UpdateChannelNotifier, UpdateChannel>((ref) {
  final svc = ref.watch(autoUpdateServiceProvider);
  return _UpdateChannelNotifier(svc);
});

// ---------------------------------------------------------------------------
// Auto-update toggle
// ---------------------------------------------------------------------------

class _AutoUpdateEnabledNotifier extends StateNotifier<bool> {
  final AutoUpdateService _svc;

  _AutoUpdateEnabledNotifier(this._svc) : super(true) {
    _load();
  }

  Future<void> _load() async {
    final enabled = await _svc.isAutoCheckEnabled();
    if (mounted) state = enabled;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _svc.setAutoCheckEnabled(enabled);
  }
}

/// Toggle: whether the app automatically checks for updates on startup.
final autoUpdateEnabledProvider =
    StateNotifierProvider<_AutoUpdateEnabledNotifier, bool>((ref) {
  final svc = ref.watch(autoUpdateServiceProvider);
  return _AutoUpdateEnabledNotifier(svc);
});

// ---------------------------------------------------------------------------
// Update check (FutureProvider)
// ---------------------------------------------------------------------------

/// Performs a version check against GitHub Releases.
///
/// Automatically re-runs whenever [updateChannelProvider] changes.
/// Returns an [UpdateInfo] when a newer version is available, or null.
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  final svc = ref.watch(autoUpdateServiceProvider);
  final channel = ref.watch(updateChannelProvider);
  final autoEnabled = ref.watch(autoUpdateEnabledProvider);

  if (!autoEnabled) return null;

  return svc.checkForUpdate(channel: channel);
});

// ---------------------------------------------------------------------------
// Install instructions helper
// ---------------------------------------------------------------------------

/// Returns platform-appropriate instructions for the given [UpdateInfo].
/// Exposed as a simple Provider so UI widgets don't import the service directly.
final updateInstallInstructionsProvider =
    Provider.family<String, UpdateInfo>((ref, info) {
  final svc = ref.watch(autoUpdateServiceProvider);
  return svc.installInstructions(info);
});
