// lib/services/webdav_config_service.dart
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

class WebDavConfigService {
  final String configPath;
  final SecureStorage _secure;

  WebDavConfigService({required this.configPath, required SecureStorage secureStorage})
      : _secure = secureStorage;

  Future<Map<String, String>?> readCredentials() async {
    try {
      return await _secure.readMap('webdav_credentials');
    } catch (e) {
      debugPrint('⚠️ Error reading WebDAV credentials: $e');
      return null;
    }
  }

  Future<void> saveCredentials(Map<String, String> creds) async {
    try {
      await _secure.writeMap('webdav_credentials', creds);
    } catch (e) {
      debugPrint('❌ Error saving WebDAV credentials: $e');
      rethrow;
    }
  }

  Future<void> clearCredentials() async {
    try {
      await _secure.delete('webdav_credentials');
    } catch (e) {
      debugPrint('⚠️ Error clearing WebDAV credentials: $e');
    }
  }
}
