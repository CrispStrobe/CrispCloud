import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/mount_dialog_strings.dart';
import 'package:crisp_cloud/l10n/mount_backend_strings.dart';
import 'package:crisp_cloud/l10n/mount_error_presentation.dart';
import 'package:crisp_cloud/services/fuse_mount_service.dart';
import 'package:crisp_cloud/widgets/mount_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('German mount manager describes the missing bridge', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showMountDialog(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Als Laufwerk einbinden'), findsOneWidget);
    expect(find.textContaining('native Brücke'), findsOneWidget);
  });

  testWidgets('all locales provide mount controls and bridge guidance', (
    tester,
  ) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              final strings = MountDialogStrings(context);
              final backends = MountBackendStrings(context);
              return SingleChildScrollView(child: Column(
                children: [
                  Text(strings.text('mount')),
                  Text(strings.text('bridgeMissing')),
                  Text(backends.title),
                  Text(backends.kernelWarning),
                  Text(backends.fuseTTitle),
                  Text(backends.fuseTMessage),
                  Text(backends.fuseTAccept),
                  Text(backends.rcloneHint),
                  Text(backends.rcloneMissing),
                  Text(backends.rcloneFailed),
                  for (final backend in MacFuseBackend.values)
                    Text(backends.label(backend)),
                ],
              ));
            },
          ),
        ),
      );
      expect(find.byType(Text), findsNWidgets(15));
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('known service errors are localized and OS details preserved', (
    tester,
  ) async {
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
      final bridge = localizedMountError(
        context,
        'Bad state: ${FuseMountService.bridgeMissing}',
      );
      expect(bridge, MountDialogStrings(context).text('bridgeMissing'));
      expect(localizedMountError(context, FuseMountService.rcloneMissing),
          MountBackendStrings(context).rcloneMissing);
      expect(
        localizedMountError(context, FuseMountService.linuxMissing),
        contains('sudo apt install fuse3'),
      );
      expect(
        localizedMountError(
          context,
          '${FuseMountService.createFailedPrefix}OS detail-42',
        ),
        contains('OS detail-42'),
      );
      expect(
        localizedMountError(context, 'external error-42'),
        'external error-42',
      );
    }
  });

  testWidgets('new mount failures localize app text in every language', (
    tester,
  ) async {
    const path = '/tmp/Cloud: "Fotos"';
    const detail = 'OS stderr: access denied\nline two';
    final rendered = <String, Map<String, String>>{};
    final cases = <String, Map<String, Object>>{
      'mountPointOccupied': {'path': path},
      'mountProbeFailed': {'path': path, 'error': detail},
      'helperExited': {'code': 73, 'error': detail},
      'mountNotVisible': {'path': path, 'error': detail},
    };
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
      rendered[locale.languageCode] = {};
      for (final item in cases.entries) {
        final entry = MountEntry(
          mountPoint: path,
          label: 'Cloud',
          provider: 'Test',
          remotePath: '/',
          status: MountStatus.error,
          errorMessage: 'raw service message',
          errorKey: item.key,
          errorValues: item.value,
        );
        final localized = localizedMountEntryError(context, entry);
        rendered[locale.languageCode]![item.key] = localized;
        expect(
          localized,
          contains(MountDialogStrings(context).text(item.key, item.value)),
        );
        if (item.value.containsKey('path')) expect(localized, contains(path));
        if (item.value.containsKey('code')) expect(localized, contains('73'));
        if (item.value.containsKey('error')) {
          expect(localized, endsWith('\n$detail'));
        }
      }
    }
    for (final language in rendered.keys.where((code) => code != 'en')) {
      for (final key in cases.keys) {
        expect(
          rendered[language]![key],
          isNot(rendered['en']![key]),
          reason: '$language must translate $key',
        );
      }
    }
  });
}
