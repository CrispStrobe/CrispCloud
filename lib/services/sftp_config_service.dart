// lib/services/sftp_config_service.dart
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

class SFTPConfigService {
  final String configPath;
  final SecureStorage _secure;

  SFTPConfigService({required this.configPath, required SecureStorage secureStorage})
      : _secure = secureStorage;

  Future<Map<String, String>?> readCredentials() async {
    try {
      return await _secure.readMap('sftp_credentials');
    } catch (e) {
      debugPrint('⚠️ Error reading SFTP credentials: $e');
      return null;
    }
  }

  Future<void> saveCredentials(Map<String, String> creds) async {
    try {
      await _secure.writeMap('sftp_credentials', creds);
    } catch (e) {
      debugPrint('❌ Error saving SFTP credentials: $e');
      rethrow;
    }
  }

  Future<void> clearCredentials() async {
    try {
      await _secure.delete('sftp_credentials');
    } catch (e) {
      debugPrint('⚠️ Error clearing SFTP credentials: $e');
    }
  }
}
