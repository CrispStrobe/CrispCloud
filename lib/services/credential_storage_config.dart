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

  static Future<CredentialStorageMode?> readModeIfConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_modeKey);
    if (raw == null) return null;
    return CredentialStorageMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => CredentialStorageMode.systemKeychain,
    );
  }

  static Future<CredentialStorageMode> readMode() async =>
      await readModeIfConfigured() ?? CredentialStorageMode.systemKeychain;

  static Future<void> writeMode(CredentialStorageMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  /// macOS-only. Empty/null means the system default keychain.
  static Future<String?> readCustomKeychainPath() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_customKeychainPathKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static Future<void> writeCustomKeychainPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    final value = path?.trim();
    if (value == null || value.isEmpty) {
      await prefs.remove(_customKeychainPathKey);
    } else {
      await prefs.setString(_customKeychainPathKey, value);
    }
  }
}

/// Initial mode selected before the first frame. Settings mutate this value and
/// ask for a restart so every config service is rebuilt consistently.
final credentialStorageModeProvider = StateProvider<CredentialStorageMode>(
  (ref) => CredentialStorageMode.systemKeychain,
);

/// True when the native encrypted-file vault must be unlocked before the app
/// can read or write credentials.
final credentialVaultRequiredProvider = StateProvider<bool>((ref) => false);
