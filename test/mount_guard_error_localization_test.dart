import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/mount_error_presentation.dart';
import 'package:crisp_cloud/l10n/mount_guard_error_strings.dart';
import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final guards = <Object>[
    StateError('Cannot mount while mounts are being shut down'),
    ArgumentError('FUSE-T requires non-commercial-use acknowledgement'),
    ArgumentError('Cloud client required'),
    UnsupportedError('rclone NFS is currently available on macOS only'),
    ArgumentError('An rclone remote such as work:documents is required'),
    StateError('Cannot remove a mount while its state is changing'),
    StateError('Cannot remove a mount that is still active'),
  ];

  test(
    'all guard errors localize in nine languages through provider dispatch',
    () {
      for (final guard in guards) {
        final original = guard.toString();
        final translations = <String>{};
        for (final locale in AppLocalizations.supportedLocales) {
          final text = localizedKnownProviderErrorForLanguage(
            locale.languageCode,
            guard,
          );
          expect(text, isNotNull);
          expect(text, isNotEmpty);
          expect(
            localizedMountGuardErrorForLanguage(locale.languageCode, original),
            text,
          );
          if (locale.languageCode != 'en') expect(text, isNot(original));
          translations.add(text!);
        }
        expect(translations, hasLength(9));
        expect(guard.toString(), original);
      }
    },
  );

  test('unknown errors and near matches preserve diagnostics', () {
    for (final error in <Object>[
      StateError('mount returned 32: /資料/path'),
      ArgumentError('custom diagnostic'),
      'Cannot remove a mount that is still active: /Volumes/Work',
    ]) {
      expect(localizedMountGuardErrorForLanguage('de', error), isNull);
      expect(localizedProviderErrorForLanguage('de', error), error.toString());
    }
    expect(
      localizedMountGuardErrorForLanguage('xx', guards[2]),
      'Cloud client required',
    );
  });

  testWidgets(
    'legacy mount presentation translates guards and retains OS details',
    (tester) async {
      for (final locale in AppLocalizations.supportedLocales) {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (context) => Column(
                children: [
                  Text(localizedMountError(context, guards[0].toString())),
                  Text(
                    localizedMountError(
                      context,
                      'mount: /資料/volume: device busy',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            localizedProviderErrorForLanguage(locale.languageCode, guards[0]),
          ),
          findsOneWidget,
        );
        expect(find.text('mount: /資料/volume: device busy'), findsOneWidget);
      }
    },
  );
}
