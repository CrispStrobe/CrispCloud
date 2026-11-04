import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/mount_dialog_strings.dart';
import 'package:crisp_cloud/l10n/mount_error_presentation.dart';
import 'package:crisp_cloud/services/fuse_mount_service.dart';
import 'package:crisp_cloud/widgets/mount_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('German mount manager describes the missing bridge',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => showMountDialog(context),
                      child: const Text('Open'),
                    ))),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Als Laufwerk einbinden'), findsOneWidget);
    expect(find.textContaining('native Brücke'), findsOneWidget);
  });

  testWidgets('all locales provide mount controls and bridge guidance',
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) {
          final strings = MountDialogStrings(context);
          return Column(children: [
            Text(strings.text('mount')),
            Text(strings.text('bridgeMissing')),
          ]);
        }),
      ));
      expect(find.byType(Text), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('known service errors are localized and OS details preserved',
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        }),
      ));
      final bridge = localizedMountError(
          context, 'Bad state: ${FuseMountService.bridgeMissing}');
      expect(bridge, MountDialogStrings(context).text('bridgeMissing'));
      expect(localizedMountError(context, FuseMountService.linuxMissing),
          contains('sudo apt install fuse3'));
      expect(
          localizedMountError(
              context, '${FuseMountService.createFailedPrefix}OS detail-42'),
          contains('OS detail-42'));
      expect(localizedMountError(context, 'external error-42'),
          'external error-42');
    }
  });
}
