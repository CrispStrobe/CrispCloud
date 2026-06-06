// lib/providers/analytics_provider.dart
//
// Riverpod providers for AnalyticsService.
//
// Usage:
//   // Read the toggle state:
//   final enabled = ref.watch(analyticsEnabledProvider);
//
//   // Toggle it:
//   await ref.read(analyticsEnabledProvider.notifier).setEnabled(true);
//
//   // Access the service directly:
//   final service = ref.read(analyticsServiceProvider);
//   service.trackFeatureUsage('file_preview');
//
//   // Read aggregate stats:
//   final summary = await ref.read(usageSummaryProvider.future);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/analytics_service.dart';
import '../services/log_service.dart';

export '../services/analytics_service.dart'
    show
        AnalyticsEvent,
        EventCategory,
        UsageSummary,
        AnalyticsService,
        AnalyticsBackend,
        LocalBackend,
        RemoteBackend;

// ---------------------------------------------------------------------------
// analyticsEnabledProvider
// ---------------------------------------------------------------------------

/// Persists and exposes the analytics opt-in toggle.
///
/// This is the canonical source of truth for the toggle. It loads its initial
/// value from SharedPreferences and writes back on every change.
final analyticsEnabledProvider =
    StateNotifierProvider<AnalyticsEnabledNotifier, bool>(
  (ref) => AnalyticsEnabledNotifier(ref),
);

class AnalyticsEnabledNotifier extends StateNotifier<bool> {
  static const _log = Log('AnalyticsEnabledNotifier');
  static const _key = 'analytics_enabled';

  final Ref _ref;

  AnalyticsEnabledNotifier(this._ref) : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_key) ?? false;
    } catch (e) {
      _log.warn('Failed to load analytics_enabled', e);
    }
  }

  /// Enable or disable analytics and persist the preference.
  Future<void> setEnabled(bool value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (e) {
      _log.warn('Failed to save analytics_enabled', e);
    }

    // Propagate to the service instance.
    try {
      final service = _ref.read(analyticsServiceProvider);
      await service.setEnabled(value);
    } catch (_) {
      // Service may not be initialized yet.
    }
  }

  /// Toggle the current state.
  Future<void> toggle() => setEnabled(!state);
}

// ---------------------------------------------------------------------------
// analyticsServiceProvider
// ---------------------------------------------------------------------------

/// Singleton [AnalyticsService] instance.
///
/// The service is created lazily. Call [initialize()] once in app startup:
///
/// ```dart
/// await ref.read(analyticsServiceProvider).initialize();
/// ```
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final service = AnalyticsService(backend: LocalBackend());

  // Sync the enabled state whenever the toggle changes.
  ref.listen<bool>(analyticsEnabledProvider, (previous, next) async {
    await service.setEnabled(next);
  });

  return service;
});

// ---------------------------------------------------------------------------
// usageSummaryProvider
// ---------------------------------------------------------------------------

/// Async provider that computes and returns the current [UsageSummary].
///
/// Re-evaluates whenever [analyticsServiceProvider] changes.
final usageSummaryProvider = FutureProvider<UsageSummary>((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  return service.getUsageSummary();
});
