import 'package:crisp_cloud/l10n/sync_dialog_strings.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const examples = {
    'en': 'Sync Pairs',
    'de': 'Synchronisierungspaare',
    'fr': 'Paires de synchronisation',
    'es': 'Pares de sincronización',
    'pt': 'Pares de sincronização',
    'zh': '同步配对',
    'ja': '同期ペア',
    'ko': '동기화 쌍',
    'ar': 'أزواج المزامنة',
  };

  for (final entry in examples.entries) {
    testWidgets('sync strings resolve for ${entry.key}', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: Locale(entry.key),
        supportedLocales: examples.keys.map(Locale.new).toList(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) {
          final strings = SyncDialogStrings(context);
          return Column(children: [
            Text(strings.text('pairs')),
            Text(strings.text('lastResult', {
              'up': 11,
              'down': 22,
              'conflicts': 33,
              'errors': 44,
            })),
          ]);
        }),
      ));
      expect(find.text(entry.value), findsOneWidget);
      final summary = tester.widgetList<Text>(find.byType(Text)).last.data!;
      for (final count in ['11', '22', '33', '44']) {
        expect(summary, contains(count));
      }
      expect(summary, isNot(contains('{')));
    });
  }
}
