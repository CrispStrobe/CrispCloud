import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/async_lock.dart';

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
  const CredentialStorageSelection({
    this.mode,
    this.customKeychainPath,
    this.createFileVault = false,
  });

  final CredentialStorageMode? mode;
  final String? customKeychainPath;

  /// One pending creation attempt, authorized by fresh-profile setup or an
  /// authenticated settings change. Absence of a vault never grants this.
  final bool createFileVault;
}

class CredentialStorageConfig {
  static const _modeKey = 'credential_storage_mode_v1';
  static const _customKeychainPathKey = 'custom_keychain_path';
  // Keep the existing preference key so v2 installations cannot accidentally
  // fall back to stale legacy mode/path preferences after an upgrade.
  static const selectionKey = 'credential_storage_selection_v2';
  static final _operations = AsyncLock();

  /// Read mode and path from one preference snapshot. A malformed explicit
  /// selection must never silently redirect credentials to the default store.
  static Future<CredentialStorageSelection> readSelection() =>
      _operations.synchronized(_readSelection);

  static Future<CredentialStorageSelection> _readSelection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return _selectionFromPreferences(prefs);
  }

  static CredentialStorageSelection _selectionFromPreferences(
    SharedPreferences prefs,
  ) {
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
    final dynamic value;
    try {
      value = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Invalid credential-storage selection.');
    }
    if (value is! Map<String, dynamic> ||
        value['version'] is! int ||
        (value['version'] != 2 && value['version'] != 3) ||
        (value['version'] == 2 && value.length != 3) ||
        (value['version'] == 3 &&
            (value.length != 4 || value['createFileVault'] is! bool)) ||
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
    final mode = _parseMode(value['mode'] as String?);
    final createFileVault =
        value['version'] == 3 && value['createFileVault'] == true;
    if (createFileVault && mode != CredentialStorageMode.encryptedFile) {
      throw const FormatException('Invalid credential-vault creation intent.');
    }
    return CredentialStorageSelection(
      mode: mode,
      customKeychainPath: normalizedPath,
      createFileVault: createFileVault,
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

  static Future<bool> readFileVaultCreationAllowed() async =>
      (await readSelection()).createFileVault;

  /// Store a confirmed choice as one verified write. Separate mode/path writes
  /// could redirect an existing custom-keychain profile after a partial failure.
  static Future<void> writeSelection({
    required CredentialStorageMode mode,
    String? customKeychainPath,
    bool createFileVault = false,
  }) => _operations.synchronized(
    () => _writeSelection(
      CredentialStorageSelection(
        mode: mode,
        customKeychainPath: _normalizePath(customKeychainPath),
        createFileVault: createFileVault,
      ),
    ),
  );

  static Future<void> writeMode(CredentialStorageMode mode) =>
      _operations.synchronized(() async {
        final previous = await _readSelection();
        await _writeSelection(
          CredentialStorageSelection(
            mode: mode,
            customKeychainPath: previous.customKeychainPath,
            createFileVault: previous.mode == mode && previous.createFileVault,
          ),
        );
      });

  /// macOS-only. Empty/null means the system default keychain.
  static Future<String?> readCustomKeychainPath() async =>
      (await readSelection()).customKeychainPath;

  static Future<void> writeCustomKeychainPath(String? path) =>
      _operations.synchronized(() async {
        final previous = await _readSelection();
        await _writeSelection(
          CredentialStorageSelection(
            mode: previous.mode,
            customKeychainPath: _normalizePath(path),
            createFileVault: previous.createFileVault,
          ),
        );
      });

  /// Consume before invoking a new-vault creator, never after it. A failed or
  /// indeterminate consumption must not create a vault; a failed creation must
  /// not restore this permission. An interrupted attempt can therefore require
  /// restoring the original vault or returning to an authenticated old store.
  ///
  /// An already consumed snapshot is deliberately rejected: a stale startup
  /// must not recreate a later-deleted vault and discard its App Lock policy.
  /// The lock serializes this isolate's read/modify/write operations. Neither
  /// SharedPreferences nor this API supplies cross-process compare-and-swap.
  static Future<void> consumeFileVaultCreation({
    required CredentialStorageSelection expected,
  }) => _operations.synchronized(() async {
    final current = await _readSelection();
    if (!expected.createFileVault ||
        expected.mode != CredentialStorageMode.encryptedFile ||
        current.mode != expected.mode ||
        current.customKeychainPath != expected.customKeychainPath ||
        current.createFileVault != expected.createFileVault) {
      throw StateError('Credential-vault creation is no longer authorized.');
    }
    await _writeSelection(
      CredentialStorageSelection(
        mode: current.mode,
        customKeychainPath: current.customKeychainPath,
      ),
    );
  });

  /// Browser-only first-profile evidence, captured before startup writes any
  /// identity, settings, or cache. Existing or ambiguous profiles never gain
  /// permission merely because their vault metadata disappeared. A previously
  /// authorized pending v3 intent remains readable across interrupted startup.
  /// Browser storage is not a transaction spanning separate tabs.
  static Future<CredentialStorageSelection> captureWebVaultCreation({
    required Future<List<String>> Function() readVaultKeys,
  }) => _operations.synchronized(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final previous = _selectionFromPreferences(prefs);
    if (prefs.getKeys().isNotEmpty) return previous;
    final vaultKeys = await readVaultKeys();
    // Re-read after the asynchronous evidence check. Do not overwrite a
    // selection or other profile data that appeared while it was running.
    await prefs.reload();
    if (prefs.getKeys().isNotEmpty) return _selectionFromPreferences(prefs);
    if (vaultKeys.isNotEmpty) return previous;
    const authorized = CredentialStorageSelection(
      mode: CredentialStorageMode.encryptedFile,
      createFileVault: true,
    );
    await _writeSelection(authorized);
    return authorized;
  });

  static String? _normalizePath(String? path) {
    final value = path?.trim();
    if (value != null && value.contains('\u0000')) {
      throw const FormatException('Invalid custom keychain path.');
    }
    return value == null || value.isEmpty ? null : value;
  }

  static Future<void> _writeSelection(
    CredentialStorageSelection selection,
  ) async {
    if (selection.createFileVault &&
        selection.mode != CredentialStorageMode.encryptedFile) {
      throw const FormatException('Invalid credential-vault creation intent.');
    }
    final prefs = await SharedPreferences.getInstance();
    await _writeVerified(
      prefs,
      selectionKey,
      jsonEncode({
        'version': 3,
        'mode': selection.mode?.name,
        'customKeychainPath': selection.customKeychainPath,
        'createFileVault': selection.createFileVault,
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
final credentialStorageKeychainRestartRequiredProvider = StateProvider<bool>(
  (ref) => false,
);

/// True when the native encrypted-file vault must be unlocked before the app
/// can read or write credentials.
final credentialVaultRequiredProvider = StateProvider<bool>((ref) => false);
