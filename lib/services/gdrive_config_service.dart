// lib/services/gdrive_config_service.dart
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

class GDriveConfigService {
  final String configPath;
  final SecureStorage _secure;

  GDriveConfigService({required this.configPath, required SecureStorage secureStorage})
      : _secure = secureStorage;

  Future<Map<String, String>?> readCredentials() async {
    try {
      return await _secure.readMap('gdrive_credentials');
    } catch (e) {
      debugPrint('Warning: Error reading GDrive credentials: $e');
      return null;
    }
  }

  Future<void> saveCredentials(Map<String, String> creds) async {
    try {
      await _secure.writeMap('gdrive_credentials', creds);
    } catch (e) {
      debugPrint('Error saving GDrive credentials: $e');
      rethrow;
    }
  }

  Future<void> clearCredentials() async {
    try {
      await _secure.delete('gdrive_credentials');
    } catch (e) {
      debugPrint('Warning: Error clearing GDrive credentials: $e');
    }
  }
}
