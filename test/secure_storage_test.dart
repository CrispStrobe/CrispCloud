import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

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
    late InMemorySecureStorage secure;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      secure = InMemorySecureStorage();
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
  });
}
