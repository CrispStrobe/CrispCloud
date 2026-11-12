import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/path_favorites_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'path favorite controls have translations in every supported language',
    () {
      const keys = [
        'title',
        'manage',
        'add',
        'edit',
        'new',
        'empty',
        'filter',
        'noMatches',
        'path',
        'source',
        'unbound',
        'bind',
        'collection',
        'up',
        'down',
        'invalidName',
        'invalidPath',
        'duplicate',
        'folderRequired',
        'sourceChanged',
        'sourceFixed',
      ];
      const english = PathFavoritesStrings.forLanguage('en');
      for (final locale in AppLocalizations.supportedLocales) {
        final strings = PathFavoritesStrings.forLanguage(locale.languageCode);
        for (final key in keys) {
          expect(
            strings.text(key),
            isNotEmpty,
            reason: '${locale.languageCode}/$key',
          );
          expect(strings.text(key), isNot(key));
          if (locale.languageCode != 'en') {
            expect(
              strings.text(key),
              isNot(english.text(key)),
              reason: '${locale.languageCode}/$key',
            );
          }
        }
      }
    },
  );
}
