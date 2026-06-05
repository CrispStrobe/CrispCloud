// lib/providers/veracrypt_mount_provider.dart
//
// Riverpod providers for VeraCrypt mount state.
//
// - [veracryptMountServiceProvider]  — singleton service instance
// - [veracryptInstalledProvider]     — FutureProvider: is the CLI available?
// - [veracryptMountsProvider]        — StateNotifier tracking active mounts
//   with mount/unmount actions.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/log_service.dart';
import '../services/veracrypt_mount_service.dart';

// ---------------------------------------------------------------------------
// Singleton service
// ---------------------------------------------------------------------------

/// Provides the singleton [VeraCryptMountService] instance.
final veracryptMountServiceProvider = Provider<VeraCryptMountService>((ref) {
  return VeraCryptMountService();
});

// ---------------------------------------------------------------------------
// Installation check
// ---------------------------------------------------------------------------

/// Async check for whether `veracrypt` CLI is available on PATH.
///
/// Re-evaluate by calling `ref.refresh(veracryptInstalledProvider)`.
final veracryptInstalledProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(veracryptMountServiceProvider);
  return service.isVeraCryptInstalled();
});

// ---------------------------------------------------------------------------
// Active mounts state notifier
// ---------------------------------------------------------------------------

/// State managed by [VeraCryptMountsNotifier].
class VeraCryptMountsState {
  /// All currently-mounted volumes known to this notifier.
  final List<VeraCryptMountPoint> mounts;

  /// True while a mount or unmount operation is in progress.
  final bool isBusy;

  /// Last error, or null if no error has occurred.
  final String? lastError;

  const VeraCryptMountsState({
    this.mounts = const [],
    this.isBusy = false,
    this.lastError,
  });

  VeraCryptMountsState copyWith({
    List<VeraCryptMountPoint>? mounts,
    bool? isBusy,
    String? lastError,
    bool clearError = false,
  }) =>
      VeraCryptMountsState(
        mounts: mounts ?? this.mounts,
        isBusy: isBusy ?? this.isBusy,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

class VeraCryptMountsNotifier extends Notifier<VeraCryptMountsState> {
  static const _log = Log('VeraCryptMountsNotifier');

  @override
  VeraCryptMountsState build() => const VeraCryptMountsState();

  VeraCryptMountService get _service =>
      ref.read(veracryptMountServiceProvider);

  // ---------------------------------------------------------------------------
  // Refresh
  // ---------------------------------------------------------------------------

  /// Refresh the mount list by querying the CLI.
  Future<void> refresh() async {
    if (!VeraCryptMountService.isDesktopPlatform) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final mounts = await _service.listMounted();
      state = state.copyWith(mounts: mounts, isBusy: false);
    } catch (e) {
      _log.warn('refresh() failed', e);
      state = state.copyWith(
        isBusy: false,
        lastError: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Mount
  // ---------------------------------------------------------------------------

  /// Mount a container. On success, refreshes the mount list.
  ///
  /// Returns the resulting [VeraCryptMountPoint] or null on failure.
  Future<VeraCryptMountPoint?> mount(
    String containerPath,
    String password, {
    String? mountPoint,
    bool readOnly = false,
    String? hashAlgorithm,
    int? slot,
    bool truecryptMode = false,
  }) async {
    if (!VeraCryptMountService.isDesktopPlatform) {
      state = state.copyWith(
          lastError: 'VeraCrypt is only supported on desktop platforms.');
      return null;
    }

    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final entry = await _service.mount(
        containerPath,
        password,
        mountPoint: mountPoint,
        readOnly: readOnly,
        hashAlgorithm: hashAlgorithm,
        slot: slot,
        truecryptMode: truecryptMode,
      );
      // Append to local list immediately (no need to re-query CLI).
      final updated = [...state.mounts, entry];
      state = state.copyWith(mounts: updated, isBusy: false);
      return entry;
    } catch (e) {
      _log.error('mount() failed', e);
      state = state.copyWith(isBusy: false, lastError: e.toString());
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Unmount
  // ---------------------------------------------------------------------------

  /// Unmount a volume by its mount-point path or slot number.
  Future<bool> unmount(Object mountPointOrSlot) async {
    if (!VeraCryptMountService.isDesktopPlatform) return false;

    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _service.unmount(mountPointOrSlot);
      // Remove from local list.
      final updated = state.mounts.where((m) {
        if (mountPointOrSlot is int) return m.slot != mountPointOrSlot;
        return m.mountPoint != mountPointOrSlot.toString();
      }).toList();
      state = state.copyWith(mounts: updated, isBusy: false);
      return true;
    } catch (e) {
      _log.error('unmount() failed', e);
      state = state.copyWith(isBusy: false, lastError: e.toString());
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Unmount all
  // ---------------------------------------------------------------------------

  /// Unmount all volumes.
  Future<bool> unmountAll() async {
    if (!VeraCryptMountService.isDesktopPlatform) return false;

    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _service.unmountAll();
      state = state.copyWith(mounts: const [], isBusy: false);
      return true;
    } catch (e) {
      _log.error('unmountAll() failed', e);
      state = state.copyWith(isBusy: false, lastError: e.toString());
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Error handling
  // ---------------------------------------------------------------------------

  /// Clear the last error.
  void clearError() => state = state.copyWith(clearError: true);
}

/// Provider for the [VeraCryptMountsNotifier].
final veracryptMountsProvider =
    NotifierProvider<VeraCryptMountsNotifier, VeraCryptMountsState>(
  VeraCryptMountsNotifier.new,
);
