// lib/services/encryption_service.dart
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:bip39/bip39.dart' as bip39;
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

    final output = Uint8List(cipher.getOutputSize(plaintext.length));
    var offset = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
    offset += cipher.doFinal(output, offset);

    // Prepend nonce: [nonce (12)] [ciphertext + tag (offset bytes)]
    final result = Uint8List(12 + offset);
    result.setRange(0, 12, nonce);
    result.setRange(12, 12 + offset, output);
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

    final output = Uint8List(cipher.getOutputSize(ciphertextWithTag.length));
    var offset = cipher.processBytes(
        ciphertextWithTag, 0, ciphertextWithTag.length, output, 0);
    offset += cipher.doFinal(output, offset);

    // Return only the actual plaintext bytes (offset may be < output.length)
    return Uint8List.fromList(output.sublist(0, offset));
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

  // ---------------------------------------------------------------------------
  // Key Management — export, import, BIP39 mnemonic backup
  // ---------------------------------------------------------------------------

  /// Export a raw encryption key as a hex string.
  static String exportKeyAsHex(Uint8List key) {
    return key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Import a raw encryption key from a hex string.
  /// Throws [FormatException] if the hex string is invalid or not 32 bytes.
  static Uint8List importKeyFromHex(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (clean.length != 64) {
      throw FormatException(
          'Key must be 64 hex characters (32 bytes), got ${clean.length}');
    }
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(clean)) {
      throw const FormatException('Key contains invalid hex characters');
    }
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Generate a BIP39 mnemonic phrase (24 words) that encodes the key.
  ///
  /// The key (32 bytes = 256 bits) maps directly to a 24-word mnemonic.
  /// The salt is prepended so recovery only requires the mnemonic.
  ///
  /// Returns a map with 'mnemonic' (24 words) and 'salt' (hex string).
  static Map<String, String> generateMnemonic(Uint8List key, Uint8List salt) {
    // BIP39 with 256 bits of entropy → 24-word mnemonic
    final mnemonic = bip39.entropyToMnemonic(exportKeyAsHex(key));
    return {
      'mnemonic': mnemonic,
      'salt': exportKeyAsHex(salt),
    };
  }

  /// Recover an encryption key from a BIP39 mnemonic phrase.
  ///
  /// Returns the 32-byte key, or throws if the mnemonic is invalid.
  static Uint8List recoverKeyFromMnemonic(String mnemonic) {
    final clean = mnemonic.trim().toLowerCase();
    if (!bip39.validateMnemonic(clean)) {
      throw const FormatException('Invalid BIP39 mnemonic phrase');
    }
    final entropyHex = bip39.mnemonicToEntropy(clean);
    return importKeyFromHex(entropyHex);
  }

  /// Export key + salt as a single backup bundle (JSON string).
  ///
  /// Contains the mnemonic, salt (hex), and a verification hash so recovery
  /// can confirm the key is correct before use.
  static String exportBackupBundle(Uint8List key, Uint8List salt) {
    final mnemonicData = generateMnemonic(key, salt);
    // Create a verification token: encrypt a known string with the key
    final verifyPlain = Uint8List.fromList(utf8.encode('CrispCloud-verify'));
    final verifyEnc = encrypt(verifyPlain, key);
    return json.encode({
      'version': 1,
      'mnemonic': mnemonicData['mnemonic'],
      'salt': mnemonicData['salt'],
      'verify': base64Url.encode(verifyEnc),
    });
  }

  /// Import and verify a backup bundle. Returns {'key': Uint8List, 'salt': Uint8List}.
  ///
  /// Throws if the mnemonic is invalid or the verification check fails.
  static Map<String, Uint8List> importBackupBundle(String bundleJson) {
    final data = json.decode(bundleJson) as Map<String, dynamic>;
    final mnemonic = data['mnemonic'] as String;
    final saltHex = data['salt'] as String;
    final verifyB64 = data['verify'] as String?;

    final key = recoverKeyFromMnemonic(mnemonic);
    final salt = importKeyFromHex(saltHex);

    // Verify if token is present
    if (verifyB64 != null) {
      try {
        final verifyEnc = base64Url.decode(verifyB64);
        final decrypted = decrypt(verifyEnc, key);
        final text = utf8.decode(decrypted);
        if (text != 'CrispCloud-verify') {
          throw const FormatException('Key verification failed');
        }
      } catch (e) {
        if (e is FormatException) rethrow;
        throw const FormatException(
            'Key verification failed — mnemonic may be incorrect');
      }
    }

    return {'key': key, 'salt': salt};
  }
}
