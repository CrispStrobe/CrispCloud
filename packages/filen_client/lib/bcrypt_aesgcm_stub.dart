// lib/bcrypt_aesgcm_stub.dart
//
// Web / non-FFI stub for [BCryptAesGcm]. The real implementation
// (bcrypt_aesgcm.dart) imports `dart:ffi` and `dart:io`, neither of which is
// available under dart2js/dartdevc. `aes_gcm_backend.dart` selects this file
// via a conditional import when `dart.library.ffi` is absent, so the FFI
// backend is never compiled for web. `tryLoad()` returns null, so the backend
// chooser falls through to the WebCrypto-backed CryptographyBackend.

import 'dart:typed_data';

class BCryptAesGcm {
  BCryptAesGcm._();

  /// No Windows CNG bcrypt FFI on this platform (web); the chooser falls back.
  static BCryptAesGcm? tryLoad() => null;

  Uint8List encrypt(Uint8List key, Uint8List plaintext) =>
      throw UnsupportedError('BCryptAesGcm is unavailable on this platform');

  Uint8List decrypt(Uint8List key, Uint8List data) =>
      throw UnsupportedError('BCryptAesGcm is unavailable on this platform');
}
