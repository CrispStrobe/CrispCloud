import 'dart:ui';

/// Internationalization (i18n) settings for the Emoji Editor component.
class I18nEmojiEditor {
  /// Creates an instance of [I18nEmojiEditor] with customizable
  /// internationalization settings.
  ///
  /// You can provide translations and messages specifically for the Emoji
  /// Editor component of your application.
  ///
  /// Example:
  ///
  /// ```dart
  /// I18nEmojiEditor(
  ///   bottomNavigationBarText: 'Emojis',
  ///   search: 'Search',
  /// )
  /// ```
  const I18nEmojiEditor({
    this.bottomNavigationBarText = 'Emoji',
    this.search = 'Search',
    this.categoryRecent = 'Recent',
    this.categorySmileys = 'Smileys & People',
    this.categoryAnimals = 'Animals & Nature',
    this.categoryFood = 'Food & Drink',
    this.categoryActivities = 'Activities',
    this.categoryTravel = 'Travel & Places',
    this.categoryObjects = 'Objects',
    this.categorySymbols = 'Symbols',
    this.categoryFlags = 'Flags',
    this.enableSearchAutoI18n = false,
    this.locale,
  });

  /// Automatically translates emoji search terms based on the specified locale.
  ///
  /// **This increases the app size by approximately 2MB.**
  ///
  /// To optimize size, manually set an `emojiSet` in `EmojiEditorConfigs`
  /// if only a single locale is needed.
  ///
  /// If `false` and no `emojiSet` is specified, it defaults to
  /// `emojiSetEnglish`.
  ///
  /// Default: `false`
  final bool enableSearchAutoI18n;

  /// Defines the locale for selecting the appropriate language for the emoji
  /// set, affecting emoji search results.
  ///
  /// This takes effect only if `enableSearchAutoLocale` is `true` or if you
  /// manually configure an `emojiSet` in `EmojiEditorConfigs`.
  ///
  /// Supported languages: `en`, `de`, `es`, `fr`, `hi`, `it`, `ja`, `pt`,
  /// `ru`, `zh`.
  ///
  /// Default: `Localizations.localeOf(context)`
  final Locale? locale;

  /// Text for the bottom navigation bar item that opens the Emoji Editor.
  final String bottomNavigationBarText;

  /// Hint text in the search field.
  final String search;

  /// Text for the 'Recent' category in the emoji picker.
  final String categoryRecent;

  /// Text for the 'Smileys & People' category in the emoji picker.
  final String categorySmileys;

  /// Text for the 'Animals & Nature' category in the emoji picker.
  final String categoryAnimals;

  /// Text for the 'Food & Drink' category in the emoji picker.
  final String categoryFood;

  /// Text for the 'Activities' category in the emoji picker.
  final String categoryActivities;

  /// Text for the 'Travel & Places' category in the emoji picker.
  final String categoryTravel;

  /// Text for the 'Objects' category in the emoji picker.
  final String categoryObjects;

  /// Text for the 'Symbols' category in the emoji picker.
  final String categorySymbols;

  /// Text for the 'Flags' category in the emoji picker.
  final String categoryFlags;
}
