// lib/providers/mount_provider.dart
//
// Riverpod provider for FUSE mount state.
//
// MountNotifier wraps FuseMountService, persists mount configurations across
// restarts, and exposes the mount list to the UI layer.
//
// Auto-mount on startup and auto-unmount on app exit are opt-in via
// [autoMountOnStartup] and the [dispose] override.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cloud_storage_interface.dart';
import '../services/fuse_mount_service.dart';
import '../services/log_service.dart';
import 'auth_provider.dart';
import 'error_provider.dart';

class MountNotifier extends ChangeNotifier {
  static const _log = Log('MountNotifier');

  final Ref _ref;
  final FuseMountService _service;

  bool _autoUnmountOnExit = true;
  bool _isChecking = false; // true while the availability check is running

  /// Cached result of the last FUSE availability check.
  /// null = not yet checked, empty string = available, otherwise the error.
  String? _availabilityError;

  MountNotifier(this._ref) : _service = FuseMountService() {
    _service.onChanged = notifyListeners;
    _init();
  }

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  Future<void> _init() async {
    if (!FuseMountService.isSupported) return;
    await _service.loadPersistedMounts();
    notifyListeners();
    unawaited(_checkAvailability());
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// All known mounts (mounted, unmounted, error).
  List<MountEntry> get mounts => _service.getMounts();

  /// Currently mounted drives only.
  List<MountEntry> get activeMounts => _service.getActiveMounts();

  /// Whether the current platform supports FUSE.
  bool get isSupported => FuseMountService.isSupported;

  /// null = not yet checked; empty = OK; non-empty = human-readable error.
  String? get availabilityError => _availabilityError;

  /// True while the availability check is running.
  bool get isCheckingAvailability => _isChecking;

  bool get autoUnmountOnExit => _autoUnmountOnExit;

  // ---------------------------------------------------------------------------
  // FUSE availability
  // ---------------------------------------------------------------------------

  Future<void> _checkAvailability() async {
    if (!isSupported) return;
    _isChecking = true;
    notifyListeners();
    try {
      _availabilityError = await _service.checkFuseAvailability();
    } catch (e) {
      _availabilityError = e.toString();
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  /// Re-run the FUSE availability check (e.g. after the user installs macFUSE).
  Future<void> recheckAvailability() => _checkAvailability();

  // ---------------------------------------------------------------------------
  // Mount / unmount
  // ---------------------------------------------------------------------------

  /// Mount a cloud path as a local drive.
  ///
  /// Uses the currently authenticated [CloudStorageClient] obtained from
  /// [authProvider]. Returns the resulting [MountEntry].
  Future<MountEntry?> mount({
    required String remotePath,
    required String mountPoint,
    String? label,
  }) async {
    if (!isSupported) {
      _ref.read(errorProvider).addError('FUSE mounts are not supported on this platform.');
      return null;
    }

    if (_availabilityError != null && _availabilityError!.isNotEmpty) {
      _ref.read(errorProvider).addError(_availabilityError!);
      return null;
    }

    try {
      final auth = _ref.read(authProvider);
      if (!auth.isConnected) {
        _ref.read(errorProvider).addError('Connect to a cloud provider before mounting.');
        return null;
      }
      final entry = await _service.mount(
        client: auth.client,
        remotePath: remotePath,
        mountPoint: mountPoint,
        label: label,
      );
      if (entry.status == MountStatus.error) {
        _ref.read(errorProvider).addError(
            'Mount failed: ${entry.errorMessage ?? "unknown error"}');
      }
      notifyListeners();
      return entry;
    } catch (e) {
      _log.error('mount() failed', e);
      _ref.read(errorProvider).addError('Mount failed: $e');
      return null;
    }
  }

  /// Mount using an explicit [CloudStorageClient] (for multi-cloud scenarios).
  Future<MountEntry?> mountWithClient({
    required CloudStorageClient client,
    required String remotePath,
    required String mountPoint,
    String? label,
  }) async {
    if (!isSupported) {
      _ref.read(errorProvider).addError('FUSE mounts are not supported on this platform.');
      return null;
    }
    try {
      final entry = await _service.mount(
        client: client,
        remotePath: remotePath,
        mountPoint: mountPoint,
        label: label,
      );
      if (entry.status == MountStatus.error) {
        _ref.read(errorProvider).addError(
            'Mount failed: ${entry.errorMessage ?? "unknown error"}');
      }
      notifyListeners();
      return entry;
    } catch (e) {
      _log.error('mountWithClient() failed', e);
      _ref.read(errorProvider).addError('Mount failed: $e');
      return null;
    }
  }

  /// Unmount the drive at [mountPoint].
  Future<void> unmount(String mountPoint) async {
    try {
      await _service.unmount(mountPoint);
      notifyListeners();
    } catch (e) {
      _log.error('unmount() failed', e);
      _ref.read(errorProvider).addError('Unmount failed: $e');
    }
  }

  /// Remove a mount configuration entirely.
  Future<void> removeMount(String mountPoint) async {
    try {
      await _service.removeMount(mountPoint);
      notifyListeners();
    } catch (e) {
      _log.error('removeMount() failed', e);
      _ref.read(errorProvider).addError('Remove mount failed: $e');
    }
  }

  /// Unmount all active drives (e.g. called from app exit hook).
  Future<void> unmountAll() async {
    await _service.unmountAll();
    notifyListeners();
  }

  bool isMounted(String mountPoint) => _service.isMounted(mountPoint);

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  void setAutoUnmountOnExit(bool value) {
    _autoUnmountOnExit = value;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  Future<void> dispose() async {
    if (_autoUnmountOnExit) {
      await _service.unmountAll();
    }
    super.dispose();
  }
}

final mountProvider = ChangeNotifierProvider<MountNotifier>((ref) {
  return MountNotifier(ref);
});
