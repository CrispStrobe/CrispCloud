import 'package:flutter/widgets.dart' show TextDirection;

import '../embed/office_theme.dart';
import 'office_german.dart';

/// Interface language of the editor's own review, proofing and notes chrome.
///
/// Arabic follows the host's right-to-left [OfficeSurfaceConfig.textDirection]
/// (as before); German is selected by passing [OfficeStrings.german]; any
/// other configuration keeps English.
enum OfficeUiLanguage {
  english,
  german,
  arabic;

  /// Language of [config]'s host chrome.
  static OfficeUiLanguage of(OfficeSurfaceConfig config) =>
      config.textDirection == TextDirection.rtl
      ? arabic
      : identical(config.strings, OfficeStrings.german)
      ? german
      : english;

  /// [arabic] when [isArabic]; [german] when [isGerman]; else English.
  static OfficeUiLanguage from({bool arabic = false, bool german = false}) =>
      arabic
      ? OfficeUiLanguage.arabic
      : german
      ? OfficeUiLanguage.german
      : english;

  bool get isArabic => this == arabic;
  bool get isGerman => this == german;

  /// A fixed label authored as an English/Arabic pair. German comes from
  /// [officeGerman], keyed by the English text, and falls back to English
  /// so a missing entry never hides a control (a test keeps it complete).
  String label(String englishText, String arabicText) => switch (this) {
    english => englishText,
    german => officeGerman[englishText] ?? englishText,
    arabic => arabicText,
  };

  /// A phrase built from values, where each language orders them itself.
  String phrase(String englishText, String germanText, String arabicText) =>
      switch (this) {
        english => englishText,
        german => germanText,
        arabic => arabicText,
      };
}
