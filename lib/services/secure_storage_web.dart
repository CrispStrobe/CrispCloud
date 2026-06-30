// lib/services/secure_storage_web.dart
//
// Web-specific SecureStorage implementation that encrypts credentials
// client-side using AES-256-GCM before persisting to localStorage.
//
// On native platforms, flutter_secure_storage delegates to OS keychains.
// On web, there is no OS keychain, so we derive an AES-256 key from a
// user-provided master password via PBKDF2 and encrypt every value
// before writing it to localStorage.
//
// Storage format per key:
//   localStorage["crisp_enc_<key>"] = base64(nonce‖ciphertext‖tag)
//   localStorage["crisp_enc_salt"]  = base64(salt)  (unencrypted, for KDF)
//   localStorage["crisp_enc_verify"] = encrypted verification token

import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

import 'encryption_service.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';
import 'web_crypto_provider.dart';
// Picks the native WebCrypto (crypto.subtle) provider on the web build and the
// pure-Dart pointycastle provider on the Dart VM / native (so tests run without
// a browser).
import 'web_crypto_factory_io.dart'
    if (dart.library.js_interop) 'web_crypto_factory_web.dart';

const _log = Log('WebEncryptedStorage');

/// Prefix for all encrypted entries in the backing store.
const _keyPrefix = 'crisp_enc_';

/// Key under which the PBKDF2 salt is stored (unencrypted).
const _saltKey = '${_keyPrefix}salt';

/// Key under which a verification token is stored so we can detect
/// an incorrect master password without corrupting real data.
const _verifyKey = '${_keyPrefix}verify';

/// Key under which the PBKDF2 iteration count is stored (unencrypted), so the
/// count can be raised over time without locking out existing data.
const _iterationsKey = '${_keyPrefix}iterations';

/// The plaintext we encrypt as a verification token.
const _verifyPlaintext = 'CrispCloud-web-verify';

/// PBKDF2 iterations for NEW vaults — OWASP 2023 for PBKDF2-HMAC-SHA256.
/// Affordable because WebCrypto derives natively (~ms); the pointycastle
/// fallback (tests/native) is only ever used at the lower legacy count.
const _pbkdf2Iterations = 600000;

/// Iteration count assumed for a pre-existing vault that has no stored count
/// (the original hard-coded EncryptionService.deriveKey default).
const _legacyIterations = 100000;

/// Web-specific [SecureStorage] that encrypts values with AES-256-GCM
/// using a key derived from a master password.
///
/// Usage:
/// ```dart
/// final storage = WebEncryptedStorage(backingStore);
/// await storage.initialize('my-master-password');
/// await storage.write('token', 'secret-value');
/// ```
///
/// The [backingStore] is a simple string key-value map (backed by
/// localStorage, IndexedDB, or an in-memory map for tests).
class WebEncryptedStorage extends SecureStorage {
  /// Pluggable backing store so tests can inject an in-memory map
  /// instead of requiring a browser environment.
  final WebStorageBackend _backend;

  /// Expose the backing store for checking if credentials exist
  /// (e.g., to decide whether to show the master password gate).
  WebStorageBackend get backend => _backend;

  /// Crypto backend: native WebCrypto (non-extractable key) on the web build,
  /// pointycastle on the Dart VM / native (tests). Injectable for tests.
  final WebCryptoProvider _crypto;

  /// Opaque derived AES-256-GCM key — a non-extractable CryptoKey under
  /// WebCrypto (the raw bytes never enter JS memory), a Uint8List under
  /// pointycastle. Held in memory only, never persisted.
  Object? _cryptoKey;

  /// PBKDF2 iteration count for a NEW vault. Defaults to the SOTA
  /// [_pbkdf2Iterations]; tests override it low so the pure-Dart pointycastle
  /// fallback (no WebCrypto in the VM) stays fast. Production web never lowers
  /// it — WebCrypto derives 600k natively in ~ms.
  final int _newVaultIterations;

  WebEncryptedStorage(this._backend,
      {WebCryptoProvider? cryptoProvider,
      int newVaultIterations = _pbkdf2Iterations})
      : _crypto = cryptoProvider ?? defaultWebCryptoProvider(),
        _newVaultIterations = newVaultIterations;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Whether [initialize] has been called successfully.
  bool get isInitialized => _cryptoKey != null;

  /// Derive the encryption key from [masterPassword] and either create a new
  /// salt (first run) or load the existing one.
  ///
  /// If a verification token already exists, this method will attempt to
  /// decrypt it. A mismatch throws [StateError] (wrong password).
  Future<void> initialize(String masterPassword) async {
    Uint8List salt;
    int iterations;
    final existingSalt = await _backend.getItem(_saltKey);

    if (existingSalt != null) {
      // Returning user — load existing salt + its iteration count. A vault
      // created before iteration-versioning has no stored count → it was
      // derived at the legacy 100k, so we must derive at 100k to decrypt it.
      salt = base64.decode(existingSalt);
      final storedIters = await _backend.getItem(_iterationsKey);
      iterations = int.tryParse(storedIters ?? '') ?? _legacyIterations;
    } else {
      // First run — new salt + SOTA iteration count, both persisted.
      salt = EncryptionService.generateSalt();
      iterations = _newVaultIterations;
      await _backend.setItem(_saltKey, base64.encode(salt));
      await _backend.setItem(_iterationsKey, iterations.toString());
    }

    final key = await _crypto.deriveKey(masterPassword, salt, iterations);

    // Verify against existing token (if any).
    final existingVerify = await _backend.getItem(_verifyKey);
    if (existingVerify != null) {
      try {
        final decrypted =
            await _crypto.decrypt(key, base64.decode(existingVerify));
        if (utf8.decode(decrypted) != _verifyPlaintext) {
          throw StateError('Master password verification failed');
        }
      } catch (e) {
        if (e is StateError) rethrow;
        throw StateError('Incorrect master password');
      }
    } else {
      // First run — store a verification token.
      final encrypted = await _crypto.encrypt(
        key,
        Uint8List.fromList(utf8.encode(_verifyPlaintext)),
      );
      await _backend.setItem(_verifyKey, base64.encode(encrypted));
    }

    _cryptoKey = key;
    _log.info('Web encrypted storage initialized');
  }

  // ---------------------------------------------------------------------------
  // SecureStorage interface
  // ---------------------------------------------------------------------------

  void _checkInit() {
    if (!isInitialized) {
      throw StateError(
        'WebEncryptedStorage not initialized — call initialize() first',
      );
    }
  }

  String _storageKey(String key) => '$_keyPrefix$key';

  @override
  Future<String?> read(String key) async {
    // If not initialized (first-time user who skipped the gate),
    // return null — there are no stored credentials to read.
    if (!isInitialized) return null;
    final raw = await _backend.getItem(_storageKey(key));
    if (raw == null) return null;
    try {
      final decrypted = await _crypto.decrypt(_cryptoKey!, base64.decode(raw));
      return utf8.decode(decrypted);
    } catch (e) {
      _log.warn('Failed to decrypt value for key "$key"', e);
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    if (!isInitialized) {
      throw StateError(
        'Set a master password before saving credentials. '
        'Go to Settings to configure encrypted storage.',
      );
    }
    final encrypted = await _crypto.encrypt(
      _cryptoKey!,
      Uint8List.fromList(utf8.encode(value)),
    );
    await _backend.setItem(_storageKey(key), base64.encode(encrypted));
  }

  @override
  Future<void> delete(String key) async {
    _checkInit();
    await _backend.removeItem(_storageKey(key));
  }

  @override
  Future<bool> containsKey(String key) async {
    if (!isInitialized) return false;
    return await _backend.getItem(_storageKey(key)) != null;
  }

  @override
  Future<void> deleteAll() async {
    _checkInit();
    // Remove all keys with our prefix, except the salt, iteration count and
    // verify token, so the master password still works after clearing creds.
    final keys = await _backend.allKeys();
    for (final k in keys) {
      if (k.startsWith(_keyPrefix) &&
          k != _saltKey &&
          k != _verifyKey &&
          k != _iterationsKey) {
        await _backend.removeItem(k);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Backing store abstraction
// ---------------------------------------------------------------------------

/// Minimal key-value backend so [WebEncryptedStorage] can work both in
/// the browser (localStorage / IndexedDB) and in unit tests.
abstract class WebStorageBackend {
  Future<String?> getItem(String key);
  Future<void> setItem(String key, String value);
  Future<void> removeItem(String key);
  Future<List<String>> allKeys();
}

/// In-memory backend for unit tests.
class InMemoryWebStorageBackend implements WebStorageBackend {
  final Map<String, String> _store = {};

  @override
  Future<String?> getItem(String key) async => _store[key];

  @override
  Future<void> setItem(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> removeItem(String key) async {
    _store.remove(key);
  }

  @override
  Future<List<String>> allKeys() async => _store.keys.toList();
}

/// Browser localStorage backend for production web builds.
class LocalStorageBackend implements WebStorageBackend {
  @override
  Future<String?> getItem(String key) async {
    return html.window.localStorage[key];
  }

  @override
  Future<void> setItem(String key, String value) async {
    html.window.localStorage[key] = value;
  }

  @override
  Future<void> removeItem(String key) async {
    html.window.localStorage.remove(key);
  }

  @override
  Future<List<String>> allKeys() async {
    return html.window.localStorage.keys.toList();
  }
}
