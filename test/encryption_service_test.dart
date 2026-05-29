import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/encryption_service.dart';

void main() {
  group('EncryptionService', () {
    // A fixed key for deterministic tests (32 bytes = 256 bits).
    late Uint8List testKey;

    setUp(() {
      final salt = EncryptionService.generateSalt();
      testKey = EncryptionService.deriveKey('test-passphrase', salt,
          iterations: 1000); // low iterations for speed in tests
    });

    // -----------------------------------------------------------------------
    // Key derivation
    // -----------------------------------------------------------------------
    group('deriveKey', () {
      test('produces 32 bytes (256 bits)', () {
        final salt = EncryptionService.generateSalt();
        final key = EncryptionService.deriveKey('password', salt,
            iterations: 1000);
        expect(key.length, 32);
      });

      test('same passphrase + salt produces same key', () {
        final salt = Uint8List.fromList(List.filled(16, 42));
        final k1 = EncryptionService.deriveKey('pass', salt, iterations: 1000);
        final k2 = EncryptionService.deriveKey('pass', salt, iterations: 1000);
        expect(k1, equals(k2));
      });

      test('different salts produce different keys', () {
        final s1 = Uint8List.fromList(List.filled(16, 1));
        final s2 = Uint8List.fromList(List.filled(16, 2));
        final k1 = EncryptionService.deriveKey('pass', s1, iterations: 1000);
        final k2 = EncryptionService.deriveKey('pass', s2, iterations: 1000);
        expect(k1, isNot(equals(k2)));
      });
    });

    // -----------------------------------------------------------------------
    // Salt generation
    // -----------------------------------------------------------------------
    test('generateSalt produces 16 bytes', () {
      final salt = EncryptionService.generateSalt();
      expect(salt.length, 16);
    });

    // -----------------------------------------------------------------------
    // Nonce generation
    // -----------------------------------------------------------------------
    test('generateNonce produces 12 bytes', () {
      final nonce = EncryptionService.generateNonce();
      expect(nonce.length, 12);
    });

    // -----------------------------------------------------------------------
    // Encrypt / Decrypt round-trip
    // -----------------------------------------------------------------------
    group('encrypt + decrypt', () {
      test('round-trips correctly for normal data', () {
        final plaintext =
            Uint8List.fromList(utf8.encode('Hello, encrypted world!'));
        final encrypted = EncryptionService.encrypt(plaintext, testKey);
        final decrypted = EncryptionService.decrypt(encrypted, testKey);
        expect(decrypted, equals(plaintext));
      });

      test('round-trips correctly for empty data', () {
        final plaintext = Uint8List(0);
        final encrypted = EncryptionService.encrypt(plaintext, testKey);
        // encrypted should be nonce (12) + tag (16) = 28 bytes minimum
        expect(encrypted.length, greaterThanOrEqualTo(28));
        final decrypted = EncryptionService.decrypt(encrypted, testKey);
        expect(decrypted, equals(plaintext));
      });

      test('round-trips correctly for large data (1 MB)', () {
        final plaintext = Uint8List(1024 * 1024); // 1 MB of zeroes
        for (var i = 0; i < plaintext.length; i++) {
          plaintext[i] = i % 256;
        }
        final encrypted = EncryptionService.encrypt(plaintext, testKey);
        final decrypted = EncryptionService.decrypt(encrypted, testKey);
        expect(decrypted, equals(plaintext));
      });

      test('different nonces produce different ciphertexts', () {
        final plaintext = Uint8List.fromList(utf8.encode('same content'));
        final e1 = EncryptionService.encrypt(plaintext, testKey);
        final e2 = EncryptionService.encrypt(plaintext, testKey);
        // Both decrypt to the same plaintext
        expect(EncryptionService.decrypt(e1, testKey), equals(plaintext));
        expect(EncryptionService.decrypt(e2, testKey), equals(plaintext));
        // But the ciphertext bytes differ (different random nonces)
        expect(e1, isNot(equals(e2)));
      });

      test('wrong key fails to decrypt', () {
        final plaintext = Uint8List.fromList(utf8.encode('secret'));
        final encrypted = EncryptionService.encrypt(plaintext, testKey);

        final wrongKey = Uint8List(32); // all zeroes
        expect(
          () => EncryptionService.decrypt(encrypted, wrongKey),
          throwsA(anything),
        );
      });

      test('data too short throws FormatException', () {
        expect(
          () => EncryptionService.decrypt(Uint8List(10), testKey),
          throwsA(isA<FormatException>()),
        );
      });
    });

    // -----------------------------------------------------------------------
    // Filename encryption
    // -----------------------------------------------------------------------
    group('filename encryption', () {
      test('round-trips correctly', () {
        const filename = 'my_document.pdf';
        final encrypted =
            EncryptionService.encryptFilename(filename, testKey);
        final decrypted =
            EncryptionService.decryptFilename(encrypted, testKey);
        expect(decrypted, equals(filename));
      });

      test('encrypted filename is base64url safe', () {
        const filename = 'report 2024 (final).xlsx';
        final encrypted =
            EncryptionService.encryptFilename(filename, testKey);
        // base64url uses only [A-Za-z0-9_-=]
        expect(encrypted, matches(RegExp(r'^[A-Za-z0-9_=-]+$')));
      });

      test('encrypted filename differs from original', () {
        const filename = 'test.txt';
        final encrypted =
            EncryptionService.encryptFilename(filename, testKey);
        expect(encrypted, isNot(equals(filename)));
      });
    });
  });
}
