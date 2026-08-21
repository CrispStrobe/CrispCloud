// lib/openssl_aesgcm_stub.dart
//
// Web / non-FFI stub for [OpenSslAesGcm]. The real implementation
// (openssl_aesgcm.dart) imports `dart:ffi` and `dart:io`, neither of which is
// available under dart2js/dartdevc. `aes_gcm_backend.dart` selects this file
// via a conditional import when `dart.library.ffi` is absent, so the FFI
// backend is never compiled for web. `tryLoad()` returns null, so the backend
// chooser falls through to the WebCrypto-backed CryptographyBackend.

import 'dart:typed_data';

class OpenSslAesGcm {
  OpenSslAesGcm._();

  /// No OpenSSL FFI on this platform (web); the chooser falls back.
  static OpenSslAesGcm? tryLoad() => null;

  Uint8List encrypt(Uint8List key, Uint8List plaintext) =>
      throw UnsupportedError('OpenSslAesGcm is unavailable on this platform');

  Uint8List decrypt(Uint8List key, Uint8List data) =>
      throw UnsupportedError('OpenSslAesGcm is unavailable on this platform');
}
