import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/widgets/saved_searches_dialog.dart';
import 'package:crisp_cloud/services/saved_search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('saved filter summary localizes labels and keeps values', (tester) async {
    final search = SavedSearch(
      name: 'documents', query: 'report', createdAt: DateTime(2026),
      filterByType: const ['pdf'], filterByMinSize: 1024,
      filterByDateAfter: DateTime(2026, 3, 14),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Text(
        localizedSavedSearchFilterSummary(context, search),
      )),
    ));
    expect(find.textContaining('Tipo: pdf'), findsOneWidget);
    expect(find.textContaining('Mín.'), findsOneWidget);
    expect(find.textContaining('Después:'), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
  });

  testWidgets('save search dialog follows the selected language', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: Consumer(builder: (context, ref, _) => TextButton(
          onPressed: () => showSaveSearchDialog(context, ref, query: 'report'),
          child: const Text('Show'),
        ))),
      ),
    ));
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar búsqueda'), findsOneWidget);
    expect(find.text('Nombre de esta búsqueda'), findsOneWidget);
  });
}
