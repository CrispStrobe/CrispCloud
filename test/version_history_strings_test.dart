import 'package:crisp_cloud/l10n/version_history_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('version history messages cover all locales and preserve parameters',
      () {
    final translations = VersionHistoryStrings.translations;
    expect(translations.keys.toSet(),
        {'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'});
    final keys = translations['de']!.keys.toSet();
    for (final locale in translations.entries) {
      expect(locale.value.keys.toSet(), keys, reason: locale.key);
      for (final entry in locale.value.entries) {
        expect(entry.value, isNotEmpty, reason: '${locale.key}: ${entry.key}');
        for (final match in RegExp(r'\{[^}]+\}').allMatches(entry.key)) {
          expect(entry.value, contains(match.group(0)), reason: locale.key);
        }
      }
    }
  });

  test('localized restore confirmation preserves the date', () {
    final strings = VersionHistoryStrings.forLanguage('de');
    expect(
        strings.format(
            'This will replace the current file with the version from {date}. The current version will be preserved in the version history.',
            {'date': '2026-11-04'}),
        contains('2026-11-04'));
    expect(strings.format('Version History — {name}', {'name': 'test.txt'}),
        'Versionsverlauf — test.txt');
  });
}
