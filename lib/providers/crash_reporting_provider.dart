// lib/providers/crash_reporting_provider.dart
//
// Riverpod providers for crash reporting.
//
// Usage:
//   // Read the toggle state:
//   final enabled = ref.watch(crashReportingEnabledProvider);
//
//   // Toggle it:
//   await ref.read(crashReportingEnabledProvider.notifier).setEnabled(true);
//
//   // Access the service directly:
//   final service = ref.read(crashReportingServiceProvider);
//   await service.reportError(error, stackTrace);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/crash_reporting_service.dart';
import '../services/log_service.dart';

// ---------------------------------------------------------------------------
// crashReportingEnabledProvider
// ---------------------------------------------------------------------------

/// Persists and exposes the crash reporting opt-in toggle.
///
/// This is the canonical source of truth for the toggle. It loads its initial
/// value from SharedPreferences and writes back on every change.
final crashReportingEnabledProvider =
    StateNotifierProvider<CrashReportingEnabledNotifier, bool>(
  (ref) => CrashReportingEnabledNotifier(),
);

class CrashReportingEnabledNotifier extends StateNotifier<bool> {
  static final _log = Log('CrashReportingEnabledNotifier');
  static const _key = 'crash_reporting_enabled';

  CrashReportingEnabledNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_key) ?? false;
    } catch (e) {
      _log.warn('Failed to load crash_reporting_enabled', e);
    }
  }

  /// Enable or disable crash reporting and persist the preference.
  Future<void> setEnabled(bool value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (e) {
      _log.warn('Failed to save crash_reporting_enabled', e);
    }

    // Propagate to the service instance if it exists
    try {
      final container = ProviderContainer();
      final service = container.read(crashReportingServiceProvider);
      if (value) {
        await service.enable();
      } else {
        await service.disable();
      }
      container.dispose();
    } catch (_) {
      // Service may not be initialized yet; the service reads from prefs on init.
    }
  }

  /// Toggle the current state.
  Future<void> toggle() => setEnabled(!state);
}

// ---------------------------------------------------------------------------
// crashReportingServiceProvider
// ---------------------------------------------------------------------------

/// Singleton [CrashReportingService] instance.
///
/// The service is created eagerly but [initialize()] is not called
/// automatically — call it once in app startup (e.g. main.dart):
///
/// ```dart
/// await ref.read(crashReportingServiceProvider).initialize();
/// ```
final crashReportingServiceProvider = Provider<CrashReportingService>((ref) {
  final service = CrashReportingService(backend: LocalBackend());
  // Sync the service state when the toggle changes.
  ref.listen<bool>(crashReportingEnabledProvider, (previous, next) async {
    if (next) {
      await service.enable();
    } else {
      await service.disable();
    }
  });
  return service;
});
