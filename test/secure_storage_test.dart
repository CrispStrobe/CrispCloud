import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

class _PersistentTestStorage extends InMemorySecureStorage {
  bool ignoreWrites = false;
  bool failWrites = false;

  @override
  bool get isPersistent => true;

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Synthetic storage failure');
    if (!ignoreWrites) await super.write(key, value);
  }
}

void main() {
  group('InMemorySecureStorage', () {
    late InMemorySecureStorage storage;

    setUp(() {
      storage = InMemorySecureStorage();
    });

    test('read returns null for missing key', () async {
      expect(await storage.read('nope'), isNull);
    });

    test('write and read round-trip', () async {
      await storage.write('key1', 'value1');
      expect(await storage.read('key1'), 'value1');
    });

    test('containsKey returns true after write', () async {
      await storage.write('k', 'v');
      expect(await storage.containsKey('k'), isTrue);
      expect(await storage.containsKey('missing'), isFalse);
    });

    test('delete removes key', () async {
      await storage.write('k', 'v');
      await storage.delete('k');
      expect(await storage.read('k'), isNull);
      expect(await storage.containsKey('k'), isFalse);
    });

    test('deleteAll clears everything', () async {
      await storage.write('a', '1');
      await storage.write('b', '2');
      await storage.deleteAll();
      expect(await storage.read('a'), isNull);
      expect(await storage.read('b'), isNull);
    });

    test('writeMap and readMap round-trip', () async {
      final data = {'email': 'user@test.com', 'password': 'secret'};
      await storage.writeMap('creds', data);
      final result = await storage.readMap('creds');
      expect(result, equals(data));
    });

    test('readMap returns null for missing key', () async {
      expect(await storage.readMap('nope'), isNull);
    });

    test('readMap returns null for invalid JSON', () async {
      await storage.write('bad', 'not-json');
      expect(await storage.readMap('bad'), isNull);
    });

    test('overwrite existing key', () async {
      await storage.write('k', 'old');
      await storage.write('k', 'new');
      expect(await storage.read('k'), 'new');
    });
  });

  group('CredentialMigration', () {
    late _PersistentTestStorage secure;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      secure = _PersistentTestStorage();
    });

    test('migrates credentials from SharedPreferences', () async {
      // Pre-populate SharedPreferences with plaintext creds
      SharedPreferences.setMockInitialValues({
        'filen_credentials': '{"email":"user@filen.io","apiKey":"abc"}',
        'sftp_credentials': '{"host":"example.com","username":"root"}',
        'webdav_credentials': '{"url":"https://dav.test","username":"admin"}',
      });

      await CredentialMigration.migrateIfNeeded(secure);

      // Verify credentials are in secure storage
      final filen = await secure.readMap('filen_credentials');
      expect(filen, isNotNull);
      expect(filen!['email'], 'user@filen.io');

      final sftp = await secure.readMap('sftp_credentials');
      expect(sftp, isNotNull);
      expect(sftp!['host'], 'example.com');

      final webdav = await secure.readMap('webdav_credentials');
      expect(webdav, isNotNull);
      expect(webdav!['url'], 'https://dav.test');

      // Verify old keys removed from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('filen_credentials'), isNull);
      expect(prefs.getString('sftp_credentials'), isNull);
      expect(prefs.getString('webdav_credentials'), isNull);
    });

    test('is idempotent — does not re-migrate', () async {
      SharedPreferences.setMockInitialValues({
        'filen_credentials': '{"email":"original@test.com"}',
      });

      await CredentialMigration.migrateIfNeeded(secure);

      // Manually change secure storage to verify it's not overwritten
      await secure.writeMap('filen_credentials', {'email': 'changed@test.com'});

      // Second migration should be a no-op
      await CredentialMigration.migrateIfNeeded(secure);

      final creds = await secure.readMap('filen_credentials');
      expect(creds!['email'], 'changed@test.com');
    });

    test('handles empty SharedPreferences gracefully', () async {
      await CredentialMigration.migrateIfNeeded(secure);
      expect(await secure.readMap('filen_credentials'), isNull);
    });

    test('session-only mode leaves saved credentials and marker untouched', () async {
      const key = 'filen_credentials';
      const raw = '{"email":"persisted@example.test"}';
      SharedPreferences.setMockInitialValues({key: raw});
      final ephemeral = InMemorySecureStorage();

      await CredentialMigration.migrateIfNeeded(ephemeral);

      expect(ephemeral.isPersistent, isFalse);
      expect(await ephemeral.read(key), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), raw);
      expect(prefs.containsKey('secure_storage_migration_v1'), isFalse);

      // Choosing a persistent store later can still complete migration.
      await CredentialMigration.migrateIfNeeded(secure);
      expect(await secure.read(key), raw);
      expect(prefs.containsKey(key), isFalse);
      expect(prefs.getBool('secure_storage_migration_v1'), isTrue);
    });

    test('an existing secure login wins without deleting the legacy copy', () async {
      const key = 'filen_credentials';
      const legacy = '{"email":"old@example.test"}';
      const current = '{"email":"current@example.test"}';
      SharedPreferences.setMockInitialValues({key: legacy});
      await secure.write(key, current);

      await CredentialMigration.migrateIfNeeded(secure);

      expect(await secure.read(key), current);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), legacy);
      expect(prefs.getBool('secure_storage_migration_v1'), isNot(true));
    });

    test('an identical verified secure copy permits legacy cleanup', () async {
      const key = 'filen_credentials';
      const raw = '{"email":"same@example.test"}';
      SharedPreferences.setMockInitialValues({key: raw});
      await secure.write(key, raw);
      secure.failWrites = true;

      await CredentialMigration.migrateIfNeeded(secure);

      expect(await secure.read(key), raw);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(key), isFalse);
    });

    for (final failure in ['drop', 'throw']) {
      test('a $failure write keeps the durable legacy copy and retries', () async {
        const key = 'filen_credentials';
        const raw = '{"email":"preserved@example.test"}';
        SharedPreferences.setMockInitialValues({key: raw});
        secure.ignoreWrites = failure == 'drop';
        secure.failWrites = failure == 'throw';

        await expectLater(
          CredentialMigration.migrateIfNeeded(secure),
          throwsStateError,
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(key), raw);
        expect(prefs.getBool('secure_storage_migration_v1'), isNot(true));
        secure.ignoreWrites = false;
        secure.failWrites = false;
        await CredentialMigration.migrateIfNeeded(secure);
        expect(await secure.read(key), raw);
        expect(prefs.containsKey(key), isFalse);
      });
    }
  });
}
