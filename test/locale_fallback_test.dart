import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';

void main() {
  testWidgets('unsupported system languages fall back to English',
      (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('it');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: Builder(
          builder: (context) => Text(AppLocalizations.of(context)!.settings)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Arabic remains available when selected', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
          builder: (context) => Text(AppLocalizations.of(context)!.settings)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('الإعدادات'), findsOneWidget);
  });
}
