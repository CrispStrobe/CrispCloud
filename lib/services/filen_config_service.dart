// services/filen_config_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'secure_storage_service.dart';

class FilenConfigService {
  final String configPath;
  final SecureStorage _secure;

  FilenConfigService({required this.configPath, required SecureStorage secureStorage})
      : _secure = secureStorage;

  // --- Credential operations (secure storage) ---

  Future<Map<String, String>?> readCredentials() async {
    try {
      final creds = await _secure.readMap('filen_credentials');
      if (creds == null) {
        debugPrint('📂 No Filen credentials found');
        return null;
      }
      debugPrint('✅ Loaded Filen credentials from secure storage');
      return creds;
    } catch (e) {
      debugPrint('⚠️ Error reading Filen credentials: $e');
      return null;
    }
  }

  Future<void> saveCredentials(Map<String, String> credentials) async {
    try {
      await _secure.writeMap('filen_credentials', credentials);
      // Credentials saved (do not log sensitive data)
    } catch (e) {
      debugPrint('❌ Error saving Filen credentials: $e');
      rethrow;
    }
  }

  Future<void> clearCredentials() async {
    try {
      await _secure.delete('filen_credentials');
      debugPrint('🗑️ Cleared Filen credentials');
    } catch (e) {
      debugPrint('⚠️ Error clearing Filen credentials: $e');
    }
  }

  // --- Non-credential operations (SharedPreferences) ---

  String generateBatchId(String operation, List<String> sources, String target) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hash = sources.join('|').hashCode;
    return 'filen_${operation}_${timestamp}_$hash';
  }

  Future<void> saveBatchState(String batchId, Map<String, dynamic> state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = json.encode(state);
      await prefs.setString('filen_batch_$batchId', stateJson);
      debugPrint('💾 Saved batch state for $batchId');
    } catch (e) {
      debugPrint('⚠️ Error saving batch state: $e');
    }
  }

  Future<Map<String, dynamic>?> readBatchState(String batchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = prefs.getString('filen_batch_$batchId');
      if (stateJson == null) return null;
      return Map<String, dynamic>.from(json.decode(stateJson) as Map);
    } catch (e) {
      debugPrint('⚠️ Error reading batch state: $e');
      return null;
    }
  }

  Future<void> deleteBatchState(String batchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('filen_batch_$batchId');
      debugPrint('🗑️ Deleted batch state for $batchId');
    } catch (e) {
      debugPrint('⚠️ Error deleting batch state: $e');
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
      debugPrint('⚠️ Error getting batch IDs: $e');
      return [];
    }
  }

  Future<void> saveProviderPreference(String provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cloud_provider', provider);
      debugPrint('💾 Saved provider preference: $provider');
    } catch (e) {
      debugPrint('⚠️ Error saving provider preference: $e');
    }
  }

  Future<String?> getProviderPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('cloud_provider');
    } catch (e) {
      debugPrint('⚠️ Error getting provider preference: $e');
      return null;
    }
  }
}
