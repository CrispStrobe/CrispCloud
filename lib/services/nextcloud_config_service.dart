// lib/services/nextcloud_config_service.dart
import 'log_service.dart';
import 'secure_storage_service.dart';

class NextcloudConfigService {
  static final _log = Log('NextcloudConfig');

  final String configPath;
  final SecureStorage _secure;

  NextcloudConfigService({required this.configPath, required SecureStorage secureStorage})
      : _secure = secureStorage;

  Future<Map<String, String>?> readCredentials() async {
    try {
      return await _secure.readMap('nextcloud_credentials');
    } catch (e) {
      _log.warn('Error reading credentials', e);
      return null;
    }
  }

  Future<void> saveCredentials(Map<String, String> creds) async {
    try {
      await _secure.writeMap('nextcloud_credentials', creds);
    } catch (e) {
      _log.error('Error saving credentials', e);
      rethrow;
    }
  }

  Future<void> clearCredentials() async {
    try {
      await _secure.delete('nextcloud_credentials');
    } catch (e) {
      _log.warn('Error clearing credentials', e);
    }
  }
}
