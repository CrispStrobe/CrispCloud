import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Explicit local installation and manual grammar preference. Never downloads.
abstract final class OfficeSpacyPreferences {
  static final changes = ValueNotifier<int>(0);
  static const enabledKey = 'office_spacy_manual_enabled_v1';
  static const bundleKey = 'office_spacy_bundle_v1';
  static const libraryKey = 'office_spacy_library_v1';

  static Future<({bool enabled, String bundle, String library})> read() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(enabledKey) ?? false,
      bundle: prefs.getString(bundleKey) ?? '',
      library: prefs.getString(libraryKey) ?? '',
    );
  }

  static Future<void> write({
    required bool enabled,
    required String bundle,
    required String library,
  }) async {
    if (enabled && (bundle.isEmpty || library.isEmpty)) {
      throw ArgumentError('Choose the verified native installation first.');
    }
    final prefs = await SharedPreferences.getInstance();
    // Disable first, so a partial persistence failure never enables a worker.
    if (!await prefs.setBool(enabledKey, false) ||
        !await prefs.setString(bundleKey, bundle) ||
        !await prefs.setString(libraryKey, library) ||
        !await prefs.setBool(enabledKey, enabled)) {
      throw StateError('Could not save the optional grammar preference.');
    }
    changes.value++;
  }
}
