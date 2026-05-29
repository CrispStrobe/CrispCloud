// lib/services/onedrive_config_service.dart
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

class OneDriveConfigService {
  final String configPath;
  final SecureStorage _secure;

  OneDriveConfigService({required this.configPath, required SecureStorage secureStorage})
      : _secure = secureStorage;

  Future<Map<String, String>?> readCredentials() async {
    try {
      return await _secure.readMap('onedrive_credentials');
    } catch (e) {
      debugPrint('Warning: Error reading OneDrive credentials: $e');
      return null;
    }
  }

  Future<void> saveCredentials(Map<String, String> creds) async {
    try {
      await _secure.writeMap('onedrive_credentials', creds);
    } catch (e) {
      debugPrint('Error saving OneDrive credentials: $e');
      rethrow;
    }
  }

  Future<void> clearCredentials() async {
    try {
      await _secure.delete('onedrive_credentials');
    } catch (e) {
      debugPrint('Warning: Error clearing OneDrive credentials: $e');
    }
  }
}
