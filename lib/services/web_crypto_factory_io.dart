// lib/services/web_crypto_factory_io.dart
//
// Default WebCryptoProvider for non-web targets (Dart VM, native). Used by the
// conditional import in secure_storage_web.dart so unit tests and native builds
// compile without dart:js_interop. WebEncryptedStorage is only instantiated on
// web, so this provider is effectively a no-op there — but tests construct it
// to exercise the storage logic with real (pointycastle) crypto.

import 'bcrypt_crypto_provider.dart';
import 'cryptography_crypto_provider.dart';
import 'openssl_crypto_provider.dart';
import 'web_crypto_provider.dart';

// Native crypto backend, best-available first (all standardized AES-256-GCM, so
// byte-interoperable with existing files); each FFI provider self-tests at load
// and returns null on failure, so the chain degrades safely:
//   1. OS OpenSSL libcrypto via FFI — Linux, and Windows where present.
//      AES-NI hardware, ~1280 MB/s, no bundled native library.
//   2. Windows CNG bcrypt.dll via FFI — hardware AES-GCM on Windows.
//   3. CryptographyCryptoProvider — package:cryptography, hardware-accelerated on
//      Android/iOS/macOS via FlutterCryptography (Keystore/CryptoKit), pure-Dart
//      as the final fallback.
// macOS intentionally skips OpenSSL: sandboxed App Store/TestFlight processes
// are aborted by dyld when asked to load a Homebrew library outside the bundle.
// The web build uses WebCryptoSubtleProvider instead (see *_web.dart).
WebCryptoProvider defaultWebCryptoProvider() {
  return OpenSslCryptoProvider.tryCreate() ??
      BCryptCryptoProvider.tryCreate() ??
      CryptographyCryptoProvider();
}
