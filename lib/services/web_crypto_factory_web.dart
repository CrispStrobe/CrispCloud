// lib/services/web_crypto_factory_web.dart
//
// Default WebCryptoProvider for the web build: the native WebCrypto
// (crypto.subtle) implementation with a non-extractable key.

import 'web_crypto_provider.dart';
import 'web_crypto_subtle.dart';

WebCryptoProvider defaultWebCryptoProvider() => const WebCryptoSubtleProvider();
