// lib/services/b2_config_service.dart
//
// Backblaze B2 native API configuration service.
// Persists application key ID, application key, bucket ID, and bucket name
// to SecureStorage. Caches auth-response data (authToken, apiUrl, downloadUrl,
// accountId) in memory — cleared on logout.

import 'log_service.dart';
import 'secure_storage_service.dart';

class B2ConfigService {
  static final _log = Log('B2Config');

  static const _credentialsKey = 'b2_credentials';

  final SecureStorage _secure;

  // Cached values from the last b2_authorize_account response.
  String? _authToken;
  String? _apiUrl;
  String? _downloadUrl;
  String? _accountId;

  B2ConfigService({required SecureStorage secureStorage})
      : _secure = secureStorage;

  // ---------------------------------------------------------------------------
  // Credential persistence
  // ---------------------------------------------------------------------------

  /// Read persisted credentials: keyId, applicationKey, bucketId, bucketName.
  Future<Map<String, String>?> readCredentials() async {
    try {
      return await _secure.readMap(_credentialsKey);
    } catch (e) {
      _log.warn('Error reading B2 credentials', e);
      return null;
    }
  }

  /// Persist credentials returned from the UI / login flow.
  Future<void> saveCredentials({
    required String keyId,
    required String applicationKey,
    String? bucketId,
    String? bucketName,
  }) async {
    try {
      final map = <String, String>{
        'keyId': keyId,
        'applicationKey': applicationKey,
        if (bucketId != null) 'bucketId': bucketId,
        if (bucketName != null) 'bucketName': bucketName,
      };
      await _secure.writeMap(_credentialsKey, map);
    } catch (e) {
      _log.error('Error saving B2 credentials', e);
      rethrow;
    }
  }

  /// Remove all persisted credentials.
  Future<void> clearCredentials() async {
    try {
      await _secure.delete(_credentialsKey);
    } catch (e) {
      _log.warn('Error clearing B2 credentials', e);
    }
  }

  // ---------------------------------------------------------------------------
  // In-memory auth-session cache (populated after b2_authorize_account)
  // ---------------------------------------------------------------------------

  void cacheAuthResponse({
    required String authToken,
    required String apiUrl,
    required String downloadUrl,
    required String accountId,
  }) {
    _authToken = authToken;
    _apiUrl = apiUrl;
    _downloadUrl = downloadUrl;
    _accountId = accountId;
  }

  void clearAuthCache() {
    _authToken = null;
    _apiUrl = null;
    _downloadUrl = null;
    _accountId = null;
  }

  /// The auth token returned by b2_authorize_account.
  String? get authToken => _authToken;

  /// The per-account API URL (e.g. https://apiNNN.backblazeb2.com).
  String? getApiUrl() => _apiUrl;

  /// The download URL (e.g. https://f002.backblazeb2.com).
  String? getDownloadUrl() => _downloadUrl;

  /// The Backblaze account ID.
  String? get accountId => _accountId;

  bool get hasSession => _authToken != null && _apiUrl != null;
}
