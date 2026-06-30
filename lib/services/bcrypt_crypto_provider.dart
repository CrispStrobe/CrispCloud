// lib/services/bcrypt_crypto_provider.dart
//
// WebCryptoProvider backed by Windows CNG (bcrypt.dll) over FFI. Hardware AES-GCM
// on Windows without a bundled native library. tryCreate() returns null when not
// on Windows or if the self-test fails, so the factory falls through.

import 'dart:typed_data';

import 'bcrypt_aesgcm.dart';
import 'encryption_service.dart';
import 'web_crypto_provider.dart';

class BCryptCryptoProvider implements WebCryptoProvider {
  final BCryptAesGcm _bc;
  BCryptCryptoProvider._(this._bc);

  static BCryptCryptoProvider? tryCreate() {
    final b = BCryptAesGcm.tryLoad();
    return b == null ? null : BCryptCryptoProvider._(b);
  }

  @override
  Future<Object> deriveKey(
          String password, Uint8List salt, int iterations) async =>
      EncryptionService.deriveKey(password, salt, iterations: iterations);

  @override
  Future<Object> importKey(Uint8List rawKey) async => rawKey;

  @override
  Future<Uint8List> encrypt(Object key, Uint8List plaintext) async =>
      _bc.encrypt(key as Uint8List, plaintext);

  @override
  Future<Uint8List> decrypt(Object key, Uint8List data) async =>
      _bc.decrypt(key as Uint8List, data);
}
