import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/credential_storage_setup.dart';
import 'package:crisp_cloud/widgets/settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LockReadFailure extends InMemorySecureStorage {
  @override
  Future<String?> read(String key) async => throw StateError('Locked store');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late InMemorySecureStorage storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = InMemorySecureStorage();
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(storage),
    ]);
  });

  tearDown(() => container.dispose());

  Future<void> showSection(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(
        body: CredentialStorageSettingsSection(),
      )),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> chooseSession(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('settings-credential-storage')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This session only'));
    await tester.pumpAndSettle();
  }

  Future<void> saveChoice(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('credential-setup-continue'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('saving session-only keeps active storage until restart', (tester) async {
    await storage.write('filen_credentials', 'original credential');
    await showSection(tester);
    await chooseSession(tester);
    await saveChoice(tester);

    expect(await CredentialStorageConfig.readMode(), CredentialStorageMode.sessionOnly);
    expect(container.read(credentialStorageModeProvider), CredentialStorageMode.systemKeychain);
    expect(container.read(credentialStoragePendingModeProvider), CredentialStorageMode.sessionOnly);
    expect(await storage.read('filen_credentials'), 'original credential');
    expect(find.textContaining('Current session: System keychain'), findsOneWidget);
    expect(find.textContaining('After restart: This session only'), findsOneWidget);
    expect(find.textContaining('original storage until restart'), findsOneWidget);
  });

  testWidgets('an enabled App Lock prevents opening the chooser', (tester) async {
    await storage.write('app_lock_salt', 'AAAAAAAAAAAAAAAAAAAAAA==');
    await storage.write('app_lock_hash', List.filled(64, 'a').join());
    await storage.write('app_lock_enabled', 'true');
    await showSection(tester);
    await tester.tap(find.byKey(const ValueKey('settings-credential-storage')));
    await tester.pumpAndSettle();

    expect(find.byType(CredentialStorageSetupPanel), findsNothing);
    expect(find.textContaining('Disable App Lock'), findsOneWidget);
    expect(await CredentialStorageConfig.readModeIfConfigured(), isNull);
  });

  testWidgets('App Lock is rechecked before saving a pending choice', (tester) async {
    await showSection(tester);
    await chooseSession(tester);
    await storage.write('app_lock_salt', 'AAAAAAAAAAAAAAAAAAAAAA==');
    await storage.write('app_lock_hash', List.filled(64, 'a').join());
    await storage.write('app_lock_enabled', 'true');
    await saveChoice(tester);

    expect(await CredentialStorageConfig.readModeIfConfigured(), isNull);
    expect(container.read(credentialStoragePendingModeProvider), isNull);
    expect(find.textContaining('Disable App Lock'), findsOneWidget);
  });

  testWidgets('an unreadable lock cannot authorize changing storage', (tester) async {
    container.dispose();
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(_LockReadFailure()),
    ]);
    await showSection(tester);
    await tester.tap(find.byKey(const ValueKey('settings-credential-storage')));
    await tester.pumpAndSettle();

    expect(find.byType(CredentialStorageSetupPanel), findsNothing);
    expect(find.textContaining('Could not verify App Lock'), findsOneWidget);
    expect(await CredentialStorageConfig.readModeIfConfigured(), isNull);
  });

  testWidgets('cancelling a choice preserves the configured backend', (tester) async {
    await CredentialStorageConfig.writeSelection(mode: CredentialStorageMode.systemKeychain);
    await showSection(tester);
    await chooseSession(tester);
    final context = tester.element(find.byType(CredentialStorageSetupPanel));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    expect(await CredentialStorageConfig.readMode(), CredentialStorageMode.systemKeychain);
    expect(container.read(credentialStoragePendingModeProvider), isNull);
  });
}
