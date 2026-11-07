import 'package:crisp_cloud/main.dart' show appLockServiceProvider;
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/credential_storage_bootstrap.dart';
import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/secure_storage_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PersistentTestStorage extends InMemorySecureStorage {
  @override
  bool get isPersistent => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a failed configured keychain never opens a different backend',
    () async {
      var fileOpens = 0;
      var migrations = 0;
      final bootstrap = CredentialStorageBootstrap(
        openKeychain: (_) async =>
            throw StateError('Synthetic locked keychain'),
        openFileVault: () async {
          fileOpens++;
          return InMemorySecureStorage();
        },
        migrate: (_) async {
          migrations++;
        },
      );

      await expectLater(
        bootstrap.open(mode: CredentialStorageMode.systemKeychain),
        throwsStateError,
      );
      expect(fileOpens, 0);
      expect(migrations, 0);
    },
  );

  test('a custom keychain is opened explicitly before migration', () async {
    final storage = InMemorySecureStorage();
    final operations = <String>[];
    final bootstrap = CredentialStorageBootstrap(
      openKeychain: (path) async {
        operations.add('open:$path');
        return storage;
      },
      openFileVault: () async => throw StateError('Unexpected file fallback'),
      migrate: (opened) async {
        expect(opened, same(storage));
        operations.add('migrate');
      },
    );

    final selected = await bootstrap.open(
      mode: CredentialStorageMode.systemKeychain,
      customKeychainPath: '/synthetic/selected.keychain-db',
    );

    expect(operations, ['open:/synthetic/selected.keychain-db', 'migrate']);
    expect(selected.storage, same(storage));
    expect(selected.mode, CredentialStorageMode.systemKeychain);
    expect(selected.requiresUnlock, isFalse);
  });

  test(
    'a locked file vault is returned without reading or migrating secrets',
    () async {
      final storage = InMemorySecureStorage();
      final bootstrap = CredentialStorageBootstrap(
        openKeychain: (_) async =>
            throw StateError('Unexpected keychain fallback'),
        openFileVault: () async => storage,
        migrate: (_) async => throw StateError('Must unlock before migrating'),
      );

      final selected = await bootstrap.open(
        mode: CredentialStorageMode.encryptedFile,
      );

      expect(selected.storage, same(storage));
      expect(selected.mode, CredentialStorageMode.encryptedFile);
      expect(selected.requiresUnlock, isTrue);
    },
  );

  test(
    'session-only mode opens no persistent backend or migration path',
    () async {
      final bootstrap = CredentialStorageBootstrap(
        openKeychain: (_) async =>
            throw StateError('Unexpected keychain access'),
        openFileVault: () async => throw StateError('Unexpected file access'),
        migrate: (_) async => throw StateError('Unexpected migration'),
      );

      final first = await bootstrap.open(
        mode: CredentialStorageMode.sessionOnly,
      );
      await first.storage.write('filen_credentials', 'session secret');
      final restarted = await bootstrap.open(
        mode: CredentialStorageMode.sessionOnly,
      );

      expect(first.storage.isPersistent, isFalse);
      expect(first.requiresUnlock, isFalse);
      expect(restarted.mode, CredentialStorageMode.sessionOnly);
      expect(await restarted.storage.read('filen_credentials'), isNull);
    },
  );

  test('first-run unlocked file storage migrates before bypassing the password gate', () async {
    final storage = WebEncryptedStorage(
      InMemoryWebStorageBackend(),
      newVaultIterations: 10,
    );
    await storage.initialize(
      '  exact password bytes  ',
      expectedExisting: false,
    );
    var migrated = false;
    final bootstrap = CredentialStorageBootstrap(
      openKeychain: (_) async => throw StateError('Unexpected keychain access'),
      openFileVault: () async => storage,
      migrate: (opened) async {
        expect(opened, same(storage));
        expect(storage.isInitialized, isTrue);
        migrated = true;
      },
    );

    final selected = await bootstrap.open(
      mode: CredentialStorageMode.encryptedFile,
    );

    expect(migrated, isTrue);
    expect(selected.requiresUnlock, isFalse);
  });

  test(
    'first-run unlocked file storage cannot bypass a failed migration',
    () async {
      final storage = WebEncryptedStorage(
        InMemoryWebStorageBackend(),
        newVaultIterations: 10,
      );
      await storage.initialize('password', expectedExisting: false);
      final bootstrap = CredentialStorageBootstrap(
        openKeychain: (_) async =>
            throw StateError('Unexpected keychain access'),
        openFileVault: () async => storage,
        migrate: (_) async => throw StateError('Synthetic migration failure'),
      );

      await expectLater(
        bootstrap.open(mode: CredentialStorageMode.encryptedFile),
        throwsStateError,
      );
    },
  );

  test(
    'immediate creation requires both an explicit grant and its consumer',
    () async {
      var opens = 0;
      final bootstrap = CredentialStorageBootstrap(
        openKeychain: (_) async =>
            throw StateError('Unexpected keychain access'),
        openFileVault: () async {
          opens++;
          return InMemorySecureStorage();
        },
        migrate: (_) async => throw StateError('Unexpected migration'),
      );
      for (final granted in [false, true]) {
        await expectLater(
          bootstrap.open(
            mode: CredentialStorageMode.encryptedFile,
            createFileVault: granted,
            createFileVaultImmediately: true,
          ),
          throwsA(isA<CredentialStorageUnavailable>()),
        );
      }
      await expectLater(
        bootstrap.open(
          mode: CredentialStorageMode.encryptedFile,
          createFileVaultImmediately: true,
          consumeFileVaultCreation: () async {},
        ),
        throwsA(isA<CredentialStorageUnavailable>()),
      );
      expect(opens, 0);
    },
  );

  test(
    'first-run creation consumes durable permission before any vault write',
    () async {
      await CredentialStorageConfig.writeSelection(
        mode: CredentialStorageMode.encryptedFile,
        createFileVault: true,
      );
      final expected = await CredentialStorageConfig.readSelection();
      final backend = InMemoryWebStorageBackend();
      final storage = WebEncryptedStorage(backend, newVaultIterations: 10);
      final operations = <String>[];
      final bootstrap = CredentialStorageBootstrap(
        openKeychain: (_) async =>
            throw StateError('Unexpected keychain access'),
        openFileVault: () async {
          expect(
            await CredentialStorageConfig.readFileVaultCreationAllowed(),
            isFalse,
          );
          expect(await backend.allKeys(), isEmpty);
          operations.add('create');
          await storage.initialize(
            'public fixture password',
            expectedExisting: false,
          );
          return storage;
        },
        migrate: (_) async {
          expect(storage.isInitialized, isTrue);
          operations.add('migrate');
        },
      );
      final opened = await bootstrap.open(
        mode: CredentialStorageMode.encryptedFile,
        createFileVault: true,
        createFileVaultImmediately: true,
        consumeFileVaultCreation: () async {
          await CredentialStorageConfig.consumeFileVaultCreation(
            expected: expected,
          );
          operations.add('consume');
        },
      );
      expect(operations, ['consume', 'create', 'migrate']);
      expect(opened.requiresUnlock, isFalse);
      expect(opened.createFileVault, isFalse);
      expect(opened.consumeFileVaultCreation, isNull);
    },
  );

  test(
    'failed authorization consumption invokes neither creator nor migration',
    () async {
      var opens = 0;
      final bootstrap = CredentialStorageBootstrap(
        openKeychain: (_) async =>
            throw StateError('Unexpected keychain access'),
        openFileVault: () async {
          opens++;
          return InMemorySecureStorage();
        },
        migrate: (_) async => throw StateError('Unexpected migration'),
      );
      await expectLater(
        bootstrap.open(
          mode: CredentialStorageMode.encryptedFile,
          createFileVault: true,
          createFileVaultImmediately: true,
          consumeFileVaultCreation: () async =>
              throw StateError('Synthetic rejected consumption'),
        ),
        throwsStateError,
      );
      expect(opens, 0);
    },
  );

  test('failed creation never restores permission after restart', () async {
    await CredentialStorageConfig.writeSelection(
      mode: CredentialStorageMode.encryptedFile,
      createFileVault: true,
    );
    final expected = await CredentialStorageConfig.readSelection();
    final backend = InMemoryWebStorageBackend();
    var creates = 0;
    final bootstrap = CredentialStorageBootstrap(
      openKeychain: (_) async => throw StateError('Unexpected keychain access'),
      openFileVault: () async {
        creates++;
        throw StateError('Synthetic creation failure before commit');
      },
      migrate: (_) async => throw StateError('Unexpected migration'),
    );
    Future<void> consume() =>
        CredentialStorageConfig.consumeFileVaultCreation(expected: expected);
    await expectLater(
      bootstrap.open(
        mode: CredentialStorageMode.encryptedFile,
        createFileVault: true,
        createFileVaultImmediately: true,
        consumeFileVaultCreation: consume,
      ),
      throwsStateError,
    );
    expect(
      await CredentialStorageConfig.readFileVaultCreationAllowed(),
      isFalse,
    );
    await expectLater(
      bootstrap.open(
        mode: CredentialStorageMode.encryptedFile,
        createFileVault: true,
        createFileVaultImmediately: true,
        consumeFileVaultCreation: consume,
      ),
      throwsStateError,
    );
    expect(creates, 1);

    final restarted = await CredentialStorageBootstrap(
      openKeychain: (_) async => throw StateError('Unexpected keychain access'),
      openFileVault: () async =>
          WebEncryptedStorage(backend, newVaultIterations: 10),
      migrate: (_) async => throw StateError('Unexpected migration'),
    ).open(mode: CredentialStorageMode.encryptedFile);
    expect(restarted.requiresUnlock, isTrue);
    expect(restarted.createFileVault, isFalse);
    expect(restarted.consumeFileVaultCreation, isNull);
    expect(await backend.allKeys(), isEmpty);
  });

  test(
    'a deferred gate receives only a still-pending grant without spending it',
    () async {
      var consumed = false;
      Future<void> consume() async {
        consumed = true;
      }

      final storage = WebEncryptedStorage(
        InMemoryWebStorageBackend(),
        newVaultIterations: 10,
      );
      final opened =
          await CredentialStorageBootstrap(
            openKeychain: (_) async =>
                throw StateError('Unexpected keychain access'),
            openFileVault: () async => storage,
            migrate: (_) async => throw StateError('Unexpected migration'),
          ).open(
            mode: CredentialStorageMode.encryptedFile,
            createFileVault: true,
            consumeFileVaultCreation: consume,
          );
      expect(opened.requiresUnlock, isTrue);
      expect(opened.createFileVault, isTrue);
      expect(opened.consumeFileVaultCreation, same(consume));
      expect(consumed, isFalse);
      expect(await storage.hasVault(), isFalse);
    },
  );

  test('an existing unlocked vault retires unused creation intent before migration', () async {
    final storage = WebEncryptedStorage(
      InMemoryWebStorageBackend(),
      newVaultIterations: 10,
    );
    await storage.initialize(
      'public fixture password',
      expectedExisting: false,
    );
    final operations = <String>[];
    final opened =
        await CredentialStorageBootstrap(
          openKeychain: (_) async =>
              throw StateError('Unexpected keychain access'),
          openFileVault: () async => storage,
          migrate: (_) async {
            operations.add('migrate');
          },
        ).open(
          mode: CredentialStorageMode.encryptedFile,
          createFileVault: true,
          consumeFileVaultCreation: () async {
            operations.add('consume');
          },
        );
    expect(operations, ['consume', 'migrate']);
    expect(opened.createFileVault, isFalse);
    expect(opened.consumeFileVaultCreation, isNull);
  });

  test(
    'a stale startup cannot recreate a later-deleted protected vault',
    () async {
      await CredentialStorageConfig.writeSelection(
        mode: CredentialStorageMode.encryptedFile,
        createFileVault: true,
      );
      final stale = await CredentialStorageConfig.readSelection();
      final backend = InMemoryWebStorageBackend();
      final storage = WebEncryptedStorage(backend, newVaultIterations: 10);
      await CredentialStorageConfig.consumeFileVaultCreation(expected: stale);
      await storage.initialize('original password', expectedExisting: false);
      await storage.write('app_lock_enabled', 'true');
      await storage.write('app_lock_hash', 'public fixture original lock');
      // Models a missing selected file, not a request to reset the old profile.
      for (final key in await backend.allKeys()) {
        await backend.removeItem(key);
      }
      var creations = 0;
      final staleStartup = CredentialStorageBootstrap(
        openKeychain: (_) async =>
            throw StateError('Unexpected keychain access'),
        openFileVault: () async {
          creations++;
          final replacement = WebEncryptedStorage(
            backend,
            newVaultIterations: 10,
          );
          await replacement.initialize(
            'replacement password',
            expectedExisting: false,
          );
          return replacement;
        },
        migrate: (_) async => throw StateError('Must not expose old profile'),
      );
      await expectLater(
        staleStartup.open(
          mode: CredentialStorageMode.encryptedFile,
          createFileVault: true,
          createFileVaultImmediately: true,
          consumeFileVaultCreation: () =>
              CredentialStorageConfig.consumeFileVaultCreation(expected: stale),
        ),
        throwsStateError,
      );
      expect(creations, 0);
      expect(await backend.allKeys(), isEmpty);
    },
  );

  test('persisted pending selection blocks App Lock even without a UI notification', () async {
    final storage = _PersistentTestStorage();
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        credentialStorageModeProvider.overrideWith(
          (ref) => CredentialStorageMode.systemKeychain,
        ),
      ],
    );
    addTearDown(container.dispose);
    final lock = container.read(appLockServiceProvider);
    // Models a committed setting whose acknowledgement failed, or a setting
    // changed by another process. This container has no pending-mode update.
    await CredentialStorageConfig.writeSelection(
      mode: CredentialStorageMode.encryptedFile,
    );
    expect(container.read(credentialStoragePendingModeProvider), isNull);

    await expectLater(lock.setup('fixture code'), throwsStateError);

    expect(await storage.containsKey('app_lock_hash'), isFalse);
    expect(await storage.containsKey('app_lock_salt'), isFalse);
    expect(await storage.containsKey('app_lock_enabled'), isFalse);
  });

  test(
    'unreadable persisted selection cannot authorize App Lock setup',
    () async {
      final storage = _PersistentTestStorage();
      final container = ProviderContainer(
        overrides: [secureStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('credential_storage_selection_v2', 'invalid-json');

      await expectLater(
        container.read(appLockServiceProvider).setup('fixture code'),
        throwsFormatException,
      );

      expect(await storage.containsKey('app_lock_hash'), isFalse);
      expect(await storage.containsKey('app_lock_salt'), isFalse);
      expect(await storage.containsKey('app_lock_enabled'), isFalse);
    },
  );
}
