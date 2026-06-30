// lib/services/cryptography_crypto_provider.dart
//
// Native WebCryptoProvider backed by package:cryptography's AES-256-GCM. On its
// own it's pure-Dart (~7-9 MB/s — ~8x faster than pointycastle's ~1 MB/s); when
// the app calls FlutterCryptography.enable() (cryptography_flutter), AesGcm
// delegates to the platform's hardware-accelerated crypto (Android Keystore,
// Apple CryptoKit) for ~1000 MB/s. Selected on native by the conditional-import
// factory; the web build uses WebCryptoSubtleProvider instead.
//
// Wire format matches the other providers exactly — AES-256-GCM,
// [nonce(12) | ciphertext | tag(16)] — and AES-GCM is standardized, so this
// decrypts data written by the pointycastle path (existing files stay readable).

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'encryption_service.dart';
import 'web_crypto_provider.dart';

class CryptographyCryptoProvider implements WebCryptoProvider {
  CryptographyCryptoProvider();

  // Resolved from Cryptography.instance, so FlutterCryptography.enable() (called
  // in main) makes this the hardware-backed implementation on devices.
  final AesGcm _algo = AesGcm.with256bits();

  @override
  Future<Object> deriveKey(
      String password, Uint8List salt, int iterations) async {
    // PBKDF2-HMAC-SHA256 is standardized; reuse the proven pointycastle KDF so
    // the derived bytes match existing vaults, then wrap as a SecretKey.
    final bytes =
        EncryptionService.deriveKey(password, salt, iterations: iterations);
    return _algo.newSecretKeyFromBytes(bytes);
  }

  @override
  Future<Object> importKey(Uint8List rawKey) async =>
      _algo.newSecretKeyFromBytes(rawKey);

  @override
  Future<Uint8List> encrypt(Object key, Uint8List plaintext) async {
    final nonce = _algo.newNonce(); // 12 bytes
    final box = await _algo.encrypt(plaintext,
        secretKey: key as SecretKey, nonce: nonce);
    final ct = box.cipherText;
    final mac = box.mac.bytes; // 16-byte GCM tag
    final out = Uint8List(12 + ct.length + mac.length);
    out.setRange(0, 12, nonce);
    out.setRange(12, 12 + ct.length, ct);
    out.setRange(12 + ct.length, out.length, mac);
    return out;
  }

  @override
  Future<Uint8List> decrypt(Object key, Uint8List data) async {
    if (data.length < 28) {
      throw const FormatException('Data too short for AES-GCM');
    }
    final nonce = data.sublist(0, 12);
    final ct = data.sublist(12, data.length - 16);
    final mac = data.sublist(data.length - 16);
    final clear = await _algo.decrypt(
      SecretBox(ct, nonce: nonce, mac: Mac(mac)),
      secretKey: key as SecretKey,
    );
    return Uint8List.fromList(clear);
  }
}
