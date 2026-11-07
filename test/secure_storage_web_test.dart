import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/secure_storage_web.dart';
import 'package:crisp_cloud/services/web_crypto_provider.dart';

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

    test('all credential operations fail closed before unlock', () async {
      await expectLater(storage.read('key'), throwsStateError);
      await expectLater(storage.containsKey('key'), throwsStateError);
      await expectLater(storage.write('key', 'val'), throwsStateError);
      await expectLater(storage.delete('key'), throwsStateError);
      await expectLater(storage.deleteAll(), throwsStateError);
      expect(await backend.allKeys(), isEmpty);
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

    test('hasVault validates new/existing state without writing', () async {
      expect(await storage.hasVault(), isFalse);
      expect(await backend.allKeys(), isEmpty);
      await storage.initialize('pw');
      final before = await _snapshot(backend);
      expect(await storage.hasVault(), isTrue);
      expect(await _snapshot(backend), before);
    });

    test('gate existence expectations are enforced before writes or derivation', () async {
      final crypto = _RecordingCrypto();
      final candidate = WebEncryptedStorage(backend,
          cryptoProvider: crypto, newVaultIterations: 1000);
      await expectLater(candidate.initialize('pw', expectedExisting: true),
          throwsStateError);
      expect(crypto.derivations, 0);
      expect(await backend.allKeys(), isEmpty);
      await candidate.initialize('pw', expectedExisting: false);
      final before = await _snapshot(backend);
      final derivations = crypto.derivations;
      await expectLater(candidate.initialize('pw', expectedExisting: false),
          throwsStateError);
      expect(crypto.derivations, derivations);
      expect(candidate.isInitialized, isFalse);
      expect(await _snapshot(backend), before);
      await candidate.initialize('pw', expectedExisting: true);
      expect(candidate.isInitialized, isTrue);
    });

    test('a failed reinitialization locks a previously unlocked handle', () async {
      await storage.initialize('correct');
      await storage.write('token', 'preserve');
      final before = await _snapshot(backend);
      await expectLater(storage.initialize('wrong'), throwsStateError);
      expect(storage.isInitialized, isFalse);
      await expectLater(storage.read('token'), throwsStateError);
      await expectLater(storage.write('token', 'overwrite'), throwsStateError);
      expect(await _snapshot(backend), before);
      await storage.initialize('correct');
      expect(await storage.read('token'), 'preserve');
    });

    test('missing verification metadata never resets a populated vault', () async {
      await storage.initialize('correct');
      await storage.write('token', 'preserve');
      await backend.removeItem('crisp_enc_verify');
      final before = await _snapshot(backend);
      await expectLater(storage.hasVault(), throwsStateError);
      await expectLater(storage.initialize('new-password'), throwsStateError);
      expect(storage.isInitialized, isFalse);
      expect(await _snapshot(backend), before);
    });

    test('credentials with all metadata missing are corruption', () async {
      await backend.setItem('crisp_enc_token', 'existing-ciphertext');
      final before = await _snapshot(backend);
      await expectLater(storage.hasVault(), throwsStateError);
      await expectLater(storage.initialize('pw'), throwsStateError);
      expect(await _snapshot(backend), before);
    });

    test('invalid metadata is rejected before deriving a key', () async {
      // Structurally valid fields from the independent legacy fixture below.
      const valid = {
        'crisp_enc_salt': 'AAECAwQFBgcICQoLDA0ODw==',
        'crisp_enc_verify':
            'AAECAwQFBgcICQoL/jyTTCdfBw7/XZ5jwBt53SL6qPz1VaakOfSSskSpKQTXlfZxrQ==',
        'crisp_enc_iterations': '100000',
      };
      final mutations = <Map<String, String>>[
        {'crisp_enc_iterations': '0'},
        {'crisp_enc_iterations': '-1'},
        {'crisp_enc_iterations': '2000001'},
        {'crisp_enc_iterations': '9999999999999999999999999'},
        {'crisp_enc_iterations': 'not-a-number'},
        {'crisp_enc_iterations': ' 100000'},
        {'crisp_enc_iterations': ''},
        {'crisp_enc_salt': base64.encode(Uint8List(15))},
        {'crisp_enc_salt': base64.encode(Uint8List(17))},
        {'crisp_enc_salt': List.filled(24, '!').join()},
        {'crisp_enc_verify': List.filled(64, '!').join()},
        {'crisp_enc_verify': ''},
      ];
      for (final mutation in mutations) {
        final candidate = InMemoryWebStorageBackend();
        for (final entry in {...valid, ...mutation}.entries) {
          await candidate.setItem(entry.key, entry.value);
        }
        final before = await _snapshot(candidate);
        final crypto = _RecordingCrypto();
        final vault = WebEncryptedStorage(candidate, cryptoProvider: crypto);
        await expectLater(vault.hasVault(), throwsStateError);
        await expectLater(vault.initialize('pw'), throwsStateError);
        expect(crypto.derivations, 0, reason: mutation.toString());
        expect(await _snapshot(candidate), before);
      }
    });

    test('new vault iteration configuration is bounded before crypto or writes', () async {
      for (final iterations in [0, -1, 2000001]) {
        final candidate = InMemoryWebStorageBackend();
        final crypto = _RecordingCrypto();
        final vault = WebEncryptedStorage(candidate,
            cryptoProvider: crypto, newVaultIterations: iterations);
        await expectLater(vault.initialize('pw'), throwsStateError);
        expect(crypto.derivations, 0);
        expect(await candidate.allKeys(), isEmpty);
      }
    });

    test('legacy iterationless fixture remains readable without rewriting it', () async {
      // Independently generated with Python cryptography PBKDF2HMAC(SHA256,
      // length=32, iterations=100000, salt=bytes(range(16))) and AESGCM.
      // Nonces are bytes(range(12)) and bytes(range(16, 28)); public test data.
      await backend.setItem('crisp_enc_salt', 'AAECAwQFBgcICQoLDA0ODw==');
      await backend.setItem('crisp_enc_verify',
          'AAECAwQFBgcICQoL/jyTTCdfBw7/XZ5jwBt53SL6qPz1VaakOfSSskSpKQTXlfZxrQ==');
      await backend.setItem('crisp_enc_token',
          'EBESExQVFhcYGRobypG7A+Qcpypw4OX3vubJiilOeUvuFH3R08tTGU53/Dz0aKgH3b9sfak=');
      final before = await _snapshot(backend);
      expect(await storage.hasVault(), isTrue);
      await storage.initialize('legacy-vault-password');
      expect(await storage.read('token'), 'independent legacy secret');
      expect(await _snapshot(backend), before);
    });

    test('new vault default remains 600000 iterations', () async {
      final crypto = _RecordingCrypto(fakeDerivation: true);
      final vault = WebEncryptedStorage(backend, cryptoProvider: crypto);
      await vault.initialize('pw');
      expect(crypto.lastIterations, 600000);
      expect(await backend.getItem('crisp_enc_iterations'), '600000');
    });

    test('metadata changes invalidate an unlocked handle before mutations', () async {
      await storage.initialize('pw');
      await storage.write('token', 'preserve');
      await backend.setItem('crisp_enc_iterations', '1001');
      final before = await _snapshot(backend);
      await expectLater(storage.write('token', 'overwrite'), throwsStateError);
      expect(storage.isInitialized, isFalse);
      expect(await _snapshot(backend), before);
    });

    test('tampered credential is an error, never absence', () async {
      await storage.initialize('pw');
      await storage.write('token', 'preserve');
      final encoded = (await backend.getItem('crisp_enc_token'))!;
      expect(encoded, startsWith('v2:'));
      final raw = base64.decode(encoded.substring(3));
      raw[raw.length - 1] ^= 1;
      await backend.setItem('crisp_enc_token', 'v2:${base64.encode(raw)}');
      final before = await _snapshot(backend);
      await expectLater(storage.read('token'), throwsStateError);
      expect(await _snapshot(backend), before);
    });

    test('independent bound-record fixture checks format and storage key', () async {
      // Python cryptography, same public PBKDF2 fixture parameters as above.
      // Plaintext: ff 43 43 56 02 || compact JSON with key then value;
      // nonce=bytes(range(32,44)). This fixture is not produced by this codec.
      await backend.setItem('crisp_enc_salt', 'AAECAwQFBgcICQoLDA0ODw==');
      await backend.setItem('crisp_enc_verify',
          'AAECAwQFBgcICQoL/jyTTCdfBw7/XZ5jwBt53SL6qPz1VaakOfSSskSpKQTXlfZxrQ==');
      const record = 'v2:ICEiIyQlJicoKSormpqheYTHHZ8Z6HXr55/ZztkxKOmAc/ETdwdJkdX4NINnl24uSXgD5X4xFsW6AgeHz21XNa8DRgCtu8T6E0jFu1XTBVSJHMOuGPXa6EhNHtdB';
      await backend.setItem('crisp_enc_token', record);
      await storage.initialize('legacy-vault-password');
      expect(await storage.read('token'), 'independent bound secret');
      await backend.setItem('crisp_enc_other', record);
      await expectLater(storage.read('other'), throwsStateError);
    });

    test('new records authenticate the requested credential key', () async {
      await storage.initialize('pw');
      await storage.write('filen', 'filen-secret');
      await storage.write('internxt', 'internxt-secret');
      final filen = (await backend.getItem('crisp_enc_filen'))!;
      final internxt = (await backend.getItem('crisp_enc_internxt'))!;
      expect(filen, startsWith('v2:'));
      await backend.setItem('crisp_enc_filen', internxt);
      await backend.setItem('crisp_enc_internxt', filen);
      final before = await _snapshot(backend);
      await expectLater(storage.read('filen'), throwsStateError);
      await expectLater(storage.read('internxt'), throwsStateError);
      expect(await _snapshot(backend), before);
    });

    test('stripping the record version cannot downgrade key binding', () async {
      await storage.initialize('pw');
      await storage.write('token', 'secret');
      final bound = (await backend.getItem('crisp_enc_token'))!;
      expect(bound, startsWith('v2:'));
      await backend.setItem('crisp_enc_token', bound.substring(3));
      await expectLater(storage.read('token'), throwsStateError);
      await backend.setItem('crisp_enc_different', bound.substring(3));
      await expectLater(storage.read('different'), throwsStateError);
    });

    test('adding a bound prefix to a legacy record is rejected', () async {
      await backend.setItem('crisp_enc_salt', 'AAECAwQFBgcICQoLDA0ODw==');
      await backend.setItem('crisp_enc_verify',
          'AAECAwQFBgcICQoL/jyTTCdfBw7/XZ5jwBt53SL6qPz1VaakOfSSskSpKQTXlfZxrQ==');
      const legacy = 'EBESExQVFhcYGRobypG7A+Qcpypw4OX3vubJiilOeUvuFH3R08tTGU53/Dz0aKgH3b9sfak=';
      await backend.setItem('crisp_enc_token', 'v2:$legacy');
      await storage.initialize('legacy-vault-password');
      await expectLater(storage.read('token'), throwsStateError);
      await backend.setItem('crisp_enc_token', legacy);
      expect(await storage.read('token'), 'independent legacy secret');
      await storage.write('token', 'rewritten and bound');
      final rewritten = (await backend.getItem('crisp_enc_token'))!;
      expect(rewritten, startsWith('v2:'));
      expect(await storage.read('token'), 'rewritten and bound');
      await backend.setItem('crisp_enc_other', rewritten);
      await expectLater(storage.read('other'), throwsStateError);
    });

    test('metadata names cannot be used as credential keys', () async {
      await storage.initialize('pw');
      final before = await _snapshot(backend);
      for (final key in ['salt', 'iterations', 'verify']) {
        await expectLater(storage.read(key), throwsArgumentError);
        await expectLater(storage.write(key, 'bad'), throwsArgumentError);
        await expectLater(storage.delete(key), throwsArgumentError);
        await expectLater(storage.containsKey(key), throwsArgumentError);
      }
      expect(await _snapshot(backend), before);
    });
  });
}

Future<Map<String, String?>> _snapshot(WebStorageBackend backend) async => {
  for (final key in await backend.allKeys()) key: await backend.getItem(key),
};

class _RecordingCrypto extends PointycastleCryptoProvider {
  _RecordingCrypto({this.fakeDerivation = false});
  final bool fakeDerivation;
  int derivations = 0;
  int? lastIterations;

  @override
  Future<Object> deriveKey(String password, Uint8List salt, int iterations) async {
    derivations++;
    lastIterations = iterations;
    if (fakeDerivation) return Uint8List(32);
    return super.deriveKey(password, salt, iterations);
  }
}
