import 'dart:convert';
import 'dart:typed_data';

import 'package:filen_client/aes_gcm_backend.dart';
import 'package:filen_client/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final crypto = FilenCrypto(aesGcm: CryptographyBackend());

  test('Filen raw, hex and base64 keys preserve the same AES-256 bytes', () async {
    const raw = '0123456789abcdefghijklmnopqrstuv';
    final key = Uint8List.fromList(utf8.encode(raw));
    final plaintext = Uint8List.fromList(utf8.encode('Filen key encoding fixture'));
    final ciphertext = await crypto.encryptData(plaintext, key);
    for (final representation in [
      raw,
      _hex(key),
      _hex(key).toUpperCase(),
      base64.encode(key),
      base64.encode(key).replaceAll('=', ''),
      base64Url.encode(key),
      base64Url.encode(key).replaceAll('=', ''),
    ]) {
      final decoded = crypto.decodeUniversalKey(representation);
      expect(decoded, key);
      expect(await crypto.decryptData(ciphertext, decoded), plaintext);
    }
    // A raw 32-character key consisting entirely of hex digits is still raw.
    const allHexRaw = '0123456789abcdef0123456789abcdef';
    expect(crypto.decodeUniversalKey(allHexRaw), utf8.encode(allHexRaw));
  });

  test('base64 and base64url special characters decode binary keys', () {
    final key = Uint8List.fromList(List.generate(32, (i) => (i * 73 + 251) & 255));
    for (final representation in [
      base64.encode(key),
      base64.encode(key).replaceAll('=', ''),
      base64Url.encode(key),
      base64Url.encode(key).replaceAll('=', ''),
      _hex(key),
    ]) {
      expect(crypto.decodeUniversalKey(representation), key);
    }
  });

  test('encoded keys with invalid byte lengths fail before cipher use', () {
    for (final length in [0, 1, 16, 24, 31, 33, 48, 64]) {
      final encoded = base64.encode(Uint8List(length));
      // Exactly 32 alphabet characters denotes Filen's raw-key format,
      // irrespective of whether that string can also be decoded as base64.
      if (encoded.length == 32) continue;
      expect(() => crypto.decodeUniversalKey(encoded), throwsFormatException);
    }
    for (final malformed in ['', '!', 'abcde', 'not a Filen file key']) {
      expect(() => crypto.decodeUniversalKey(malformed), throwsFormatException);
    }
  });

  test('every Filen backend rejects non-AES-256 keys', () async {
    final backends = [
      CryptographyBackend(),
      PointycastleBackend((length) => Uint8List(length)),
      chooseAesGcmBackend(),
    ];
    final plaintext = Uint8List.fromList([1, 2, 3]);
    final key = Uint8List(32);
    for (final backend in backends) {
      final ciphertext = await backend.encryptData(key, plaintext);
      for (final length in [0, 1, 16, 24, 31, 33, 48, 64]) {
        final invalidKey = Uint8List(length);
        await expectLater(
          backend.encryptData(invalidKey, plaintext),
          throwsArgumentError,
          reason: '${backend.name}: $length-byte encryption key',
        );
        await expectLater(
          backend.decryptData(invalidKey, ciphertext),
          throwsArgumentError,
          reason: '${backend.name}: $length-byte decryption key',
        );
      }
      for (final length in [0, 1, 12, 27]) {
        await expectLater(
          backend.decryptData(key, Uint8List(length)),
          throwsFormatException,
        );
      }
    }
  });
}
