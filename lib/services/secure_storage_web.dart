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

final _log = Log('WebEncryptedStorage');

/// Prefix for all encrypted entries in the backing store.
const _keyPrefix = 'crisp_enc_';

/// Key under which the PBKDF2 salt is stored (unencrypted).
const _saltKey = '${_keyPrefix}salt';

/// Key under which a verification token is stored so we can detect
/// an incorrect master password without corrupting real data.
const _verifyKey = '${_keyPrefix}verify';

/// The plaintext we encrypt as a verification token.
const _verifyPlaintext = 'CrispCloud-web-verify';

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

  /// Derived AES-256 key — held in memory only, never persisted.
  Uint8List? _derivedKey;

  WebEncryptedStorage(this._backend);

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Whether [initialize] has been called successfully.
  bool get isInitialized => _derivedKey != null;

  /// Derive the encryption key from [masterPassword] and either create a new
  /// salt (first run) or load the existing one.
  ///
  /// If a verification token already exists, this method will attempt to
  /// decrypt it. A mismatch throws [StateError] (wrong password).
  Future<void> initialize(String masterPassword) async {
    Uint8List salt;
    final existingSalt = await _backend.getItem(_saltKey);

    if (existingSalt != null) {
      // Returning user — load existing salt.
      salt = base64.decode(existingSalt);
    } else {
      // First run — generate and persist a new salt.
      salt = EncryptionService.generateSalt();
      await _backend.setItem(_saltKey, base64.encode(salt));
    }

    final key = EncryptionService.deriveKey(masterPassword, salt);

    // Verify against existing token (if any).
    final existingVerify = await _backend.getItem(_verifyKey);
    if (existingVerify != null) {
      try {
        final decrypted = EncryptionService.decrypt(
          base64.decode(existingVerify),
          key,
        );
        if (utf8.decode(decrypted) != _verifyPlaintext) {
          throw StateError('Master password verification failed');
        }
      } catch (e) {
        if (e is StateError) rethrow;
        throw StateError('Incorrect master password');
      }
    } else {
      // First run — store a verification token.
      final encrypted = EncryptionService.encrypt(
        Uint8List.fromList(utf8.encode(_verifyPlaintext)),
        key,
      );
      await _backend.setItem(_verifyKey, base64.encode(encrypted));
    }

    _derivedKey = key;
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
    _checkInit();
    final raw = await _backend.getItem(_storageKey(key));
    if (raw == null) return null;
    try {
      final decrypted = EncryptionService.decrypt(
        base64.decode(raw),
        _derivedKey!,
      );
      return utf8.decode(decrypted);
    } catch (e) {
      _log.warn('Failed to decrypt value for key "$key"', e);
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _checkInit();
    final encrypted = EncryptionService.encrypt(
      Uint8List.fromList(utf8.encode(value)),
      _derivedKey!,
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
    _checkInit();
    return await _backend.getItem(_storageKey(key)) != null;
  }

  @override
  Future<void> deleteAll() async {
    _checkInit();
    // Remove all keys with our prefix, except the salt and verify token,
    // so the master password still works after clearing credentials.
    final keys = await _backend.allKeys();
    for (final k in keys) {
      if (k.startsWith(_keyPrefix) && k != _saltKey && k != _verifyKey) {
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
