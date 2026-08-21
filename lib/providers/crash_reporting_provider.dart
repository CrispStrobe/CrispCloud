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
import '../services/crash_reporting_service.dart';

// ---------------------------------------------------------------------------
// crashReportingEnabledProvider
// ---------------------------------------------------------------------------

/// Persists and exposes the crash reporting opt-in toggle.
///
/// This is the canonical source of truth for the toggle. It loads its initial
/// value from SharedPreferences and writes back on every change.
final crashReportingEnabledProvider =
    StateNotifierProvider<CrashReportingEnabledNotifier, bool>(
  (ref) => CrashReportingEnabledNotifier(
    ref.watch(crashReportingServiceProvider),
  ),
);

class CrashReportingEnabledNotifier extends StateNotifier<bool> {
  final CrashReportingService _service;

  CrashReportingEnabledNotifier(this._service) : super(false) {
    _load();
  }

  Future<void> _load() async {
    await _service.initialize();
    if (mounted) state = _service.isEnabled;
  }

  /// Enable or disable crash reporting and persist the preference.
  Future<void> setEnabled(bool value) async {
    if (value) {
      await _service.enable();
    } else {
      await _service.disable();
    }
    if (mounted) state = _service.isEnabled;
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
  return CrashReportingService(backend: LocalBackend());
});
