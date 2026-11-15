import 'package:crisp_cloud/services/app_legal_notices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/screens/about_dialog.dart';

void main() {
  test('source links resolve to this app and the reported revision', () {
    expect(
      appSourceUrl('6fcc4497'),
      'https://github.com/CrispStrobe/CrispCloud/tree/6fcc4497',
    );
    expect(appSourceUrl(''), 'https://github.com/CrispStrobe/CrispCloud');
    expect(
      appSourceUrl('../other'),
      'https://github.com/CrispStrobe/CrispCloud',
    );
  });
  testWidgets(
    'About exposes the central trademark notice through its licence page',
    (tester) async {
      LicenseRegistry.reset();
      addTearDown(LicenseRegistry.reset);
      registerAppLegalNotices();
      final entries = await LicenseRegistry.licenses.toList();
      expect(entries.single.packages, contains('CrispCloud'));
      expect(
        entries.single.paragraphs.map((p) => p.text).join('\n'),
        contains('GNU AFFERO GENERAL PUBLIC LICENSE'),
      );
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AboutAppDialog()),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text('View Open Source Licenses');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(
        tester
            .widget<LicensePage>(find.byType(LicensePage))
            .applicationLegalese,
        appLegalNotice,
      );
    },
  );
}
