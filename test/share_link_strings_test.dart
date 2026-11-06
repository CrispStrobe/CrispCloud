import 'package:crisp_cloud/l10n/share_link_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all share link translations contain each message and placeholder', () {
    final translations = ShareLinkStrings.translations;
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

  test('expiry labels use locale-specific singular and plural forms', () {
    expect(ShareLinkStrings.forLanguage('en').expires(1), 'Expires in 1 day');
    expect(
        ShareLinkStrings.forLanguage('de').expires(7), 'Läuft in 7 Tagen ab');
    expect(ShareLinkStrings.forLanguage('ar').duration(1), 'يوم واحد');
    expect(ShareLinkStrings.forLanguage('ar').duration(2), 'يومان');
    expect(ShareLinkStrings.forLanguage('ar').duration(7), '7 أيام');
    expect(ShareLinkStrings.forLanguage('ja').expires(3), '3 日後に期限切れ');
  });

  test('provider errors retain their relevant details', () {
    final strings = ShareLinkStrings.forLanguage('es');
    expect(strings.failure('Dropbox', 403, 'denied'),
        'Error al compartir con Dropbox (HTTP 403): denied');
  });
}
