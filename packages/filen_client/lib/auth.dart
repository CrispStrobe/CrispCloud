/// Authentication for the Filen API.
///
/// Handles login, 2FA, key derivation, and session setup.
import 'dart:convert';

import 'package:filen_client/api.dart';
import 'package:filen_client/crypto.dart';

class FilenAuth {
  final FilenApi api;
  final FilenCrypto crypto;

  FilenAuth({required this.api, required this.crypto});

  Future<Map<String, dynamic>> getAuthInfo(String email) async {
    final response = await api.makeRequest(
      'POST',
      Uri.parse('${FilenApi.apiUrl}/v3/auth/info'),
      body: json.encode({'email': email}),
      useAuth: false,
    );

    final data = json.decode(response.body);
    if (data['status'] != true) throw Exception(data['message']);
    return data['data'] ?? data;
  }

  Future<Map<String, dynamic>> login(String email, String password,
      {String twoFactorCode = "XXXXXX"}) async {
    final authInfo = await getAuthInfo(email);
    final authVersion = authInfo['authVersion'] ?? 2;
    final salt = authInfo['salt'] ?? '';

    api.log('Deriving keys...');
    final derived = await crypto.deriveKeys(password, authVersion, salt);
    final derivedPassword = derived['password']!;
    final localMasterKey = derived['masterKey']!;

    final loginPayload = {
      'email': email.toLowerCase(),
      'password': derivedPassword,
      'authVersion': authVersion,
      // The API rejects an empty value when 2FA is disabled.
      'twoFactorCode': twoFactorCode.trim().isEmpty ? 'XXXXXX' : twoFactorCode,
    };

    final response = await api.makeRequest(
      'POST',
      Uri.parse('${FilenApi.apiUrl}/v3/login'),
      body: json.encode(loginPayload),
      useAuth: false,
    );

    final data = json.decode(response.body);

    if (data['status'] == true && data['data'] != null) {
      final loginData = data['data'];

      List<String> rawEncryptedKeys = [];
      if (loginData['masterKeys'] is String) {
        rawEncryptedKeys = [loginData['masterKeys']];
      } else if (loginData['masterKeys'] is List) {
        rawEncryptedKeys =
            (loginData['masterKeys'] as List).map((e) => e.toString()).toList();
      }

      api.log('Decrypting ${rawEncryptedKeys.length} master keys...');

      List<String> decryptedMasterKeys = [];
      for (var encryptedKey in rawEncryptedKeys) {
        try {
          final decrypted =
              await crypto.decryptMetadata002(encryptedKey, localMasterKey);
          decryptedMasterKeys.add(decrypted);
        } catch (e) {
          api.log('Failed to decrypt a master key: $e');
        }
      }

      if (decryptedMasterKeys.isEmpty) {
        api.log('Warning: No master keys decrypted. Using local master key.');
        decryptedMasterKeys.add(localMasterKey);
      }

      return {
        'email': email,
        'apiKey': loginData['apiKey'],
        'masterKeys': decryptedMasterKeys.join('|'),
        'baseFolderUUID': loginData['baseFolderUUID'] ?? '',
        'userId': (loginData['id'] ?? loginData['userId'] ?? '').toString(),
      };
    } else {
      final code = data['code'] ?? '';
      if (code == 'enter_2fa' || code == 'wrong_2fa') throw Exception(code);
      throw Exception(data['message'] ?? 'Login failed');
    }
  }

  Future<String> fetchBaseFolderUUID() async {
    final response = await api.makeRequest(
      'GET',
      Uri.parse('${FilenApi.apiUrl}/v3/user/baseFolder'),
    );

    final data = json.decode(response.body);
    if (data['status'] == true && data['data'] != null) {
      return data['data']['uuid'] ?? '';
    }
    return data['uuid'] ?? '';
  }
}
