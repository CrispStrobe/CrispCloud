// lib/services/sftp_config_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class SFTPConfigService {
  final String configPath;

  SFTPConfigService({required this.configPath});

  Future<Map<String, String>?> readCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('sftp_credentials');
    if (jsonStr == null) return null;
    return Map<String, String>.from(json.decode(jsonStr));
  }

  Future<void> saveCredentials(Map<String, String> creds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sftp_credentials', json.encode(creds));
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sftp_credentials');
  }
}