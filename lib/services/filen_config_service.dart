// services/filen_config_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:filen_client/config_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';
import 'secure_storage_service.dart';

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

  final String configPath;
  final SecureStorage _secure;

  FilenConfigService({
    required this.configPath,
    required SecureStorage secureStorage,
  }) : _secure = secureStorage;

  /// The SDK's ConfigService can use the same host secure store instead of
  /// writing its legacy plaintext credentials file.
  ConfigStorage get sdkStorage =>
      _FilenSecureConfigStorage(_secure, configPath);

  // --- Credential operations (secure storage) ---

  Future<Map<String, String>?> readCredentials() async {
    try {
      final creds = await _secure.readMap('filen_credentials');
      if (creds == null) {
        _log.debug('No credentials found');
        return null;
      }
      _log.debug('Loaded credentials from secure storage');
      return creds;
    } catch (e) {
      _log.warn('Error reading credentials', e);
      return null;
    }
  }

  Future<void> saveCredentials(Map<String, String> credentials) async {
    try {
      await _secure.writeMap('filen_credentials', credentials);
      await _deleteLegacyCredentialsFile();
      // Credentials saved (do not log sensitive data)
    } catch (e) {
      _log.error('Error saving credentials', e);
      rethrow;
    }
  }

  Future<void> clearCredentials() async {
    try {
      if (_secure.isPersistent) {
        // A conflicting old preference may have been retained by migration.
        // Remove it before the secure entry so it cannot be reimported after a
        // successful logout. Session-only mode must leave durable data alone.
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        if (prefs.containsKey('filen_credentials')) {
          if (!await prefs.remove('filen_credentials')) {
            throw const FilenCredentialDeletionFailure();
          }
          await prefs.reload();
          if (prefs.containsKey('filen_credentials')) {
            throw const FilenCredentialDeletionFailure();
          }
        }
      }
      await _secure.delete('filen_credentials');
      if (await _secure.read('filen_credentials') != null) {
        throw const FilenCredentialDeletionFailure();
      }
      await _deleteLegacyCredentialsFile();
      _log.debug('Cleared credentials');
    } catch (_) {
      _log.warn('Saved Filen credentials could not be removed.');
      throw const FilenCredentialDeletionFailure();
    }
  }

  Future<void> _deleteLegacyCredentialsFile() async {
    try {
      final legacy = File(p.join(configPath, 'credentials.json'));
      if (await legacy.exists()) await legacy.delete();
    } catch (_) {
      // The secure entry is authoritative; a leftover legacy file is removed
      // again on the next successful login/logout.
    }
  }

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
  _FilenSecureConfigStorage(this._secure, this._configPath);
  final SecureStorage _secure;
  final String _configPath;

  Future<void> _deleteLegacy() async {
    try {
      final legacy = File(p.join(_configPath, 'credentials.json'));
      if (await legacy.exists()) await legacy.delete();
    } catch (_) {
      // Retried on the next save/logout.
    }
  }

  @override
  Future<Map<String, dynamic>?> readCredentials() async {
    final stored = await _secure.readMap('filen_credentials');
    return stored?.cast<String, dynamic>();
  }

  @override
  Future<void> saveCredentials(Map<String, dynamic> data) async {
    await _secure.writeMap(
      'filen_credentials',
      data.map((key, value) => MapEntry(key, value.toString())),
    );
    await _deleteLegacy();
  }

  @override
  Future<void> clearCredentials() async {
    await _secure.delete('filen_credentials');
    await _deleteLegacy();
  }
}
