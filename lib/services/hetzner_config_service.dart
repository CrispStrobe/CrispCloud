// lib/services/hetzner_config_service.dart
//
// Persists Hetzner Storage Box credentials and protocol preference.
// Keys stored: username (uNNNNNN), password, protocol ('sftp'|'webdav'),
// and an optional sub-account username.

import 'log_service.dart';
import 'secure_storage_service.dart';

/// Supported protocols for Hetzner Storage Box.
enum HetznerProtocol { sftp, webdav }

class HetznerConfigService {
  static const _log = Log('HetznerConfig');

  static const _storageKey = 'hetzner_credentials';

  final SecureStorage _secure;

  HetznerConfigService({required SecureStorage secureStorage})
      : _secure = secureStorage;

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<Map<String, String>?> readCredentials() async {
    try {
      return await _secure.readMap(_storageKey);
    } catch (e) {
      _log.warn('Error reading Hetzner credentials', e);
      return null;
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> saveCredentials({
    required String username,
    required String password,
    required HetznerProtocol protocol,
    String? subAccount,
  }) async {
    try {
      final map = <String, String>{
        'username': username,
        'password': password,
        'protocol': protocol.name, // 'sftp' or 'webdav'
        if (subAccount != null && subAccount.isNotEmpty)
          'subAccount': subAccount,
      };
      await _secure.writeMap(_storageKey, map);
    } catch (e) {
      _log.error('Error saving Hetzner credentials', e);
      rethrow;
    }
  }

  // ── Clear ─────────────────────────────────────────────────────────────────

  Future<void> clearCredentials() async {
    try {
      await _secure.delete(_storageKey);
    } catch (e) {
      _log.warn('Error clearing Hetzner credentials', e);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Parses the stored protocol string back to [HetznerProtocol].
  /// Defaults to [HetznerProtocol.sftp] if missing or unrecognised.
  static HetznerProtocol parseProtocol(String? raw) {
    if (raw == HetznerProtocol.webdav.name) return HetznerProtocol.webdav;
    return HetznerProtocol.sftp;
  }
}
