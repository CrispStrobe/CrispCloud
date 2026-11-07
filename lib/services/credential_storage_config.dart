import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where CrispCloud persists provider and terminal credentials.
enum CredentialStorageMode {
  /// macOS Keychain / iOS Keychain / Android Keystore / libsecret / DPAPI.
  systemKeychain,

  /// AES-256-GCM vault in the app support directory, unlocked by a master
  /// password. Works when no OS keychain is available.
  encryptedFile,

  /// Keep credentials only for this process. Nothing survives a restart.
  sessionOnly,
}

/// Non-secret credential-storage preferences. Credentials themselves are never
/// written here.
class CredentialStorageConfig {
  static const _modeKey = 'credential_storage_mode_v1';
  static const _customKeychainPathKey = 'custom_keychain_path';

  static Future<CredentialStorageMode> readMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_modeKey);
    if (raw == null) return CredentialStorageMode.systemKeychain;
    for (final mode in CredentialStorageMode.values) {
      if (mode.name == raw) return mode;
    }
    throw const FormatException('Unknown credential-storage mode.');
  }

  static Future<void> writeMode(CredentialStorageMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeVerified(prefs, _modeKey, mode.name);
  }

  /// macOS-only. Empty/null means the system default keychain.
  static Future<String?> readCustomKeychainPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final value = prefs.getString(_customKeychainPathKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static Future<void> writeCustomKeychainPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    final value = path?.trim();
    if (value != null && value.contains('\u0000')) {
      throw const FormatException('Invalid custom keychain path.');
    }
    await _writeVerified(
      prefs,
      _customKeychainPathKey,
      value == null || value.isEmpty ? null : value,
    );
  }

  static Future<void> _writeVerified(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    try {
      final saved = value == null
          ? await prefs.remove(key)
          : await prefs.setString(key, value);
      // SharedPreferences mutates its cache even when the platform rejects a
      // write. Reload before claiming a persisted choice or reporting failure.
      await prefs.reload();
      if (!saved || prefs.getString(key) != value) {
        throw StateError('Credential-storage settings were not saved.');
      }
    } catch (_) {
      try {
        await prefs.reload();
      } catch (_) {
        // Retain the original persistence error.
      }
      rethrow;
    }
  }
}

/// The store actually used by this process. Changing preferences must not
/// relabel an active persistent store as session-only before restart.
final credentialStorageModeProvider = StateProvider<CredentialStorageMode>(
  (ref) => CredentialStorageMode.systemKeychain,
);

/// A saved preference for the next launch; null means the active mode.
final credentialStoragePendingModeProvider =
    StateProvider<CredentialStorageMode?>((ref) => null);

/// Custom keychain changes also require a restart, even if the mode is the same.
final credentialStorageKeychainRestartRequiredProvider =
    StateProvider<bool>((ref) => false);

/// True when the native encrypted-file vault must be unlocked before the app
/// can read or write credentials.
final credentialVaultRequiredProvider = StateProvider<bool>((ref) => false);
