import 'dart:async';

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

class _DelayedLockRead extends InMemorySecureStorage {
  bool delayNextPolicyRead = false;
  bool waiting = false;
  final release = Completer<void>();

  @override
  Future<String?> read(String key) async {
    if (key == 'app_lock_enabled' && delayNextPolicyRead) {
      delayNextPolicyRead = false;
      waiting = true;
      await release.future;
    }
    return super.read(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late InMemorySecureStorage storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = InMemorySecureStorage();
    container = ProviderContainer(
      overrides: [secureStorageProvider.overrideWithValue(storage)],
    );
  });

  tearDown(() => container.dispose());

  Future<void> showSection(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: CredentialStorageSettingsSection()),
        ),
      ),
    );
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

  testWidgets('saving session-only keeps active storage until restart', (
    tester,
  ) async {
    await storage.write('filen_credentials', 'original credential');
    await showSection(tester);
    await chooseSession(tester);
    await saveChoice(tester);

    expect(
      await CredentialStorageConfig.readMode(),
      CredentialStorageMode.sessionOnly,
    );
    expect(
      container.read(credentialStorageModeProvider),
      CredentialStorageMode.systemKeychain,
    );
    expect(
      container.read(credentialStoragePendingModeProvider),
      CredentialStorageMode.sessionOnly,
    );
    expect(await storage.read('filen_credentials'), 'original credential');
    expect(
      find.textContaining('Current session: System keychain'),
      findsOneWidget,
    );
    expect(
      find.textContaining('After restart: This session only'),
      findsOneWidget,
    );
    expect(
      find.textContaining('original storage until restart'),
      findsOneWidget,
    );
  });

  testWidgets('an enabled App Lock prevents opening the chooser', (
    tester,
  ) async {
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

  testWidgets(
    'an authenticated switch authorizes one deferred file vault creation',
    (tester) async {
      await CredentialStorageConfig.writeSelection(
        mode: CredentialStorageMode.systemKeychain,
      );
      await showSection(tester);
      await tester.tap(
        find.byKey(const ValueKey('settings-credential-storage')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encrypted file (master password)'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await saveChoice(tester);

      final selection = await CredentialStorageConfig.readSelection();
      expect(selection.mode, CredentialStorageMode.encryptedFile);
      expect(selection.createFileVault, isTrue);
      expect(
        container.read(credentialStorageModeProvider),
        CredentialStorageMode.systemKeychain,
      );
    },
  );

  testWidgets(
    'reconfirming an existing file vault does not authorize replacement',
    (tester) async {
      await CredentialStorageConfig.writeSelection(
        mode: CredentialStorageMode.encryptedFile,
      );
      container.read(credentialStorageModeProvider.notifier).state =
          CredentialStorageMode.encryptedFile;
      await showSection(tester);
      await tester.tap(
        find.byKey(const ValueKey('settings-credential-storage')),
      );
      await tester.pumpAndSettle();
      await saveChoice(tester);

      final selection = await CredentialStorageConfig.readSelection();
      expect(selection.mode, CredentialStorageMode.encryptedFile);
      expect(selection.createFileVault, isFalse);
    },
  );

  testWidgets(
    'cancelling a pending switch back to the active vault does not grant recreation',
    (tester) async {
      await CredentialStorageConfig.writeSelection(
        mode: CredentialStorageMode.encryptedFile,
      );
      container.read(credentialStorageModeProvider.notifier).state =
          CredentialStorageMode.encryptedFile;
      await showSection(tester);
      await chooseSession(tester);
      await saveChoice(tester);
      expect(
        container.read(credentialStoragePendingModeProvider),
        CredentialStorageMode.sessionOnly,
      );

      await tester.tap(
        find.byKey(const ValueKey('settings-credential-storage')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encrypted file (master password)'));
      await tester.pumpAndSettle();
      await saveChoice(tester);

      final selection = await CredentialStorageConfig.readSelection();
      expect(selection.mode, CredentialStorageMode.encryptedFile);
      expect(selection.createFileVault, isFalse);
      expect(container.read(credentialStoragePendingModeProvider), isNull);
    },
  );

  testWidgets('App Lock is rechecked before saving a pending choice', (
    tester,
  ) async {
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

  testWidgets(
    'another storage change cannot start while a saved choice is being verified',
    (tester) async {
      final delayed = _DelayedLockRead();
      container.dispose();
      container = ProviderContainer(
        overrides: [secureStorageProvider.overrideWithValue(delayed)],
      );
      await showSection(tester);
      await chooseSession(tester);
      delayed.delayNextPolicyRead = true;
      await saveChoice(tester);
      expect(delayed.waiting, isTrue);
      expect(find.byType(CredentialStorageSetupPanel), findsNothing);
      expect(await CredentialStorageConfig.readModeIfConfigured(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('settings-credential-storage')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CredentialStorageSetupPanel), findsNothing);

      delayed.release.complete();
      await tester.pumpAndSettle();
      expect(
        await CredentialStorageConfig.readMode(),
        CredentialStorageMode.sessionOnly,
      );
      expect(
        container.read(credentialStoragePendingModeProvider),
        CredentialStorageMode.sessionOnly,
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-credential-storage')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CredentialStorageSetupPanel), findsOneWidget);
    },
  );

  testWidgets('an unreadable lock cannot authorize changing storage', (
    tester,
  ) async {
    container.dispose();
    container = ProviderContainer(
      overrides: [secureStorageProvider.overrideWithValue(_LockReadFailure())],
    );
    await showSection(tester);
    await tester.tap(find.byKey(const ValueKey('settings-credential-storage')));
    await tester.pumpAndSettle();

    expect(find.byType(CredentialStorageSetupPanel), findsNothing);
    expect(find.textContaining('Could not verify App Lock'), findsOneWidget);
    expect(await CredentialStorageConfig.readModeIfConfigured(), isNull);
  });

  testWidgets('cancelling a choice preserves the configured backend', (
    tester,
  ) async {
    await CredentialStorageConfig.writeSelection(
      mode: CredentialStorageMode.systemKeychain,
    );
    await showSection(tester);
    await chooseSession(tester);
    final context = tester.element(find.byType(CredentialStorageSetupPanel));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    expect(
      await CredentialStorageConfig.readMode(),
      CredentialStorageMode.systemKeychain,
    );
    expect(container.read(credentialStoragePendingModeProvider), isNull);
  });
}
