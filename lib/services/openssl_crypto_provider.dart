// lib/services/openssl_crypto_provider.dart
//
// WebCryptoProvider backed by the OS's OpenSSL libcrypto over FFI (see
// openssl_aesgcm.dart). Hardware-accelerated bulk AES-GCM on Linux (and any
// desktop where libcrypto is present) without bundling a native library.
// tryCreate() returns null when libcrypto isn't available, so the factory falls
// back to webcrypto / package:cryptography.

import 'dart:typed_data';

import 'encryption_service.dart';
import 'openssl_aesgcm.dart';
import 'web_crypto_provider.dart';

class OpenSslCryptoProvider implements WebCryptoProvider {
  final OpenSslAesGcm _ossl;
  OpenSslCryptoProvider._(this._ossl);

  /// Returns a provider if the OS libcrypto loads + passes a self-test, else null.
  static OpenSslCryptoProvider? tryCreate() {
    final o = OpenSslAesGcm.tryLoad();
    return o == null ? null : OpenSslCryptoProvider._(o);
  }

  // The OpenSSL provider is used for bulk file crypto; the (web-only) storage
  // key derivation never reaches it. Reuse the standardized pointycastle PBKDF2
  // for completeness — the opaque key is the raw 32-byte Uint8List.
  @override
  Future<Object> deriveKey(
          String password, Uint8List salt, int iterations) async =>
      EncryptionService.deriveKey(password, salt, iterations: iterations);

  @override
  Future<Object> importKey(Uint8List rawKey) async => rawKey;

  @override
  Future<Uint8List> encrypt(Object key, Uint8List plaintext) async =>
      _ossl.encrypt(key as Uint8List, plaintext);

  @override
  Future<Uint8List> decrypt(Object key, Uint8List data) async =>
      _ossl.decrypt(key as Uint8List, data);
}
