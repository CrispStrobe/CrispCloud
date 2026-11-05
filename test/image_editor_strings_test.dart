import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/image_editor_strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every application locale has a complete image editor catalog', () {
    final appLanguages = AppLocalizations.supportedLocales
        .map((locale) => locale.languageCode)
        .toSet();
    expect(ImageEditorStrings.supportedLanguageCodes, appLanguages);
    expect(ImageEditorStrings.catalog.keys.toSet(), appLanguages);
    final englishKeys = ImageEditorStrings.catalog['en']!.keys.toSet();

    for (final language in appLanguages) {
      final translations = ImageEditorStrings.catalog[language]!;
      expect(translations.keys.toSet(), englishKeys, reason: language);
      for (final entry in translations.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: '$language: ${entry.key}',
        );
        expect(
          ImageEditorStrings.forLanguage(language, entry.key),
          entry.value,
          reason: '$language: ${entry.key}',
        );
      }
    }
  });

  test('package tools and host chrome use the same locale catalog', () {
    for (final language in ImageEditorStrings.supportedLanguageCodes) {
      final i18n = ImageEditorStrings.editorI18nForLocale(Locale(language));
      String expected(String key) =>
          ImageEditorStrings.forLanguage(language, key);

      expect(i18n.cancel, expected('Cancel'));
      expect(i18n.undo, expected('Undo'));
      expect(i18n.done, expected('Apply'));
      expect(i18n.doneLoadingMsg, expected('Applying changes…'));
      expect(i18n.various.closeEditorWarningConfirmBtn, expected('Discard'));
      expect(i18n.layerInteraction.rotateScale, expected('Rotate and scale'));
      expect(i18n.paintEditor.bottomNavigationBarText, expected('Draw'));
      expect(i18n.paintEditor.changeOpacity, expected('Change opacity'));
      expect(i18n.textEditor.inputHintText, expected('Enter text'));
      expect(i18n.textEditor.cancel, expected('Cancel'));
      expect(i18n.textEditor.reset, expected('Reset'));
      expect(i18n.textEditor.fontFamilyExampleText, expected('Aa'));
      expect(
        i18n.cropRotateEditor.bottomNavigationBarText,
        expected('Crop and rotate'),
      );
      expect(i18n.cropRotateEditor.ratio, expected('Ratio'));
      expect(i18n.tuneEditor.tint, expected('Tint'));
      expect(i18n.filterEditor.bottomNavigationBarText, expected('Filters'));
      expect(i18n.filterEditor.filters.none, expected('No filter'));
      expect(i18n.filterEditor.filters.getFilterI18n('Moon'), expected('Moon'));
      expect(i18n.blurEditor.done, expected('Apply'));
      expect(i18n.emojiEditor.locale, Locale(language));
      expect(i18n.emojiEditor.categorySmileys, expected('Smileys and people'));
      expect(i18n.emojiEditor.search, expected('Search emoji'));
    }
  });

  test(
    'regional locales use their language and unsupported locales use English',
    () {
      final german = ImageEditorStrings.editorI18nForLocale(
        const Locale('de', 'CH'),
      );
      expect(german.cancel, 'Abbrechen');
      final portuguese = ImageEditorStrings.editorI18nForLocale(
        const Locale('pt', 'BR'),
      );
      expect(portuguese.textEditor.inputHintText, 'Digite o texto');
      final unknown = ImageEditorStrings.editorI18nForLocale(
        const Locale('xx'),
      );
      expect(unknown.cancel, 'Cancel');
    },
  );

  test('missing keys fail explicitly instead of leaking English defaults', () {
    expect(
      () => ImageEditorStrings.forLanguage('de', 'unmapped editor command'),
      throwsStateError,
    );
  });

  test('font examples use the script of the selected language', () {
    expect(
      ImageEditorStrings.editorI18nForLocale(const Locale('ar'))
          .textEditor
          .fontFamilyExampleText,
      'أب',
    );
    expect(
      ImageEditorStrings.editorI18nForLocale(const Locale('zh'))
          .textEditor
          .fontFamilyExampleText,
      '文字',
    );
    expect(
      ImageEditorStrings.editorI18nForLocale(const Locale('ko'))
          .textEditor
          .fontFamilyExampleText,
      '가나',
    );
  });
}
