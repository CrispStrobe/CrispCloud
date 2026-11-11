import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/storage_analyzer_strings.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _placeholders(String text) =>
    RegExp(r'\{([^}]+)\}')
        .allMatches(text)
        .map((match) => match.group(1)!)
        .toList()
      ..sort();

void main() {
  final catalog = StorageAnalyzerStrings.translations;
  final english = catalog['en']!;

  test('every supported locale has an explicit analyzer catalog', () {
    expect(
      catalog.keys.toSet(),
      AppLocalizations.supportedLocales
          .map((locale) => locale.languageCode)
          .toSet(),
    );
    expect(english['queued'], 'Waiting to scan…');
  });

  for (final locale in AppLocalizations.supportedLocales) {
    final language = locale.languageCode;
    test('$language has every analyzer label and exact placeholders', () {
      final values = catalog[language]!;
      expect(values.keys.toSet(), english.keys.toSet());
      for (final entry in english.entries) {
        final translated = values[entry.key]!;
        expect(translated.trim(), isNotEmpty, reason: '$language/${entry.key}');
        expect(
          _placeholders(translated),
          _placeholders(entry.value),
          reason: '$language/${entry.key}',
        );
      }
    });
  }

  test('inserted paths and provider errors remain literal in every locale', () {
    const literal = '/folder/{files}/{error}/original.txt';
    for (final language in catalog.keys) {
      final strings = StorageAnalyzerStrings.forLanguage(language);
      final message = strings.text('snapshotFailed', {
        'error': literal,
        'files': 999,
      });
      expect(message, contains(literal), reason: language);
      expect(message, isNot(contains('999')), reason: language);
      expect(
        strings.text('typeFilter', {'type': '{type}/{error}/.txt'}),
        contains('{type}/{error}/.txt'),
        reason: language,
      );
      expect(
        strings.text('progress', {'files': 12, 'folders': 3, 'size': '4.5 MB'}),
        allOf(contains('12'), contains('3'), contains('4.5 MB')),
        reason: language,
      );
    }
  });

  test('unknown locales retain the English fallback', () {
    final fallback = StorageAnalyzerStrings.forLanguage('xx');
    expect(fallback.text('title'), english['title']);
    expect(fallback.text('queued'), english['queued']);
    expect(fallback.text('fileCount', {'count': 2}), '2 files');
  });
}
