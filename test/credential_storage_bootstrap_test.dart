import 'package:crisp_cloud/services/credential_storage_bootstrap.dart';
import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a failed configured keychain never opens a different backend', () async {
    var fileOpens = 0;
    var migrations = 0;
    final bootstrap = CredentialStorageBootstrap(
      openKeychain: (_) async => throw StateError('Synthetic locked keychain'),
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
  });

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

  test('a locked file vault is returned without reading or migrating secrets', () async {
    final storage = InMemorySecureStorage();
    final bootstrap = CredentialStorageBootstrap(
      openKeychain: (_) async => throw StateError('Unexpected keychain fallback'),
      openFileVault: () async => storage,
      migrate: (_) async => throw StateError('Must unlock before migrating'),
    );

    final selected = await bootstrap.open(mode: CredentialStorageMode.encryptedFile);

    expect(selected.storage, same(storage));
    expect(selected.mode, CredentialStorageMode.encryptedFile);
    expect(selected.requiresUnlock, isTrue);
  });

  test('session-only mode opens no persistent backend or migration path', () async {
    final bootstrap = CredentialStorageBootstrap(
      openKeychain: (_) async => throw StateError('Unexpected keychain access'),
      openFileVault: () async => throw StateError('Unexpected file access'),
      migrate: (_) async => throw StateError('Unexpected migration'),
    );

    final first = await bootstrap.open(mode: CredentialStorageMode.sessionOnly);
    await first.storage.write('filen_credentials', 'session secret');
    final restarted = await bootstrap.open(mode: CredentialStorageMode.sessionOnly);

    expect(first.storage.isPersistent, isFalse);
    expect(first.requiresUnlock, isFalse);
    expect(restarted.mode, CredentialStorageMode.sessionOnly);
    expect(await restarted.storage.read('filen_credentials'), isNull);
  });
}
