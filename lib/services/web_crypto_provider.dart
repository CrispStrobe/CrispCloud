// lib/services/web_crypto_provider.dart
//
// Pluggable crypto backend for WebEncryptedStorage so the on-web path can use
// the browser's native WebCrypto (crypto.subtle) — fast PBKDF2 at SOTA
// iteration counts AND a NON-EXTRACTABLE key (the raw key never lives in
// JS-readable memory) — while the Dart VM / native fallback keeps using the
// pure-Dart pointycastle implementation (so tests run without a browser).
//
// All three operations are async (WebCrypto is Promise-based). The key is an
// opaque handle: a Uint8List for pointycastle, a non-extractable CryptoKey for
// WebCrypto — callers must not inspect it.
//
// Wire format is identical across providers (and byte-compatible with the
// previous direct-EncryptionService path): AES-256-GCM, output is
// [nonce(12) | ciphertext | tag(16)]. PBKDF2-HMAC-SHA256 is standardized, so a
// key derived by one provider decrypts data written by the other for the same
// (password, salt, iterations) — which is what lets existing 100k-iteration
// data keep decrypting after the cutover.

import 'dart:typed_data';

import 'encryption_service.dart';

/// Crypto backend abstraction. Implementations: [PointycastleCryptoProvider]
/// (pure Dart, cross-platform, used in tests + native fallback) and the
/// web-only WebCrypto provider (selected by the conditional-import factory).
abstract class WebCryptoProvider {
  /// Derive an opaque AES-256-GCM key from [password]/[salt]/[iterations].
  Future<Object> deriveKey(String password, Uint8List salt, int iterations);

  /// AES-256-GCM encrypt. Returns [nonce(12) | ciphertext | tag(16)].
  Future<Uint8List> encrypt(Object key, Uint8List plaintext);

  /// AES-256-GCM decrypt of [nonce(12) | ciphertext | tag(16)].
  Future<Uint8List> decrypt(Object key, Uint8List data);
}

/// Pure-Dart provider backed by [EncryptionService] (pointycastle). Works
/// everywhere including the Dart VM, so unit tests exercise the storage logic
/// without a browser. The derived key is a raw [Uint8List] (extractable).
class PointycastleCryptoProvider implements WebCryptoProvider {
  const PointycastleCryptoProvider();

  @override
  Future<Object> deriveKey(
          String password, Uint8List salt, int iterations) async =>
      EncryptionService.deriveKey(password, salt, iterations: iterations);

  @override
  Future<Uint8List> encrypt(Object key, Uint8List plaintext) async =>
      EncryptionService.encrypt(plaintext, key as Uint8List);

  @override
  Future<Uint8List> decrypt(Object key, Uint8List data) async =>
      EncryptionService.decrypt(data, key as Uint8List);
}
