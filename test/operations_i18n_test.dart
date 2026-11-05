import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/operations_strings.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/providers/transfer_provider.dart';
import 'package:crisp_cloud/widgets/operations_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('operation translations preserve keys and parameters', () {
    final translations = OperationsStrings.translations;
    expect(translations.keys.toSet(),
        {'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'});
    final keys = translations['de']!.keys.toSet();
    for (final locale in translations.entries) {
      expect(locale.value.keys.toSet(), keys, reason: locale.key);
      for (final entry in locale.value.entries) {
        expect(entry.value, isNotEmpty, reason: '${locale.key}: ${entry.key}');
        for (final match in RegExp(r'\{[^}]+\}').allMatches(entry.key)) {
          expect(entry.value, contains(match.group(0)), reason: locale.key);
        }
      }
    }
    final de = OperationsStrings.forLanguage('de');
    expect(de.eta(15), 'Noch 15 Sek.');
    expect(de.eta(125), 'Noch 2 Min. 5 Sek.');
    expect(de.eta(3660), 'Noch 1 Std. 1 Min.');
    expect(OperationsStrings.forLanguage('ja').eta(15), '残り 15 秒');
  });

  testWidgets('operation panel displays translated controls', (tester) async {
    final operation = OperationProgress(
      id: 'example',
      type: OperationType.upload,
      sourcePath: '/a',
      targetPath: '/b',
      fileName: 'test.txt',
      totalBytes: 100,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        transferProvider.overrideWith(
            (ref) => TransferNotifier(ref)..operations.add(operation)),
      ],
      child: const MaterialApp(
        locale: Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: OperationsPanel()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Vorgänge: 1'), findsOneWidget);
    expect(
        find.byTooltip('Alle aktiven Übertragungen abbrechen'), findsOneWidget);
    expect(find.byTooltip('Pausieren'), findsOneWidget);
  });
}
