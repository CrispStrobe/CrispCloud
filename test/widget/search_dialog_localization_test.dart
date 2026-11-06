import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/search_dialog_strings.dart';
import 'package:crisp_cloud/widgets/search_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('size bounds use locale-specific labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Text(
            '${SearchDialogStrings(context).text('min')} / ${SearchDialogStrings(context).text('max')}',
          ),
        ),
      ),
    );
    expect(find.text('最小 / 最大'), findsOneWidget);
  });

  testWidgets('empty search results follow the selected language', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('es'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    showSearchResultsDialog(context, ref, 'informe', [], []),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Resultados de búsqueda para «informe»'), findsOneWidget);
    expect(find.text('No se encontraron resultados.'), findsOneWidget);
  });
}
