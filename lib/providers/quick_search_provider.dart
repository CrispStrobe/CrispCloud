// lib/providers/quick_search_provider.dart
//
// Settings for the Total Commander / Double Commander style quick search in
// the file panels:
//
//  * jump   — typing moves the cursor to the next matching entry without
//             changing the listing (Total Commander "Quick search").
//  * filter — typing narrows the visible listing to matching entries
//             (Double Commander "Quick filter").
//  * off    — typing letters does nothing (all shortcuts keep working).
//
// All options are persisted with SharedPreferences.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum QuickSearchMode {
  /// Move the cursor to matching entries; the listing stays complete.
  jump,

  /// Filter the visible listing down to matching entries.
  filter,

  /// Disable letter quick-search entirely.
  off,
}

class QuickSearchSettings {
  final QuickSearchMode mode;

  /// Prefix match (true) vs. substring match (false).
  final bool matchFromStart;
  final bool caseSensitive;

  /// Up/Down cycle through the matches while a quick search is active.
  final bool arrowNavigation;

  /// Clear the search after this many seconds of inactivity (0 = never).
  final int resetSeconds;

  const QuickSearchSettings({
    this.mode = QuickSearchMode.jump,
    this.matchFromStart = true,
    this.caseSensitive = false,
    this.arrowNavigation = true,
    this.resetSeconds = 3,
  });

  QuickSearchSettings copyWith({
    QuickSearchMode? mode,
    bool? matchFromStart,
    bool? caseSensitive,
    bool? arrowNavigation,
    int? resetSeconds,
  }) {
    return QuickSearchSettings(
      mode: mode ?? this.mode,
      matchFromStart: matchFromStart ?? this.matchFromStart,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      arrowNavigation: arrowNavigation ?? this.arrowNavigation,
      resetSeconds: resetSeconds ?? this.resetSeconds,
    );
  }
}

class QuickSearchSettingsNotifier extends StateNotifier<QuickSearchSettings> {
  QuickSearchSettingsNotifier() : super(const QuickSearchSettings()) {
    _load();
  }

  static const _modeKey = 'quick_search_mode';
  static const _fromStartKey = 'quick_search_from_start';
  static const _caseKey = 'quick_search_case_sensitive';
  static const _arrowsKey = 'quick_search_arrow_navigation';
  static const _resetKey = 'quick_search_reset_seconds';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeName = prefs.getString(_modeKey);
      final mode = QuickSearchMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => state.mode,
      );
      state = state.copyWith(
        mode: mode,
        matchFromStart: prefs.getBool(_fromStartKey) ?? state.matchFromStart,
        caseSensitive: prefs.getBool(_caseKey) ?? state.caseSensitive,
        arrowNavigation: prefs.getBool(_arrowsKey) ?? state.arrowNavigation,
        resetSeconds: prefs.getInt(_resetKey) ?? state.resetSeconds,
      );
    } catch (_) {
      // Preferences are optional; defaults are fine.
    }
  }

  Future<void> setMode(QuickSearchMode value) async {
    state = state.copyWith(mode: value);
    await _writeString(_modeKey, value.name);
  }

  Future<void> setMatchFromStart(bool value) async {
    state = state.copyWith(matchFromStart: value);
    await _writeBool(_fromStartKey, value);
  }

  Future<void> setCaseSensitive(bool value) async {
    state = state.copyWith(caseSensitive: value);
    await _writeBool(_caseKey, value);
  }

  Future<void> setArrowNavigation(bool value) async {
    state = state.copyWith(arrowNavigation: value);
    await _writeBool(_arrowsKey, value);
  }

  Future<void> setResetSeconds(int value) async {
    final clamped = value.clamp(0, 30);
    state = state.copyWith(resetSeconds: clamped);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_resetKey, clamped);
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  Future<void> _writeBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  Future<void> _writeString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {
      // Ignore persistence failures.
    }
  }
}

final quickSearchSettingsProvider =
    StateNotifierProvider<QuickSearchSettingsNotifier, QuickSearchSettings>(
  (ref) => QuickSearchSettingsNotifier(),
);
