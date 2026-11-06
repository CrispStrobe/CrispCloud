import 'dart:async';
import 'dart:ui' show Locale;

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the optional app language as a language code. Missing or invalid
/// values mean that the operating system language should be used.
class LocalePreference {
  static const key = 'app_locale_override';
  static const supported = {'en', 'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'};
  static Future<void> _writes = Future.value();

  static Future<Locale?> read({bool refresh = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (refresh) await prefs.reload();
      final stored = prefs.getString(key) ?? prefs.getString('app_locale');
      final code = stored?.split(RegExp(r'[-_]')).first;
      return code != null && supported.contains(code) ? Locale(code) : null;
    } catch (_) {
      // Preferences are optional: startup and background sync use system locale.
      return null;
    }
  }

  /// Serialize writes to preserve the user's last selection during rapid changes.
  static Future<void> write(Locale? locale) {
    _writes = _writes.catchError((_) {}).then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final code = locale?.languageCode;
        if (code == null || !supported.contains(code)) {
          // Keep an explicit system choice so an older preference cannot
          // resurrect a previously selected language during migration.
          await prefs.setString(key, 'system');
        } else {
          await prefs.setString(key, code);
        }
      } catch (_) {
        // A preference failure must not interrupt foreground use.
      }
    });
    return _writes;
  }
}
