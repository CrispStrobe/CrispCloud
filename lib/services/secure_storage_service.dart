// lib/services/secure_storage_service.dart
//
// Abstraction over platform-specific secure storage.
//
// Native (macOS/iOS/Android/Linux/Windows): uses flutter_secure_storage
// which delegates to Keychain, Keystore, libsecret, DPAPI respectively.
//
// Web: uses SharedPreferences with a warning — browser storage is not
// truly secure, but it's the best we can do without a server-side component.
// A future iteration should encrypt values client-side before storing.
//
// Non-credential data (provider preference, batch state) stays in
// SharedPreferences via the config services directly.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';

const _secureLog = Log('SecureStorage');

/// Abstract interface for secure key-value storage of credentials.
///
/// Implementations must encrypt data at rest (or delegate to a platform
/// mechanism that does).
abstract class SecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<bool> containsKey(String key);
  Future<void> deleteAll();

  /// Convenience: store a JSON-serialisable map.
  Future<void> writeMap(String key, Map<String, String> data) async {
    await write(key, json.encode(data));
  }

  /// Convenience: read a stored JSON map.
  Future<Map<String, String>?> readMap(String key) async {
    final raw = await read(key);
    if (raw == null) return null;
    try {
      return Map<String, String>.from(json.decode(raw) as Map);
    } catch (e) {
      _secureLog.warn('Failed to decode map for key "$key"', e);
      return null;
    }
  }
}

/// Production implementation backed by flutter_secure_storage (native)
/// or SharedPreferences (web, with a logged warning).
class PlatformSecureStorage extends SecureStorage {
  // flutter_secure_storage handles Keychain (macOS/iOS), Keystore (Android),
  // libsecret (Linux), DPAPI (Windows).
  //
  // On Web, flutter_secure_storage uses localStorage (unencrypted), which is
  // equivalent to SharedPreferences. We accept this limitation for now and
  // log a warning so it's visible during development.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  PlatformSecureStorage() {
    if (kIsWeb) {
      _secureLog.warn(
        'Running on Web — credentials are stored in localStorage (not encrypted at rest). This is a known limitation.',
      );
    }
  }

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// In-memory implementation for tests.
class InMemorySecureStorage extends SecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);

  @override
  Future<void> deleteAll() async {
    _store.clear();
  }
}

/// Migrates credentials from plaintext SharedPreferences to SecureStorage.
///
/// Call once on app startup. After migration, the old SharedPreferences keys
/// are removed so the migration is idempotent.
class CredentialMigration {
  static const _migrationDoneKey = 'secure_storage_migration_v1';

  static Future<void> migrateIfNeeded(SecureStorage secure) async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(_migrationDoneKey) == true) return;

    _secureLog.info('Migrating credentials from SharedPreferences to SecureStorage...');

    // Migrate each provider's credentials
    for (final key in ['dropbox_credentials', 'filen_credentials', 'ftp_credentials', 'gdrive_credentials', 'nextcloud_credentials', 'onedrive_credentials', 'pcloud_credentials', 's3_credentials', 'sftp_credentials', 'webdav_credentials']) {
      final raw = prefs.getString(key);
      if (raw != null) {
        await secure.write(key, raw);
        await prefs.remove(key);
        _secureLog.debug('Migrated $key');
      }
    }

    await prefs.setBool(_migrationDoneKey, true);
    _secureLog.info('Credential migration complete');
  }
}
