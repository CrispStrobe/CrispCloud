import 'package:crisp_cloud/main.dart' show appLockServiceProvider;
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/credential_storage_bootstrap.dart';
import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/secure_storage_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/main.dart' show appLockServiceProvider;
import 'package:crisp_cloud/providers/core_providers.dart';

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
