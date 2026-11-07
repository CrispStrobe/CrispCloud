import 'package:crisp_cloud/main.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:crisp_cloud/services/secure_storage_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TemporarilyUnavailableBackend extends InMemoryWebStorageBackend {
  bool unavailable = true;

  @override
  Future<String?> getItem(String key) async {
    if (unavailable) throw StateError('Synthetic unavailable store');
    return super.getItem(key);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('new vaults reject short passwords before writing any metadata', (
    tester,
  ) async {
    final backend = InMemoryWebStorageBackend();
    final storage = WebEncryptedStorage(backend, newVaultIterations: 10);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          credentialVaultCreationProvider.overrideWith((ref) => () async {}),
        ],
        child: const MaterialApp(home: WebMasterPasswordGate()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'short');
    await tester.enterText(find.byType(TextField).last, 'short');
    await tester.tap(find.text('Create vault'));
    await tester.pumpAndSettle();
    expect(
      find.text('Use at least 8 characters for the master password.'),
      findsOneWidget,
    );
    expect(storage.isInitialized, isFalse);
    expect(await backend.allKeys(), isEmpty);
  });

  testWidgets('unreadable storage offers retry without a create prompt', (
    tester,
  ) async {
    final backend = _TemporarilyUnavailableBackend();
    final storage = WebEncryptedStorage(backend, newVaultIterations: 10);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          credentialVaultCreationProvider.overrideWith((ref) => () async {}),
        ],
        child: const MaterialApp(home: WebMasterPasswordGate()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Create vault'), findsNothing);
    expect(storage.isInitialized, isFalse);

    backend.unavailable = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Create vault'), findsOneWidget);
    expect(await backend.allKeys(), isEmpty);
  });

  testWidgets('partial existing metadata never offers to replace a vault', (
    tester,
  ) async {
    final backend = InMemoryWebStorageBackend();
    await backend.setItem('crisp_enc_salt', 'incomplete-existing-vault');
    final storage = WebEncryptedStorage(backend, newVaultIterations: 10);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(storage)],
        child: const MaterialApp(home: WebMasterPasswordGate()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Create vault'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      await backend.getItem('crisp_enc_salt'),
      'incomplete-existing-vault',
    );
    expect(await backend.getItem('crisp_enc_verify'), isNull);
    expect(storage.isInitialized, isFalse);
  });

  testWidgets(
    'startup storage failure retries without selecting a new backend',
    (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        StartupFailureApp(
          error: StateError('Synthetic unavailable selected store'),
          onRetry: () => retries++,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
      expect(find.text('Create vault'), findsNothing);
    },
  );

  testWidgets(
    'a missing vault in an existing profile never offers a replacement password',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'installation_id': 'existing-profile',
        'credential_storage_selection_v2':
            '{"version":2,"mode":"encryptedFile","customKeychainPath":null}',
      });
      final backend = InMemoryWebStorageBackend();
      final storage = WebEncryptedStorage(backend, newVaultIterations: 10);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [secureStorageProvider.overrideWithValue(storage)],
          child: const MaterialApp(home: WebMasterPasswordGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Create vault'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Create vault'), findsNothing);
      expect(storage.isInitialized, isFalse);
      expect(await backend.allKeys(), isEmpty);
      expect(
        await CredentialStorageConfig.readFileVaultCreationAllowed(),
        isFalse,
      );
    },
  );

  testWidgets(
    'a stale creation screen cannot write an empty replacement vault',
    (tester) async {
      await CredentialStorageConfig.writeSelection(
        mode: CredentialStorageMode.encryptedFile,
        createFileVault: true,
      );
      final expected = await CredentialStorageConfig.readSelection();
      final backend = InMemoryWebStorageBackend();
      final storage = WebEncryptedStorage(backend, newVaultIterations: 10);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            credentialVaultCreationProvider.overrideWith(
              (ref) =>
                  () => CredentialStorageConfig.consumeFileVaultCreation(
                    expected: expected,
                  ),
            ),
          ],
          child: const MaterialApp(home: WebMasterPasswordGate()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create vault'), findsOneWidget);
      // Another startup has already used this permission. Its later missing
      // vault must not be replaced by this still-open password form.
      await CredentialStorageConfig.consumeFileVaultCreation(
        expected: expected,
      );
      await tester.enterText(find.byType(TextField).first, 'new password');
      await tester.enterText(find.byType(TextField).last, 'new password');
      await tester.tap(find.text('Create vault'));
      await tester.pumpAndSettle();

      expect(storage.isInitialized, isFalse);
      expect(await backend.allKeys(), isEmpty);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Create vault'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Create vault'), findsNothing);
      expect(await backend.allKeys(), isEmpty);
    },
  );

  testWidgets(
    'creation authorization failures are redacted before vault unlock',
    (tester) async {
      final backend = InMemoryWebStorageBackend();
      final storage = WebEncryptedStorage(backend, newVaultIterations: 10);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            credentialVaultCreationProvider.overrideWith(
              (ref) => () async {
                throw const FormatException(
                  'private-token-and-path',
                  'secret JSON',
                );
              },
            ),
          ],
          child: const MaterialApp(home: WebMasterPasswordGate()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'new password');
      await tester.enterText(find.byType(TextField).last, 'new password');
      await tester.tap(find.text('Create vault'));
      await tester.pumpAndSettle();

      expect(find.textContaining('private-token-and-path'), findsNothing);
      expect(find.textContaining('secret JSON'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(await backend.allKeys(), isEmpty);
    },
  );

  testWidgets('first visit asks to create a vault before saving credentials', (
    tester,
  ) async {
    final storage = WebEncryptedStorage(
      InMemoryWebStorageBackend(),
      newVaultIterations: 10,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          credentialVaultCreationProvider.overrideWith((ref) => () async {}),
        ],
        child: const MaterialApp(home: WebMasterPasswordGate()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create vault'), findsOneWidget);
    expect(find.text('Confirm master password'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).obscureText,
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.visibility).first);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).obscureText,
      isFalse,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isTrue,
    );
    await tester.enterText(find.byType(TextField).first, 'password');
    await tester.enterText(find.byType(TextField).last, 'different');
    await tester.tap(find.text('Create vault'));
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(storage.isInitialized, isFalse);
  });

  testWidgets('existing vault requires its password even with no credentials', (
    tester,
  ) async {
    final backend = InMemoryWebStorageBackend();
    await WebEncryptedStorage(
      backend,
      newVaultIterations: 10,
    ).initialize('correct');
    final storage = WebEncryptedStorage(backend, newVaultIterations: 10);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(storage)],
        child: const MaterialApp(home: WebMasterPasswordGate()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.text('Confirm master password'), findsNothing);
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect master password'), findsOneWidget);
    expect(storage.isInitialized, isFalse);
  });

  testWidgets(
    'unreadable app-lock policy stays blocked after exact-password vault unlock',
    (tester) async {
      final backend = InMemoryWebStorageBackend();
      final original = WebEncryptedStorage(backend, newVaultIterations: 10);
      await original.initialize('  correct  ');
      await original.write('app_lock_enabled', 'true');
      await backend.setItem('crisp_enc_app_lock_enabled', 'damaged-ciphertext');
      final storage = WebEncryptedStorage(backend, newVaultIterations: 10);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [secureStorageProvider.overrideWithValue(storage)],
          child: const MaterialApp(home: WebMasterPasswordGate()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  correct  ');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(storage.isInitialized, isTrue);
      expect(tester.takeException(), isNull);
      expect(
        await backend.getItem('crisp_enc_app_lock_enabled'),
        'damaged-ciphertext',
      );
    },
  );

  testWidgets('an existing unlock form cannot create a replacement vault', (
    tester,
  ) async {
    final backend = InMemoryWebStorageBackend();
    await WebEncryptedStorage(
      backend,
      newVaultIterations: 10,
    ).initialize('correct');
    final storage = WebEncryptedStorage(backend, newVaultIterations: 10);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(storage)],
        child: const MaterialApp(home: WebMasterPasswordGate()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);
    for (final key in await backend.allKeys()) {
      await backend.removeItem(key);
    }

    await tester.enterText(find.byType(TextField), 'correct');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(storage.isInitialized, isFalse);
    expect(await backend.allKeys(), isEmpty);
    expect(find.text('Create vault'), findsNothing);
  });
  testWidgets('vault setup and validation follow the selected locale', (
    tester,
  ) async {
    final storage = WebEncryptedStorage(
      InMemoryWebStorageBackend(),
      newVaultIterations: 10,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          credentialVaultCreationProvider.overrideWith((ref) => () async {}),
        ],
        child: const MaterialApp(
          locale: Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: WebMasterPasswordGate(),
        ),
      ),
    );
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
