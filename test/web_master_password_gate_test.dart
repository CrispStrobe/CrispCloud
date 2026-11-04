import 'package:crisp_cloud/main.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/secure_storage_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first visit asks to create a vault before saving credentials',
      (tester) async {
    final storage = WebEncryptedStorage(InMemoryWebStorageBackend(),
        newVaultIterations: 10);
    await tester.pumpWidget(ProviderScope(
      overrides: [secureStorageProvider.overrideWithValue(storage)],
      child: const MaterialApp(home: WebMasterPasswordGate()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Create vault'), findsOneWidget);
    expect(find.text('Confirm master password'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'password');
    await tester.enterText(find.byType(TextField).last, 'different');
    await tester.tap(find.text('Create vault'));
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(storage.isInitialized, isFalse);
  });

  testWidgets('existing vault requires its password even with no credentials',
      (tester) async {
    final backend = InMemoryWebStorageBackend();
    await WebEncryptedStorage(backend, newVaultIterations: 10)
        .initialize('correct');
    final storage = WebEncryptedStorage(backend, newVaultIterations: 10);
    await tester.pumpWidget(ProviderScope(
      overrides: [secureStorageProvider.overrideWithValue(storage)],
      child: const MaterialApp(home: WebMasterPasswordGate()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.text('Confirm master password'), findsNothing);
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect master password'), findsOneWidget);
    expect(storage.isInitialized, isFalse);
  });
  testWidgets('vault setup and validation follow the selected locale',
      (tester) async {
    final storage = WebEncryptedStorage(InMemoryWebStorageBackend(),
        newVaultIterations: 10);
    await tester.pumpWidget(ProviderScope(
      overrides: [secureStorageProvider.overrideWithValue(storage)],
      child: const MaterialApp(
        locale: Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: WebMasterPasswordGate(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Tresor erstellen'), findsOneWidget);
    expect(find.text('Master-Passwort bestätigen'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'password');
    await tester.enterText(find.byType(TextField).last, 'different');
    await tester.ensureVisible(find.text('Tresor erstellen'));
    await tester.tap(find.text('Tresor erstellen'));
    await tester.pump();
    expect(find.text('Die Passwörter stimmen nicht überein'), findsOneWidget);
  });
}
