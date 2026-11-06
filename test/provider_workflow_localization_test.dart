import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/provider_workflow_strings.dart';
import 'package:crisp_cloud/services/fuse_mount_service.dart';
import 'package:crisp_cloud/services/provider_workflow_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workflow failures retain diagnostic and format contracts', () {
    const format = TransferFileFormatException(
      TransferFileCode.invalidName,
      'The server returned an invalid file name',
    );
    expect(format, isA<FormatException>());
    expect(format.message, 'The server returned an invalid file name');
    const failure = MountWorkflowFailure(
      MountWorkflowCode.mount,
      'Mount failed: diagnostic',
      cause: 'diagnostic',
    );
    expect(failure.toString(), 'Mount failed: diagnostic');
    expect(
      localizedProviderWorkflowErrorForLanguage('de', failure),
      'Einbinden fehlgeschlagen: diagnostic',
    );
    expect(
      localizedProviderWorkflowErrorForLanguage('xx', format),
      'The server returned an invalid file name.',
    );
    expect(localizedProviderWorkflowErrorForLanguage('de', 'external'), isNull);
  });

  testWidgets(
    'mount wrappers and transfer file failures translate in nine locales',
    (tester) async {
      final results = <String, Set<String>>{};
      for (final locale in AppLocalizations.supportedLocales) {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        );
        for (final code in MountWorkflowCode.values.where(
          (code) => code != MountWorkflowCode.availability,
        )) {
          final text = localizedProviderWorkflowError(
            context,
            MountWorkflowFailure(code, 'raw', cause: '/volume/{error}: denied'),
          )!;
          results.putIfAbsent(code.name, () => <String>{}).add(text);
          if ([
            MountWorkflowCode.mount,
            MountWorkflowCode.unmount,
            MountWorkflowCode.remove,
          ].contains(code)) {
            expect(text, contains('/volume/{error}: denied'));
          }
        }
        for (final code in TransferFileCode.values) {
          results
              .putIfAbsent(code.name, () => <String>{})
              .add(
                localizedProviderWorkflowError(
                  context,
                  TransferFileException(code, 'raw'),
                )!,
              );
        }
      }
      expect(results.values, everyElement(hasLength(9)));
    },
  );

  testWidgets(
    'mount entry and availability causes use existing localized service messages',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      final entry = MountEntry(
        mountPoint: '/m',
        label: 'm',
        provider: 'p',
        remotePath: '/',
        status: MountStatus.error,
      );
      expect(
        localizedProviderWorkflowError(
          context,
          MountWorkflowFailure(MountWorkflowCode.mount, 'raw', cause: entry),
        ),
        'Einbinden fehlgeschlagen: Unbekannter Fehler',
      );
      final availability = localizedProviderWorkflowError(
        context,
        const MountWorkflowFailure(
          MountWorkflowCode.availability,
          'raw',
          cause: FuseMountService.unsupportedPlatform,
        ),
      );
      expect(availability, isNot(FuseMountService.unsupportedPlatform));
      expect(availability, isNot('raw'));
    },
  );
}
