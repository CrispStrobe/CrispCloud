// lib/services/app_lock_service.dart
//
// App lock service: PIN or password protection for the app.
// Stores a salted SHA-256 hash in SecureStorage. Supports auto-lock timeout.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'log_service.dart';
import 'secure_storage_service.dart';

class AppLockService {
  static final _log = Log('AppLockService');

  static const _hashKey = 'app_lock_hash';
  static const _saltKey = 'app_lock_salt';
  static const _enabledKey = 'app_lock_enabled';
  static const _timeoutKey = 'app_lock_timeout';

  final SecureStorage _storage;

  AppLockService(this._storage);

  /// Check if app lock is configured.
  Future<bool> isEnabled() async {
    final val = await _storage.read(_enabledKey);
    return val == 'true';
  }

  /// Get auto-lock timeout in seconds (0 = immediate, -1 = disabled).
  Future<int> getTimeout() async {
    final val = await _storage.read(_timeoutKey);
    return int.tryParse(val ?? '') ?? 300; // Default 5 minutes
  }

  /// Set auto-lock timeout in seconds.
  Future<void> setTimeout(int seconds) async {
    await _storage.write(_timeoutKey, seconds.toString());
  }

  /// Set up app lock with a PIN or password.
  Future<void> setup(String code) async {
    if (code.length < 4) {
      throw ArgumentError('Code must be at least 4 characters');
    }

    // Generate random salt
    final saltBytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      saltBytes[i] = DateTime.now().microsecond % 256 ^ (i * 17 + 31);
    }
    final salt = base64Encode(saltBytes);

    // Hash: SHA-256(salt + code)
    final hash = _hashCode(code, salt);

    await _storage.write(_saltKey, salt);
    await _storage.write(_hashKey, hash);
    await _storage.write(_enabledKey, 'true');
    _log.info('App lock configured');
  }

  /// Verify the code against the stored hash.
  Future<bool> verify(String code) async {
    final storedHash = await _storage.read(_hashKey);
    final salt = await _storage.read(_saltKey);
    if (storedHash == null || salt == null) return false;

    final hash = _hashCode(code, salt);
    return hash == storedHash;
  }

  /// Disable app lock and clear stored hash.
  Future<void> disable() async {
    await _storage.delete(_hashKey);
    await _storage.delete(_saltKey);
    await _storage.write(_enabledKey, 'false');
    _log.info('App lock disabled');
  }

  /// Change the lock code. Requires current code verification.
  Future<bool> changeCode(String currentCode, String newCode) async {
    if (!await verify(currentCode)) return false;
    await setup(newCode);
    return true;
  }

  String _hashCode(String code, String salt) {
    final bytes = utf8.encode('$salt:$code');
    // Multiple rounds for slow hashing
    var digest = sha256.convert(bytes);
    for (int i = 0; i < 9999; i++) {
      digest = sha256.convert(digest.bytes);
    }
    return digest.toString();
  }
}
