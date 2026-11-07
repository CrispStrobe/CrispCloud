// services/filen_config_service.dart
import 'dart:convert';

import 'package:filen_client/config_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/async_lock.dart';
import 'filen_legacy_credentials_stub.dart'
    if (dart.library.io) 'filen_legacy_credentials_io.dart'
    as legacy;
import 'log_service.dart';
import 'secure_storage_service.dart';

/// Credential errors must never expose stored contents or platform details.
class FilenCredentialReadFailure implements Exception {
  const FilenCredentialReadFailure();

  @override
  String toString() =>
      'Saved Filen credentials could not be read. Restore access to '
      'credential storage and retry.';
}

class FilenCredentialSaveFailure implements Exception {
  const FilenCredentialSaveFailure();

  @override
  String toString() =>
      'Saving Filen credentials or removing an old credential file could not '
      'be verified. Restore access to credential storage and retry.';
}

/// A safe logout error; never contains credentials or platform error details.
class FilenCredentialDeletionFailure implements Exception {
  const FilenCredentialDeletionFailure();

  @override
  String toString() =>
      'Saved Filen credentials could not be removed. Restore access to '
      'credential storage and retry logout before closing CrispCloud.';
}

class FilenConfigService {
  static const _log = Log('FilenConfig');
  static const _credentialsKey = 'filen_credentials';
  // App and SDK operations share a namespace. Serialize their read/write/clear
  // operations across service instances in this isolate.
  static final _credentialsLock = AsyncLock();

  final String configPath;
  final SecureStorage _secure;

  FilenConfigService({
    required this.configPath,
    required SecureStorage secureStorage,
  }) : _secure = secureStorage;

  /// The SDK's ConfigService can use the same host secure store instead of
  /// writing its legacy plaintext credentials file. Keep a stable identity so
  /// logout can distinguish this store from a separately injected SDK store.
  late final ConfigStorage sdkStorage = _FilenSecureConfigStorage(this);

  // --- Credential operations (secure storage) ---

  Future<Map<String, String>?> readCredentials() =>
      _credentialsLock.synchronized(() async {
        try {
          final raw = await _secure.read(_credentialsKey);
          if (raw == null) {
            _log.debug('No credentials found');
            return null;
          }
          // Do not use readMap's corrupt-data fallback: an unreadable existing
          // record is different from an absent login, and errors are redacted.
          final creds = Map<String, String>.from(json.decode(raw) as Map);
          _log.debug('Loaded credentials from secure storage');
          return creds;
        } catch (_) {
          _log.warn('Saved Filen credentials could not be read.');
          throw const FilenCredentialReadFailure();
        }
      });

  Future<void> saveCredentials(Map<String, String> credentials) async {
    try {
      // Snapshot the caller's map before awaiting, then verify the exact bytes
      // before removing any durable legacy copy. A successful Future alone
      // does not establish that a keychain/vault accepted a write.
      final encoded = json.encode(Map<String, String>.from(credentials));
      await _credentialsLock.synchronized(() async {
        await _secure.write(_credentialsKey, encoded);
        if (await _secure.read(_credentialsKey) != encoded) {
          throw const FilenCredentialSaveFailure();
        }
        if (_secure.isPersistent) {
          legacy.deleteLegacyFilenCredentials(configPath);
        }
      });
    } catch (_) {
      _log.warn('Saving Filen credentials could not be verified.');
      throw const FilenCredentialSaveFailure();
    }
  }

  Future<void> clearCredentials() => _credentialsLock.synchronized(() async {
    try {
      if (_secure.isPersistent) {
        // A conflicting old preference may have been retained by migration.
        // Remove it before the secure entry so it cannot be reimported after a
        // successful logout. Session-only mode must leave durable data alone.
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        if (prefs.containsKey(_credentialsKey)) {
          if (!await prefs.remove(_credentialsKey)) {
            throw const FilenCredentialDeletionFailure();
          }
          await prefs.reload();
          if (prefs.containsKey(_credentialsKey)) {
            throw const FilenCredentialDeletionFailure();
          }
        }
        // Keep the secure entry available for retry if the legacy file cannot
        // be removed. A session-only logout must never touch this file.
        legacy.deleteLegacyFilenCredentials(configPath);
      }
      await _secure.delete(_credentialsKey);
      if (await _secure.read(_credentialsKey) != null) {
        throw const FilenCredentialDeletionFailure();
      }
      _log.debug('Cleared credentials');
    } catch (_) {
      _log.warn('Saved Filen credentials could not be removed.');
      throw const FilenCredentialDeletionFailure();
    }
  });

  // --- Non-credential operations (SharedPreferences) ---

  String generateBatchId(
    String operation,
    List<String> sources,
    String target,
  ) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hash = sources.join('|').hashCode;
    return 'filen_${operation}_${timestamp}_$hash';
  }

  Future<void> saveBatchState(
    String batchId,
    Map<String, dynamic> state,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = json.encode(state);
      await prefs.setString('filen_batch_$batchId', stateJson);
      _log.debug('Saved batch state for $batchId');
    } catch (e) {
      _log.warn('Error saving batch state', e);
    }
  }

  Future<Map<String, dynamic>?> readBatchState(String batchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = prefs.getString('filen_batch_$batchId');
      if (stateJson == null) return null;
      return Map<String, dynamic>.from(json.decode(stateJson) as Map);
    } catch (e) {
      _log.warn('Error reading batch state', e);
      return null;
    }
  }

  Future<void> deleteBatchState(String batchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('filen_batch_$batchId');
      _log.debug('Deleted batch state for $batchId');
    } catch (e) {
      _log.warn('Error deleting batch state', e);
    }
  }

  Future<List<String>> getAllBatchIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      return keys
          .where((key) => key.startsWith('filen_batch_'))
          .map((key) => key.replaceFirst('filen_batch_', ''))
          .toList();
    } catch (e) {
      _log.warn('Error getting batch IDs', e);
      return [];
    }
  }

  Future<void> saveProviderPreference(String provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cloud_provider', provider);
      _log.debug('Saved provider preference: $provider');
    } catch (e) {
      _log.warn('Error saving provider preference', e);
    }
  }

  Future<String?> getProviderPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('cloud_provider');
    } catch (e) {
      _log.warn('Error getting provider preference', e);
      return null;
    }
  }
}

/// Adapts the Filen SDK's legacy ConfigStorage interface to the host secure
/// store. The SDK never sees the plaintext credentials file.
class _FilenSecureConfigStorage implements ConfigStorage {
  _FilenSecureConfigStorage(this._config);
  final FilenConfigService _config;

  @override
  Future<Map<String, dynamic>?> readCredentials() async {
    final stored = await _config.readCredentials();
    return stored == null ? null : Map<String, dynamic>.from(stored);
  }

  @override
  Future<void> saveCredentials(Map<String, dynamic> data) async {
    // FilenAuth returns strings, including masterKeys joined with '|'. Never
    // turn a list/map/null into a superficially valid credential string.
    final credentials = <String, String>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is! String) {
        throw const FormatException('Filen credentials must contain strings.');
      }
      credentials[entry.key] = value;
    }
    await _config.saveCredentials(credentials);
  }

  @override
  Future<void> clearCredentials() => _config.clearCredentials();
}
