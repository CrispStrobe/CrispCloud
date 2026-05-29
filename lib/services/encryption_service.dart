// lib/services/encryption_service.dart
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:pointycastle/export.dart';

/// Standalone, stateless encryption utility for client-side file encryption.
/// Uses AES-256-GCM with PBKDF2 key derivation.
class EncryptionService {
  /// Derive a 256-bit key from a passphrase using PBKDF2 with HMAC-SHA256.
  static Uint8List deriveKey(String passphrase, Uint8List salt,
      {int iterations = 100000}) {
    final params = Pbkdf2Parameters(salt, iterations, 32); // 256 bits
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    kdf.init(params);
    return kdf.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  /// Generate a cryptographically secure random salt (16 bytes).
  static Uint8List generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
  }

  /// Generate a cryptographically secure random nonce (12 bytes for GCM).
  static Uint8List generateNonce() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(12, (_) => random.nextInt(256)));
  }

  /// Encrypt data with AES-256-GCM.
  ///
  /// Returns: nonce (12 bytes) + ciphertext + GCM tag (16 bytes).
  static Uint8List encrypt(Uint8List plaintext, Uint8List key) {
    final nonce = generateNonce();
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
        true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));

    final ciphertext = Uint8List(cipher.getOutputSize(plaintext.length));
    final len =
        cipher.processBytes(plaintext, 0, plaintext.length, ciphertext, 0);
    cipher.doFinal(ciphertext, len);

    // Prepend nonce: [nonce (12)] [ciphertext + tag]
    final result = Uint8List(12 + ciphertext.length);
    result.setRange(0, 12, nonce);
    result.setRange(12, result.length, ciphertext);
    return result;
  }

  /// Decrypt data encrypted with AES-256-GCM.
  ///
  /// Input: nonce (12 bytes) + ciphertext + GCM tag (16 bytes).
  /// Throws [FormatException] if data is too short.
  /// Throws on authentication failure (wrong key or tampered data).
  static Uint8List decrypt(Uint8List data, Uint8List key) {
    // Minimum: 12 (nonce) + 0 (plaintext) + 16 (tag) = 28 bytes
    if (data.length < 28) {
      throw const FormatException('Data too short for AES-GCM');
    }

    final nonce = data.sublist(0, 12);
    final ciphertextWithTag = data.sublist(12);

    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
        false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));

    final plaintext =
        Uint8List(cipher.getOutputSize(ciphertextWithTag.length));
    final len = cipher.processBytes(
        ciphertextWithTag, 0, ciphertextWithTag.length, plaintext, 0);
    cipher.doFinal(plaintext, len);

    return plaintext;
  }

  /// Encrypt a filename, returning a base64url-safe encoded string.
  static String encryptFilename(String filename, Uint8List key) {
    final encrypted = encrypt(Uint8List.fromList(utf8.encode(filename)), key);
    return base64Url.encode(encrypted);
  }

  /// Decrypt a filename previously encrypted with [encryptFilename].
  static String decryptFilename(String encryptedFilename, Uint8List key) {
    final data = base64Url.decode(encryptedFilename);
    final decrypted = decrypt(data, key);
    return utf8.decode(decrypted);
  }
}
