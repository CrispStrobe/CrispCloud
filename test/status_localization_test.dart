import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('status labels include counts and sizes in every supported language', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final strings = lookupAppLocalizations(locale);
      expect(strings.nTransfers(7), contains('7'));
      expect(strings.nItems(7), contains('7'));
      expect(strings.nPairs(7), contains('7'));
      expect(strings.lastSyncChanges(7), contains('7'));
      expect(strings.free('12 GB'), contains('12 GB'));
      expect(strings.syncing, isNotEmpty);
      expect(strings.hidden, isNotEmpty);
    }
  });
  test('Spanish status labels are translated', () {
    final strings = lookupAppLocalizations(const Locale('es'));
    expect(strings.syncing, 'Sincronizando');
    expect(strings.nItems(2), '2 elementos');
  });
}
