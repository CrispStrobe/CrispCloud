import 'package:crisp_cloud/l10n/gallery_viewer_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every gallery viewer label covers all supported app languages', () {
    expect(GalleryViewerStrings.languages.toSet(),
        {'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'});
    for (final entry in GalleryViewerStrings.translations.entries) {
      expect(entry.value.length, GalleryViewerStrings.languages.length,
          reason: entry.key);
      for (var i = 0; i < entry.value.length; i++) {
        expect(entry.value[i].trim(), isNotEmpty,
            reason: '${GalleryViewerStrings.languages[i]}: ${entry.key}');
        expect(GalleryViewerStrings.forLanguage(
            GalleryViewerStrings.languages[i], entry.key), entry.value[i]);
      }
    }
  });

  test('English and unsupported system locales retain readable labels', () {
    expect(GalleryViewerStrings.forLanguage('en', 'Fit image'), 'Fit image');
    expect(GalleryViewerStrings.forLanguage('fi', 'Fit image'), 'Fit image');
    expect(GalleryViewerStrings.forLanguage('de', 'Fit image'), 'Bild einpassen');
  });
}
