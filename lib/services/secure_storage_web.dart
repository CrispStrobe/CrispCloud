// Shared password vault codec for browser storage and the native file backend.
// AES-256-GCM values retain the existing nonce(12) | ciphertext | tag(16)
// format; PBKDF2-HMAC-SHA256 metadata remains compatible with legacy vaults.

import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

import '../utils/async_lock.dart';
import 'encryption_service.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';
import 'credential_storage_diagnostics.dart';
import 'web_crypto_provider.dart';
import 'web_crypto_factory_io.dart'
    if (dart.library.js_interop) 'web_crypto_factory_web.dart';

const _log = Log('WebEncryptedStorage');
const _keyPrefix = 'crisp_enc_';
const _saltKey = '${_keyPrefix}salt';
const _verifyKey = '${_keyPrefix}verify';
const _iterationsKey = '${_keyPrefix}iterations';
const _verifyPlaintext = 'CrispCloud-web-verify';
const _pbkdf2Iterations = 600000;
const _legacyIterations = 100000;

// ':' cannot occur in legacy base64. The authenticated inner 0xff byte cannot
// occur in the UTF-8 plaintext of a legacy String value, so stripping 'v2:'
// cannot downgrade a bound record into a valid legacy credential.
const _boundRecordPrefix = 'v2:';
const _boundRecordMagic = <int>[0xff, 0x43, 0x43, 0x56, 0x02];

// A corrupt or hostile vault must not choose unbounded work before password
// verification. Existing positive counts up to this ceiling stay readable;
// increasing it is an explicit compatibility/performance review. The public
// app creates vaults at 600,000, while tests can inject a lower positive count.
const _maxPbkdf2Iterations = 2000000;

/// Password-unlocked AES-256-GCM credential storage.
///
/// The file backend supplies an atomic transaction covering metadata, key
/// verification, and every credential operation. Other backends retain their
/// own persistence guarantees; in particular localStorage is not a transaction
/// spanning browser tabs. Metadata changes invalidate an unlocked handle.
/// New credential values authenticate their storage key in a versioned binary
/// envelope; existing UTF-8/base64 values remain readable and become bound when
/// rewritten. Verification metadata keeps the original format.
class WebEncryptedStorage extends SecureStorage
    implements CredentialStorageIdentity {
  @override
  String get credentialStoreName => 'Browser encrypted credential vault';
  @override
  String get credentialStoreLocation =>
      'Browser storage at ${Uri.base.hasScheme && (Uri.base.scheme == 'https' || Uri.base.scheme == 'http') ? Uri.base.origin : Uri.base}';
  final WebStorageBackend _backend;
  WebStorageBackend get backend => _backend;
  final WebCryptoProvider _crypto;
  final int _newVaultIterations;
  final _operations = AsyncLock();
  Object? _cryptoKey;
  _VaultMetadata? _metadata;

  WebEncryptedStorage(
    this._backend, {
    WebCryptoProvider? cryptoProvider,
    int newVaultIterations = _pbkdf2Iterations,
  }) : _crypto = cryptoProvider ?? defaultWebCryptoProvider(),
       _newVaultIterations = newVaultIterations;

  bool get isInitialized => _cryptoKey != null;

  Future<T> _withBackend<T>(Future<T> Function(WebStorageBackend) action) {
    final backend = _backend;
    if (backend is TransactionalWebStorageBackend) {
      return backend.transaction(action);
    }
    return action(backend);
  }

  /// Inspect existing-vs-new state without deriving a key or changing storage.
  /// Partial, malformed, or unsupported metadata throws instead of offering to
  /// create a vault over damaged credentials. Missing iterations are accepted
  /// only for a complete legacy salt/verification pair (100,000 iterations).
  Future<bool> hasVault() => _operations.synchronized(
    () => _withBackend((backend) async => await _readMetadata(backend) != null),
  );

  /// Unlock an existing vault or atomically initialize a new file vault.
  /// A failed attempt always leaves this handle locked. Neither a wrong
  /// password nor incomplete metadata writes a replacement verification token.
  Future<void> initialize(
    String masterPassword, {
    bool? expectedExisting,
  }) => _operations.synchronized(() async {
    _cryptoKey = null;
    _metadata = null;
    try {
      final unlocked = await _withBackend((backend) async {
        var metadata = await _readMetadata(backend);
        if (expectedExisting != null &&
            (metadata != null) != expectedExisting) {
          throw StateError('Credential vault state changed; inspect it again');
        }
        final salt = metadata?.saltBytes ?? EncryptionService.generateSalt();
        final iterations = metadata?.iterations ?? _newVaultIterations;
        _validateIterations(iterations);
        final key = await _crypto.deriveKey(masterPassword, salt, iterations);
        if (metadata != null) {
          try {
            final verified = await _crypto.decrypt(
              key,
              base64.decode(metadata.verify),
            );
            if (utf8.decode(verified) != _verifyPlaintext) {
              throw StateError('Master password verification failed');
            }
          } catch (_) {
            throw StateError('Incorrect master password or damaged vault');
          }
        } else {
          // Finish crypto before making any writes. A transactional backend
          // publishes all three metadata fields together, or none of them.
          final verified = await _crypto.encrypt(
            key,
            Uint8List.fromList(utf8.encode(_verifyPlaintext)),
          );
          metadata = _VaultMetadata(
            base64.encode(salt),
            base64.encode(verified),
            iterations.toString(),
            salt,
            iterations,
          );
          await backend.setItem(_saltKey, metadata.salt);
          await backend.setItem(_iterationsKey, metadata.storedIterations!);
          await backend.setItem(_verifyKey, metadata.verify);
        }
        return (key: key, metadata: metadata);
      });
      // File transaction commit must succeed before the handle is unlocked.
      _cryptoKey = unlocked.key;
      _metadata = unlocked.metadata;
      _log.info('Encrypted credential storage initialized');
    } catch (_) {
      _cryptoKey = null;
      _metadata = null;
      rethrow;
    }
  });

  static void _validateIterations(int iterations) {
    if (iterations < 1 || iterations > _maxPbkdf2Iterations) {
      throw StateError('Unsupported credential vault PBKDF2 iteration count');
    }
  }

  Future<_VaultMetadata?> _readMetadata(WebStorageBackend backend) async {
    final salt = await backend.getItem(_saltKey);
    final verify = await backend.getItem(_verifyKey);
    final storedIterations = await backend.getItem(_iterationsKey);
    if (salt == null && verify == null && storedIterations == null) {
      if ((await backend.allKeys()).any((key) => key.startsWith(_keyPrefix))) {
        throw StateError('Credential vault is missing encryption metadata');
      }
      return null;
    }
    if (salt == null || verify == null) {
      throw StateError('Credential vault has incomplete encryption metadata');
    }
    Uint8List saltBytes;
    try {
      // The existing format always writes a 16-byte salt and a fixed-size
      // encrypted verification token. Bound decoding before allocating data.
      if (salt.length != 24 ||
          verify.length != ((28 + _verifyPlaintext.length + 2) ~/ 3) * 4) {
        throw const FormatException('Invalid metadata length');
      }
      saltBytes = base64.decode(salt);
      final verifyBytes = base64.decode(verify);
      if (saltBytes.length != 16 ||
          base64.encode(saltBytes) != salt ||
          verifyBytes.length != 28 + _verifyPlaintext.length ||
          base64.encode(verifyBytes) != verify) {
        throw const FormatException('Invalid metadata encoding');
      }
    } on FormatException {
      throw StateError('Credential vault has malformed encryption metadata');
    }
    var iterations = _legacyIterations;
    if (storedIterations != null) {
      if (!RegExp(r'^[1-9][0-9]{0,6}$').hasMatch(storedIterations)) {
        throw StateError('Credential vault has an invalid PBKDF2 count');
      }
      iterations = int.parse(storedIterations);
      _validateIterations(iterations);
    }
    return _VaultMetadata(
      salt,
      verify,
      storedIterations,
      saltBytes,
      iterations,
    );
  }

  Future<Object> _currentKey(WebStorageBackend backend) async {
    final key = _cryptoKey;
    if (key == null) {
      throw StateError('Credential vault is locked; unlock it before use');
    }
    try {
      final current = await _readMetadata(backend);
      if (current == null || !current.sameGeneration(_metadata)) {
        throw StateError(
          'Credential vault changed; unlock it again before use',
        );
      }
      return key;
    } catch (_) {
      _cryptoKey = null;
      _metadata = null;
      rethrow;
    }
  }

  String _storageKey(String key) {
    final stored = '$_keyPrefix$key';
    if (stored == _saltKey ||
        stored == _verifyKey ||
        stored == _iterationsKey) {
      throw ArgumentError.value(key, 'key', 'Reserved credential vault key');
    }
    return stored;
  }

  static Uint8List _encodeBoundRecord(String storedKey, String value) {
    final payload = utf8.encode(jsonEncode({'key': storedKey, 'value': value}));
    return Uint8List.fromList([..._boundRecordMagic, ...payload]);
  }

  static String _decodeBoundRecord(String storedKey, Uint8List plaintext) {
    if (plaintext.length < _boundRecordMagic.length) {
      throw const FormatException('Invalid bound credential record');
    }
    for (var index = 0; index < _boundRecordMagic.length; index++) {
      if (plaintext[index] != _boundRecordMagic[index]) {
        throw const FormatException('Invalid bound credential record');
      }
    }
    final record = jsonDecode(
      utf8.decode(plaintext.sublist(_boundRecordMagic.length)),
    );
    if (record is! Map ||
        record.length != 2 ||
        record['key'] != storedKey ||
        record['value'] is! String) {
      throw const FormatException(
        'Credential record belongs to a different key',
      );
    }
    return record['value'] as String;
  }

  @override
  Future<String?> read(String key) => _operations.synchronized(
    () => _withBackend((backend) async {
      final stored = _storageKey(key);
      final cryptoKey = await _currentKey(backend);
      final raw = await backend.getItem(stored);
      if (raw == null) return null;
      try {
        final bound = raw.startsWith(_boundRecordPrefix);
        final ciphertext = bound
            ? raw.substring(_boundRecordPrefix.length)
            : raw;
        final decrypted = await _crypto.decrypt(
          cryptoKey,
          base64.decode(ciphertext),
        );
        return bound
            ? _decodeBoundRecord(stored, decrypted)
            : utf8.decode(decrypted);
      } catch (_) {
        // Absence and authentication failure are different states. Returning
        // null here allowed legacy migration to overwrite damaged credentials.
        throw StateError('Stored credential could not be authenticated');
      }
    }),
  );

  @override
  Future<void> write(String key, String value) => _operations.synchronized(
    () => _withBackend((backend) async {
      final stored = _storageKey(key);
      final cryptoKey = await _currentKey(backend);
      final encrypted = await _crypto.encrypt(
        cryptoKey,
        _encodeBoundRecord(stored, value),
      );
      await backend.setItem(
        stored,
        '$_boundRecordPrefix${base64.encode(encrypted)}',
      );
    }),
  );

  @override
  Future<void> delete(String key) => _operations.synchronized(
    () => _withBackend((backend) async {
      final stored = _storageKey(key);
      await _currentKey(backend);
      await backend.removeItem(stored);
    }),
  );

  @override
  Future<bool> containsKey(String key) => _operations.synchronized(
    () => _withBackend((backend) async {
      final stored = _storageKey(key);
      await _currentKey(backend);
      return await backend.getItem(stored) != null;
    }),
  );

  @override
  Future<void> deleteAll() => _operations.synchronized(
    () => _withBackend((backend) async {
      await _currentKey(backend);
      for (final key in await backend.allKeys()) {
        if (key.startsWith(_keyPrefix) &&
            key != _saltKey &&
            key != _verifyKey &&
            key != _iterationsKey) {
          await backend.removeItem(key);
        }
      }
    }),
  );
}

class _VaultMetadata {
  const _VaultMetadata(
    this.salt,
    this.verify,
    this.storedIterations,
    this.saltBytes,
    this.iterations,
  );
  final String salt;
  final String verify;
  final String? storedIterations;
  final Uint8List saltBytes;
  final int iterations;

  bool sameGeneration(_VaultMetadata? other) =>
      other != null &&
      salt == other.salt &&
      verify == other.verify &&
      storedIterations == other.storedIterations;
}

/// Minimal string backend. Implementations must distinguish failed reads from
/// missing values; silently discarding malformed data is not safe for a vault.
abstract class WebStorageBackend {
  Future<String?> getItem(String key);
  Future<void> setItem(String key, String value);
  Future<void> removeItem(String key);
  Future<List<String>> allKeys();
}

/// Optional all-or-nothing read/modify/write boundary, used by native files.
/// [action] receives an isolated staged backend and must not retain it. A
/// callback failure discards every staged change. A successful future means
/// commit completed; a commit error must describe an uncertain result if the
/// atomic replacement already happened. The callback may perform async crypto.
abstract class TransactionalWebStorageBackend implements WebStorageBackend {
  Future<T> transaction<T>(Future<T> Function(WebStorageBackend) action);
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
