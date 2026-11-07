import 'dart:convert';

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
class CredentialStorageSelection {
  const CredentialStorageSelection({this.mode, this.customKeychainPath});

  final CredentialStorageMode? mode;
  final String? customKeychainPath;
}

class CredentialStorageConfig {
  static const _modeKey = 'credential_storage_mode_v1';
  static const _customKeychainPathKey = 'custom_keychain_path';
  static const selectionKey = 'credential_storage_selection_v2';

  /// Read mode and path from one preference snapshot. A malformed explicit
  /// selection must never silently redirect credentials to the default store.
  static Future<CredentialStorageSelection> readSelection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.containsKey(selectionKey)) {
      final raw = prefs.get(selectionKey);
      if (raw is! String) {
        throw const FormatException('Invalid credential-storage selection.');
      }
      return decodeSelection(raw);
    }
    final rawMode = prefs.get(_modeKey);
    final rawPath = prefs.get(_customKeychainPathKey);
    if ((rawMode != null && rawMode is! String) ||
        (rawPath != null && rawPath is! String)) {
      throw const FormatException('Invalid credential-storage settings.');
    }
    return CredentialStorageSelection(
      mode: _parseMode(rawMode as String?),
      customKeychainPath: _normalizePath(rawPath as String?),
    );
  }

  /// Used by the interrupted-first-setup guard as well as normal startup.
  static CredentialStorageSelection decodeSelection(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value.length != 3 ||
        value['version'] is! int ||
        value['version'] != 2 ||
        !value.containsKey('mode') ||
        !value.containsKey('customKeychainPath') ||
        (value['mode'] != null && value['mode'] is! String) ||
        (value['customKeychainPath'] != null &&
            value['customKeychainPath'] is! String)) {
      throw const FormatException('Invalid credential-storage selection.');
    }
    final path = value['customKeychainPath'] as String?;
    final normalizedPath = _normalizePath(path);
    if (path != normalizedPath) {
      throw const FormatException('Invalid custom keychain path.');
    }
    return CredentialStorageSelection(
      mode: _parseMode(value['mode'] as String?),
      customKeychainPath: normalizedPath,
    );
  }

  static CredentialStorageMode? _parseMode(String? raw) {
    if (raw == null) return null;
    for (final mode in CredentialStorageMode.values) {
      if (mode.name == raw) return mode;
    }
    throw const FormatException('Unknown credential-storage mode.');
  }

  static Future<CredentialStorageMode?> readModeIfConfigured() async =>
      (await readSelection()).mode;

  static Future<CredentialStorageMode> readMode() async =>
      await readModeIfConfigured() ?? CredentialStorageMode.systemKeychain;

  /// Store a confirmed choice as one verified write. Separate mode/path writes
  /// could redirect an existing custom-keychain profile after a partial failure.
  static Future<void> writeSelection({
    required CredentialStorageMode mode,
    String? customKeychainPath,
  }) => _writeSelection(CredentialStorageSelection(
    mode: mode,
    customKeychainPath: _normalizePath(customKeychainPath),
  ));

  static Future<void> writeMode(CredentialStorageMode mode) async {
    final previous = await readSelection();
    await writeSelection(mode: mode, customKeychainPath: previous.customKeychainPath);
  }

  /// macOS-only. Empty/null means the system default keychain.
  static Future<String?> readCustomKeychainPath() async =>
      (await readSelection()).customKeychainPath;

  static Future<void> writeCustomKeychainPath(String? path) async {
    final previous = await readSelection();
    await _writeSelection(CredentialStorageSelection(
      mode: previous.mode,
      customKeychainPath: _normalizePath(path),
    ));
  }

  static String? _normalizePath(String? path) {
    final value = path?.trim();
    if (value != null && value.contains('\u0000')) {
      throw const FormatException('Invalid custom keychain path.');
    }
    return value == null || value.isEmpty ? null : value;
  }

  static Future<void> _writeSelection(CredentialStorageSelection selection) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeVerified(
      prefs,
      selectionKey,
      jsonEncode({
        'version': 2,
        'mode': selection.mode?.name,
        'customKeychainPath': selection.customKeychainPath,
      }),
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
