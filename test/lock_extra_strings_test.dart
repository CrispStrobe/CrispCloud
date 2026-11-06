import 'package:crisp_cloud/l10n/lock_extra_strings.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in [
    'en',
    'de',
    'fr',
    'es',
    'pt',
    'ar',
    'ja',
    'ko',
    'zh'
  ]) {
    testWidgets('biometric method is interpolated for $language',
        (tester) async {
      late LockExtraStrings strings;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        supportedLocales: [Locale(language)],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) {
          strings = LockExtraStrings(context);
          return const SizedBox();
        }),
      ));
      for (final value in [
        strings.useOrPin('Face ID'),
        strings.unlockWith('Face ID'),
        strings.alternative('Face ID')
      ]) {
        expect(value, contains('Face ID'));
        expect(value, isNot(contains('{method}')));
      }
      expect(strings.minLengthError, isNotEmpty);
      expect(strings.incorrectCurrent, isNotEmpty);
    });
  }
}
