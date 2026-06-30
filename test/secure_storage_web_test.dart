import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/secure_storage_web.dart';

void main() {
  group('WebEncryptedStorage', () {
    late InMemoryWebStorageBackend backend;
    late WebEncryptedStorage storage;

    setUp(() {
      backend = InMemoryWebStorageBackend();
      storage = WebEncryptedStorage(backend, newVaultIterations: 1000);
    });

    test('isInitialized is false before initialize()', () {
      expect(storage.isInitialized, isFalse);
    });

    test('initialize with master password succeeds', () async {
      await storage.initialize('test-password-123');
      expect(storage.isInitialized, isTrue);
    });

    test('operations before initialize() — reads return null/false, writes throw', () async {
      // read() and containsKey() gracefully return null/false (first-time user
      // who hasn't set a master password yet — no credentials to decrypt).
      expect(await storage.read('key'), isNull);
      expect(await storage.containsKey('key'), isFalse);
      // Mutating operations require initialization and throw StateError.
      await expectLater(() => storage.write('key', 'val'), throwsStateError);
      await expectLater(() => storage.delete('key'), throwsStateError);
      await expectLater(() => storage.deleteAll(), throwsStateError);
    });

    test('write and read round-trip', () async {
      await storage.initialize('my-password');
      await storage.write('token', 'secret-value-42');
      final result = await storage.read('token');
      expect(result, 'secret-value-42');
    });

    test('read returns null for missing key', () async {
      await storage.initialize('pw');
      expect(await storage.read('nonexistent'), isNull);
    });

    test('containsKey works', () async {
      await storage.initialize('pw');
      await storage.write('k', 'v');
      expect(await storage.containsKey('k'), isTrue);
      expect(await storage.containsKey('missing'), isFalse);
    });

    test('delete removes entry', () async {
      await storage.initialize('pw');
      await storage.write('k', 'v');
      expect(await storage.read('k'), 'v');

      await storage.delete('k');
      expect(await storage.read('k'), isNull);
      expect(await storage.containsKey('k'), isFalse);
    });

    test('deleteAll clears all entries but preserves salt and verify', () async {
      await storage.initialize('pw');
      await storage.write('a', '1');
      await storage.write('b', '2');
      await storage.deleteAll();

      expect(await storage.read('a'), isNull);
      expect(await storage.read('b'), isNull);

      // Salt and verify token should still exist so re-init works.
      final keys = await backend.allKeys();
      expect(keys, contains('crisp_enc_salt'));
      expect(keys, contains('crisp_enc_verify'));
    });

    test('writeMap and readMap round-trip', () async {
      await storage.initialize('pw');
      final data = {'email': 'user@test.com', 'password': 's3cret'};
      await storage.writeMap('creds', data);
      final result = await storage.readMap('creds');
      expect(result, equals(data));
    });

    test('readMap returns null for missing key', () async {
      await storage.initialize('pw');
      expect(await storage.readMap('nope'), isNull);
    });

    test('wrong master password fails to decrypt', () async {
      // Initialize with correct password and write data.
      await storage.initialize('correct-password');
      await storage.write('secret', 'important-data');

      // Create a new storage instance with the same backend.
      final storage2 = WebEncryptedStorage(backend, newVaultIterations: 1000);

      // Attempt to initialize with wrong password — should throw.
      expect(
        () => storage2.initialize('wrong-password'),
        throwsA(isA<StateError>()),
      );
    });

    test('re-initialize with correct password succeeds', () async {
      await storage.initialize('my-pw');
      await storage.write('k', 'v');

      // Create new instance, re-initialize with same password.
      final storage2 = WebEncryptedStorage(backend, newVaultIterations: 1000);
      await storage2.initialize('my-pw');
      expect(await storage2.read('k'), 'v');
    });

    test('values are encrypted in the backing store', () async {
      await storage.initialize('pw');
      await storage.write('token', 'plain-text-secret');

      // The raw value in the backend should NOT be the plaintext.
      final raw = await backend.getItem('crisp_enc_token');
      expect(raw, isNotNull);
      expect(raw, isNot('plain-text-secret'));
    });

    test('overwrite existing key', () async {
      await storage.initialize('pw');
      await storage.write('k', 'old');
      await storage.write('k', 'new');
      expect(await storage.read('k'), 'new');
    });

    test('handles empty string values', () async {
      await storage.initialize('pw');
      await storage.write('empty', '');
      expect(await storage.read('empty'), '');
    });

    test('handles unicode values', () async {
      await storage.initialize('pw');
      const unicode = 'Hallo Welt \u{1F680} \u{00E4}\u{00F6}\u{00FC}';
      await storage.write('unicode', unicode);
      expect(await storage.read('unicode'), unicode);
    });
  });
}
