// lib/services/s3_config_service.dart
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

class S3ConfigService {
  final String configPath;
  final SecureStorage _secure;

  S3ConfigService({required this.configPath, required SecureStorage secureStorage})
      : _secure = secureStorage;

  Future<Map<String, String>?> readCredentials() async {
    try {
      return await _secure.readMap('s3_credentials');
    } catch (e) {
      debugPrint('Warning: Error reading S3 credentials: $e');
      return null;
    }
  }

  Future<void> saveCredentials(Map<String, String> creds) async {
    try {
      await _secure.writeMap('s3_credentials', creds);
    } catch (e) {
      debugPrint('Error saving S3 credentials: $e');
      rethrow;
    }
  }

  Future<void> clearCredentials() async {
    try {
      await _secure.delete('s3_credentials');
    } catch (e) {
      debugPrint('Warning: Error clearing S3 credentials: $e');
    }
  }
}
