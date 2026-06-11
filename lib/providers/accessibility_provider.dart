// lib/providers/accessibility_provider.dart
//
// Riverpod providers for the accessibility foundations:
//  - accessibilityServiceProvider  : singleton AccessibilityService
//  - highContrastProvider           : high-contrast toggle with persistence
//  - reducedMotionProvider          : reduced-motion toggle with persistence

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/accessibility_service.dart';
import '../services/log_service.dart';

// ---------------------------------------------------------------------------
// Service singleton
// ---------------------------------------------------------------------------

/// Singleton [AccessibilityService].
///
/// The service is created eagerly; it calls [AccessibilityService.initialize]
/// asynchronously so stored preferences are loaded without blocking the UI.
final accessibilityServiceProvider = Provider<AccessibilityService>((ref) {
  final svc = AccessibilityService();
  svc.initialize();
  return svc;
});

// ---------------------------------------------------------------------------
// High-contrast notifier
// ---------------------------------------------------------------------------

/// Whether high-contrast mode is enabled, persisted to [SharedPreferences].
///
/// Toggle via:
/// ```dart
/// ref.read(highContrastProvider.notifier).toggle();
/// // or
/// ref.read(highContrastProvider.notifier).setValue(true);
/// ```
final highContrastProvider =
    StateNotifierProvider<_BoolPreferenceNotifier, bool>(
  (ref) => _BoolPreferenceNotifier(
    key: 'accessibility_high_contrast',
    defaultValue: false,
  ),
);

// ---------------------------------------------------------------------------
// Reduced-motion notifier
// ---------------------------------------------------------------------------

/// Whether reduced-motion mode is enabled, persisted to [SharedPreferences].
///
/// Note: The effective reduced-motion state should also account for the
/// platform OS flag via [AccessibilityService.effectiveReducedMotion].
final reducedMotionProvider =
    StateNotifierProvider<_BoolPreferenceNotifier, bool>(
  (ref) => _BoolPreferenceNotifier(
    key: 'accessibility_reduced_motion',
    defaultValue: false,
  ),
);

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Generic [StateNotifier] for a persisted boolean preference.
class _BoolPreferenceNotifier extends StateNotifier<bool> {
  _BoolPreferenceNotifier({
    required String key,
    required bool defaultValue,
  })  : _key = key,
        super(defaultValue) {
    _load();
  }

  final String _key;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_key) ?? state;
    } catch (e) {
      // Silently ignored
    }
  }

  /// Toggle the current value.
  Future<void> toggle() => setValue(!state);

  /// Set the value explicitly and persist it.
  Future<void> setValue(bool value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (e) {
      // Silently ignored
    }
  }
}
