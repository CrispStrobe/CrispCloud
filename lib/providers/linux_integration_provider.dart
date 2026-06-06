// lib/providers/linux_integration_provider.dart
//
// Riverpod providers for Linux desktop integration.
//
// Exposes:
//   linuxFileManagersProvider  — AsyncValue<List<String>> of detected file
//                                managers on the current system.
//   linuxIntegrationEnabledProvider — per-file-manager bool toggle (in-memory;
//                                     persist via shared_preferences if needed).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/linux_integration_service.dart';

// ---------------------------------------------------------------------------
// Singleton service provider
// ---------------------------------------------------------------------------

/// Provides the shared [LinuxIntegrationService] instance.
final linuxIntegrationServiceProvider = Provider<LinuxIntegrationService>(
  (ref) => LinuxIntegrationService(),
);

// ---------------------------------------------------------------------------
// Detected file managers
// ---------------------------------------------------------------------------

/// Async list of file manager names detected on this Linux system.
///
/// Returns an empty list on non-Linux platforms.
final linuxFileManagersProvider = FutureProvider<List<String>>((ref) async {
  final service = ref.watch(linuxIntegrationServiceProvider);
  return service.getInstalledFileManagers();
});

// ---------------------------------------------------------------------------
// Per-file-manager integration toggle
// ---------------------------------------------------------------------------

/// Tracks whether the CrispCloud integration is enabled for a given
/// [fileManager] name (e.g. 'nautilus', 'dolphin', 'thunar').
///
/// State is in-memory; callers should persist via SharedPreferences if needed.
class LinuxIntegrationEnabledNotifier extends StateNotifier<bool> {
  final String fileManager;
  final LinuxIntegrationService _service;

  LinuxIntegrationEnabledNotifier(this.fileManager, this._service)
      : super(false);

  /// Enables the integration for [fileManager] by calling the appropriate
  /// install method. Updates state on success.
  Future<void> enable() async {
    if (!LinuxIntegrationService.isLinux) return;
    final ok = await _install();
    if (ok) state = true;
  }

  /// Disables the integration for [fileManager] by calling the appropriate
  /// uninstall method. Updates state on success.
  Future<void> disable() async {
    if (!LinuxIntegrationService.isLinux) return;
    final ok = await _uninstall();
    if (ok) state = false;
  }

  Future<bool> _install() {
    switch (fileManager) {
      case 'nautilus':
        return _service.installNautilusExtension();
      case 'dolphin':
        return _service.installDolphinAction();
      case 'thunar':
        return _service.installThunarAction();
      default:
        return Future.value(false);
    }
  }

  Future<bool> _uninstall() {
    switch (fileManager) {
      case 'nautilus':
        return _service.uninstallNautilusExtension();
      case 'dolphin':
        return _service.uninstallDolphinAction();
      case 'thunar':
        return _service.uninstallThunarAction();
      default:
        return Future.value(false);
    }
  }
}

/// Family provider keyed by file-manager name.
final linuxIntegrationEnabledProvider = StateNotifierProvider.family<
    LinuxIntegrationEnabledNotifier, bool, String>((ref, fileManager) {
  final service = ref.watch(linuxIntegrationServiceProvider);
  return LinuxIntegrationEnabledNotifier(fileManager, service);
});
