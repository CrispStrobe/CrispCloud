// lib/services/web_crypto_factory_io.dart
//
// Default WebCryptoProvider for non-web targets (Dart VM, native). Used by the
// conditional import in secure_storage_web.dart so unit tests and native builds
// compile without dart:js_interop. WebEncryptedStorage is only instantiated on
// web, so this provider is effectively a no-op there — but tests construct it
// to exercise the storage logic with real (pointycastle) crypto.

import 'cryptography_crypto_provider.dart';
import 'openssl_crypto_provider.dart';
import 'web_crypto_provider.dart';

// Native crypto backend, best-available first (all standardized AES-256-GCM, so
// byte-interoperable with existing files):
//   1. OS OpenSSL libcrypto via FFI (Linux always; desktop where present) —
//      AES-NI hardware, ~1280 MB/s, no bundled native library.
//   2. CryptographyCryptoProvider — package:cryptography, which is
//      hardware-accelerated on Android/iOS/macOS when FlutterCryptography is
//      enabled (Keystore/CryptoKit), and pure-Dart elsewhere.
// The web build uses WebCryptoSubtleProvider instead (see *_web.dart).
WebCryptoProvider defaultWebCryptoProvider() {
  final openssl = OpenSslCryptoProvider.tryCreate();
  if (openssl != null) return openssl;
  return CryptographyCryptoProvider();
}
