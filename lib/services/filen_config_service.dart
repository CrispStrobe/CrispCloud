// services/filen_config_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class FilenConfigService {
  final String configPath;
  
  FilenConfigService({required this.configPath});

  // Read stored credentials
  Future<Map<String, String>?> readCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final credentialsJson = prefs.getString('filen_credentials');
      
      if (credentialsJson == null) {
        debugPrint('📂 No Filen credentials found in SharedPreferences');
        return null;
      }
      
      final credentials = Map<String, String>.from(
        json.decode(credentialsJson) as Map
      );
      
      debugPrint('✅ Loaded Filen credentials from SharedPreferences');
      return credentials;
    } catch (e) {
      debugPrint('⚠️ Error reading Filen credentials: $e');
      return null;
    }
  }

  // Save credentials
  Future<void> saveCredentials(Map<String, String> credentials) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final credentialsJson = json.encode(credentials);
      await prefs.setString('filen_credentials', credentialsJson);
      
      // Credentials saved (do not log sensitive data)
    } catch (e) {
      debugPrint('❌ Error saving Filen credentials: $e');
      rethrow;
    }
  }

  // Clear credentials
  Future<void> clearCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('filen_credentials');
      debugPrint('🗑️ Cleared Filen credentials');
    } catch (e) {
      debugPrint('⚠️ Error clearing Filen credentials: $e');
    }
  }

  // Generate batch ID for operations
  String generateBatchId(String operation, List<String> sources, String target) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hash = sources.join('|').hashCode;
    return 'filen_${operation}_${timestamp}_$hash';
  }

  // Save batch state (for resumable operations)
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

  // Read batch state
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

  // Delete batch state
  Future<void> deleteBatchState(String batchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('filen_batch_$batchId');
      debugPrint('🗑️ Deleted batch state for $batchId');
    } catch (e) {
      debugPrint('⚠️ Error deleting batch state: $e');
    }
  }

  // Get all batch IDs (for resuming operations)
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

  // Save provider preference
  Future<void> saveProviderPreference(String provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cloud_provider', provider);
      debugPrint('💾 Saved provider preference: $provider');
    } catch (e) {
      debugPrint('⚠️ Error saving provider preference: $e');
    }
  }

  // Get provider preference
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