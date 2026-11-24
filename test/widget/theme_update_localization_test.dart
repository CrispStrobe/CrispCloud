import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/theme_update_strings.dart';
import 'package:crisp_cloud/services/theme_service.dart';
import 'package:crisp_cloud/widgets/theme_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('theme and color names use the selected language', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final service = ThemeService();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: ThemePickerDialog(themeService: service)),
      ),
    );
    await tester.pumpAndSettle();
    // Dialog title and the theme row both read "Elegir tema".
    expect(find.text('Elegir tema'), findsNWidgets(2));
    expect(find.text('Color de acento'), findsOneWidget);
    expect(find.text('Predeterminado'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-accent')));
    await tester.pumpAndSettle();
    expect(find.text('Azul'), findsWidgets);
  });

  testWidgets('update label keeps its version in every language', (
    tester,
  ) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) =>
                Text(ThemeUpdateStrings(context).value('available', '1.2.3')),
          ),
        ),
      );
      expect(find.textContaining('1.2.3'), findsOneWidget);
      expect(find.textContaining('{n}'), findsNothing);
    }
  });
}
