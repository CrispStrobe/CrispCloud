// lib/services/dropbox_config_service.dart
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

class DropboxConfigService {
  final String configPath;
  final SecureStorage _secure;

  DropboxConfigService({required this.configPath, required SecureStorage secureStorage})
      : _secure = secureStorage;

  Future<Map<String, String>?> readCredentials() async {
    try {
      return await _secure.readMap('dropbox_credentials');
    } catch (e) {
      debugPrint('Warning: Error reading Dropbox credentials: $e');
      return null;
    }
  }

  Future<void> saveCredentials(Map<String, String> creds) async {
    try {
      await _secure.writeMap('dropbox_credentials', creds);
    } catch (e) {
      debugPrint('Error saving Dropbox credentials: $e');
      rethrow;
    }
  }

  Future<void> clearCredentials() async {
    try {
      await _secure.delete('dropbox_credentials');
    } catch (e) {
      debugPrint('Warning: Error clearing Dropbox credentials: $e');
    }
  }
}
