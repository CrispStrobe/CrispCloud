// lib/services/web_crypto_factory_io.dart
//
// Default WebCryptoProvider for non-web targets (Dart VM, native). Used by the
// conditional import in secure_storage_web.dart so unit tests and native builds
// compile without dart:js_interop. WebEncryptedStorage is only instantiated on
// web, so this provider is effectively a no-op there — but tests construct it
// to exercise the storage logic with real (pointycastle) crypto.

import 'web_crypto_provider.dart';

WebCryptoProvider defaultWebCryptoProvider() =>
    const PointycastleCryptoProvider();
