import 'dart:convert';

import 'package:internxt_client/crypto.dart' as sdk_crypto;
import 'package:internxt_client/internxt_client.dart'
    show ConfigService, ConfigStorage;
import 'package:path/path.dart' as p;

import '../../utils/async_lock.dart';
import '../log_service.dart';
import '../secure_storage_service.dart';
import 'legacy_config_io.dart'
    if (dart.library.js_interop) 'legacy_config_web.dart'
    as legacy;

/// Use the host's Keychain/Keystore or unlocked web vault for Internxt secrets.
/// Supplying a backend disables the SDK's public-static-key credential wrapper.
ConfigService createSecureInternxtConfig({
  required String configPath,
  required SecureStorage secureStorage,
}) => ConfigService(
  configPath: configPath,
  storage: InternxtSecureConfigStorage(secureStorage: secureStorage),
);

/// Adapts the SDK's path-keyed persistence to the application's secure store.
///
/// Keys are relative to the config directory, so an iOS app-container path
/// change does not orphan the Keychain entry. As with the other provider
/// configs, the default namespace holds the app's current Internxt account.
/// A consumer maintaining independent accounts must give each a namespace.
///
/// Legacy files/preferences are read only when no secure entry exists. A
/// verified secure write precedes cleanup. A durable tombstone on deletion
/// prevents a failed cleanup from resurrecting credentials on next launch.
class InternxtSecureConfigStorage implements ConfigStorage {
  InternxtSecureConfigStorage({
    required SecureStorage secureStorage,
    ConfigStorage? legacyStorage,
    String? Function()? legacyEnvironmentKey,
    this.namespace = 'internxt',
  }) : _secure = secureStorage,
       _legacy = legacyStorage ?? legacy.legacyInternxtStorage(),
       _legacyEnvironmentKey =
           legacyEnvironmentKey ?? legacy.legacyInternxtEnvironmentKey;

  static const _log = Log('InternxtSecureConfig');
  // Serializes migration/write/logout across adapter instances in this isolate.
  static final _lock = AsyncLock();
  static const _credentialsName = '.inxtcli-dart-creds.json';
  // Historical SDK default; migration only, never used for new persistence.
  static const _legacyStaticKey = '6KYQBP847D4ATSFA';
  final SecureStorage _secure;
  final ConfigStorage _legacy;
  final String? Function() _legacyEnvironmentKey;
  final String namespace;
  String? _dataDir;

  @override
  void init(String dataDir, List<String> subDirs) {
    final normalized = p.normalize(dataDir);
    if (_dataDir != null && _dataDir != normalized) {
      throw StateError('Internxt config storage is already initialized.');
    }
    _dataDir = normalized;
    // No plaintext filesystem or SharedPreferences initialization.
  }

  String _relativeKey(String key) {
    final dir = _dataDir;
    if (dir == null) {
      throw StateError('Internxt config storage has not been initialized.');
    }
    final relative = p.relative(p.normalize(key), from: dir);
    if (relative == '.' ||
        p.isAbsolute(relative) ||
        p.split(relative).contains('..')) {
      throw ArgumentError('Internxt config key is outside its directory.');
    }
    // Store a platform-independent key even when the native SDK uses Windows
    // separators. This also keeps the credential entry stable across updates.
    return p.split(relative).join('/');
  }

  String _secureKey(String relative) =>
      'internxt_config_v1:${base64Url.encode(utf8.encode(namespace))}:'
      '${base64Url.encode(utf8.encode(relative))}';

  String _encode(String? value) => jsonEncode({'schema': 1, 'value': value});

  String? _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map &&
          decoded['schema'] == 1 &&
          decoded.containsKey('value') &&
          (decoded['value'] == null || decoded['value'] is String)) {
        return decoded['value'] as String?;
      }
    } catch (_) {
      // Never include credential contents in errors or logs.
    }
    throw StateError('Internxt secure settings could not be read.');
  }

  Future<void> _persist(String secureKey, String? value) async {
    final encoded = _encode(value);
    await _secure.write(secureKey, encoded);
    if (await _secure.read(secureKey) != encoded) {
      throw StateError('Internxt secure settings could not be saved.');
    }
  }

  Future<void> _cleanLegacy(String key) async {
    try {
      await _legacy.delete(key);
    } catch (_) {
      // The secure value/tombstone is authoritative. Retry cleanup on a later
      // operation, but never fall back to the obsolete credentials.
      _log.warn('Could not remove an obsolete Internxt config entry.');
    }
  }

  String _decodeLegacyCredentials(String raw) {
    try {
      var decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      if (decoded.containsKey('fmt')) {
        if (decoded['fmt'] != 'inxt-cred-v1' || decoded['ct'] is! String) {
          throw const FormatException();
        }
        final String? secret;
        if (decoded['src'] == 'static') {
          secret = _legacyStaticKey;
        } else if (decoded['src'] == 'env') {
          secret = _legacyEnvironmentKey();
        } else {
          throw const FormatException();
        }
        if (secret == null || secret.isEmpty) {
          throw const FormatException();
        }
        decoded = jsonDecode(
          sdk_crypto.decryptTextWithKey(decoded['ct'] as String, secret),
        );
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException();
        }
      }
      return jsonEncode(decoded);
    } catch (_) {
      // Preserve the legacy copy, including when its environment key is absent.
      throw StateError('Existing Internxt credentials could not be migrated.');
    }
  }

  @override
  Future<bool> exists(String key) async => await read(key) != null;

  @override
  Future<String?> read(String key) => _lock.synchronized(() async {
    final relative = _relativeKey(key);
    final secureKey = _secureKey(relative);
    final saved = await _secure.read(secureKey);
    if (saved != null) {
      final value = _decode(saved);
      await _cleanLegacy(key);
      return value;
    }
    final old = await _legacy.read(key);
    if (old == null) return null;
    final value = relative == _credentialsName
        ? _decodeLegacyCredentials(old)
        : old;
    await _persist(secureKey, value);
    await _cleanLegacy(key);
    return value;
  });

  @override
  Future<void> write(String key, String value) => _lock.synchronized(() async {
    final relative = _relativeKey(key);
    await _persist(_secureKey(relative), value);
    await _cleanLegacy(key);
  });

  @override
  Future<void> delete(String key) => _lock.synchronized(() async {
    final relative = _relativeKey(key);
    await _persist(_secureKey(relative), null);
    await _cleanLegacy(key);
  });
}
