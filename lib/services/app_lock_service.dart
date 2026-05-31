// lib/services/app_lock_service.dart
//
// App lock service: PIN or password protection for the app.
// Stores a salted SHA-256 hash in SecureStorage. Supports auto-lock timeout.
// Optional biometric unlock via local_auth (FaceID / TouchID / fingerprint).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'log_service.dart';
import 'secure_storage_service.dart';

class AppLockService {
  static final _log = Log('AppLockService');

  static const _hashKey = 'app_lock_hash';
  static const _saltKey = 'app_lock_salt';
  static const _enabledKey = 'app_lock_enabled';
  static const _timeoutKey = 'app_lock_timeout';
  static const _biometricKey = 'app_lock_biometric';

  final SecureStorage _storage;
  final LocalAuthentication _localAuth;

  AppLockService(this._storage, {LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

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
    await _storage.write(_biometricKey, 'false');
    _log.info('App lock disabled');
  }

  /// Change the lock code. Requires current code verification.
  Future<bool> changeCode(String currentCode, String newCode) async {
    if (!await verify(currentCode)) return false;
    await setup(newCode);
    return true;
  }

  // --- Biometric ---

  /// Check if the device supports biometric authentication.
  ///
  /// On Windows, `local_auth` delegates to Windows Hello (PIN, face, or
  /// fingerprint). `isDeviceSupported()` returns true when Windows Hello is
  /// configured, so we rely on that check rather than `canCheckBiometrics`.
  Future<bool> isBiometricAvailable() async {
    if (kIsWeb) return false;
    try {
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (!isDeviceSupported) return false;
      // On Windows, canCheckBiometrics may be false even when Windows Hello
      // is set up (e.g. PIN-only Hello). Treat device support as sufficient.
      if (!kIsWeb && Platform.isWindows) return true;
      final canCheck = await _localAuth.canCheckBiometrics;
      return canCheck || isDeviceSupported;
    } catch (e) {
      _log.warn('Biometric availability check failed: $e');
      return false;
    }
  }

  /// Get the available biometric types on this device.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (kIsWeb) return [];
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      _log.warn('Failed to get available biometrics: $e');
      return [];
    }
  }

  /// Check if biometric unlock is enabled by the user.
  Future<bool> isBiometricEnabled() async {
    final val = await _storage.read(_biometricKey);
    return val == 'true';
  }

  /// Enable or disable biometric unlock.
  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(_biometricKey, enabled.toString());
    _log.info('Biometric unlock ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Attempt biometric authentication. Returns true if successful.
  ///
  /// On Windows, `biometricOnly: true` is not supported by Windows Hello
  /// (which also accepts a PIN as fallback). We therefore set `biometricOnly`
  /// to false on Windows so the plugin does not throw an unsupported-option
  /// error while still delegating to Windows Hello for authentication.
  Future<bool> authenticateWithBiometric() async {
    if (kIsWeb) return false;
    final isWindows = !kIsWeb && Platform.isWindows;
    try {
      final result = await _localAuth.authenticate(
        localizedReason: 'Unlock CrispCloud',
        options: AuthenticationOptions(
          stickyAuth: true,
          // Windows Hello does not support biometric-only enforcement.
          biometricOnly: !isWindows,
        ),
      );
      if (result) {
        _log.info('Biometric authentication succeeded');
      } else {
        _log.debug('Biometric authentication cancelled or failed');
      }
      return result;
    } catch (e) {
      _log.error('Biometric authentication error: $e');
      return false;
    }
  }

  /// Get a human-readable label for the primary biometric type.
  ///
  /// Returns "Windows Hello" on Windows regardless of the reported biometric
  /// types, since Windows Hello is the umbrella brand for all Windows
  /// authentication methods (PIN, face recognition, fingerprint).
  Future<String> getBiometricLabel() async {
    if (!kIsWeb && Platform.isWindows) return 'Windows Hello';
    final types = await getAvailableBiometrics();
    if (types.contains(BiometricType.face)) return 'Face ID';
    if (types.contains(BiometricType.fingerprint)) return 'Fingerprint';
    if (types.contains(BiometricType.iris)) return 'Iris';
    if (types.contains(BiometricType.strong)) return 'Biometric';
    if (types.contains(BiometricType.weak)) return 'Biometric';
    return 'Biometric';
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
