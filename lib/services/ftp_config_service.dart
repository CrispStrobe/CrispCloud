// lib/services/ftp_config_service.dart
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

class FTPConfigService {
  final String configPath;
  final SecureStorage _secure;

  FTPConfigService({required this.configPath, required SecureStorage secureStorage})
      : _secure = secureStorage;

  Future<Map<String, String>?> readCredentials() async {
    try {
      return await _secure.readMap('ftp_credentials');
    } catch (e) {
      debugPrint('Warning: Error reading FTP credentials: $e');
      return null;
    }
  }

  Future<void> saveCredentials(Map<String, String> creds) async {
    try {
      await _secure.writeMap('ftp_credentials', creds);
    } catch (e) {
      debugPrint('Error saving FTP credentials: $e');
      rethrow;
    }
  }

  Future<void> clearCredentials() async {
    try {
      await _secure.delete('ftp_credentials');
    } catch (e) {
      debugPrint('Warning: Error clearing FTP credentials: $e');
    }
  }
}
